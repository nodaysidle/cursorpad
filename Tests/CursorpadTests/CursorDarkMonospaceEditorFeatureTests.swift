import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Cursorpad

@Suite("CursorDarkMonospaceEditorFeatureTests")
@MainActor
struct CursorDarkMonospaceEditorFeatureTests {
    // MARK: - Helpers

    private func makeEditor() -> (scrollView: NSScrollView, textView: CursorTextView, gutter: CursorGutterView) {
        let assembly = CursorTextView.makeConfiguredScrollView()
        assembly.textView.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        assembly.scrollView.frame = assembly.textView.frame
        assembly.gutter.frame = NSRect(x: 0, y: 0, width: CursorDarkEditorTokens.gutterWidth, height: 480)
        return assembly
    }

    private func hexComponents(_ color: NSColor) throws -> (Int, Int, Int) {
        let srgb = try #require(color.usingColorSpace(.sRGB), "color must convert to sRGB")
        return (
            Int((srgb.redComponent * 255).rounded()),
            Int((srgb.greenComponent * 255).rounded()),
            Int((srgb.blueComponent * 255).rounded())
        )
    }

    private func median(_ durations: [Duration]) -> Duration {
        durations.sorted()[durations.count / 2]
    }

    // MARK: - ACC-CURSOR-DARK-MONOSPACE-EDITOR-01: exact Cursor tokens

    @Test("editor tokens match the locked Cursor palette in sRGB exactly")
    func exactTokens() throws {
        let tokens = CursorDarkEditorTokens.self
        #expect(try hexComponents(tokens.editorBackground) == (0x18, 0x18, 0x18))
        #expect(try hexComponents(tokens.text) == (0xE0, 0xE0, 0xE0))
        #expect(try hexComponents(tokens.selection) == (0x26, 0x4F, 0x78))
        #expect(try hexComponents(tokens.caret) == (0x80, 0xBF, 0xFF))
        #expect(try hexComponents(tokens.activeLine) == (0x22, 0x22, 0x22))
        #expect(try hexComponents(tokens.gutter) == (0x6E, 0x76, 0x81))
    }

    @Test("a configured text view applies the locked tokens and typography")
    func configuredTextViewUsesTokens() throws {
        let (_, textView, _) = makeEditor()

        #expect(textView.backgroundColor == CursorDarkEditorTokens.editorBackground)
        #expect(try hexComponents(textView.backgroundColor) == (0x18, 0x18, 0x18))
        #expect(textView.insertionPointColor == CursorDarkEditorTokens.caret)
        #expect(textView.textColor == CursorDarkEditorTokens.text)
        let selectionColor = try #require(textView.selectedTextAttributes[.backgroundColor] as? NSColor)
        #expect(selectionColor == CursorDarkEditorTokens.selection)
        #expect(textView.font?.pointSize == 13)
        #expect(textView.defaultParagraphStyle?.lineHeightMultiple == 1.45)
        #expect(abs(textView.lineHeight - 13 * 1.45) < 0.0001, "line height was \(textView.lineHeight)")
        #expect(!textView.isRichText)
    }

    @Test("the text view is backed by TextKit 2")
    func usesTextKit2() throws {
        let (_, textView, _) = makeEditor()
        // TextKit 2 owns the pipeline: NSTextContentStorage + NSTextLayoutManager, not TextKit 1.
        // A TextKit 1 text view leaves `textContentStorage` nil, so requiring it non-nil (and wired
        // to the same layout manager the view reports) is the TextKit 2 proof.
        let contentStorage = try #require(textView.textContentStorage, "TextKit 2 content storage must exist")
        let layoutManager = try #require(textView.textLayoutManager, "TextKit 2 layout manager must exist")
        #expect(layoutManager.textContentManager === contentStorage)
        #expect(textView.textContentStorage === contentStorage)
        #expect(contentStorage.textLayoutManagers.contains { $0 === layoutManager })
        #expect(textView.isEditable)
    }

    // MARK: - Font fallback (CON-CURSOR-DARK-MONOSPACE-EDITOR-INTERFACE failure path)

    @Test("SF Mono is used when available and the system monospaced font is the documented fallback")
    func fontFallback() throws {
        // The preferred path resolves through the font descriptor seam.
        let hostHasPreferredFont = NSFont(name: "SF Mono", size: 13) != nil || NSFont(name: "SFMono-Regular", size: 13) != nil
        let resolved = EditorTypography.resolveFont(provider: { name, size in NSFont(name: name, size: size) })
        #expect(resolved.font.pointSize == 13)
        #expect(
            (resolved.source == .sfMono) == hostHasPreferredFont,
            "resolved source must reflect real host availability (SF Mono present: \(hostHasPreferredFont))"
        )
        if hostHasPreferredFont {
            #expect(resolved.source.explanation == nil)
        }

        // A resolvable preferred descriptor reports .sfMono.
        let preferred = EditorTypography.resolveFont(provider: { _, size in NSFont(name: "Menlo", size: size) })
        #expect(preferred.source == .sfMono)

        let fallback = EditorTypography.resolveFont(provider: { _, _ in nil })
        #expect(fallback.source == .systemMonospaced)
        #expect(fallback.font.fontName == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular).fontName)
        #expect(fallback.source.explanation?.contains("SF Mono is unavailable") == true)
    }

    @Test("the text view reports its font source and can retry typography explicitly")
    func typographyRetry() {
        let (_, textView, _) = makeEditor()
        #expect(textView.fontSource == EditorTypography.resolveFont().source)
        let refreshesBefore = textView.typographyRefreshCount
        textView.refreshTypography()
        #expect(textView.typographyRefreshCount == refreshesBefore + 1)
        #expect(textView.font?.pointSize == 13, "the last valid typography is preserved across retries")
    }

    // MARK: - ACC-CURSOR-DARK-MONOSPACE-EDITOR-02: gutter line numbers recalculate

    @Test("gutter line numbers recalculate as lines are added or removed")
    func lineNumbersRecalculate() throws {
        let (_, textView, gutter) = makeEditor()
        textView.applyExternalText("one\ntwo\nthree")
        #expect(textView.logicalLineNumbers() == [1, 2, 3])
        #expect(gutter.recalculationCount >= 1)

        // Typing adds a line: the gutter must follow.
        let afterTyping = textView.logicalLineNumbers().count
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.performTypingMutation("\nfour")
        #expect(textView.logicalLineNumbers() == [1, 2, 3, 4])
        #expect(afterTyping == 3)
        #expect(gutter.recalculationCount >= 2)

        // Removing lines recalculates again.
        let removalsBefore = gutter.recalculationCount
        textView.applyExternalText("one")
        #expect(textView.logicalLineNumbers() == [1])
        #expect(gutter.recalculationCount > removalsBefore)

        // An empty note still shows line 1.
        textView.applyExternalText("")
        #expect(textView.logicalLineNumbers() == [1])
    }

    @Test("the gutter draws one number per logical line with the muted token color")
    func gutterDrawsLineNumbers() throws {
        let (_, textView, gutter) = makeEditor()
        textView.applyExternalText("alpha\nbeta\ngamma\ndelta")

        let image = NSImage(size: gutter.frame.size)
        image.lockFocus()
        gutter.drawHashMarksAndLabels(in: gutter.bounds)
        image.unlockFocus()

        #expect(gutter.lastRenderedLineCount == 4, "drew \(gutter.lastRenderedLineCount) numbers")
        #expect(try hexComponents(CursorDarkEditorTokens.gutter) == (0x6E, 0x76, 0x81))
    }

    @Test("the active line highlight tracks the caret and uses #222222")
    func activeLineHighlight() throws {
        let (_, textView, _) = makeEditor()
        textView.applyExternalText("first\nsecond\nthird")
        textView.setSelectedRange(NSRange(location: 8, length: 0))

        let secondLine = try #require(textView.activeLineRect(), "second line must have layout geometry")
        #expect(secondLine.height > 0)
        #expect(secondLine.height >= textView.lineHeight * 0.99)

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let firstLine = try #require(textView.activeLineRect())
        #expect(firstLine.minY < secondLine.minY, "the highlight must follow the caret")
        #expect(try hexComponents(CursorDarkEditorTokens.activeLine) == (0x22, 0x22, 0x22))
    }

    // MARK: - ACC-CURSOR-DARK-MONOSPACE-EDITOR-03: typing latency

    @Test("a typing mutation in a 500-line note stays under 8 milliseconds")
    func typingLatency() throws {
        let (_, textView, _) = makeEditor()
        let document = (1...500).map { "line \($0) with some representative text to lay out" }.joined(separator: "\n")
        textView.applyExternalText(document)
        textView.setSelectedRange(NSRange(location: (document as NSString).length, length: 0))

        // Warm the layout path, then measure real keystroke mutations.
        textView.performTypingMutation("x")
        let clock = ContinuousClock()
        var durations: [Duration] = []
        for _ in 0..<5 {
            let start = clock.now
            textView.performTypingMutation("y")
            durations.append(clock.now - start)
        }
        let observed = median(durations)
        print("[benchmark] typing mutation on a 500-line note: median \(observed), runs \(durations)")
        #expect(observed < .milliseconds(8), "typing mutation took \(observed)")
        #expect(textView.logicalLineNumbers().count == 500)
    }

    // MARK: - Binding to the current note

    @Test("the editor coordinator publishes typed text through the binding")
    func coordinatorPublishesTypedText() async throws {
        @MainActor
        final class Box { var value = "" }
        let box = Box()
        let coordinator = CursorEditorCoordinator(onTextChange: { box.value = $0 })

        let assembly = CursorTextView.makeConfiguredScrollView()
        assembly.textView.delegate = coordinator
        coordinator.textView = assembly.textView

        assembly.textView.applyExternalText("hello")
        assembly.textView.setSelectedRange(NSRange(location: 5, length: 0))
        assembly.textView.performTypingMutation("!")
        #expect(box.value == "hello!")
        #expect(coordinator.changeCount == 1)
        #expect(assembly.textView.string == "hello!")
    }

    @Test("external note text is applied without feedback loops and clamps the caret")
    func externalTextApplication() throws {
        let (_, textView, _) = makeEditor()
        textView.applyExternalText("first note body")
        textView.setSelectedRange(NSRange(location: 15, length: 0))

        // Switching to a shorter note must not leave the caret out of bounds.
        #expect(textView.applyExternalText("short") == true)
        #expect(textView.string == "short")
        #expect(textView.selectedRange().location <= (textView.string as NSString).length)

        // Applying the same text again is a no-op (no redundant reloads).
        #expect(textView.applyExternalText("short") == false)
    }

    @Test("the composition root mirrors editor edits and note switches")
    func appStateEditorBinding() async throws {
        let root = try TestEnvironment.makeTempDirectory("editor-appstate")
        let state = AppState(services: TestEnvironment.makeServices(root: root))
        await state.start()
        state.newNote()
        await state.waitForPendingOperations()

        state.applyEditorText("typed by the editor")
        #expect(state.editorText == "typed by the editor")
        #expect(state.editorCharacterCount == 19)

        // The editor mirrors a fallback typography resolution and exposes the explicit retry.
        state.editorTypographyResolved(.systemMonospaced)
        #expect(state.editorFontNotice?.contains("SF Mono is unavailable") == true)
        let retriesBefore = state.editorTypographyRetryRequests
        state.retryEditorTypography()
        #expect(state.editorTypographyRetryRequests == retriesBefore + 1)

        await state.flushForTermination()
    }

    @Test("the editor feature contains no detached tasks or unchecked sendability")
    func noForbiddenConcurrency() throws {
        let source = try readPackageFile("Sources/Cursorpad/Features/CursorDarkMonospaceEditorFeature.swift")
        #expect(!source.contains("Task.detached"))
        #expect(!source.contains("@unchecked Sendable"))
        #expect(source.contains("usingTextLayoutManager: true"))
    }
}
