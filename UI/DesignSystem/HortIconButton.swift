import SwiftUI

/// Square icon button used in toolbars, headers and card quick actions.
/// Guarantees a minimum 28×28 pt hit target.
struct HortIconButton: View {
    let icon: String
    let help: LocalizedStringKey
    var disabled: Bool = false
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(foreground)
                .frame(width: HortSizing.iconButton, height: HortSizing.iconButton)
                .background(HortColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .onHover { isHovering = $0 }
        .accessibilityLabel(help)
    }

    private var foreground: Color {
        if disabled { return HortColors.textTertiary.opacity(0.5) }
        return isHovering ? HortColors.textPrimary : HortColors.textSecondary
    }
}
