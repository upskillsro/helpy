import XCTest
import AppKit
@testable import Helpy

@MainActor
final class PillPanelTests: XCTestCase {
    /// The pill hosts an "Add subtask…" field, so it has to take keystrokes.
    /// A plain borderless `NSWindow` never can — `canBecomeKey` is read-only
    /// and false for `.borderless`. `KeyablePanel` overrides it, which is why
    /// the pill can be borderless at all.
    func testPillPanelCanBecomeKey() {
        let panel = AppWindowCoordinator.makePillPanel()
        XCTAssertTrue(panel.canBecomeKey)
    }

    /// Regression guard for the crash that killed the app on every entry into
    /// focus mode.
    ///
    /// The pill used to be a SwiftUI `Window` scene. SwiftUI owns and
    /// KVO-observes a scene's window, and the pill view reached back in from
    /// its own body update to restyle it — writing to observed properties from
    /// inside SwiftUI's update pass. Every crash report ends the same way:
    /// `styleWindow` → `_NSSetBoolValueAndNotify` → EXC_BAD_ACCESS, or
    /// "os_unfair_lock is corrupt".
    ///
    /// The fix is ownership, not ordering: the panel is built here, complete,
    /// before anything can observe it. This test pins that down by proving the
    /// factory hands back a fully configured panel — if chrome ever migrates
    /// back out to a view that applies it later, these assertions fail.
    func testPillPanelChromeIsSetAtCreation() {
        let panel = AppWindowCoordinator.makePillPanel()

        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.hasShadow)
        XCTAssertTrue(panel.isMovableByWindowBackground)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertEqual(panel.identifier, AppWindowCoordinator.pillWindowIdentifier)
    }

    /// A panel that is already KVO-observed must survive being shown and
    /// hidden. Nothing in that path may write to its style mask — that write
    /// is what used to be fatal.
    func testShowingAndHidingAnObservedPanelIsSafe() {
        final class Observer: NSObject {
            override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                       change: [NSKeyValueChangeKey: Any]?,
                                       context: UnsafeMutableRawPointer?) {}
        }

        let panel = AppWindowCoordinator.makePillPanel()
        let observer = Observer()
        panel.addObserver(observer, forKeyPath: "opaque", options: [.new], context: nil)
        defer { panel.removeObserver(observer, forKeyPath: "opaque") }

        let maskBefore = panel.styleMask
        let classBefore: AnyClass? = object_getClass(panel)

        panel.orderFront(nil)
        panel.orderOut(nil)

        XCTAssertEqual(panel.styleMask, maskBefore)
        XCTAssertTrue(object_getClass(panel) === classBefore,
                      "showing the pill must not swizzle or restyle its window")
    }

    /// Menu-bar mode has no pill at all, so asking for one must not create a
    /// panel that then sits invisible on screen for the app's whole lifetime.
    func testShowPillDoesNothingInMenuBarMode() {
        let coordinator = AppWindowCoordinator()
        coordinator.applyDisplayMode(.menuBarIcon)
        coordinator.showPill()
        XCTAssertNil(coordinator.pillPanel)
    }
}
