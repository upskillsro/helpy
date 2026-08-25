import EventKit
import SwiftUI

/// A list opened as a board: Backlog → This week → Today.
///
/// Columns are derived from due dates, and dragging a card rewrites the due date
/// its new column implies — so a move here shows up in Apple Reminders and on
/// the phone, not just in Helpy.
struct ListBoardView: View {
    let list: EKCalendar

    @EnvironmentObject var remindersService: RemindersService
    @EnvironmentObject var navigation: AppNavigation
    @Environment(\.colorScheme) private var colorScheme

    @State private var draggedId: String?

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var week: HelpyWeek { HelpyWeek() }

    private var buckets: [TaskBucket: [EKReminder]] {
        Dictionary(grouping: remindersService.reminders(in: list.calendarIdentifier)) {
            week.bucket(for: $0)
        }
    }

    var body: some View {
        let grouped = buckets

        HStack(alignment: .top, spacing: 10) {
            ForEach(TaskBucket.boardOrder) { bucket in
                BoardColumnView(
                    bucket: bucket,
                    reminders: grouped[bucket] ?? [],
                    isDraggingAppWide: draggedId != nil,
                    draggedId: draggedId,
                    onDrop: { identifier in move(identifier, to: bucket) },
                    onAdd: { title in add(title, to: bucket) },
                    onFocus: bucket == .today
                        ? { navigation.focus(on: list.calendarIdentifier) }
                        : nil
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(t.canvas)
        .onAppear { remindersService.fetchAllLists() }
    }

    /// A card dropped into the column it already lives in is left alone — that
    /// keeps a task with a real time today from being flattened to 9:00 just
    /// because it was nudged.
    private func move(_ identifier: String, to bucket: TaskBucket) {
        draggedId = nil
        guard let reminder = remindersService.reminders(in: list.calendarIdentifier)
            .first(where: { $0.calendarItemIdentifier == identifier })
        else { return }

        guard week.bucket(for: reminder) != bucket else { return }
        remindersService.updateDueDate(reminder, date: week.dueDate(for: bucket))
    }

    private func add(_ title: String, to bucket: TaskBucket) {
        let due = week.dueDate(for: bucket).map {
            Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
        }
        remindersService.createReminder(title: title, in: list, dueDate: due)
        remindersService.fetchAllLists()
    }
}
