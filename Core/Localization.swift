import Foundation

/// The `.lproj` to read strings from: the in-app override when the user picked
/// a language, otherwise the locale SwiftUI itself renders with.
///
/// The "system" case matters. `NSLocalizedString` resolves through
/// `Bundle.main.preferredLocalizations`, which follows the macOS *language
/// list*, while SwiftUI's `Text(LocalizedStringKey)` follows the `\.locale`
/// environment — which `HortApp` sets to `Locale.current`, the macOS *region*.
/// Those two disagree whenever language and region are set to different
/// countries, and the window then mixes both translations.
func localizationIdentifier(setting: String, systemLocale: Locale = .current) -> String {
    guard setting == "system" else { return setting }
    return systemLocale.language.languageCode?.identifier ?? "en"
}

/// Resolves a localization key honoring the in-app language override
/// (`SettingsStore.language`), falling back to the system language.
///
/// Use this for strings built at runtime (counts, names, interpolation) instead
/// of `NSLocalizedString`: the in-app language picker only sets the SwiftUI
/// `\.locale` environment, which `LocalizedStringKey`-based `Text` respects but
/// `NSLocalizedString` does not — so `NSLocalizedString` would leak the system
/// language (e.g. German "ausgewählt" while the app is set to English).
func L(_ key: String) -> String {
    let identifier = localizationIdentifier(setting: SettingsStore.shared.language)
    if let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
    // Unlocalized build or an identifier we don't ship: let Foundation decide.
    return NSLocalizedString(key, comment: "")
}
