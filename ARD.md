# Architecture Requirements Document — CursorPad

## Document Purpose

Lock architecture boundaries, component ownership, runtime flows, state placement, platform lifecycle, persistence, security, integrations, and trade-offs without changing product scope.

## Architecture Summary

A modern, ultra-fast native macOS notepad under the selected preset with a signature Cursor dark editor theme, sub-100ms launch, zero-latency TextKit 2 typing, instant fuzzy search, and local atomic persistence. The implementation uses the Native macOS SwiftUI Desktop contract in native runtime mode.

## Architectural Style

- Preset-owned Native macOS SwiftUI Desktop architecture
- Use an @main SwiftUI App entry with WindowGroup; one @Observable @MainActor AppState owns presentation state, feature services are injected at the composition root, and AppKit adapters remain in Platform owners.
- Run I/O and provider work in cancellable async tasks or actors off the main actor and publish UI state on the main actor.
- Vertical feature owners with explicit platform-boundary owners
- One-way feature and contract dependencies following the phase graph
- Local-first state unless product semantics explicitly require a remote service

## Runtime Boundaries

- FEAT-CURSOR-DARK-MONOSPACE-EDITOR — Cursor Dark Monospace Editor: Initializes a native TextKit 2 text view configured with SF Mono 13pt typography, 1.45 line height, Cursor background color (#181818), selection tint (#264f78), and active line highlight (#222222). Line numbers render in the gutter with muted foreground (#6e7681).
- FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — Command Palette Note Navigation: Displays a floating glassmorphic spotlight modal with an auto-focused search input (#1e1e1e background, #2b2b2b border). As the user types, notes are ranked using prefix and fuzzy subsequence matching. Arrow keys navigate selections and Enter switches notes.
- FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — Non-Blocking Atomic Disk Storage: Debounces text changes by 250ms and asynchronously writes UTF-8 bytes to the Application Support directory using atomic temporary file swap (NSDataWritingAtomic).
- FEAT-COMPACT-SIDEBAR-LIBRARY — Compact Sidebar Library: Renders a compact SwiftUI sidebar (#1e1e1e background) listing notes ordered by last updated timestamp. Displays note title, relative timestamp, and character count. Clicking an item binds the editor to that note.

## Component and Ownership Map

- OWN-DATA-STORE — DataStore owns Sources/Cursorpad/Platform/DataStore.swift; focused test Tests/CursorpadTests/DataStoreTests.swift; create phase PHASE-02-DATA-STORE; modify phases none
- OWN-LIFECYCLE-COORDINATOR — LifecycleCoordinator owns Sources/Cursorpad/Platform/LifecycleCoordinator.swift; focused test Tests/CursorpadTests/LifecycleCoordinatorTests.swift; create phase PHASE-03-LIFECYCLE-COORDINATOR; modify phases none
- OWN-COMMAND-PALETTE-NOTE-NAVIGATION — CommandPaletteNoteNavigationFeature owns Sources/Cursorpad/Features/CommandPaletteNoteNavigationFeature.swift; focused test Tests/CursorpadTests/CommandPaletteNoteNavigationFeatureTests.swift; create phase PHASE-04-COMMAND-PALETTE-NOTE-NAVIGATION; modify phases none
- OWN-CURSOR-DARK-MONOSPACE-EDITOR — CursorDarkMonospaceEditorFeature owns Sources/Cursorpad/Features/CursorDarkMonospaceEditorFeature.swift; focused test Tests/CursorpadTests/CursorDarkMonospaceEditorFeatureTests.swift; create phase PHASE-05-CURSOR-DARK-MONOSPACE-EDITOR; modify phases none
- OWN-PERMISSION-COORDINATOR — PermissionCoordinator owns Sources/Cursorpad/Platform/PermissionCoordinator.swift; focused test Tests/CursorpadTests/PermissionCoordinatorTests.swift; create phase PHASE-06-PERMISSION-COORDINATOR; modify phases none
- OWN-COMPACT-SIDEBAR-LIBRARY — CompactSidebarLibraryFeature owns Sources/Cursorpad/Features/CompactSidebarLibraryFeature.swift; focused test Tests/CursorpadTests/CompactSidebarLibraryFeatureTests.swift; create phase PHASE-07-COMPACT-SIDEBAR-LIBRARY; modify phases none
- OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE — NonBlockingAtomicDiskStorageFeature owns Sources/Cursorpad/Features/NonBlockingAtomicDiskStorageFeature.swift; focused test Tests/CursorpadTests/NonBlockingAtomicDiskStorageFeatureTests.swift; create phase PHASE-08-NON-BLOCKING-ATOMIC-DISK-STORAGE; modify phases none
- OWN-PACKAGING — Packaging owns Scripts/package_app.sh; focused test Tests/CursorpadTests/PackagingContractTests.swift; create phase PHASE-09-PACKAGING; modify phases none

## Runtime Flows

1. Cursor Dark Monospace Editor outcome: User opens a note or creates a new tab with Command+N. → Initializes a native TextKit 2 text view configured with SF Mono 13pt typography, 1.45 line height, Cursor background color (#181818), selection tint (#264f78), and active line highlight (#222222). Line numbers render in the gutter with muted foreground (#6e7681). → Users type in a dark-mode editor styled after the Cursor IDE with line numbers and smooth caret animations.
2. Command Palette Note Navigation outcome: User presses Command+P or Command+K from anywhere in the app window. → Displays a floating glassmorphic spotlight modal with an auto-focused search input (#1e1e1e background, #2b2b2b border). As the user types, notes are ranked using prefix and fuzzy subsequence matching. Arrow keys navigate selections and Enter switches notes. → Users quickly filter and open existing notes using fuzzy title matching without leaving the keyboard.
3. Non-Blocking Atomic Disk Storage outcome: User edits text or creates a new note. → Debounces text changes by 250ms and asynchronously writes UTF-8 bytes to the Application Support directory using atomic temporary file swap (NSDataWritingAtomic). → Notes are auto-saved to disk immediately upon editing without blocking UI typing or risking data corruption.
4. Compact Sidebar Library outcome: User toggles sidebar with Command+B or window launch. → Renders a compact SwiftUI sidebar (#1e1e1e background) listing notes ordered by last updated timestamp. Displays note title, relative timestamp, and character count. Clicking an item binds the editor to that note. → Users view their note list with modified timestamps, word counts, and search filter.

## State Ownership

- Persistence: enabled with UserDefaults for lightweight settings and SQLite for durable record collections in Application Support.
- Settings placement: UserDefaults with versioned keys and explicit reset behavior.
- Record placement: SQLite in Application Support with schema-versioned transactional migrations and owner-scoped repositories.
- OWN-DATA-STORE owns state mutated through Sources/Cursorpad/Platform/DataStore.swift.
- OWN-LIFECYCLE-COORDINATOR owns state mutated through Sources/Cursorpad/Platform/LifecycleCoordinator.swift.
- OWN-COMMAND-PALETTE-NOTE-NAVIGATION owns state mutated through Sources/Cursorpad/Features/CommandPaletteNoteNavigationFeature.swift.
- OWN-CURSOR-DARK-MONOSPACE-EDITOR owns state mutated through Sources/Cursorpad/Features/CursorDarkMonospaceEditorFeature.swift.
- OWN-PERMISSION-COORDINATOR owns state mutated through Sources/Cursorpad/Platform/PermissionCoordinator.swift.
- OWN-COMPACT-SIDEBAR-LIBRARY owns state mutated through Sources/Cursorpad/Features/CompactSidebarLibraryFeature.swift.
- OWN-NON-BLOCKING-ATOMIC-DISK-STORAGE owns state mutated through Sources/Cursorpad/Features/NonBlockingAtomicDiskStorageFeature.swift.
- OWN-PACKAGING owns state mutated through Scripts/package_app.sh.

## Platform Lifecycle

- Use WindowGroup as the Dock-first application entry.
- Cancel tasks and release AppKit delegates during application termination.
- Model window restoration only for product-owned state.
- Initialize preset-owned state and services without starting privileged capture, remote requests, or destructive work automatically.
- Stop new work, cancel active operations, and preserve only state covered by the persistence contracts.
- Use WindowGroup as the Dock-first application entry. Cancel tasks and release AppKit delegates during application termination. Model window restoration only for product-owned state.
- CON-LIFECYCLE-APPLICATION-LAUNCH: Initialize preset-owned state and services without starting privileged capture, remote requests, or destructive work automatically. Cleanup: Rollback partial initialization and keep a safe retry or manual launch path.
- CON-LIFECYCLE-APPLICATION-TERMINATION: Stop new work, cancel active operations, and preserve only state covered by the persistence contracts. Cleanup: Release permissions, listeners, handles, tasks, clipboard snapshots, and temporary resources before termination completes.
- CON-LIFECYCLE-PRESET: Use WindowGroup as the Dock-first application entry. Cancel tasks and release AppKit delegates during application termination. Model window restoration only for product-owned state. Cleanup: Restore the last safe lifecycle state, release partial resources, and rerun the focused lifecycle checks.
- Application launch: Initialize preset-owned state and services without starting privileged capture, remote requests, or destructive work automatically. Cleanup: Rollback partial initialization and keep a safe retry or manual launch path.
- Application termination: Stop new work, cancel active operations, and preserve only state covered by the persistence contracts. Cleanup: Release permissions, listeners, handles, tasks, clipboard snapshots, and temporary resources before termination completes.

## Persistence Placement

- Persistence: enabled with UserDefaults for lightweight settings and SQLite for durable record collections in Application Support.
- Settings: UserDefaults with versioned keys and explicit reset behavior.
- Records: SQLite in Application Support with schema-versioned transactional migrations and owner-scoped repositories.

## Security Boundaries

- Minimize collected data and keep it inside the preset-defined owner, storage, and integration boundaries.
- Protect NoteDocument as personal data and never expose it through logs or diagnostics.
- Protect EditorConfiguration as personal data and never expose it through logs or diagnostics.
- CON-PERMISSION-FILESYSTEM: Use NSOpenPanel and security-scoped bookmarks only for user-selected locations; release every access scope.
- CON-SECURITY-BOUNDARY: Minimize collected data and keep it inside the preset-defined owner, storage, and integration boundaries. Protect NoteDocument as personal data and never expose it through logs or diagnostics. Protect EditorConfiguration as personal data and never expose it through logs or diagnostics.

## Accessibility Boundary

- Require VoiceOver and keyboard operation for every control, expose stable accessibility labels, roles, values, and focus order, and verify with SwiftUI accessibility tests plus Accessibility Inspector.

## External Integration Placement

- Use one actor-owned URLSession boundary: URLSession.data(for:) for HTTPS requests and URLSessionWebSocketTask for streaming; encode and decode typed Codable DTOs, map failures before they reach UI state, and never expose raw response bodies.
- No external service is activated by this product contract.

## Recovery Architecture

- Represent operations as idle, active, succeeded, failed, or cancelled and preserve the last valid user state.
- Use explicit user retries only; cancel tasks and close streams, file handles, delegates, and temporary resources on every terminal path.

## Packaging and Installation

- Scripts/package_app.sh is the sole packaging authority for release build, app assembly, resources, signing, strict verification, and DMG creation.
- Assemble one native arm64 macOS .app from the Swift Package Manager release executable, Info.plist, App.entitlements, and AppIcon.icns.
- Ad-hoc sign local builds or use an explicitly supplied Developer ID for distribution, then require codesign --verify --deep --strict.
- Register and launch the installed bundle through LaunchServices.
- Install the verified signed app at /Applications/CursorPad.app after a scoped rollback copy, then register and launch that exact bundle through LaunchServices.
- Output artifact: native macOS .app and DMG
- Artifact path: dist/CursorPad.app

## Architectural Trade-offs

- Preset fidelity is favored over cross-stack reuse.
- Deterministic owner and file mappings are favored over runtime plugin discovery.
- Durable local recovery is favored over transient simplicity.
- No server runtime is introduced.

## Architecture Review Checklist

- Every feature has one owner and one focused test.
- Every contract resolves to known features and one owner.
- Every modified file is created in an earlier phase.
- Persistence, permissions, credentials, lifecycle, recovery, packaging, and signing are explicit.
- No forbidden technology appears in an implementation decision.

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
