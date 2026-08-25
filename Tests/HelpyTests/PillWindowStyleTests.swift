import XCTest
import AppKit
@testable import Helpy

@MainActor
final class PillWindowStyleTests: XCTestCase {
    private final class Observer: NSObject {
        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                   change: [NSKeyValueChangeKey: Any]?,
                                   context: UnsafeMutableRawPointer?) {}
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 268, height: 44),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    /// The pill window has to take keystrokes for the "Add subtask…" field.
    /// A `.borderless` window never can — that is what drove the old runtime
    /// subclassing — so the style mask must keep `.titled`.
    func testStyledPillWindowCanBecomeKey() {
        let window = makeWindow()
        PillWindowStyle.apply(to: window)
        XCTAssertTrue(window.canBecomeKey)
    }

    /// Regression guard for a crash on entering focus mode.
    ///
    /// The pill used to be made key-able by `object_setClass`-ing the window
    /// onto a runtime subclass. By the time that ran, SwiftUI had already
    /// KVO-observed the window, so it subclassed KVO's own `NSKVONotifying_*`
    /// class and left KVO's bookkeeping inconsistent. The next write to any
    /// observed property went through `_NSSetBoolValueAndNotify` and killed
    /// the process ("os_unfair_lock is corrupt"). Styling must therefore leave
    /// the window's class alone.
    ///
    /// Against the old implementation this does not fail — it takes the whole
    /// test process down with SIGKILL, exactly as it did the app.
    func testStylingLeavesAnObservedWindowsClassAlone() {
        let window = makeWindow()
        let observer = Observer()
        window.addObserver(observer, forKeyPath: "opaque", options: [.new], context: nil)
        defer { window.removeObserver(observer, forKeyPath: "opaque") }

        let classBeforeStyling: AnyClass? = object_getClass(window)
        PillWindowStyle.apply(to: window)
        XCTAssertTrue(object_getClass(window) === classBeforeStyling,
                      "styling must not swizzle the window's class")

        // The write that used to be fatal.
        window.isOpaque = false
        XCTAssertFalse(window.isOpaque)
    }

    /// Both the pill's own view and the focus-mode transition style this
    /// window. They must not be able to disagree about the style mask.
    func testRestylingIsIdempotent() {
        let window = makeWindow()
        PillWindowStyle.apply(to: window)
        let mask = window.styleMask
        PillWindowStyle.apply(to: window)
        XCTAssertEqual(window.styleMask, mask)
        XCTAssertTrue(window.canBecomeKey)
    }
}
