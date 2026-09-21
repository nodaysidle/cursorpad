# Product Requirements Document — CursorPad

## Document Purpose

Define the product boundary, users, problems, goals, journeys, feature outcomes, success criteria, and explicit scope without implementation invention.

## Product Definition

A modern, ultra-fast native macOS notepad under the selected preset with a signature Cursor dark editor theme, sub-100ms launch, zero-latency TextKit 2 typing, instant fuzzy search, and local atomic persistence.

## Problem Statement

macOS developers and power users wanting a distraction-free notepad that matches the Cursor editor palette need a focused way to render text with zero perceptible typing latency using native TextKit 2 and Metal-backed glyph caching without cloud syncing, account login, telemetry, or remote server dependencies.

## Target Users

- macOS developers and power users wanting a distraction-free notepad that matches the Cursor editor palette
- Engineers capturing scratch code, terminal output, and markdown notes without heavy Electron lag

## Goals

- Render text with zero perceptible typing latency using native TextKit 2 and Metal-backed glyph caching
- Match the exact modern Cursor aesthetic with custom dark tokens (#181818 background, #1e1e1e sidebar, #2b2b2b border, #80bfff blue accent, and #e0e0e0 text)
- Launch from the Dock or global hotkey in under 100 milliseconds with state instantly restored
- Persist all notes as local plain-text/markdown files with atomic non-blocking disk operations

## Non-Goals

- Cloud syncing, account login, telemetry, or remote server dependencies
- WYSIWYG rich text styling, word processor formatting, or PDF printing tools
- In-app code execution, compilation, or LSP terminal debugging

## Primary User Journeys

### Cursor Dark Monospace Editor outcome

- Actor: macOS developers and power users wanting a distraction-free notepad that matches the Cursor editor palette
- Steps: User opens a note or creates a new tab with Command+N. → Initializes a native TextKit 2 text view configured with SF Mono 13pt typography, 1.45 line height, Cursor background color (#181818), selection tint (#264f78), and active line highlight (#222222). Line numbers render in the gutter with muted foreground (#6e7681).
- Outcome: Users type in a dark-mode editor styled after the Cursor IDE with line numbers and smooth caret animations.

### Command Palette Note Navigation outcome

- Actor: macOS developers and power users wanting a distraction-free notepad that matches the Cursor editor palette
- Steps: User presses Command+P or Command+K from anywhere in the app window. → Displays a floating glassmorphic spotlight modal with an auto-focused search input (#1e1e1e background, #2b2b2b border). As the user types, notes are ranked using prefix and fuzzy subsequence matching. Arrow keys navigate selections and Enter switches notes.
- Outcome: Users quickly filter and open existing notes using fuzzy title matching without leaving the keyboard.

### Non-Blocking Atomic Disk Storage outcome

- Actor: macOS developers and power users wanting a distraction-free notepad that matches the Cursor editor palette
- Steps: User edits text or creates a new note. → Debounces text changes by 250ms and asynchronously writes UTF-8 bytes to the Application Support directory using atomic temporary file swap (NSDataWritingAtomic).
- Outcome: Notes are auto-saved to disk immediately upon editing without blocking UI typing or risking data corruption.

### Compact Sidebar Library outcome

- Actor: macOS developers and power users wanting a distraction-free notepad that matches the Cursor editor palette
- Steps: User toggles sidebar with Command+B or window launch. → Renders a compact SwiftUI sidebar (#1e1e1e background) listing notes ordered by last updated timestamp. Displays note title, relative timestamp, and character count. Clicking an item binds the editor to that note.
- Outcome: Users view their note list with modified timestamps, word counts, and search filter.

## Feature Contracts

### FEAT-CURSOR-DARK-MONOSPACE-EDITOR — Cursor Dark Monospace Editor

- Behavior: Initializes a native TextKit 2 text view configured with SF Mono 13pt typography, 1.45 line height, Cursor background color (#181818), selection tint (#264f78), and active line highlight (#222222). Line numbers render in the gutter with muted foreground (#6e7681).
- Inputs: User opens a note or creates a new tab with Command+N.
- Outputs: Users type in a dark-mode editor styled after the Cursor IDE with line numbers and smooth caret animations.
- Acceptance outcomes: Editor background color precisely matches hexadecimal #181818 in AppKit color space.; Gutter line numbers automatically recalculate as lines are added or removed.; Typing latency remains under 8 milliseconds per keystroke on Apple Silicon hardware.
- Failure behavior: Falls back to standard macOS monospaced system font if custom font descriptor fails to instantiate.
- Recovery: Preserve the last valid state, explain the failure, and allow an explicit retry of Cursor Dark Monospace Editor.

### FEAT-COMMAND-PALETTE-NOTE-NAVIGATION — Command Palette Note Navigation

- Behavior: Displays a floating glassmorphic spotlight modal with an auto-focused search input (#1e1e1e background, #2b2b2b border). As the user types, notes are ranked using prefix and fuzzy subsequence matching. Arrow keys navigate selections and Enter switches notes.
- Inputs: User presses Command+P or Command+K from anywhere in the app window.
- Outputs: Users quickly filter and open existing notes using fuzzy title matching without leaving the keyboard.
- Acceptance outcomes: Fuzzy search filters a library of 1,000 notes in under 5 milliseconds.; Pressing Command+P opens the palette overlay within 16 milliseconds without layout hitch.; Pressing Escape closes the palette and restores first-responder focus to the editor.
- Failure behavior: Displays 'No matching notes found' message when query yields zero results and keeps search field active.
- Recovery: Preserve the last valid state, explain the failure, and allow an explicit retry of Command Palette Note Navigation.

### FEAT-NON-BLOCKING-ATOMIC-DISK-STORAGE — Non-Blocking Atomic Disk Storage

- Behavior: Debounces text changes by 250ms and asynchronously writes UTF-8 bytes to the Application Support directory using atomic temporary file swap (NSDataWritingAtomic).
- Inputs: User edits text or creates a new note.
- Outputs: Notes are auto-saved to disk immediately upon editing without blocking UI typing or risking data corruption.
- Acceptance outcomes: App crash or forced termination preserves the last auto-saved note state without file truncation.; Changes are committed to disk via atomic write within 300ms of user typing cessation.; Disk write operations never execute on the main actor thread.
- Failure behavior: Surfaces a discreet status bar error indicator if disk write fails and retains modified text in memory buffer.
- Recovery: Preserve the last valid state, explain the failure, and allow an explicit retry of Non-Blocking Atomic Disk Storage.

### FEAT-COMPACT-SIDEBAR-LIBRARY — Compact Sidebar Library

- Behavior: Renders a compact SwiftUI sidebar (#1e1e1e background) listing notes ordered by last updated timestamp. Displays note title, relative timestamp, and character count. Clicking an item binds the editor to that note.
- Inputs: User toggles sidebar with Command+B or window launch.
- Outputs: Users view their note list with modified timestamps, word counts, and search filter.
- Acceptance outcomes: Deleting a note moves the target file to the macOS Trash directory via NSFileManager.; Selecting a note switches the editor contents within 16 milliseconds.; Sidebar list updates note order dynamically when a note is edited.
- Failure behavior: Shows an empty state prompt inviting the user to press Command+N when no notes exist.
- Recovery: Preserve the last valid state, explain the failure, and allow an explicit retry of Compact Sidebar Library.

## Requirement Contracts

- REQ-CURSOR-DARK-MONOSPACE-EDITOR — The product must Initializes a native TextKit 2 text view configured with SF Mono 13pt typography, 1.45 line height, Cursor background color (#181818), selection tint (#264f78), and active line highlight (#222222). Line numbers render in the gutter with muted foreground (#6e7681). Acceptance ACC-CURSOR-DARK-MONOSPACE-EDITOR-01, ACC-CURSOR-DARK-MONOSPACE-EDITOR-02, ACC-CURSOR-DARK-MONOSPACE-EDITOR-03: Editor background color precisely matches hexadecimal #181818 in AppKit color space.; Gutter line numbers automatically recalculate as lines are added or removed.; Typing latency remains under 8 milliseconds per keystroke on Apple Silicon hardware.
- REQ-COMMAND-PALETTE-NOTE-NAVIGATION — The product must Displays a floating glassmorphic spotlight modal with an auto-focused search input (#1e1e1e background, #2b2b2b border). As the user types, notes are ranked using prefix and fuzzy subsequence matching. Arrow keys navigate selections and Enter switches notes. Acceptance ACC-COMMAND-PALETTE-NOTE-NAVIGATION-01, ACC-COMMAND-PALETTE-NOTE-NAVIGATION-02, ACC-COMMAND-PALETTE-NOTE-NAVIGATION-03: Fuzzy search filters a library of 1,000 notes in under 5 milliseconds.; Pressing Command+P opens the palette overlay within 16 milliseconds without layout hitch.; Pressing Escape closes the palette and restores first-responder focus to the editor.
- REQ-NON-BLOCKING-ATOMIC-DISK-STORAGE — The product must Debounces text changes by 250ms and asynchronously writes UTF-8 bytes to the Application Support directory using atomic temporary file swap (NSDataWritingAtomic). Acceptance ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-01, ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-02, ACC-NON-BLOCKING-ATOMIC-DISK-STORAGE-03: App crash or forced termination preserves the last auto-saved note state without file truncation.; Changes are committed to disk via atomic write within 300ms of user typing cessation.; Disk write operations never execute on the main actor thread.
- REQ-COMPACT-SIDEBAR-LIBRARY — The product must Renders a compact SwiftUI sidebar (#1e1e1e background) listing notes ordered by last updated timestamp. Displays note title, relative timestamp, and character count. Clicking an item binds the editor to that note. Acceptance ACC-COMPACT-SIDEBAR-LIBRARY-01, ACC-COMPACT-SIDEBAR-LIBRARY-02, ACC-COMPACT-SIDEBAR-LIBRARY-03: Deleting a note moves the target file to the macOS Trash directory via NSFileManager.; Selecting a note switches the editor contents within 16 milliseconds.; Sidebar list updates note order dynamically when a note is edited.

## Shared End-to-End Acceptance

- No shared acceptance criterion requires the final integration and packaging gate.

## UX Requirements

- Cold launch to responsive typing state must complete within 100 milliseconds.
- Memory footprint must remain under 40MB for a 500-note library.
- Keyboard shortcuts must align with standard macOS conventions (Cmd+N, Cmd+P, Cmd+B, Cmd+W).

## Privacy and Security Requirements

- Minimize collected data and keep it inside the preset-defined owner, storage, and integration boundaries.
- Protect NoteDocument as personal data and never expose it through logs or diagnostics.
- Protect EditorConfiguration as personal data and never expose it through logs or diagnostics.

## Operational Constraints

- the local validation command strict concurrency with zero compiler concurrency warnings.
- macOS 14+ target utilizing native SwiftUI and TextKit 2 without Electron or WebKit.
- Zero network access or third-party tracking libraries.

## Success Criteria

- Render text with zero perceptible typing latency using native TextKit 2 and Metal-backed glyph caching
- Match the exact modern Cursor aesthetic with custom dark tokens (#181818 background, #1e1e1e sidebar, #2b2b2b border, #80bfff blue accent, and #e0e0e0 text)
- Launch from the Dock or global hotkey in under 100 milliseconds with state instantly restored
- Persist all notes as local plain-text/markdown files with atomic non-blocking disk operations
- Editor background color precisely matches hexadecimal #181818 in AppKit color space.
- Typing latency remains under 8 milliseconds per keystroke on Apple Silicon hardware.
- Gutter line numbers automatically recalculate as lines are added or removed.
- Pressing Command+P opens the palette overlay within 16 milliseconds without layout hitch.
- Fuzzy search filters a library of 1,000 notes in under 5 milliseconds.
- Pressing Escape closes the palette and restores first-responder focus to the editor.
- Changes are committed to disk via atomic write within 300ms of user typing cessation.
- App crash or forced termination preserves the last auto-saved note state without file truncation.
- Disk write operations never execute on the main actor thread.
- Sidebar list updates note order dynamically when a note is edited.
- Selecting a note switches the editor contents within 16 milliseconds.
- Deleting a note moves the target file to the macOS Trash directory via NSFileManager.

## Explicit Assumptions

- The selected preset is authoritative for every technology and mechanical decision.
- Omitted mechanics use the conservative preset-defined contract without another provider request.

## Scope Boundaries

- Included features: Cursor Dark Monospace Editor; Command Palette Note Navigation; Non-Blocking Atomic Disk Storage; Compact Sidebar Library
- Excluded outcomes: Cloud syncing, account login, telemetry, or remote server dependencies; WYSIWYG rich text styling, word processor formatting, or PDF printing tools; In-app code execution, compilation, or LSP terminal debugging
- Locked delivery preset: native-macos-swiftui-desktop

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
