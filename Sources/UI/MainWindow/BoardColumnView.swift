import EventKit
import SwiftUI
import UniformTypeIdentifiers

/// One column of a list board.
///
/// Cards are `ReminderRowView` — the same component the side strip uses — so the
/// two can never drift into looking like different apps.
///
/// Between every pair of cards sits a drop slot. That is what makes reordering
/// possible: a column-wide drop target can only answer "which column", and the
/// question a drag actually asks is "which column, and where in it".
struct BoardColumnView: View {
    let bucket: TaskBucket
    let reminders: [EKReminder]
    let isDraggingAppWide: Bool
    let draggedId: String?
    /// The card's identifier and the slot it was dropped on.
    let onDrop: (String, Int) -> Void
    let onAdd: (String) -> Void
    /// Only Today carries it.
    let onFocus: (() -> Void)?
    let onDragStart: (String) -> Void

    @EnvironmentObject var estimateStore: EstimateStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var isTargeted = false

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var isToday: Bool { bucket == .today }
    private var isDone: Bool { bucket.isDoneColumn }

    private var estimateSummary: String? {
        guard !isDone else { return nil }
        let seconds = reminders.reduce(0.0) { total, reminder in
            total + (estimateStore.getMetadata(for: reminder.calendarItemIdentifier)?.estimatedDuration ?? 0)
        }
        guard seconds > 0 else { return nil }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(reminders.enumerated()), id: \.element.calendarItemIdentifier) { index, reminder in
                        dropSlot(index)
                        ReminderRowView(
                            reminder: reminder,
                            isDraggingAppWide: isDraggingAppWide,
                            isBeingDragged: draggedId == reminder.calendarItemIdentifier
                        )
                        .onDrag {
                            onDragStart(reminder.calendarItemIdentifier)
                            return NSItemProvider(object: reminder.calendarItemIdentifier as NSString)
                        } preview: {
                            // Without an explicit preview macOS drags the raw
                            // string payload, so the thing under the cursor is
                            // a UUID rather than the task you grabbed.
                            BoardDragPreview(title: reminder.title, palette: t)
                        }
                    }
                    dropSlot(reminders.count)
                }
                .padding(.horizontal, 9)
                .padding(.top, 2)
                // The column closes ranks behind a card that leaves and opens
                // for one that arrives, instead of snapping to the new order.
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.82),
                    value: reminders.map(\.calendarItemIdentifier)
                )
            }
            .scrollBounceBehavior(.basedOnSize)

            if isDone && reminders.isEmpty {
                emptyDoneState
            }

            if !isDone { addRow }

            if let onFocus {
                Button(action: onFocus) {
                    HStack(spacing: 6) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Focus Today")
                            .font(.inter(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(t.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                            .fill(t.rail)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
                .padding(.bottom, 9)
                .disabled(reminders.isEmpty)
                .opacity(reminders.isEmpty ? 0.45 : 1)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                .fill(columnFill)
        )
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                .fill(t.rail.opacity(isTargeted ? 0.06 : 0))
        )
        .animation(.easeOut(duration: 0.14), value: isTargeted)
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                .stroke(
                    isTargeted ? t.rail : (isToday ? t.surfaceActiveBorder : t.line),
                    lineWidth: isTargeted ? 2 : 1
                )
        )
        // The column-wide target is the fallback for the empty space under the
        // cards; the slots handle everything between them.
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            accept(providers, at: reminders.count)
        }
    }

    private func dropSlot(_ index: Int) -> some View {
        BoardDropSlot(
            isArmed: isDraggingAppWide,
            palette: t,
            onDrop: { identifier in onDrop(identifier, index) }
        )
    }

    private var emptyDoneState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(t.muted2)
            Text("Nothing finished yet")
                .font(.inter(size: 10.5))
                .foregroundStyle(t.muted2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(bucket.title.uppercased())
                .font(.inter(size: 9, weight: .bold))
                .kerning(0.9)
                .foregroundStyle(t.muted2)
            Spacer()
            Text(countLabel)
                .font(.inter(size: 9))
                .foregroundStyle(t.muted2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 8)
    }

    private var countLabel: String {
        guard let estimateSummary else { return "\(reminders.count)" }
        return "\(reminders.count) · \(estimateSummary)"
    }

    private var columnFill: Color {
        if isDone { return t.canvas }
        return isToday ? t.surfaceActive : t.surface
    }

    private var addRow: some View {
        BoardAddTaskField(palette: t, bucket: bucket, onAdd: onAdd)
            .padding(.horizontal, 9)
            .padding(.top, 6)
            .padding(.bottom, 9)
    }

    private func accept(_ providers: [NSItemProvider], at index: Int) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let identifier = object as? String else { return }
            Task { @MainActor in onDrop(identifier, index) }
        }
        return true
    }
}

/// The add-task control at the foot of a column.
///
/// Idle it is a quiet dashed row, so a column with nothing in it still shows
/// where tasks go. Clicking turns it into a real field that names the column it
/// is adding to and stays open for the next one — adding five things in a row
/// is the common case, not the exception.
private struct BoardAddTaskField: View {
    let palette: HelpyPalette
    let bucket: TaskBucket
    let onAdd: (String) -> Void

    @State private var title = ""
    @State private var isActive = false
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if isActive {
                editor
            } else {
                collapsed
            }
        }
        .animation(.easeOut(duration: 0.14), value: isActive)
    }

    private var collapsed: some View {
        Button {
            isActive = true
            isFocused = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Add task")
                    .font(.inter(size: 11, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovering ? palette.ink2 : palette.muted2)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                    .fill(isHovering ? palette.surfaceHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                    .strokeBorder(palette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    private var editor: some View {
        HStack(spacing: 7) {
            TextField("Add to \(bucket.title)…", text: $title)
                .textFieldStyle(.plain)
                .font(.inter(size: 11))
                .foregroundStyle(palette.ink)
                .focused($isFocused)
                .onSubmit(commit)
                .onExitCommand(perform: dismiss)

            Button(action: commit) {
                Image(systemName: "return")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(canSubmit ? palette.onAccent : palette.muted2)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(canSubmit ? palette.rail : palette.controlHoverFill)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                .fill(palette.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                .strokeBorder(palette.rail.opacity(0.65), lineWidth: 1.5)
        )
        // Clicking away from an empty field puts the quiet row back; a field
        // left with text in it stays, so nothing typed is thrown away.
        .onChange(of: isFocused) { _, focused in
            if !focused && !canSubmit { isActive = false }
        }
    }

    private func commit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = ""
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        isFocused = true
    }

    private func dismiss() {
        title = ""
        isActive = false
        isFocused = false
    }
}

/// The gap between two cards, as a drop target.
///
/// Two pixels tall at rest so the column looks normal, opening to a real target
/// only while something is actually being dragged. Showing permanent gaps would
/// make a still board look broken.
private struct BoardDropSlot: View {
    let isArmed: Bool
    let palette: HelpyPalette
    let onDrop: (String) -> Void

    @State private var isTargeted = false

    /// Three heights, in order of how much the slot is claiming: invisible,
    /// armed enough to be hittable, and opened to the size of the card that
    /// would land there.
    private var height: CGFloat {
        if isTargeted { return 38 }
        return isArmed ? 10 : 3
    }

    var body: some View {
        Color.clear
            .frame(height: height)
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                        .fill(palette.rail.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                                .strokeBorder(palette.rail.opacity(0.55),
                                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        )
                        .padding(.vertical, 2)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let identifier = object as? String else { return }
                    Task { @MainActor in onDrop(identifier) }
                }
                return true
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.8), value: height)
    }
}

/// What you actually see under the cursor mid-drag: the task, small.
private struct BoardDragPreview: View {
    let title: String
    let palette: HelpyPalette

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .strokeBorder(palette.checkBorder, lineWidth: 1.5)
                .frame(width: 13, height: 13)
            Text(title)
                .font(.inter(size: 12, weight: .medium))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: 230, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                .strokeBorder(palette.rail.opacity(0.7), lineWidth: 1.5)
        )
    }
}
