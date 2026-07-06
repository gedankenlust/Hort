import SwiftUI

/// Hort design system entry point.
///
/// New code should prefer the typed token enums (`HortColors`, `HortTypography`,
/// `HortSpacing`, `HortRadius`, `HortAnimation`, `HortSizing`) imported from
/// `UI/DesignSystem/HortDesignTokens.swift`. The nested `Theme.Colors`,
/// `Theme.Fonts` and `Theme.Layout` aliases are kept for backwards
/// compatibility with existing views during the migration.
enum Theme {
    enum Colors {
        // Surfaces
        static let background    = HortColors.background
        static let surface       = HortColors.surface
        static let elevated      = HortColors.elevated
        static let elevatedHi    = HortColors.elevatedHover

        // Accent
        static let accent        = HortColors.accent
        static let accentSoft    = HortColors.accentSoft
        static let accentMuted   = HortColors.accentMuted

        // Text
        static let textPrimary   = HortColors.textPrimary
        static let textSecondary = HortColors.textSecondary
        static let textTertiary  = HortColors.textTertiary

        // Hairlines
        static let border        = HortColors.border
        static let borderStrong  = HortColors.borderStrong
        static let borderFocus   = HortColors.borderFocus

        // Semantic
        static let danger        = HortColors.danger
        static let dangerSoft    = HortColors.dangerSoft
        static let warning       = HortColors.warning
        static let warningSoft   = HortColors.warningSoft
        static let success       = HortColors.success
        static let successSoft   = HortColors.successSoft
        static let info          = HortColors.info

        // Deprecated alias — kept temporarily for any lingering references.
        @available(*, deprecated, renamed: "textTertiary")
        static let secondaryAccent = HortColors.textTertiary
    }

    enum Fonts {
        static func technical(size: CGFloat = HortTypography.Size.bodySmall) -> Font {
            HortTypography.technical(size: size)
        }

        static func label(_ size: CGFloat = HortTypography.Size.bodySmall,
                          weight: Font.Weight = HortTypography.Weight.label) -> Font {
            HortTypography.label(size: size, weight: weight)
        }

        static func primary(size: CGFloat = HortTypography.Size.body,
                            weight: Font.Weight = .regular) -> Font {
            HortTypography.primary(size: size, weight: weight)
        }
    }

    enum Layout {
        static let cornerRadius: CGFloat  = HortRadius.medium
        static let cardRadius: CGFloat    = HortRadius.large
        static let spacing: CGFloat       = HortSpacing.md
        static let sidebarWidth: CGFloat  = HortSizing.sidebarWidth
        static let inspectorWidth: CGFloat = HortSizing.inspectorWidth

        static let cardHeight: CGFloat    = HortSizing.cardHeight
        static let cardMinWidth: CGFloat  = HortSizing.cardMinWidth
        static let cardMaxWidth: CGFloat  = HortSizing.cardMaxWidth
        static let gridSpacing: CGFloat   = HortSizing.cardSpacing

        // Padding tokens
        static let paddingSmall:  CGFloat = HortSpacing.sm
        static let paddingMedium: CGFloat = HortSpacing.md
        static let paddingLarge:  CGFloat = HortSpacing.lg
        static let paddingXL:     CGFloat = HortSpacing.xxl
    }

    enum Animation {
        static let fast: Double   = HortAnimation.fast
        static let normal: Double = HortAnimation.normal
        static let slow: Double   = HortAnimation.slow
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    init?(hexString: String) {
        var clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        var rgbValue: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&rgbValue) else { return nil }
        self.init(hex: UInt32(rgbValue))
    }
}
