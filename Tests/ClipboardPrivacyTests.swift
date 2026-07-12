import AppKit
import XCTest
@testable import Hort

final class ClipboardPrivacyTests: XCTestCase {
    func testRecognizesAllSensitivePasteboardTypes() {
        for type in ClipboardMonitor.sensitiveTypes {
            XCTAssertTrue(ClipboardMonitor.containsSensitiveType([.string, type]))
        }
    }

    func testOrdinaryClipboardTypesAreNotSensitive() {
        XCTAssertFalse(ClipboardMonitor.containsSensitiveType([.string, .png]))
        XCTAssertFalse(ClipboardMonitor.containsSensitiveType(nil))
    }

    func testExcludesPasswordManagersAndHortItself() {
        let excluded = SettingsStore.defaultExcludedBundleIDs
        XCTAssertTrue(ClipboardMonitor.shouldExclude(
            bundleIdentifier: "com.1password.1password",
            ownBundleIdentifier: "dev.hort.app",
            excludedBundleIDs: excluded
        ))
        XCTAssertTrue(ClipboardMonitor.shouldExclude(
            bundleIdentifier: "dev.hort.app",
            ownBundleIdentifier: "dev.hort.app",
            excludedBundleIDs: excluded
        ))
    }

    func testAllowsAnOrdinaryApplication() {
        XCTAssertFalse(ClipboardMonitor.shouldExclude(
            bundleIdentifier: "com.apple.Safari",
            ownBundleIdentifier: "dev.hort.app",
            excludedBundleIDs: SettingsStore.defaultExcludedBundleIDs
        ))
    }
}
