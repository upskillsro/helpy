import AppKit
import XCTest
@testable import Helpy

@MainActor
final class MainWindowStyleTests: XCTestCase {

    private func window() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    /// Both modes must accept keystrokes: the normal window has a quick-add
    /// field in every board column, and the strip has one at the bottom.
    /// `canBecomeKey` is read-only and false for `.borderless`, which is the
    /// trap this guards.
    func testBothModesProduceAKeyableWindow() {
        for mode in [MainWindowMode.normal, .strip] {
            let w = window()
            MainWindowStyle.apply(mode, to: w)
            XCTAssertTrue(w.canBecomeKey, "\(mode) window must accept key input")
            XCTAssertTrue(w.styleMask.contains(.titled), "\(mode) must stay titled")
        }
    }

    func testNormalModeIsResizableAndOrdinaryLevel() {
        let w = window()
        MainWindowStyle.apply(.normal, to: w)
        XCTAssertTrue(w.styleMask.contains(.resizable))
        XCTAssertEqual(w.level, .normal)
        XCTAssertTrue(w.isMovable)
        XCTAssertEqual(w.minSize, MainWindowStyle.normalMinSize)
    }

    func testStripModeIsPinnedAndFloating() {
        let w = window()
        MainWindowStyle.apply(.strip, to: w)
        XCTAssertFalse(w.styleMask.contains(.resizable))
        XCTAssertEqual(w.level, .floating)
        XCTAssertFalse(w.isMovable, "the strip is locked to the screen edge")
        XCTAssertTrue(w.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(w.titleVisibility, .hidden)
    }

    func testStripWidthIsTheStripWidth() {
        let w = window()
        MainWindowStyle.apply(.strip, to: w)
        XCTAssertEqual(w.frame.width, MainWindowStyle.stripWidth)
    }

    /// Switching back and forth must land in the same state each time — the
    /// window is reused, not recreated.
    func testSwitchingModesIsReversible() {
        let w = window()
        MainWindowStyle.apply(.normal, to: w)
        MainWindowStyle.apply(.strip, to: w)
        MainWindowStyle.apply(.normal, to: w)

        XCTAssertTrue(w.canBecomeKey)
        XCTAssertTrue(w.styleMask.contains(.resizable))
        XCTAssertEqual(w.level, .normal)
        XCTAssertTrue(w.isOpaque)
    }

    func testApplyingTheSameModeTwiceIsIdempotent() {
        for mode in [MainWindowMode.normal, .strip] {
            let w = window()
            MainWindowStyle.apply(mode, to: w)
            let mask = w.styleMask
            let level = w.level
            MainWindowStyle.apply(mode, to: w)
            XCTAssertEqual(w.styleMask, mask)
            XCTAssertEqual(w.level, level)
        }
    }
}
