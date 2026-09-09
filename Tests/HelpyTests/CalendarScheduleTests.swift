import XCTest
@testable import Helpy

final class CalendarScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            calendar: calendar, timeZone: calendar.timeZone,
            year: 2026, month: 9, day: day, hour: hour, minute: minute
        ))!
    }

    private func item(
        _ id: String, day: Int, hour: Int, minute: Int = 0, minutes: Int, done: Bool = false
    ) -> ScheduledItem {
        ScheduledItem(
            id: id, title: id, start: date(day, hour, minute), minutes: minutes,
            listId: "L", listColorHex: 0x0086E8, isDone: done, priority: 0
        )
    }

    // MARK: - Grid arithmetic

    func testMinuteAndYAreInverses() {
        let grid = CalendarGrid(startHour: 8, endHour: 20, hourHeight: 52)
        XCTAssertEqual(grid.y(forMinuteOfDay: 8 * 60), 0)
        XCTAssertEqual(grid.y(forMinuteOfDay: 9 * 60), 52)
        XCTAssertEqual(grid.y(forMinuteOfDay: 9 * 60 + 30), 78)
        XCTAssertEqual(grid.minute(atY: 0), 8 * 60)
        XCTAssertEqual(grid.minute(atY: 52), 9 * 60)
        XCTAssertEqual(grid.minute(atY: 78), 9 * 60 + 30)
    }

    func testDropSnapsToQuarterHour() {
        let grid = CalendarGrid(startHour: 8, endHour: 20, hourHeight: 60)
        // 8:00 + 22 minutes of travel lands on the quarter, not on 8:22.
        XCTAssertEqual(grid.minute(atY: 22), 8 * 60 + 15)
        XCTAssertEqual(grid.minute(atY: 38), 8 * 60 + 45)
    }

    func testDropNearTheBottomKeepsTheBlockWhole() {
        let grid = CalendarGrid(startHour: 8, endHour: 20, hourHeight: 60)
        // A 2h block dropped at 19:30 has to start at 18:00 to end at 20:00.
        let start = grid.minute(atY: 11.5 * 60, duration: 120)
        XCTAssertEqual(start, 18 * 60)
    }

    func testDropAboveTheWindowClampsToTheFirstHour() {
        let grid = CalendarGrid(startHour: 8, endHour: 20, hourHeight: 60)
        XCTAssertEqual(grid.minute(atY: -400), 8 * 60)
    }

    func testWindowWidensForATaskScheduledOutsideWorkingHours() {
        let early = item("early", day: 8, hour: 6, minute: 30, minutes: 60)
        let late = item("late", day: 8, hour: 19, minutes: 150) // ends 21:30
        let grid = CalendarGrid.fitting(
            [early, late], startHour: 8, endHour: 20, hourHeight: 52, calendar: calendar
        )
        XCTAssertEqual(grid.startHour, 6)
        XCTAssertEqual(grid.endHour, 22)
    }

    func testWindowIsUnchangedWhenEverythingFits() {
        let grid = CalendarGrid.fitting(
            [item("a", day: 8, hour: 9, minutes: 60)],
            startHour: 8, endHour: 20, hourHeight: 52, calendar: calendar
        )
        XCTAssertEqual(grid.startHour, 8)
        XCTAssertEqual(grid.endHour, 20)
    }

    // MARK: - Overlap packing

    func testSequentialBlocksEachTakeTheFullWidth() {
        let placed = CalendarLayout.pack([
            item("a", day: 8, hour: 9, minutes: 60),
            item("b", day: 8, hour: 10, minutes: 60)
        ])
        XCTAssertEqual(placed.map(\.columns), [1, 1])
        XCTAssertEqual(placed.map(\.column), [0, 0])
    }

    func testTwoOverlappingBlocksSplitTheDay() {
        let placed = CalendarLayout.pack([
            item("a", day: 8, hour: 9, minutes: 90),
            item("b", day: 8, hour: 10, minutes: 60)
        ])
        XCTAssertEqual(Set(placed.map(\.columns)), [2])
        XCTAssertEqual(Set(placed.map(\.column)), [0, 1])
    }

    func testALaneIsReusedOnceItIsFree() {
        // a 9–11, b 9:30–10, c 10–11 : c fits back in b's lane, so 2 columns.
        let placed = CalendarLayout.pack([
            item("a", day: 8, hour: 9, minutes: 120),
            item("b", day: 8, hour: 9, minute: 30, minutes: 30),
            item("c", day: 8, hour: 10, minutes: 60)
        ])
        XCTAssertEqual(Set(placed.map(\.columns)), [2])
        let byId = Dictionary(uniqueKeysWithValues: placed.map { ($0.item.id, $0.column) })
        XCTAssertEqual(byId["a"], 0)
        XCTAssertEqual(byId["b"], 1)
        XCTAssertEqual(byId["c"], 1)
    }

    func testAGapEndsTheClusterSoLaterBlocksGetTheFullWidth() {
        let placed = CalendarLayout.pack([
            item("a", day: 8, hour: 9, minutes: 60),
            item("b", day: 8, hour: 9, minutes: 60),
            item("c", day: 8, hour: 14, minutes: 60)
        ])
        let byId = Dictionary(uniqueKeysWithValues: placed.map { ($0.item.id, $0.columns) })
        XCTAssertEqual(byId["a"], 2)
        XCTAssertEqual(byId["b"], 2)
        XCTAssertEqual(byId["c"], 1)
    }

    func testBookedMinutesIgnoresFinishedWork() {
        let minutes = CalendarLayout.bookedMinutes([
            item("a", day: 8, hour: 9, minutes: 60),
            item("b", day: 8, hour: 11, minutes: 30, done: true)
        ])
        XCTAssertEqual(minutes, 60)
    }

    // MARK: - Week

    func testWeekRunsSevenDaysFromTheWeekStart() {
        let week = CalendarWeek.week(offset: 0, calendar: calendar, now: date(9, 11))
        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(calendar.component(.day, from: week.start), 7) // Monday
        XCTAssertEqual(calendar.component(.day, from: week.end), 13)
    }

    func testWeekOffsetMovesAWholeWeek() {
        let next = CalendarWeek.week(offset: 1, calendar: calendar, now: date(9, 11))
        XCTAssertEqual(calendar.component(.day, from: next.start), 14)
    }

    // MARK: - Components

    func testScheduledComponentsRoundTripToTheSameTime() {
        let parts = TaskSchedule.components(day: date(10, 0), minuteOfDay: 14 * 60 + 45, calendar: calendar)
        XCTAssertEqual(parts.hour, 14)
        XCTAssertEqual(parts.minute, 45)
        XCTAssertEqual(TaskSchedule.dueDate(parts, calendar: calendar), date(10, 14, 45))
    }

    func testUnschedulingKeepsTheDayAndDropsTheClock() {
        let scheduled = TaskSchedule.components(day: date(11, 0), minuteOfDay: 9 * 60, calendar: calendar)
        let dayOnly = TaskSchedule.dayOnlyComponents(from: scheduled, calendar: calendar)
        XCTAssertNil(dayOnly?.hour)
        XCTAssertEqual(dayOnly?.day, 11)
        XCTAssertEqual(TaskSchedule.dueDate(dayOnly, calendar: calendar), date(11, 0))
    }

    func testDueDateResolvesComponentsThatCarryNoCalendar() {
        var bare = DateComponents()
        bare.year = 2026; bare.month = 9; bare.day = 10; bare.hour = 9
        XCTAssertNil(bare.date)
        XCTAssertEqual(TaskSchedule.dueDate(bare, calendar: calendar), date(10, 9))
    }
}
