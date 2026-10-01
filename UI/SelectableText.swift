import SwiftUI
import AppKit

/// Read-only, selectable text (NSTextView) so the inspector supports native
/// ⌘A / copy. Intentionally **not** wrapped in an NSScrollView — nesting that
/// inside the inspector's SwiftUI ScrollView inflated AppKit hit regions past
/// the clipped visual bounds (offset hover on the action buttons) and stole
/// scroll events so the panel couldn't reach the bottom.
struct SelectableText: NSViewRepresentable {
    let text: String

    /// Explicit sRGB — do not bridge `HortColors.textPrimary` via `NSColor(Color)`,
    /// which can resolve to black/clear outside a SwiftUI environment.
    private static let foreground = NSColor(srgbRed: 0xF1 / 255,
                                            green: 0xF4 / 255,
                                            blue: 0xF9 / 255,
                                            alpha: 1)
    private static let bodyFont = NSFont.systemFont(ofSize: 12)

    func makeNSView(context: Context) -> FocusReportingTextView {
        let textView = FocusReportingTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.appearance = NSAppearance(named: .darkAqua)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        apply(text, to: textView)
        return textView
    }

    func updateNSView(_ textView: FocusReportingTextView, context: Context) {
        if textView.string != text {
            apply(text, to: textView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: FocusReportingTextView,
                      context: Context) -> CGSize? {
        let width = max(proposal.width ?? proposal.replacingUnspecifiedDimensions().width, 1)
        guard let container = nsView.textContainer,
              let layout = nsView.layoutManager else {
            return CGSize(width: width, height: 20)
        }
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        nsView.frame.size.width = width
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let inset = nsView.textContainerInset
        let height = ceil(used.height + inset.height * 2 + 2)
        return CGSize(width: width, height: max(height, 20))
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

    /// Intrinsic height from layout so SwiftUI proposes a frame that matches
    /// the drawn glyphs (keeps hit-testing aligned with what the user sees).
    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let layout = layoutManager else {
            return super.intrinsicContentSize
        }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let inset = textContainerInset
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: ceil(used.height + inset.height * 2 + 2))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}
