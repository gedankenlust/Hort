import Foundation

/// Resolves a localization key honoring the in-app language override
/// (`SettingsStore.language`), falling back to the system language.
///
/// Use this for strings built at runtime (counts, names, interpolation) instead
/// of `NSLocalizedString`: the in-app language picker only sets the SwiftUI
/// `\.locale` environment, which `LocalizedStringKey`-based `Text` respects but
/// `NSLocalizedString` does not — so `NSLocalizedString` would leak the system
/// language (e.g. German "ausgewählt" while the app is set to English).
func L(_ key: String) -> String {
    let lang = SettingsStore.shared.language
    if lang != "system",
       let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
    return NSLocalizedString(key, comment: "")
}
