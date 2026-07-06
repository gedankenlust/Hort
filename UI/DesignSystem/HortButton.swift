import SwiftUI

/// Unified Hort button with semantic variants.
struct HortButton: View {
    enum Style {
        case primary
        case secondary
        case ghost
        case destructive
    }

    let title: LocalizedStringKey
    var icon: String? = nil
    var style: Style = .secondary
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: HortSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .frame(width: 16)
                }
                Text(title)
                    .font(HortTypography.label(size: HortTypography.Size.bodySmall,
                                               weight: .medium))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HortSpacing.md)
            .padding(.horizontal, HortSpacing.md)
            .background(background)
            .foregroundColor(foreground)
            .clipShape(RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }

    private var background: Color {
        switch style {
        case .primary:
            return isHovering ? HortColors.accent.opacity(0.85) : HortColors.accent
        case .secondary:
            return isHovering ? HortColors.elevatedHover : HortColors.elevated
        case .ghost:
            return isHovering ? HortColors.accentSoft : Color.clear
        case .destructive:
            return isHovering ? HortColors.dangerSoft.opacity(0.7) : HortColors.dangerSoft
        }
    }

    private var foreground: Color {
        switch style {
        case .primary:
            return HortColors.background
        case .secondary:
            return isHovering ? HortColors.textPrimary : HortColors.textSecondary
        case .ghost:
            return isHovering ? HortColors.accent : HortColors.textSecondary
        case .destructive:
            return isHovering ? HortColors.danger : HortColors.textSecondary
        }
    }
}
