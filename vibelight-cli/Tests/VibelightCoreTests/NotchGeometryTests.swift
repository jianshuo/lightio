import XCTest
@testable import VibelightCore
import CoreGraphics

final class NotchGeometryTests: XCTestCase {
    func testCenteredNotchRectOnM4MacBookPro14() {
        // M4 MBP 14" logical points: 1512 wide. Notch is roughly 200 pt wide × 32 pt tall.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = NotchGeometry.notchRect(
            screenFrame: screen,
            notchSize: CGSize(width: 200, height: 32),
            menuBarHeight: 32
        )
        XCTAssertEqual(notch.width, 200, accuracy: 0.01)
        XCTAssertEqual(notch.height, 32, accuracy: 0.01)
        XCTAssertEqual(notch.midX, screen.midX, accuracy: 0.01)
        // Notch sits at the very top of the screen (origin.y == screen.maxY - height)
        XCTAssertEqual(notch.maxY, screen.maxY, accuracy: 0.01)
    }

    func testWindowFrameAddsPaddingForGlow() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = NotchGeometry.notchRect(
            screenFrame: screen,
            notchSize: CGSize(width: 200, height: 32),
            menuBarHeight: 32
        )
        let window = NotchGeometry.overlayWindowFrame(notchRect: notch, glowPadding: 40)
        XCTAssertEqual(window.width, 280, accuracy: 0.01)
        XCTAssertEqual(window.height, 112, accuracy: 0.01)
        XCTAssertEqual(window.midX, notch.midX, accuracy: 0.01)
    }
}
