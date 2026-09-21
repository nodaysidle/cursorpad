# Technical Requirements Document — CursorPad

## Document Purpose

Lock the stack, project layout, interfaces, data, integrations, lifecycle, persistence, credentials, permissions, recovery, tests, packaging, signing, validation, and completion proof.

## Locked Identity

- Project name: CursorPad
- Project slug: cursorpad
- Bundle or application ID: com.cursorpad.app
- Runtime mode: native
- Output artifact: native macOS .app and DMG
- Artifact path: dist/CursorPad.app

## Locked Stack

- Swift 6
- SwiftUI
- AppKit bridges where native macOS APIs require them
- Swift Package Manager
- Swift Testing
- Keychain
- UserDefaults
- SQLite3
- Application Support

## Runtime Architecture Contracts

- Use an @main SwiftUI App entry with WindowGroup; one @Observable @MainActor AppState owns presentation state, feature services are injected at the composition root, and AppKit adapters remain in Platform owners.
- Run I/O and provider work in cancellable async tasks or actors off the main actor and publish UI state on the main actor.

## Forbidden Technologies

- Forbidden: iOS
- Forbidden: Catalyst
- Forbidden: Flutter
- Forbidden: Tauri
- Forbidden: Electron

## Project Layout

- Package.swift
- Sources/Cursorpad/CursorpadApp.swift
- Sources/Cursorpad/AppState.swift
- Tests/CursorpadTests/ContractTests.swift
- Sources/Cursorpad/Platform/DataStore.swift
- Tests/CursorpadTests/DataStoreTests.swift
- Sources/Cursorpad/Platform/LifecycleCoordinator.swift
- Tests/CursorpadTests/LifecycleCoordinatorTests.swift
- Sources/Cursorpad/Features/CommandPaletteNoteNavigationFeature.swift
- Tests/CursorpadTests/CommandPaletteNoteNavigationFeatureTests.swift
- Sources/Cursorpad/Features/CursorDarkMonospaceEditorFeature.swift
- Tests/CursorpadTests/CursorDarkMonospaceEditorFeatureTests.swift
- Sources/Cursorpad/Platform/PermissionCoordinator.swift
- Tests/CursorpadTests/PermissionCoordinatorTests.swift
- Sources/Cursorpad/Features/CompactSidebarLibraryFeature.swift
- Tests/CursorpadTests/CompactSidebarLibraryFeatureTests.swift
- Sources/Cursorpad/Features/NonBlockingAtomicDiskStorageFeature.swift
- Tests/CursorpadTests/NonBlockingAtomicDiskStorageFeatureTests.swift
- Scripts/package_app.sh
- Tests/CursorpadTests/PackagingContractTests.swift
- Resources/Info.plist
- Resources/App.entitlements
- Resources/AppIcon.icns

## Owner-to-File and Focused-Test Map

- OWN-DATA-STORE — DataStore — implementation Sources/Cursorpad/Platform/DataStore.swift — focused test Tests/CursorpadTests/DataStoreTests.swift — command swift test --filter DataStoreTests
- OWN-LIFECYCLE-COORDINATOR — LifecycleCoordinator — implementation Sources/Cursorpad/Platform/LifecycleCoordinator.swift — focused test Tests/CursorpadTests/LifecycleCoordinatorTests.swift — command swift test --filter LifecycleCoordinatorTests
- OWN-COMMAND-PALETTE-NOTE-NAVIGATION — CommandPaletteNoteNavigationFeature — implementation Sources/Cursorpad/Features/CommandPaletteNoteNavigationFeature.swift — focused test Tests/CursorpadTests/CommandPaletteNoteNavigationFeatureTests.swift — command swift test --filter CommandPaletteNoteNavigationFeatureTests
- OWN-CURSOR-DARK-MONOSPACE-EDITOR — CursorDarkMonospaceEditorFeature — implementation Sources/Cursorpad/Features/CursorDarkMonospaceEditorFeature.swift — focused test Tests/CursorpadTests/CursorDarkMonospaceEditorFeatureTests.swift — command swift test --filter CursorDarkMonospaceEditorFeatureTests
- OWN-PERMISSION-COORDINATOR — PermissionCoordinator — implementation Sources/Cursorpad/Platform/PermissionCoordinator.swift — focused test Tests/CursorpadTests/PermissionCoordinatorTests.swift — command swift test --filter PermissionCoordinatorTests
- OWN-COMPACT-SIDEBAR-LIBRARY — CompactSidebarLibraryFeature — implementation Sources/Cursorpad/Features/CompactSidebarLibraryFeature.swift — focused test Tests/CursorpadTests/CompactSidebarLibraryFeatureTests.swift — command swift test --filter CompactSidebarLibraryFeatureTests
- OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE — NonBlockingAtomicDiskStorageFeature — implementation Sources/Cursorpad/Features/NonBlockingAtomicDiskStorageFeature.swift — focused test Tests/CursorpadTests/NonBlockingAtomicDiskStorageFeatureTests.swift — command swift test --filter NonBlockingAtomicDiskStorageFeatureTests
- OWN-PACKAGING — Packaging — implementation Scripts/package_app.sh — focused test Tests/CursorpadTests/PackagingContractTests.swift — command swift test --filter PackagingContractTests

## Interface Contracts

### CON-CURSOR-DARK-MONOSPACE-EDITOR-INTERFACE — Cursor Dark Monospace Editor interface

- Kind: interface
- Feature trace: FEAT-CURSOR-DARK-MONOSPACE-EDITOR
- Owner: OWN-CURSOR-DARK-MONOSPACE-EDITOR
- Decision: Initializes a native TextKit 2 text view configured with SF Mono 13pt typography, 1.45 line height, Cursor background color (#181818), selection tint (#264f78), and active line highlight (#222222). Line numbers render in the gutter with muted foreground (#6e7681).
- Inputs: User opens a note or creates a new tab with Command+N.
- Outputs: Users type in a dark-mode editor styled after the Cursor IDE with line numbers and smooth caret animations.
- Failure behavior: Falls back to standard macOS monospaced system font if custom font descriptor fails to instantiate.
- Recovery: Preserve the last valid state, explain the failure, and allow an explicit retry of Cursor Dark Monospace Editor.

### CON-COMMAND-PALETTE-NOTE-NAVIGATION-INTERFACE — Command Palette Note Navigation interface

- Kind: interface
- Feature trace: FEAT-COMMAND-PALETTE-NOTE-NAVIGATION
- Owner: OWN-COMMAND-PALETTE-NOTE-NAVIGATION
- Decision: Displays a floating glassmorphic spotlight modal with an auto-focused search input (#1e1e1e background, #2b2b2b border). As the user types, notes are ranked using prefix and fuzzy subsequence matching. Arrow keys navigate selections and Enter switches notes.
- Inputs: User presses Command+P or Command+K from anywhere in the app window.
- Outputs: Users quickly filter and open existing notes using fuzzy title matching without leaving the keyboard.
- Failure behavior: Displays 'No matching notes found' message when query yields zero results and keeps search field active.
- Recovery: Preserve the last valid state, explain the failure, and allow an explicit retry of Command Palette Note Navigation.

### CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-INTERFACE — Non-Blocking Atomic Disk Storage interface

- Kind: interface
- Feature trace: FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE
- Owner: OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE
- Decision: Debounces text changes by 250ms and asynchronously writes UTF-8 bytes to the Application Support directory using atomic temporary file swap (NSDataWritingAtomic).
- Inputs: User edits text or creates a new note.
- Outputs: Notes are auto-saved to disk immediately upon editing without blocking UI typing or risking data corruption.
- Failure behavior: Surfaces a discreet status bar error indicator if disk write fails and retains modified text in memory buffer.
- Recovery: Preserve the last valid state, explain the failure, and allow an explicit retry of Non-Blocking Atomic Disk Storage.

### CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE — Compact Sidebar Library interface

- Kind: interface
- Feature trace: FEAT-COMPACT-SIDEBAR-LIBRARY
- Owner: OWN-COMPACT-SIDEBAR-LIBRARY
- Decision: Renders a compact SwiftUI sidebar (#1e1e1e background) listing notes ordered by last updated timestamp. Displays note title, relative timestamp, and character count. Clicking an item binds the editor to that note.
- Inputs: User toggles sidebar with Command+B or window launch.
- Outputs: Users view their note list with modified timestamps, word counts, and search filter.
- Failure behavior: Shows an empty state prompt inviting the user to press Command+N when no notes exist.
- Recovery: Preserve the last valid state, explain the failure, and allow an explicit retry of Compact Sidebar Library.

## Data Contracts

### CON-DATA-NOTEDOCUMENT — NoteDocument

- Kind: data
- Feature trace: none
- Owner: OWN-DATA-STORE
- Decision: Represents a single plain text note with metadata and file reference.
- Retention: Retained locally until explicitly deleted by the user.
- Sensitivity: personal
- Failure behavior: Reject invalid or incomplete records without replacing the last valid state.
- Recovery: Preserve the last valid record and expose a bounded correction or rebuild path.

### CON-DATA-EDITORCONFIGURATION — EditorConfiguration

- Kind: data
- Feature trace: none
- Owner: OWN-DATA-STORE
- Decision: Stores editor preferences including font size, tab width, and word wrap state.
- Retention: Persisted across application launches in AppStorage.
- Sensitivity: personal
- Failure behavior: Reject invalid or incomplete records without replacing the last valid state.
- Recovery: Preserve the last valid record and expose a bounded correction or rebuild path.

## External Integration Contracts

- Use one actor-owned URLSession boundary: URLSession.data(for:) for HTTPS requests and URLSessionWebSocketTask for streaming; encode and decode typed Codable DTOs, map failures before they reach UI state, and never expose raw response bodies.

- None. The project graph contains no applicable contract of this kind.

## Lifecycle Contracts

### CON-LIFECYCLE-APPLICATION-LAUNCH — Application launch

- Kind: lifecycle
- Feature trace: none
- Owner: OWN-LIFECYCLE-COORDINATOR
- Decision: Initialize preset-owned state and services without starting privileged capture, remote requests, or destructive work automatically.
- Cleanup: Rollback partial initialization and keep a safe retry or manual launch path.
- Failure behavior: An interrupted lifecycle transition must not be reported as complete.
- Recovery: Rollback partial initialization and keep a safe retry or manual launch path.

### CON-LIFECYCLE-APPLICATION-TERMINATION — Application termination

- Kind: lifecycle
- Feature trace: none
- Owner: OWN-LIFECYCLE-COORDINATOR
- Decision: Stop new work, cancel active operations, and preserve only state covered by the persistence contracts.
- Cleanup: Release permissions, listeners, handles, tasks, clipboard snapshots, and temporary resources before termination completes.
- Failure behavior: An interrupted lifecycle transition must not be reported as complete.
- Recovery: Release permissions, listeners, handles, tasks, clipboard snapshots, and temporary resources before termination completes.

### CON-LIFECYCLE-PRESET — Native macOS SwiftUI Desktop lifecycle

- Kind: lifecycle
- Feature trace: FEAT-CURSOR-DARK-MONOSPACE-EDITOR, FEAT-COMMAND-PALETTE-NOTE-NAVIGATION, FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE, FEAT-COMPACT-SIDEBAR-LIBRARY
- Owner: OWN-LIFECYCLE-COORDINATOR
- Decision: Use WindowGroup as the Dock-first application entry. Cancel tasks and release AppKit delegates during application termination. Model window restoration only for product-owned state.
- Use WindowGroup as the Dock-first application entry.
- Cancel tasks and release AppKit delegates during application termination.
- Model window restoration only for product-owned state.
- Failure behavior: A preset lifecycle invariant failure blocks completion and leaves the last safe state active.
- Recovery: Restore the last safe lifecycle state, release partial resources, and rerun the focused lifecycle checks.

## Persistence Contracts

Persistence: enabled with UserDefaults for lightweight settings and SQLite for durable record collections in Application Support.

### CON-PERSISTENCE-NOTEDOCUMENT — NoteDocument persistence

- Kind: persistence
- Feature trace: none
- Owner: OWN-DATA-STORE
- Decision: Persistence: enabled with UserDefaults for lightweight settings and SQLite for durable record collections in Application Support. Represents a single plain text note with metadata and file reference.
- Placement: SQLite in Application Support with schema-versioned transactional migrations and owner-scoped repositories.
- Retention: Retained locally until explicitly deleted by the user.
- Deletion: Delete NoteDocument only through an explicit user action or the stated retention boundary, and report deletion failure honestly.
- Sensitivity: personal
- Failure behavior: A failed write leaves the prior durable state valid and the new state visibly unsaved.
- Recovery: Retry through the same atomic boundary without duplicating the record.; Delete NoteDocument only through an explicit user action or the stated retention boundary, and report deletion failure honestly.

### CON-PERSISTENCE-EDITORCONFIGURATION — EditorConfiguration persistence

- Kind: persistence
- Feature trace: none
- Owner: OWN-DATA-STORE
- Decision: Persistence: enabled with UserDefaults for lightweight settings and SQLite for durable record collections in Application Support. Stores editor preferences including font size, tab width, and word wrap state.
- Placement: SQLite in Application Support with schema-versioned transactional migrations and owner-scoped repositories.
- Retention: Persisted across application launches in AppStorage.
- Deletion: Delete EditorConfiguration only through an explicit user action or the stated retention boundary, and report deletion failure honestly.
- Sensitivity: personal
- Failure behavior: A failed write leaves the prior durable state valid and the new state visibly unsaved.
- Recovery: Retry through the same atomic boundary without duplicating the record.; Delete EditorConfiguration only through an explicit user action or the stated retention boundary, and report deletion failure honestly.

## Credential Contracts

- None. The project graph contains no applicable contract of this kind.

## Permission Contracts

### CON-PERMISSION-FILESYSTEM — filesystem permission

- Kind: permission
- Feature trace: FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE, FEAT-COMPACT-SIDEBAR-LIBRARY
- Owner: OWN-PERMISSION-COORDINATOR
- Decision: Use NSOpenPanel and security-scoped bookmarks only for user-selected locations; release every access scope.
- Purpose: Access only user-selected files and folders required by a feature.
- Denied behavior: Leave existing state unchanged and allow another explicit selection.
- Failure behavior: Leave existing state unchanged and allow another explicit selection.
- Recovery: Recheck authorization only after an explicit user action and preserve the documented denied path.

## Errors and Recovery Contracts

- Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state.
- Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path.

### CON-CURSOR-DARK-MONOSPACE-EDITOR-RECOVERY — Cursor Dark Monospace Editor recovery

- Kind: recovery
- Feature trace: FEAT-CURSOR-DARK-MONOSPACE-EDITOR
- Owner: OWN-CURSOR-DARK-MONOSPACE-EDITOR
- Decision: Treat failure as a terminal or recoverable state exactly as the semantic contract describes. Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state. Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path.
- Failure: Falls back to standard macOS monospaced system font if custom font descriptor fails to instantiate.
- Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state.
- Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path.
- Failure behavior: Falls back to standard macOS monospaced system font if custom font descriptor fails to instantiate.
- Recovery: Preserve the last valid state, explain the failure, and allow an explicit retry of Cursor Dark Monospace Editor.

### CON-COMMAND-PALETTE-NOTE-NAVIGATION-RECOVERY — Command Palette Note Navigation recovery

- Kind: recovery
- Feature trace: FEAT-COMMAND-PALETTE-NOTE-NAVIGATION
- Owner: OWN-COMMAND-PALETTE-NOTE-NAVIGATION
- Decision: Treat failure as a terminal or recoverable state exactly as the semantic contract describes. Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state. Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path.
- Failure: Displays 'No matching notes found' message when query yields zero results and keeps search field active.
- Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state.
- Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path.
- Failure behavior: Displays 'No matching notes found' message when query yields zero results and keeps search field active.
- Recovery: Preserve the last valid state, explain the failure, and allow an explicit retry of Command Palette Note Navigation.

### CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY — Non-Blocking Atomic Disk Storage recovery

- Kind: recovery
- Feature trace: FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE
- Owner: OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE
- Decision: Treat failure as a terminal or recoverable state exactly as the semantic contract describes. Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state. Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path.
- Failure: Surfaces a discreet status bar error indicator if disk write fails and retains modified text in memory buffer.
- Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state.
- Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path.
- Failure behavior: Surfaces a discreet status bar error indicator if disk write fails and retains modified text in memory buffer.
- Recovery: Preserve the last valid state, explain the failure, and allow an explicit retry of Non-Blocking Atomic Disk Storage.

### CON-COMPACT-SIDEBAR-LIBRARY-RECOVERY — Compact Sidebar Library recovery

- Kind: recovery
- Feature trace: FEAT-COMPACT-SIDEBAR-LIBRARY
- Owner: OWN-COMPACT-SIDEBAR-LIBRARY
- Decision: Treat failure as a terminal or recoverable state exactly as the semantic contract describes. Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state. Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path.
- Failure: Shows an empty state prompt inviting the user to press Command+N when no notes exist.
- Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state.
- Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path.
- Failure behavior: Shows an empty state prompt inviting the user to press Command+N when no notes exist.
- Recovery: Preserve the last valid state, explain the failure, and allow an explicit retry of Compact Sidebar Library.

## Security Contract

### CON-SECURITY-BOUNDARY — Privacy and security boundary

- Kind: security
- Feature trace: FEAT-CURSOR-DARK-MONOSPACE-EDITOR, FEAT-COMMAND-PALETTE-NOTE-NAVIGATION, FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE, FEAT-COMPACT-SIDEBAR-LIBRARY
- Owner: OWN-PACKAGING
- Decision: Minimize collected data and keep it inside the preset-defined owner, storage, and integration boundaries. Protect NoteDocument as personal data and never expose it through logs or diagnostics. Protect EditorConfiguration as personal data and never expose it through logs or diagnostics.
- Minimize collected data and keep it inside the preset-defined owner, storage, and integration boundaries.
- Protect NoteDocument as personal data and never expose it through logs or diagnostics.
- Protect EditorConfiguration as personal data and never expose it through logs or diagnostics.
- Failure behavior: A privacy or security invariant failure stops the affected operation before data crosses the boundary.
- Recovery: Restore the last safe state and require explicit user action before retrying.

## Accessibility Contracts

- Require VoiceOver and keyboard operation for every control, expose stable accessibility labels, roles, values, and focus order, and verify with SwiftUI accessibility tests plus Accessibility Inspector.

## Testing Contract

- Framework: Swift Testing
- Tests/CursorpadTests/DataStoreTests.swift: cover no direct features and contracts CON-DATA-NOTEDOCUMENT, CON-DATA-EDITORCONFIGURATION, CON-PERSISTENCE-NOTEDOCUMENT, CON-PERSISTENCE-EDITORCONFIGURATION.
- Tests/CursorpadTests/LifecycleCoordinatorTests.swift: cover no direct features and contracts CON-LIFECYCLE-APPLICATION-LAUNCH, CON-LIFECYCLE-APPLICATION-TERMINATION, CON-LIFECYCLE-PRESET.
- Tests/CursorpadTests/CommandPaletteNoteNavigationFeatureTests.swift: cover FEAT-COMMAND-PALETTE-NOTE-NAVIGATION and contracts CON-COMMAND-PALETTE-NOTE-NAVIGATION-INTERFACE, CON-COMMAND-PALETTE-NOTE-NAVIGATION-RECOVERY.
- Tests/CursorpadTests/CursorDarkMonospaceEditorFeatureTests.swift: cover FEAT-CURSOR-DARK-MONOSPACE-EDITOR and contracts CON-CURSOR-DARK-MONOSPACE-EDITOR-INTERFACE, CON-CURSOR-DARK-MONOSPACE-EDITOR-RECOVERY.
- Tests/CursorpadTests/PermissionCoordinatorTests.swift: cover no direct features and contracts CON-PERMISSION-FILESYSTEM.
- Tests/CursorpadTests/CompactSidebarLibraryFeatureTests.swift: cover FEAT-COMPACT-SIDEBAR-LIBRARY and contracts CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE, CON-COMPACT-SIDEBAR-LIBRARY-RECOVERY.
- Tests/CursorpadTests/NonBlockingAtomicDiskStorageFeatureTests.swift: cover FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE and contracts CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-INTERFACE, CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY.
- Tests/CursorpadTests/PackagingContractTests.swift: cover no direct features and contracts CON-SECURITY-BOUNDARY, CON-PACKAGING-RELEASE.
- Run focused tests before shared suites and package checks.

## Packaging Contract

### CON-PACKAGING-RELEASE — Native macOS SwiftUI Desktop packaging

- Kind: packaging
- Feature trace: FEAT-CURSOR-DARK-MONOSPACE-EDITOR, FEAT-COMMAND-PALETTE-NOTE-NAVIGATION, FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE, FEAT-COMPACT-SIDEBAR-LIBRARY
- Owner: OWN-PACKAGING
- Decision: Scripts/package_app.sh is the sole packaging authority for release build, app assembly, resources, signing, strict verification, and DMG creation. Assemble one native arm64 macOS .app from the Swift Package Manager release executable, Info.plist, App.entitlements, and AppIcon.icns. Ad-hoc sign local builds or use an explicitly supplied Developer ID for distribution, then require codesign --verify --deep --strict. Register and launch the installed bundle through LaunchServices.
- Scripts/package_app.sh is the sole packaging authority for release build, app assembly, resources, signing, strict verification, and DMG creation.
- Assemble one native arm64 macOS .app from the Swift Package Manager release executable, Info.plist, App.entitlements, and AppIcon.icns.
- Ad-hoc sign local builds or use an explicitly supplied Developer ID for distribution, then require codesign --verify --deep --strict.
- Register and launch the installed bundle through LaunchServices.
- Bundle identity: CFBundleIdentifier = com.cursorpad.app; CFBundleName = CursorPad; CFBundleExecutable = Cursorpad; CFBundleIconFile = AppIcon; CFBundlePackageType = APPL; CFBundleShortVersionString = 1.0.0; CFBundleVersion = 1.
- Info.plist ownership: Resources/Info.plist declares CFBundleIdentifier, CFBundleExecutable, CFBundleIconFile, LSMinimumSystemVersion = 13.0, NSHighResolutionCapable = true, NSMicrophoneUsageDescription = "CursorPad uses the microphone only while you explicitly record dictation.", and LSUIElement = false.
- Entitlements ownership: Resources/App.entitlements is the only entitlements source and is an XML plist with an empty dictionary for the local unsandboxed build; com.apple.security.app-sandbox and broad file or automation entitlements are absent, and signing passes this reviewed file explicitly.
- Icon ownership: Resources/AppIcon.icns is the single source icon copied to Contents/Resources/AppIcon.icns and referenced by CFBundleIconFile.
- Architecture: Scripts/package_app.sh runs swift build -c release --arch arm64, rejects a non-arm64 Mach-O executable, and copies .build/arm64-apple-macosx/release/Cursorpad.
- App assembly: create dist/CursorPad.app/Contents/MacOS and Contents/Resources, copy the executable to Contents/MacOS/Cursorpad, copy Info.plist to Contents/Info.plist, copy AppIcon.icns to Contents/Resources, and write no competing Packaging.swift implementation.
- Signing: Scripts/package_app.sh signs the assembled bundle once with the selected local or distribution identity and Resources/App.entitlements, then runs codesign --verify --deep --strict and rejects any failure before DMG or install.
- Launch: after the verified rollback and app copy, register the exact bundle with LaunchServices and launch it with open -b com.cursorpad.app; verify that running bundle identity rather than a path lookalike.
- Installation: Install the verified signed app at /Applications/CursorPad.app after a scoped rollback copy, then register and launch that exact bundle through LaunchServices.
- Output artifact: native macOS .app and DMG
- Failure behavior: A failed build, signature, package, install, or launch check blocks completion.
- Recovery: Fix the first failing validation command, rebuild the artifact, and rerun every later release gate.

## Signing Contract

Sign CursorPad.app with an explicit Developer ID for distribution or ad-hoc identity '-' for local proof; codesign strict verification is mandatory.

## Installation Contract

Install the verified signed app at /Applications/CursorPad.app after a scoped rollback copy, then register and launch that exact bundle through LaunchServices.

## Validation Commands

1. `swift test`
2. `swift build -c release`
3. `./Scripts/package_app.sh`
4. `codesign --verify --deep --strict "dist/CursorPad.app"`
5. `open "dist/CursorPad.app"`

## Completion Evidence

- Swift tests and release build exit successfully.
- The .app has the locked bundle ID and resources.
- codesign strict verification succeeds.
- LaunchServices starts the production process.

## Traceability Index

- FEAT-CURSOR-DARK-MONOSPACE-EDITOR — Cursor Dark Monospace Editor — Requirement REQ-CURSOR-DARK-MONOSPACE-EDITOR — Acceptance ACC-CURSOR-DARK-MONOSPACE-EDITOR-01 (feature, owner OWN-CURSOR-DARK-MONOSPACE-EDITOR): Editor background color precisely matches hexadecimal #181818 in AppKit color space.; ACC-CURSOR-DARK-MONOSPACE-EDITOR-02 (feature, owner OWN-CURSOR-DARK-MONOSPACE-EDITOR): Gutter line numbers automatically recalculate as lines are added or removed.; ACC-CURSOR-DARK-MONOSPACE-EDITOR-03 (feature, owner OWN-CURSOR-DARK-MONOSPACE-EDITOR): Typing latency remains under 8 milliseconds per keystroke on Apple Silicon hardware. — Owner OWN-CURSOR-DARK-MONOSPACE-EDITOR — Interface CON-CURSOR-DARK-MONOSPACE-EDITOR-INTERFACE — Data none — Persistence none — Recovery CON-CURSOR-DARK-MONOSPACE-EDITOR-RECOVERY — All contracts CON-CURSOR-DARK-MONOSPACE-EDITOR-INTERFACE, CON-CURSOR-DARK-MONOSPACE-EDITOR-RECOVERY, CON-LIFECYCLE-PRESET, CON-SECURITY-BOUNDARY, CON-PACKAGING-RELEASE — Files Sources/Cursorpad/Features/CursorDarkMonospaceEditorFeature.swift; Tests/CursorpadTests/CursorDarkMonospaceEditorFeatureTests.swift — Phase PHASE-05-CURSOR-DARK-MONOSPACE-EDITOR depends on PHASE-01-FOUNDATION, PHASE-03-LIFECYCLE-COORDINATOR — Task TASK-05-CURSOR-DARK-MONOSPACE-EDITOR depends on TASK-01-FOUNDATION, TASK-03-LIFECYCLE-COORDINATOR — Focused test command swift test --filter CursorDarkMonospaceEditorFeatureTests — Validation swift test --filter CursorDarkMonospaceEditorFeatureTests; swift test; swift build -c release — Downstream instruction Implement owner OWN-CURSOR-DARK-MONOSPACE-EDITOR (CursorDarkMonospaceEditorFeature) in Sources/Cursorpad/Features/CursorDarkMonospaceEditorFeature.swift and its real focused checks in Tests/CursorpadTests/CursorDarkMonospaceEditorFeatureTests.swift. Cover direct features FEAT-CURSOR-DARK-MONOSPACE-EDITOR and owned contracts CON-CURSOR-DARK-MONOSPACE-EDITOR-INTERFACE, CON-CURSOR-DARK-MONOSPACE-EDITOR-RECOVERY. Depend only on OWN-LIFECYCLE-COORDINATOR; implement every documented decision, failure, cancellation, cleanup, and recovery branch. Create only Sources/Cursorpad/Features/CursorDarkMonospaceEditorFeature.swift; Tests/CursorpadTests/CursorDarkMonospaceEditorFeatureTests.swift and modify only Sources/Cursorpad/AppState.swift after its foundation creation.
- FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — Command Palette Note Navigation — Requirement REQ-COMMAND-PALETTE-NOTE-NAVIGATION — Acceptance ACC-COMMAND-PALETTE-NOTE-NAVIGATION-01 (feature, owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION): Fuzzy search filters a library of 1,000 notes in under 5 milliseconds.; ACC-COMMAND-PALETTE-NOTE-NAVIGATION-02 (feature, owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION): Pressing Command+P opens the palette overlay within 16 milliseconds without layout hitch.; ACC-COMMAND-PALETTE-NOTE-NAVIGATION-03 (feature, owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION): Pressing Escape closes the palette and restores first-responder focus to the editor. — Owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION — Interface CON-COMMAND-PALETTE-NOTE-NAVIGATION-INTERFACE — Data none — Persistence none — Recovery CON-COMMAND-PALETTE-NOTE-NAVIGATION-RECOVERY — All contracts CON-COMMAND-PALETTE-NOTE-NAVIGATION-INTERFACE, CON-COMMAND-PALETTE-NOTE-NAVIGATION-RECOVERY, CON-LIFECYCLE-PRESET, CON-SECURITY-BOUNDARY, CON-PACKAGING-RELEASE — Files Sources/Cursorpad/Features/CommandPaletteNoteNavigationFeature.swift; Tests/CursorpadTests/CommandPaletteNoteNavigationFeatureTests.swift — Phase PHASE-04-COMMAND-PALETTE-NOTE-NAVIGATION depends on PHASE-01-FOUNDATION, PHASE-03-LIFECYCLE-COORDINATOR — Task TASK-04-COMMAND-PALETTE-NOTE-NAVIGATION depends on TASK-01-FOUNDATION, TASK-03-LIFECYCLE-COORDINATOR — Focused test command swift test --filter CommandPaletteNoteNavigationFeatureTests — Validation swift test --filter CommandPaletteNoteNavigationFeatureTests; swift test; swift build -c release — Downstream instruction Implement owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION (CommandPaletteNoteNavigationFeature) in Sources/Cursorpad/Features/CommandPaletteNoteNavigationFeature.swift and its real focused checks in Tests/CursorpadTests/CommandPaletteNoteNavigationFeatureTests.swift. Cover direct features FEAT-COMMAND-PALETTE-NOTE-NAVIGATION and owned contracts CON-COMMAND-PALETTE-NOTE-NAVIGATION-INTERFACE, CON-COMMAND-PALETTE-NOTE-NAVIGATION-RECOVERY. Depend only on OWN-LIFECYCLE-COORDINATOR; implement every documented decision, failure, cancellation, cleanup, and recovery branch. Create only Sources/Cursorpad/Features/CommandPaletteNoteNavigationFeature.swift; Tests/CursorpadTests/CommandPaletteNoteNavigationFeatureTests.swift and modify only Sources/Cursorpad/AppState.swift after its foundation creation.
- FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — Non-Blocking Atomic Disk Storage — Requirement REQ-NON-BLOCKING-ATOMIC-DISK-STORAGE — Acceptance ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-01 (feature, owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE): App crash or forced termination preserves the last auto-saved note state without file truncation.; ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-02 (feature, owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE): Changes are committed to disk via atomic write within 300ms of user typing cessation.; ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-03 (feature, owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE): Disk write operations never execute on the main actor thread. — Owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE — Interface CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-INTERFACE — Data none — Persistence none — Recovery CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY — All contracts CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-INTERFACE, CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY, CON-LIFECYCLE-PRESET, CON-PERMISSION-FILESYSTEM, CON-SECURITY-BOUNDARY, CON-PACKAGING-RELEASE — Files Sources/Cursorpad/Features/NonBlockingAtomicDiskStorageFeature.swift; Tests/CursorpadTests/NonBlockingAtomicDiskStorageFeatureTests.swift — Phase PHASE-08-NON-BLOCKING-ATOMIC-DISK-STORAGE depends on PHASE-01-FOUNDATION, PHASE-03-LIFECYCLE-COORDINATOR, PHASE-06-PERMISSION-COORDINATOR — Task TASK-08-NON-BLOCKING-ATOMIC-DISK-STORAGE depends on TASK-01-FOUNDATION, TASK-03-LIFECYCLE-COORDINATOR, TASK-06-PERMISSION-COORDINATOR — Focused test command swift test --filter NonBlockingAtomicDiskStorageFeatureTests — Validation swift test --filter NonBlockingAtomicDiskStorageFeatureTests; swift test; swift build -c release — Downstream instruction Implement owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE (NonBlockingAtomicDiskStorageFeature) in Sources/Cursorpad/Features/NonBlockingAtomicDiskStorageFeature.swift and its real focused checks in Tests/CursorpadTests/NonBlockingAtomicDiskStorageFeatureTests.swift. Cover direct features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE and owned contracts CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-INTERFACE, CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY. Depend only on OWN-LIFECYCLE-COORDINATOR, OWN-PERMISSION-COORDINATOR; implement every documented decision, failure, cancellation, cleanup, and recovery branch. Create only Sources/Cursorpad/Features/NonBlockingAtomicDiskStorageFeature.swift; Tests/CursorpadTests/NonBlockingAtomicDiskStorageFeatureTests.swift and modify only Sources/Cursorpad/AppState.swift after its foundation creation.
- FEAT-COMPACT-SIDEBAR-LIBRARY — Compact Sidebar Library — Requirement REQ-COMPACT-SIDEBAR-LIBRARY — Acceptance ACC-COMPACT-SIDEBAR-LIBRARY-01 (feature, owner OWN-COMPACT-SIDEBAR-LIBRARY): Deleting a note moves the target file to the macOS Trash directory via NSFileManager.; ACC-COMPACT-SIDEBAR-LIBRARY-02 (feature, owner OWN-COMPACT-SIDEBAR-LIBRARY): Selecting a note switches the editor contents within 16 milliseconds.; ACC-COMPACT-SIDEBAR-LIBRARY-03 (feature, owner OWN-COMPACT-SIDEBAR-LIBRARY): Sidebar list updates note order dynamically when a note is edited. — Owner OWN-COMPACT-SIDEBAR-LIBRARY — Interface CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE — Data none — Persistence none — Recovery CON-COMPACT-SIDEBAR-LIBRARY-RECOVERY — All contracts CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE, CON-COMPACT-SIDEBAR-LIBRARY-RECOVERY, CON-LIFECYCLE-PRESET, CON-PERMISSION-FILESYSTEM, CON-SECURITY-BOUNDARY, CON-PACKAGING-RELEASE — Files Sources/Cursorpad/Features/CompactSidebarLibraryFeature.swift; Tests/CursorpadTests/CompactSidebarLibraryFeatureTests.swift — Phase PHASE-07-COMPACT-SIDEBAR-LIBRARY depends on PHASE-01-FOUNDATION, PHASE-03-LIFECYCLE-COORDINATOR, PHASE-06-PERMISSION-COORDINATOR — Task TASK-07-COMPACT-SIDEBAR-LIBRARY depends on TASK-01-FOUNDATION, TASK-03-LIFECYCLE-COORDINATOR, TASK-06-PERMISSION-COORDINATOR — Focused test command swift test --filter CompactSidebarLibraryFeatureTests — Validation swift test --filter CompactSidebarLibraryFeatureTests; swift test; swift build -c release — Downstream instruction Implement owner OWN-COMPACT-SIDEBAR-LIBRARY (CompactSidebarLibraryFeature) in Sources/Cursorpad/Features/CompactSidebarLibraryFeature.swift and its real focused checks in Tests/CursorpadTests/CompactSidebarLibraryFeatureTests.swift. Cover direct features FEAT-COMPACT-SIDEBAR-LIBRARY and owned contracts CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE, CON-COMPACT-SIDEBAR-LIBRARY-RECOVERY. Depend only on OWN-LIFECYCLE-COORDINATOR, OWN-PERMISSION-COORDINATOR; implement every documented decision, failure, cancellation, cleanup, and recovery branch. Create only Sources/Cursorpad/Features/CompactSidebarLibraryFeature.swift; Tests/CursorpadTests/CompactSidebarLibraryFeatureTests.swift and modify only Sources/Cursorpad/AppState.swift after its foundation creation.
- REQ-CURSOR-DARK-MONOSPACE-EDITOR — Feature FEAT-CURSOR-DARK-MONOSPACE-EDITOR — The product must Initializes a native TextKit 2 text view configured with SF Mono 13pt typography, 1.45 line height, Cursor background color (#181818), selection tint (#264f78), and active line highlight (#222222). Line numbers render in the gutter with muted foreground (#6e7681). — Acceptance ACC-CURSOR-DARK-MONOSPACE-EDITOR-01, ACC-CURSOR-DARK-MONOSPACE-EDITOR-02, ACC-CURSOR-DARK-MONOSPACE-EDITOR-03: Editor background color precisely matches hexadecimal #181818 in AppKit color space.; Gutter line numbers automatically recalculate as lines are added or removed.; Typing latency remains under 8 milliseconds per keystroke on Apple Silicon hardware.
- REQ-COMMAND-PALETTE-NOTE-NAVIGATION — Feature FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — The product must Displays a floating glassmorphic spotlight modal with an auto-focused search input (#1e1e1e background, #2b2b2b border). As the user types, notes are ranked using prefix and fuzzy subsequence matching. Arrow keys navigate selections and Enter switches notes. — Acceptance ACC-COMMAND-PALETTE-NOTE-NAVIGATION-01, ACC-COMMAND-PALETTE-NOTE-NAVIGATION-02, ACC-COMMAND-PALETTE-NOTE-NAVIGATION-03: Fuzzy search filters a library of 1,000 notes in under 5 milliseconds.; Pressing Command+P opens the palette overlay within 16 milliseconds without layout hitch.; Pressing Escape closes the palette and restores first-responder focus to the editor.
- REQ-NON-BLOCKING-ATOMIC-DISK-STORAGE — Feature FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — The product must Debounces text changes by 250ms and asynchronously writes UTF-8 bytes to the Application Support directory using atomic temporary file swap (NSDataWritingAtomic). — Acceptance ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-01, ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-02, ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-03: App crash or forced termination preserves the last auto-saved note state without file truncation.; Changes are committed to disk via atomic write within 300ms of user typing cessation.; Disk write operations never execute on the main actor thread.
- REQ-COMPACT-SIDEBAR-LIBRARY — Feature FEAT-COMPACT-SIDEBAR-LIBRARY — The product must Renders a compact SwiftUI sidebar (#1e1e1e background) listing notes ordered by last updated timestamp. Displays note title, relative timestamp, and character count. Clicking an item binds the editor to that note. — Acceptance ACC-COMPACT-SIDEBAR-LIBRARY-01, ACC-COMPACT-SIDEBAR-LIBRARY-02, ACC-COMPACT-SIDEBAR-LIBRARY-03: Deleting a note moves the target file to the macOS Trash directory via NSFileManager.; Selecting a note switches the editor contents within 16 milliseconds.; Sidebar list updates note order dynamically when a note is edited.
- ACC-COMMAND-PALETTE-NOTE-NAVIGATION-01 — feature acceptance — Features FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — Owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION — Criterion Fuzzy search filters a library of 1,000 notes in under 5 milliseconds.
- ACC-COMMAND-PALETTE-NOTE-NAVIGATION-02 — feature acceptance — Features FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — Owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION — Criterion Pressing Command+P opens the palette overlay within 16 milliseconds without layout hitch.
- ACC-COMMAND-PALETTE-NOTE-NAVIGATION-03 — feature acceptance — Features FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — Owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION — Criterion Pressing Escape closes the palette and restores first-responder focus to the editor.
- ACC-COMPACT-SIDEBAR-LIBRARY-01 — feature acceptance — Features FEAT-COMPACT-SIDEBAR-LIBRARY — Owner OWN-COMPACT-SIDEBAR-LIBRARY — Criterion Deleting a note moves the target file to the macOS Trash directory via NSFileManager.
- ACC-COMPACT-SIDEBAR-LIBRARY-02 — feature acceptance — Features FEAT-COMPACT-SIDEBAR-LIBRARY — Owner OWN-COMPACT-SIDEBAR-LIBRARY — Criterion Selecting a note switches the editor contents within 16 milliseconds.
- ACC-COMPACT-SIDEBAR-LIBRARY-03 — feature acceptance — Features FEAT-COMPACT-SIDEBAR-LIBRARY — Owner OWN-COMPACT-SIDEBAR-LIBRARY — Criterion Sidebar list updates note order dynamically when a note is edited.
- ACC-CURSOR-DARK-MONOSPACE-EDITOR-01 — feature acceptance — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR — Owner OWN-CURSOR-DARK-MONOSPACE-EDITOR — Criterion Editor background color precisely matches hexadecimal #181818 in AppKit color space.
- ACC-CURSOR-DARK-MONOSPACE-EDITOR-02 — feature acceptance — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR — Owner OWN-CURSOR-DARK-MONOSPACE-EDITOR — Criterion Gutter line numbers automatically recalculate as lines are added or removed.
- ACC-CURSOR-DARK-MONOSPACE-EDITOR-03 — feature acceptance — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR — Owner OWN-CURSOR-DARK-MONOSPACE-EDITOR — Criterion Typing latency remains under 8 milliseconds per keystroke on Apple Silicon hardware.
- ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-01 — feature acceptance — Features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — Owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE — Criterion App crash or forced termination preserves the last auto-saved note state without file truncation.
- ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-02 — feature acceptance — Features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — Owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE — Criterion Changes are committed to disk via atomic write within 300ms of user typing cessation.
- ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-03 — feature acceptance — Features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — Owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE — Criterion Disk write operations never execute on the main actor thread.
- CON-CURSOR-DARK-MONOSPACE-EDITOR-INTERFACE — Cursor Dark Monospace Editor interface (interface) — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR — Owner OWN-CURSOR-DARK-MONOSPACE-EDITOR — Decision Initializes a native TextKit 2 text view configured with SF Mono 13pt typography, 1.45 line height, Cursor background color (#181818), selection tint (#264f78), and active line highlight (#222222). Line numbers render in the gutter with muted foreground (#6e7681). — Details Inputs: User opens a note or creates a new tab with Command+N.; Outputs: Users type in a dark-mode editor styled after the Cursor IDE with line numbers and smooth caret animations. — Failure Falls back to standard macOS monospaced system font if custom font descriptor fails to instantiate. — Recovery Preserve the last valid state, explain the failure, and allow an explicit retry of Cursor Dark Monospace Editor.
- CON-CURSOR-DARK-MONOSPACE-EDITOR-RECOVERY — Cursor Dark Monospace Editor recovery (recovery) — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR — Owner OWN-CURSOR-DARK-MONOSPACE-EDITOR — Decision Treat failure as a terminal or recoverable state exactly as the semantic contract describes. Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state. Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path. — Details Failure: Falls back to standard macOS monospaced system font if custom font descriptor fails to instantiate.; Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state.; Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path. — Failure Falls back to standard macOS monospaced system font if custom font descriptor fails to instantiate. — Recovery Preserve the last valid state, explain the failure, and allow an explicit retry of Cursor Dark Monospace Editor.
- CON-COMMAND-PALETTE-NOTE-NAVIGATION-INTERFACE — Command Palette Note Navigation interface (interface) — Features FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — Owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION — Decision Displays a floating glassmorphic spotlight modal with an auto-focused search input (#1e1e1e background, #2b2b2b border). As the user types, notes are ranked using prefix and fuzzy subsequence matching. Arrow keys navigate selections and Enter switches notes. — Details Inputs: User presses Command+P or Command+K from anywhere in the app window.; Outputs: Users quickly filter and open existing notes using fuzzy title matching without leaving the keyboard. — Failure Displays 'No matching notes found' message when query yields zero results and keeps search field active. — Recovery Preserve the last valid state, explain the failure, and allow an explicit retry of Command Palette Note Navigation.
- CON-COMMAND-PALETTE-NOTE-NAVIGATION-RECOVERY — Command Palette Note Navigation recovery (recovery) — Features FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — Owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION — Decision Treat failure as a terminal or recoverable state exactly as the semantic contract describes. Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state. Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path. — Details Failure: Displays 'No matching notes found' message when query yields zero results and keeps search field active.; Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state.; Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path. — Failure Displays 'No matching notes found' message when query yields zero results and keeps search field active. — Recovery Preserve the last valid state, explain the failure, and allow an explicit retry of Command Palette Note Navigation.
- CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-INTERFACE — Non-Blocking Atomic Disk Storage interface (interface) — Features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — Owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE — Decision Debounces text changes by 250ms and asynchronously writes UTF-8 bytes to the Application Support directory using atomic temporary file swap (NSDataWritingAtomic). — Details Inputs: User edits text or creates a new note.; Outputs: Notes are auto-saved to disk immediately upon editing without blocking UI typing or risking data corruption. — Failure Surfaces a discreet status bar error indicator if disk write fails and retains modified text in memory buffer. — Recovery Preserve the last valid state, explain the failure, and allow an explicit retry of Non-Blocking Atomic Disk Storage.
- CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY — Non-Blocking Atomic Disk Storage recovery (recovery) — Features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — Owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE — Decision Treat failure as a terminal or recoverable state exactly as the semantic contract describes. Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state. Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path. — Details Failure: Surfaces a discreet status bar error indicator if disk write fails and retains modified text in memory buffer.; Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state.; Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path. — Failure Surfaces a discreet status bar error indicator if disk write fails and retains modified text in memory buffer. — Recovery Preserve the last valid state, explain the failure, and allow an explicit retry of Non-Blocking Atomic Disk Storage.
- CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE — Compact Sidebar Library interface (interface) — Features FEAT-COMPACT-SIDEBAR-LIBRARY — Owner OWN-COMPACT-SIDEBAR-LIBRARY — Decision Renders a compact SwiftUI sidebar (#1e1e1e background) listing notes ordered by last updated timestamp. Displays note title, relative timestamp, and character count. Clicking an item binds the editor to that note. — Details Inputs: User toggles sidebar with Command+B or window launch.; Outputs: Users view their note list with modified timestamps, word counts, and search filter. — Failure Shows an empty state prompt inviting the user to press Command+N when no notes exist. — Recovery Preserve the last valid state, explain the failure, and allow an explicit retry of Compact Sidebar Library.
- CON-COMPACT-SIDEBAR-LIBRARY-RECOVERY — Compact Sidebar Library recovery (recovery) — Features FEAT-COMPACT-SIDEBAR-LIBRARY — Owner OWN-COMPACT-SIDEBAR-LIBRARY — Decision Treat failure as a terminal or recoverable state exactly as the semantic contract describes. Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state. Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path. — Details Failure: Shows an empty state prompt inviting the user to press Command+N when no notes exist.; Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state.; Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path. — Failure Shows an empty state prompt inviting the user to press Command+N when no notes exist. — Recovery Preserve the last valid state, explain the failure, and allow an explicit retry of Compact Sidebar Library.
- CON-DATA-NOTEDOCUMENT — NoteDocument (data) — Features  — Owner OWN-DATA-STORE — Decision Represents a single plain text note with metadata and file reference. — Details Retention: Retained locally until explicitly deleted by the user.; Sensitivity: personal — Failure Reject invalid or incomplete records without replacing the last valid state. — Recovery Preserve the last valid record and expose a bounded correction or rebuild path.
- CON-DATA-EDITORCONFIGURATION — EditorConfiguration (data) — Features  — Owner OWN-DATA-STORE — Decision Stores editor preferences including font size, tab width, and word wrap state. — Details Retention: Persisted across application launches in AppStorage.; Sensitivity: personal — Failure Reject invalid or incomplete records without replacing the last valid state. — Recovery Preserve the last valid record and expose a bounded correction or rebuild path.
- CON-LIFECYCLE-APPLICATION-LAUNCH — Application launch (lifecycle) — Features  — Owner OWN-LIFECYCLE-COORDINATOR — Decision Initialize preset-owned state and services without starting privileged capture, remote requests, or destructive work automatically. — Details Cleanup: Rollback partial initialization and keep a safe retry or manual launch path. — Failure An interrupted lifecycle transition must not be reported as complete. — Recovery Rollback partial initialization and keep a safe retry or manual launch path.
- CON-LIFECYCLE-APPLICATION-TERMINATION — Application termination (lifecycle) — Features  — Owner OWN-LIFECYCLE-COORDINATOR — Decision Stop new work, cancel active operations, and preserve only state covered by the persistence contracts. — Details Cleanup: Release permissions, listeners, handles, tasks, clipboard snapshots, and temporary resources before termination completes. — Failure An interrupted lifecycle transition must not be reported as complete. — Recovery Release permissions, listeners, handles, tasks, clipboard snapshots, and temporary resources before termination completes.
- CON-LIFECYCLE-PRESET — Native macOS SwiftUI Desktop lifecycle (lifecycle) — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR, FEAT-COMMAND-PALETTE-NOTE-NAVIGATION, FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE, FEAT-COMPACT-SIDEBAR-LIBRARY — Owner OWN-LIFECYCLE-COORDINATOR — Decision Use WindowGroup as the Dock-first application entry. Cancel tasks and release AppKit delegates during application termination. Model window restoration only for product-owned state. — Details Use WindowGroup as the Dock-first application entry.; Cancel tasks and release AppKit delegates during application termination.; Model window restoration only for product-owned state. — Failure A preset lifecycle invariant failure blocks completion and leaves the last safe state active. — Recovery Restore the last safe lifecycle state, release partial resources, and rerun the focused lifecycle checks.
- CON-PERSISTENCE-NOTEDOCUMENT — NoteDocument persistence (persistence) — Features  — Owner OWN-DATA-STORE — Decision Persistence: enabled with UserDefaults for lightweight settings and SQLite for durable record collections in Application Support. Represents a single plain text note with metadata and file reference. — Details Placement: SQLite in Application Support with schema-versioned transactional migrations and owner-scoped repositories.; Retention: Retained locally until explicitly deleted by the user.; Deletion: Delete NoteDocument only through an explicit user action or the stated retention boundary, and report deletion failure honestly.; Sensitivity: personal — Failure A failed write leaves the prior durable state valid and the new state visibly unsaved. — Recovery Retry through the same atomic boundary without duplicating the record.; Delete NoteDocument only through an explicit user action or the stated retention boundary, and report deletion failure honestly.
- CON-PERSISTENCE-EDITORCONFIGURATION — EditorConfiguration persistence (persistence) — Features  — Owner OWN-DATA-STORE — Decision Persistence: enabled with UserDefaults for lightweight settings and SQLite for durable record collections in Application Support. Stores editor preferences including font size, tab width, and word wrap state. — Details Placement: SQLite in Application Support with schema-versioned transactional migrations and owner-scoped repositories.; Retention: Persisted across application launches in AppStorage.; Deletion: Delete EditorConfiguration only through an explicit user action or the stated retention boundary, and report deletion failure honestly.; Sensitivity: personal — Failure A failed write leaves the prior durable state valid and the new state visibly unsaved. — Recovery Retry through the same atomic boundary without duplicating the record.; Delete EditorConfiguration only through an explicit user action or the stated retention boundary, and report deletion failure honestly.
- CON-PERMISSION-FILESYSTEM — filesystem permission (permission) — Features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE, FEAT-COMPACT-SIDEBAR-LIBRARY — Owner OWN-PERMISSION-COORDINATOR — Decision Use NSOpenPanel and security-scoped bookmarks only for user-selected locations; release every access scope. — Details Purpose: Access only user-selected files and folders required by a feature.; Denied behavior: Leave existing state unchanged and allow another explicit selection. — Failure Leave existing state unchanged and allow another explicit selection. — Recovery Recheck authorization only after an explicit user action and preserve the documented denied path.
- CON-SECURITY-BOUNDARY — Privacy and security boundary (security) — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR, FEAT-COMMAND-PALETTE-NOTE-NAVIGATION, FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE, FEAT-COMPACT-SIDEBAR-LIBRARY — Owner OWN-PACKAGING — Decision Minimize collected data and keep it inside the preset-defined owner, storage, and integration boundaries. Protect NoteDocument as personal data and never expose it through logs or diagnostics. Protect EditorConfiguration as personal data and never expose it through logs or diagnostics. — Details Minimize collected data and keep it inside the preset-defined owner, storage, and integration boundaries.; Protect NoteDocument as personal data and never expose it through logs or diagnostics.; Protect EditorConfiguration as personal data and never expose it through logs or diagnostics. — Failure A privacy or security invariant failure stops the affected operation before data crosses the boundary. — Recovery Restore the last safe state and require explicit user action before retrying.
- CON-PACKAGING-RELEASE — Native macOS SwiftUI Desktop packaging (packaging) — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR, FEAT-COMMAND-PALETTE-NOTE-NAVIGATION, FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE, FEAT-COMPACT-SIDEBAR-LIBRARY — Owner OWN-PACKAGING — Decision Scripts/package_app.sh is the sole packaging authority for release build, app assembly, resources, signing, strict verification, and DMG creation. Assemble one native arm64 macOS .app from the Swift Package Manager release executable, Info.plist, App.entitlements, and AppIcon.icns. Ad-hoc sign local builds or use an explicitly supplied Developer ID for distribution, then require codesign --verify --deep --strict. Register and launch the installed bundle through LaunchServices. — Details Scripts/package_app.sh is the sole packaging authority for release build, app assembly, resources, signing, strict verification, and DMG creation.; Assemble one native arm64 macOS .app from the Swift Package Manager release executable, Info.plist, App.entitlements, and AppIcon.icns.; Ad-hoc sign local builds or use an explicitly supplied Developer ID for distribution, then require codesign --verify --deep --strict.; Register and launch the installed bundle through LaunchServices.; Bundle identity: CFBundleIdentifier = com.cursorpad.app; CFBundleName = CursorPad; CFBundleExecutable = Cursorpad; CFBundleIconFile = AppIcon; CFBundlePackageType = APPL; CFBundleShortVersionString = 1.0.0; CFBundleVersion = 1.; Info.plist ownership: Resources/Info.plist declares CFBundleIdentifier, CFBundleExecutable, CFBundleIconFile, LSMinimumSystemVersion = 13.0, NSHighResolutionCapable = true, NSMicrophoneUsageDescription = "CursorPad uses the microphone only while you explicitly record dictation.", and LSUIElement = false.; Entitlements ownership: Resources/App.entitlements is the only entitlements source and is an XML plist with an empty dictionary for the local unsandboxed build; com.apple.security.app-sandbox and broad file or automation entitlements are absent, and signing passes this reviewed file explicitly.; Icon ownership: Resources/AppIcon.icns is the single source icon copied to Contents/Resources/AppIcon.icns and referenced by CFBundleIconFile.; Architecture: Scripts/package_app.sh runs swift build -c release --arch arm64, rejects a non-arm64 Mach-O executable, and copies .build/arm64-apple-macosx/release/Cursorpad.; App assembly: create dist/CursorPad.app/Contents/MacOS and Contents/Resources, copy the executable to Contents/MacOS/Cursorpad, copy Info.plist to Contents/Info.plist, copy AppIcon.icns to Contents/Resources, and write no competing Packaging.swift implementation.; Signing: Scripts/package_app.sh signs the assembled bundle once with the selected local or distribution identity and Resources/App.entitlements, then runs codesign --verify --deep --strict and rejects any failure before DMG or install.; Launch: after the verified rollback and app copy, register the exact bundle with LaunchServices and launch it with open -b com.cursorpad.app; verify that running bundle identity rather than a path lookalike.; Installation: Install the verified signed app at /Applications/CursorPad.app after a scoped rollback copy, then register and launch that exact bundle through LaunchServices.; Output artifact: native macOS .app and DMG — Failure A failed build, signature, package, install, or launch check blocks completion. — Recovery Fix the first failing validation command, rebuild the artifact, and rerun every later release gate.
