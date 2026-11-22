import Foundation

/// Pure tag-quality rules used by sidebar filtering and Autopilot organization.
enum TagPolicy {
    /// Number+short-suffix tags that are meaningful keywords, not units/codes.
    private static let numericTagWhitelist: Set<String> = [
        "3d", "4k", "8k", "2fa", "5g", "4g", "3g", "1080p", "720p", "2d", "3ds", "ios", "y2k",
    ]

    /// Tags that are purely numeric, date-like, single characters, or
    /// measurement units are noise from AI analysis and clutter the sidebar.
    static func isJunkTag(_ tag: String) -> Bool {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 1 { return true }
        if numericTagWhitelist.contains(t.lowercased()) { return false }
        if Double(t) != nil { return true }
        let junkPatterns = [
            #"^\d{1,4}[./-]\d{1,2}([./-]\d{2,4})?$"#,  // dates
            #"^\d+(\.\d+)?\s?[a-z]{1,3}$"#,            // number + short unit suffix
            #"^\d{4}$"#,                                 // bare years
        ]
        for pattern in junkPatterns {
            if t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        }
        return false
    }
}
