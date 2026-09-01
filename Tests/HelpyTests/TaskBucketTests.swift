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

    /// The mirror of the drop rule: on the last day of the week, tasks dated
    /// into the week ahead show up in This week rather than in Backlog.
    func testOnTheLastDayOfTheWeekNextWeekIsThisWeek() {
        let w = week(firstWeekday: 2, day: 30)
        XCTAssertEqual(w.bucket(forDueDate: date(w, day: 2, month: 9)), .thisWeek)
        XCTAssertEqual(w.bucket(forDueDate: date(w, day: 6, month: 9)), .thisWeek)
        XCTAssertEqual(w.bucket(forDueDate: date(w, day: 7, month: 9)), .backlog)
        // Mid-week the window does not roll: next week is still Backlog.
        XCTAssertEqual(week(firstWeekday: 2).bucket(forDueDate: date(w, day: 2, month: 9)), .backlog)
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
        XCTAssertNil(week(firstWeekday: 2).dueDateComponents(for: .backlog))
    }

    func testDroppingIntoTodayLandsInTheTodayBucket() {
        let w = week(firstWeekday: 2)
        let due = w.dueDateComponents(for: .today)
        XCTAssertNotNil(due)
        XCTAssertEqual(w.bucket(forDueDate: due?.date), .today)
    }

    /// A column is a day, not an hour: writing one made every card dropped
    /// into Today due at 9:00 with an alarm to match.
    func testDropTargetsCarryNoTimeOfDay() {
        let w = week(firstWeekday: 2)
        XCTAssertNil(w.dueDateComponents(for: .today)?.hour)
        XCTAssertNil(w.dueDateComponents(for: .today)?.minute)
        XCTAssertNil(w.dueDateComponents(for: .thisWeek)?.hour)
    }

    func testDroppingIntoThisWeekLandsInTheThisWeekBucket() {
        let w = week(firstWeekday: 2)
        let due = w.dueDateComponents(for: .thisWeek)
        XCTAssertNotNil(due)
        XCTAssertEqual(w.bucket(forDueDate: due?.date), .thisWeek)
        XCTAssertEqual(due?.day, 30)
    }

    /// On the final day of the week the window rolls into the week ahead, so
    /// dragging a card out of Today into This week actually moves it. Before
    /// this, the drop handed back today's date and the card snapped home —
    /// which read as "the board is broken" every Sunday.
    func testThisWeekDropOnTheLastDayOfTheWeekMovesIntoNextWeek() {
        // Sunday 2026-08-30 is the last day of a Monday-start week.
        let w = week(firstWeekday: 2, day: 30)
        let due = w.dueDateComponents(for: .thisWeek)?.date
        XCTAssertNotNil(due)
        XCTAssertGreaterThan(due!, w.startOfToday)
        XCTAssertEqual(w.bucket(forDueDate: due), .thisWeek)
        XCTAssertEqual(w.calendar.component(.day, from: due!), 6)   // Sun 2026-09-06
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
