import Foundation
import Testing

@testable import Cursorpad

@Suite("CommandPaletteNoteNavigationFeatureTests")
struct CommandPaletteNoteNavigationFeatureTests {
    // MARK: - Helpers

    private func entry(_ title: String, id: String, at time: TimeInterval = 1_700_000_000) -> PaletteNoteEntry {
        PaletteNoteEntry(id: id, title: title, updatedAt: Date(timeIntervalSince1970: time))
    }

    /// 1,000 realistic note titles with overlapping words, so ranking does real work.
    private func makeThousandNotes() -> [PaletteNoteEntry] {
        let words = ["project", "alpha", "meeting", "notes", "roadmap", "release", "debugging", "parser", "design", "review"]
        return (0..<1_000).map { index in
            let first = words[index % words.count]
            let second = words[(index / words.count) % words.count]
            return PaletteNoteEntry(
                id: "note-\(index)",
                title: "\(first.capitalized) \(second) \(index)",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(index))
            )
        }
    }

    private func median(_ durations: [Duration]) -> Duration {
        let sorted = durations.sorted()
        return sorted[sorted.count / 2]
    }

    private func measure(_ runs: Int, _ body: () -> Void) -> [Duration] {
        let clock = ContinuousClock()
        var durations: [Duration] = []
        for _ in 0..<runs {
            let start = clock.now
            body()
            durations.append(clock.now - start)
        }
        return durations
    }

    // MARK: - CON-COMMAND-PALETTE-NOTE-NAVIGATION-INTERFACE: ranking

    @Test("exact match outranks prefix, and prefix outranks subsequence")
    func rankingOrder() {
        let notes = [
            entry("Project notes: alpha", id: "subsequence", at: 1_700_000_000),
            entry("Project Alpha roadmap", id: "prefix", at: 1_700_000_000),
            entry("project alpha", id: "exact", at: 1_700_000_000)
        ]
        let ranked = CommandPaletteRanking.rank(query: "project alpha", notes: notes)
        #expect(ranked.map(\.id) == ["exact", "prefix", "subsequence"])
        #expect(ranked[0].score > ranked[1].score)
        #expect(ranked[1].score > ranked[2].score)
    }

    @Test("subsequence matching finds characters spread through a title")
    func subsequenceMatching() {
        let notes = [
            entry("Weekly meeting notes", id: "meeting"),
            entry("Unrelated topic", id: "unrelated")
        ]
        let ranked = CommandPaletteRanking.rank(query: "wmnotes", notes: notes)
        #expect(ranked.map(\.id) == ["meeting"])
        #expect(CommandPaletteRanking.score(query: "wmnotes", title: "unrelated topic") == nil)
    }

    @Test("ties are broken by newest update, then title")
    func tieBreaking() {
        let notes = [
            entry("Release checklist", id: "older", at: 1_700_000_000),
            entry("Release checklist", id: "newer", at: 1_700_000_900)
        ]
        let ranked = CommandPaletteRanking.rank(query: "release", notes: notes)
        #expect(ranked.map(\.id) == ["newer", "older"])
    }

    @Test("an empty query lists the newest notes first and respects the result limit")
    func emptyQueryListsNewest() {
        let notes = (0..<10).map { entry("Note \($0)", id: "note-\($0)", at: 1_700_000_000 - Double($0)) }
        #expect(CommandPaletteRanking.rank(query: "", notes: notes).map(\.id).first == "note-0")
        let limited = CommandPaletteRanking.rank(query: "", notes: notes, limit: 3)
        #expect(limited.count == 3)
        #expect(limited.map(\.id) == ["note-0", "note-1", "note-2"])
    }

    // MARK: - CON-COMMAND-PALETTE-NOTE-NAVIGATION-RECOVERY: zero results

    @Test("zero results report the required message and keep the search field active")
    func zeroResultMessage() {
        var session = CommandPaletteSession.presented(candidates: [entry("Project Alpha", id: "alpha")])
        session.updateQuery("zzzzz", candidates: [entry("Project Alpha", id: "alpha")])

        #expect(session.results.isEmpty)
        #expect(session.zeroResultMessage == "No matching notes found")
        #expect(session.query == "zzzzz", "the search field must keep its query")
        #expect(session.selected == nil)
        #expect(!session.isDismissed)

        // Recovering is a pure re-query: the same session finds the note again.
        session.updateQuery("alpha", candidates: [entry("Project Alpha", id: "alpha")])
        #expect(session.results.map(\.id) == ["alpha"])
        #expect(session.zeroResultMessage == nil)
    }

    // MARK: - Keyboard navigation

    @Test("arrow keys navigate and wrap; enter resolves the highlighted note")
    func keyboardNavigation() {
        let notes = [
            entry("Alpha", id: "a", at: 1_700_000_300),
            entry("Beta", id: "b", at: 1_700_000_200),
            entry("Gamma", id: "c", at: 1_700_000_100)
        ]
        var session = CommandPaletteSession.presented(candidates: notes)
        #expect(session.selected?.id == "a")
        session.moveSelection(by: 1)
        #expect(session.selected?.id == "b")
        session.moveSelection(by: 1)
        session.moveSelection(by: 1)
        #expect(session.selected?.id == "a", "down from the last row wraps to the first")
        session.moveSelection(by: -1)
        #expect(session.selected?.id == "c", "up from the first row wraps to the last")

        // A shorter result set clamps the selection instead of going out of bounds.
        session.updateQuery("gamma", candidates: notes)
        #expect(session.selected?.id == "c")
    }

    // MARK: - ACC-COMMAND-PALETTE-NOTE-NAVIGATION-01: 1,000-note fuzzy search under 5 ms

    @Test("fuzzy search filters a library of 1,000 notes in under 5 milliseconds")
    func thousandNoteBenchmark() {
        let notes = makeThousandNotes()
        // Warm the code paths, then measure real runs.
        _ = CommandPaletteRanking.rank(query: "proj", notes: notes)
        let durations = measure(7) {
            let ranked = CommandPaletteRanking.rank(query: "prj alpha", notes: notes)
            #expect(!ranked.isEmpty)
        }
        let observed = median(durations)
        print("[benchmark] fuzzy search over 1,000 notes: median \(observed), runs \(durations)")
        #expect(observed < .milliseconds(5), "median fuzzy search over 1,000 notes took \(observed)")
    }

    // MARK: - ACC-COMMAND-PALETTE-NOTE-NAVIGATION-02: palette opens under 16 ms

    @Test("opening the palette over a real 1,000-note library stays under 16 milliseconds")
    @MainActor
    func openStateBenchmark() async throws {
        let root = try TestEnvironment.makeTempDirectory("palette-benchmark")
        let store = DataStore(paths: DataStore.Paths(rootURL: root))
        try await store.open()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<1_000 {
            _ = try await store.createNote(at: base.addingTimeInterval(-Double(index)))
        }
        await store.close()

        let state = AppState(services: TestEnvironment.makeServices(root: root))
        await state.start()
        #expect(state.notes.count == 1_000)

        // Warm the first presentation, then measure real opens.
        state.presentCommandPalette()
        state.dismissCommandPalette()

        let durations = measure(5) {
            state.presentCommandPalette()
            #expect(state.isCommandPalettePresented)
            #expect(!state.paletteResults.isEmpty)
            state.dismissCommandPalette()
        }
        let observed = median(durations)
        print("[benchmark] palette open over 1,000 notes: median \(observed), runs \(durations)")
        #expect(observed < .milliseconds(16), "opening the palette took \(observed)")
        await state.flushForTermination()
    }

    // MARK: - ACC-COMMAND-PALETTE-NOTE-NAVIGATION-03: escape restores editor focus

    @Test("escape dismisses the palette and restores editor focus")
    @MainActor
    func escapeRestoresFocus() async throws {
        let root = try TestEnvironment.makeTempDirectory("palette-escape")
        let state = AppState(services: TestEnvironment.makeServices(root: root))
        await state.start()
        state.newNote()
        await state.waitForPendingOperations()

        let focusRequestsBefore = state.editorFocusRequests
        state.presentCommandPalette()
        #expect(state.isCommandPalettePresented)
        state.dismissCommandPalette()
        #expect(!state.isCommandPalettePresented)
        #expect(state.editorFocusRequests == focusRequestsBefore + 1)
        #expect(state.paletteQuery.isEmpty, "dismissing must reset the query")
        await state.flushForTermination()
    }

    // MARK: - AppState integration

    @Test("typing, navigating and confirming a palette selection switches the bound note")
    @MainActor
    func confirmSelectsNote() async throws {
        let root = try TestEnvironment.makeTempDirectory("palette-confirm")
        let state = AppState(services: TestEnvironment.makeServices(root: root))
        await state.start()

        state.newNote()
        await state.waitForPendingOperations()
        let first = try #require(state.notes.first)
        state.newNote()
        await state.waitForPendingOperations()
        let second = try #require(state.notes.first)
        #expect(first.id != second.id)

        state.presentCommandPalette()
        state.updatePaletteQuery("untitled")
        #expect(state.paletteResults.count == 2)

        let focusRequestsBefore = state.editorFocusRequests
        state.movePaletteSelection(by: 1)
        let expected = try #require(state.paletteResults.indices.contains(state.paletteSelectedIndex)
            ? state.paletteResults[state.paletteSelectedIndex].id
            : nil)
        state.confirmPaletteSelection()
        await state.waitForPendingOperations()

        #expect(!state.isCommandPalettePresented)
        #expect(state.selectedNoteID == expected)
        #expect(state.editorFocusRequests == focusRequestsBefore + 1)

        // The zero-result path keeps the palette open so the user can retype.
        state.presentCommandPalette()
        state.updatePaletteQuery("no-such-note-title")
        #expect(state.paletteZeroResultMessage == "No matching notes found")
        #expect(state.isCommandPalettePresented)
        state.confirmPaletteSelection()
        #expect(state.isCommandPalettePresented, "Enter on zero results keeps the search field active")
        state.dismissCommandPalette()
        await state.flushForTermination()
    }
}
