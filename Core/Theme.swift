import SwiftUI

enum Theme {
    enum Colors {
        // Surfaces — deep graphite with a faint blue cast, layered for elevation.
        static let background  = Color(hex: 0x0B0E14) // app canvas
        static let surface     = Color(hex: 0x11161F) // sidebar / panels
        static let elevated    = Color(hex: 0x171D29) // cards
        static let elevatedHi  = Color(hex: 0x1F2738) // hover / selected fill

        // Accent — a single restrained cyan used as punctuation, not decoration.
        static let accent      = Color(hex: 0x32D2E0)
        static let accentSoft  = Color(hex: 0x32D2E0).opacity(0.14)

        // Text — three contrast tiers.
        static let textPrimary   = Color(hex: 0xF1F4F9)
        static let textSecondary = Color(hex: 0x9AA5B5)
        static let textTertiary  = Color(hex: 0x5B6573)
        /// Back-compat alias still referenced by some views.
        static let secondaryAccent = Color(hex: 0x5B6573)

        // Hairlines.
        static let border        = Color.white.opacity(0.07)
        static let borderStrong  = Color.white.opacity(0.12)

        // Semantic.
        static let danger  = Color(hex: 0xFF5C5C)
        static let warning = Color(hex: 0xF5B544)
    }

    enum Fonts {
        /// Tracked label text (small caps headers, metadata). System font now —
        /// the old monospace look is dropped for Apple-grade clarity.
        static func technical(size: CGFloat) -> Font {
            .system(size: size, weight: .medium)
        }

        static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight)
        }

        static func primary(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }
    }

    enum Layout {
        static let cornerRadius: CGFloat = 10
        static let cardRadius: CGFloat = 12
        static let spacing: CGFloat = 12
        static let sidebarWidth: CGFloat = 248
        static let inspectorWidth: CGFloat = 300

        // Uniform tile grid.
        static let cardHeight: CGFloat = 208
        static let cardMinWidth: CGFloat = 240
        static let cardMaxWidth: CGFloat = 320
        static let gridSpacing: CGFloat = 16
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
