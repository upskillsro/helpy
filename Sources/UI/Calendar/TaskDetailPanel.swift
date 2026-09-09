import SwiftUI

/// The panel that opens on the right when a block is clicked.
///
/// Everything here writes through to the same places the rest of the app reads
/// from — title and notes to the reminder, the time to its due date, the length
/// to `EstimateStore`, subtasks to `SubtaskStore` — so nothing in this panel is
/// calendar-only except the colour.
struct TaskDetailPanel: View {
    let item: ScheduledItem
    let listName: String
    let notes: String
    let palette: HelpyPalette
    let grid: CalendarGrid
    let week: CalendarWeek
    @ObservedObject var subtaskStore: SubtaskStore
    let onTitle: (String) -> Void
    let onNotes: (String) -> Void
    let onColor: (UInt32?) -> Void
    let onMove: (Int, Int) -> Void
    let onLength: (Int) -> Void
    let onComplete: () -> Void
    let onUnschedule: () -> Void
    let onClose: () -> Void

    @State private var title = ""
    @State private var noteText = ""
    @State private var newSubtask = ""
    @FocusState private var subtaskFocused: Bool

    private var t: HelpyPalette { palette }
    private let calendar = Calendar.current

    /// The lengths worth one click. Anything else is a drag on the block's
    /// bottom edge.
    private static let lengths = [15, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(t.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Colour") { colorRow }
                    section("When") { whenRows }
                    section("Notes") { notesField }
                    section("Subtasks") { subtasks }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            Rectangle().fill(t.line).frame(height: 1)
            footer
        }
        .frame(width: 296)
        .background(t.canvas)
        .task(id: item.id) { load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                TextField("Title", text: $title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.inter(size: 14, weight: .bold))
                    .foregroundStyle(t.ink)
                    .lineLimit(1...4)
                    .onSubmit(commitTitle)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(t.controlIcon)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(t.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Text(listName)
                .font(.inter(size: 10.5, weight: .semibold))
                .foregroundStyle(t.muted)
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 12)
        // Losing focus is the commit. There is no Save button anywhere else in
        // the app and this field should not be the first one.
        .onChange(of: title) { _, _ in commitTitle() }
    }

    // MARK: - Sections

    private func section<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.inter(size: 9.5, weight: .bold))
                .kerning(0.9)
                .foregroundStyle(t.muted2)
            content()
        }
    }

    private var colorRow: some View {
        HStack(spacing: 7) {
            swatch(hex: nil, fill: Color(hex: item.listColorHex), isOn: item.overrideColorHex == nil)
            ForEach(TaskColorStore.palette, id: \.self) { hex in
                swatch(hex: hex, fill: Color(hex: hex), isOn: item.overrideColorHex == hex)
            }
        }
    }

    /// The first swatch is the list's own colour and clears the override, which
    /// is why it is drawn hollow rather than as one more choice.
    private func swatch(hex: UInt32?, fill: Color, isOn: Bool) -> some View {
        Button { onColor(hex) } label: {
            Circle()
                .fill(hex == nil ? fill.opacity(0.18) : fill)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(fill.opacity(0.7), lineWidth: hex == nil ? 1.5 : 0))
                .overlay(
                    Circle()
                        .strokeBorder(t.ink, lineWidth: 1.5)
                        .padding(-3)
                        .opacity(isOn ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .help(hex == nil ? "Follow the list" : "")
    }

    private var whenRows: some View {
        VStack(alignment: .leading, spacing: 11) {
            dayStrip
            HStack(spacing: 8) {
                Text("Starts")
                    .font(.inter(size: 11.5))
                    .foregroundStyle(t.muted)
                startField
                Spacer(minLength: 0)
                Text("Takes")
                    .font(.inter(size: 11.5))
                    .foregroundStyle(t.muted)
                // The chips only cover the common lengths, so the real one is
                // spelled out here or a 3h 15m block would look unset.
                Text(CalendarFormat.duration(minutes: item.minutes))
                    .font(.inter(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(t.ink)
            }
            lengthChips
        }
    }

    /// The stepper field draws no box of its own, so it gets the same surface
    /// and border as the day pills or it reads as loose text on the panel.
    private var startField: some View {
        DatePicker("", selection: startBinding, displayedComponents: .hourAndMinute)
            .datePickerStyle(.stepperField)
            .labelsHidden()
            .font(.inter(size: 12, weight: .semibold))
            .fixedSize()
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(t.line, lineWidth: 1)
            )
    }

    /// The whole week as one row. Moving a block to Thursday is one click, and
    /// the strip doubles as a reminder of which day you are looking at.
    private var dayStrip: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                let day = week.days[index]
                let isOn = index == dayIndex
                Button {
                    onMove(index, CalendarGrid.minuteOfDay(item.start))
                } label: {
                    VStack(spacing: 1) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.inter(size: 8.5, weight: .bold))
                            .foregroundStyle(isOn ? t.onAccent.opacity(0.8) : t.muted2)
                        Text(day.formatted(.dateTime.day()))
                            .font(.inter(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(isOn ? t.onAccent : t.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isOn ? t.accent : t.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isOn ? .clear : t.line, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One click for the lengths a task actually gets given. The bottom edge of
    /// the block is still there for anything in between.
    private var lengthChips: some View {
        HStack(spacing: 5) {
            ForEach(Self.lengths, id: \.self) { minutes in
                let isOn = minutes == item.minutes
                Button { onLength(minutes) } label: {
                    Text(CalendarFormat.duration(minutes: minutes))
                        .font(.inter(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isOn ? t.onAccent : t.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isOn ? t.accent : t.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(isOn ? .clear : t.line, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The date part stays whatever day the block is on; only the clock moves.
    private var startBinding: Binding<Date> {
        Binding(
            get: { item.start },
            set: { onMove(dayIndex, CalendarGrid.minuteOfDay($0)) }
        )
    }

    private var notesField: some View {
        HelpyTextView(
            text: $noteText,
            font: NSFont.systemFont(ofSize: 12),
            textColor: t.ink,
            minHeight: 62
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(t.fieldBorder, lineWidth: 1)
        )
        .onChange(of: noteText) { _, value in onNotes(value) }
    }

    private var subtasks: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(subtaskStore.subtasks(for: item.id)) { sub in
                SubtaskPanelRow(
                    item: sub,
                    palette: t,
                    onToggle: { subtaskStore.toggleSubtask(id: sub.id, for: item.id) },
                    onDelete: { subtaskStore.deleteSubtask(id: sub.id, for: item.id) }
                )
            }
            SubtaskInputRow(
                title: $newSubtask,
                palette: t,
                cornerRadius: 10,
                isFocused: $subtaskFocused,
                onClose: { subtaskFocused = false },
                onSubmit: addSubtask
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            action(item.isDone ? "Not done" : "Mark done", icon: "checkmark", run: onComplete)
            action("Unschedule", icon: "arrow.uturn.left", run: onUnschedule)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func action(_ label: String, icon: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.inter(size: 11, weight: .semibold))
            }
            .foregroundStyle(t.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(t.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bits

    private var dayIndex: Int {
        week.days.firstIndex { calendar.isDate($0, inSameDayAs: item.start) } ?? 0
    }

    private func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month())
    }

    private func load() {
        title = item.title
        noteText = notes
        newSubtask = ""
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.title else { return }
        onTitle(trimmed)
    }

    private func addSubtask() {
        let trimmed = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtaskStore.addSubtask(title: trimmed, for: item.id)
        newSubtask = ""
        subtaskFocused = true
    }
}
