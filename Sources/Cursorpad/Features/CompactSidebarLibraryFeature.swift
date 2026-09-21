import Foundation
import SwiftUI

// MARK: - CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE / CON-COMPACT-SIDEBAR-LIBRARY-RECOVERY
//
// The compact sidebar is the library surface: a #1e1e1e list with a #2b2b2b divider, one row per
// note (title, relative timestamp, character count), newest first, no search of its own (the command
// palette is the only search surface). Deleting a note is an explicit user action that moves the
// body file to the macOS Trash through the FileManager trash API *before* the metadata row is
// removed, so a failure can never destroy the user's text.

/// One sidebar row, ready to render. Values are computed once per publish so the row text is
/// deterministic and testable.
struct CompactSidebarRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let updatedAt: Date
    let timestampText: String
    let characterCountText: String
    let isBodyMissing: Bool
    let isSelected: Bool
    let accessibilityLabel: String
}

/// Pure presentation rules for the compact sidebar (ACC-COMPACT-SIDEBAR-LIBRARY-01/02/03).
enum CompactSidebarLibrary {
    /// Locked empty-state copy (CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE failure behavior).
    static let emptyStateTitle = "No notes yet"
    static let emptyStateHint = "Press ⌘N to create your first note."
    static let emptyStateAccessibilityLabel = "Library is empty. Press Command N to create your first note."

    /// Locked delete affordance and failure copy (explicit user action only).
    static let deleteMenuTitle = "Move to Trash"
    static let deleteFailurePrefix = "Could not move this note to the Trash"

    /// Newest-first order, identical to the datastore's `ORDER BY updated_at DESC, id ASC`.
    static func ordered(_ notes: [NoteDocument]) -> [NoteDocument] {
        notes.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id < rhs.id
        }
    }

    /// Builds the rows the sidebar renders. `now` fixes the relative timestamps.
    static func rows(
        notes: [NoteDocument],
        selectedID: String?,
        missingBodyIDs: Set<String>,
        now: Date
    ) -> [CompactSidebarRow] {
        ordered(notes).map { note in
            let isBodyMissing = missingBodyIDs.contains(note.id)
            let timestampText = relativeTimestamp(for: note.updatedAt, relativeTo: now)
            let characterCountText = characterCountText(note.characterCount)
            let isSelected = note.id == selectedID
            return CompactSidebarRow(
                id: note.id,
                title: note.title,
                updatedAt: note.updatedAt,
                timestampText: timestampText,
                characterCountText: characterCountText,
                isBodyMissing: isBodyMissing,
                isSelected: isSelected,
                accessibilityLabel: accessibilityLabel(
                    title: note.title,
                    timestampText: timestampText,
                    characterCountText: characterCountText,
                    isSelected: isSelected,
                    isBodyMissing: isBodyMissing
                )
            )
        }
    }

    /// Compact relative timestamp: "just now", "12m ago", "3h ago", "yesterday", "4d ago",
    /// then a short absolute date for anything older than a week.
    static func relativeTimestamp(for date: Date, relativeTo now: Date) -> String {
        let interval = now.timeIntervalSince(date)
        guard interval >= 60 else { return "just now" }
        if interval < 3_600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3_600))h ago" }
        if interval < 172_800 { return "yesterday" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d ago" }
        return absoluteDateFormatter.string(from: date)
    }

    static func characterCountText(_ count: Int) -> String {
        "\(count) character\(count == 1 ? "" : "s")"
    }

    static func accessibilityLabel(
        title: String,
        timestampText: String,
        characterCountText: String,
        isSelected: Bool,
        isBodyMissing: Bool
    ) -> String {
        var label = "\(title), \(timestampText), \(characterCountText)"
        if isSelected { label += ", selected" }
        if isBodyMissing { label += ", body file missing" }
        return label
    }

    private static let absoluteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

// MARK: - Trash boundary

/// Moves a note body file to the macOS Trash.
///
/// Production is the real `FileManager.trashItem(at:resultingItemURL:)` API — the file ends up in
/// the user's Trash (or the volume's `.Trashes` directory for external volumes), never deleted
/// outright. Tests inject a recorder or a failing implementation to verify the recovery path.
struct BodyTrashService: Sendable {
    var moveToTrash: @Sendable (URL) throws -> URL

    static var live: BodyTrashService {
        BodyTrashService(moveToTrash: { url in
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            return (resultingURL as URL?) ?? url
        })
    }

    /// Ordinary filesystem deletes, used when a test needs a fresh, non-trash removal.
    static var deleting: BodyTrashService {
        BodyTrashService(moveToTrash: { url in
            try FileManager.default.removeItem(at: url)
            return url
        })
    }
}

/// Outcome of trashing one body file.
enum NoteBodyTrashOutcome: Equatable {
    /// The body file was moved to the Trash; `url` is where it landed.
    case movedToTrash(URL)
    /// The body file was already gone (a flagged missing body); nothing to move.
    case alreadyMissing
}

enum NoteBodyTrash {
    /// Moves the body file *before* the metadata delete. A failure here must abort the delete.
    static func moveBodyToTrash(
        fileName: String,
        store: DataStore,
        trash: BodyTrashService,
        fileManager: FileManager = .default
    ) throws -> NoteBodyTrashOutcome {
        let url = store.bodyURL(fileName: fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            return .alreadyMissing
        }
        return .movedToTrash(try trash.moveToTrash(url))
    }
}

// MARK: - Views

/// Compact sidebar surface: #1e1e1e background, #2b2b2b divider, newest-first rows, empty state.
struct CompactSidebarLibraryView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if state.sidebarRows.isEmpty {
                CompactSidebarEmptyStateView(onCreateNote: { state.newNote() })
            } else {
                list
            }
        }
        .background(EditorSurfaceTokens.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(EditorSurfaceTokens.divider)
                .frame(width: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-sidebar")
        .accessibilityLabel("Note library")
    }

    private var list: some View {
        List(selection: $state.selectedNoteID) {
            ForEach(state.sidebarRows) { row in
                CompactSidebarRowView(row: row)
                    .tag(row.id)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button(CompactSidebarLibrary.deleteMenuTitle) {
                            state.deleteNote(id: row.id)
                        }
                        .accessibilityIdentifier("sidebar-delete-\(row.id)")
                    }
                    .accessibilityIdentifier("sidebar-note-\(row.id)")
                    .accessibilityLabel(row.accessibilityLabel)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(EditorSurfaceTokens.sidebarBackground)
        // Keyboard operation: Delete / Command-Delete removes the selected note (explicit action).
        .onDeleteCommand {
            guard let selectedNoteID = state.selectedNoteID else { return }
            state.deleteNote(id: selectedNoteID)
        }
        .accessibilityIdentifier("library-list")
    }
}

/// Row content: title, relative timestamp and character count.
struct CompactSidebarRowView: View {
    let row: CompactSidebarRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
                .font(.system(size: 12, weight: row.isSelected ? .semibold : .medium))
                .foregroundStyle(EditorSurfaceTokens.textPrimary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(row.timestampText)
                Text("·")
                Text(row.characterCountText)
                if row.isBodyMissing {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityLabel("Body file missing")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(EditorSurfaceTokens.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.isSelected ? [.isSelected] : [])
    }
}

/// Honest empty state (CON-COMPACT-SIDEBAR-LIBRARY-INTERFACE failure behavior).
struct CompactSidebarEmptyStateView: View {
    var onCreateNote: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 26))
                .foregroundStyle(EditorSurfaceTokens.textSecondary)
            Text(CompactSidebarLibrary.emptyStateTitle)
                .font(.headline)
                .foregroundStyle(EditorSurfaceTokens.textPrimary)
            Text(CompactSidebarLibrary.emptyStateHint)
                .font(.callout)
                .foregroundStyle(EditorSurfaceTokens.textSecondary)
                .multilineTextAlignment(.center)
            Button("New Note", action: onCreateNote)
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .accessibilityIdentifier("empty-state-new-note-button")
                .accessibilityLabel("New note")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("library-empty-state")
        .accessibilityLabel(CompactSidebarLibrary.emptyStateAccessibilityLabel)
    }
}
