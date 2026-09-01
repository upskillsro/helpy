import EventKit
import SwiftUI

/// One square in the Lists grid.
///
/// A preview, not a control: the task cards are inert, so the only thing you
/// can hit is the cell itself and the overflow menu. A checkbox here would only
/// ever be pressed by accident on the way to opening the list.
struct ListCellView: View {
    let list: EKCalendar
    let reminders: [EKReminder]
    let onOpen: () -> Void

    @EnvironmentObject var iconStore: ListIconStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private static let peekLimit = 4
    private static let borderWidth: CGFloat = 3

    private var peeked: [EKReminder] { Array(reminders.prefix(Self.peekLimit)) }
    private var overflow: Int { max(0, reminders.count - peeked.count) }

    private var pendingLabel: String {
        reminders.count == 1 ? "1 pending task" : "\(reminders.count) pending tasks"
    }

    var body: some View {
        // The square comes from the cell's width, never from its content. Sized
        // by content, a cell holding four task cards came out taller than one
        // reading ALL CLEAR and the row stopped lining up.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { cell }
            .contextMenu { menuItems }
            .help(list.title)
    }

    private var cell: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                titleRow

                if peeked.isEmpty {
                    allClear
                } else {
                    VStack(spacing: 5) {
                        ForEach(peeked, id: \.calendarItemIdentifier) { reminder in
                            taskCard(reminder, index: (peeked.firstIndex(of: reminder) ?? 0) + 1)
                        }
                        if overflow > 0 {
                            Text("+\(overflow) more")
                                .font(.inter(size: 10))
                                .foregroundStyle(t.muted2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }

                Text(pendingLabel)
                    .font(.inter(size: 10.5, weight: .medium))
                    .foregroundStyle(t.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(17)
            .background(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .fill(isHovering ? t.surfaceHover : t.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(isHovering ? t.rail : t.line, lineWidth: Self.borderWidth)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            ListIconSquare(
                listId: list.calendarIdentifier,
                title: list.title,
                color: list.helpyColor,
                side: 18,
                cornerRadius: 5,
                acceptsDrop: true
            )
            Text(list.title)
                .font(.inter(size: 13, weight: .semibold))
                .foregroundStyle(t.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 2)

            // Inside the cell rather than on hover: a menu that appears only
            // when you are already hovering is a menu nobody finds.
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.muted2)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18, height: 18)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Open List", action: onOpen)
        Divider()
        Button("Choose Icon…") {
            ListIconPicker.present(for: list.calendarIdentifier, in: iconStore)
        }
        if iconStore.hasIcon(for: list.calendarIdentifier) {
            Button("Remove Icon") {
                iconStore.removeIcon(for: list.calendarIdentifier)
            }
        }
    }

    private func taskCard(_ reminder: EKReminder, index: Int) -> some View {
        HStack(spacing: 7) {
            Text("\(index)")
                .font(.inter(size: 9.5, weight: .medium))
                .foregroundStyle(t.muted2)
                .monospacedDigit()
                .frame(minWidth: 8, alignment: .trailing)
            Text(reminder.title ?? "")
                .font(.inter(size: 11))
                .foregroundStyle(t.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(t.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(t.line, lineWidth: 1)
        )
    }

    private var allClear: some View {
        VStack(spacing: 7) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(t.success)
            Text("ALL CLEAR")
                .font(.inter(size: 10, weight: .bold))
                .kerning(1)
                .foregroundStyle(t.muted2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The trailing cell that opens the create-list sheet. Hidden entirely when no
/// Reminders source can hold a new list, rather than failing on click.
struct NewListCell: View {
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var t: HelpyPalette { .forScheme(colorScheme) }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { cell }
    }

    private var cell: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                Text("New list")
                    .font(.inter(size: 11.5, weight: .medium))
            }
            .foregroundStyle(isHovering ? t.accent : t.muted2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                .fill(isHovering ? t.surfaceHover : t.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isHovering ? t.accent.opacity(0.55) : t.line,
                    style: StrokeStyle(lineWidth: 3, dash: [5, 4])
                )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}
