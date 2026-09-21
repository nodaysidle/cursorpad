// swift-tools-version: 6.0
import PackageDescription

// CursorPad — locked foundation (PHASE-01).
// Tools 6.0, macOS 14 deployment target, executable product/target `Cursorpad`,
// Swift 6 language mode, sqlite3 linked, no external package dependencies.
let package = Package(
    name: "Cursorpad",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Cursorpad", targets: ["Cursorpad"])
    ],
    targets: [
        .executableTarget(
            name: "Cursorpad",
            path: "Sources/Cursorpad",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CursorpadTests",
            dependencies: ["Cursorpad"],
            path: "Tests/CursorpadTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
