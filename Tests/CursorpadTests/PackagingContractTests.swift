import Foundation
import Testing

@testable import Cursorpad

// MARK: - Packaging contracts (CON-PACKAGING-RELEASE, CON-SECURITY-BOUNDARY)
//
// These checks read the *source inputs* of packaging — the script, the Info.plist, the
// entitlements, the icon and the user guide — and the *contracts* they must satisfy. They never
// require a previously produced `dist/` artifact: only the optional bundle/DMG checks look at
// `dist/`, and they pass silently when nothing has been packaged yet.

enum PackagingContract {
    /// The declared PHASE-09 packaging inputs (TASK-09-PACKAGING "Files to create" + root guide).
    static let requiredInputPaths = [
        "Scripts/package_app.sh",
        "Resources/Info.plist",
        "Resources/App.entitlements",
        "Resources/AppIcon.icns",
        "USERGUIDE.md"
    ]

    /// Artifact paths locked by CON-PACKAGING-RELEASE / AGENTS.md.
    static let lockedArtifactPaths = [
        "dist/CursorPad.app",
        "dist/CursorPad.dmg"
    ]

    enum Violation: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case drift(String)

        var description: String {
            switch self {
            case .missing(let detail): "missing packaging input: \(detail)"
            case .drift(let detail): "packaging drift: \(detail)"
            }
        }
    }

    // MARK: Info.plist

    static func parsePlist(_ data: Data) throws -> [String: Any] {
        do {
            let parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dictionary = parsed as? [String: Any] else {
                throw Violation.drift("plist root is not a dictionary")
            }
            return dictionary
        } catch let violation as Violation {
            throw violation
        } catch {
            throw Violation.drift("plist is not a readable property list: \(error)")
        }
    }

    /// Locks the bundle identity, the deployment minimum and the declared privacy surface.
    static func validateInfoPlist(_ plist: [String: Any]) throws {
        let requiredStrings: [String: String] = [
            "CFBundleIdentifier": AppIdentity.bundleIdentifier,
            "CFBundleName": AppIdentity.displayName,
            "CFBundleDisplayName": AppIdentity.displayName,
            "CFBundleExecutable": AppIdentity.executableName,
            "CFBundleIconFile": "AppIcon",
            "CFBundlePackageType": "APPL",
            "CFBundleSignature": "????",
            "CFBundleShortVersionString": AppIdentity.version,
            "CFBundleVersion": AppIdentity.build,
            "LSMinimumSystemVersion": AppIdentity.minimumSystemVersion,
            "NSMicrophoneUsageDescription": "CursorPad uses the microphone only while you explicitly record dictation."
        ]
        for (key, expected) in requiredStrings {
            guard let actual = plist[key] as? String else {
                throw Violation.missing("Info.plist key \(key)")
            }
            guard actual == expected else {
                throw Violation.drift("Info.plist \(key) must be '\(expected)', found '\(actual)'")
            }
        }

        guard plist["LSMinimumSystemVersion"] as? String == "14.0" else {
            throw Violation.drift("Info.plist LSMinimumSystemVersion must be 14.0 (TRD-locked deployment floor)")
        }
        guard plist["NSHighResolutionCapable"] as? Bool == true else {
            throw Violation.missing("Info.plist NSHighResolutionCapable = true")
        }
        guard plist["LSUIElement"] as? Bool == false else {
            throw Violation.drift("Info.plist LSUIElement must be false (Dock-first application)")
        }
        guard plist["NSPrincipalClass"] as? String == "NSApplication" else {
            throw Violation.missing("Info.plist NSPrincipalClass = NSApplication")
        }
    }

    // MARK: Entitlements

    /// The only entitlements source, and an empty dictionary for the local unsandboxed build.
    static func validateEntitlements(_ raw: String, parsed: [String: Any]) throws {
        guard parsed.isEmpty else {
            throw Violation.drift("Resources/App.entitlements must be an empty dictionary, found \(parsed.keys.sorted())")
        }
        let forbidden = [
            "com.apple.security.app-sandbox",
            "com.apple.security.files.user-selected.read-write",
            "com.apple.security.files.all",
            "com.apple.security.automation.apple-events",
            "com.apple.security.get-task-allow",
            "com.apple.security.network.client",
            "com.apple.security.device.audio-input"
        ]
        for token in forbidden where raw.contains(token) {
            throw Violation.drift("entitlements request '\(token)'; the local build stays unsandboxed and empty")
        }
        guard raw.contains("<plist version=\"1.0\">") && raw.contains("</plist>") else {
            throw Violation.drift("entitlements must be an XML plist")
        }
    }

    // MARK: Packaging script

    /// Required commands and invariants of the sole packaging authority.
    static func validatePackagingScript(_ source: String) throws {
        let required = [
            "#!/bin/bash",
            "set -euo pipefail",
            // Release build, and a failed build must be fatal.
            "swift build -c release --arch arm64",
            "if ! swift build -c release --arch arm64; then",
            "fatal \"release build failed",
            // Release executable discovery is asked of SwiftPM itself.
            "swift build -c release --arch arm64 --show-bin-path",
            // arm64 Mach-O gate.
            "file -b",
            "Mach-O 64-bit executable arm64",
            "lipo -archs",
            "\"arm64\"",
            // Bundle assembly.
            "dist/CursorPad.app",
            "dist/CursorPad.dmg",
            "Contents/MacOS",
            "Contents/Resources",
            "Contents/PkgInfo",
            "APPL????",
            "AppIcon.icns",
            "USERGUIDE.md",
            "App.entitlements",
            "Info.plist",
            // Signing, mandatory strict verification and DMG creation.
            "codesign",
            "--entitlements",
            "codesign --verify --deep --strict --verbose=2",
            "if ! codesign --verify --deep --strict --verbose=2",
            "hdiutil create",
            "hdiutil verify",
            "if ! hdiutil verify",
            // Identity read back from the assembled bundle.
            "/usr/libexec/PlistBuddy",
            "CFBundleIdentifier",
            "LSMinimumSystemVersion"
        ]
        for token in required where !source.contains(token) {
            throw Violation.drift("Scripts/package_app.sh is missing `\(token)`")
        }

        // The build result may never be swallowed.
        if source.contains("swift build -c release --arch arm64 ||") {
            throw Violation.drift("Scripts/package_app.sh ignores a failed release build")
        }
        if source.contains("set +e") {
            throw Violation.drift("Scripts/package_app.sh disables error handling")
        }

        // Install/launch is opt-in only: the default run stops after the verified DMG.
        guard source.contains("if [[ \"${CURSORPAD_INSTALL}\" == \"1\" ]]; then") else {
            throw Violation.drift("install/launch is not guarded behind the --install flag")
        }
        if source.range(of: "open -b") != nil && !source.contains("--install") {
            throw Violation.drift("Scripts/package_app.sh launches the app without an explicit opt-in")
        }

        // No network, no elevation, no version control side effects, no user-data access.
        let forbidden = ["sudo", "git ", "git\t", "curl ", "wget ", "ssh ", "launchctl", "defaults write",
                         "npm ", "pip ", "nc ", "Application Support", "sqlite"]
        for token in forbidden where source.contains(token) {
            throw Violation.drift("Scripts/package_app.sh must not reference `\(token)`")
        }
        if source.contains("|| true") && source.contains("swift build") {
            throw Violation.drift("Scripts/package_app.sh may not mask the release build result")
        }

        // The artifact paths are asserted, not merely assumed.
        guard source.contains("EXPECTED_APP_PATH") && source.contains("EXPECTED_DMG_PATH") else {
            throw Violation.drift("Scripts/package_app.sh does not assert the locked dist/ paths")
        }
    }

    // MARK: User guide

    static func validateUserGuide(_ text: String) throws {
        let required = [
            "# CursorPad",
            "macOS 14",
            "com.cursorpad.app",
            "⌘N", "⌘P", "⌘K", "⌘B",
            "Application Support/CursorPad",
            "CursorPad.sqlite3",
            "Trash",
            "codesign --verify --deep --strict",
            "dist/CursorPad.dmg",
            "telemetry",
            "Uninstall"
        ]
        for token in required where !text.contains(token) {
            throw Violation.drift("USERGUIDE.md is missing `\(token)`")
        }
        guard text.count > 2_000 else {
            throw Violation.drift("USERGUIDE.md is too thin to be a real guide (\(text.count) characters)")
        }
    }

    // MARK: Icon

    /// Structural icns validation: header, chunk table and the modern high-resolution entries.
    static func validateIcon(_ data: Data) throws -> [String] {
        guard data.count > 8, data.prefix(4) == Data("icns".utf8) else {
            throw Violation.drift("Resources/AppIcon.icns does not start with the icns magic")
        }
        let declaredLength = Int(data[4]) << 24 | Int(data[5]) << 16 | Int(data[6]) << 8 | Int(data[7])
        guard declaredLength == data.count else {
            throw Violation.drift("icns declares \(declaredLength) bytes but the file is \(data.count)")
        }

        var types: [String] = []
        var offset = 8
        while offset + 8 <= data.count {
            let typeStart = data.startIndex + offset
            guard let type = String(data: data[typeStart..<(typeStart + 4)], encoding: .ascii) else {
                throw Violation.drift("icns chunk at \(offset) has a non-ASCII type")
            }
            let lengthStart = data.startIndex + offset + 4
            let length = Int(data[lengthStart]) << 24 | Int(data[lengthStart + 1]) << 16
                | Int(data[lengthStart + 2]) << 8 | Int(data[lengthStart + 3])
            guard length >= 8, offset + length <= data.count else {
                throw Violation.drift("icns chunk \(type) at \(offset) has an invalid length \(length)")
            }
            types.append(type)
            offset += length
        }
        guard offset == data.count else {
            throw Violation.drift("icns chunk table ends at \(offset), file is \(data.count) bytes")
        }

        for requiredType in ["ic10", "ic09", "ic08", "ic07", "ic11", "ic12", "ic13", "ic14"] {
            guard types.contains(requiredType) else {
                throw Violation.drift("icon is missing the \(requiredType) representation (no modern size ladder)")
            }
        }
        return types
    }
}

// MARK: - Helpers

private func packagingData(_ relativePath: String) throws -> Data {
    let url = packageRootURL().appendingPathComponent(relativePath)
    guard let data = try? Data(contentsOf: url) else {
        throw PackagingContract.Violation.missing(relativePath)
    }
    return data
}

private func readMachOHeader(_ data: Data) throws -> (magic: UInt32, cpuType: UInt32) {
    guard data.count >= 8 else {
        throw PackagingContract.Violation.drift("executable is too small to be a Mach-O image")
    }
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return UInt32(data[start]) | UInt32(data[start + 1]) << 8
            | UInt32(data[start + 2]) << 16 | UInt32(data[start + 3]) << 24
    }
    return (littleEndianUInt32(at: 0), littleEndianUInt32(at: 4))
}

// MARK: - Tests

@Suite("PackagingContractTests")
struct PackagingContractTests {
    @Test("packaging inputs exist at the exact declared paths")
    func packagingInputsExist() throws {
        for relativePath in PackagingContract.requiredInputPaths {
            let url = packageRootURL().appendingPathComponent(relativePath)
            #expect(FileManager.default.fileExists(atPath: url.path), "missing \(relativePath)")
        }
    }

    @Test("package_app.sh is an executable script with the sole-authority commands")
    func packagingScriptContract() throws {
        let source = try readPackageFile("Scripts/package_app.sh")
        try PackagingContract.validatePackagingScript(source)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: packageRootURL().appendingPathComponent("Scripts/package_app.sh").path
        )
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect(permissions & 0o111 != 0, "Scripts/package_app.sh must be executable (found \(String(permissions, radix: 8)))")
    }

    @Test("packaging script validator actually rejects drift")
    func packagingScriptValidatorRejectsDrift() throws {
        let source = try readPackageFile("Scripts/package_app.sh")

        let withoutShowBinPath = source.replacingOccurrences(
            of: "swift build -c release --arch arm64 --show-bin-path",
            with: "echo .build/release"
        )
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validatePackagingScript(withoutShowBinPath)
        }

        let withoutArchGate = source.replacingOccurrences(of: "Mach-O 64-bit executable arm64", with: "Mach-O")
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validatePackagingScript(withoutArchGate)
        }

        let withoutStrictVerify = source.replacingOccurrences(
            of: "codesign --verify --deep --strict --verbose=2",
            with: "codesign --display"
        )
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validatePackagingScript(withoutStrictVerify)
        }

        let swallowingBuild = source.replacingOccurrences(
            of: "if ! swift build -c release --arch arm64; then",
            with: "swift build -c release --arch arm64 || true; if false; then"
        )
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validatePackagingScript(swallowingBuild)
        }

        let installing = source.replacingOccurrences(
            of: "if [[ \"${CURSORPAD_INSTALL}\" == \"1\" ]]; then",
            with: "if true; then"
        )
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validatePackagingScript(installing)
        }
    }

    @Test("Info.plist locks the bundle identity and the packaging surface")
    func infoPlistContract() throws {
        let data = try packagingData("Resources/Info.plist")
        let plist = try PackagingContract.parsePlist(data)
        try PackagingContract.validateInfoPlist(plist)
    }

    @Test("Info.plist agrees with the locked AppIdentity constants")
    func infoPlistMatchesAppIdentity() throws {
        let plist = try PackagingContract.parsePlist(try packagingData("Resources/Info.plist"))
        #expect(plist["CFBundleIdentifier"] as? String == AppIdentity.bundleIdentifier)
        #expect(plist["CFBundleName"] as? String == AppIdentity.displayName)
        #expect(plist["CFBundleExecutable"] as? String == AppIdentity.executableName)
        #expect(plist["CFBundleShortVersionString"] as? String == AppIdentity.version)
        #expect(plist["CFBundleVersion"] as? String == AppIdentity.build)
        #expect(plist["LSMinimumSystemVersion"] as? String == AppIdentity.minimumSystemVersion)
        #expect(AppIdentity.minimumSystemVersion == "14.0")
    }

    @Test("Info.plist validator actually rejects drift")
    func infoPlistValidatorRejectsDrift() throws {
        let data = try packagingData("Resources/Info.plist")
        let plist = try PackagingContract.parsePlist(data)

        var staleSystemVersion = plist
        staleSystemVersion["LSMinimumSystemVersion"] = "13.0"
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validateInfoPlist(staleSystemVersion)
        }

        var wrongBundle = plist
        wrongBundle["CFBundleIdentifier"] = "com.example.cursorpad"
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validateInfoPlist(wrongBundle)
        }

        var dockless = plist
        dockless["LSUIElement"] = true
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validateInfoPlist(dockless)
        }

        var wrongIcon = plist
        wrongIcon["CFBundleIconFile"] = "AppIcon.icns"
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validateInfoPlist(wrongIcon)
        }
    }

    @Test("entitlements stay an empty dictionary for the local unsandboxed build")
    func entitlementsContract() throws {
        let raw = try readPackageFile("Resources/App.entitlements")
        let parsed = try PackagingContract.parsePlist(Data(raw.utf8))
        try PackagingContract.validateEntitlements(raw, parsed: parsed)
    }

    @Test("entitlements validator actually rejects drift")
    func entitlementsValidatorRejectsDrift() throws {
        let raw = try readPackageFile("Resources/App.entitlements")
        let sandboxed = raw.replacingOccurrences(
            of: "<dict/>",
            with: "<dict>\n\t<key>com.apple.security.app-sandbox</key>\n\t<true/>\n</dict>"
        )
        let parsed = try PackagingContract.parsePlist(Data(sandboxed.utf8))
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validateEntitlements(sandboxed, parsed: parsed)
        }
    }

    @Test("AppIcon.icns carries the full modern size ladder")
    func appIconContract() throws {
        let data = try packagingData("Resources/AppIcon.icns")
        let types = try PackagingContract.validateIcon(data)
        #expect(types.contains("ic10"), "expected a 1024 pt representation")
        #expect(data.count > 50_000, "icon looks too small for a modern app icon (\(data.count) bytes)")
    }

    @Test("icon validator actually rejects drift")
    func iconValidatorRejectsDrift() throws {
        let data = try packagingData("Resources/AppIcon.icns")

        var corruptHeader = data
        corruptHeader[0] = 0x00
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validateIcon(corruptHeader)
        }

        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validateIcon(Data("not an icon".utf8))
        }
    }

    @Test("USERGUIDE.md documents install, shortcuts, storage, privacy and removal")
    func userGuideContract() throws {
        let text = try readPackageFile("USERGUIDE.md")
        try PackagingContract.validateUserGuide(text)
    }

    @Test("user guide validator actually rejects drift")
    func userGuideValidatorRejectsDrift() throws {
        let text = try readPackageFile("USERGUIDE.md")
        let withoutPrivacy = text.replacingOccurrences(of: "telemetry", with: "signal")
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validateUserGuide(withoutPrivacy)
        }
        #expect(throws: PackagingContract.Violation.self) {
            try PackagingContract.validateUserGuide("# CursorPad\nshort\n")
        }
    }

    @Test("packaging sources keep the privacy boundary (no network, no secrets, no user data)")
    func securityBoundaryContract() throws {
        let sources = [
            "Resources/Info.plist",
            "Resources/App.entitlements",
            "Scripts/package_app.sh",
            "USERGUIDE.md"
        ]
        let forbidden = [
            "apiKey", "api_key", "secret", "password", "Bearer ", "BEGIN PRIVATE KEY",
            "telemetry=", "analytics", "collect", "client_secret", "token="
        ]
        for relativePath in sources {
            let text = try readPackageFile(relativePath)
            for token in forbidden where text.contains(token) {
                // The user guide may honestly state that no analytics are collected.
                if relativePath == "USERGUIDE.md" && token == "analytics" { continue }
                Issue.record("\(relativePath) contains forbidden token '\(token)'")
            }
        }

        // No endpoints anywhere in packaging sources apart from the Apple plist DTD.
        for relativePath in sources {
            let text = try readPackageFile(relativePath)
            for line in text.split(separator: "\n") where line.contains("http://") || line.contains("https://") {
                let isAppleDTD = line.contains("http://www.apple.com/DTDs/PropertyList-1.0.dtd")
                #expect(isAppleDTD, "\(relativePath) contains an unexpected URL: \(line)")
            }
        }

        // The packaging script never touches note data or user state.
        let script = try readPackageFile("Scripts/package_app.sh")
        for token in ["Application Support", "Notes/", "sqlite", "UserDefaults", "defaults"] {
            #expect(!script.contains(token), "package_app.sh must not touch user data (\(token))")
        }

        // The entitlements are the only entitlements source and request nothing.
        let entitlements = try PackagingContract.parsePlist(try packagingData("Resources/App.entitlements"))
        #expect(entitlements.isEmpty)
    }

    // MARK: Optional artifact checks — green before and after packaging.

    @Test("assembled bundle, when present, matches the packaging contract")
    func assembledBundleContract() throws {
        let bundleURL = packageRootURL().appendingPathComponent("dist/CursorPad.app")
        guard FileManager.default.fileExists(atPath: bundleURL.path) else { return }

        let pkgInfoURL = bundleURL.appendingPathComponent("Contents/PkgInfo")
        let pkgInfo = try Data(contentsOf: pkgInfoURL)
        #expect(pkgInfo == Data("APPL????".utf8), "Contents/PkgInfo must be exactly APPL????")
        #expect(pkgInfo.count == 8)

        let bundledPlistData = try Data(contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist"))
        let sourcePlistData = try packagingData("Resources/Info.plist")
        #expect(bundledPlistData == sourcePlistData, "Contents/Info.plist must be the reviewed source plist")

        let executableURL = bundleURL.appendingPathComponent("Contents/MacOS/\(AppIdentity.executableName)")
        #expect(FileManager.default.fileExists(atPath: executableURL.path))
        let header = try readMachOHeader(try Data(contentsOf: executableURL))
        #expect(header.magic == 0xFEED_FACF, "executable must be a 64-bit Mach-O image")
        #expect(header.cpuType == 0x0100_000C, "executable must be arm64")

        for resource in ["AppIcon.icns", "USERGUIDE.md", "App.entitlements"] {
            let url = bundleURL.appendingPathComponent("Contents/Resources/\(resource)")
            #expect(FileManager.default.fileExists(atPath: url.path), "missing bundled resource \(resource)")
        }
    }

    @Test("disk image, when present, is a verified read-only image")
    func diskImageContract() throws {
        let dmgURL = packageRootURL().appendingPathComponent("dist/CursorPad.dmg")
        guard FileManager.default.fileExists(atPath: dmgURL.path) else { return }

        let data = try Data(contentsOf: dmgURL)
        #expect(data.count > 100_000, "unexpectedly small disk image (\(data.count) bytes)")

        // UDIF images end with a 512-byte `koly` trailer describing the image blocks.
        let trailer = Array(data.suffix(512))
        #expect(trailer.count == 512, "disk image is smaller than a UDIF trailer")
        #expect(Data(trailer.prefix(4)) == Data("koly".utf8), "disk image is missing its UDIF koly trailer")
        func bigEndianUInt32(at offset: Int) -> UInt32 {
            UInt32(trailer[offset]) << 24 | UInt32(trailer[offset + 1]) << 16
                | UInt32(trailer[offset + 2]) << 8 | UInt32(trailer[offset + 3])
        }
        #expect(bigEndianUInt32(at: 4) == 4, "expected UDIF trailer version 4")
        #expect(bigEndianUInt32(at: 8) == 512, "expected a 512-byte UDIF trailer header")
    }
}
