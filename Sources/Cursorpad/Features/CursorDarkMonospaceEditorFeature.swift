import AppKit
import SwiftUI

// MARK: - CON-CURSOR-DARK-MONOSPACE-EDITOR-INTERFACE / CON-CURSOR-DARK-MONOSPACE-EDITOR-RECOVERY
//
// A native AppKit/TextKit 2 editor bridge styled after the Cursor IDE. The SwiftUI layer never
// contains text rendering: `CursorDarkMonospaceEditorView` is a thin `NSViewRepresentable` over
// `CursorTextView` (TextKit 2) plus `CursorGutterView`, and every AppKit touch stays on the main
// actor.

/// Locked Cursor dark editor tokens (PRD success criteria + TRD interface contract).
enum CursorDarkEditorTokens {
    static let editorBackground = NSColor(srgbRed: 0x18 / 255.0, green: 0x18 / 255.0, blue: 0x18 / 255.0, alpha: 1)
    static let text = NSColor(srgbRed: 0xE0 / 255.0, green: 0xE0 / 255.0, blue: 0xE0 / 255.0, alpha: 1)
    static let selection = NSColor(srgbRed: 0x26 / 255.0, green: 0x4F / 255.0, blue: 0x78 / 255.0, alpha: 1)
    static let caret = NSColor(srgbRed: 0x80 / 255.0, green: 0xBF / 255.0, blue: 0xFF / 255.0, alpha: 1)
    static let activeLine = NSColor(srgbRed: 0x22 / 255.0, green: 0x22 / 255.0, blue: 0x22 / 255.0, alpha: 1)
    static let gutter = NSColor(srgbRed: 0x6E / 255.0, green: 0x76 / 255.0, blue: 0x81 / 255.0, alpha: 1)

    static let fontSize: CGFloat = 13
    static let lineHeightMultiple: CGFloat = 1.45
    static let preferredFontName = "SF Mono"
    static let fallbackFontName = "SFMono-Regular"
    static let gutterFontSize: CGFloat = 11
    static let gutterWidth: CGFloat = 44
}

/// Where the editor typography came from. The fallback path is a first-class, explainable state.
enum EditorFontSource: Equatable, Sendable {
    case sfMono
    case systemMonospaced

    /// User-facing explanation for the fallback; `nil` when the preferred font is in use.
    var explanation: String? {
        switch self {
        case .sfMono:
            nil
        case .systemMonospaced:
            "SF Mono is unavailable; using the standard macOS monospaced system font."
        }
    }
}

/// Typography factory for the editor. `resolveFont(provider:)` is the seam that proves the
/// documented fallback (CON-CURSOR-DARK-MONOSPACE-EDITOR-INTERFACE failure behavior).
enum EditorTypography {
    typealias FontProvider = @Sendable (String, CGFloat) -> NSFont?

    static func resolveFont(
        provider: FontProvider = { name, size in NSFont(name: name, size: size) }
    ) -> (font: NSFont, source: EditorFontSource) {
        if let font = provider(CursorDarkEditorTokens.preferredFontName, CursorDarkEditorTokens.fontSize) {
            return (font, .sfMono)
        }
        if let font = provider(CursorDarkEditorTokens.fallbackFontName, CursorDarkEditorTokens.fontSize) {
            return (font, .sfMono)
        }
        return (NSFont.monospacedSystemFont(ofSize: CursorDarkEditorTokens.fontSize, weight: .regular), .systemMonospaced)
    }

    /// 1.45 line height, word wrapping and the editor's fixed tab width.
    static func paragraphStyle(tabWidth: Int = 4) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = CursorDarkEditorTokens.lineHeightMultiple
        style.lineBreakMode = .byWordWrapping
        let charWidth = NSFont.monospacedSystemFont(ofSize: CursorDarkEditorTokens.fontSize, weight: .regular)
            .advancement(forCGGlyph: 32).width
        let tabInterval = max(1, CGFloat(tabWidth)) * charWidth
        style.defaultTabInterval = tabInterval
        style.tabStops = []
        return style
    }
}

// MARK: - Text view

/// TextKit 2 text view with the Cursor dark styling, the active-line highlight and a line-number
/// gutter that recalculates on every edit.
@MainActor
final class CursorTextView: NSTextView {
    private(set) var fontSource: EditorFontSource = .sfMono
    private(set) var typographyRefreshCount = 0
    private(set) var gutterRecalculationCount = 0

    weak var gutter: CursorGutterView?

    /// Designated factory: TextKit 2 layout, locked tokens, locked typography.
    static func makeConfigured() -> CursorTextView {
        let view = CursorTextView(usingTextLayoutManager: true)
        view.configure()
        return view
    }

    /// Scroll view + gutter + text view wired exactly as the window uses them.
    static func makeConfiguredScrollView() -> (scrollView: NSScrollView, textView: CursorTextView, gutter: CursorGutterView) {
        let textView = makeConfigured()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        let gutter = CursorGutterView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        textView.gutter = gutter
        return (scrollView, textView, gutter)
    }

    private func configure() {
        let resolved = EditorTypography.resolveFont()
        fontSource = resolved.source
        applyTypography(resolved.font)

        backgroundColor = CursorDarkEditorTokens.editorBackground
        drawsBackground = true
        insertionPointColor = CursorDarkEditorTokens.caret
        selectedTextAttributes = [.backgroundColor: CursorDarkEditorTokens.selection]
        textColor = CursorDarkEditorTokens.text

        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isEditable = true
        isSelectable = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        usesFindBar = false
        isIncrementalSearchingEnabled = false

        textContainerInset = NSSize(width: 8, height: 6)
        minSize = .zero
        maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        needsDisplay = true
    }

    /// Re-resolves the typography, preserving the last valid state when the preferred font is
    /// missing (explicit retry path for the editor recovery contract).
    func refreshTypography() {
        let resolved = EditorTypography.resolveFont()
        fontSource = resolved.source
        typographyRefreshCount += 1
        applyTypography(resolved.font)
    }

    private func applyTypography(_ font: NSFont) {
        self.font = font
        textColor = CursorDarkEditorTokens.text
        defaultParagraphStyle = EditorTypography.paragraphStyle()
        typingAttributes = [
            .font: font,
            .foregroundColor: CursorDarkEditorTokens.text,
            .paragraphStyle: EditorTypography.paragraphStyle()
        ]
    }

    /// Effective line height for the locked 1.45 multiple.
    var lineHeight: CGFloat {
        let pointSize = font?.pointSize ?? CursorDarkEditorTokens.fontSize
        return pointSize * CursorDarkEditorTokens.lineHeightMultiple
    }

    // MARK: Note binding

    /// Applies externally sourced text (a note switch). Returns `true` when the text actually
    /// changed, so the SwiftUI layer never reloads the same body twice. The caret is clamped into
    /// the new text and the gutter recalculates.
    @discardableResult
    func applyExternalText(_ text: String) -> Bool {
        guard string != text else { return false }
        let previousLocation = selectedRange().location
        string = text
        let length = (string as NSString).length
        setSelectedRange(NSRange(location: min(previousLocation, length), length: 0))
        refreshDerivedState()
        return true
    }

    /// One real keystroke mutation through the AppKit editing path
    /// (`shouldChangeText` → `replaceCharacters` → `didChangeText`).
    func performTypingMutation(_ insertion: String) {
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: insertion) else { return }
        textStorage?.replaceCharacters(in: range, with: insertion)
        setSelectedRange(NSRange(location: range.location + (insertion as NSString).length, length: 0))
        didChangeText()
    }

    override func didChangeText() {
        super.didChangeText()
        refreshDerivedState()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
    }

    private func refreshDerivedState() {
        gutterRecalculationCount += 1
        gutter?.recalculate()
        needsDisplay = true
    }

    // MARK: Line numbers (logical lines)

    var logicalLineCount: Int {
        let text = string
        guard !text.isEmpty else { return 1 }
        var count = 1
        for character in text where character == "\n" { count += 1 }
        return count
    }

    func logicalLineNumbers() -> [Int] {
        Array(1...logicalLineCount)
    }

    /// UTF-16 offsets of each logical line start, aligned with TextKit/NSRange arithmetic.
    func logicalLineStartOffsets() -> [Int] {
        let nsString = string as NSString
        var offsets: [Int] = [0]
        let length = nsString.length
        var location = 0
        while location < length {
            if nsString.character(at: location) == 10 {
                offsets.append(location + 1)
            }
            location += 1
        }
        return offsets
    }

    /// View-space Y of the first layout line at `characterIndex` (TextKit 2 fragments).
    func lineOriginY(characterIndex: Int) -> CGFloat? {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return nil }
        let length = (string as NSString).length
        let clamped = max(0, min(characterIndex, length))
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        guard let location = contentManager.location(layoutManager.documentRange.location, offsetBy: clamped) else {
            return nil
        }
        var originY: CGFloat?
        layoutManager.enumerateTextLayoutFragments(from: location, options: [.ensuresLayout]) { fragment in
            originY = self.textContainerOrigin.y + fragment.layoutFragmentFrame.minY
            return false
        }
        return originY
    }

    /// View-space rect of the caret's logical line, used for the #222222 active-line highlight.
    func activeLineRect() -> NSRect? {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return nil }
        let nsString = string as NSString
        let length = nsString.length
        let insertion = min(selectedRange().location, length)
        let lineRange = nsString.lineRange(for: NSRange(location: insertion, length: 0))
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        guard let location = contentManager.location(layoutManager.documentRange.location, offsetBy: lineRange.location) else {
            return nil
        }
        var rect: NSRect?
        layoutManager.enumerateTextLayoutFragments(from: location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let height = max(frame.height, self.lineHeight)
            rect = NSRect(
                x: 0,
                y: self.textContainerOrigin.y + frame.minY,
                width: self.bounds.width,
                height: height
            )
            return false
        }
        return rect
    }

    // MARK: Drawing

    override func drawBackground(in rect: NSRect) {
        CursorDarkEditorTokens.editorBackground.setFill()
        rect.fill()
        guard let lineRect = activeLineRect(), rect.intersects(lineRect) else { return }
        CursorDarkEditorTokens.activeLine.setFill()
        lineRect.fill()
    }
}

// MARK: - Gutter

/// Line-number gutter: one number per logical line, muted #6e7681, recalculated on every edit.
@MainActor
final class CursorGutterView: NSRulerView {
    weak var textView: CursorTextView?

    private(set) var recalculationCount = 0
    private(set) var lastRenderedLineCount = 0

    init(textView: CursorTextView, scrollView: NSScrollView?) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = CursorDarkEditorTokens.gutterWidth
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("CursorGutterView is created in code only")
    }

    /// Called by the text view after every edit; the next draw re-reads the logical line count.
    func recalculate() {
        recalculationCount += 1
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        CursorDarkEditorTokens.editorBackground.setFill()
        bounds.fill()

        guard let textView else { return }
        let lineStarts = textView.logicalLineStartOffsets()
        lastRenderedLineCount = lineStarts.count

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: CursorDarkEditorTokens.gutterFontSize, weight: .regular),
            .foregroundColor: CursorDarkEditorTokens.gutter
        ]

        for (index, lineStart) in lineStarts.enumerated() {
            guard let yInTextView = textView.lineOriginY(characterIndex: lineStart) else { continue }
            let label = "\(index + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            let yInGutter = convert(NSPoint(x: 0, y: yInTextView), from: textView).y
            label.draw(
                at: NSPoint(x: bounds.width - size.width - 10, y: yInGutter),
                withAttributes: attributes
            )
        }
    }
}

// MARK: - SwiftUI bridge

/// SwiftUI-facing editor. Composition changes only inside `AppState`; the AppKit boundary lives
/// here, on the main actor, with TextKit 2 doing the layout.
struct CursorDarkMonospaceEditorView: NSViewRepresentable {
    /// The currently bound note body, read directly from `AppState` so SwiftUI observation stays
    /// deterministic. The editor never writes through a binding: it reports changes through
    /// `onTextChange`, which the composition root applies.
    var text: String
    var onTextChange: @MainActor (String) -> Void
    var focusRequests: Int = 0
    var typographyRetryRequests: Int = 0
    var onTypographyResolved: @MainActor (EditorFontSource) -> Void = { _ in }

    func makeCoordinator() -> CursorEditorCoordinator {
        CursorEditorCoordinator(onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let assembly = CursorTextView.makeConfiguredScrollView()
        context.coordinator.textView = assembly.textView
        assembly.textView.delegate = context.coordinator
        assembly.textView.applyExternalText(text)
        context.coordinator.observedFocusRequests = focusRequests
        context.coordinator.observedTypographyRetryRequests = typographyRetryRequests
        onTypographyResolved(assembly.textView.fontSource)
        return assembly.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.onTextChange = onTextChange
        textView.applyExternalText(text)

        if context.coordinator.observedFocusRequests != focusRequests {
            context.coordinator.observedFocusRequests = focusRequests
            context.coordinator.requestEditorFocus()
        }
        if context.coordinator.observedTypographyRetryRequests != typographyRetryRequests {
            context.coordinator.observedTypographyRetryRequests = typographyRetryRequests
            textView.refreshTypography()
            onTypographyResolved(textView.fontSource)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: CursorEditorCoordinator) {
        coordinator.textView?.delegate = nil
        coordinator.textView = nil
        scrollView.documentView = nil
    }
}

/// Publishes typed text to the binding and restores first-responder focus on request.
@MainActor
final class CursorEditorCoordinator: NSObject, NSTextViewDelegate {
    var onTextChange: @MainActor (String) -> Void
    weak var textView: CursorTextView?

    private(set) var changeCount = 0
    private(set) var lastPublishedText = ""
    var observedFocusRequests = 0
    var observedTypographyRetryRequests = 0

    init(onTextChange: @MainActor @escaping (String) -> Void) {
        self.onTextChange = onTextChange
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? CursorTextView else { return }
        changeCount += 1
        lastPublishedText = textView.string
        onTextChange(textView.string)
    }

    /// Hands first-responder focus back to the editor (palette dismissal, note switch).
    func requestEditorFocus() {
        guard let textView, let window = textView.window else { return }
        window.makeFirstResponder(textView)
    }
}
