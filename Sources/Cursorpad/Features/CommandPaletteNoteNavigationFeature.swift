import Foundation
import SwiftUI

// MARK: - CON-COMMAND-PALETTE-NOTE-NAVIGATION-INTERFACE / CON-COMMAND-PALETTE-NOTE-NAVIGATION-RECOVERY
//
// The command palette is the only search surface (locked decision). It ranks notes with prefix and
// fuzzy subsequence matching, navigates with the arrow keys, opens with Enter and restores editor
// focus on Escape.

/// A note as the palette sees it: identity, display title and update order.
struct PaletteNoteEntry: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let updatedAt: Date
}

/// One ranked palette row.
struct PaletteRankedNote: Identifiable, Equatable, Sendable {
    let entry: PaletteNoteEntry
    let score: Int

    var id: String { entry.id }
}

/// Deterministic prefix + fuzzy subsequence ranking (ACC-COMMAND-PALETTE-NOTE-NAVIGATION-01).
enum CommandPaletteRanking {
    /// The overlay never renders more rows than this; the input stays responsive on huge libraries.
    static let resultLimit = 200

    /// Locked failure copy (CON-COMMAND-PALETTE-NOTE-NAVIGATION-INTERFACE).
    static let zeroResultMessage = "No matching notes found"

    /// Ranks `notes` for `query`, newest-first for ties. An empty query lists the newest notes.
    static func rank(query: String, notes: [PaletteNoteEntry], limit: Int = resultLimit) -> [PaletteRankedNote] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return notes.prefix(max(0, limit)).map { PaletteRankedNote(entry: $0, score: 0) }
        }

        var matches: [PaletteRankedNote] = []
        matches.reserveCapacity(min(notes.count, limit))
        for note in notes {
            if let score = score(query: trimmed, title: note.title) {
                matches.append(PaletteRankedNote(entry: note, score: score))
            }
        }

        matches.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.updatedAt != rhs.entry.updatedAt { return lhs.entry.updatedAt > rhs.entry.updatedAt }
            if lhs.entry.title != rhs.entry.title { return lhs.entry.title < rhs.entry.title }
            return lhs.entry.id < rhs.entry.id
        }

        if matches.count > limit {
            matches.removeLast(matches.count - limit)
        }
        return matches
    }

    /// Scores one title. Higher is better; `nil` means no match.
    ///
    /// Bands: exact (1000) > prefix (≤900) > word-start / contiguous / gapped subsequence (≤880).
    static func score(query: String, title: String) -> Int? {
        let needle = query.lowercased()
        let haystack = title.lowercased()
        guard !needle.isEmpty else { return 0 }
        if haystack == needle { return 1000 }
        if haystack.hasPrefix(needle) {
            return 900 - min(haystack.count - needle.count, 100)
        }

        let characters = Array(haystack)
        var wordStarts = Set<Int>()
        var atWordBoundary = true
        for (index, character) in characters.enumerated() {
            if character == " " || character == "-" || character == "_" || character == "." || character == "/" {
                atWordBoundary = true
            } else {
                if atWordBoundary { wordStarts.insert(index) }
                atWordBoundary = false
            }
        }

        var needleIndex = needle.startIndex
        var firstMatch: Int?
        var lastMatch: Int?
        var matched = 0
        var index = 0
        while index < characters.count, needleIndex < needle.endIndex {
            if characters[index] == needle[needleIndex] {
                if firstMatch == nil { firstMatch = index }
                lastMatch = index
                matched += 1
                needleIndex = needle.index(after: needleIndex)
            }
            index += 1
        }
        guard matched == needle.count, let first = firstMatch, let last = lastMatch else { return nil }

        let span = last - first + 1
        let gapPenalty = (span - needle.count) * 4
        var score = 700 - gapPenalty - first
        if span == needle.count { score += 60 }
        if wordStarts.contains(first) { score += 120 }
        return max(1, score)
    }
}

/// Palette interaction state: query, ranked rows, highlighted row and dismissal.
///
/// `Equatable` so tests can prove the whole session is preserved on a zero-result query.
struct CommandPaletteSession: Equatable {
    private(set) var query: String = ""
    private(set) var results: [PaletteRankedNote] = []
    private(set) var selectedIndex: Int = 0
    private(set) var isDismissed: Bool = false

    static func presented(candidates: [PaletteNoteEntry]) -> CommandPaletteSession {
        var session = CommandPaletteSession()
        session.updateQuery("", candidates: candidates)
        return session
    }

    /// Re-ranks for the new query. Zero results keep the query and the session active
    /// (CON-COMMAND-PALETTE-NOTE-NAVIGATION-RECOVERY).
    mutating func updateQuery(_ text: String, candidates: [PaletteNoteEntry]) {
        isDismissed = false
        query = text
        results = CommandPaletteRanking.rank(query: text, notes: candidates)
        if results.isEmpty {
            selectedIndex = 0
        } else if selectedIndex >= results.count {
            selectedIndex = results.count - 1
        }
    }

    /// Moves the highlight; wraps at both ends like a spotlight palette.
    mutating func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let count = results.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    mutating func dismiss() {
        isDismissed = true
    }

    var selected: PaletteRankedNote? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    var zeroResultMessage: String? {
        results.isEmpty ? CommandPaletteRanking.zeroResultMessage : nil
    }
}

// MARK: - Overlay

/// Floating styled spotlight overlay: auto-focused search input (#1e1e1e over glass, #2b2b2b
/// border), arrow-key navigation and Enter to open the highlighted note.
struct CommandPaletteOverlayView: View {
    @Bindable var state: AppState

    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Rectangle()
                .fill(EditorSurfaceTokens.divider)
                .frame(height: 1)
            content
        }
        .frame(width: 540)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(EditorSurfaceTokens.sidebarBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(EditorSurfaceTokens.divider, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 28, y: 10)
        .padding(.top, 90)
        .onAppear { searchFieldFocused = true }
        .onExitCommand { state.dismissCommandPalette() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("command-palette")
        .accessibilityLabel("Command palette")
    }

    private var searchField: some View {
        TextField("Search notes", text: queryBinding)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(EditorSurfaceTokens.textPrimary)
            .focused($searchFieldFocused)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .onSubmit { state.confirmPaletteSelection() }
            .onKeyPress(.upArrow) { state.movePaletteSelection(by: -1); return .handled }
            .onKeyPress(.downArrow) { state.movePaletteSelection(by: 1); return .handled }
            .onKeyPress(.escape) { state.dismissCommandPalette(); return .handled }
            .accessibilityLabel("Search notes")
            .accessibilityIdentifier("palette-search-field")
    }

    @ViewBuilder
    private var content: some View {
        if let message = state.paletteZeroResultMessage {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(EditorSurfaceTokens.textSecondary)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("palette-empty-message")
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(state.paletteResults.enumerated()), id: \.element.id) { index, ranked in
                        paletteRow(ranked, isSelected: index == state.paletteSelectedIndex)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
            .frame(maxHeight: 320)
            .accessibilityIdentifier("palette-results")
        }
    }

    private func paletteRow(_ ranked: PaletteRankedNote, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(EditorSurfaceTokens.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(ranked.entry.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(EditorSurfaceTokens.textPrimary)
                    .lineLimit(1)
                Text(ranked.entry.updatedAt, format: .relative(presentation: .named))
                    .font(.system(size: 10))
                    .foregroundStyle(EditorSurfaceTokens.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? EditorSurfaceTokens.accent.opacity(0.22) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { state.selectPaletteResult(id: ranked.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("palette-result-\(ranked.id)")
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { MainActor.assumeIsolated { state.paletteQuery } },
            set: { newValue in MainActor.assumeIsolated { state.updatePaletteQuery(newValue) } }
        )
    }
}
