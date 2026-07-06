import SwiftUI
import AppKit

/// Read-only, selectable text (NSTextView) so the inspector content supports
/// native ⌘A select-all and copy. It reports its first-responder state to
/// AppState so the feed's ⌘A ("select all cards") stands down while this text
/// is focused, and the feed re-claims ⌘A when a card is clicked (which resigns
/// this view's first-responder status).
struct SelectableText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FocusReportingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = NSColor(HortColors.textPrimary)
        textView.font = .systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.appearance = NSAppearance(named: .darkAqua)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        textView.textColor = NSColor(HortColors.textPrimary)
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
