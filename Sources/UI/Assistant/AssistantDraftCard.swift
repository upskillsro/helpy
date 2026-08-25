import SwiftUI

struct AssistantDraftCard: View {
    let action: AssistantActionDraft
    let onChange: (AssistantActionDraft) -> Void
    let onApply: (AssistantActionDraft) -> Void
    let onDiscard: () -> Void

    @State private var localAction: AssistantActionDraft
    @State private var showDatePopover = false
    @State private var showTimePopover = false
    @State private var showPriorityPopover = false
    @Environment(\.colorScheme) private var colorScheme

    init(action: AssistantActionDraft, onChange: @escaping (AssistantActionDraft) -> Void, onApply: @escaping (AssistantActionDraft) -> Void, onDiscard: @escaping () -> Void) {
        self.action = action
        self.onChange = onChange
        self.onApply = onApply
        self.onDiscard = onDiscard
        _localAction = State(initialValue: action)
    }

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var isEditableAction: Bool { localAction.kind == .create || localAction.kind == .update }
    private var hasDate: Bool { localAction.schedule?.hasDate ?? false }
    private var hasTime: Bool { localAction.schedule?.hasTime ?? false }
    private var currentPriority: Int { localAction.priority ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditableAction {
                editableContent
            } else if localAction.kind == .reorder {
                reorderContent
            } else if localAction.kind == .complete {
                completionContent
            } else {
                staticSummaryContent
            }

            footerRow
        }
        .padding(12)
        .helpyCard(t, fill: t.surface, border: t.line, cornerRadius: HelpyMetrics.rowCornerRadius)
        .onChange(of: action) { _, newAction in
            localAction = newAction
        }
    }

    private var editableContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if localAction.kind == .update, let target = localAction.targetReminderTitle, !target.isEmpty {
                Text(target)
                    .font(.inter(size: 11))
                    .foregroundColor(t.muted)
                    .lineLimit(1)
            }

            TextField("Task title", text: Binding(
                get: { localAction.title ?? "" },
                set: { value in
                    localAction.title = value
                    onChange(localAction)
                }
            ))
            .textFieldStyle(.plain)
            .font(.inter(size: 13, weight: .medium))
            .foregroundColor(t.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .helpyCard(t, fill: t.fieldFill, border: t.fieldBorder, cornerRadius: 10)

            HStack(spacing: 8) {
                dateButton
                timeButton
                priorityButton

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let date = localAction.schedule?.date {
                            metaPill(systemImage: "calendar", text: compactDate(date))
                        }
                        if let time = localAction.schedule?.time, let compactTime = compactTime(time) {
                            metaPill(systemImage: "clock", text: compactTime)
                        }
                        if currentPriority != 0 {
                            metaPill(systemImage: "flag.fill", text: priorityTitle(currentPriority), tint: priorityColor(currentPriority))
                        }
                    }
                    .padding(.trailing, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(t.fieldFill)
            )
        }
    }

    private var dateButton: some View {
        iconButton(systemImage: "calendar") {
            showDatePopover.toggle()
        }
        .popover(isPresented: $showDatePopover, arrowEdge: .bottom) {
            assistantPopover {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Date")
                        .font(.inter(size: 13, weight: .semibold))

                    DatePicker(
                        "",
                        selection: Binding(
                            get: { localAction.schedule?.date ?? Calendar.current.startOfDay(for: Date()) },
                            set: { newDate in
                                let existingTime = localAction.schedule?.time
                                localAction.schedule = AssistantScheduleDraft(date: newDate, time: existingTime)
                                onChange(localAction)
                            }
                        ),
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)

                    HStack {
                        Button("Clear") {
                            localAction.schedule = .empty
                            onChange(localAction)
                        }
                        .buttonStyle(HelpySecondaryButtonStyle(palette: t))

                        Spacer()

                        Button("Done") {
                            showDatePopover = false
                        }
                        .buttonStyle(HelpyPrimaryButtonStyle(palette: t))
                    }
                }
            }
        }
    }

    private var timeButton: some View {
        iconButton(systemImage: "clock") {
            if !hasDate {
                localAction.schedule = AssistantScheduleDraft(date: Calendar.current.startOfDay(for: Date()), time: localAction.schedule?.time)
                onChange(localAction)
            }
            showTimePopover.toggle()
        }
        .popover(isPresented: $showTimePopover, arrowEdge: .bottom) {
            assistantPopover {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Time")
                        .font(.inter(size: 13, weight: .semibold))

                    DatePicker(
                        "",
                        selection: Binding(
                            get: { resolvedPopoverTimeDate() },
                            set: { newValue in
                                let time = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                let existingDate = localAction.schedule?.date ?? Calendar.current.startOfDay(for: Date())
                                localAction.schedule = AssistantScheduleDraft(date: existingDate, time: time)
                                onChange(localAction)
                            }
                        ),
                        displayedComponents: [.hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)

                    HStack {
                        Button("Clear") {
                            let existingDate = localAction.schedule?.date
                            localAction.schedule = existingDate.map { AssistantScheduleDraft(date: $0, time: nil) } ?? .empty
                            onChange(localAction)
                        }
                        .buttonStyle(HelpySecondaryButtonStyle(palette: t))

                        Spacer()

                        Button("Done") {
                            showTimePopover = false
                        }
                        .buttonStyle(HelpyPrimaryButtonStyle(palette: t))
                    }
                }
            }
        }
    }

    private var priorityButton: some View {
        iconButton(systemImage: "flag") {
            showPriorityPopover.toggle()
        }
        .popover(isPresented: $showPriorityPopover, arrowEdge: .bottom) {
            assistantPopover {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Priority")
                        .font(.inter(size: 13, weight: .semibold))

                    ReminderPriorityChips(
                        selectedPriority: Binding(
                            get: { currentPriority },
                            set: { newValue in
                                localAction.priority = newValue == 0 ? nil : newValue
                                onChange(localAction)
                            }
                        )
                    )

                    HStack {
                        Spacer()
                        Button("Done") {
                            showPriorityPopover = false
                        }
                        .buttonStyle(HelpyPrimaryButtonStyle(palette: t))
                    }
                }
            }
        }
    }

    private var reorderContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localAction.targetReminderTitle ?? localAction.displayTitle)
                .font(.inter(size: 13, weight: .medium))
                .foregroundColor(t.ink)

            Stepper(value: Binding(
                get: { max(localAction.newPosition ?? 1, 1) },
                set: { value in
                    localAction.newPosition = max(value, 1)
                    onChange(localAction)
                }
            ), in: 1...999) {
                Text("Move to position \(localAction.newPosition ?? 1)")
                    .font(.inter(size: 11))
                    .foregroundColor(t.muted)
            }
        }
    }

    private var completionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localAction.targetReminderTitle ?? localAction.displayTitle)
                .font(.inter(size: 13, weight: .medium))
                .foregroundColor(t.ink)

            Toggle(isOn: Binding(
                get: { localAction.completed ?? true },
                set: { value in
                    localAction.completed = value
                    onChange(localAction)
                }
            )) {
                Text((localAction.completed ?? true) ? "Mark complete" : "Mark incomplete")
                    .font(.inter(size: 11))
                    .foregroundColor(t.muted)
            }
            .toggleStyle(.switch)
        }
    }

    private var staticSummaryContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localAction.targetReminderTitle ?? localAction.displayTitle)
                .font(.inter(size: 13, weight: .medium))
                .foregroundColor(t.ink)
            Text(localAction.summaryText)
                .font(.inter(size: 11))
                .foregroundColor(t.muted)
        }
    }

    private var footerRow: some View {
        HStack {
            Button("Discard", action: onDiscard)
                .buttonStyle(HelpyQuietButtonStyle(palette: t))

            Spacer()

            Button(buttonTitle(for: localAction.kind)) {
                onApply(localAction)
            }
            .buttonStyle(HelpyPrimaryButtonStyle(palette: t))
        }
    }

    private func iconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(t.controlIcon)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(t.fieldFill)
                )
        }
        .buttonStyle(.plain)
    }

    private func assistantPopover<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(width: 250)
    }

    private func metaPill(systemImage: String, text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.inter(size: 10.5, weight: .medium))
        .foregroundColor(tint ?? t.chipText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.map { $0.opacity(0.16) } ?? t.chipFill))
    }

    private func resolvedPopoverTimeDate() -> Date {
        let baseDate = localAction.schedule?.date ?? Calendar.current.startOfDay(for: Date())
        var components = Calendar.current.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = localAction.schedule?.time?.hour ?? Calendar.current.component(.hour, from: Date())
        components.minute = localAction.schedule?.time?.minute ?? Calendar.current.component(.minute, from: Date())
        return Calendar.current.date(from: components) ?? Date()
    }

    private func compactDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func compactTime(_ time: DateComponents) -> String? {
        var components = DateComponents()
        components.year = 2000
        components.month = 1
        components.day = 1
        components.hour = time.hour
        components.minute = time.minute
        guard let date = Calendar.current.date(from: components) else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func priorityTitle(_ priority: Int) -> String {
        switch priority {
        case 1...4: return "High"
        case 5: return "Medium"
        case 6...9: return "Low"
        default: return "None"
        }
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 1...4: return t.hot
        case 5: return t.warm
        case 6...9: return t.accent
        default: return t.muted
        }
    }

    private func buttonTitle(for kind: AssistantActionKind) -> String {
        switch kind {
        case .create: return "Create"
        case .update: return "Apply"
        case .delete: return "Delete"
        case .complete: return "Apply"
        case .reorder: return "Move"
        }
    }
}
