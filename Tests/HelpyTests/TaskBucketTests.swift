import XCTest
@testable import Helpy

final class TaskBucketTests: XCTestCase {

    /// Monday 2026-08-24, 14:00 local. Wednesday of the same week is 2026-08-26.
    private func week(firstWeekday: Int, day: Int = 24, hour: Int = 14) -> HelpyWeek {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = firstWeekday
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
        return HelpyWeek(calendar: calendar, now: now)
    }

    private func date(_ w: HelpyWeek, day: Int, month: Int = 8, year: Int = 2026, hour: Int = 12) -> Date {
        w.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Bucket derivation

    func testNoDueDateIsBacklog() {
        XCTAssertEqual(week(firstWeekday: 2).bucket(forDueDate: nil), .backlog)
    }

    func testOverdueIsToday() {
        let w = week(firstWeekday: 2)
        XCTAssertEqual(w.bucket(forDueDate: date(w, day: 1)), .today)
    }

    func testDueEarlierTodayIsStillToday() {
        let w = week(firstWeekday: 2, hour: 14)
        XCTAssertEqual(w.bucket(forDueDate: date(w, day: 24, hour: 9)), .today)
    }

    func testDueLastMinuteOfTodayIsToday() {
        let w = week(firstWeekday: 2)
        XCTAssertEqual(w.bucket(forDueDate: date(w, day: 24, hour: 23)), .today)
    }

    func testDueTomorrowIsThisWeek() {
        let w = week(firstWeekday: 2)
        XCTAssertEqual(w.bucket(forDueDate: date(w, day: 25)), .thisWeek)
    }

    func testDueOnTheLastDayOfTheWeekIsThisWeek() {
        // Monday-start week of 2026-08-24 ends Sunday 2026-08-30.
        let w = week(firstWeekday: 2)
        XCTAssertEqual(w.bucket(forDueDate: date(w, day: 30, hour: 23)), .thisWeek)
    }

    func testDueNextWeekIsBacklogNotThisWeek() {
        let w = week(firstWeekday: 2)
        XCTAssertEqual(w.bucket(forDueDate: date(w, day: 31)), .backlog)
    }

    /// The rule that keeps a dated task from falling off the board entirely.
    func testDueNextMonthIsBacklog() {
        let w = week(firstWeekday: 2)
        XCTAssertEqual(w.bucket(forDueDate: date(w, day: 20, month: 9)), .backlog)
    }

    func testWeekBoundaryFollowsFirstWeekday() {
        // Sunday-start: the week containing Mon 2026-08-24 ends Sat 2026-08-29,
        // so Sunday the 30th is already next week.
        let sundayStart = week(firstWeekday: 1)
        XCTAssertEqual(sundayStart.bucket(forDueDate: date(sundayStart, day: 30)), .backlog)

        // Monday-start: the same date is the last day of this week.
        let mondayStart = week(firstWeekday: 2)
        XCTAssertEqual(mondayStart.bucket(forDueDate: date(mondayStart, day: 30)), .thisWeek)
    }

    // MARK: - Drop targets

    func testDroppingIntoBacklogClearsTheDate() {
        XCTAssertNil(week(firstWeekday: 2).dueDate(for: .backlog))
    }

    func testDroppingIntoTodayLandsInTheTodayBucket() {
        let w = week(firstWeekday: 2)
        let due = w.dueDate(for: .today)
        XCTAssertNotNil(due)
        XCTAssertEqual(w.bucket(forDueDate: due), .today)
        XCTAssertEqual(w.calendar.component(.hour, from: due!), 9)
    }

    func testDroppingIntoThisWeekLandsInTheThisWeekBucket() {
        let w = week(firstWeekday: 2)
        let due = w.dueDate(for: .thisWeek)
        XCTAssertNotNil(due)
        XCTAssertEqual(w.bucket(forDueDate: due), .thisWeek)
        XCTAssertEqual(w.calendar.component(.day, from: due!), 30)
    }

    /// On the final day of the week there is no slot left that is not today,
    /// so a This-week drop legitimately lands in Today rather than in the past.
    func testThisWeekDropOnTheLastDayOfTheWeekDoesNotGoBackwards() {
        let w = week(firstWeekday: 2, day: 30)
        let due = w.dueDate(for: .thisWeek)
        XCTAssertNotNil(due)
        XCTAssertGreaterThanOrEqual(due!, w.startOfToday)
        XCTAssertEqual(w.bucket(forDueDate: due), .today)
    }

    // MARK: - Planning weeks

    func testRollingWindowIsContiguousAndCentredOnThisWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26))!

        let weeks = PlanWeek.rollingWindow(weeksBack: 4, weeksForward: 8, calendar: calendar, now: now)

        XCTAssertEqual(weeks.count, 13)
        XCTAssertEqual(weeks.filter(\.isCurrent).count, 1)
        XCTAssertEqual(weeks.firstIndex(where: \.isCurrent), 4)
        XCTAssertEqual(Set(weeks.map(\.id)).count, weeks.count, "week keys must be unique")

        for (earlier, later) in zip(weeks, weeks.dropFirst()) {
            XCTAssertEqual(earlier.end, later.start, "weeks must not leave a gap")
        }
    }

    func testWeekKeyIsStableForEveryDayOfTheSameWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        let keys = (24...30).map { day -> String in
            let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: day))!
            return PlanWeek.key(for: date, calendar: calendar)
        }
        XCTAssertEqual(Set(keys).count, 1, "every day Mon–Sun maps to one key, got \(keys)")
    }
}
