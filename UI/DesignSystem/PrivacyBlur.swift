import SwiftUI

/// Radii for privacy screenshot mode. Text needs a stronger blur than image
/// thumbs so OCR-style letterforms disappear without wrecking layout.
enum PrivacyBlur {
    static let text: CGFloat = 10
    static let image: CGFloat = 14
}

extension View {
    /// Soft-blurs sensitive content when privacy mode is on. Keeps layout size;
    /// hides the real string from accessibility. Hit-testing is off by default
    /// so blurred text can't be selected or copied during a screenshot.
    func privacyBlur(
        _ enabled: Bool,
        radius: CGFloat = PrivacyBlur.text,
        disableHitTesting: Bool = true
    ) -> some View {
        self
            .blur(radius: enabled ? radius : 0)
            .accessibilityHidden(enabled)
            .allowsHitTesting(!(enabled && disableHitTesting))
    }
}
