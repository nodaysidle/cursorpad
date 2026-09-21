import Foundation
import SQLite3

// MARK: - CON-DATA-NOTEDOCUMENT

/// A single plain text note with metadata and a file reference.
///
/// Locked fields: id, title, fileName, createdAt, updatedAt, characterCount.
/// Retention: local until the user explicitly deletes it. Sensitivity: personal — note bodies and
/// titles never reach logs or diagnostics.
struct NoteDocument: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var fileName: String
    var createdAt: Date
    var updatedAt: Date
    var characterCount: Int
}

// MARK: - CON-DATA-EDITORCONFIGURATION

/// Editor preferences. Retained across launches; stored with versioned UserDefaults keys so a future
/// schema can migrate instead of silently reinterpreting stale values.
struct EditorConfiguration: Codable, Equatable, Sendable {
    var fontSize: Double
    var tabWidth: Int
    var wrapsLines: Bool

    static let `default` = EditorConfiguration(fontSize: 13, tabWidth: 4, wrapsLines: true)

    // Per-field validation ranges. Values outside these bounds are rejected, not clamped, so a
    // corrupt write never silently changes user intent.
    static let fontSizeRange: ClosedRange<Double> = 9...72
    static let tabWidthRange: ClosedRange<Int> = 1...16
}

/// Reads/writes `EditorConfiguration` with per-field validation, fallback and reset.
struct EditorConfigurationStore {
    static let keyPrefix = "cursorpad.config.editor.v1."
    static let fontSizeKey = keyPrefix + "fontSize"
    static let tabWidthKey = keyPrefix + "tabWidth"
    static let wrapsLinesKey = keyPrefix + "wrapsLines"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Loads each field independently: a single invalid field falls back to its default without
    /// discarding the other valid fields.
    func load() -> EditorConfiguration {
        var configuration = EditorConfiguration.default

        if let stored = defaults.object(forKey: Self.fontSizeKey) as? Double,
           EditorConfiguration.fontSizeRange.contains(stored) {
            configuration.fontSize = stored
        }
        if let stored = defaults.object(forKey: Self.tabWidthKey) as? Int,
           EditorConfiguration.tabWidthRange.contains(stored) {
            configuration.tabWidth = stored
        }
        if let stored = defaults.object(forKey: Self.wrapsLinesKey) as? Bool {
            configuration.wrapsLines = stored
        }

        return configuration
    }

    func save(_ configuration: EditorConfiguration) {
        defaults.set(configuration.fontSize, forKey: Self.fontSizeKey)
        defaults.set(configuration.tabWidth, forKey: Self.tabWidthKey)
        defaults.set(configuration.wrapsLines, forKey: Self.wrapsLinesKey)
    }

    /// Bounded correction path: drops every stored value and returns the locked defaults.
    @discardableResult
    func reset() -> EditorConfiguration {
        defaults.removeObject(forKey: Self.fontSizeKey)
        defaults.removeObject(forKey: Self.tabWidthKey)
        defaults.removeObject(forKey: Self.wrapsLinesKey)
        return .default
    }
}

/// Derives a display title from note text: the first non-empty line with leading heading marks
/// stripped, capped at `maximumLength`; `Untitled` when the note has no usable text.
enum NoteTitle {
    static let untitled = "Untitled"
    static let maximumLength = 60

    static func derive(from text: String) -> String {
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            while line.hasPrefix("#") {
                line.removeFirst()
            }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            return String(line.prefix(maximumLength))
        }
        return untitled
    }
}

/// Timestamp precision rules for stored metadata.
///
/// `updated_at` is persisted as a SQLite `REAL`, so every timestamp makes a
/// `Date -> timeIntervalSince1970 -> Date` round trip. Measured on APFS, ~47% of file
/// modification timestamps do not survive that round trip exactly: the result differs by one ulp
/// (±1.19e-7 s) in either direction. A strict `file.mtime > metadata.updated_at` comparison
/// therefore reports "the file is newer" for a file nobody touched, which made launch
/// reconciliation non-idempotent (a spurious refresh on every second pass, dependent on the
/// timestamp bits and thus intermittent).
///
/// Two rules make the comparison deterministic and independent of that noise:
/// 1. Every persisted timestamp is normalized to whole milliseconds, and comparisons are made on
///    normalized `TimeInterval` values, so ±1 ulp noise can never flip the outcome.
/// 2. Bodies written by the app are additionally stamped so the file modification date equals the
///    recorded `updatedAt`; a file the app wrote is never classified as newer than its own record.
enum StorageTimestamp {
    /// Storage granularity for note metadata: 1 ms. Noise below this is not an edit.
    static let precision: TimeInterval = 0.001

    static func normalizeInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return interval }
        return (interval * 1000).rounded() / 1000
    }

    static func normalize(_ date: Date) -> Date {
        let interval = date.timeIntervalSince1970
        let normalized = normalizeInterval(interval)
        return normalized == interval ? date : Date(timeIntervalSince1970: normalized)
    }

    /// True only when the file is newer than the recorded metadata by at least the storage
    /// precision. Sub-millisecond differences are treated as the same instant.
    static func isFileNewerThanMetadata(_ fileDate: Date, metadata: Date) -> Bool {
        normalizeInterval(fileDate.timeIntervalSince1970) > normalizeInterval(metadata.timeIntervalSince1970)
    }
}

// MARK: - DataStore

/// Owns SQLite metadata, Markdown body files and launch reconciliation.
///
/// SQLite strategy (locked): the raw handle is confined to this actor, opened with a 5 second busy
/// timeout, WAL journaling, `synchronous = NORMAL`, and schema migration guarded by `user_version`
/// inside a transaction. `import SQLite3` appears only in this file.
actor DataStore {
    // MARK: Nested types

    struct Paths: Sendable, Equatable {
        let rootURL: URL

        init(rootURL: URL) {
            self.rootURL = rootURL
        }

        var notesDirectory: URL {
            AppStoragePaths.notesDirectory(root: rootURL)
        }

        var databaseURL: URL {
            AppStoragePaths.databaseURL(root: rootURL)
        }

        static func `default`(fileManager: FileManager = .default) -> Paths {
            Paths(rootURL: AppStoragePaths.defaultRootURL(fileManager: fileManager))
        }
    }

    enum DataStoreError: Error, Equatable, CustomStringConvertible {
        case notOpen
        case sqlite(String)
        case fileSystem(String)
        case invalidRecord(String)

        var description: String {
            switch self {
            case .notOpen: "data store is not open"
            case .sqlite(let message): "sqlite: \(message)"
            case .fileSystem(let message): "file system: \(message)"
            case .invalidRecord(let message): "invalid record: \(message)"
            }
        }
    }

    /// Result of a launch reconciliation pass.
    struct ReconcileReport: Sendable, Equatable {
        var adopted: [NoteDocument] = []
        var refreshed: [NoteDocument] = []
        var markedMissing: [String] = []
        var skippedInvalidFiles: [String] = []
        var invalidRecordCount: Int = 0
    }

    /// Read-only view of the library used by the sidebar and the status line.
    struct LibrarySnapshot: Sendable, Equatable {
        var notes: [NoteDocument] = []
        var missingBodyIDs: [String] = []
        var invalidRecordCount: Int = 0
    }

    private struct RawRow {
        let document: NoteDocument?
        let fileName: String
        let bodyMissing: Bool
    }

    // MARK: State

    static let schemaVersion: Int32 = 1
    static let busyTimeoutMilliseconds: Int32 = 5000

    nonisolated let paths: Paths

    private var handle: OpaquePointer?
    private var isOpen = false

    init(paths: Paths) {
        self.paths = paths
    }

    // MARK: - Lifecycle

    func open() throws {
        guard !isOpen else { return }
        try createDirectoriesIfNeeded()

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(paths.databaseURL.path, &database, flags, nil)

        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite error \(result)"
            if let database { sqlite3_close_v2(database) }
            throw DataStoreError.sqlite(message)
        }

        do {
            sqlite3_busy_timeout(database, Self.busyTimeoutMilliseconds)
            handle = database
            try execute("PRAGMA journal_mode=WAL;")
            try execute("PRAGMA synchronous=NORMAL;")
            try migrate()
            isOpen = true
        } catch {
            handle = nil
            sqlite3_close_v2(database)
            throw error
        }
    }

    func close() {
        if let handle {
            sqlite3_close_v2(handle)
        }
        handle = nil
        isOpen = false
    }

    // MARK: - Queries

    /// All valid notes, newest update first. Invalid records are excluded, never repaired silently.
    func notes() throws -> [NoteDocument] {
        try librarySnapshot().notes
    }

    func librarySnapshot() throws -> LibrarySnapshot {
        try requireOpen()
        let rows = try loadRawRows()
        return LibrarySnapshot(
            notes: rows.compactMap(\.document),
            missingBodyIDs: rows.filter(\.bodyMissing).compactMap { $0.document?.id }.sorted(),
            invalidRecordCount: rows.filter { $0.document == nil }.count
        )
    }

    func note(id: String) throws -> NoteDocument? {
        try requireOpen()
        let statement = try prepare("SELECT id, title, file_name, created_at, updated_at, character_count, body_missing FROM notes WHERE id = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }
        try bindText(id, at: 1, in: statement)
        guard try step(statement) else { return nil }
        return try decodeNote(statement)
    }

    // MARK: - Mutations

    /// Creates one note: lowercase UUID identity, `<id>.md` file name, atomically written empty body.
    /// The file is rolled back if the metadata insert fails, so a failure never leaves an orphan.
    func createNote(at date: Date = Date()) throws -> NoteDocument {
        try requireOpen()
        let identifier = UUID().uuidString.lowercased()
        let stamp = StorageTimestamp.normalize(date)
        let document = NoteDocument(
            id: identifier,
            title: NoteTitle.untitled,
            fileName: "\(identifier).md",
            createdAt: stamp,
            updatedAt: stamp,
            characterCount: 0
        )
        do {
            try writeBody(fileName: document.fileName, text: "", stampedAt: stamp)
            try insert(document, bodyMissing: false)
        } catch {
            try? FileManager.default.removeItem(at: bodyURL(fileName: document.fileName))
            throw error
        }
        return document
    }

    func updateMetadata(_ note: NoteDocument) throws {
        try requireOpen()
        guard let handle else { throw DataStoreError.notOpen }
        let statement = try prepare("UPDATE notes SET title = ?, file_name = ?, created_at = ?, updated_at = ?, character_count = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        try bindText(note.title, at: 1, in: statement)
        try bindText(note.fileName, at: 2, in: statement)
        try bindDouble(StorageTimestamp.normalizeInterval(note.createdAt.timeIntervalSince1970), at: 3, in: statement)
        try bindDouble(StorageTimestamp.normalizeInterval(note.updatedAt.timeIntervalSince1970), at: 4, in: statement)
        try bindInt(note.characterCount, at: 5, in: statement)
        try bindText(note.id, at: 6, in: statement)
        _ = try step(statement)
        guard sqlite3_changes(handle) > 0 else {
            throw DataStoreError.invalidRecord("unknown note id \(note.id)")
        }
    }

    /// Refreshes derived metadata (title, character count, timestamp) from the body text.
    @discardableResult
    func refreshMetadata(id: String, fromText text: String, updatedAt: Date) throws -> NoteDocument {
        guard var document = try note(id: id) else {
            throw DataStoreError.invalidRecord("unknown note id \(id)")
        }
        document.title = NoteTitle.derive(from: text)
        document.characterCount = text.count
        document.updatedAt = StorageTimestamp.normalize(updatedAt)
        try updateMetadata(document)
        return document
    }

    func setBodyMissing(id: String, _ missing: Bool) throws {
        try requireOpen()
        guard let handle else { throw DataStoreError.notOpen }
        let statement = try prepare("UPDATE notes SET body_missing = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        try bindInt(missing ? 1 : 0, at: 1, in: statement)
        try bindText(id, at: 2, in: statement)
        _ = try step(statement)
        guard sqlite3_changes(handle) > 0 else {
            throw DataStoreError.invalidRecord("unknown note id \(id)")
        }
    }

    /// Removes only the metadata row. The caller moves the body file to Trash first so a metadata
    /// failure cannot destroy the user's text.
    func deleteNote(id: String) throws {
        try requireOpen()
        guard let handle else { throw DataStoreError.notOpen }
        let statement = try prepare("DELETE FROM notes WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        try bindText(id, at: 1, in: statement)
        _ = try step(statement)
        guard sqlite3_changes(handle) > 0 else {
            throw DataStoreError.invalidRecord("unknown note id \(id)")
        }
    }

    // MARK: - Bodies

    nonisolated func bodyURL(fileName: String) -> URL {
        paths.notesDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    func readBody(fileName: String) throws -> String {
        let url = bodyURL(fileName: fileName)
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw DataStoreError.fileSystem("unable to read \(fileName): \(error.localizedDescription)")
        }
    }

    /// Atomic UTF-8 body write (`NSDataWritingAtomic` semantics) used for note creation, explicit
    /// recovery and the autosave path. Returns the normalized timestamp recorded for the write and
    /// stamps the file's modification date to it (best effort).
    ///
    /// Callers must record the returned stamp in the same pass — `refreshMetadata(updatedAt:)` on
    /// the autosave/recovery paths, the row itself on `createNote` — so the file and its metadata
    /// describe the same instant and reconciliation never classifies the app's own write as a
    /// newer external edit.
    @discardableResult
    func writeBody(fileName: String, text: String, stampedAt: Date = Date()) throws -> Date {
        let stamp = StorageTimestamp.normalize(stampedAt)
        let url = bodyURL(fileName: fileName)
        try writeAtomically(Data(text.utf8), to: url)
        stampModificationDate(stamp, at: url)
        return stamp
    }

    /// Best effort: reconciliation normalizes timestamps to milliseconds before deciding "newer",
    /// so a failed stamp degrades to the normalization rule instead of a false refresh.
    private func stampModificationDate(_ date: Date, at url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    // MARK: - Reconciliation

    /// Launch reconciliation: adopts unknown body files, refreshes metadata when a file is newer,
    /// marks rows whose body disappeared, and reports unreadable files. Invalid records and their
    /// files are preserved untouched.
    func reconcile() throws -> ReconcileReport {
        try requireOpen()
        var report = ReconcileReport()
        let rows = try loadRawRows()
        report.invalidRecordCount = rows.filter { $0.document == nil }.count

        var knownFileNames = Set(rows.map(\.fileName))
        var rowByFileName: [String: RawRow] = [:]
        for row in rows where row.document != nil {
            rowByFileName[row.fileName] = row
        }

        let fileManager = FileManager.default
        let directoryNames: [String]
        do {
            directoryNames = try fileManager.contentsOfDirectory(atPath: paths.notesDirectory.path)
                .filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }
                .sorted()
        } catch {
            throw DataStoreError.fileSystem("unable to list notes directory: \(error.localizedDescription)")
        }

        for fileName in directoryNames {
            let url = paths.notesDirectory.appendingPathComponent(fileName, isDirectory: false)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let modifiedAt = values?.contentModificationDate ?? Date()
            let createdAt = values?.creationDate ?? modifiedAt

            if let row = rowByFileName[fileName], let document = row.document {
                let fileIsNewer = StorageTimestamp.isFileNewerThanMetadata(modifiedAt, metadata: document.updatedAt)
                guard row.bodyMissing || fileIsNewer else { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    report.skippedInvalidFiles.append(fileName)
                    continue
                }
                let refreshed = try refreshMetadata(id: document.id, fromText: text, updatedAt: max(modifiedAt, document.updatedAt))
                if row.bodyMissing {
                    try setBodyMissing(id: document.id, false)
                }
                report.refreshed.append(refreshed)
            } else if knownFileNames.contains(fileName) {
                // Owned by an invalid row: preserve it rather than adopting a duplicate identity.
                continue
            } else {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    report.skippedInvalidFiles.append(fileName)
                    continue
                }
                let stem = (fileName as NSString).deletingPathExtension
                var identifier = UUID().uuidString.lowercased()
                if let uuid = UUID(uuidString: stem), stem == uuid.uuidString.lowercased(), try note(id: stem) == nil {
                    identifier = stem
                }
                let document = NoteDocument(
                    id: identifier,
                    title: NoteTitle.derive(from: text),
                    fileName: fileName,
                    createdAt: min(createdAt, modifiedAt),
                    updatedAt: modifiedAt,
                    characterCount: text.count
                )
                try insert(document, bodyMissing: false)
                knownFileNames.insert(fileName)
                report.adopted.append(document)
            }
        }

        let fileNamesOnDisk = Set(directoryNames)
        for row in rows {
            guard let document = row.document, !fileNamesOnDisk.contains(document.fileName), !row.bodyMissing else { continue }
            try setBodyMissing(id: document.id, true)
            report.markedMissing.append(document.id)
        }

        return report
    }

    // MARK: - Test seams (used only by focused tests to simulate damaged or foreign state)

    /// Runs raw SQL against the open database. Test-only: production code always uses the typed API.
    func runRawSQLForTesting(_ sql: String) throws {
        try requireOpen()
        try execute(sql)
    }

    /// Returns the first column of the first row for a raw query. Test-only.
    func rawQuerySingleValueForTesting(_ sql: String) throws -> String? {
        try querySingleValue(sql)
    }

    // MARK: - SQLite plumbing

    /// SQLITE_TRANSIENT: lets SQLite copy bound strings instead of retaining Swift buffers.
    private var transientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private func requireOpen() throws {
        guard isOpen else { throw DataStoreError.notOpen }
    }

    private func createDirectoriesIfNeeded() throws {
        let manager = FileManager.default
        for directory in [paths.rootURL, paths.notesDirectory] {
            do {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw DataStoreError.fileSystem("unable to create \(directory.path): \(error.localizedDescription)")
            }
        }
    }

    private func migrate() throws {
        let storedVersion = Int(try querySingleValue("PRAGMA user_version;") ?? "0") ?? 0
        if storedVersion == 0 {
            try inTransaction {
                try execute(Self.schemaSQL)
                try execute("PRAGMA user_version = \(Self.schemaVersion);")
            }
        } else if Int32(storedVersion) > Self.schemaVersion {
            throw DataStoreError.sqlite("database schema version \(storedVersion) is newer than supported version \(Self.schemaVersion)")
        }
    }

    private static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        file_name TEXT NOT NULL UNIQUE,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL,
        character_count INTEGER NOT NULL DEFAULT 0,
        body_missing INTEGER NOT NULL DEFAULT 0
    );
    """

    private func inTransaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let result = try body()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard let handle else { throw DataStoreError.notOpen }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "sqlite error \(result)"
            if let errorMessage {
                sqlite3_free(UnsafeMutableRawPointer(errorMessage))
            }
            throw DataStoreError.sqlite(message)
        }
    }

    private func querySingleValue(_ sql: String) throws -> String? {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard try step(statement) else { return nil }
        if let text = columnText(statement, 0) {
            return text
        }
        return String(sqlite3_column_int64(statement, 0))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let handle else { throw DataStoreError.notOpen }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DataStoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        return statement
    }

    @discardableResult
    private func step(_ statement: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            guard let handle else { throw DataStoreError.notOpen }
            throw DataStoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func bindText(_ value: String, at index: Int32, in statement: OpaquePointer) throws {
        let result = value.withCString { sqlite3_bind_text(statement, index, $0, -1, transientDestructor) }
        guard result == SQLITE_OK else { throw DataStoreError.sqlite(bindFailureMessage()) }
    }

    private func bindDouble(_ value: Double, at index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw DataStoreError.sqlite(bindFailureMessage())
        }
    }

    private func bindInt(_ value: Int, at index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_int64(statement, index, Int64(value)) == SQLITE_OK else {
            throw DataStoreError.sqlite(bindFailureMessage())
        }
    }

    private func bindFailureMessage() -> String {
        guard let handle else { return "bind failed" }
        return String(cString: sqlite3_errmsg(handle))
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func loadRawRows() throws -> [RawRow] {
        let statement = try prepare("SELECT id, title, file_name, created_at, updated_at, character_count, body_missing FROM notes ORDER BY updated_at DESC, id ASC;")
        defer { sqlite3_finalize(statement) }
        var rows: [RawRow] = []
        while try step(statement) {
            let bodyMissing = sqlite3_column_int(statement, 6) != 0
            if let document = try decodeNote(statement) {
                rows.append(RawRow(document: document, fileName: document.fileName, bodyMissing: bodyMissing))
            } else {
                rows.append(RawRow(document: nil, fileName: columnText(statement, 2) ?? "", bodyMissing: bodyMissing))
            }
        }
        return rows
    }

    /// Rejects invalid or incomplete records without touching the last valid state.
    private func decodeNote(_ statement: OpaquePointer) throws -> NoteDocument? {
        guard let rawIdentifier = columnText(statement, 0) else { return nil }
        let identifier = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              let uuid = UUID(uuidString: identifier),
              identifier == uuid.uuidString.lowercased() else { return nil }

        guard let rawFileName = columnText(statement, 2) else { return nil }
        let fileName = rawFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fileName.hasSuffix(".md"), !fileName.contains("/"), !fileName.hasPrefix(".") else { return nil }

        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        guard createdAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970.isFinite else { return nil }

        let title = columnText(statement, 1) ?? NoteTitle.untitled
        let characterCount = Int(sqlite3_column_int64(statement, 5))

        return NoteDocument(
            id: identifier,
            title: title,
            fileName: fileName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            characterCount: max(0, characterCount)
        )
    }

    private func insert(_ document: NoteDocument, bodyMissing: Bool) throws {
        let statement = try prepare("INSERT INTO notes (id, title, file_name, created_at, updated_at, character_count, body_missing) VALUES (?, ?, ?, ?, ?, ?, ?);")
        defer { sqlite3_finalize(statement) }
        try bindText(document.id, at: 1, in: statement)
        try bindText(document.title, at: 2, in: statement)
        try bindText(document.fileName, at: 3, in: statement)
        try bindDouble(StorageTimestamp.normalizeInterval(document.createdAt.timeIntervalSince1970), at: 4, in: statement)
        try bindDouble(StorageTimestamp.normalizeInterval(document.updatedAt.timeIntervalSince1970), at: 5, in: statement)
        try bindInt(document.characterCount, at: 6, in: statement)
        try bindInt(bodyMissing ? 1 : 0, at: 7, in: statement)
        _ = try step(statement)
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw DataStoreError.fileSystem("unable to write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
