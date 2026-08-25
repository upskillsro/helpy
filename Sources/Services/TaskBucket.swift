import EventKit
import Foundation

/// Which column of a list board a task sits in.
///
/// A bucket is always DERIVED from the due date, never stored alongside it.
/// Dragging a card writes the due date its target column implies, so the move
/// round-trips through EventKit and shows up in Apple Reminders on every device.
/// Storing the column separately would give us two sources of truth that drift
/// the moment a task is edited on the phone.
enum TaskBucket: String, CaseIterable, Identifiable {
    case backlog
    case thisWeek
    case today

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlog: return "Backlog"
        case .thisWeek: return "This week"
        case .today: return "Today"
        }
    }

    /// Left-to-right board order.
    static let boardOrder: [TaskBucket] = [.backlog, .thisWeek, .today]
}

/// The date arithmetic behind the board columns and the planning weeks.
///
/// Both features ask this one type where a week starts and ends, so a task the
/// board calls "this week" is always the same week the planner is showing.
/// `calendar` and `now` are injected so the boundary cases are testable without
/// waiting for a Sunday.
struct HelpyWeek {
    let calendar: Calendar
    let now: Date

    init(calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        self.now = now
    }

    var startOfToday: Date { calendar.startOfDay(for: now) }

    var startOfTomorrow: Date {
        calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
    }

    /// First moment of the current week, per the user's own `firstWeekday`.
    var startOfWeek: Date {
        calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
    }

    /// First moment of next week — the exclusive end of this one.
    var startOfNextWeek: Date {
        calendar.dateInterval(of: .weekOfYear, for: now)?.end
            ?? calendar.date(byAdding: .day, value: 7, to: startOfWeek)
            ?? startOfWeek
    }

    /// The last calendar day that still counts as "this week".
    var lastDayOfWeek: Date {
        calendar.date(byAdding: .day, value: -1, to: startOfNextWeek) ?? startOfToday
    }

    /// The column a due date puts a task in.
    ///
    /// Note the last rule: a task due after this week is Backlog, not a fourth
    /// column and not nowhere. "Backlog" means *not this week*, not *undated* —
    /// without that, a task due next month would vanish off the board entirely.
    func bucket(forDueDate date: Date?) -> TaskBucket {
        guard let date else { return .backlog }
        if date < startOfTomorrow { return .today }      // due today, or overdue
        if date < startOfNextWeek { return .thisWeek }
        return .backlog
    }

    func bucket(for reminder: EKReminder) -> TaskBucket {
        bucket(forDueDate: reminder.dueDateComponents?.date)
    }

    /// The due date a card takes on when it is dropped into a column.
    ///
    /// Backlog clears the date. The other two land on 9:00 local, which is the
    /// hour Reminders itself defaults an all-day task to.
    ///
    /// On the final day of a week, "this week" and "today" are the same day, so
    /// a card dropped into This week lands in Today. That is right — there is
    /// no time left in the week that is not today.
    func dueDate(for bucket: TaskBucket) -> Date? {
        switch bucket {
        case .backlog:
            return nil
        case .today:
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: startOfToday)
        case .thisWeek:
            let day = max(lastDayOfWeek, startOfToday)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
        }
    }
}

/// One week in the Planning tab.
///
/// `id` is the key the plan is stored under. It is built from the calendar's own
/// week-of-year components, so it stays stable across launches and is readable
/// in a defaults dump when something looks wrong.
struct PlanWeek: Identifiable, Equatable {
    let start: Date
    let end: Date          // exclusive
    let id: String
    let isCurrent: Bool

    var lastDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: end) ?? start
    }

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = parts.yearForWeekOfYear ?? 0
        let week = parts.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    /// The rolling window the Planning tab shows: a few weeks of history for
    /// context, the current week, and enough runway to plan ahead. Weeks outside
    /// the window are neither shown nor created — there is no infinite scroll
    /// and no backfill.
    static func rollingWindow(
        weeksBack: Int = 4,
        weeksForward: Int = 8,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [PlanWeek] {
        let current = HelpyWeek(calendar: calendar, now: now).startOfWeek
        return (-weeksBack...weeksForward).compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: current),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)
            else { return nil }
            return PlanWeek(
                start: start,
                end: end,
                id: key(for: start, calendar: calendar),
                isCurrent: offset == 0
            )
        }
    }
}
