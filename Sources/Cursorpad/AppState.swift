import AppKit
import Observation
import SwiftUI

// MARK: - Locked identity

/// Locked product identity (CON-PACKAGING-RELEASE / locked foundation).
enum AppIdentity {
    static let bundleIdentifier = "com.cursorpad.app"
    static let displayName = "CursorPad"
    static let executableName = "Cursorpad"
    static let version = "1.0.0"
    static let build = "1"
    static let minimumSystemVersion = "14.0"
}

/// Locked on-disk layout: SQLite metadata + Markdown bodies inside Application Support.
enum AppStoragePaths {
    static let directoryName = "CursorPad"
    static let notesDirectoryName = "Notes"
    static let databaseName = "CursorPad.sqlite3"

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func notesDirectory(root: URL) -> URL {
        root.appendingPathComponent(notesDirectoryName, isDirectory: true)
    }

    static func databaseURL(root: URL) -> URL {
        root.appendingPathComponent(databaseName, isDirectory: false)
    }
}

/// Versioned UserDefaults keys for product-owned presentation state.
enum AppPreferenceKeys {
    static let lastSelection = "cursorpad.ui.lastSelection.v1"
    static let sidebarVisible = "cursorpad.ui.sidebarVisible.v1"
}

// MARK: - Presentation state

/// Single `@Observable @MainActor` composition root. Feature services are injected through
/// `Services`; every later phase evolves behavior inside this file only.
@Observable
@MainActor
final class AppState {
    /// Composition-root service description. PHASE-02+ attaches the data store, body writer,
    /// lifecycle coordinator and permission coordinator here.
    struct Services: Sendable {
        var storageRoot: URL
        /// `nil` uses `UserDefaults.standard`; tests pass an isolated suite and remove it afterwards.
        var userDefaultsSuiteName: String?
        var debounceInterval: Duration

        init(storageRoot: URL, userDefaultsSuiteName: String? = nil, debounceInterval: Duration = .milliseconds(250)) {
            self.storageRoot = storageRoot
            self.userDefaultsSuiteName = userDefaultsSuiteName
            self.debounceInterval = debounceInterval
        }

        /// Resolved on demand so `Services` stays `Sendable` (UserDefaults itself is not).
        var userDefaults: UserDefaults {
            if let suiteName = userDefaultsSuiteName, let defaults = UserDefaults(suiteName: suiteName) {
                return defaults
            }
            return .standard
        }

        static var live: Services {
            Services(storageRoot: AppStoragePaths.defaultRootURL())
        }
    }

    /// Library load state. Matches the recovery vocabulary: idle, active, succeeded, failed, cancelled.
    enum LibraryStatus: Equatable, Sendable {
        case idle
        case active
        case succeeded
        case failed(String)
        case cancelled

        var isReady: Bool { self == .succeeded }

        var canRetryStartup: Bool {
            switch self {
            case .failed, .cancelled:
                return true
            case .idle, .active, .succeeded:
                return false
            }
        }
    }

    /// Whether the open note still has keystrokes that have not reached disk.
    enum NotePersistenceStatus: Equatable, Sendable {
        case saved
        case unsaved
        case saving
    }

    /// Errors raised by the composition root itself (never by user-visible features).
    enum CompositionError: Error, LocalizedError {
        case detached

        var errorDescription: String? { "the composition root was released before the step completed" }
    }

    let services: Services
    /// Launch/termination sequencing (CON-LIFECYCLE-APPLICATION-LAUNCH,
    /// CON-LIFECYCLE-APPLICATION-TERMINATION, CON-LIFECYCLE-PRESET).
    let lifecycle = LifecycleCoordinator()
    /// Explicit user-selected external locations (CON-PERMISSION-FILESYSTEM).
    let permissions = PermissionCoordinator()
    /// Debounced, off-main atomic body writes (PHASE-08,
    /// CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-INTERFACE).
    let autosave: NonBlockingAtomicDiskStorage
    /// Status-bar indicator for a failed autosave. The text itself stays in the autosave's memory
    /// buffer until the user explicitly retries (CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY).
    private(set) var autosaveFailure: String?

    // MARK: Presentation state

    var isSidebarVisible = true
    private(set) var isCommandPalettePresented = false
    private(set) var editorFocusRequests = 0
    private(set) var statusMessage: String?

    // Command palette presentation mirrors (PHASE-04). The palette session owns the logic; these
    // mirror the parts the overlay renders.
    private(set) var paletteQuery = ""
    private(set) var paletteResults: [PaletteRankedNote] = []
    private(set) var paletteSelectedIndex = 0
    private(set) var paletteZeroResultMessage: String?
    private var paletteSession = CommandPaletteSession()

    private(set) var notes: [NoteDocument] = []
    var selectedNoteID: String?
    private(set) var libraryStatus: LibraryStatus = .idle
    private(set) var missingBodyNoteIDs: Set<String> = []
    /// Compact sidebar presentation rows (PHASE-07), newest first.
    private(set) var sidebarRows: [CompactSidebarRow] = []
    /// Explicit-delete bookkeeping: the row stays until the trash + metadata delete both succeed.
    private(set) var pendingDeletionNoteID: String?
    private(set) var pendingDeletionFailure: String?
    /// Trash boundary for explicit deletes. Production moves the body file to the macOS Trash.
    var trashService = BodyTrashService.live
    private(set) var editorText = ""
    private(set) var editorCharacterCount = 0
    private(set) var editorFontSource: EditorFontSource = .sfMono
    private(set) var editorFontNotice: String?
    private(set) var editorTypographyRetryRequests = 0
    private(set) var editorConfiguration: EditorConfiguration
    private(set) var notePersistenceStatus: NotePersistenceStatus = .saved
    /// Status text set while a font retry is in flight. Cleared when the editor reports the result.
    static let editorFontRecheckMessage = "Re-checking the editor font…"

    // MARK: Services and private state

    private(set) var dataStore: DataStore?
    private var loadedNoteID: String?
    private var selectionGeneration = 0
    private var pendingOperations: [Task<Void, Never>] = []
    /// Editor edit sequence and the autosave submissions that carry it, so the quit path and the
    /// focused checks can wait for every handed-over edit deterministically.
    private var editorEditGeneration = 0
    private var latestSubmittedGeneration = 0
    private var autosaveSubmissions: [Task<Void, Never>] = []
    private(set) var hasStarted = false
    private var terminationHookInstalled = false

    init(services: Services = .live) {
        self.services = services
        self.autosave = NonBlockingAtomicDiskStorage(debounceInterval: services.debounceInterval)
        self.editorConfiguration = EditorConfigurationStore(defaults: services.userDefaults).load()
    }

    // MARK: - Lifecycle

    /// Runs the launch sequence: open storage, reconcile the library, load notes, restore selection.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        restoreSidebarPreference()
        await launchStorage()
    }

    /// Explicit user retry after a failed launch (recovery contract: retries are user-initiated).
    func retryStorageStartup() async {
        guard libraryStatus.canRetryStartup else { return }
        statusMessage = "Retrying storage…"
        lifecycle.reset()
        await launchStorage()
    }

    private func launchStorage() async {
        libraryStatus = .active
        installLaunchStepsIfNeeded()
        switch await lifecycle.launch() {
        case .succeeded, .idle, .active:
            break
        case .failed(let description):
            libraryStatus = .failed(description)
            statusMessage = "Storage unavailable — \(description)"
        case .cancelled:
            libraryStatus = .cancelled
            statusMessage = "Storage unavailable — launch was cancelled."
        }
    }

    /// Registers the launch sequence exactly once. Each step commits one unit of work and carries
    /// the rollback for whatever it managed to commit (CON-LIFECYCLE-APPLICATION-LAUNCH).
    private func installLaunchStepsIfNeeded() {
        guard !lifecycle.hasLaunchSteps else { return }
        lifecycle.addLaunchStep(
            name: "open-storage",
            rollback: { [weak self] in await self?.rollbackOpenStorage() }
        ) { [weak self] in
            guard let self else { throw CompositionError.detached }
            let store = DataStore(paths: DataStore.Paths(rootURL: self.services.storageRoot))
            try await store.open()
            self.dataStore = store
            // The autosave boundary exists from launch: atomic body writes plus the metadata stamp
            // of the same instant, both owned by the datastore (PHASE-08).
            await self.autosave.attach(writer: .live(for: store)) { [weak self] event in
                guard let self else { return }
                await self.applyAutosaveEvent(event)
            }
        }
        lifecycle.addLaunchStep(
            name: "reconcile-library",
            rollback: { [weak self] in await self?.rollbackLibraryState() }
        ) { [weak self] in
            guard let self, let store = self.dataStore else { throw CompositionError.detached }
            let report = try await store.reconcile()
            let snapshot = try await store.librarySnapshot()
            self.notes = snapshot.notes
            self.missingBodyNoteIDs = Set(snapshot.missingBodyIDs)
            self.libraryStatus = .succeeded
            self.publishSidebarRows()
            self.statusMessage = Self.reconciliationSummary(report: report, snapshot: snapshot)
        }
        lifecycle.addLaunchStep(name: "restore-selection") { [weak self] in
            self?.restoreLastSelection()
        }
    }

    private func rollbackOpenStorage() async {
        // The launch did not complete: pending autosave text is dropped and the boundary is
        // detached so nothing can write into a store that is being closed.
        await autosave.discard()
        await autosave.attach(writer: .unavailable)
        if let dataStore {
            await dataStore.close()
        }
        dataStore = nil
    }

    private func rollbackLibraryState() async {
        notes = []
        missingBodyNoteIDs = []
        sidebarRows = []
        editorText = ""
        editorCharacterCount = 0
        loadedNoteID = nil
        libraryStatus = .idle
        statusMessage = nil
    }

    private static func reconciliationSummary(report: DataStore.ReconcileReport, snapshot: DataStore.LibrarySnapshot) -> String? {
        var fragments: [String] = []
        if !report.adopted.isEmpty {
            fragments.append("adopted \(report.adopted.count) note\(report.adopted.count == 1 ? "" : "s")")
        }
        if !report.refreshed.isEmpty {
            fragments.append("refreshed \(report.refreshed.count)")
        }
        if !report.markedMissing.isEmpty {
            fragments.append("\(report.markedMissing.count) body file\(report.markedMissing.count == 1 ? " is" : "s are") missing")
        }
        if snapshot.invalidRecordCount > 0 {
            fragments.append("\(snapshot.invalidRecordCount) damaged record\(snapshot.invalidRecordCount == 1 ? "" : "s") left untouched")
        }
        if !report.skippedInvalidFiles.isEmpty {
            fragments.append("\(report.skippedInvalidFiles.count) unreadable file\(report.skippedInvalidFiles.count == 1 ? "" : "s") skipped")
        }
        guard !fragments.isEmpty else { return nil }
        return "Library: " + fragments.joined(separator: ", ") + "."
    }

    /// Installs the async termination flush that `AppDelegate` invokes on quit. Called once the
    /// window appears; safe to call repeatedly.
    func attachTerminationHook() {
        guard !terminationHookInstalled else { return }
        terminationHookInstalled = true
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else { return }
        delegate.terminationFlushHandler = { [weak self] in
            await self?.flushForTermination()
        }
    }

    /// Flushes pending work before the process exits. Bounded to at most two seconds by
    /// `LifecycleCoordinator.terminate`, so termination can never hang; the method always returns.
    func flushForTermination() async {
        switch await lifecycle.terminate(
            flush: { [weak self] in await self?.flushBeforeTermination() },
            close: { [weak self] in await self?.closeStorage() }
        ) {
        case .completed:
            break
        case .timedOut:
            statusMessage = "Termination flush exceeded its time budget."
        case .failed(let message):
            statusMessage = "Termination was not clean — \(message)"
        }
    }

    /// Everything that must settle before the storage handle is released.
    private func flushBeforeTermination() async {
        cancelPendingOperations()
        await waitForPendingOperations()
        // The autosave's pending text reaches disk before the handle is closed, so a quit never
        // loses the last edits (CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-INTERFACE, quit flush).
        await flushAutosave()
        // CON-LIFECYCLE-APPLICATION-TERMINATION cleanup: permission scopes are released before the
        // storage handle is closed, so no external access outlives the process.
        permissions.releaseAllScopes()
    }

    private func cancelPendingOperations() {
        let operations = pendingOperations
        pendingOperations = []
        for operation in operations {
            operation.cancel()
        }
    }

    /// Tracks a command-triggered operation so termination and tests can await completion.
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let task = Task { @MainActor in
            guard !Task.isCancelled else { return }
            await operation()
        }
        pendingOperations.append(task)
        lifecycle.trackOwnedTasks(pendingOperations)
    }

    /// Awaits every enqueued operation, including ones spawned while waiting.
    func waitForPendingOperations() async {
        while !pendingOperations.isEmpty {
            let operations = pendingOperations
            pendingOperations = []
            for operation in operations {
                await operation.value
            }
        }
        lifecycle.trackOwnedTasks(pendingOperations)
    }

    private func closeStorage() async {
        guard let dataStore else { return }
        await dataStore.close()
        self.dataStore = nil
    }

    // MARK: - Commands (wired from CursorpadApp.swift)

    /// Command + N. Creates and binds one new note.
    func newNote() {
        guard !lifecycle.isTerminating else {
            statusMessage = "CursorPad is shutting down."
            return
        }
        guard let dataStore else {
            statusMessage = "Storage is still starting up."
            return
        }
        enqueue { [weak self] in
            guard let self else { return }
            do {
                let note = try await dataStore.createNote()
                self.notes.insert(note, at: 0)
                self.notePersistenceStatus = .saved
                self.statusMessage = nil
                await self.bindSelection(to: note.id)
            } catch {
                self.statusMessage = "Could not create note — \(Self.describe(error))"
            }
        }
    }

    // MARK: - Command palette (Command + P / Command + K)

    /// Opens the palette with the current library ranked for an empty query.
    func presentCommandPalette() {
        guard !lifecycle.isTerminating else {
            statusMessage = "CursorPad is shutting down."
            return
        }
        paletteSession = CommandPaletteSession.presented(candidates: paletteCandidates())
        publishPaletteSession()
        isCommandPalettePresented = true
    }

    /// Closes the palette and hands first-responder focus back to the editor
    /// (ACC-COMMAND-PALETTE-NOTE-NAVIGATION-03).
    func dismissCommandPalette() {
        paletteSession.dismiss()
        publishPaletteSession()
        isCommandPalettePresented = false
        editorFocusRequests += 1
    }

    /// Re-ranks the library for a new query. Zero results keep the palette open with the locked
    /// message, so the user can keep typing (CON-COMMAND-PALETTE-NOTE-NAVIGATION-RECOVERY).
    func updatePaletteQuery(_ text: String) {
        guard isCommandPalettePresented else { return }
        paletteSession.updateQuery(text, candidates: paletteCandidates())
        publishPaletteSession()
    }

    /// Arrow-key navigation with wrap-around.
    func movePaletteSelection(by delta: Int) {
        guard isCommandPalettePresented else { return }
        paletteSession.moveSelection(by: delta)
        publishPaletteSession()
    }

    /// Enter: opens the highlighted note and restores editor focus.
    func confirmPaletteSelection() {
        guard isCommandPalettePresented else { return }
        guard let ranked = paletteSession.selected else {
            return
        }
        dismissCommandPalette()
        enqueue { [weak self] in await self?.selectNote(id: ranked.entry.id) }
    }

    /// Mouse selection of a palette row: same contract as Enter.
    func selectPaletteResult(id: String) {
        guard isCommandPalettePresented else { return }
        guard paletteSession.results.contains(where: { $0.id == id }) else {
            statusMessage = "That note is no longer in the library."
            return
        }
        dismissCommandPalette()
        enqueue { [weak self] in await self?.selectNote(id: id) }
    }

    private func paletteCandidates() -> [PaletteNoteEntry] {
        notes.map { PaletteNoteEntry(id: $0.id, title: $0.title, updatedAt: $0.updatedAt) }
    }

    private func publishPaletteSession() {
        paletteQuery = paletteSession.query
        paletteResults = paletteSession.results
        paletteSelectedIndex = paletteSession.selectedIndex
        paletteZeroResultMessage = paletteSession.zeroResultMessage
    }

    /// Command + B.
    func toggleSidebar() {
        isSidebarVisible.toggle()
        services.userDefaults.set(isSidebarVisible, forKey: AppPreferenceKeys.sidebarVisible)
    }

    // MARK: - External locations (PHASE-06, CON-PERMISSION-FILESYSTEM)

    /// Last valid user-selected external location, kept across denial, cancel and failure.
    private(set) var externalLocationSummary: String?

    /// Command surface for the permission contract. Each entry point is an explicit user action;
    /// nothing here re-presents the panel on its own.
    func requestExternalFolderAccess() {
        guard !rejectIfTerminating() else { return }
        applyPermissions(permissions.requestAccess(.folder))
    }

    func requestExternalFileAccess() {
        guard !rejectIfTerminating() else { return }
        applyPermissions(permissions.requestAccess(.file))
    }

    /// Explicit retry after a denied, cancelled or failed selection (recovery path).
    func retryExternalAccess() {
        guard !rejectIfTerminating() else { return }
        guard permissions.lastPurpose != nil else {
            statusMessage = "There is no location request to retry."
            return
        }
        applyPermissions(permissions.retryLastPurpose())
    }

    /// Explicitly drops every open access scope without changing the recorded selection.
    func releaseExternalAccess() {
        permissions.releaseAllScopes()
        publishExternalAccess()
        statusMessage = "Released the external location's access scope."
    }

    /// Mirrors the coordinator's state. The status line always states what happened and what the
    /// user can do next; a failure never erases the last valid location.
    private func applyPermissions(_ state: PermissionCoordinator.State) {
        publishExternalAccess()
        switch state {
        case .succeeded:
            guard let grant = permissions.grant else { break }
            statusMessage = "Access granted to \(grant.displayName) — \(permissions.activeScopeCount) access scope open."
        case .cancelled:
            statusMessage = permissions.cancelledMessage
        case .failed(let description):
            statusMessage = "External access was not granted — \(description)"
        case .idle, .active:
            break
        }
    }

    private func publishExternalAccess() {
        guard let grant = permissions.grant else {
            externalLocationSummary = nil
            return
        }
        externalLocationSummary = "External location: \(grant.displayName)"
    }

    @discardableResult
    private func rejectIfTerminating() -> Bool {
        guard lifecycle.isTerminating else { return false }
        statusMessage = "CursorPad is shutting down."
        return true
    }

    // MARK: - Note selection

    // MARK: Editor binding (PHASE-05)

    /// Applies one editor edit. The AppKit bridge never writes through a binding; it reports the
    /// new text here so the composition root stays the single source of presentation truth.
    func applyEditorText(_ text: String) {
        guard text != editorText else { return }
        editorText = text
        editorCharacterCount = text.count
        notePersistenceStatus = .unsaved
        scheduleAutosave(for: text)
    }

    /// Hands one edit to the debounced autosave for the note the editor is bound to
    /// (FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE). The submission is recorded so the quit path and the
    /// focused checks can wait for it deterministically; the generation keeps a late delivery from
    /// replacing newer text.
    private func scheduleAutosave(for text: String) {
        guard let noteID = loadedNoteID, let note = notes.first(where: { $0.id == noteID }) else { return }
        editorEditGeneration += 1
        let generation = editorEditGeneration
        latestSubmittedGeneration = generation
        let fileName = note.fileName
        let task = Task { [autosave] in
            await autosave.scheduleTextChange(
                noteID: noteID,
                fileName: fileName,
                text: text,
                generation: generation
            )
        }
        autosaveSubmissions.append(task)
    }

    // MARK: - Autosave (PHASE-08, CON-NON-BLOCKING-ATOMIC-DISK-STORAGE)

    /// Waits until every submitted edit has reached the autosave actor, without committing the
    /// pending one. A pending autosave for a note that is going away is discarded instead.
    private func waitForAutosaveSubmissions() async {
        while !autosaveSubmissions.isEmpty {
            let submissions = autosaveSubmissions
            autosaveSubmissions = []
            for submission in submissions {
                await submission.value
            }
        }
    }

    /// Commits the pending autosave and waits for it. Used before the editor is rebound, before
    /// termination, and by the focused checks.
    func flushAutosave() async {
        await waitForAutosaveSubmissions()
        await autosave.flush()
    }

    /// Explicit user retry of a failed autosave. Nothing retries on its own; the retained text is
    /// re-attempted only because the user asked again
    /// (CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY).
    /// Explicit save. Autosave still runs after 250 ms; this commits the pending edit immediately.
    func saveNow() {
        guard !rejectIfTerminating() else { return }
        guard loadedNoteID != nil else {
            statusMessage = "Open a note before saving."
            return
        }
        if autosaveFailure != nil {
            notePersistenceStatus = .saving
            statusMessage = "Saving…"
            retryAutosave()
            return
        }
        guard notePersistenceStatus == .unsaved else {
            statusMessage = "Saved"
            return
        }
        notePersistenceStatus = .saving
        statusMessage = "Saving…"
        enqueue { [weak self] in
            guard let self else { return }
            await self.flushAutosave()
            if self.autosaveFailure == nil {
                if self.notePersistenceStatus == .saving {
                    self.notePersistenceStatus = .saved
                }
                if self.statusMessage == "Saving…" {
                    self.statusMessage = "Saved"
                }
            }
        }
    }

    var canSaveNow: Bool {
        loadedNoteID != nil && notePersistenceStatus != .saving && !lifecycle.isTerminating
    }

    var saveStatusLabel: String {
        if autosaveFailure != nil { return "Not saved" }
        switch notePersistenceStatus {
        case .saved:
            return "Saved"
        case .unsaved:
            return "Unsaved changes"
        case .saving:
            return "Saving…"
        }
    }

    func retryAutosave() {
        guard !rejectIfTerminating() else { return }
        guard autosaveFailure != nil else {
            statusMessage = "There is no failed autosave to retry."
            return
        }
        enqueue { [weak self] in
            guard let self else { return }
            await self.waitForAutosaveSubmissions()
            await self.autosave.retry()
        }
    }

    /// Mirrors autosave events into presentation state: the discreet failure indicator, the
    /// refreshed metadata row and the sidebar order.
    private func applyAutosaveEvent(_ event: AutosaveEvent) async {
        switch event {
        case .scheduled, .discarded:
            break
        case .committed(let commit):
            if commit.generation >= latestSubmittedGeneration {
                notePersistenceStatus = .saved
                if statusMessage == "Saving…" {
                    statusMessage = "Saved"
                }
            }
            if autosaveFailure != nil {
                autosaveFailure = nil
                if statusMessage?.hasPrefix("Autosave failed") == true {
                    statusMessage = nil
                }
            }
            if missingBodyNoteIDs.contains(commit.noteID) {
                missingBodyNoteIDs.remove(commit.noteID)
                do {
                    try await dataStore?.setBodyMissing(id: commit.noteID, false)
                } catch {
                    statusMessage = "Saved this note but could not clear its missing-body flag: \(Self.describe(error))"
                }
            }
            applyRefreshedNote(commit.document)
        case .failed(_, _, let message):
            autosaveFailure = message
            notePersistenceStatus = .unsaved
            statusMessage = "Autosave failed — \(message)"
        }
    }

    /// Mirrors the editor's resolved typography so the status line can explain a fallback font.
    func editorTypographyResolved(_ source: EditorFontSource) {
        editorFontSource = source
        editorFontNotice = source.explanation
        if statusMessage == Self.editorFontRecheckMessage {
            statusMessage = source.explanation
        }
    }

    /// Explicit retry of the editor typography (CON-CURSOR-DARK-MONOSPACE-EDITOR-RECOVERY).
    func retryEditorTypography() {
        editorTypographyRetryRequests += 1
        statusMessage = Self.editorFontRecheckMessage
    }

    /// Selects a note and binds the editor to its body. Safe to call with an unknown id.
    func selectNote(id: String) async {
        guard notes.contains(where: { $0.id == id }) else {
            statusMessage = "That note is no longer in the library."
            return
        }
        await bindSelection(to: id)
    }

    /// Called when the sidebar selection changes; idempotent for the already-bound note.
    func noteSelectionChanged(to id: String) async {
        guard loadedNoteID != id else { return }
        await selectNote(id: id)
    }

    private func bindSelection(to id: String) async {
        defer { publishSidebarRows() }
        // Whatever was typed into the note the editor is leaving is committed before the rebind, so
        // no pending write outlives its note (CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY).
        await flushAutosave()
        selectedNoteID = id
        persistLastSelection()
        selectionGeneration += 1
        let generation = selectionGeneration

        guard let dataStore, let note = notes.first(where: { $0.id == id }) else {
            editorText = ""
            editorCharacterCount = 0
            loadedNoteID = nil
            return
        }

        do {
            let text = try await dataStore.readBody(fileName: note.fileName)
            guard generation == selectionGeneration else { return }
            editorText = text
            editorCharacterCount = text.count
            notePersistenceStatus = .saved
            loadedNoteID = id
            if missingBodyNoteIDs.remove(id) != nil {
                do {
                    try await dataStore.setBodyMissing(id: id, false)
                } catch {
                    statusMessage = "Recovered this note but could not clear its missing-body flag: \(Self.describe(error))"
                    return
                }
            }
            statusMessage = nil
        } catch {
            guard generation == selectionGeneration else { return }
            editorText = ""
            editorCharacterCount = 0
            loadedNoteID = id
            await flagMissingBody(id)
            statusMessage = "Could not read this note — \(Self.describe(error))"
        }
    }

    private func flagMissingBody(_ id: String) async {
        guard let dataStore else { return }
        do {
            try await dataStore.setBodyMissing(id: id, true)
            missingBodyNoteIDs.insert(id)
        } catch {
            statusMessage = "Note body is missing and could not be flagged: \(Self.describe(error))"
        }
    }

    // MARK: - Compact sidebar library (PHASE-07)

    /// Rebuilds the sidebar rows. Called after every library, selection, edit or delete change.
    func publishSidebarRows(now: Date = Date()) {
        sidebarRows = CompactSidebarLibrary.rows(
            notes: notes,
            selectedID: selectedNoteID,
            missingBodyIDs: missingBodyNoteIDs,
            now: now
        )
    }

    /// Applies a refreshed note document produced by an edit that reached disk: the row is replaced
    /// and promoted to the top of the newest-first order (ACC-COMPACT-SIDEBAR-LIBRARY-03).
    func applyRefreshedNote(_ document: NoteDocument) {
        guard let index = notes.firstIndex(where: { $0.id == document.id }) else { return }
        notes[index] = document
        notes = CompactSidebarLibrary.ordered(notes)
        if selectedNoteID == document.id {
            editorCharacterCount = document.characterCount
        }
        publishSidebarRows()
    }

    var canDeleteSelectedNote: Bool {
        guard let selectedNoteID else { return false }
        return notes.contains { $0.id == selectedNoteID } && pendingDeletionNoteID == nil
    }

    /// Explicit user action: move the note's body file to the macOS Trash and only then remove the
    /// metadata row (ACC-COMPACT-SIDEBAR-LIBRARY-01). A failure keeps the row, the selection and the
    /// editor exactly as they were and exposes an explicit retry.
    func deleteNote(id: String) {
        guard !rejectIfTerminating() else { return }
        guard let dataStore else {
            statusMessage = "Storage is still starting up."
            return
        }
        guard let note = notes.first(where: { $0.id == id }) else {
            statusMessage = "That note is no longer in the library."
            return
        }
        pendingDeletionNoteID = id
        pendingDeletionFailure = nil
        enqueue { [weak self] in
            guard let self else { return }
            // A pending autosave for this note must not resurrect its body file after the delete.
            await self.waitForAutosaveSubmissions()
            await self.autosave.discard(noteID: id)
            do {
                let outcome = try NoteBodyTrash.moveBodyToTrash(
                    fileName: note.fileName,
                    store: dataStore,
                    trash: self.trashService
                )
                try await dataStore.deleteNote(id: id)

                self.notes.removeAll { $0.id == id }
                self.missingBodyNoteIDs.remove(id)
                self.pendingDeletionNoteID = nil
                self.pendingDeletionFailure = nil

                if self.selectedNoteID == id {
                    // Hand the editor to the newest remaining note, or to the empty state.
                    if let next = self.notes.first {
                        await self.bindSelection(to: next.id)
                    } else {
                        self.selectedNoteID = nil
                        self.loadedNoteID = nil
                        self.editorText = ""
                        self.editorCharacterCount = 0
                        self.persistLastSelection()
                        // The deleted row must leave the sidebar: the library is now empty and the
                        // empty state takes over (CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE).
                        self.publishSidebarRows()
                    }
                } else {
                    self.publishSidebarRows()
                }

                switch outcome {
                case .movedToTrash:
                    self.statusMessage = "Moved “\(note.title)” to the Trash."
                case .alreadyMissing:
                    self.statusMessage = "Removed “\(note.title)” — its body file was already missing."
                }
            } catch {
                // The last valid state is untouched: the row, the selection and the editor stay.
                let description = Self.describe(error)
                self.pendingDeletionFailure = description
                self.statusMessage = "\(CompactSidebarLibrary.deleteFailurePrefix) — \(description)"
                self.publishSidebarRows()
            }
        }
    }

    /// Keyboard operation: Delete removes the selected note (the same explicit path as the menu).
    func deleteSelectedNote() {
        guard let selectedNoteID else {
            statusMessage = "Select a note to move it to the Trash."
            return
        }
        deleteNote(id: selectedNoteID)
    }

    /// Explicit recovery for a failed delete: retries the same note.
    func retryPendingDeletion() {
        guard let noteID = pendingDeletionNoteID else {
            statusMessage = "There is no failed deletion to retry."
            return
        }
        guard !lifecycle.isTerminating else {
            statusMessage = "CursorPad is shutting down."
            return
        }
        pendingDeletionNoteID = nil
        pendingDeletionFailure = nil
        deleteNote(id: noteID)
    }

    /// Drops a failed deletion without retrying; nothing was deleted.
    func dismissPendingDeletion() {
        pendingDeletionNoteID = nil
        pendingDeletionFailure = nil
        publishSidebarRows()
    }

    // MARK: - Preferences

    private func restoreSidebarPreference() {
        if services.userDefaults.object(forKey: AppPreferenceKeys.sidebarVisible) != nil {
            isSidebarVisible = services.userDefaults.bool(forKey: AppPreferenceKeys.sidebarVisible)
        }
    }

    private func restoreLastSelection() {
        defer { selectedNoteID = notes.first?.id }
        guard let storedID = services.userDefaults.string(forKey: AppPreferenceKeys.lastSelection) else { return }
        guard let note = notes.first(where: { $0.id == storedID }) else { return }
        selectedNoteID = note.id
    }

    private func persistLastSelection() {
        services.userDefaults.set(selectedNoteID, forKey: AppPreferenceKeys.lastSelection)
    }

    // MARK: - Helpers

    var selectedNote: NoteDocument? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    static func describe(_ error: Error) -> String {
        (error as? DataStore.DataStoreError)?.description ?? error.localizedDescription
    }
}

// MARK: - Root view

/// Final shape: NavigationSplitView with the compact sidebar, the Cursor-dark editor and the
/// status line. PHASE-02 binds the library and selection; PHASE-04/05/07 attach the real features.
struct AppRootView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 480)
        .task {
            await state.start()
            state.attachTerminationHook()
        }
        .onChange(of: state.selectedNoteID) { _, newValue in
            guard let newValue else { return }
            Task { await state.noteSelectionChanged(to: newValue) }
        }
        .overlay {
            if state.isCommandPalettePresented {
                CommandPaletteOverlayView(state: state)
            }
        }
    }

    private var sidebar: some View {
        CompactSidebarLibraryView(state: state)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if state.selectedNoteID == nil {
                Spacer()
                Text("No note open")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Press ⌘N to start writing.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                Spacer()
            } else {
                CursorDarkMonospaceEditorView(
                    text: state.editorText,
                    configuration: state.editorConfiguration,
                    onTextChange: { newText in state.applyEditorText(newText) },
                    focusRequests: state.editorFocusRequests,
                    typographyRetryRequests: state.editorTypographyRetryRequests,
                    onTypographyResolved: { source in state.editorTypographyResolved(source) }
                )
                .accessibilityIdentifier("editor-body")
                .accessibilityLabel("Note body")
            }
            statusLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EditorSurfaceTokens.editorBackground)
        .accessibilityIdentifier("editor-detail")
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            if state.selectedNoteID != nil {
                Button {
                    state.saveNow()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .labelStyle(.titleAndIcon)
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(!state.canSaveNow)
                .accessibilityIdentifier("save-button")
                .accessibilityLabel("Save note")
                .accessibilityHint("Writes the open note to disk now. Autosave still runs after you stop typing.")
                Text(state.saveStatusLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(state.notePersistenceStatus == .unsaved ? EditorSurfaceTokens.accent : EditorSurfaceTokens.textSecondary)
                    .accessibilityIdentifier("save-status")
            }
            if state.libraryStatus.canRetryStartup {
                Button("Retry Storage") {
                    Task { await state.retryStorageStartup() }
                }
                .controlSize(.small)
                .accessibilityIdentifier("storage-retry-button")
            }
            if state.pendingDeletionFailure != nil {
                Button("Retry Delete") { state.retryPendingDeletion() }
                    .controlSize(.small)
                    .accessibilityIdentifier("delete-retry-button")
                    .accessibilityLabel("Retry moving the note to the Trash")
                Button("Dismiss") { state.dismissPendingDeletion() }
                    .controlSize(.small)
                    .accessibilityIdentifier("delete-dismiss-button")
            }
            if state.autosaveFailure != nil {
                Button("Retry Autosave") { state.retryAutosave() }
                    .controlSize(.small)
                    .accessibilityIdentifier("autosave-retry-button")
                    .accessibilityLabel("Retry saving the note")
            }
            Text(state.statusMessage ?? (state.selectedNoteID == nil ? "Ready" : ""))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("status-message")
            Spacer()
            if state.selectedNoteID != nil {
                Text("\(state.editorCharacterCount) characters")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("status-character-count")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(EditorSurfaceTokens.sidebarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EditorSurfaceTokens.divider)
                .frame(height: 1)
        }
    }

}

/// Surface colors shared by the window chrome.
enum EditorSurfaceTokens {
    static let editorBackground = Color(red: 0x18 / 255.0, green: 0x18 / 255.0, blue: 0x18 / 255.0)
    static let sidebarBackground = Color(red: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x1E / 255.0)
    static let divider = Color(red: 0x2B / 255.0, green: 0x2B / 255.0, blue: 0x2B / 255.0)
    static let textPrimary = Color(red: 0xE0 / 255.0, green: 0xE0 / 255.0, blue: 0xE0 / 255.0)
    static let textSecondary = Color(red: 0x6E / 255.0, green: 0x76 / 255.0, blue: 0x81 / 255.0)
    static let accent = Color(red: 0x80 / 255.0, green: 0xBF / 255.0, blue: 0xFF / 255.0)
}
