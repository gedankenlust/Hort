import XCTest
@testable import Hort

final class LocalizationTests: XCTestCase {
    func testExplicitLanguageWinsOverSystemLocale() {
        XCTAssertEqual(
            localizationIdentifier(setting: "en", systemLocale: Locale(identifier: "de_DE")),
            "en",
            "an in-app language pick must not be overridden by the system"
        )
        XCTAssertEqual(
            localizationIdentifier(setting: "de", systemLocale: Locale(identifier: "en_US")),
            "de"
        )
    }

    func testSystemSettingFollowsLocaleLanguageNotRegion() {
        // The case that mixed translations in one window: language and region
        // point at different countries. Runtime strings have to follow the same
        // locale SwiftUI renders LocalizedStringKey with.
        XCTAssertEqual(
            localizationIdentifier(setting: "system", systemLocale: Locale(identifier: "de_US")),
            "de"
        )
        XCTAssertEqual(
            localizationIdentifier(setting: "system", systemLocale: Locale(identifier: "en_DE")),
            "en"
        )
    }

    func testUnknownSystemLocaleFallsBackToEnglish() {
        XCTAssertEqual(localizationIdentifier(setting: "system", systemLocale: Locale(identifier: "")), "en")
    }

    /// Both strings files, read from source. `Bundle.main` is the xctest runner
    /// here, not the app, so the packaged bundle isn't reachable from a test.
    private func strings(_ language: String) throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root
            .appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String],
                             "could not read \(language).lproj/Localizable.strings")
    }

    func testEveryKeyExistsInBothLanguages() throws {
        let en = try strings("en"), de = try strings("de")
        XCTAssertEqual(de.keys.sorted().filter { en[$0] == nil }, [],
                       "keys only in German — English falls back to the raw key on screen")
        XCTAssertEqual(en.keys.sorted().filter { de[$0] == nil }, [],
                       "keys only in English — German falls back to the raw key on screen")
    }

    func testNoTranslationIsLeftEmpty() throws {
        for language in ["en", "de"] {
            let empty = try strings(language).filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            XCTAssertEqual(empty.keys.sorted(), [], "empty \(language) translations render as blank UI")
        }
    }

    func testFormatPlaceholdersMatchAcrossLanguages() throws {
        // A key with %@ in one language but not the other crashes String(format:)
        // or silently drops the value.
        let en = try strings("en"), de = try strings("de")
        for (key, enValue) in en {
            guard let deValue = de[key] else { continue }
            XCTAssertEqual(enValue.components(separatedBy: "%").count,
                           deValue.components(separatedBy: "%").count,
                           "placeholder count differs for \"\(key)\"")
        }
    }
}
