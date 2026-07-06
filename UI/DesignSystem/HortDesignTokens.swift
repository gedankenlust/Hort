import SwiftUI

// MARK: - Hort Design Tokens
//
// Single source of truth for colors, typography, spacing, radius and animation.
// Views should consume these tokens through `Theme.Colors`, `Theme.Fonts`,
// `Theme.Layout` etc. rather than hard-coding values.

// MARK: Colors

enum HortColors {
    // Surfaces — deep graphite with a faint blue cast, layered for elevation.
    static let background     = Color(hex: 0x0B0E14) // app canvas
    static let surface        = Color(hex: 0x11161F) // sidebar / panels
    static let elevated       = Color(hex: 0x171D29) // cards
    static let elevatedHover  = Color(hex: 0x1F2738) // hover / selected fill

    // Accent — a single restrained cyan used as punctuation, not decoration.
    static let accent         = Color(hex: 0x32D2E0)
    static let accentSoft     = Color(hex: 0x32D2E0).opacity(0.14)
    static let accentMuted    = Color(hex: 0x32D2E0).opacity(0.08)

    // Text — three contrast tiers.
    static let textPrimary    = Color(hex: 0xF1F4F9)
    static let textSecondary  = Color(hex: 0x9AA5B5)
    static let textTertiary   = Color(hex: 0x5B6573)

    // Hairlines.
    static let border         = Color.white.opacity(0.07)
    static let borderStrong   = Color.white.opacity(0.12)
    static let borderFocus    = Color(hex: 0x32D2E0).opacity(0.5)

    // Semantic.
    static let danger         = Color(hex: 0xFF5C5C)
    static let dangerSoft     = Color(hex: 0xFF5C5C).opacity(0.14)
    static let warning        = Color(hex: 0xF5B544)
    static let warningSoft    = Color(hex: 0xF5B544).opacity(0.14)
    static let success        = Color(hex: 0x4CD964)
    static let successSoft    = Color(hex: 0x4CD964).opacity(0.14)
    static let info           = Color(hex: 0x32D2E0)
}

// MARK: Typography

enum HortTypography {
    enum Size {
        static let caption: CGFloat    = 11
        static let bodySmall: CGFloat  = 12
        static let body: CGFloat       = 13
        static let headline: CGFloat   = 15
        static let title: CGFloat      = 20
        static let largeTitle: CGFloat = 28
    }

    enum Weight {
        static let label: Font.Weight    = .semibold
        static let technical: Font.Weight = .medium
    }

    /// Small labels (section headers, metadata, badges).
    static func label(size: CGFloat = Size.bodySmall,
                      weight: Font.Weight = Weight.label) -> Font {
        .system(size: size, weight: weight)
    }

    /// Technical / monospaced text for metadata, IDs, paths, model names.
    static func technical(size: CGFloat = Size.bodySmall,
                          weight: Font.Weight = Weight.technical) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Primary readable text.
    static func primary(size: CGFloat = Size.body,
                        weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Large marketing/display text (Launch, Onboarding).
    static func display(size: CGFloat = Size.largeTitle,
                        weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: Spacing

enum HortSpacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: Radius

enum HortRadius {
    static let small:  CGFloat = 6
    static let medium: CGFloat = 8
    static let large: CGFloat = 12
    static let xl:     CGFloat = 16
}

// MARK: Animation

enum HortAnimation {
    static let fast:   Double = 0.15
    static let normal: Double = 0.25
    static let slow:   Double = 0.40
}

// MARK: Sizing

enum HortSizing {
    static let iconButton:   CGFloat = 28
    static let quickAction:  CGFloat = 24
    static let sidebarWidth: CGFloat = 280
    static let inspectorWidth: CGFloat = 340

    // Card grid.
    static let cardHeight:   CGFloat = 208
    static let cardMinWidth: CGFloat = 240
    static let cardMaxWidth: CGFloat = 320
    static let cardSpacing:  CGFloat = 16
    static let cardRadius:   CGFloat = HortRadius.large
}
