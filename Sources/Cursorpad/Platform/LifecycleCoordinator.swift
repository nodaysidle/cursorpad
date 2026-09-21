import Foundation

// MARK: - CON-LIFECYCLE-APPLICATION-LAUNCH / CON-LIFECYCLE-APPLICATION-TERMINATION / CON-LIFECYCLE-PRESET

/// Explicit lifecycle states. Every transition reports exactly one of these, and an interrupted
/// transition is never reported as `succeeded`.
enum LifecycleState: Equatable, Sendable {
    case idle
    case active
    case succeeded
    case failed(String)
    case cancelled
}

/// Outcome of a bounded lifecycle operation (the normal-quit path).
enum LifecycleOutcome: Equatable, Sendable {
    case completed
    case timedOut(Duration)
    case failed(String)
}

/// Owns launch sequencing with rollback, owned-task cancellation and the bounded termination path.
///
/// Contracts implemented here:
/// - CON-LIFECYCLE-APPLICATION-LAUNCH: steps run in registered order; a failure rolls back the
///   steps that already completed (reverse order) and keeps a safe, explicit retry path.
/// - CON-LIFECYCLE-APPLICATION-TERMINATION: stop new work, cancel owned tasks, flush, release the
///   storage handle; the flush is bounded so normal quit can never hang.
/// - CON-LIFECYCLE-PRESET: the coordinator never starts privileged capture, remote requests or
///   destructive work; it only sequences what the composition root registers.
@MainActor
final class LifecycleCoordinator {
    /// A launch step read its dependencies from the composition root; `run` performs it and
    /// `rollback` (optional) undoes whatever `run` managed to commit.
    typealias Operation = @MainActor () async throws -> Void

    struct LaunchStep {
        let name: String
        let run: Operation
        let rollback: Operation?
    }

    /// Two-second bounded normal-quit path (locked functional requirement).
    static let defaultTerminationDeadline: Duration = .seconds(2)

    /// Deadline seam: `terminate` arms the watchdog through this clock.
    ///
    /// Production runs `realDeadlineTimer`, so the flush is bounded by the locked two-second budget
    /// even when the main actor is busy. The seam exists so focused tests can arm the watchdog
    /// deterministically (and assert the exact budget it was armed with) instead of making the
    /// nominal completion path a wall-clock race against the host's main-actor queue latency.
    typealias DeadlineTimer = @Sendable (Duration) async -> Void

    /// Production watchdog: the deadline elapses on the real clock. Cancellation means the flush
    /// settled first, so the watchdog simply ends without producing a result.
    static let realDeadlineTimer: DeadlineTimer = { duration in
        do {
            try await Task.sleep(for: duration)
        } catch {
            // Cancelled: the bounded race is already decided by the other side.
        }
    }

    let terminationDeadline: Duration

    /// Test seam. Production always runs `LifecycleCoordinator.realDeadlineTimer`.
    var deadlineTimer: DeadlineTimer = LifecycleCoordinator.realDeadlineTimer

    private(set) var state: LifecycleState = .idle
    private(set) var completedStepNames: [String] = []
    private(set) var rollbackFailureDescriptions: [String] = []
    private(set) var lastTerminationOutcome: LifecycleOutcome?
    private(set) var lastTerminationDuration: Duration?
    /// True from the first `terminate(...)` call onwards; used by the composition root to refuse
    /// new work instead of dropping it silently.
    private(set) var isTerminating = false

    private var steps: [LaunchStep] = []
    private var ownedTasks: [Task<Void, Never>] = []

    init(terminationDeadline: Duration = LifecycleCoordinator.defaultTerminationDeadline) {
        self.terminationDeadline = terminationDeadline
    }

    var hasLaunchSteps: Bool { !steps.isEmpty }

    var ownedTaskCount: Int { ownedTasks.count }

    // MARK: - Registration

    func addLaunchStep(name: String, rollback: Operation? = nil, run: @escaping Operation) {
        steps.append(LaunchStep(name: name, run: run, rollback: rollback))
    }

    func registerOwnedTask(_ task: Task<Void, Never>) {
        ownedTasks.append(task)
    }

    /// Replaces the tracked owned-task list with the composition root's current truth, so completed
    /// commands are not retained for the lifetime of the process.
    func trackOwnedTasks(_ tasks: [Task<Void, Never>]) {
        ownedTasks = tasks
    }

    // MARK: - Launch

    /// Runs every registered launch step in order.
    ///
    /// - A throwing step rolls back the steps that already completed, in reverse order, and reports
    ///   `failed`. Rollback failures are recorded and reported, never hidden.
    /// - Cancellation reports `cancelled`.
    /// - `launch()` is allowed again after `failed`/`cancelled` (explicit user retry) but is a
    ///   no-op while `active`.
    @discardableResult
    func launch() async -> LifecycleState {
        guard state != .active else { return state }
        state = .active
        completedStepNames = []
        rollbackFailureDescriptions = []
        var completedIndices: [Int] = []

        for (index, step) in steps.enumerated() {
            if Task.isCancelled {
                await rollback(completedIndices)
                state = .cancelled
                return state
            }
            do {
                try await step.run()
                completedIndices.append(index)
                completedStepNames.append(step.name)
            } catch is CancellationError {
                await rollback(completedIndices)
                state = .cancelled
                return state
            } catch {
                await rollback(completedIndices)
                state = .failed(Self.describe(error))
                return state
            }
        }

        state = .succeeded
        return state
    }

    private func rollback(_ indices: [Int]) async {
        for index in indices.reversed() {
            let step = steps[index]
            guard let rollback = step.rollback else { continue }
            do {
                try await rollback()
            } catch {
                rollbackFailureDescriptions.append("\(step.name): \(Self.describe(error))")
            }
        }
    }

    // MARK: - Cancellation

    /// Cancels every owned task. Active launch state moves to `cancelled`.
    func cancel() {
        cancelOwnedTasks()
        if state == .active {
            state = .cancelled
        }
    }

    func cancelOwnedTasks() {
        let tasks = ownedTasks
        ownedTasks = []
        for task in tasks {
            task.cancel()
        }
    }

    /// Returns to `idle` so an explicit user retry may launch again. Refused while `active`.
    func reset() {
        guard state != .active else { return }
        state = .idle
        completedStepNames = []
        rollbackFailureDescriptions = []
    }

    // MARK: - Termination

    /// Bounded normal-quit path: stop new work, cancel owned tasks, flush within the deadline and
    /// release the storage handle.
    ///
    /// The flush and close closures must be cancellation-aware; the coordinator cancels them when
    /// the deadline expires, so termination always returns and can never hang the process. An
    /// interrupted path reports `timedOut`/`failed` and never `completed`.
    @discardableResult
    func terminate(flush: @escaping Operation, close: @escaping Operation) async -> LifecycleOutcome {
        if let lastTerminationOutcome {
            return lastTerminationOutcome
        }
        isTerminating = true
        state = .active
        cancelOwnedTasks()

        let clock = ContinuousClock()
        let started = clock.now
        let flushResult = await runBounded(flush, deadline: terminationDeadline)
        lastTerminationDuration = clock.now - started

        // The handle is released even when the flush timed out, but with a short grace so a stuck
        // earlier phase cannot stall the quit path.
        let closeDeadline: Duration = flushResult == .finished ? terminationDeadline : .milliseconds(250)
        let closeResult = await runBounded(close, deadline: closeDeadline)

        let outcome: LifecycleOutcome
        switch closeResult {
        case .failed(let message):
            rollbackFailureDescriptions.append("termination close: \(message)")
            state = .failed("termination close failed — \(message)")
            outcome = .failed(message)
        case .timedOut:
            state = .failed("termination close exceeded its deadline")
            outcome = .failed("termination close timed out")
        case .finished:
            if flushResult == .finished {
                state = .succeeded
                outcome = .completed
            } else if case .failed(let message) = flushResult {
                state = .failed("termination flush failed — \(message)")
                outcome = .failed(message)
            } else {
                state = .failed("termination flush exceeded the \(terminationDeadline) deadline")
                outcome = .timedOut(terminationDeadline)
            }
        }
        lastTerminationOutcome = outcome
        return outcome
    }

    // MARK: - Bounded execution

    private enum BoundedResult: Equatable, Sendable {
        case finished
        case failed(String)
        case timedOut
    }

    /// Races `operation` against a deadline. Whichever settles first wins; the loser is cancelled.
    /// Both branches are structured tasks — no detached work, no unchecked sendability.
    private func runBounded(_ operation: @escaping Operation, deadline: Duration) async -> BoundedResult {
        let timer = deadlineTimer
        return await withTaskGroup(of: BoundedResult.self) { group in
            group.addTask {
                do {
                    try await operation()
                    return .finished
                } catch {
                    return .failed(LifecycleCoordinator.describe(error))
                }
            }
            group.addTask {
                await timer(deadline)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }

    // MARK: - Helpers

    nonisolated static func describe(_ error: Error) -> String {
        if let dataStoreError = error as? DataStore.DataStoreError {
            return dataStoreError.description
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "\(error)"
    }
}
