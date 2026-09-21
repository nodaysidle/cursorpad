import Foundation

// MARK: - CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-INTERFACE / CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY
//
// Autosave for note bodies. Edits are handed to this actor, coalesced, and — after 250 ms of
// typing cessation — written as UTF-8 bytes through an atomic temporary-file swap in the
// Application Support directory, off the main actor. Every committed body write is paired with the
// metadata stamp of the same instant, so the file's modification date and the recorded `updatedAt`
// describe one moment and launch reconciliation never mistakes the app's own write for a newer
// external edit.
//
// Failure keeps the user's text in memory (never truncated, never dropped), reports the failure
// honestly and exposes an explicit retry; nothing here retries on its own. Every terminal path —
// note switch, note deletion, normal quit — ends the debounce task instead of leaving it dangling,
// and the quit path flushes the pending text before the storage handle is released.

/// One pending body edit, keyed by the note it belongs to.
struct PendingBodyWrite: Equatable, Sendable {
    let noteID: String
    let fileName: String
    let text: String
    /// Editor edit sequence. A stale delivery never replaces newer text.
    let generation: Int
}

/// A committed autosave: the body file and the metadata row that carry the same instant.
struct AutosaveCommit: Equatable, Sendable {
    let noteID: String
    let fileName: String
    let stamp: Date
    let document: NoteDocument
}

/// Everything the composition root mirrors into presentation state.
enum AutosaveEvent: Equatable, Sendable {
    case scheduled(noteID: String, fileName: String)
    case committed(AutosaveCommit)
    case failed(noteID: String, fileName: String, message: String)
    case discarded(noteID: String)
}

actor NonBlockingAtomicDiskStorage {
    /// Locked debounce interval (REQ-NON-BLOCKING-ATOMIC-DISK-STORAGE).
    static let debounceInterval: Duration = .milliseconds(250)

    /// Locked acceptance bound: a committed write lands within 300 ms of typing cessation
    /// (ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-02).
    static let commitBudget: Duration = .milliseconds(300)

    /// Contract vocabulary: idle, active, succeeded, failed, cancelled.
    enum State: Equatable, Sendable {
        case idle
        case active
        case succeeded
        case failed(String)
        case cancelled
    }

    enum StorageError: Error, Equatable, CustomStringConvertible {
        case notOpen

        var description: String { "the note storage is not open yet" }
    }

    /// The disk boundary this feature drives: the atomic UTF-8 body write and the metadata stamp
    /// that records the same instant.
    ///
    /// Production runs `live(for:)`, so both calls execute on the datastore actor — never on the
    /// main actor. Focused checks replace the boundary to script failures and to record where the
    /// work really ran.
    struct Writer: Sendable {
        var writeBodyAtomically: @Sendable (_ fileName: String, _ text: String, _ stampedAt: Date) async throws -> Date
        var pairMetadata: @Sendable (_ noteID: String, _ text: String, _ stamp: Date) async throws -> NoteDocument

        static func live(for store: DataStore) -> Writer {
            Writer(
                writeBodyAtomically: { fileName, text, stampedAt in
                    try await store.writeBody(fileName: fileName, text: text, stampedAt: stampedAt)
                },
                pairMetadata: { noteID, text, stamp in
                    try await store.refreshMetadata(id: noteID, fromText: text, updatedAt: stamp)
                }
            )
        }

        /// Before a successful launch opens storage, every attempt fails honestly instead of
        /// writing nowhere.
        static var unavailable: Writer {
            Writer(
                writeBodyAtomically: { _, _, _ in throw StorageError.notOpen },
                pairMetadata: { _, _, _ in throw StorageError.notOpen }
            )
        }
    }

    // MARK: State

    private(set) var state: State = .idle
    /// Text waiting for its debounce (or for a flush).
    private(set) var pending: PendingBodyWrite?
    /// Text whose commit failed. Kept in memory until an explicit retry or a newer edit.
    private(set) var retained: PendingBodyWrite?
    private(set) var commitCount = 0
    private(set) var failureCount = 0
    private(set) var lastCommit: AutosaveCommit?
    /// Time from the last accepted edit to the completed commit of the last write — the quantity
    /// ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-02 bounds. Measured where the work runs.
    private(set) var lastCommitLatency: Duration?

    private var writer: Writer
    private let debounceInterval: Duration
    private var onEvent: @Sendable (AutosaveEvent) async -> Void
    private let clock = ContinuousClock()

    private var debounceTask: Task<Void, Never>?
    /// Identity of the task that currently occupies `debounceTask`.
    ///
    /// The timer releases this slot itself once its sleep has elapsed, so the commit it triggers never
    /// cancels the task that is running it — which would make a cancellation-aware writer fail
    /// spuriously on a healthy disk. A newer edit, an explicit flush and a discard still cancel a
    /// *waiting* timer.
    private var debounceToken = 0
    private var scheduledAt: ContinuousClock.Instant?
    private var settleWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        writer: Writer = .unavailable,
        debounceInterval: Duration = NonBlockingAtomicDiskStorage.debounceInterval,
        onEvent: @escaping @Sendable (AutosaveEvent) async -> Void = { _ in }
    ) {
        self.writer = writer
        self.debounceInterval = debounceInterval
        self.onEvent = onEvent
    }

    /// Attaches the storage boundary once the launch step opened the datastore.
    func attach(writer: Writer) {
        self.writer = writer
    }

    /// Attaches the storage boundary and the composition root that mirrors the events.
    func attach(writer: Writer, onEvent: @escaping @Sendable (AutosaveEvent) async -> Void) {
        self.writer = writer
        self.onEvent = onEvent
    }

    // MARK: - Edits (CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-INTERFACE)

    /// Accepts one editor edit. The debounce restarts on every call, so a burst of typing produces
    /// exactly one write — the text of the last edit, 250 ms after the user stops.
    func scheduleTextChange(noteID: String, fileName: String, text: String, generation: Int) async {
        if let pending, pending.noteID == noteID, generation <= pending.generation {
            // A stale delivery never replaces newer text.
            return
        }
        if let pending, pending.noteID != noteID {
            // The user moved on to another note before the debounce elapsed: commit what was typed
            // rather than lose it.
            await commit(pending)
        }
        retained = nil
        let write = PendingBodyWrite(noteID: noteID, fileName: fileName, text: text, generation: generation)
        pending = write
        scheduledAt = clock.now
        state = .active
        startDebounce(for: write)
        await onEvent(.scheduled(noteID: noteID, fileName: fileName))
    }

    /// Commits the pending edit now instead of waiting for the debounce (note switch, quit flush).
    /// A failed write is never retried here — retries are explicit user actions.
    func flush() async {
        if let pending {
            await commit(pending)
        }
    }

    /// Waits until the currently pending edit has reached a terminal state — committed, failed or
    /// discarded — without shortening its debounce.
    func settle() async {
        guard pending != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            settleWaiters.append(continuation)
        }
    }

    /// Explicit user retry of the retained text (CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY).
    /// Nothing calls this on its own.
    @discardableResult
    func retry() async -> State {
        guard let retained else { return state }
        await commit(retained)
        return state
    }

    /// Terminal path for text that must not reach disk any more: the note was deleted or the
    /// launch was rolled back. Cancels the debounce task and drops the text.
    func discard(noteID: String? = nil) async {
        var discardedID: String?
        if let pending, noteID == nil || pending.noteID == noteID {
            discardedID = pending.noteID
            self.pending = nil
            debounceTask?.cancel()
            debounceTask = nil
            scheduledAt = nil
        }
        if let retained, noteID == nil || retained.noteID == noteID {
            discardedID = retained.noteID
            self.retained = nil
        }
        guard let discardedID else { return }
        state = .cancelled
        resumeSettleWaiters()
        await onEvent(.discarded(noteID: discardedID))
    }

    // MARK: - Internals

    private func startDebounce(for write: PendingBodyWrite) {
        debounceTask?.cancel()
        let interval = debounceInterval
        let generation = write.generation
        debounceToken += 1
        let token = debounceToken
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                // Cancelled: the edit was superseded, flushed or discarded.
                return
            }
            await self?.debounceElapsed(generation: generation, token: token)
        }
    }

    private func debounceElapsed(generation: Int, token: Int) async {
        // The sleep is over, so this task is no longer a cancellable waiting timer: it releases its
        // own slot before committing, and an explicit flush or discard that arrives while the commit
        // runs finds nothing here to cancel instead of cancelling the commit's own task.
        if debounceToken == token {
            debounceTask = nil
        }
        guard let pending, pending.generation == generation else { return }
        await commit(pending)
    }

    /// Atomic body write first, then the metadata stamp of the same instant. A failure retains the
    /// text and reports it; nothing is retried automatically.
    private func commit(_ write: PendingBodyWrite) async {
        pending = nil
        debounceTask?.cancel()
        debounceTask = nil

        do {
            let stamp = try await writer.writeBodyAtomically(write.fileName, write.text, Date())
            let document = try await writer.pairMetadata(write.noteID, write.text, stamp)
            let commit = AutosaveCommit(
                noteID: write.noteID,
                fileName: write.fileName,
                stamp: stamp,
                document: document
            )
            if let scheduledAt { lastCommitLatency = clock.now - scheduledAt }
            scheduledAt = nil
            retained = nil
            commitCount += 1
            lastCommit = commit
            state = .succeeded
            resumeSettleWaiters()
            await onEvent(.committed(commit))
        } catch {
            let message = Self.describe(error)
            scheduledAt = nil
            retained = write
            failureCount += 1
            state = .failed(message)
            resumeSettleWaiters()
            await onEvent(.failed(noteID: write.noteID, fileName: write.fileName, message: message))
        }
    }

    private func resumeSettleWaiters() {
        let waiters = settleWaiters
        settleWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    static func describe(_ error: Error) -> String {
        if let storageError = error as? StorageError {
            return storageError.description
        }
        if let dataStoreError = error as? DataStore.DataStoreError {
            return dataStoreError.description
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "\(error)"
    }
}
