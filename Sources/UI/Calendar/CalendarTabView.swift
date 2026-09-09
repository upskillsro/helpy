import AppKit
import EventKit
import SwiftUI

/// The Calendar tab: an unscheduled rail on the left, a week of time on the
/// right, and dragging between them as the only way to allocate a day.
///
/// Nothing here is a new store. A block *is* a reminder whose due date carries
/// an hour, and its height *is* the estimate `EstimateStore` already holds — so
/// a task scheduled here moves on the board, syncs to the phone, and can be
/// dragged back out without leaving anything behind. See `TaskSchedule`.
struct CalendarTabView: View {
    @EnvironmentObject var remindersService: RemindersService
    @EnvironmentObject var estimateStore: EstimateStore
    @EnvironmentObject var subtaskStore: SubtaskStore
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var settings = SettingsStore()
    @ObservedObject private var taskColors = TaskColorStore.shared

    @State private var weekOffset = 0
    /// nil = every list at once.
    @State private var selectedListId: String?
    /// The rail card currently under the pointer, and how long its block will be.
    @State private var railDrag: RailDrag?
    /// A block is being dragged back over the rail. The grid owns the rest of
    /// the drag; only this crosses back, so only this is shared.
    @State private var blockOverRail = false
    @State private var isOverRail = false
    /// The block whose detail panel is open.
    @State private var selectedTaskId: String?

    /// One coordinate space for the whole tab, so a block being dragged can ask
    /// whether the pointer has crossed back into the rail.
    static let space = "helpy.calendar"
    static let railWidth: CGFloat = 246
    static let gutterWidth: CGFloat = 52
    static let hourHeight: CGFloat = 52

    private var t: HelpyPalette { .forScheme(colorScheme) }

    var body: some View {
        Group {
            if !remindersService.isAccessGranted {
                RemindersAccessDeniedView()
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.canvas)
        .coordinateSpace(name: Self.space)
        .onAppear { remindersService.fetchAllLists() }
        // A drag the user abandons off-window never reports an end, so the drop
        // ghost would stay armed forever. The first pointer move with no button
        // held disarms it — the same guard the board uses.
        .onContinuousHover { phase in
            guard railDrag != nil, case .active = phase else { return }
            if NSEvent.pressedMouseButtons & 1 == 0 { railDrag = nil }
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            UnscheduledRailView(
                lists: remindersService.lists,
                selectedListId: $selectedListId,
                reminders: unscheduled,
                totalMinutes: unscheduledMinutes,
                isTargeted: isOverRail || blockOverRail,
                isDraggingAppWide: railDrag != nil,
                draggedId: railDrag?.id,
                onDragStart: { id in railDrag = RailDrag(id: id, minutes: minutes(forTask: id)) }
            )
            .frame(width: Self.railWidth)

            Rectangle().fill(t.line).frame(width: 1)

            CalendarWeekGrid(
                week: week,
                grid: grid,
                items: items,
                palette: t,
                capacityMinutes: Int(settings.calendarDailyCapacityHours * 60),
                railDrag: railDrag,
                selectedId: selectedTaskId,
                blockOverRail: $blockOverRail,
                weekOffset: $weekOffset,
                onScheduleDrop: schedule,
                onMove: { move($0, dayIndex: $1, minute: $2) },
                onResize: { applyResize($0, minutes: $1) },
                onUnschedule: unschedule,
                onComplete: complete,
                onSelect: { selectedTaskId = $0 }
            )
            .frame(maxWidth: .infinity)

            if let selected {
                Rectangle().fill(t.line).frame(width: 1)
                TaskDetailPanel(
                    item: selected,
                    listName: listName(selected.listId),
                    notes: remindersService.reminder(withId: selected.id)?.notes ?? "",
                    palette: t,
                    grid: grid,
                    week: week,
                    subtaskStore: subtaskStore,
                    onTitle: { rename(selected.id, to: $0) },
                    onNotes: { note(selected.id, to: $0) },
                    onColor: { taskColors.setColor($0, for: selected.id) },
                    onMove: { move(selected.id, dayIndex: $0, minute: $1) },
                    onLength: { applyResize(selected.id, minutes: $0) },
                    onComplete: { complete(selected.id) },
                    onUnschedule: {
                        unschedule(selected.id)
                        selectedTaskId = nil
                    },
                    onClose: { selectedTaskId = nil }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.16), value: selectedTaskId)
    }

    /// The open block, or nothing when it has been unscheduled or the week
    /// moved off it.
    private var selected: ScheduledItem? {
        guard let selectedTaskId else { return nil }
        return items.first { $0.id == selectedTaskId }
    }

    private func listName(_ id: String) -> String {
        remindersService.lists.first { $0.calendarIdentifier == id }?.title ?? ""
    }

    // MARK: - Data

    private var week: CalendarWeek { CalendarWeek.week(offset: weekOffset) }

    private var visibleLists: [EKCalendar] {
        guard let selectedListId else { return remindersService.lists }
        return remindersService.lists.filter { $0.calendarIdentifier == selectedListId }
    }

    /// Everything open in the visible lists, plus what was finished there — a
    /// day that reads as empty because its work is done is a lie about how the
    /// day went.
    private var allReminders: [EKReminder] {
        visibleLists.flatMap {
            remindersService.reminders(in: $0.calendarIdentifier)
                + remindersService.completedReminders(in: $0.calendarIdentifier)
        }
    }

    private var unscheduled: [EKReminder] {
        visibleLists
            .flatMap { remindersService.reminders(in: $0.calendarIdentifier) }
            .filter { !TaskSchedule.isScheduled($0) }
    }

    private var unscheduledMinutes: Int {
        unscheduled.reduce(0) { $0 + minutes(forTask: $1.calendarItemIdentifier) }
    }

    /// The blocks for the visible week, one per scheduled task.
    private var items: [ScheduledItem] {
        let calendar = Calendar.current
        guard let first = week.days.first,
              let limit = calendar.date(byAdding: .day, value: 7, to: first)
        else { return [] }

        let colors = Dictionary(
            remindersService.lists.map { ($0.calendarIdentifier, $0.helpyColor.helpyHex ?? 0x0086E8) },
            uniquingKeysWith: { first, _ in first }
        )

        return allReminders.compactMap { reminder in
            guard let start = TaskSchedule.startTime(of: reminder),
                  start >= first, start < limit,
                  let listId = reminder.calendar?.calendarIdentifier
            else { return nil }
            return ScheduledItem(
                id: reminder.calendarItemIdentifier,
                title: reminder.title ?? "",
                start: start,
                minutes: minutes(forTask: reminder.calendarItemIdentifier),
                listId: listId,
                listColorHex: colors[listId] ?? 0x0086E8,
                isDone: reminder.isCompleted,
                priority: reminder.priority,
                overrideColorHex: taskColors.color(for: reminder.calendarItemIdentifier)
            )
        }
    }

    /// A block is as long as its estimate. Without one it is half an hour on
    /// screen and still zero in the store — dragging its bottom edge is what
    /// turns that into a real estimate.
    private func minutes(forTask id: String) -> Int {
        let seconds = estimateStore.getMetadata(for: id)?.estimatedDuration ?? 0
        guard seconds > 0 else { return ScheduledItem.defaultMinutes }
        return max(ScheduledItem.minimumMinutes, Int(seconds) / 60)
    }

    private var grid: CalendarGrid {
        CalendarGrid.fitting(
            items,
            startHour: settings.calendarDayStartHour,
            endHour: settings.calendarDayEndHour,
            hourHeight: Self.hourHeight
        )
    }

    // MARK: - Moves

    private func schedule(_ id: String, day: Date, minute: Int) {
        railDrag = nil
        guard let reminder = remindersService.reminder(withId: id) else { return }
        remindersService.schedule(
            reminder, day: day, minuteOfDay: minute, alarm: settings.calendarBlockAlarms
        )
    }

    private func move(_ id: String, dayIndex: Int, minute: Int) {
        guard week.days.indices.contains(dayIndex),
              let reminder = remindersService.reminder(withId: id) else { return }
        remindersService.schedule(
            reminder, day: week.days[dayIndex], minuteOfDay: minute,
            alarm: settings.calendarBlockAlarms
        )
    }

    private func unschedule(_ id: String) {
        railDrag = nil
        guard let reminder = remindersService.reminder(withId: id) else { return }
        remindersService.unschedule(reminder)
    }

    private func applyResize(_ id: String, minutes: Int) {
        estimateStore.updateEstimate(for: id, duration: TimeInterval(minutes * 60))
    }

    private func rename(_ id: String, to title: String) {
        guard let reminder = remindersService.reminder(withId: id) else { return }
        remindersService.updateTitle(reminder, newTitle: title)
    }

    private func note(_ id: String, to notes: String) {
        guard let reminder = remindersService.reminder(withId: id) else { return }
        remindersService.updateNotes(reminder, newNotes: notes)
    }

    private func complete(_ id: String) {
        guard let reminder = remindersService.reminder(withId: id) else { return }
        remindersService.toggleComplete(reminder)
    }
}

// MARK: - Drag state

/// A card on its way out of the rail. The length travels with it so the drop
/// preview is the size of the block that will land.
struct RailDrag: Equatable {
    let id: String
    let minutes: Int
}

/// A block being moved inside the grid. Deltas rather than an absolute position:
/// the block keeps the part of itself the pointer grabbed.
struct BlockDrag: Equatable {
    let id: String
    let dayIndex: Int
    let startMinute: Int
    let minutes: Int
    var dayDelta: Int = 0
    var minuteDelta: Int = 0
    var overRail: Bool = false
}

struct BlockResize: Equatable {
    let id: String
    var minutes: Int
}
