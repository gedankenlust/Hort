import SwiftUI

/// Unified empty-state view with icon, title, subtitle and optional CTA.
struct HortEmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: HortSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(HortColors.accent)
                .frame(width: 80, height: 80)
                .background(HortColors.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: HortRadius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: HortRadius.xl, style: .continuous)
                        .strokeBorder(HortColors.accent.opacity(0.3), lineWidth: 1)
                )

            VStack(spacing: HortSpacing.sm) {
                Text(title)
                    .font(HortTypography.label(size: HortTypography.Size.headline,
                                               weight: .semibold))
                    .foregroundColor(HortColors.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(HortTypography.primary(size: HortTypography.Size.bodySmall))
                        .foregroundColor(HortColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }

            if let actionTitle, let action {
                HortButton(title: actionTitle, style: .secondary, action: action)
                    .frame(maxWidth: 240)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
