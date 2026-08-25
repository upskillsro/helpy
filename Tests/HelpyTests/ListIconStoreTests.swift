import AppKit
import XCTest
@testable import Helpy

@MainActor
final class ListIconStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ListIconStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func swatch(width: CGFloat = 40, height: CGFloat = 40) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemPink.set()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    func testNoIconByDefault() {
        let store = ListIconStore(directory: directory)
        XCTAssertFalse(store.hasIcon(for: "list-a"))
        XCTAssertNil(store.image(for: "list-a"))
    }

    func testSavedIconIsFoundAndSquared() throws {
        let store = ListIconStore(directory: directory)
        XCTAssertTrue(store.setIcon(swatch(width: 200, height: 60), for: "list-a"))
        XCTAssertTrue(store.hasIcon(for: "list-a"))

        let saved = try XCTUnwrap(store.image(for: "list-a"))
        XCTAssertEqual(saved.size.width, ListIconStore.iconSide)
        XCTAssertEqual(saved.size.height, ListIconStore.iconSide)
    }

    func testSavingBumpsTheRevisionSoViewsRedraw() {
        let store = ListIconStore(directory: directory)
        let before = store.revision
        store.setIcon(swatch(), for: "list-a")
        XCTAssertGreaterThan(store.revision, before)
    }

    func testRemovingRestoresTheMonogram() {
        let store = ListIconStore(directory: directory)
        store.setIcon(swatch(), for: "list-a")
        store.removeIcon(for: "list-a")
        XCTAssertFalse(store.hasIcon(for: "list-a"))
        XCTAssertNil(store.image(for: "list-a"))
    }

    func testIconsSurviveANewStoreInstance() {
        ListIconStore(directory: directory).setIcon(swatch(), for: "list-a")
        XCTAssertTrue(ListIconStore(directory: directory).hasIcon(for: "list-a"))
    }

    /// A deleted list must not hand its icon to whatever comes next.
    func testPruneRemovesOnlyOrphans() {
        let store = ListIconStore(directory: directory)
        store.setIcon(swatch(), for: "kept")
        store.setIcon(swatch(), for: "deleted")

        store.pruneOrphans(keeping: ["kept"])

        XCTAssertTrue(store.hasIcon(for: "kept"))
        XCTAssertFalse(store.hasIcon(for: "deleted"))
    }

    func testUnreadableSourceIsRefusedNotCrashed() {
        let store = ListIconStore(directory: directory)
        let junk = directory.appendingPathComponent("junk.png")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data("not an image".utf8).write(to: junk)

        XCTAssertFalse(store.setIcon(from: junk, for: "list-a"))
        XCTAssertFalse(store.hasIcon(for: "list-a"))
    }

    func testMonogramTakesTheFirstLetter() {
        XCTAssertEqual(ListMonogram.letter(for: "Work"), "W")
        XCTAssertEqual(ListMonogram.letter(for: "  faceless"), "F")
        XCTAssertEqual(ListMonogram.letter(for: ""), "?")
        XCTAssertEqual(ListMonogram.letter(for: "🎬 Shorts"), "🎬")
    }
}
