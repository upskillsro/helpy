import EventKit
import Foundation

/// Keeps a week's plan and its linked Reminders list in step.
///
/// A week can mirror into a list. When it does, every task you score in the
/// planner also becomes a real reminder due inside that week — which is exactly
/// what puts it in that list's "This week" column on the board. Ticking it in
/// either place ticks it in the other.
///
/// Every write that touches both sides goes through here. The plan store knows
/// nothing about EventKit and `RemindersService` knows nothing about plans;
/// putting the two-sided writes in one place is what stops them drifting.
@MainActor
struct WeeklyPlanSync {
    let store: WeeklyPlanStore
    let reminders: RemindersService
    /// Used when a week has no list of its own yet.
    let defaultListId: String?

    /// The list this week mirrors into.
    ///
    /// Three states, not two: a week that has never been pointed anywhere
    /// follows the default, a week set to a list uses that list, and a week
    /// switched off stores `WeeklyPlan.noList` so the default cannot quietly
    /// switch it back on.
    func listId(for week: PlanWeek) -> String? {
        switch store.plan(for: week.id).linkedListId {
        case .none: return defaultListId
        case .some(WeeklyPlan.noList): return nil
        case .some(let id): return id
        }
    }

    func linkedList(for week: PlanWeek) -> EKCalendar? {
        guard let id = listId(for: week) else { return nil }
        return reminders.lists.first { $0.calendarIdentifier == id }
    }

    // MARK: - Writes

    func addTask(title: String, points: Int, to week: PlanWeek) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var reminderId: String?
        if let listId = listId(for: week) {
            // Record what the week actually mirrored into, so changing the
            // default later cannot silently re-point a week's existing tasks.
            // Going through `setLinkedList` also drags anything already on the
            // week into the list, rather than mirroring only what comes next.
            if store.plan(for: week.id).linkedListId == nil {
                setLinkedList(listId, for: week)
            }
            reminderId = reminders.createReminder(
                title: trimmed,
                inListId: listId,
                dueDate: dueDate(in: week)
            )
        }

        store.addTask(title: trimmed, points: points, reminderId: reminderId, to: week.id)
    }

    func toggle(_ task: WeeklyPlanTask, in week: PlanWeek) {
        store.toggleTask(id: task.id, in: week.id)
        if let reminderId = task.reminderId {
            reminders.setCompleted(!task.isDone, forIdentifier: reminderId)
        }
    }

    func delete(_ task: WeeklyPlanTask, in week: PlanWeek) {
        // Only ever deletes the reminder this task created, never one the user
        // made in the list themselves.
        if let reminderId = task.reminderId {
            reminders.deleteReminder(withIdentifier: reminderId)
        }
        store.deleteTask(id: task.id, in: week.id)
    }

    func rename(_ task: WeeklyPlanTask, to title: String, in week: PlanWeek) {
        store.updateTask(id: task.id, in: week.id, title: title)
        if let reminderId = task.reminderId {
            reminders.updateTitle(forIdentifier: reminderId, newTitle: title)
        }
    }

    /// Points are Helpy's own scoring, so this never touches Reminders.
    func setPoints(_ points: Int, for task: WeeklyPlanTask, in week: PlanWeek) {
        store.updateTask(id: task.id, in: week.id, points: points)
    }

    /// Repoints a week at a different list, or switches mirroring off when
    /// `listId` is nil. Tasks that were already mirrored stay where they are —
    /// moving somebody's reminders between real lists behind their back is not
    /// something a picker should do.
    func setLinkedList(_ listId: String?, for week: PlanWeek) {
        store.setLinkedList(listId ?? WeeklyPlan.noList, for: week.id)
        if listId != nil { backfillIntoLinkedList(for: week) }
    }

    /// Pushes tasks that have no reminder yet into the week's list.
    ///
    /// Linking a week that already has tasks on it has to bring them along.
    /// Without this the list stays empty after linking and the feature simply
    /// looks broken — which is exactly how it looked.
    ///
    /// Tasks already ticked off are left alone: back-dating somebody's
    /// Reminders with completions they never made there is worse than a gap.
    func backfillIntoLinkedList(for week: PlanWeek) {
        guard let listId = listId(for: week) else { return }
        for task in store.plan(for: week.id).tasks
        where task.reminderId == nil && !task.isDone {
            guard let id = reminders.createReminder(
                title: task.title, inListId: listId, dueDate: dueDate(in: week)
            ) else { continue }
            store.setReminderId(id, forTask: task.id, in: week.id)
        }
    }

    // MARK: - Reads

    /// Pulls completion back from Reminders, so ticking a task on the board (or
    /// on your phone) shows up in the planner.
    ///
    /// A reminder that no longer exists loses its link rather than its task:
    /// the week's score is Helpy's record and must survive the user cleaning
    /// out a list.
    func refreshFromReminders(for week: PlanWeek) {
        for task in store.plan(for: week.id).tasks {
            guard let reminderId = task.reminderId else { continue }
            guard let isCompleted = reminders.completionState(forIdentifier: reminderId) else {
                store.setReminderId(nil, forTask: task.id, in: week.id)
                continue
            }
            store.setTaskDone(isCompleted, id: task.id, in: week.id)
        }
    }

    /// 9am on the week's last day. For the current week that lands the task in
    /// the board's "This week" column, which is the point. A future week's
    /// tasks correctly file under Backlog until that week comes round, and a
    /// past week's read as overdue.
    private func dueDate(in week: PlanWeek) -> DateComponents? {
        Calendar.current.dateComponents([.year, .month, .day], from: week.lastDay)
    }
}
