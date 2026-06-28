import SwiftUI
import AppKit

/// Read-only, selectable text (NSTextView) so the inspector content can be
/// drag-selected and copied (and offers a native right-click "Select All").
/// ⌘A stays a feed action ("select all cards"); to grab this text use drag and
/// ⌘C, or right-click and "Select All".
struct SelectableText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = NSColor(Theme.Colors.textPrimary)
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
        textView.textColor = NSColor(Theme.Colors.textPrimary)
    }
}
