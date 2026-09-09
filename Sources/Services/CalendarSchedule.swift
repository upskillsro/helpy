import EventKit
import Foundation

// MARK: - Scheduled item

/// One task placed on the calendar: a start time and a length.
///
/// The start is the reminder's own due date *with* an hour, and the length is
/// its estimate. Neither is stored twice — this is a read of the two sources
/// the app already has (EventKit and `EstimateStore`), assembled for layout.
struct ScheduledItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let minutes: Int
    let listId: String
    let listColorHex: UInt32
    let isDone: Bool
    let priority: Int
    /// Set from the detail panel. Nil means the block follows its list.
    var overrideColorHex: UInt32?

    var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }

    /// The block a task gets when it has no estimate yet. Dropping does not
    /// write it: an untouched block is a half hour on screen and a zero in the
    /// store, and dragging its edge is what turns it into a real estimate.
    static let defaultMinutes = 30
    static let minimumMinutes = 15
}

// MARK: - The grid

/// The visible time window and the arithmetic that maps a time to a y offset
/// and a y offset back to a time.
///
/// One type owns both directions on purpose: a drop reads a y and writes a
/// time, and a block reads a time and draws at a y, so the two have to agree
/// exactly or a card lands an hour from where it was dropped.
struct CalendarGrid: Equatable {
    /// Inclusive first hour shown.
    let startHour: Int
    /// Exclusive last hour shown: 20 means the grid stops at 20:00.
    let endHour: Int
    let hourHeight: CGFloat
    let snapMinutes: Int

    init(startHour: Int = 8, endHour: Int = 20, hourHeight: CGFloat = 52, snapMinutes: Int = 15) {
        let start = max(0, min(23, startHour))
        self.startHour = start
        self.endHour = max(start + 1, min(24, endHour))
        self.hourHeight = hourHeight
        self.snapMinutes = max(5, snapMinutes)
    }

    var hours: [Int] { Array(startHour..<endHour) }
    var firstMinute: Int { startHour * 60 }
    var lastMinute: Int { endHour * 60 }
    var totalHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }

    /// y for a wall-clock minute count, measured from the top of the grid.
    func y(forMinuteOfDay minute: Int) -> CGFloat {
        CGFloat(minute - firstMinute) / 60 * hourHeight
    }

    func y(for date: Date, calendar: Calendar = .current) -> CGFloat {
        y(forMinuteOfDay: CalendarGrid.minuteOfDay(date, calendar: calendar))
    }

    func height(forMinutes minutes: Int) -> CGFloat {
        CGFloat(max(minutes, ScheduledItem.minimumMinutes)) / 60 * hourHeight
    }

    /// The minute a y offset points at, snapped to the grid's step.
    ///
    /// `duration` keeps a block inside the window: dropped near the bottom edge
    /// it starts early enough to finish on the last row rather than rendering
    /// clipped by the frame. A block longer than the whole window starts at the
    /// top.
    func minute(atY y: CGFloat, duration: Int = 0) -> Int {
        let raw = Int(((y / hourHeight) * 60).rounded()) + firstMinute
        let snapped = Int((Double(raw) / Double(snapMinutes)).rounded()) * snapMinutes
        let latest = max(firstMinute, lastMinute - max(duration, snapMinutes))
        return min(max(snapped, firstMinute), latest)
    }

    func snap(_ minutes: Int) -> Int {
        Int((Double(minutes) / Double(snapMinutes)).rounded()) * snapMinutes
    }

    /// Clamps a start time into the window, keeping the block whole.
    func clampStart(minute: Int, duration: Int) -> Int {
        let latest = max(firstMinute, lastMinute - max(duration, snapMinutes))
        return min(max(minute, firstMinute), latest)
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Widens the default window until every scheduled item fits.
    ///
    /// The 8–20 default is what a working day looks like, not a claim about the
    /// data: a task scheduled at 06:30 on the phone still has to appear, and a
    /// window that silently hid it would read as the task being lost.
    static func fitting(
        _ items: [ScheduledItem],
        startHour: Int,
        endHour: Int,
        hourHeight: CGFloat,
        calendar: Calendar = .current
    ) -> CalendarGrid {
        var first = startHour
        var last = endHour
        for item in items {
            let begin = minuteOfDay(item.start, calendar: calendar)
            first = min(first, begin / 60)
            // A block ending at 20:00 needs the 19:00 row, not a 20:00 one.
            let finish = begin + max(item.minutes, ScheduledItem.minimumMinutes)
            last = max(last, Int(ceil(Double(finish) / 60)))
        }
        return CalendarGrid(
            startHour: first,
            endHour: min(24, last),
            hourHeight: hourHeight
        )
    }
}

// MARK: - The week

/// The seven days the grid is showing.
struct CalendarWeek: Equatable {
    let days: [Date]
    let start: Date
    let offset: Int

    static func week(offset: Int, calendar: Calendar = .current, now: Date = Date()) -> CalendarWeek {
        let thisWeek = HelpyWeek(calendar: calendar, now: now).startOfWeek
        let start = calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeek) ?? thisWeek
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        return CalendarWeek(days: days, start: start, offset: offset)
    }

    var end: Date { days.last ?? start }

    /// "8 – 14 September", or "29 September – 5 October" across a boundary.
    func title(calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let day = DateFormatter()
        day.locale = locale
        day.calendar = calendar
        day.setLocalizedDateFormatFromTemplate("d")
        let month = DateFormatter()
        month.locale = locale
        month.calendar = calendar
        month.setLocalizedDateFormatFromTemplate("MMMM")

        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        if sameMonth {
            return "\(day.string(from: first)) – \(day.string(from: last)) \(month.string(from: last))"
        }
        return "\(day.string(from: first)) \(month.string(from: first)) – "
            + "\(day.string(from: last)) \(month.string(from: last))"
    }
}

// MARK: - Overlap layout

/// Side-by-side placement for blocks that share the same hours.
///
/// Two tasks booked at 10:00 are a fact about the plan, not an error, so they
/// split the day's width instead of hiding one behind the other — the same
/// answer every calendar app gives, and the only one that makes an oversold
/// morning visible.
enum CalendarLayout {
    struct Placed: Identifiable, Equatable {
        let item: ScheduledItem
        /// 0-based lane within the day.
        let column: Int
        /// How many lanes the day is split into where this block sits.
        let columns: Int

        var id: String { item.id }
    }

    static func pack(_ items: [ScheduledItem]) -> [Placed] {
        let sorted = items.sorted {
            $0.start == $1.start ? $0.minutes > $1.minutes : $0.start < $1.start
        }

        var placed: [Placed] = []
        var cluster: [(item: ScheduledItem, column: Int)] = []
        var clusterEnd: Date?
        var laneEnds: [Date] = []

        func flush() {
            let width = max(laneEnds.count, 1)
            placed.append(contentsOf: cluster.map { Placed(item: $0.item, column: $0.column, columns: width) })
            cluster.removeAll()
            laneEnds.removeAll()
            clusterEnd = nil
        }

        for item in sorted {
            // A gap with nothing running through it ends the cluster: what
            // follows can use the full width again.
            if let end = clusterEnd, item.start >= end { flush() }

            let lane = laneEnds.firstIndex { $0 <= item.start } ?? laneEnds.count
            if lane == laneEnds.count {
                laneEnds.append(item.end)
            } else {
                laneEnds[lane] = item.end
            }
            cluster.append((item, lane))
            clusterEnd = max(clusterEnd ?? item.end, item.end)
        }
        flush()
        return placed
    }

    static func bookedMinutes(_ items: [ScheduledItem]) -> Int {
        items.filter { !$0.isDone }.reduce(0) { $0 + $1.minutes }
    }
}

// MARK: - Reading and writing a schedule

/// Turns reminders into blocks and blocks back into due dates.
///
/// The rule that makes the Calendar tab and the board agree: a due date with an
/// **hour** is scheduled and belongs on the grid; a due date without one is a
/// day, not a time, and stays in the unscheduled rail. Nothing else is stored,
/// so a task moved on the phone moves here too.
enum TaskSchedule {
    /// `DateComponents.date` is nil unless the components carry a calendar, and
    /// components that came back from EventKit do not always have one.
    static func dueDate(_ components: DateComponents?, calendar: Calendar = .current) -> Date? {
        guard let components else { return nil }
        if let date = components.date { return date }
        return calendar.date(from: components)
    }

    static func isScheduled(_ reminder: EKReminder) -> Bool {
        reminder.dueDateComponents?.hour != nil
    }

    static func startTime(of reminder: EKReminder, calendar: Calendar = .current) -> Date? {
        guard isScheduled(reminder) else { return nil }
        return dueDate(reminder.dueDateComponents, calendar: calendar)
    }

    /// The components a block writes: the day it sits on plus the time it
    /// starts at, carrying the calendar so `.date` round-trips.
    static func components(
        day: Date,
        minuteOfDay: Int,
        calendar: Calendar = .current
    ) -> DateComponents {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = minuteOfDay / 60
        parts.minute = minuteOfDay % 60
        parts.calendar = calendar
        return parts
    }

    /// Dropping a block back in the rail keeps the day and drops the clock, so
    /// a task unscheduled from Thursday is still due Thursday on the board.
    static func dayOnlyComponents(
        from components: DateComponents?,
        calendar: Calendar = .current
    ) -> DateComponents? {
        guard let date = dueDate(components, calendar: calendar) else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day], from: date)
        parts.calendar = calendar
        return parts
    }
}
