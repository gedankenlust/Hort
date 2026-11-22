import XCTest
@testable import Hort

final class ScreenshotMonitorTests: XCTestCase {
    func testRecognizesLocalizedScreenshotNames() {
        XCTAssertTrue(ScreenshotMonitor.isScreenshotFileName("Screenshot 2026-11-21 at 10.00.00.png"))
        XCTAssertTrue(ScreenshotMonitor.isScreenshotFileName("Bildschirmfoto 2026-11-21 um 10.00.00.png"))
        XCTAssertTrue(ScreenshotMonitor.isScreenshotFileName("Capture d'écran 2026-11-21 à 10.00.00.png"))
        XCTAssertTrue(ScreenshotMonitor.isScreenshotFileName("Captura de pantalla 2026-11-21.png"))
        XCTAssertTrue(ScreenshotMonitor.isScreenshotFileName("Schermata 2026-11-21.png"))
        XCTAssertTrue(ScreenshotMonitor.isScreenshotFileName("Screenshot.heic"))
        XCTAssertTrue(ScreenshotMonitor.isScreenshotFileName("Screenshot.jpg"))
    }

    func testRejectsNonScreenshotFiles() {
        XCTAssertFalse(ScreenshotMonitor.isScreenshotFileName(".DS_Store"))
        XCTAssertFalse(ScreenshotMonitor.isScreenshotFileName("notes.txt"))
        XCTAssertFalse(ScreenshotMonitor.isScreenshotFileName("photo.png"))
        XCTAssertFalse(ScreenshotMonitor.isScreenshotFileName("Screenshot.pdf"))
    }
}
