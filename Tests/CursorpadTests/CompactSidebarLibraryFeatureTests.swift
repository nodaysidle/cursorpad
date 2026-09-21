import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Cursorpad

// MARK: - PHASE-07 focused checks for FEAT-COMPACT-SIDEBAR-LIBRARY
//
// Covers CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE (newest-first rows with title, relative timestamp
// and character count; the locked empty state; deletion as an explicit user action) and
// CON-COMPACT-SIDEBAR-LIBRARY-RECOVERY (idle/active/succeeded/failed/cancelled, explicit retries
// only, nothing left open after a terminal path).
//
// ACC-COMPACT-SIDEBAR-LIBRARY-01 is verified against the real `FileManager.trashItem` API on this
// volume; ACC-02 and ACC-03 are measured against real datastore-backed state.

@Suite("CompactSidebarLibraryFeatureTests")
@MainActor
struct CompactSidebarLibraryFeatureTests {
    // MARK: - Helpers

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeNote(
        id: String,
        title: String,
        updatedAt: Date,
        characters: Int
    ) -> NoteDocument {
        NoteDocument(
            id: id,
            title: title,
            fileName: "\(id).md",
            createdAt: updatedAt,
            updatedAt: updatedAt,
            characterCount: characters
        )
    }

    private func hexComponents(_ color: NSColor) throws -> (Int, Int, Int) {
        let srgb = try #require(color.usingColorSpace(.sRGB), "color must convert to sRGB")
        return (
            Int((srgb.redComponent * 255).rounded()),
            Int((srgb.greenComponent * 255).rounded()),
            Int((srgb.blueComponent * 255).rounded())
        )
    }

    private func median(_ durations: [Duration]) -> Duration {
        let sorted = durations.sorted()
        return sorted[sorted.count / 2]
    }

    private struct Seed {
        let title: String
        let body: String
        let updatedAt: Date
    }

    /// Writes a real on-disk library (SQLite metadata + Markdown bodies) with deterministic
    /// timestamps, so ordering assertions are stable.
    @discardableResult
    private func seedLibrary(root: URL, seeds: [Seed]) async throws -> [NoteDocument] {
        let store = DataStore(paths: DataStore.Paths(rootURL: root))
        try await store.open()
        var documents: [NoteDocument] = []
        for seed in seeds {
            let created = try await store.createNote(at: seed.updatedAt)
            _ = try await store.writeBody(fileName: created.fileName, text: seed.body, stampedAt: seed.updatedAt)
            documents.append(try await store.refreshMetadata(id: created.id, fromText: seed.body, updatedAt: seed.updatedAt))
        }
        await store.close()
        return documents
    }

    private func makeState(label: String, seeds: [Seed]) async throws -> AppState {
        let root = try TestEnvironment.makeTempDirectory(label)
        try await seedLibrary(root: root, seeds: seeds)
        let state = AppState(services: TestEnvironment.makeServices(root: root))
        await state.start()
        return state
    }

    /// Two-note library: Alpha (older) and Beta (newer).
    private func makeTwoNoteState(label: String) async throws -> AppState {
        let now = Date()
        return try await makeState(label: label, seeds: [
            Seed(title: "Alpha", body: "Alpha", updatedAt: now.addingTimeInterval(-90)),
            Seed(title: "Beta", body: "Beta", updatedAt: now.addingTimeInterval(-30))
        ])
    }

    /// Thread-safe recorder for the synchronous `BodyTrashService` seam. `failAll()` scripts the
    /// failing-trash path; every landed item is reported so the test can clean the volume Trash.
    private final class TrashRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var requested: [URL] = []
        private var landed: [URL] = []
        private var failing = false
        private var failures = 0

        var requestedURLs: [URL] { lock.withLock { requested } }
        var landedURLs: [URL] { lock.withLock { landed } }
        var failureCount: Int { lock.withLock { failures } }

        func failAll() { lock.withLock { failing = true } }
        func repair() { lock.withLock { failing = false } }

        var service: BodyTrashService {
            BodyTrashService(moveToTrash: { [self] url in
                let shouldFail = lock.withLock { failing }
                lock.withLock { requested.append(url) }
                if shouldFail {
                    lock.withLock { failures += 1 }
                    throw SidebarTestError.refused
                }
                var resulting: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                let destination = (resulting as URL?) ?? url
                lock.withLock { landed.append(destination) }
                return destination
            })
        }

        /// Removes everything this recorder moved into the volume Trash.
        func cleanTrash() {
            for url in landedURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE: rows

    @Test("rows are newest first and carry title, relative timestamp and character count")
    func rowsCarryLockedFields() {
        let now = Self.base
        let notes = [
            makeNote(id: "a", title: "Alpha", updatedAt: now.addingTimeInterval(-30), characters: 1),
            makeNote(id: "b", title: "Beta", updatedAt: now.addingTimeInterval(-7_200), characters: 0),
            makeNote(id: "c", title: "Gamma", updatedAt: now.addingTimeInterval(-9_000), characters: 42)
        ]

        let rows = CompactSidebarLibrary.rows(notes: notes, selectedID: "c", missingBodyIDs: ["b"], now: now)

        #expect(rows.map(\.id) == ["a", "b", "c"], "the sidebar is ordered by last updated timestamp, newest first")
        #expect(rows[0].title == "Alpha")
        #expect(rows[0].timestampText == "just now")
        #expect(rows[0].characterCountText == "1 character")
        #expect(rows[1].characterCountText == "0 characters")
        #expect(rows[1].isBodyMissing)
        #expect(rows[2].isSelected)
        #expect(!rows[0].isSelected)
        #expect(rows[0].accessibilityLabel.contains("Alpha"))
        #expect(rows[2].accessibilityLabel.contains("selected"))
        #expect(rows[1].accessibilityLabel.contains("body file missing"))
    }

    @Test("relative timestamps follow the compact scale and fall back to a short date")
    func relativeTimestampScale() {
        let now = Self.base
        #expect(CompactSidebarLibrary.relativeTimestamp(for: now.addingTimeInterval(-10), relativeTo: now) == "just now")
        #expect(CompactSidebarLibrary.relativeTimestamp(for: now.addingTimeInterval(-59), relativeTo: now) == "just now")
        #expect(CompactSidebarLibrary.relativeTimestamp(for: now.addingTimeInterval(-60), relativeTo: now) == "1m ago")
        #expect(CompactSidebarLibrary.relativeTimestamp(for: now.addingTimeInterval(-3_600), relativeTo: now) == "1h ago")
        #expect(CompactSidebarLibrary.relativeTimestamp(for: now.addingTimeInterval(-90_000), relativeTo: now) == "yesterday")
        #expect(CompactSidebarLibrary.relativeTimestamp(for: now.addingTimeInterval(-345_600), relativeTo: now) == "4d ago")

        let older = now.addingTimeInterval(-864_000)
        let formatted = CompactSidebarLibrary.relativeTimestamp(for: older, relativeTo: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        #expect(formatted == formatter.string(from: older), "older notes fall back to a short absolute date")
        #expect(!formatted.contains("ago") && formatted != "yesterday" && formatted != "just now")
    }

    @Test("an empty library shows the locked empty state inviting Command+N")
    func emptyStateIsLocked() {
        #expect(CompactSidebarLibrary.emptyStateTitle == "No notes yet")
        #expect(CompactSidebarLibrary.emptyStateHint.contains("⌘N"))
        #expect(CompactSidebarLibrary.emptyStateAccessibilityLabel.contains("Command N"))
        #expect(CompactSidebarLibrary.deleteMenuTitle == "Move to Trash")
    }

    @Test("the sidebar surface uses the locked #1e1e1e background and #2b2b2b divider")
    func surfaceColoursAreLocked() throws {
        #expect(try hexComponents(NSColor(EditorSurfaceTokens.sidebarBackground)) == (0x1E, 0x1E, 0x1E))
        #expect(try hexComponents(NSColor(EditorSurfaceTokens.divider)) == (0x2B, 0x2B, 0x2B))
    }

    @Test("the production sidebar keeps the locked presentation, selection and accessibility wiring")
    func productionSidebarWiring() throws {
        let source = try readPackageFile("Sources/Cursorpad/Features/CompactSidebarLibraryFeature.swift")
        #expect(source.contains("EditorSurfaceTokens.sidebarBackground"))
        #expect(source.contains("EditorSurfaceTokens.divider"))
        #expect(source.contains("List(selection: $state.selectedNoteID)"), "clicking a row binds the editor to that note")
        #expect(source.contains("state.deleteNote(id: row.id)"))
        #expect(source.contains("onDeleteCommand"))
        #expect(source.contains("library-empty-state"))
        #expect(source.contains("empty-state-new-note-button"))
        #expect(source.contains("sidebar-note-"))
        #expect(source.contains("sidebar-delete-"))
        #expect(source.contains("accessibilityLabel"))
        #expect(!source.contains("Task.detached"))
        #expect(!source.contains("Task.sleep"))

        // ACC-01: the only production removal path is the FileManager Trash API.
        #expect(source.contains("FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)"))
        #expect(source.contains("enum NoteBodyTrash"))
        let plainRemovalSites = source.components(separatedBy: "removeItem(at: url)").count - 1
        #expect(plainRemovalSites == 1, "a plain removal exists only in the `deleting` test seam")

        // The composition root calls the trash boundary *before* removing the metadata row.
        let appStateSource = try readPackageFile("Sources/Cursorpad/AppState.swift")
        let trashRange = try #require(appStateSource.range(of: "NoteBodyTrash.moveBodyToTrash("))
        let metadataDeleteRange = try #require(appStateSource.range(of: "try await dataStore.deleteNote(id: id)"))
        #expect(trashRange.lowerBound < metadataDeleteRange.lowerBound,
                "the body file must be moved to the Trash before its metadata row is removed")
    }

    // MARK: - ACC-COMPACT-SIDEBAR-LIBRARY-01: delete moves the file to the macOS Trash

    @Test("deleting a note moves its body file to the macOS Trash through FileManager")
    func liveTrashServiceMovesFileToTrash() async throws {
        let root = try TestEnvironment.makeTempDirectory("sidebar-trash-live")
        let store = DataStore(paths: DataStore.Paths(rootURL: root))
        try await store.open()
        let note = try await store.createNote()
        _ = try await store.writeBody(fileName: note.fileName, text: "payload", stampedAt: Date())
        let bodyURL = store.bodyURL(fileName: note.fileName)
        #expect(FileManager.default.fileExists(atPath: bodyURL.path))

        let outcome = try NoteBodyTrash.moveBodyToTrash(fileName: note.fileName, store: store, trash: .live)
        await store.close()

        guard case .movedToTrash(let trashedURL) = outcome else {
            Issue.record("expected the production trash service to move the body file, got \(outcome)")
            return
        }
        defer { try? FileManager.default.removeItem(at: trashedURL) }

        #expect(!FileManager.default.fileExists(atPath: bodyURL.path), "the body file must leave the notes directory")
        #expect(FileManager.default.fileExists(atPath: trashedURL.path), "the body file must land in the Trash")
        #expect(trashedURL.lastPathComponent == note.fileName)
        #expect(trashedURL.standardizedFileURL != bodyURL.standardizedFileURL)
        // The Trash it lands in belongs to the same volume as the file it left.
        let volumeRoot = URL(fileURLWithPath: "/Volumes/\(root.pathComponents[2])")
        #expect(trashedURL.path.hasPrefix(volumeRoot.path) || trashedURL.path.contains("/.Trash"),
                "trashed item \(trashedURL.path) is not on volume \(volumeRoot.path)")
    }

    @Test("a body file that already vanished is reported as missing instead of being trashed")
    func alreadyMissingBodyIsHonest() async throws {
        let root = try TestEnvironment.makeTempDirectory("sidebar-trash-missing")
        let store = DataStore(paths: DataStore.Paths(rootURL: root))
        try await store.open()
        let note = try await store.createNote()
        try await store.writeBody(fileName: note.fileName, text: "payload", stampedAt: Date())
        let bodyURL = store.bodyURL(fileName: note.fileName)
        try FileManager.default.removeItem(at: bodyURL)

        let outcome = try NoteBodyTrash.moveBodyToTrash(fileName: note.fileName, store: store, trash: .live)
        await store.close()
        #expect(outcome == .alreadyMissing)
    }

    @Test("the composition root routes deletion through the trash service before the metadata row")
    func appStateDeletesThroughTrashService() async throws {
        let state = try await makeTwoNoteState(label: "sidebar-delete-live")
        let recorder = TrashRecorder()
        state.trashService = recorder.service
        defer { recorder.cleanTrash() }

        let target = try #require(state.notes.first { $0.title == "Alpha" })
        let store = try #require(state.dataStore)
        let bodyURL = store.bodyURL(fileName: target.fileName)
        #expect(FileManager.default.fileExists(atPath: bodyURL.path))

        state.deleteNote(id: target.id)
        await state.waitForPendingOperations()

        #expect(recorder.requestedURLs.map(\.standardizedFileURL) == [bodyURL.standardizedFileURL],
                "the delete must hand the body file to the trash boundary")
        #expect(!FileManager.default.fileExists(atPath: bodyURL.path))
        #expect(!state.notes.contains { $0.id == target.id })
        #expect(!state.sidebarRows.contains { $0.id == target.id })
        #expect(state.statusMessage?.contains("Moved") == true)
        #expect(state.pendingDeletionNoteID == nil)
        #expect(state.pendingDeletionFailure == nil)
        let remainingRow = try await store.note(id: target.id)
        #expect(remainingRow == nil, "the metadata row is removed after the trash move")
    }

    @Test("deleting the selected note hands the editor to the newest remaining note")
    func deletingSelectedNoteRebindsEditor() async throws {
        let state = try await makeTwoNoteState(label: "sidebar-delete-selected")
        let recorder = TrashRecorder()
        state.trashService = recorder.service
        defer { recorder.cleanTrash() }

        let alpha = try #require(state.notes.first { $0.title == "Alpha" })
        let beta = try #require(state.notes.first { $0.title == "Beta" })
        await state.selectNote(id: beta.id)
        #expect(state.editorText == "Beta")
        #expect(state.sidebarRows.first?.id == beta.id)

        state.deleteNote(id: beta.id)
        await state.waitForPendingOperations()

        #expect(state.selectedNoteID == alpha.id, "the newest remaining note is bound")
        #expect(state.editorText == "Alpha")
        #expect(state.sidebarRows.map(\.id) == [alpha.id])

        // Deleting the last note returns the library and the editor to the empty state.
        state.deleteNote(id: alpha.id)
        await state.waitForPendingOperations()
        #expect(state.notes.isEmpty)
        #expect(state.sidebarRows.isEmpty, "an empty library shows the empty state")
        #expect(state.selectedNoteID == nil)
        #expect(state.editorText.isEmpty)
    }

    @Test("keyboard deletion uses the same explicit path and reports when nothing is selected")
    func keyboardDeletePath() async throws {
        let state = try await makeTwoNoteState(label: "sidebar-delete-keyboard")
        let recorder = TrashRecorder()
        state.trashService = recorder.service
        defer { recorder.cleanTrash() }

        state.selectedNoteID = nil
        state.deleteSelectedNote()
        #expect(state.statusMessage?.contains("Select a note") == true, "no deletion without a selection")
        #expect(state.notes.count == 2)

        let target = try #require(state.notes.first)
        state.selectedNoteID = target.id
        #expect(state.canDeleteSelectedNote)
        state.deleteSelectedNote()
        await state.waitForPendingOperations()
        #expect(state.notes.count == 1)
        #expect(recorder.requestedURLs.count == 1)
    }

    // MARK: - CON-COMPACT-SIDEBAR-LIBRARY-RECOVERY: failure keeps the last valid state

    @Test("a failed trash keeps the row, the selection and the editor and exposes an explicit retry")
    func deleteFailurePreservesEverythingAndRetries() async throws {
        let state = try await makeTwoNoteState(label: "sidebar-delete-failure")
        let recorder = TrashRecorder()
        recorder.failAll()
        state.trashService = recorder.service
        defer { recorder.cleanTrash() }

        let target = try #require(state.notes.first { $0.title == "Alpha" })
        let store = try #require(state.dataStore)
        let bodyURL = store.bodyURL(fileName: target.fileName)
        await state.selectNote(id: target.id)
        #expect(state.editorText == "Alpha")
        let rowsBefore = state.sidebarRows

        state.deleteNote(id: target.id)
        await state.waitForPendingOperations()

        #expect(state.pendingDeletionNoteID == target.id)
        #expect(state.pendingDeletionFailure?.contains("refused") == true)
        #expect(state.statusMessage?.hasPrefix(CompactSidebarLibrary.deleteFailurePrefix) == true)
        #expect(state.notes.contains { $0.id == target.id }, "the library keeps its last valid state")
        #expect(state.sidebarRows == rowsBefore, "the row is untouched")
        #expect(state.selectedNoteID == target.id, "the selection is untouched")
        #expect(state.editorText == "Alpha", "the editor keeps the user's text")
        #expect(FileManager.default.fileExists(atPath: bodyURL.path), "the body file is still on disk")

        // Nothing retries by itself: waiting changes nothing until the user acts.
        try await Task.sleep(for: .milliseconds(300))
        await state.waitForPendingOperations()
        #expect(recorder.failureCount == 1, "a failed delete must not auto-retry")

        // The failure can be dropped without deleting anything.
        state.dismissPendingDeletion()
        #expect(state.pendingDeletionFailure == nil)
        #expect(state.notes.count == 2)
        #expect(state.statusMessage?.hasPrefix(CompactSidebarLibrary.deleteFailurePrefix) == true, "dismissal keeps the honest report")

        // Explicit retry after the user repairs the problem.
        recorder.repair()
        state.trashService = recorder.service
        state.deleteNote(id: target.id)
        await state.waitForPendingOperations()
        #expect(!state.notes.contains { $0.id == target.id })
        #expect(!FileManager.default.fileExists(atPath: bodyURL.path))
        #expect(state.pendingDeletionNoteID == nil)
        #expect(state.pendingDeletionFailure == nil)
    }

    @Test("retrying without a failed deletion reports honestly instead of deleting")
    func retryWithoutFailureIsHonest() async throws {
        let state = try await makeTwoNoteState(label: "sidebar-delete-retry-empty")
        state.retryPendingDeletion()
        #expect(state.statusMessage?.contains("no failed deletion") == true)
        #expect(state.notes.count == 2)
    }

    // MARK: - ACC-COMPACT-SIDEBAR-LIBRARY-02: selection switches the editor under 16 ms

    @Test("selecting a note switches the editor contents within 16 milliseconds")
    func selectionLatencyBenchmark() async throws {
        let now = Date()
        var seeds: [Seed] = []
        for index in 0..<200 {
            seeds.append(Seed(
                title: "Note \(index)",
                body: "body of note \(index)",
                updatedAt: now.addingTimeInterval(-Double(index))
            ))
        }
        let state = try await makeState(label: "sidebar-select-benchmark", seeds: seeds)
        #expect(state.notes.count == 200)

        let newest = try #require(state.notes.first)
        let oldest = try #require(state.notes.last)
        #expect(state.sidebarRows.count == 200)

        // Warm both directions, then measure real switches through the sidebar's own path.
        await state.selectNote(id: oldest.id)
        await state.selectNote(id: newest.id)
        var durations: [Duration] = []
        let clock = ContinuousClock()
        for run in 0..<9 {
            let target = run.isMultiple(of: 2) ? oldest.id : newest.id
            let start = clock.now
            await state.noteSelectionChanged(to: target)
            durations.append(clock.now - start)
        }
        let observed = median(durations)
        print("[benchmark] sidebar selection switch: median \(observed), runs \(durations)")
        #expect(observed < .milliseconds(16), "switching the bound note took \(observed)")
        #expect(state.editorText == "body of note 199", "the last measured switch bound the oldest note")
        await state.flushForTermination()
    }

    @Test("selection is honest: unknown ids are refused and rebinding the same note is a no-op")
    func selectionHonesty() async throws {
        let state = try await makeTwoNoteState(label: "sidebar-selection-honesty")
        let target = try #require(state.notes.first { $0.title == "Alpha" })

        await state.selectNote(id: target.id)
        #expect(state.editorText == "Alpha")
        #expect(state.selectedNoteID == target.id)

        await state.selectNote(id: "missing-note")
        #expect(state.statusMessage?.contains("no longer in the library") == true)
        #expect(state.editorText == "Alpha", "an unknown id must not clear the editor")

        // The sidebar already binds this note: rebinding is a no-op.
        await state.noteSelectionChanged(to: target.id)
        #expect(state.editorText == "Alpha")
        #expect(state.selectedNoteID == target.id)
    }

    // MARK: - ACC-COMPACT-SIDEBAR-LIBRARY-03: rows follow edits

    @Test("an edit promotes the note's row to the top and refreshes its character count")
    func editedNoteReordersRows() async throws {
        let state = try await makeTwoNoteState(label: "sidebar-order")
        let alpha = try #require(state.notes.first { $0.title == "Alpha" })
        let beta = try #require(state.notes.first { $0.title == "Beta" })
        #expect(state.sidebarRows.map(\.id) == [beta.id, alpha.id])
        #expect(state.sidebarRows.map(\.characterCountText) == ["4 characters", "5 characters"])

        let store = try #require(state.dataStore)
        let stamp = Date()
        _ = try await store.writeBody(fileName: alpha.fileName, text: "alpha edited body", stampedAt: stamp)
        let refreshed = try await store.refreshMetadata(id: alpha.id, fromText: "alpha edited body", updatedAt: stamp)
        state.applyRefreshedNote(refreshed)

        #expect(state.sidebarRows.map(\.id) == [alpha.id, beta.id], "the order follows the last updated timestamp")
        #expect(state.sidebarRows.first?.title == "alpha edited body", "the title follows the edited body")
        #expect(state.sidebarRows.first?.characterCountText == "17 characters")
        #expect(state.sidebarRows.first?.timestampText == "just now")
    }

    @Test("a new note appears at the top of the sidebar with an empty body")
    func newNoteAppearsInSidebar() async throws {
        let state = try await makeTwoNoteState(label: "sidebar-new-note")
        #expect(state.sidebarRows.count == 2)

        state.newNote()
        await state.waitForPendingOperations()

        let created = try #require(state.notes.first)
        #expect(state.sidebarRows.first?.id == created.id)
        #expect(state.sidebarRows.first?.title == "Untitled")
        #expect(state.sidebarRows.first?.characterCountText == "0 characters")
        #expect(state.sidebarRows.first?.isSelected == true)
        #expect(state.editorText.isEmpty)
    }
}

private enum SidebarTestError: Error, LocalizedError {
    case refused

    var errorDescription: String? { "refused" }
}
