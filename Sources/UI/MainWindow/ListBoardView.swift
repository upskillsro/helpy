import AppKit
import EventKit
import SwiftUI

/// A list opened as a board: Backlog → This week → Today → Completed.
///
/// The first three columns are derived from due dates, and dragging a card
/// between them rewrites the due date its new column implies — so a move here
/// shows up in Apple Reminders and on the phone, not just in Helpy. Completed
/// is the odd one out: it is a flag, not a date, so dropping into it ticks the
/// task and dragging back out un-ticks it and gives it the date of wherever it
/// landed.
struct ListBoardView: View {
    let list: EKCalendar

    @EnvironmentObject var remindersService: RemindersService
    @EnvironmentObject var navigation: AppNavigation
    @Environment(\.colorScheme) private var colorScheme

    @State private var draggedId: String?

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var week: HelpyWeek { HelpyWeek() }

    private var open: [EKReminder] { remindersService.reminders(in: list.calendarIdentifier) }
    private var done: [EKReminder] { remindersService.completedReminders(in: list.calendarIdentifier) }

    private var buckets: [TaskBucket: [EKReminder]] {
        Dictionary(grouping: open) { week.bucket(for: $0) }
    }

    var body: some View {
        let grouped = buckets

        VStack(spacing: 12) {
            ListBoardHeader(list: list, pendingCount: open.count)

            HStack(alignment: .top, spacing: 10) {
                ForEach(TaskBucket.boardOrder) { bucket in
                    BoardColumnView(
                        bucket: bucket,
                        reminders: bucket.isDoneColumn ? done : (grouped[bucket] ?? []),
                        isDraggingAppWide: draggedId != nil,
                        draggedId: draggedId,
                        onDrop: { identifier, index in place(identifier, into: bucket, at: index) },
                        onAdd: { title in add(title, to: bucket) },
                        onFocus: bucket == .today
                            ? { navigation.focus(on: list.calendarIdentifier) }
                            : nil,
                        onDragStart: { draggedId = $0 }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(t.canvas)
        .onAppear { remindersService.fetchAllLists() }
        // A drag the user abandons outside the window never reports an end, so
        // the drop slots would stay open forever. The first pointer move with
        // no button held closes them.
        .onContinuousHover { phase in
            guard draggedId != nil, case .active = phase else { return }
            if NSEvent.pressedMouseButtons & 1 == 0 { draggedId = nil }
        }
    }

    // MARK: - Moving cards

    /// Puts a card in a column at a position.
    ///
    /// Both halves matter: the column decides the due date (or the completion
    /// flag), the position decides where it sits among its neighbours. A drop
    /// inside the column a card already lives in only reorders it — that keeps
    /// a task with a real time today from being flattened to 9:00 just because
    /// it was nudged up one slot.
    private func place(_ identifier: String, into bucket: TaskBucket, at index: Int) {
        draggedId = nil

        if let reminder = done.first(where: { $0.calendarItemIdentifier == identifier }) {
            reopen(reminder, into: bucket, at: index)
            return
        }

        guard let reminder = open.first(where: { $0.calendarItemIdentifier == identifier }) else { return }

        if bucket.isDoneColumn {
            remindersService.toggleComplete(reminder)
            return
        }

        if week.bucket(for: reminder) != bucket {
            remindersService.updateDueDate(reminder, components: week.dueDateComponents(for: bucket))
        }
        remindersService.placeReminder(
            identifier, atIndex: index, of: bucket,
            inListId: list.calendarIdentifier, week: week
        )
    }

    /// Dragging out of Completed. Un-ticks first so the card is back among the
    /// open tasks, then dates and places it — otherwise it would be ordered
    /// against a list it is not in yet.
    private func reopen(_ reminder: EKReminder, into bucket: TaskBucket, at index: Int) {
        guard !bucket.isDoneColumn else { return }
        remindersService.toggleComplete(reminder)
        remindersService.updateDueDate(reminder, components: week.dueDateComponents(for: bucket))
    }

    private func add(_ title: String, to bucket: TaskBucket) {
        guard !bucket.isDoneColumn else { return }
        remindersService.createReminder(
            title: title,
            in: list,
            dueDate: week.dueDateComponents(for: bucket)
        )
        remindersService.fetchAllLists()
    }
}

/// The list's identity above the board: icon, name and how much is open, as one
/// object rather than a chip beside a title.
struct ListBoardHeader: View {
    let list: EKCalendar
    let pendingCount: Int

    @Environment(\.colorScheme) private var colorScheme
    private var t: HelpyPalette { .forScheme(colorScheme) }

    private var pendingLabel: String {
        pendingCount == 1 ? "1 open" : "\(pendingCount) open"
    }

    var body: some View {
        HStack(spacing: 10) {
            ListIconSquare(
                listId: list.calendarIdentifier,
                title: list.title,
                color: list.helpyColor,
                side: 26,
                cornerRadius: 7,
                acceptsDrop: true
            )

            Text(list.title)
                .font(.inter(size: 16, weight: .bold))
                .foregroundStyle(t.ink)
                .lineLimit(1)

            Text(pendingLabel)
                .font(.inter(size: 10.5, weight: .semibold))
                .foregroundStyle(t.chipText)
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(t.chipFill))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                .fill(t.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(t.line, lineWidth: 1)
        )
    }
}
