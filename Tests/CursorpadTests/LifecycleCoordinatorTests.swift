import Foundation
import Testing

@testable import Cursorpad

// MARK: - Test doubles

/// Records cancellation + ordering observations for coordinator tests without leaving the actor.
private actor LifecycleProbe {
    private(set) var cancellations = 0
    private(set) var transcript: [String] = []
    private var failingStepNames: Set<String> = []
    private var repaired = false

    func recordCancellation() { cancellations += 1 }
    func append(_ entry: String) { transcript.append(entry) }
    func failOnce(_ name: String) { failingStepNames.insert(name) }
    func repair() { repaired = true }

    func shouldFail(_ name: String) -> Bool {
        if repaired { return false }
        return failingStepNames.contains(name)
    }
}

// MARK: - Termination test seams

/// Records that a cancelled operation actually stopped.
private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flagged = false

    func set() { lock.withLock { flagged = true } }
    var isSet: Bool { lock.withLock { flagged } }
}

/// Records when the production watchdog was armed and when it really fired.
///
/// Both instants are read where the watchdog runs (off the main actor), so a busy main actor
/// cannot inflate the measurement that proves the locked two-second budget.
private final class WatchdogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var armings: [ContinuousClock.Instant] = []
    private var firings: [ContinuousClock.Instant] = []

    func record(armedAt: ContinuousClock.Instant, firedAt: ContinuousClock.Instant) {
        lock.withLock {
            armings.append(armedAt)
            firings.append(firedAt)
        }
    }

    /// Number of real firings. A watchdog that was cancelled by the winning operation never fires.
    var count: Int { lock.withLock { firings.count } }

    /// How long the watchdog that fired had been waiting — the budget it actually honoured.
    var waited: Duration? {
        lock.withLock {
            guard let armedAt = armings.first, let firedAt = firings.first else { return nil }
            return firedAt - armedAt
        }
    }
}

/// Cancellation-aware controllable deadline for the bounded termination checks.
///
/// Every suite of this package runs in parallel, and unrelated AppKit work can keep the main actor
/// busy for hundreds of milliseconds. A bounded operation must therefore never be verified as a
/// wall-clock race against that queue: the tests arm the watchdog through this gate, assert the
/// exact budget the coordinator requested, and decide themselves whether the deadline expires
/// (`fire()`) or the operation settles first (the armed task is cancelled).
///
/// Each arming waits independently — a cancellation resolves only the waiter it cancelled — so
/// both bounded phases of `terminate` (flush, then close) are each decided by their own operation
/// rather than by the host's main-actor latency. The production two-second watchdog is verified
/// separately by `terminationIsBounded`, which runs the real timer.
private final class DeadlineGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingWaiter: CheckedContinuation<Void, Never>?
    private var firesAwaitingArming = 0
    private var cancellationAwaitingArming = false
    private var armedDurations: [Duration] = []
    private var fires = 0
    private var cancellations = 0

    /// Records the budget the coordinator armed the watchdog with.
    func arm(_ duration: Duration) { lock.withLock { armedDurations.append(duration) } }

    /// Suspends until the test fires the deadline or the armed task is cancelled.
    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeImmediately: Bool = lock.withLock {
                    if cancellationAwaitingArming {
                        cancellationAwaitingArming = false
                        cancellations += 1
                        return true
                    }
                    if firesAwaitingArming > 0 {
                        firesAwaitingArming -= 1
                        fires += 1
                        return true
                    }
                    pendingWaiter = continuation
                    return false
                }
                if resumeImmediately { continuation.resume() }
            }
        } onCancel: {
            resolveCancellation()
        }
    }

    /// The test decides the deadline elapsed.
    func fire() {
        let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
            guard let pendingWaiter else {
                firesAwaitingArming += 1
                return nil
            }
            self.pendingWaiter = nil
            fires += 1
            return pendingWaiter
        }
        waiter?.resume()
    }

    private func resolveCancellation() {
        let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
            guard let pendingWaiter else {
                // Cancelled before the arming suspended: the waiter consumes it on entry.
                cancellationAwaitingArming = true
                return nil
            }
            self.pendingWaiter = nil
            cancellations += 1
            return pendingWaiter
        }
        waiter?.resume()
    }

    var armed: [Duration] { lock.withLock { armedDurations } }
    var firedCount: Int { lock.withLock { fires } }
    var cancelledCount: Int { lock.withLock { cancellations } }
}

@Suite("LifecycleCoordinatorTests")
struct LifecycleCoordinatorTests {
    // MARK: - Launch (CON-LIFECYCLE-APPLICATION-LAUNCH)

    @Test("launch runs registered steps in order and reports success")
    @MainActor
    func launchRunsStepsInOrder() async throws {
        let probe = LifecycleProbe()
        let coordinator = LifecycleCoordinator()
        coordinator.addLaunchStep(name: "first") { await probe.append("first") }
        coordinator.addLaunchStep(name: "second") { await probe.append("second") }
        coordinator.addLaunchStep(name: "third") { await probe.append("third") }

        let state = await coordinator.launch()
        #expect(state == .succeeded)
        #expect(coordinator.state == .succeeded)
        #expect(coordinator.completedStepNames == ["first", "second", "third"])
        #expect(await probe.transcript == ["first", "second", "third"])
    }

    @Test("a failing step rolls back completed steps in reverse and never reports completion")
    @MainActor
    func failingStepRollsBackInReverse() async throws {
        let probe = LifecycleProbe()
        let coordinator = LifecycleCoordinator()
        coordinator.addLaunchStep(
            name: "storage",
            rollback: { await probe.append("rollback:storage") }
        ) { await probe.append("storage") }
        coordinator.addLaunchStep(
            name: "library",
            rollback: { await probe.append("rollback:library") }
        ) { await probe.append("library") }
        coordinator.addLaunchStep(
            name: "broken",
            rollback: { await probe.append("rollback:broken") }
        ) { throw LifecycleTestError.refused }

        let state = await coordinator.launch()
        guard case .failed(let message) = state else {
            Issue.record("expected failed, got \(state)")
            return
        }
        #expect(message.contains("refused"))
        #expect(coordinator.completedStepNames == ["storage", "library"])
        // Only the completed steps roll back, newest first, and the failed step never reports done.
        #expect(await probe.transcript == ["storage", "library", "rollback:library", "rollback:storage"])
        #expect(coordinator.state != .succeeded)
    }

    @Test("a failing rollback is reported and still preserves derived state")
    @MainActor
    func rollbackFailuresAreReported() async throws {
        let coordinator = LifecycleCoordinator()
        coordinator.addLaunchStep(name: "storage", rollback: { throw LifecycleTestError.refused }) { }
        coordinator.addLaunchStep(name: "library") { throw LifecycleTestError.refused }

        let state = await coordinator.launch()
        #expect(state != .succeeded)
        #expect(coordinator.rollbackFailureDescriptions.count == 1)
        #expect(coordinator.rollbackFailureDescriptions.first?.contains("storage") == true)
    }

    @Test("cancellation is reported as cancelled, not as success or failure")
    @MainActor
    func cancelledLaunchIsReportedAsCancelled() async throws {
        let coordinator = LifecycleCoordinator()
        coordinator.addLaunchStep(name: "storage") { }
        coordinator.addLaunchStep(name: "cancelled") { throw CancellationError() }

        let state = await coordinator.launch()
        #expect(state == .cancelled)
        #expect(coordinator.state == .cancelled)
    }

    @Test("an explicit retry after failure re-runs the launch steps")
    @MainActor
    func retryAfterFailureRunsAgain() async throws {
        let probe = LifecycleProbe()
        await probe.failOnce("library")
        let coordinator = LifecycleCoordinator()
        coordinator.addLaunchStep(name: "storage") { await probe.append("storage") }
        coordinator.addLaunchStep(name: "library") {
            if await probe.shouldFail("library") { throw LifecycleTestError.refused }
            await probe.append("library")
        }

        #expect(await coordinator.launch() != .succeeded)
        // The user repairs the problem and retries explicitly.
        await probe.repair()
        #expect(await coordinator.launch() == .succeeded)
        #expect(coordinator.completedStepNames == ["storage", "library"])
    }

    // MARK: - Termination (CON-LIFECYCLE-APPLICATION-TERMINATION)

    @Test("termination cancels owned tasks, flushes, closes and reports completion")
    @MainActor
    func terminationCancelsOwnedTasksAndFlushes() async throws {
        let probe = LifecycleProbe()
        let coordinator = LifecycleCoordinator()
        let gate = DeadlineGate()
        coordinator.deadlineTimer = { duration in
            gate.arm(duration)
            await gate.wait()
        }
        let ownedTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                await probe.recordCancellation()
            }
        }
        coordinator.registerOwnedTask(ownedTask)
        #expect(coordinator.ownedTaskCount == 1)

        var closeRan = false
        let outcome = await coordinator.terminate(
            flush: { await probe.append("flush") },
            close: {
                closeRan = true
                await probe.append("close")
            }
        )

        #expect(outcome == .completed)
        #expect(coordinator.state == .succeeded)
        #expect(closeRan)
        #expect(await probe.transcript == ["flush", "close"])
        #expect(await probe.cancellations == 1, "termination must cancel owned tasks")
        #expect(gate.armed.count >= 1)
        #expect(gate.armed.allSatisfy { $0 == LifecycleCoordinator.defaultTerminationDeadline },
                "every bounded phase must be armed with the locked two-second budget")
        #expect(gate.firedCount == 0, "the deadline never expired: the flush and the close both settled")
        #expect(gate.cancelledCount >= 1, "the watchdog ends as soon as the operation wins")
    }

    @Test("the normal-quit path is bounded to two seconds and still closes storage")
    @MainActor
    func terminationIsBounded() async throws {
        let coordinator = LifecycleCoordinator()
        #expect(coordinator.terminationDeadline == .seconds(2), "the locked budget must not change")

        let clock = ContinuousClock()
        let watchdog = WatchdogRecorder()
        let flushCancelled = CancellationFlag()
        let releaseGate = DeadlineGate()
        // Captured on the main actor: the deadline seam itself runs outside of it.
        let flushBudget = LifecycleCoordinator.defaultTerminationDeadline
        let productionWatchdog = LifecycleCoordinator.realDeadlineTimer
        coordinator.deadlineTimer = { duration in
            if duration == flushBudget {
                // The locked flush budget runs the production watchdog, wrapping it so the instant
                // it really fires is observable. `realDeadlineTimer` also returns when the bounded
                // race is cancelled; only a true elapse is a firing.
                let armedAt = clock.now
                await productionWatchdog(duration)
                guard !Task.isCancelled else { return }
                watchdog.record(armedAt: armedAt, firedAt: clock.now)
            } else {
                // The short storage-release grace after a timed-out flush is decided by the close
                // itself, so this check measures the flush bound instead of host scheduling.
                releaseGate.arm(duration)
                await releaseGate.wait()
            }
        }

        var closeRan = false
        let started = clock.now
        let outcome = await coordinator.terminate(
            flush: {
                // A flush that outlives the deadline: cancelled by the bound, so it must end.
                do { try await Task.sleep(for: .seconds(30)) } catch { flushCancelled.set() }
            },
            close: { closeRan = true }
        )
        let elapsed = clock.now - started

        #expect(outcome == .timedOut(LifecycleCoordinator.defaultTerminationDeadline))
        #expect(coordinator.state != .succeeded, "an interrupted transition must never report completion")
        #expect(closeRan, "storage must still be released on the bounded path")
        #expect(flushCancelled.isSet, "the hung flush must be cancelled by the bound")
        #expect(elapsed >= .seconds(1.8), "termination returned before the deadline")
        #expect(releaseGate.armed == [.milliseconds(250)],
                "a timed-out flush leaves only the short documented release grace")

        // The real watchdog must fire at the locked deadline even though the flush never finishes.
        // It is measured where it runs (off the main actor), so a busy main actor cannot inflate
        // the measurement that proves the two-second budget.
        #expect(watchdog.count == 1, "exactly one watchdog")
        let waited = try #require(watchdog.waited)
        #expect(waited >= .seconds(1.9), "the watchdog fired after only \(waited)")
        #expect(waited < .seconds(2.5), "the watchdog fired \(waited) after it was armed")
    }

    @Test("a failing close is reported honestly instead of claiming completion")
    @MainActor
    func closeFailureIsReported() async throws {
        let coordinator = LifecycleCoordinator()
        let gate = DeadlineGate()
        coordinator.deadlineTimer = { duration in
            gate.arm(duration)
            await gate.wait()
        }
        let outcome = await coordinator.terminate(
            flush: { },
            close: { throw LifecycleTestError.refused }
        )
        guard case .failed(let message) = outcome else {
            Issue.record("expected failed, got \(outcome)")
            return
        }
        #expect(message.contains("refused"))
        #expect(coordinator.state != .succeeded)
    }

    @Test("repeated termination calls are idempotent")
    @MainActor
    func terminationIsIdempotent() async throws {
        let probe = LifecycleProbe()
        let coordinator = LifecycleCoordinator()
        let gate = DeadlineGate()
        coordinator.deadlineTimer = { duration in
            gate.arm(duration)
            await gate.wait()
        }
        let first = await coordinator.terminate(flush: { await probe.append("flush") }, close: { })
        let armingsAfterFirstCall = gate.armed.count
        let second = await coordinator.terminate(flush: { await probe.append("flush-again") }, close: { })
        #expect(first == .completed)
        #expect(second == .completed)
        #expect(await probe.transcript == ["flush"], "the second call must not re-run the flush")
        #expect(gate.armed.count == armingsAfterFirstCall, "the second call must not re-arm the watchdog")
        #expect(gate.armed.allSatisfy { $0 == LifecycleCoordinator.defaultTerminationDeadline },
                "the watchdog is only ever armed with the locked budget")
    }

    // MARK: - AppState composition (CON-LIFECYCLE-PRESET)

    @Test("start() drives the launch through the coordinator and reports success")
    @MainActor
    func appStateLaunchUsesCoordinator() async throws {
        let root = try TestEnvironment.makeTempDirectory("lifecycle-appstate")
        let state = AppState(services: TestEnvironment.makeServices(root: root))

        await state.start()
        #expect(state.lifecycle.state == .succeeded)
        #expect(state.lifecycle.completedStepNames.first == "open-storage")
        #expect(state.lifecycle.completedStepNames.contains("reconcile-library"))
        #expect(state.lifecycle.completedStepNames.last == "restore-selection")
        #expect(state.libraryStatus == .ready)
        #expect(state.dataStore != nil)
        let gate = DeadlineGate()
        state.lifecycle.deadlineTimer = { duration in
            gate.arm(duration)
            await gate.wait()
        }
        await state.flushForTermination()
        #expect(state.lifecycle.lastTerminationOutcome == .completed)
        #expect(gate.firedCount == 0, "a clean flush and close never trip the watchdog")
    }

    @Test("a blocked launch rolls back partial state and the explicit retry recovers")
    @MainActor
    func appStateLaunchRollsBackOnFailure() async throws {
        let root = try TestEnvironment.makeTempDirectory("lifecycle-rollback")
        let blockedRoot = root.appendingPathComponent("blocked-root")
        try Data("this is a file, not a directory".utf8).write(to: blockedRoot)

        let state = AppState(services: TestEnvironment.makeServices(root: blockedRoot))
        await state.start()
        guard case .failed = state.lifecycle.state else {
            Issue.record("expected a failed launch, got \(state.lifecycle.state)")
            return
        }
        #expect(state.dataStore == nil, "partial launch state must be rolled back")
        #expect(state.notes.isEmpty)

        try FileManager.default.removeItem(at: blockedRoot)
        await state.retryStorageStartup()
        #expect(state.lifecycle.state == .succeeded)
        #expect(state.libraryStatus == .ready)
        let gate = DeadlineGate()
        state.lifecycle.deadlineTimer = { duration in
            gate.arm(duration)
            await gate.wait()
        }
        await state.flushForTermination()
        #expect(state.lifecycle.lastTerminationOutcome == .completed)
        #expect(gate.firedCount == 0, "a clean flush and close never trip the watchdog")
    }

    @Test("termination flushes pending work, closes storage and reports the duration")
    @MainActor
    func appStateTerminationClosesStorage() async throws {
        let root = try TestEnvironment.makeTempDirectory("lifecycle-terminate")
        let state = AppState(services: TestEnvironment.makeServices(root: root))
        await state.start()
        state.newNote()
        await state.waitForPendingOperations()
        #expect(state.notes.count == 1)

        // The watchdog is armed through the deterministic gate: the flush and the close settle by
        // themselves, so the outcome measures the shutdown path rather than the host's queue.
        let gate = DeadlineGate()
        state.lifecycle.deadlineTimer = { duration in
            gate.arm(duration)
            await gate.wait()
        }
        await state.flushForTermination()
        #expect(state.dataStore == nil)
        #expect(state.lifecycle.lastTerminationOutcome == .completed)
        #expect(state.lifecycle.lastTerminationDuration != nil)
        #expect(gate.armed.allSatisfy { $0 == LifecycleCoordinator.defaultTerminationDeadline },
                "the shutdown path is armed with the locked two-second budget")
        #expect(gate.firedCount == 0, "the flush settles inside the locked budget; the deadline never expires")

        // Work requested after termination is refused instead of silently dropped.
        state.newNote()
        await state.waitForPendingOperations()
        #expect(state.statusMessage?.contains("shutting down") == true)
    }
}

enum LifecycleTestError: Error, LocalizedError {
    case refused

    var errorDescription: String? { "refused" }
}
