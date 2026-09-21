# AGENTS.md — CursorPad

## Document Purpose

Provide the downstream coding agent with the exact authority, stack lock, execution order, validation gates, stop conditions, and honest completion vocabulary for this project.

## Required Reading Order

1. PRD.md for product scope and outcomes
2. ARD.md for architecture and ownership
3. TRD.md for locked technical contracts
4. TASKS.md for execution order
5. AGENTS.md for operating and completion rules

## Authority Hierarchy

1. The five-document packet as a single execution contract
2. PRD.md for product meaning and scope
3. ARD.md for architecture and ownership
4. TRD.md for technical and release decisions
5. TASKS.md for ordered implementation
6. Existing source only after it is created by the declared task

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

## Forbidden Substitutions

- Forbidden: iOS
- Forbidden: Catalyst
- Forbidden: Flutter
- Forbidden: Tauri
- Forbidden: Electron

## Locked Identity and Output

- Identity: com.cursorpad.app
- Preset: native-macos-swiftui-desktop
- Runtime mode: native
- Artifact: native macOS .app and DMG
- Artifact path: dist/CursorPad.app

## Installation Rule

Install the verified signed app at /Applications/CursorPad.app after a scoped rollback copy, then register and launch that exact bundle through LaunchServices.

## Execution Rules

- Do not reinterpret the idea, add scope, switch stacks, rename IDs, or invent owners.
- Use the exact owner, implementation file, focused test, feature, contract, task, and phase mappings.
- Create files only in the task that first owns them and modify them only after creation.
- Implement failure, denied, cancellation, cleanup, persistence, credential, permission, lifecycle, and recovery paths before declaring a feature complete.
- Keep secrets out of source, logs, tests, fixtures, examples, commands, and generated artifacts.
- Preserve unrelated user work and stop if an undeclared conflict prevents the exact task.
- For Astro static sites with content collections, never move catalog data into browser-side record storage.

## Runtime Architecture Rules

- Use an @main SwiftUI App entry with WindowGroup; one @Observable @MainActor AppState owns presentation state, feature services are injected at the composition root, and AppKit adapters remain in Platform owners.
- Run I/O and provider work in cancellable async tasks or actors off the main actor and publish UI state on the main actor.

## Integration Boundary

Use one actor-owned URLSession boundary: URLSession.data(for:) for HTTPS requests and URLSessionWebSocketTask for streaming; encode and decode typed Codable DTOs, map failures before they reach UI state, and never expose raw response bodies.

## Recovery Rules

- Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state.
- Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path.

## Lifecycle Rules

- Use WindowGroup as the Dock-first application entry.
- Cancel tasks and release AppKit delegates during application termination.
- Model window restoration only for product-owned state.

## Accessibility Rules

- Require VoiceOver and keyboard operation for every control, expose stable accessibility labels, roles, values, and focus order, and verify with SwiftUI accessibility tests plus Accessibility Inspector.

## Owner Map

- OWN-DATA-STORE — DataStore — Sources/Cursorpad/Platform/DataStore.swift — Tests/CursorpadTests/DataStoreTests.swift — create PHASE-02-DATA-STORE — modify none
- OWN-LIFECYCLE-COORDINATOR — LifecycleCoordinator — Sources/Cursorpad/Platform/LifecycleCoordinator.swift — Tests/CursorpadTests/LifecycleCoordinatorTests.swift — create PHASE-03-LIFECYCLE-COORDINATOR — modify none
- OWN-COMMAND-PALETTE-NOTE-NAVIGATION — CommandPaletteNoteNavigationFeature — Sources/Cursorpad/Features/CommandPaletteNoteNavigationFeature.swift — Tests/CursorpadTests/CommandPaletteNoteNavigationFeatureTests.swift — create PHASE-04-COMMAND-PALETTE-NOTE-NAVIGATION — modify none
- OWN-CURSOR-DARK-MONOSPACE-EDITOR — CursorDarkMonospaceEditorFeature — Sources/Cursorpad/Features/CursorDarkMonospaceEditorFeature.swift — Tests/CursorpadTests/CursorDarkMonospaceEditorFeatureTests.swift — create PHASE-05-CURSOR-DARK-MONOSPACE-EDITOR — modify none
- OWN-PERMISSION-COORDINATOR — PermissionCoordinator — Sources/Cursorpad/Platform/PermissionCoordinator.swift — Tests/CursorpadTests/PermissionCoordinatorTests.swift — create PHASE-06-PERMISSION-COORDINATOR — modify none
- OWN-COMPACT-SIDEBAR-LIBRARY — CompactSidebarLibraryFeature — Sources/Cursorpad/Features/CompactSidebarLibraryFeature.swift — Tests/CursorpadTests/CompactSidebarLibraryFeatureTests.swift — create PHASE-07-COMPACT-SIDEBAR-LIBRARY — modify none
- OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE — NonBlockingAtomicDiskStorageFeature — Sources/Cursorpad/Features/NonBlockingAtomicDiskStorageFeature.swift — Tests/CursorpadTests/NonBlockingAtomicDiskStorageFeatureTests.swift — create PHASE-08-NON-BLOCKING-ATOMIC-DISK-STORAGE — modify none
- OWN-PACKAGING — Packaging — Scripts/package_app.sh — Tests/CursorpadTests/PackagingContractTests.swift — create PHASE-09-PACKAGING — modify none

## Required Phase Order

1. PHASE-01-FOUNDATION: Locked foundation; depends on nothing; tasks TASK-01-FOUNDATION
2. PHASE-02-DATA-STORE: DataStore; depends on PHASE-01-FOUNDATION; tasks TASK-02-DATA-STORE
3. PHASE-03-LIFECYCLE-COORDINATOR: LifecycleCoordinator; depends on PHASE-01-FOUNDATION; tasks TASK-03-LIFECYCLE-COORDINATOR
4. PHASE-04-COMMAND-PALETTE-NOTE-NAVIGATION: CommandPaletteNoteNavigationFeature; depends on PHASE-01-FOUNDATION, PHASE-03-LIFECYCLE-COORDINATOR; tasks TASK-04-COMMAND-PALETTE-NOTE-NAVIGATION
5. PHASE-05-CURSOR-DARK-MONOSPACE-EDITOR: CursorDarkMonospaceEditorFeature; depends on PHASE-01-FOUNDATION, PHASE-03-LIFECYCLE-COORDINATOR; tasks TASK-05-CURSOR-DARK-MONOSPACE-EDITOR
6. PHASE-06-PERMISSION-COORDINATOR: PermissionCoordinator; depends on PHASE-01-FOUNDATION; tasks TASK-06-PERMISSION-COORDINATOR
7. PHASE-07-COMPACT-SIDEBAR-LIBRARY: CompactSidebarLibraryFeature; depends on PHASE-01-FOUNDATION, PHASE-03-LIFECYCLE-COORDINATOR, PHASE-06-PERMISSION-COORDINATOR; tasks TASK-07-COMPACT-SIDEBAR-LIBRARY
8. PHASE-08-NON-BLOCKING-ATOMIC-DISK-STORAGE: NonBlockingAtomicDiskStorageFeature; depends on PHASE-01-FOUNDATION, PHASE-03-LIFECYCLE-COORDINATOR, PHASE-06-PERMISSION-COORDINATOR; tasks TASK-08-NON-BLOCKING-ATOMIC-DISK-STORAGE
9. PHASE-09-PACKAGING: Packaging; depends on PHASE-01-FOUNDATION, PHASE-04-COMMAND-PALETTE-NOTE-NAVIGATION, PHASE-07-COMPACT-SIDEBAR-LIBRARY, PHASE-05-CURSOR-DARK-MONOSPACE-EDITOR, PHASE-02-DATA-STORE, PHASE-03-LIFECYCLE-COORDINATOR, PHASE-08-NON-BLOCKING-ATOMIC-DISK-STORAGE, PHASE-06-PERMISSION-COORDINATOR; tasks TASK-09-PACKAGING

## Validation Gates

1. Run `swift test` and require exit status zero.
2. Run `swift build -c release` and require exit status zero.
3. Run `./Scripts/package_app.sh` and require exit status zero.
4. Run `codesign --verify --deep --strict "dist/CursorPad.app"` and require exit status zero.
5. Run `open "dist/CursorPad.app"` and require exit status zero.

## Stop Conditions

- Stop when a requested implementation decision is absent from all five documents.
- Stop when an ID, owner, file, focused test, dependency, or command conflicts across documents.
- Stop when a task would modify a file before its create task.
- Stop when a forbidden technology or undeclared remote service is required.
- Stop when a relevant test, build, package, signing, install, or launch check fails after root-cause diagnosis.
- Report the exact blocker without claiming completion.

## Completion Reporting

- DONE: every declared feature and contract is implemented, every required command passed, the artifact was verified, and no required work remains.
- PARTIAL: safe implemented work is verified but a named external proof or user-controlled action remains; list it precisely.
- BLOCKED: an exact missing authority, unavailable dependency, unsafe conflict, or repeated external failure prevents further safe progress; include the failing command and next action.

## Review Checklist

- Product and non-goal boundaries match PRD.md.
- Architecture and state ownership match ARD.md.
- Stack, files, contracts, permissions, persistence, credentials, lifecycle, recovery, packaging, and signing match TRD.md.
- Task and phase ordering match TASKS.md.
- Focused tests and every final command passed with fresh output.

## Traceability Index

- FEAT-CURSOR-DARK-MONOSPACE-EDITOR — Cursor Dark Monospace Editor — Requirement REQ-CURSOR-DARK-MONOSPACE-EDITOR — Acceptance ACC-CURSOR-DARK-MONOSPACE-EDITOR-01, ACC-CURSOR-DARK-MONOSPACE-EDITOR-02, ACC-CURSOR-DARK-MONOSPACE-EDITOR-03 — Owner OWN-CURSOR-DARK-MONOSPACE-EDITOR — Contracts CON-CURSOR-DARK-MONOSPACE-EDITOR-INTERFACE, CON-CURSOR-DARK-MONOSPACE-EDITOR-RECOVERY, CON-LIFECYCLE-PRESET, CON-SECURITY-BOUNDARY, CON-PACKAGING-RELEASE — Files Sources/Cursorpad/Features/CursorDarkMonospaceEditorFeature.swift; Tests/CursorpadTests/CursorDarkMonospaceEditorFeatureTests.swift — Phase PHASE-05-CURSOR-DARK-MONOSPACE-EDITOR — Task TASK-05-CURSOR-DARK-MONOSPACE-EDITOR depends on TASK-01-FOUNDATION, TASK-03-LIFECYCLE-COORDINATOR
- FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — Command Palette Note Navigation — Requirement REQ-COMMAND-PALETTE-NOTE-NAVIGATION — Acceptance ACC-COMMAND-PALETTE-NOTE-NAVIGATION-01, ACC-COMMAND-PALETTE-NOTE-NAVIGATION-02, ACC-COMMAND-PALETTE-NOTE-NAVIGATION-03 — Owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION — Contracts CON-COMMAND-PALETTE-NOTE-NAVIGATION-INTERFACE, CON-COMMAND-PALETTE-NOTE-NAVIGATION-RECOVERY, CON-LIFECYCLE-PRESET, CON-SECURITY-BOUNDARY, CON-PACKAGING-RELEASE — Files Sources/Cursorpad/Features/CommandPaletteNoteNavigationFeature.swift; Tests/CursorpadTests/CommandPaletteNoteNavigationFeatureTests.swift — Phase PHASE-04-COMMAND-PALETTE-NOTE-NAVIGATION — Task TASK-04-COMMAND-PALETTE-NOTE-NAVIGATION depends on TASK-01-FOUNDATION, TASK-03-LIFECYCLE-COORDINATOR
- FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — Non-Blocking Atomic Disk Storage — Requirement REQ-NON-BLOCKING-ATOMIC-DISK-STORAGE — Acceptance ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-01, ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-02, ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-03 — Owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE — Contracts CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-INTERFACE, CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY, CON-LIFECYCLE-PRESET, CON-PERMISSION-FILESYSTEM, CON-SECURITY-BOUNDARY, CON-PACKAGING-RELEASE — Files Sources/Cursorpad/Features/NonBlockingAtomicDiskStorageFeature.swift; Tests/CursorpadTests/NonBlockingAtomicDiskStorageFeatureTests.swift — Phase PHASE-08-NON-BLOCKING-ATOMIC-DISK-STORAGE — Task TASK-08-NON-BLOCKING-ATOMIC-DISK-STORAGE depends on TASK-01-FOUNDATION, TASK-03-LIFECYCLE-COORDINATOR, TASK-06-PERMISSION-COORDINATOR
- FEAT-COMPACT-SIDEBAR-LIBRARY — Compact Sidebar Library — Requirement REQ-COMPACT-SIDEBAR-LIBRARY — Acceptance ACC-COMPACT-SIDEBAR-LIBRARY-01, ACC-COMPACT-SIDEBAR-LIBRARY-02, ACC-COMPACT-SIDEBAR-LIBRARY-03 — Owner OWN-COMPACT-SIDEBAR-LIBRARY — Contracts CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE, CON-COMPACT-SIDEBAR-LIBRARY-RECOVERY, CON-LIFECYCLE-PRESET, CON-PERMISSION-FILESYSTEM, CON-SECURITY-BOUNDARY, CON-PACKAGING-RELEASE — Files Sources/Cursorpad/Features/CompactSidebarLibraryFeature.swift; Tests/CursorpadTests/CompactSidebarLibraryFeatureTests.swift — Phase PHASE-07-COMPACT-SIDEBAR-LIBRARY — Task TASK-07-COMPACT-SIDEBAR-LIBRARY depends on TASK-01-FOUNDATION, TASK-03-LIFECYCLE-COORDINATOR, TASK-06-PERMISSION-COORDINATOR
- REQ-CURSOR-DARK-MONOSPACE-EDITOR — Feature FEAT-CURSOR-DARK-MONOSPACE-EDITOR — The product must Initializes a native TextKit 2 text view configured with SF Mono 13pt typography, 1.45 line height, Cursor background color (#181818), selection tint (#264f78), and active line highlight (#222222). Line numbers render in the gutter with muted foreground (#6e7681).
- REQ-COMMAND-PALETTE-NOTE-NAVIGATION — Feature FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — The product must Displays a floating glassmorphic spotlight modal with an auto-focused search input (#1e1e1e background, #2b2b2b border). As the user types, notes are ranked using prefix and fuzzy subsequence matching. Arrow keys navigate selections and Enter switches notes.
- REQ-NON-BLOCKING-ATOMIC-DISK-STORAGE — Feature FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — The product must Debounces text changes by 250ms and asynchronously writes UTF-8 bytes to the Application Support directory using atomic temporary file swap (NSDataWritingAtomic).
- REQ-COMPACT-SIDEBAR-LIBRARY — Feature FEAT-COMPACT-SIDEBAR-LIBRARY — The product must Renders a compact SwiftUI sidebar (#1e1e1e background) listing notes ordered by last updated timestamp. Displays note title, relative timestamp, and character count. Clicking an item binds the editor to that note.
- ACC-COMMAND-PALETTE-NOTE-NAVIGATION-01 — feature — Features FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — Owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION
- ACC-COMMAND-PALETTE-NOTE-NAVIGATION-02 — feature — Features FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — Owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION
- ACC-COMMAND-PALETTE-NOTE-NAVIGATION-03 — feature — Features FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — Owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION
- ACC-COMPACT-SIDEBAR-LIBRARY-01 — feature — Features FEAT-COMPACT-SIDEBAR-LIBRARY — Owner OWN-COMPACT-SIDEBAR-LIBRARY
- ACC-COMPACT-SIDEBAR-LIBRARY-02 — feature — Features FEAT-COMPACT-SIDEBAR-LIBRARY — Owner OWN-COMPACT-SIDEBAR-LIBRARY
- ACC-COMPACT-SIDEBAR-LIBRARY-03 — feature — Features FEAT-COMPACT-SIDEBAR-LIBRARY — Owner OWN-COMPACT-SIDEBAR-LIBRARY
- ACC-CURSOR-DARK-MONOSPACE-EDITOR-01 — feature — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR — Owner OWN-CURSOR-DARK-MONOSPACE-EDITOR
- ACC-CURSOR-DARK-MONOSPACE-EDITOR-02 — feature — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR — Owner OWN-CURSOR-DARK-MONOSPACE-EDITOR
- ACC-CURSOR-DARK-MONOSPACE-EDITOR-03 — feature — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR — Owner OWN-CURSOR-DARK-MONOSPACE-EDITOR
- ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-01 — feature — Features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — Owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE
- ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-02 — feature — Features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — Owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE
- ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-03 — feature — Features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — Owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE
- CON-CURSOR-DARK-MONOSPACE-EDITOR-INTERFACE — Cursor Dark Monospace Editor interface (interface) — Owner OWN-CURSOR-DARK-MONOSPACE-EDITOR — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR
- CON-CURSOR-DARK-MONOSPACE-EDITOR-RECOVERY — Cursor Dark Monospace Editor recovery (recovery) — Owner OWN-CURSOR-DARK-MONOSPACE-EDITOR — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR
- CON-COMMAND-PALETTE-NOTE-NAVIGATION-INTERFACE — Command Palette Note Navigation interface (interface) — Owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION — Features FEAT-COMMAND-PALETTE-NOTE-NAVIGATION
- CON-COMMAND-PALETTE-NOTE-NAVIGATION-RECOVERY — Command Palette Note Navigation recovery (recovery) — Owner OWN-COMMAND-PALETTE-NOTE-NAVIGATION — Features FEAT-COMMAND-PALETTE-NOTE-NAVIGATION
- CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-INTERFACE — Non-Blocking Atomic Disk Storage interface (interface) — Owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE — Features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE
- CON-NON-BLOCKING-ATOMIC-DISK-STORAGE-RECOVERY — Non-Blocking Atomic Disk Storage recovery (recovery) — Owner OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE — Features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE
- CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE — Compact Sidebar Library interface (interface) — Owner OWN-COMPACT-SIDEBAR-LIBRARY — Features FEAT-COMPACT-SIDEBAR-LIBRARY
- CON-COMPACT-SIDEBAR-LIBRARY-RECOVERY — Compact Sidebar Library recovery (recovery) — Owner OWN-COMPACT-SIDEBAR-LIBRARY — Features FEAT-COMPACT-SIDEBAR-LIBRARY
- CON-DATA-NOTEDOCUMENT — NoteDocument (data) — Owner OWN-DATA-STORE — Features none
- CON-DATA-EDITORCONFIGURATION — EditorConfiguration (data) — Owner OWN-DATA-STORE — Features none
- CON-LIFECYCLE-APPLICATION-LAUNCH — Application launch (lifecycle) — Owner OWN-LIFECYCLE-COORDINATOR — Features none
- CON-LIFECYCLE-APPLICATION-TERMINATION — Application termination (lifecycle) — Owner OWN-LIFECYCLE-COORDINATOR — Features none
- CON-LIFECYCLE-PRESET — Native macOS SwiftUI Desktop lifecycle (lifecycle) — Owner OWN-LIFECYCLE-COORDINATOR — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR, FEAT-COMMAND-PALETTE-NOTE-NAVIGATION, FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE, FEAT-COMPACT-SIDEBAR-LIBRARY
- CON-PERSISTENCE-NOTEDOCUMENT — NoteDocument persistence (persistence) — Owner OWN-DATA-STORE — Features none
- CON-PERSISTENCE-EDITORCONFIGURATION — EditorConfiguration persistence (persistence) — Owner OWN-DATA-STORE — Features none
- CON-PERMISSION-FILESYSTEM — filesystem permission (permission) — Owner OWN-PERMISSION-COORDINATOR — Features FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE, FEAT-COMPACT-SIDEBAR-LIBRARY
- CON-SECURITY-BOUNDARY — Privacy and security boundary (security) — Owner OWN-PACKAGING — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR, FEAT-COMMAND-PALETTE-NOTE-NAVIGATION, FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE, FEAT-COMPACT-SIDEBAR-LIBRARY
- CON-PACKAGING-RELEASE — Native macOS SwiftUI Desktop packaging (packaging) — Owner OWN-PACKAGING — Features FEAT-CURSOR-DARK-MONOSPACE-EDITOR, FEAT-COMMAND-PALETTE-NOTE-NAVIGATION, FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE, FEAT-COMPACT-SIDEBAR-LIBRARY
