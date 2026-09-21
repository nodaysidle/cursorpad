import Foundation
import Testing

@testable import Cursorpad

// MARK: - Shared test helpers (package layout, repo-local temp directories, source readers)

/// Absolute path of the package root, derived from this source file's compile-time path.
func packageRootURL() -> URL {
    URL(fileURLWithPath: #filePath)          // <root>/Tests/CursorpadTests/ContractTests.swift
        .deletingLastPathComponent()          // <root>/Tests/CursorpadTests
        .deletingLastPathComponent()          // <root>/Tests
        .deletingLastPathComponent()          // <root>
}

/// Reads a package-relative source file as UTF-8 text.
func readPackageFile(_ relativePath: String) throws -> String {
    let url = packageRootURL().appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}

enum TestEnvironment {
    /// All test scratch state stays inside the package's build directory — nothing outside the repo.
    static var scratchRoot: URL {
        packageRootURL().appendingPathComponent(".build/test-tmp", isDirectory: true)
    }

    static func makeTempDirectory(_ label: String) throws -> URL {
        let url = scratchRoot.appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeServices(root: URL, debounceInterval: Duration = .milliseconds(250)) -> AppState.Services {
        AppState.Services(storageRoot: root, userDefaultsSuiteName: "cursorpad.tests.\(UUID().uuidString)", debounceInterval: debounceInterval)
    }

    /// Fresh, isolated UserDefaults suite. Tests must clear it when done — see `withTestUserDefaults`.
    static func makeUserDefaults(suiteName: String = "cursorpad.tests.\(UUID().uuidString)") -> (defaults: UserDefaults, suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return (defaults, suiteName)
    }

    /// Runs `body` with an isolated UserDefaults suite and removes the persistent domain afterwards
    /// so no state leaks outside the repository.
    static func withTestUserDefaults<T>(_ body: (UserDefaults, String) throws -> T) rethrows -> T {
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        return try body(defaults, suiteName)
    }
}

// MARK: - Contract validation (pure functions with real teeth, exercised against real + drifted input)

enum FoundationContract {
    static let requiredPaths = [
        "Package.swift",
        "Sources/Cursorpad/CursorpadApp.swift",
        "Sources/Cursorpad/AppState.swift",
        "Tests/CursorpadTests/ContractTests.swift"
    ]

    enum Violation: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case drift(String)

        var description: String {
            switch self {
            case .missing(let path): "missing required foundation path: \(path)"
            case .drift(let detail): "foundation drift: \(detail)"
            }
        }
    }

    /// Validates the locked Package.swift contract: tools 6.0, macOS 14, executable product/target
    /// `Cursorpad`, Swift 6 language mode, sqlite3 link, no external dependencies.
    static func validatePackageManifest(_ source: String) throws {
        let required = [
            "// swift-tools-version: 6.0",
            ".macOS(.v14)",
            ".executable(name: \"Cursorpad\", targets: [\"Cursorpad\"])",
            ".executableTarget(",
            "name: \"Cursorpad\"",
            "path: \"Sources/Cursorpad\"",
            "swiftLanguageMode(.v6)",
            ".linkedLibrary(\"sqlite3\")",
            "name: \"CursorpadTests\"",
            "path: \"Tests/CursorpadTests\""
        ]
        for token in required where !source.contains(token) {
            throw Violation.drift("Package.swift is missing `\(token)`")
        }
        if source.contains(".package(") {
            throw Violation.drift("Package.swift declares an external package dependency")
        }
    }

    /// Validates the frozen app entry surface that `CursorpadApp.swift` must keep through PHASE-09.
    static func validateAppEntrySurface(_ source: String) throws {
        let required = [
            "@main",
            "WindowGroup",
            "@NSApplicationDelegateAdaptor(AppDelegate.self)",
            "AppRootView(state: state)",
            "CommandGroup(replacing: .newItem)",
            "CommandGroup(replacing: .printItem)",
            "CommandGroup(replacing: .sidebar)",
            ".keyboardShortcut(\"n\", modifiers: .command)",
            ".keyboardShortcut(\"p\", modifiers: .command)",
            ".keyboardShortcut(\"k\", modifiers: .command)",
            ".keyboardShortcut(\"b\", modifiers: .command)",
            "state.newNote()",
            "state.presentCommandPalette()",
            "state.toggleSidebar()",
            "func applicationShouldTerminate(",
            ".terminateLater",
            "terminationFlushHandler"
        ]
        for token in required where !source.contains(token) {
            throw Violation.drift("CursorpadApp.swift is missing `\(token)`")
        }
        // Command + P must not remain bound to the system Print item.
        if source.contains("CommandGroup(replacing: .printItem) {") && source.contains("printDocument") {
            throw Violation.drift("CursorpadApp.swift still forwards the system Print action")
        }
    }
}

// MARK: - Tests

@Suite("ContractTests")
struct ContractTests {
    @Test("locked identity constants")
    func identityConstants() {
        #expect(AppIdentity.bundleIdentifier == "com.cursorpad.app")
        #expect(AppIdentity.displayName == "CursorPad")
        #expect(AppIdentity.executableName == "Cursorpad")
        #expect(AppIdentity.minimumSystemVersion == "14.0")
        #expect(AppIdentity.version == "1.0.0")
        #expect(AppIdentity.build == "1")
    }

    @Test("foundation files exist at the exact declared paths")
    func foundationFilesExist() throws {
        for relativePath in FoundationContract.requiredPaths {
            let url = packageRootURL().appendingPathComponent(relativePath)
            #expect(FileManager.default.fileExists(atPath: url.path), "missing \(relativePath)")
        }
    }

    @Test("Package.swift keeps the locked manifest contract")
    func packageManifestContract() throws {
        let source = try readPackageFile("Package.swift")
        try FoundationContract.validatePackageManifest(source)
    }

    @Test("Package.swift validator actually rejects drift")
    func packageManifestValidatorRejectsDrift() throws {
        let source = try readPackageFile("Package.swift")
        // Dropping the macOS 14 platform lock must be detected.
        let staleTarget = source.replacingOccurrences(of: ".macOS(.v14)", with: ".macOS(.v13)")
        #expect(throws: FoundationContract.Violation.self) {
            try FoundationContract.validatePackageManifest(staleTarget)
        }
        // Adding an external dependency must be detected.
        let withDependency = source.replacingOccurrences(
            of: "targets: [",
            with: "dependencies: [.package(url: \"https://example.com/x\", from: \"1.0.0\")],\n    targets: ["
        )
        #expect(throws: FoundationContract.Violation.self) {
            try FoundationContract.validatePackageManifest(withDependency)
        }
    }

    @Test("CursorpadApp.swift keeps the frozen entry surface")
    func appEntrySurfaceContract() throws {
        let source = try readPackageFile("Sources/Cursorpad/CursorpadApp.swift")
        try FoundationContract.validateAppEntrySurface(source)
    }

    @Test("app entry validator actually rejects drift")
    func appEntryValidatorRejectsDrift() throws {
        let source = try readPackageFile("Sources/Cursorpad/CursorpadApp.swift")
        let withoutPrintRemoval = source.replacingOccurrences(of: "CommandGroup(replacing: .printItem) { }", with: "")
        #expect(throws: FoundationContract.Violation.self) {
            try FoundationContract.validateAppEntrySurface(withoutPrintRemoval)
        }
        let wrongShortcut = source.replacingOccurrences(of: ".keyboardShortcut(\"k\", modifiers: .command)", with: ".keyboardShortcut(\"s\", modifiers: .command)")
        #expect(throws: FoundationContract.Violation.self) {
            try FoundationContract.validateAppEntrySurface(wrongShortcut)
        }
    }

    @Test("app state actions are honest and safe before launch")
    @MainActor
    func appStatePreLaunchBehavior() async throws {
        let root = try TestEnvironment.makeTempDirectory("contracts")
        let state = AppState(services: TestEnvironment.makeServices(root: root))

        #expect(state.isSidebarVisible)
        state.toggleSidebar()
        #expect(!state.isSidebarVisible)
        state.toggleSidebar()
        #expect(state.isSidebarVisible)

        #expect(!state.isCommandPalettePresented)
        state.presentCommandPalette()
        #expect(state.isCommandPalettePresented)
        let focusRequestsBefore = state.editorFocusRequests
        state.dismissCommandPalette()
        #expect(!state.isCommandPalettePresented)
        #expect(state.editorFocusRequests == focusRequestsBefore + 1)

        // Creating a note before storage services are running must not crash and must report status
        // instead of fabricating a note.
        state.newNote()
        #expect(state.statusMessage != nil)

        await state.start()
        await state.flushForTermination()
    }

    @Test("storage paths follow the locked Application Support layout")
    func lockedStorageLayout() {
        let root = URL(fileURLWithPath: "/tmp/example-root")
        #expect(AppStoragePaths.notesDirectory(root: root).lastPathComponent == "Notes")
        #expect(AppStoragePaths.databaseURL(root: root).lastPathComponent == "CursorPad.sqlite3")
        #expect(AppStoragePaths.defaultRootURL().lastPathComponent == "CursorPad")
        #expect(AppStoragePaths.defaultRootURL().deletingLastPathComponent().lastPathComponent == "Application Support")
    }
}
