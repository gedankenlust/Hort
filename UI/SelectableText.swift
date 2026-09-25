import SwiftUI
import AppKit

/// Read-only, selectable text (NSTextView) so the inspector content supports
/// native ⌘A select-all and copy. It reports its first-responder state to
/// AppState so the feed's ⌘A ("select all cards") stands down while this text
/// is focused, and the feed re-claims ⌘A when a card is clicked (which resigns
/// this view's first-responder status).
struct SelectableText: NSViewRepresentable {
    let text: String

    /// Explicit sRGB — do not bridge `HortColors.textPrimary` via `NSColor(Color)`,
    /// which can resolve to black/clear outside a SwiftUI environment and yield
    /// an empty-looking black content box on the dark inspector surface.
    private static let foreground = NSColor(srgbRed: 0xF1 / 255,
                                            green: 0xF4 / 255,
                                            blue: 0xF9 / 255,
                                            alpha: 1)
    private static let bodyFont = NSFont.systemFont(ofSize: 12)

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]
        // NSClipView defaults to an opaque fill; keep it clear so the SwiftUI
        // `.background(HortColors.background)` is what the user sees.
        scroll.contentView.drawsBackground = false
        scroll.contentView.backgroundColor = .clear

        let textView = FocusReportingTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.appearance = NSAppearance(named: .darkAqua)

        // Size the text view to the scroll view so wrapping and drawing work
        // inside SwiftUI's flexible frame proposals.
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        apply(text, to: textView)
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            apply(text, to: textView)
        }
        // Keep width tracking in sync when SwiftUI resizes the representable.
        let width = max(nsView.contentSize.width, 1)
        textView.textContainer?.containerSize = NSSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    private func apply(_ string: String, to textView: NSTextView) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: Self.foreground,
            .font: Self.bodyFont
        ]
        textView.typingAttributes = attrs
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: string, attributes: attrs)
        )
    }
}

/// NSTextView that mirrors its first-responder state into AppState so the feed's
/// ⌘A shortcut can yield to text select-all while this view is focused.
final class FocusReportingTextView: NSTextView {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { DispatchQueue.main.async { AppState.shared.inspectorTextFocused = true } }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { DispatchQueue.main.async { AppState.shared.inspectorTextFocused = false } }
        return ok
    }
}
