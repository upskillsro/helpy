import EventKit
import SwiftUI

/// One square in the Lists grid: an icon, the list name, and a peek at what is
/// actually in the list. Deliberately no progress bar and no task count — the
/// grid is for recognising a list, not for reading its stats.
struct ListCellView: View {
    let list: EKCalendar
    let reminders: [EKReminder]
    let onOpen: () -> Void

    @EnvironmentObject var iconStore: ListIconStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private static let peekLimit = 2

    private var peeked: [EKReminder] { Array(reminders.prefix(Self.peekLimit)) }
    private var overflow: Int { max(0, reminders.count - peeked.count) }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    ListIconSquare(
                        listId: list.calendarIdentifier,
                        title: list.title,
                        color: list.helpyColor,
                        side: 18,
                        cornerRadius: 5,
                        acceptsDrop: true
                    )
                    Text(list.title)
                        .font(.inter(size: 11, weight: .semibold))
                        .foregroundStyle(t.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                VStack(alignment: .leading, spacing: 3) {
                    if peeked.isEmpty {
                        Text("Nothing open")
                            .font(.inter(size: 9.5))
                            .foregroundStyle(t.muted2)
                    } else {
                        ForEach(peeked, id: \.calendarItemIdentifier) { reminder in
                            Text(reminder.title ?? "")
                                .font(.inter(size: 9.5))
                                .foregroundStyle(t.muted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if overflow > 0 {
                            Text("+\(overflow)")
                                .font(.inter(size: 9))
                                .foregroundStyle(t.muted2)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .helpyCard(
                t,
                fill: isHovering ? t.surfaceHover : t.surface,
                border: isHovering ? t.surfaceActiveBorder : t.line,
                cornerRadius: HelpyMetrics.rowCornerRadius
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aspectRatio(1, contentMode: .fit)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .contextMenu {
            Button("Choose Icon…") {
                ListIconPicker.present(for: list.calendarIdentifier, in: iconStore)
            }
            if iconStore.hasIcon(for: list.calendarIdentifier) {
                Button("Remove Icon") {
                    iconStore.removeIcon(for: list.calendarIdentifier)
                }
            }
        }
        .help(list.title)
    }
}

/// The trailing cell that makes a new list. Hidden entirely when no Reminders
/// source can hold one, rather than failing on click.
struct NewListCell: View {
    let onCreate: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isNaming = false
    @State private var draft = ""
    @State private var isHovering = false
    @FocusState private var isFieldFocused: Bool

    private var t: HelpyPalette { .forScheme(colorScheme) }

    var body: some View {
        Group {
            if isNaming {
                TextField("List name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.inter(size: 10, weight: .medium))
                    .foregroundStyle(t.ink)
                    .multilineTextAlignment(.center)
                    .focused($isFieldFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .padding(.horizontal, 8)
            } else {
                Button {
                    isNaming = true
                    isFieldFocused = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("New")
                            .font(.inter(size: 10, weight: .medium))
                    }
                    .foregroundStyle(t.muted2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                .fill(isHovering ? t.surfaceHover : t.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                .strokeBorder(t.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .aspectRatio(1, contentMode: .fit)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    private func commit() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        isNaming = false
        guard !name.isEmpty else { return }
        onCreate(name)
    }

    private func cancel() {
        draft = ""
        isNaming = false
    }
}
