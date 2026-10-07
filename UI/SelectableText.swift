import SwiftUI

/// Read-only, selectable inspector text.
///
/// Pure SwiftUI — no `NSViewRepresentable`. AppKit text views inside the
/// inspector ScrollView previously inflated hit regions so action-button
/// hover/clicks landed offset from the drawn controls.
struct SelectableText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(HortTypography.primary(size: HortTypography.Size.caption))
            .foregroundColor(HortColors.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .onHover { hovering in
                // Yield feed ⌘A (select all cards) while the pointer is over
                // selectable inspector text; restore when it leaves.
                AppState.shared.inspectorTextFocused = hovering
            }
    }
}
