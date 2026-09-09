import EventKit
import SwiftUI

/// The left rail: everything in the visible lists that has no time yet.
///
/// Cards are `ReminderRowView`, the same component the board and the strip use,
/// so a task looks identical wherever it is waiting. A card leaves the rail by
/// being dropped on the grid and comes back by being dragged onto the rail.
struct UnscheduledRailView: View {
    let lists: [EKCalendar]
    @Binding var selectedListId: String?
    let reminders: [EKReminder]
    let totalMinutes: Int
    let isTargeted: Bool
    let isDraggingAppWide: Bool
    let draggedId: String?
    let onDragStart: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showListPicker = false

    private var t: HelpyPalette { .forScheme(colorScheme) }

    private var selectedList: EKCalendar? {
        lists.first { $0.calendarIdentifier == selectedListId }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            sectionLabel
            cards
            footer
        }
        .background(t.canvas)
        .overlay(alignment: .trailing) {
            // The rail is a drop target for a block on its way back out of the
            // week: a bar rather than a fill, so the cards under it stay legible.
            Rectangle()
                .fill(t.rail)
                .frame(width: 3)
                .opacity(isTargeted ? 1 : 0)
                .animation(.easeOut(duration: 0.14), value: isTargeted)
        }
    }

    /// A plain button plus a popover rather than a `Menu`: a borderless menu on
    /// macOS draws its own title and indicator and throws the custom label
    /// away, which left this header as a lone chevron.
    private var header: some View {
        VStack(spacing: 0) {
            Button { showListPicker.toggle() } label: {
                HStack(spacing: 9) {
                    ListIconSquare(
                        listId: selectedList?.calendarIdentifier ?? "",
                        title: selectedList?.title ?? "All",
                        color: selectedList?.helpyColor ?? t.accent,
                        side: 24,
                        cornerRadius: 7,
                        acceptsDrop: false
                    )
                    Text(selectedList?.title ?? "All lists")
                        .font(.inter(size: 13, weight: .bold))
                        .foregroundStyle(t.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(t.muted2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                        .fill(t.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                        .strokeBorder(t.line, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showListPicker, arrowEdge: .bottom) { listPicker }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 11)

            Rectangle().fill(t.line).frame(height: 1)
        }
    }

    private var listPicker: some View {
        VStack(alignment: .leading, spacing: 1) {
            pickerRow(title: "All lists", listId: nil, color: t.accent, iconId: "")
            Rectangle().fill(t.line).frame(height: 1).padding(.vertical, 3)
            ForEach(lists, id: \.calendarIdentifier) { list in
                pickerRow(
                    title: list.title,
                    listId: list.calendarIdentifier,
                    color: list.helpyColor,
                    iconId: list.calendarIdentifier
                )
            }
        }
        .padding(6)
        .frame(width: 232)
    }

    private func pickerRow(
        title: String, listId: String?, color: Color, iconId: String
    ) -> some View {
        let isSelected = selectedListId == listId
        return Button {
            selectedListId = listId
            showListPicker = false
        } label: {
            HStack(spacing: 8) {
                ListIconSquare(
                    listId: iconId, title: title, color: color,
                    side: 18, cornerRadius: 5, acceptsDrop: false
                )
                Text(title)
                    .font(.inter(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(t.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(t.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? t.surfaceActive : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sectionLabel: some View {
        HStack(spacing: 6) {
            Text("UNSCHEDULED")
                .font(.inter(size: 9, weight: .bold))
                .kerning(0.9)
                .foregroundStyle(t.muted2)
            Spacer()
            Text("\(reminders.count)")
                .font(.inter(size: 9))
                .foregroundStyle(t.muted2)
        }
        .padding(.horizontal, 13)
        .padding(.top, 12)
        .padding(.bottom, 7)
    }

    @ViewBuilder
    private var cards: some View {
        if reminders.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(t.muted2)
                Text("Everything has a time")
                    .font(.inter(size: 11))
                    .foregroundStyle(t.muted2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(reminders, id: \.calendarItemIdentifier) { reminder in
                        ReminderRowView(
                            reminder: reminder,
                            isDraggingAppWide: isDraggingAppWide,
                            isBeingDragged: draggedId == reminder.calendarItemIdentifier
                        )
                        .onDrag {
                            onDragStart(reminder.calendarItemIdentifier)
                            return NSItemProvider(object: reminder.calendarItemIdentifier as NSString)
                        } preview: {
                            BoardDragPreview(title: reminder.title ?? "", palette: t)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 10)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(t.line).frame(height: 1)
            HStack(spacing: 6) {
                Text("Unscheduled")
                    .font(.inter(size: 11))
                    .foregroundStyle(t.muted)
                Spacer()
                Text(CalendarFormat.duration(minutes: totalMinutes))
                    .font(.inter(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(t.ink)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
        }
    }
}

enum CalendarFormat {
    /// "1h 30m", "45m", "—".
    static func duration(minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func clock(minuteOfDay: Int, on day: Date, calendar: Calendar = .current) -> String {
        let date = calendar.date(
            bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day
        ) ?? day
        return clock(date)
    }
}
