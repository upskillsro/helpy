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
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlog: return "Backlog"
        case .thisWeek: return "This week"
        case .today: return "Today"
        case .completed: return "Completed"
        }
    }

    /// Completion is a flag on the task, not a date, so this one column is
    /// filled from a separate fetch and can never come out of
    /// `bucket(forDueDate:)`. Everything that walks due dates skips it.
    var isDoneColumn: Bool { self == .completed }

    /// Left-to-right board order.
    static let boardOrder: [TaskBucket] = [.backlog, .thisWeek, .today, .completed]
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

    /// The exclusive end of the board's "this week" window.
    ///
    /// Normally that is simply the start of next week. On the FINAL day of the
    /// week it is not: every day left in the week is today, so the window is
    /// empty and the This week column became an undroppable dead end — a card
    /// dragged out of Today was handed today's date straight back and snapped
    /// home. On that one day the window rolls forward, so "this week" means the
    /// week that starts tomorrow. (Sunday evening planning works the way people
    /// actually talk: "do it this week" means the week ahead.)
    var thisWeekEnd: Date {
        guard startOfNextWeek <= startOfTomorrow else { return startOfNextWeek }
        return calendar.date(byAdding: .weekOfYear, value: 1, to: startOfNextWeek) ?? startOfNextWeek
    }

    /// The last calendar day that still counts as "this week".
    var lastDayOfWeek: Date {
        calendar.date(byAdding: .day, value: -1, to: thisWeekEnd) ?? startOfToday
    }

    /// The column a due date puts a task in.
    ///
    /// Note the last rule: a task due after this week is Backlog, not a fourth
    /// column and not nowhere. "Backlog" means *not this week*, not *undated* —
    /// without that, a task due next month would vanish off the board entirely.
    func bucket(forDueDate date: Date?) -> TaskBucket {
        guard let date else { return .backlog }
        // Never returns `.completed`: see `TaskBucket.isDoneColumn`.
        if date < startOfTomorrow { return .today }      // due today, or overdue
        if date < thisWeekEnd { return .thisWeek }
        return .backlog
    }

    func bucket(for reminder: EKReminder) -> TaskBucket {
        bucket(forDueDate: reminder.dueDateComponents?.date)
    }

    /// The due date a card takes on when it is dropped into a column, as day
    /// components with no time of day.
    ///
    /// Backlog clears the date. A column means a *day*, so no hour is written:
    /// deriving components from a Date used to stamp every card dropped into
    /// Today as due at 9:00, alarm included.
    ///
    /// On the final day of a week the window has already rolled forward (see
    /// `thisWeekEnd`), so a card dropped into This week is due at the end of the
    /// week that starts tomorrow rather than snapping back into Today.
    func dueDateComponents(for bucket: TaskBucket) -> DateComponents? {
        switch bucket {
        case .backlog, .completed:
            return nil
        case .today:
            return dayComponents(startOfToday)
        case .thisWeek:
            return dayComponents(max(lastDayOfWeek, startOfToday))
        }
    }

    /// Carries the calendar with it: without one, `DateComponents.date` is nil,
    /// and every caller that turns these back into a Date silently gets
    /// nothing — including the bucketing that decides which column they land in.
    private func dayComponents(_ day: Date) -> DateComponents {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.calendar = calendar
        return components
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
