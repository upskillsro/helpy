import XCTest
@testable import Helpy

/// The pill's clock rolls by sliding a window over a strip of pre-drawn digits.
/// The row arithmetic is the whole trick, so it is pinned here: every roll has
/// to stay inside the strip, land on the right glyph, and travel in the
/// direction the clock is counting.
@MainActor
final class RollingTimeTextTests: XCTestCase {

    private typealias View = RollingTimeView

    private func travel(from digit: Int, to next: Int) -> (from: Int, to: Int, settled: Int) {
        View.travel(fromRow: View.row(showing: digit), showing: digit, to: next)
    }

    func testEveryRowShowsTheDigitItClaims() {
        for digit in 0...9 {
            XCTAssertEqual(View.digit(atRow: View.row(showing: digit)), digit)
        }
    }

    func testSettledRowAlwaysShowsTheRequestedDigit() {
        for from in 0...9 {
            for to in 0...9 {
                let move = travel(from: from, to: to)
                XCTAssertEqual(View.digit(atRow: move.settled), to,
                               "\(from) -> \(to) settled on the wrong glyph")
            }
        }
    }

    func testTravelEndpointsShowTheSameGlyphsAsTheSettledRows() {
        for from in 0...9 {
            for to in 0...9 {
                let move = travel(from: from, to: to)
                XCTAssertEqual(View.digit(atRow: move.from), from,
                               "\(from) -> \(to) starts on the wrong glyph")
                XCTAssertEqual(View.digit(atRow: move.to), to,
                               "\(from) -> \(to) ends on the wrong glyph")
            }
        }
    }

    func testEveryTravelStaysInsideTheStrip() {
        for from in 0...9 {
            for to in 0...9 {
                let move = travel(from: from, to: to)
                for row in [move.from, move.to, move.settled] {
                    XCTAssertTrue((0..<View.rowCount).contains(row),
                                  "\(from) -> \(to) left the strip at row \(row)")
                }
            }
        }
    }

    func testCountingDownAlwaysMovesDownTheStrip() {
        // A countdown steps the digit down by one, including 0 -> 9.
        for from in 0...9 {
            let to = (from + 9) % 10
            let move = travel(from: from, to: to)
            XCTAssertEqual(move.to - move.from, 1,
                           "\(from) -> \(to) should roll one row down")
        }
    }

    func testCountingUpAlwaysMovesUpTheStrip() {
        // Stopwatch and overtime step the digit up by one, including 9 -> 0.
        for from in 0...9 {
            let to = (from + 1) % 10
            let move = travel(from: from, to: to)
            XCTAssertEqual(move.to - move.from, -1,
                           "\(from) -> \(to) should roll one row up")
        }
    }

    func testMinuteBoundaryRollsDownwardNotBackwards() {
        // Seconds tens goes 0 -> 5 when a minute turns over. That is five
        // decrements, so it must travel down the strip, not spin back up.
        let move = travel(from: 0, to: 5)
        XCTAssertEqual(move.to - move.from, 5)
    }

    func testNeverTravelsMoreThanHalfACycle() {
        for from in 0...9 {
            for to in 0...9 {
                let move = travel(from: from, to: to)
                XCTAssertLessThanOrEqual(abs(move.to - move.from), View.cycle / 2,
                                         "\(from) -> \(to) took the long way round")
            }
        }
    }
}
