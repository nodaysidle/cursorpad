import Foundation
import Testing

@testable import Cursorpad

@Suite("DataStoreTests")
struct DataStoreTests {
    // MARK: - Helpers

    private func makeStore(_ label: String) async throws -> DataStore {
        let root = try TestEnvironment.makeTempDirectory(label)
        let store = DataStore(paths: DataStore.Paths(rootURL: root))
        try await store.open()
        return store
    }

    private func rawRowCount(_ store: DataStore) async throws -> Int {
        let value = try await store.rawQuerySingleValueForTesting("SELECT COUNT(*) FROM notes;")
        return Int(value ?? "0") ?? -1
    }

    // MARK: - Schema and locked SQLite strategy

    @Test("open() creates the database and applies the locked SQLite strategy")
    func openAppliesLockedSQLiteStrategy() async throws {
        let root = try TestEnvironment.makeTempDirectory("datastore-open")
        let store = DataStore(paths: DataStore.Paths(rootURL: root))
        try await store.open()

        #expect(FileManager.default.fileExists(atPath: DataStore.Paths(rootURL: root).databaseURL.path))
        #expect(try await store.rawQuerySingleValueForTesting("PRAGMA journal_mode;")?.lowercased() == "wal")
        #expect(try await store.rawQuerySingleValueForTesting("PRAGMA user_version;") == "1")
        #expect(try await store.rawQuerySingleValueForTesting("PRAGMA busy_timeout;") == "5000")
        // synchronous NORMAL == 1
        #expect(try await store.rawQuerySingleValueForTesting("PRAGMA synchronous;") == "1")

        // The Notes directory exists so bodies can be written next to the database.
        #expect(FileManager.default.fileExists(atPath: DataStore.Paths(rootURL: root).notesDirectory.path))
        await store.close()
    }

    @Test("path layout matches the locked Application Support contract")
    func pathLayout() {
        let paths = DataStore.Paths(rootURL: URL(fileURLWithPath: "/tmp/cursorpad-root"))
        #expect(paths.databaseURL.lastPathComponent == "CursorPad.sqlite3")
        #expect(paths.notesDirectory.lastPathComponent == "Notes")
        #expect(paths.databaseURL.deletingLastPathComponent().path == "/tmp/cursorpad-root")
    }

    @Test("a newer on-disk schema version is rejected instead of being downgraded")
    func rejectsNewerSchemaVersion() async throws {
        let root = try TestEnvironment.makeTempDirectory("datastore-newer-schema")
        let store = DataStore(paths: DataStore.Paths(rootURL: root))
        try await store.open()
        try await store.runRawSQLForTesting("PRAGMA user_version = 99;")
        await store.close()

        let reopened = DataStore(paths: DataStore.Paths(rootURL: root))
        var error: DataStore.DataStoreError?
        do { try await reopened.open() } catch let caught as DataStore.DataStoreError { error = caught }
        guard case .sqlite(let message) = error else {
            Issue.record("expected a sqlite schema error, got \(String(describing: error))")
            return
        }
        #expect(message.contains("99"))
    }

    @Test("operations before open() fail honestly")
    func operationsRequireOpen() async throws {
        let root = try TestEnvironment.makeTempDirectory("datastore-not-open")
        let store = DataStore(paths: DataStore.Paths(rootURL: root))
        var error: DataStore.DataStoreError?
        do { _ = try await store.notes() } catch let caught as DataStore.DataStoreError { error = caught }
        #expect(error == .notOpen)
    }

    // MARK: - CON-DATA-NOTEDOCUMENT / CON-PERSISTENCE-NOTEDOCUMENT

    @Test("createNote writes a lowercase UUID file name with an atomically written empty body")
    func createNoteWritesEmptyAtomicBody() async throws {
        let store = try await makeStore("datastore-create")
        let creationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let note = try await store.createNote(at: creationDate)

        #expect(note.id == note.id.lowercased())
        #expect(UUID(uuidString: note.id) != nil)
        #expect(note.fileName == "\(note.id).md")
        #expect(note.title == "Untitled")
        #expect(note.characterCount == 0)
        #expect(note.createdAt == creationDate)
        #expect(note.updatedAt == creationDate)

        let bodyURL = store.bodyURL(fileName: note.fileName)
        #expect(FileManager.default.fileExists(atPath: bodyURL.path))
        let size = try FileManager.default.attributesOfItem(atPath: bodyURL.path)[.size] as? Int
        #expect(size == 0)
        #expect(try await store.notes() == [note])
        await store.close()
    }

    @Test("metadata survives close and reopen")
    func metadataPersistsAcrossReopen() async throws {
        let root = try TestEnvironment.makeTempDirectory("datastore-persist")
        let store = DataStore(paths: DataStore.Paths(rootURL: root))
        try await store.open()
        let note = try await store.createNote(at: Date(timeIntervalSince1970: 1_700_000_100))
        try await store.refreshMetadata(id: note.id, fromText: "Persisted title\nbody text", updatedAt: Date(timeIntervalSince1970: 1_700_000_200))
        await store.close()

        let reopened = DataStore(paths: DataStore.Paths(rootURL: root))
        try await reopened.open()
        let reloaded = try await reopened.notes()
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.title == "Persisted title")
        #expect(reloaded.first?.characterCount == "Persisted title\nbody text".count)
        #expect(reloaded.first?.updatedAt == Date(timeIntervalSince1970: 1_700_000_200))
        await reopened.close()
    }

    @Test("refreshMetadata derives title and character count from the body text")
    func refreshMetadataDerivesTitleAndCount() async throws {
        let store = try await makeStore("datastore-refresh")
        let note = try await store.createNote()

        let markdownBody = "# Notes for today\nsecond line"
        let refreshed = try await store.refreshMetadata(id: note.id, fromText: markdownBody, updatedAt: Date(timeIntervalSince1970: 1_700_000_500))
        #expect(refreshed.title == "Notes for today")
        #expect(refreshed.characterCount == markdownBody.count)

        let blank = try await store.refreshMetadata(id: note.id, fromText: "\n   \n", updatedAt: Date(timeIntervalSince1970: 1_700_000_600))
        #expect(blank.title == "Untitled")
        #expect(blank.characterCount == "\n   \n".count)
        await store.close()
    }

    @Test("notes() is ordered by last update, newest first")
    func notesOrderedByLastUpdate() async throws {
        let store = try await makeStore("datastore-order")
        let first = try await store.createNote(at: Date(timeIntervalSince1970: 1_700_000_000))
        let second = try await store.createNote(at: Date(timeIntervalSince1970: 1_700_000_100))
        let third = try await store.createNote(at: Date(timeIntervalSince1970: 1_700_000_200))

        #expect(try await store.notes().map(\.id) == [third.id, second.id, first.id])

        // Editing the oldest note moves it to the front.
        try await store.refreshMetadata(id: first.id, fromText: "Edited", updatedAt: Date(timeIntervalSince1970: 1_700_000_300))
        #expect(try await store.notes().map(\.id) == [first.id, third.id, second.id])
        await store.close()
    }

    @Test("updateMetadata persists a replaced document and rejects unknown ids")
    func updateMetadataPersistsAndValidates() async throws {
        let store = try await makeStore("datastore-update")
        var note = try await store.createNote(at: Date(timeIntervalSince1970: 1_700_000_000))
        note.title = "Renamed"
        note.updatedAt = Date(timeIntervalSince1970: 1_700_000_400)
        note.characterCount = 42
        try await store.updateMetadata(note)

        let reloaded = try await store.note(id: note.id)
        #expect(reloaded?.title == "Renamed")
        #expect(reloaded?.characterCount == 42)

        let ghost = NoteDocument(
            id: "8a1c0e1e-0000-4000-8000-000000000000",
            title: note.title,
            fileName: note.fileName,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            characterCount: note.characterCount
        )
        var error: DataStore.DataStoreError?
        do { try await store.updateMetadata(ghost) } catch let caught as DataStore.DataStoreError { error = caught }
        guard case .invalidRecord = error else {
            Issue.record("expected invalidRecord for unknown id, got \(String(describing: error))")
            return
        }
        await store.close()
    }

    @Test("deleteNote removes the row transactionally and reports unknown ids")
    func deleteNoteRemovesRow() async throws {
        let store = try await makeStore("datastore-delete")
        let note = try await store.createNote()
        try await store.deleteNote(id: note.id)

        #expect(try await store.notes().isEmpty)
        #expect(try await rawRowCount(store) == 0)

        var error: DataStore.DataStoreError?
        do { try await store.deleteNote(id: note.id) } catch let caught as DataStore.DataStoreError { error = caught }
        guard case .invalidRecord = error else {
            Issue.record("expected invalidRecord when deleting an unknown note, got \(String(describing: error))")
            return
        }
        await store.close()
    }

    @Test("body read and write round-trip through atomic UTF-8 file writes")
    func bodyRoundTrip() async throws {
        let store = try await makeStore("datastore-body")
        let note = try await store.createNote()
        let text = "line one\nline two — unicode ✓\n"

        try await store.writeBody(fileName: note.fileName, text: text)
        #expect(try await store.readBody(fileName: note.fileName) == text)

        let raw = try String(contentsOf: store.bodyURL(fileName: note.fileName), encoding: .utf8)
        #expect(raw == text)

        var error: DataStore.DataStoreError?
        do { _ = try await store.readBody(fileName: "missing.md") } catch let caught as DataStore.DataStoreError { error = caught }
        guard case .fileSystem = error else {
            Issue.record("expected fileSystem error for a missing body, got \(String(describing: error))")
            return
        }
        await store.close()
    }

    // MARK: - Invalid records preserve prior valid state

    @Test("invalid rows are excluded, reported, and never overwrite valid records")
    func invalidRowsArePreservedAndReported() async throws {
        let store = try await makeStore("datastore-invalid")
        let valid = try await store.createNote(at: Date(timeIntervalSince1970: 1_700_000_000))

        try await store.runRawSQLForTesting("INSERT INTO notes (id, title, file_name, created_at, updated_at, character_count, body_missing) VALUES ('', 'broken', '', 0, 0, 0, 0);")
        try await store.runRawSQLForTesting("INSERT INTO notes (id, title, file_name, created_at, updated_at, character_count, body_missing) VALUES ('not-a-uuid', 'broken', 'ghost-file.md', 1, 2, 3, 0);")

        let snapshot = try await store.librarySnapshot()
        #expect(snapshot.notes.map(\.id) == [valid.id])
        #expect(snapshot.invalidRecordCount == 2)

        let report = try await store.reconcile()
        #expect(report.invalidRecordCount == 2)
        #expect(try await rawRowCount(store) == 3, "invalid rows must not be deleted")
        #expect(try await store.notes().map(\.id) == [valid.id])
        await store.close()
    }

    // MARK: - CON-PERSISTENCE-NOTEDOCUMENT reconciliation

    @Test("reconcile adopts unknown body files with derived metadata")
    func reconcileAdoptsUnknownFiles() async throws {
        let store = try await makeStore("datastore-adopt")
        let notesDirectory = store.paths.notesDirectory
        let stray = notesDirectory.appendingPathComponent("scratch-notes.md")
        let content = "Scratch title\n\nSome body text"
        try content.write(to: stray, atomically: true, encoding: .utf8)

        let report = try await store.reconcile()
        #expect(report.adopted.count == 1)
        #expect(report.adopted.first?.fileName == "scratch-notes.md")
        #expect(report.adopted.first?.title == "Scratch title")
        #expect(report.adopted.first?.characterCount == content.count)
        #expect(report.adopted.first?.id == report.adopted.first?.id.lowercased())

        // Adoption must not rewrite or move the file.
        #expect(try String(contentsOf: stray, encoding: .utf8) == content)

        // A second reconcile must not duplicate the row.
        let second = try await store.reconcile()
        #expect(second.adopted.isEmpty)
        #expect(try await store.notes().count == 1)
        await store.close()
    }

    @Test("reconcile adopts lowercase UUID file names using their own id")
    func reconcileAdoptsUUIDNamedFiles() async throws {
        let store = try await makeStore("datastore-adopt-uuid")
        let identifier = UUID().uuidString.lowercased()
        let file = store.paths.notesDirectory.appendingPathComponent("\(identifier).md")
        try "uuid named body".write(to: file, atomically: true, encoding: .utf8)

        let report = try await store.reconcile()
        #expect(report.adopted.map(\.id) == [identifier])
        await store.close()
    }

    @Test("reconcile refreshes metadata when the body file is newer")
    func reconcileRefreshesNewerFiles() async throws {
        let store = try await makeStore("datastore-refresh-newer")
        let note = try await store.createNote(at: Date(timeIntervalSince1970: 1_700_000_000))
        let bodyURL = store.bodyURL(fileName: note.fileName)

        let edited = "Edited externally\nwith more text"
        try edited.write(to: bodyURL, atomically: true, encoding: .utf8)
        let future = Date(timeIntervalSince1970: 1_700_000_900)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: bodyURL.path)

        let report = try await store.reconcile()
        #expect(report.refreshed.map(\.id) == [note.id])
        let refreshed = try await store.note(id: note.id)
        #expect(refreshed?.title == "Edited externally")
        #expect(refreshed?.characterCount == edited.count)
        #expect((refreshed?.updatedAt ?? .distantPast) > note.updatedAt)
        await store.close()
    }

    @Test("reconcile marks missing bodies and keeps the row recoverable")
    func reconcileMarksMissingBodies() async throws {
        let store = try await makeStore("datastore-missing")
        let note = try await store.createNote()
        let bodyURL = store.bodyURL(fileName: note.fileName)
        try FileManager.default.removeItem(at: bodyURL)

        let report = try await store.reconcile()
        #expect(report.markedMissing == [note.id])
        let snapshot = try await store.librarySnapshot()
        #expect(snapshot.missingBodyIDs == [note.id])
        #expect(snapshot.notes.map(\.id) == [note.id], "the record must survive its missing body")

        // Explicit recovery: restore the body and clear the flag.
        try await store.writeBody(fileName: note.fileName, text: "recovered")
        try await store.setBodyMissing(id: note.id, false)
        try await store.refreshMetadata(id: note.id, fromText: "recovered", updatedAt: Date(timeIntervalSince1970: 1_700_000_700))
        let recovered = try await store.librarySnapshot()
        #expect(recovered.missingBodyIDs.isEmpty)
        #expect(recovered.notes.first?.title == "recovered")

        // A later reconcile keeps the recovered row intact.
        let second = try await store.reconcile()
        #expect(second.markedMissing.isEmpty)
        #expect(try await rawRowCount(store) == 1)
        await store.close()
    }

    @Test("reconcile reports unreadable files instead of adopting them")
    func reconcileSkipsUnreadableFiles() async throws {
        let store = try await makeStore("datastore-invalid-utf8")
        let broken = store.paths.notesDirectory.appendingPathComponent("broken.md")
        try Data([0xFF, 0xFE, 0x00, 0x41]).write(to: broken, options: [.atomic])

        let report = try await store.reconcile()
        #expect(report.skippedInvalidFiles == ["broken.md"])
        #expect(report.adopted.isEmpty)
        #expect(try await store.notes().isEmpty)
        await store.close()
    }

    @Test("reconcile stays idempotent across repeated passes (timestamp precision regression)")
    func reconcileIsIdempotent() async throws {
        let store = try await makeStore("datastore-idempotent")
        _ = try await store.createNote()
        try await store.writeBody(fileName: "stray-file.md", text: "stray")

        let first = try await store.reconcile()
        #expect(first.adopted.map(\.fileName) == ["stray-file.md"])
        #expect(first.refreshed.isEmpty, "a freshly created note must not be re-refreshed: \(first.refreshed.map(\.fileName))")
        #expect(first.markedMissing.isEmpty, "unexpected missing: \(first.markedMissing)")

        // Repeated passes must all be complete no-ops. Before the millisecond timestamp rule, an
        // unchanged file could be reclassified as "newer" by a one-ulp Date round-trip (the
        // `reconcile is idempotent` flake), so this loop is the regression guard.
        for pass in 2...6 {
            let report = try await store.reconcile()
            #expect(report.adopted.isEmpty, "pass \(pass) adopted: \(report.adopted.map(\.fileName))")
            #expect(report.refreshed.isEmpty, "pass \(pass) refreshed: \(report.refreshed.map(\.fileName))")
            #expect(report.markedMissing.isEmpty, "pass \(pass) marked missing: \(report.markedMissing)")
        }
        #expect(try await store.notes().count == 2)
        await store.close()
    }

    @Test("sub-millisecond timestamp noise is never treated as a newer file")
    func timestampComparisonIgnoresSubMillisecondNoise() {
        let metadata = Date(timeIntervalSince1970: 1_789_977_362.5805135)
        // One ulp at this magnitude: the observed Date <-> timeIntervalSince1970 round-trip error.
        let oneULP = 1.1920928955078125e-07
        let oneULPNewer = Date(timeIntervalSince1970: metadata.timeIntervalSince1970 + oneULP)
        let oneULPOlder = Date(timeIntervalSince1970: metadata.timeIntervalSince1970 - oneULP)

        #expect(!StorageTimestamp.isFileNewerThanMetadata(oneULPNewer, metadata: metadata))
        #expect(!StorageTimestamp.isFileNewerThanMetadata(oneULPOlder, metadata: metadata))
        #expect(!StorageTimestamp.isFileNewerThanMetadata(metadata, metadata: metadata))
        // A genuine edit is still detected.
        #expect(StorageTimestamp.isFileNewerThanMetadata(Date(timeIntervalSince1970: metadata.timeIntervalSince1970 + 0.002), metadata: metadata))
        // Normalization is idempotent, so stored values stay comparable across passes.
        let normalized = StorageTimestamp.normalizeInterval(metadata.timeIntervalSince1970)
        #expect(StorageTimestamp.normalizeInterval(normalized) == normalized)
    }

    @Test("app-authored bodies carry their recorded timestamp as the file modification date")
    func appAuthoredBodiesAreStamped() async throws {
        let store = try await makeStore("datastore-stamp")
        let creationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let note = try await store.createNote(at: creationDate)

        let bodyPath = store.bodyURL(fileName: note.fileName).path
        let createdAttributes = try FileManager.default.attributesOfItem(atPath: bodyPath)
        let createdModificationDate = try #require(createdAttributes[.modificationDate] as? Date)
        #expect(StorageTimestamp.normalizeInterval(createdModificationDate.timeIntervalSince1970)
            == StorageTimestamp.normalizeInterval(note.updatedAt.timeIntervalSince1970))

        let stamp = try await store.writeBody(fileName: note.fileName, text: "edited body")
        let writtenAttributes = try FileManager.default.attributesOfItem(atPath: bodyPath)
        let writtenModificationDate = try #require(writtenAttributes[.modificationDate] as? Date)
        #expect(StorageTimestamp.normalizeInterval(writtenModificationDate.timeIntervalSince1970)
            == StorageTimestamp.normalizeInterval(stamp.timeIntervalSince1970))

        // The documented contract: the stamp returned by writeBody is recorded as the note's
        // updatedAt in the same pass. With that pairing the app's own write is stable, and only a
        // genuinely newer external edit can trigger a refresh.
        try await store.refreshMetadata(id: note.id, fromText: "edited body", updatedAt: stamp)
        let report = try await store.reconcile()
        #expect(report.refreshed.isEmpty, "stamped body must not look newer than its record: \(report.refreshed.map(\.fileName))")
        await store.close()
    }

    // MARK: - CON-DATA-EDITORCONFIGURATION / CON-PERSISTENCE-EDITORCONFIGURATION

    @Test("editor configuration uses versioned keys, defaults, and persistence")
    func editorConfigurationPersistence() {
        TestEnvironment.withTestUserDefaults { defaults, _ in
            let store = EditorConfigurationStore(defaults: defaults)
            #expect(store.load() == .default)
            #expect(EditorConfiguration.default.fontSize == 13)
            #expect(EditorConfiguration.default.tabWidth == 4)
            #expect(EditorConfiguration.default.wrapsLines == true)
            #expect(EditorConfigurationStore.fontSizeKey == "cursorpad.config.editor.v1.fontSize")

            var custom = EditorConfiguration.default
            custom.fontSize = 15
            custom.tabWidth = 2
            custom.wrapsLines = false
            store.save(custom)

            #expect(defaults.double(forKey: EditorConfigurationStore.fontSizeKey) == 15)
            #expect(defaults.integer(forKey: EditorConfigurationStore.tabWidthKey) == 2)
            #expect(defaults.bool(forKey: EditorConfigurationStore.wrapsLinesKey) == false)
            #expect(EditorConfigurationStore(defaults: defaults).load() == custom)

            #expect(store.reset() == .default)
            #expect(EditorConfigurationStore(defaults: defaults).load() == .default)
        }
    }

    @Test("editor configuration validates per field and falls back without discarding valid fields")
    func editorConfigurationPerFieldValidation() {
        TestEnvironment.withTestUserDefaults { defaults, _ in
            defaults.set(999.0, forKey: EditorConfigurationStore.fontSizeKey)
            defaults.set(-3, forKey: EditorConfigurationStore.tabWidthKey)
            defaults.set("not-a-bool", forKey: EditorConfigurationStore.wrapsLinesKey)

            let loaded = EditorConfigurationStore(defaults: defaults).load()
            #expect(loaded.fontSize == EditorConfiguration.default.fontSize)
            #expect(loaded.tabWidth == EditorConfiguration.default.tabWidth)
            #expect(loaded.wrapsLines == EditorConfiguration.default.wrapsLines)

            // A valid field is preserved even when a sibling field is invalid.
            defaults.set(18.0, forKey: EditorConfigurationStore.fontSizeKey)
            let partiallyValid = EditorConfigurationStore(defaults: defaults).load()
            #expect(partiallyValid.fontSize == 18)
            #expect(partiallyValid.tabWidth == EditorConfiguration.default.tabWidth)
        }
    }

    @Test("NoteTitle derivation follows the documented rule")
    func noteTitleDerivation() {
        #expect(NoteTitle.derive(from: "") == "Untitled")
        #expect(NoteTitle.derive(from: "\n\n   \n") == "Untitled")
        #expect(NoteTitle.derive(from: "\n# Heading here\nbody") == "Heading here")
        #expect(NoteTitle.derive(from: "  Padded title  \nbody") == "Padded title")
        let long = String(repeating: "x", count: 200)
        #expect(NoteTitle.derive(from: long).count == NoteTitle.maximumLength)
    }

    // MARK: - AppState composition-root integration (PHASE-02 wiring)

    @Test("launch loads the library; a new note is created and bound; selection persists")
    @MainActor
    func appStateCreatesAndBindsNotes() async throws {
        let root = try TestEnvironment.makeTempDirectory("appstate-create")
        let (defaults, suiteName) = TestEnvironment.makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let services = AppState.Services(storageRoot: root, userDefaultsSuiteName: suiteName)

        let state = AppState(services: services)
        await state.start()
        #expect(state.libraryStatus == .ready)
        #expect(state.notes.isEmpty)

        state.newNote()
        await state.waitForPendingOperations()
        #expect(state.notes.count == 1)
        let note = try #require(state.notes.first)
        #expect(state.selectedNoteID == note.id)
        #expect(state.editorText.isEmpty)
        #expect(state.editorCharacterCount == 0)
        #expect(state.statusMessage == nil)
        let bodyURL = DataStore.Paths(rootURL: root).notesDirectory.appendingPathComponent(note.fileName)
        #expect(FileManager.default.fileExists(atPath: bodyURL.path))

        // A fresh launch restores the library and the last selection from the same defaults suite.
        let relaunched = AppState(services: services)
        await relaunched.start()
        #expect(relaunched.notes.map(\.id) == [note.id])
        #expect(relaunched.selectedNoteID == note.id)
        await state.flushForTermination()
    }

    @Test("launch reconciliation adopts body files that are already on disk")
    @MainActor
    func appStateLaunchAdoptsStrayFiles() async throws {
        let root = try TestEnvironment.makeTempDirectory("appstate-adopt")
        let notesDirectory = DataStore.Paths(rootURL: root).notesDirectory
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try "Adopted title\n\nbody text".write(
            to: notesDirectory.appendingPathComponent("dropped-in.md"),
            atomically: true,
            encoding: .utf8
        )

        let state = AppState(services: TestEnvironment.makeServices(root: root))
        await state.start()
        #expect(state.notes.map(\.fileName) == ["dropped-in.md"])
        #expect(state.notes.first?.title == "Adopted title")
        #expect(state.statusMessage?.contains("adopted") == true)
        await state.flushForTermination()
    }

    @Test("a blocked storage root fails honestly and the explicit retry recovers")
    @MainActor
    func appStateStorageFailureAndRetry() async throws {
        let root = try TestEnvironment.makeTempDirectory("appstate-blocked")
        let blockedRoot = root.appendingPathComponent("blocked-root")
        try Data("this is a file, not a directory".utf8).write(to: blockedRoot)

        let state = AppState(services: TestEnvironment.makeServices(root: blockedRoot))
        await state.start()
        guard case .failed = state.libraryStatus else {
            Issue.record("expected a failed launch, got \(state.libraryStatus)")
            return
        }
        #expect(state.notes.isEmpty)
        #expect(state.statusMessage?.contains("Storage unavailable") == true)

        // Commands while failed must not crash and must not fabricate notes.
        state.newNote()
        await state.waitForPendingOperations()
        #expect(state.notes.isEmpty)

        // The user fixes the problem and retries explicitly.
        try FileManager.default.removeItem(at: blockedRoot)
        await state.retryStorageStartup()
        #expect(state.libraryStatus == .ready)
        state.newNote()
        await state.waitForPendingOperations()
        #expect(state.notes.count == 1)
        await state.flushForTermination()
    }

    @Test("a missing body is flagged, kept in the library, and recoverable in place")
    @MainActor
    func appStateMissingBodyRecovery() async throws {
        let root = try TestEnvironment.makeTempDirectory("appstate-missing")
        let state = AppState(services: TestEnvironment.makeServices(root: root))
        await state.start()
        state.newNote()
        await state.waitForPendingOperations()
        let note = try #require(state.notes.first)

        let bodyURL = DataStore.Paths(rootURL: root).notesDirectory.appendingPathComponent(note.fileName)
        try FileManager.default.removeItem(at: bodyURL)

        await state.selectNote(id: note.id)
        #expect(state.missingBodyNoteIDs == [note.id])
        #expect(state.editorText.isEmpty)
        #expect(state.notes.count == 1, "the record must survive a missing body")
        #expect(state.statusMessage?.contains("Could not read this note") == true)

        // Explicit recovery: the body reappears and the flag clears.
        try "restored body".write(to: bodyURL, atomically: true, encoding: .utf8)
        await state.selectNote(id: note.id)
        #expect(state.missingBodyNoteIDs.isEmpty)
        #expect(state.editorText == "restored body")
        #expect(state.statusMessage == nil)
        await state.flushForTermination()
    }

    @Test("selecting an unknown note reports instead of switching")
    @MainActor
    func appStateUnknownSelectionIsReported() async throws {
        let root = try TestEnvironment.makeTempDirectory("appstate-unknown")
        let state = AppState(services: TestEnvironment.makeServices(root: root))
        await state.start()

        await state.selectNote(id: "8a1c0e1e-0000-4000-8000-000000000000")
        #expect(state.selectedNoteID == nil)
        #expect(state.editorText.isEmpty)
        #expect(state.statusMessage?.contains("no longer in the library") == true)
        await state.flushForTermination()
    }
}
