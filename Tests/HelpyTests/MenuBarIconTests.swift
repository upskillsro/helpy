import XCTest
import AppKit
@testable import Helpy

@MainActor
final class MenuBarIconTests: XCTestCase {
    /// The status bar silently hides items whose image exceeds the bar height,
    /// so the icon must always come out constrained to menu-bar size.
    func testBundledMenuBarIconIsSizedForStatusBar() {
        let icon = AppWindowCoordinator.menuBarIconImage(from: Bundle.module)
        XCTAssertNotNil(icon)
        XCTAssertLessThanOrEqual(icon!.size.width, 22)
        XCTAssertLessThanOrEqual(icon!.size.height, 22)
        // The white cat must stay white on every menu bar appearance.
        XCTAssertFalse(icon!.isTemplate)
    }

    func testFallbackSymbolIconIsAlsoConstrained() {
        // A bundle with no MenuBarIcon.png forces the SF Symbol fallback.
        let icon = AppWindowCoordinator.menuBarIconImage(from: Bundle(for: MenuBarIconTests.self))
        XCTAssertNotNil(icon)
        XCTAssertLessThanOrEqual(icon!.size.width, 22)
        XCTAssertLessThanOrEqual(icon!.size.height, 22)
    }
}
