import SwiftUI
import XCTest
@testable import Helpy

final class AccentTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AccentTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        HelpyAccent.currentHex = HelpyAccent.defaultHex
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        HelpyAccent.currentHex = HelpyAccent.defaultHex
        super.tearDown()
    }

    /// Sky is the blue the rest of the palette was built around, so it has to
    /// stay the value an untouched install gets.
    func testDefaultAccentIsSky() {
        HelpyAccent.loadFromDefaults(defaults)
        XCTAssertEqual(HelpyAccent.currentHex, 0x0086E8)
    }

    func testStoredAccentIsLoaded() {
        defaults.set(Int(0x8B5CF6), forKey: HelpyAccent.key)
        HelpyAccent.loadFromDefaults(defaults)
        XCTAssertEqual(HelpyAccent.currentHex, 0x8B5CF6)
    }

    /// A junk value must not black out the app.
    func testOutOfRangeAccentIsIgnored() {
        defaults.set(-12, forKey: HelpyAccent.key)
        HelpyAccent.loadFromDefaults(defaults)
        XCTAssertEqual(HelpyAccent.currentHex, HelpyAccent.defaultHex)
    }

    func testColorRoundTripsThroughHex() {
        for preset in HelpyAccent.presets {
            XCTAssertEqual(Color(hex: preset.hex).helpyHex, preset.hex, preset.name)
        }
    }

    func testPresetsAreDistinct() {
        XCTAssertEqual(Set(HelpyAccent.presets.map(\.hex)).count, HelpyAccent.presets.count)
    }
}
