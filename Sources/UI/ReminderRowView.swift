import SwiftUI
import EventKit
import AppKit

struct ReminderRowView: View, Equatable {
    let reminder: EKReminder
    var isDraggingAppWide: Bool = false
    var isBeingDragged: Bool = false
    
    @EnvironmentObject var remindersService: RemindersService
    @EnvironmentObject var timerService: TimerService
    @EnvironmentObject var estimateStore: EstimateStore
    @EnvironmentObject var subtaskStore: SubtaskStore

    @State private var isHovering = false
    @State private var showCalendarEdit = false
    @State private var showNotesEdit = false
    @State private var showSubtasksEdit = false
    @State private var showTimeEdit = false
    @State private var showEstimateEdit = false
    @State private var showMoreActions = false // New state for hover menu
    @State private var isCompleting = false
    @State private var isLeaving = false
    @State private var isStruck = false
    @State private var isTitleEditing = false
    @State private var titleDraft = ""
    @FocusState private var isTitleFieldFocused: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    private var t: HelpyPalette { .forScheme(colorScheme) }

    // Completing a task runs in three beats instead of one hard cut:
    //   0.00s  the check lands — circle fills, the checkmark pops
    //   0.12s  the title strikes through and greys
    //   0.34s  the row slides right and fades, heading for Completed
    //   0.56s  commit, animated, so the list closes the gap smoothly
    // The single hard step it replaced snapped the row to opacity 0 and let
    // the list jump, which is what read as janky.
    private let completionStrikeDelay: TimeInterval = 0.12
    private let completionCheckDelay: TimeInterval = 0.34
    private let completionCommitDelay: TimeInterval = 0.56
    private let completionAnimation = Animation.spring(response: 0.28, dampingFraction: 0.55)
    
    private var effectiveHover: Bool {
        return isHovering && !isDraggingAppWide
    }
    private var isShowingHoverActions: Bool {
        let isEditing = showEstimateEdit || showNotesEdit || showTimeEdit || showMoreActions || showCalendarEdit
        return !isTitleEditing && ((effectiveHover && !reminder.isCompleted) || isEditing)
    }
    private var rowFill: Color {
        if isCompleting { return t.success.opacity(0.12) }
        return effectiveHover ? t.surfaceHover : t.surface
    }
    private var rowBorder: Color {
        if isCompleting { return t.success.opacity(0.38) }
        return effectiveHover ? t.surfaceActiveBorder : t.line
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // Checkbox
                Button(action: {
                    guard !isCompleting else { return }
                    
                    if !reminder.isCompleted {
                        withAnimation(completionAnimation) {
                            isCompleting = true
                        }
                        NSSound(named: "Glass")?.play()

                        DispatchQueue.main.asyncAfter(deadline: .now() + completionStrikeDelay) {
                            withAnimation(.easeOut(duration: 0.18)) { isStruck = true }
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + completionCheckDelay) {
                            withAnimation(.easeIn(duration: 0.22)) { isLeaving = true }
                            
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + completionCommitDelay) {
                            // Animating the data change is what makes the rows
                            // below slide up instead of jumping.
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                                remindersService.toggleComplete(reminder)
                            }
                            // Only matters if the save failed and the row is
                            // still here — otherwise this view is already gone.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isCompleting = false
                                    isLeaving = false
                                    isStruck = false
                                }
                            }
                        }
                    } else {
                        remindersService.toggleComplete(reminder)
                    }
                }) {
                    ZStack {
                        let done = reminder.isCompleted || isCompleting
                        let tint = reminder.priority > 0 ? priorityColor(for: reminder.priority) : t.accent
                        Circle()
                            .fill(done ? tint : Color.clear)
                            .overlay(
                                Circle().strokeBorder(done ? tint : t.checkBorder, lineWidth: 1.5)
                            )
                            .frame(width: 16, height: 16)

                        if done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(t.onAccent)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        }

                    }
                    .frame(width: 18, height: 18) // Touch target
                    .scaleEffect(isCompleting ? 1.16 : 1.0)
                    .animation(.easeOut(duration: 0.16), value: reminder.isCompleted)
                    .animation(completionAnimation, value: isCompleting)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 2) {
                    if isTitleEditing {
                        TextField("Task title", text: $titleDraft)
                            .textFieldStyle(.plain)
                            .font(.inter(size: 13))
                            .foregroundStyle(t.ink)
                            .focused($isTitleFieldFocused)
                            .onSubmit { saveTitleEdit() }
                            .onExitCommand { cancelTitleEdit() }
                            // Clicking away used to leave the row as a field
                            // nobody was typing in. Commit instead.
                            .onChange(of: isTitleFieldFocused) { _, focused in
                                if !focused { saveTitleEdit() }
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(t.fieldFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(t.accent.opacity(0.8), lineWidth: 1.5)
                            )
                    } else {
                        Text(reminder.title)
                            .strikethrough(reminder.isCompleted || isStruck, color: t.muted2)
                            .foregroundStyle(reminder.isCompleted || isStruck ? t.muted : t.ink)
                            .lineLimit(2)
                            .font(.inter(size: 13, weight: .medium))
                            .onTapGesture(count: 2) {
                                beginTitleEditing()
                            }
                    }
                    
                    if let notes = reminder.notes, !notes.isEmpty {
                        Text(notes.components(separatedBy: .newlines).first ?? "")
                            .lineLimit(1)
                            .font(.inter(size: 11))
                            .foregroundStyle(t.muted)
                    }
                }
                .layoutPriority(1)
                
                Spacer()
                
                // Normal State (Meta) - Always present in layout
                HStack(spacing: 8) {
                    // Subtask progress chip (app-only checklist)
                    let subtaskProgress = subtaskStore.progress(for: reminder.calendarItemIdentifier)
                    if subtaskProgress.total > 0 {
                        Button(action: { withAnimation { showSubtasksEdit.toggle() } }) {
                            let allDone = subtaskProgress.done == subtaskProgress.total
                            HStack(spacing: 3) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("\(subtaskProgress.done)/\(subtaskProgress.total)")
                                    .font(.inter(size: 11, weight: .semibold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                            .foregroundStyle(allDone ? t.success : t.chipText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(allDone ? t.success.opacity(0.12) : t.chipFill)
                            )
                            // Never let width pressure compress the chip: without this,
                            // a long title squeezed it until "1/1" wrapped one glyph per
                            // line, rendering as scattered strokes beside the icon.
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .help("Subtasks")
                    }

                    if let dueMsg = formatDueTime(reminder.dueDateComponents) {
                        let overdue = isOverdue(reminder.dueDateComponents)
                        Text(dueMsg)
                            .font(.inter(size: 11, weight: .medium))
                            .foregroundStyle(overdue ? t.chipHotText : t.chipText)
                            .fixedSize()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(overdue ? t.chipHotFill : t.chipFill))
                    }
                    
                    if let _ = reminder.recurrenceRules?.first {
                        Image(systemName: "repeat")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(t.muted2)
                    }
                    
                    // No priority flag here on purpose: the leading colour bar
                    // already carries priority, and EventKit exposes no separate
                    // "flagged" field for reminders, so a flag icon would only
                    // repeat the bar.
                }
                // The hover-actions overlay fades in over the row, so bright meta
                // content — like a green subtask chip — used to bleed through
                // beneath the buttons. Hide meta while the actions are up.
                .opacity(isShowingHoverActions ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: isShowingHoverActions)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(alignment: .trailing) {
                if isShowingHoverActions {
                    HStack(spacing: 0) {
                        // Left fade area to reveal underlying content.
                        Color.clear
                        .frame(width: 40) // Reduced width slightly for sharper transition
                        .frame(maxHeight: .infinity)
                        
                        HStack(spacing: 2) {
                            // Play
                            PillControlButton(icon: "play.fill", help: "Start Timer", tone: .go, palette: t) {
                                let duration = estimateStore.getMetadata(for: reminder.calendarItemIdentifier)?.estimatedDuration ?? 0
                                timerService.startTimer(reminderId: reminder.calendarItemIdentifier, duration: duration)
                                // Play hands the session straight to the focus
                                // surface. Starting a timer and then having to
                                // press a second button to see it was the odd
                                // step, and on the board there was nothing to
                                // look at at all.
                                timerService.isFocusMode = true
                            }
                            
                            // Time/Est Group
                            TaskStatsView(
                                estimates: estimateStore.getEstimates(for: reminder.calendarItemIdentifier),
                                showTimeEdit: $showTimeEdit,
                                showEstimateEdit: $showEstimateEdit,
                                reminder: reminder
                            )
                            
                            // Notes
                            PillControlButton(
                                icon: (reminder.notes?.isEmpty ?? true) ? "doc" : "doc.text.fill",
                                help: "Notes",
                                isActive: !(reminder.notes?.isEmpty ?? true),
                                palette: t
                            ) {
                                withAnimation { showNotesEdit.toggle() }
                            }

                            // Subtasks (app-only checklist, never synced to Reminders)
                            PillControlButton(
                                icon: subtaskStore.hasSubtasks(for: reminder.calendarItemIdentifier) ? "checklist.checked" : "checklist",
                                help: "Subtasks",
                                isActive: subtaskStore.hasSubtasks(for: reminder.calendarItemIdentifier),
                                palette: t
                            ) {
                                withAnimation { showSubtasksEdit.toggle() }
                            }

                            // --- 3 DOTS MENU ---
                            // rotationEffect rotates rendering only, not the layout
                            // frame, so the icon needs a real square around it —
                            // PillControlButton supplies one.
                            PillControlButton(icon: "ellipsis", help: "More", palette: t) {
                                showMoreActions.toggle()
                            }
                            .popover(isPresented: $showMoreActions, arrowEdge: .bottom) {
                                VStack(alignment: .leading, spacing: 6) {
                                    // Schedule Option
                                    Button(action: {
                                        showMoreActions = false
                                        withAnimation { showCalendarEdit = true }
                                    }) {
                                        HStack {
                                            Image(systemName: "calendar")
                                            Text("Schedule")
                                        }
                                        .font(.inter(size: 13, weight: .medium))
                                        .foregroundStyle(t.ink)
                                        .padding(4)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Rectangle().fill(t.line).frame(height: 1)

                                    // Priority Option (Sub-menu simulation)
                                    Text("Priority")
                                        .font(.inter(size: 10, weight: .semibold))
                                        .textCase(.uppercase)
                                        .tracking(1.0)
                                        .foregroundStyle(t.muted2)
                                        .padding(.leading, 4)
                                    
                                    HStack(spacing: 8) {
                                        Button(action: { remindersService.updatePriority(reminder, priority: 0) }) {
                                            Image(systemName: "flag.slash")
                                        }
                                        .help("None")
                                        
                                        Button(action: { remindersService.updatePriority(reminder, priority: 9) }) { // Low
                                            Text("!")
                                                .font(.inter(size: 13, weight: .bold))
                                                .foregroundStyle(t.accent)
                                        }
                                        .help("Low")

                                        Button(action: { remindersService.updatePriority(reminder, priority: 5) }) { // Med
                                            Text("!!")
                                                .font(.inter(size: 13, weight: .bold))
                                                .foregroundStyle(t.warm)
                                        }
                                        .help("Medium")

                                        Button(action: { remindersService.updatePriority(reminder, priority: 1) }) { // High
                                            Text("!!!")
                                                .font(.inter(size: 13, weight: .bold))
                                                .foregroundStyle(t.hot)
                                        }
                                        .help("High")
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 4)

                                    Rectangle().fill(t.line).frame(height: 1)

                                    // Delete lives here (not in the hover row) to save space.
                                    Button(action: {
                                        showMoreActions = false
                                        remindersService.deleteReminder(reminder)
                                    }) {
                                        HStack {
                                            Image(systemName: "trash")
                                            Text("Delete")
                                        }
                                        .font(.inter(size: 13, weight: .medium))
                                        .foregroundStyle(t.hot)
                                        .padding(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(10)
                                .frame(width: 150)
                                .background(t.surface)
                            }
                        }
                        .padding(.trailing, 16)
                        .frame(maxHeight: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                    // Opaque row colour, not a blur: the surface underneath is a
                    // flat fill now, so a plain fill hides the meta row cleanly
                    // and costs nothing to composite.
                    .background(rowFill)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white.opacity(0.9), location: 0.12),
                                .init(color: .white, location: 0.2),
                                .init(color: .white, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            
            // Embedded Editors... (Keep existing code)
            
            if showCalendarEdit {
                Rectangle().fill(t.line).frame(height: 1)
                // Labels sit above their fields rather than beside them. Inline
                // labels plus two fixed-size date fields need more width than a
                // board column has, and SwiftUI pays for the overflow by
                // crushing whatever is flexible — which turned "Date" into a
                // vertical stack of single letters and squeezed the task title
                // in the row above down to nothing.
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .bottom, spacing: 10) {
                        scheduleField("Date") {
                            DatePicker("", selection: Binding(
                                get: { reminder.dueDateComponents?.date ?? Date() },
                                set: { remindersService.updateDueDate(reminder, date: $0) }
                            ), displayedComponents: [.date])
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .fixedSize()
                        }

                        scheduleField("Time") {
                            DatePicker("", selection: Binding(
                                get: { reminder.dueDateComponents?.date ?? Date() },
                                set: { remindersService.updateDueDate(reminder, date: $0) }
                            ), displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .fixedSize()
                        }

                        Spacer(minLength: 0)
                    }

                    scheduleField("Repeat") {
                        Menu {
                            Button("Never") { remindersService.updateRecurrence(reminder, frequency: nil) }
                            Divider()
                            Button("Daily") { remindersService.updateRecurrence(reminder, frequency: .daily) }
                            Button("Weekly") { remindersService.updateRecurrence(reminder, frequency: .weekly) }
                            Button("Monthly") { remindersService.updateRecurrence(reminder, frequency: .monthly) }
                            Button("Yearly") { remindersService.updateRecurrence(reminder, frequency: .yearly) }
                        } label: {
                            Text(formatRecurrence(reminder.recurrenceRules?.first))
                        }
                        .menuStyle(.borderedButton)
                        .fixedSize()
                    }

                    HStack(spacing: 8) {
                        Button("Clear") {
                             remindersService.updateDueDate(reminder, date: nil)
                             remindersService.updateRecurrence(reminder, frequency: nil)
                             withAnimation { showCalendarEdit = false }
                        }
                        .buttonStyle(HelpyQuietButtonStyle(palette: t))

                        Spacer(minLength: 0)

                        Button("Done") {
                             withAnimation { showCalendarEdit = false }
                        }
                        .buttonStyle(HelpySecondaryButtonStyle(palette: t))
                    }
                    .padding(.top, 1)
                }
                .padding(14)
                .background(t.fieldFill)
            }

            if showNotesEdit {
                Rectangle().fill(t.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: Binding(
                        get: { reminder.notes ?? "" },
                        set: { remindersService.updateNotes(reminder, newNotes: $0) }
                    ))
                    .font(.inter(size: 13))
                    .foregroundStyle(t.ink)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 80)
                }
                .padding(12)
                .background(t.fieldFill)
            }

            if showSubtasksEdit {
                Rectangle().fill(t.line).frame(height: 1)
                SubtaskChecklist(taskId: reminder.calendarItemIdentifier)
                    .padding(12)
                    .background(t.fieldFill)
            }
        }
        // Flat surface, no shadow: depth in this design comes from the border
        // and the hover fill, not from a drop shadow under every row.
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                .fill(rowFill)
        )
        // A priority task earns a 3pt colour bar on the leading edge — the one
        // place colour enters the list. It is an inset capsule, not a
        // full-bleed rectangle: a square-cornered bar overlaid on the rounded
        // card poked out past the corner curve and read as a broken sliver.
        .overlay(alignment: .leading) {
            if reminder.priority > 0 && !reminder.isCompleted {
                Capsule(style: .continuous)
                    .fill(priorityColor(for: reminder.priority))
                    .frame(width: 3)
                    .padding(.vertical, 9)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .animation(.easeOut(duration: 0.16), value: effectiveHover)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hover
            }
        }
        // Out to the right, towards where the Completed column is.
        .offset(x: isLeaving ? 44 : 0)
        .scaleEffect(isLeaving ? 0.97 : 1.0)
        .onChange(of: isTitleEditing) { _, editing in
            if editing {
                DispatchQueue.main.async {
                    isTitleFieldFocused = true
                }
            }
        }
        .opacity(isLeaving ? 0.0 : 1.0)
        // The card being dragged stays where it was as a faint placeholder
        // rather than vanishing: the column keeps its shape, so the slots do
        // not jump around under the cursor mid-drag.
        .opacity(isBeingDragged ? 0.32 : 1.0)
        .saturation(isBeingDragged ? 0.2 : 1.0)
        .animation(.easeOut(duration: 0.14), value: isBeingDragged)
        .animation(.easeOut(duration: 0.2), value: isCompleting)
    }
    
    /// A small caps label sitting above its control. Every field in the
    /// schedule editor is built this way so the block keeps one rhythm and
    /// stays narrow enough for a board column.
    @ViewBuilder
    private func scheduleField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.inter(size: 9, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(t.muted2)
            content()
        }
    }

    private func beginTitleEditing() {
        guard !reminder.isCompleted else { return }
        titleDraft = reminder.title
        withAnimation {
            isTitleEditing = true
        }
    }
    
    private func saveTitleEdit() {
        guard isTitleEditing else { return }
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation {
            isTitleEditing = false
        }
        guard !trimmed.isEmpty else { return }
        remindersService.updateTitle(reminder, newTitle: trimmed)
    }
    
    private func cancelTitleEdit() {
        titleDraft = reminder.title
        withAnimation {
            isTitleEditing = false
        }
    }
    
    func formatTimeDisplay(spent: TimeInterval, est: TimeInterval) -> String {
        let spentStr = spent > 0 ? formatCompact(spent) : "0m"
        let estStr = est > 0 ? formatCompact(est) : "0m" // Default if unset? Or just "Est"
        // If nothing set, show "Set Est"
        if spent == 0 && est == 0 { return "0m / 0m" } // Placeholder
        return "\(spentStr) / \(estStr)"
    }
    
    func formatCompact(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let h = m / 60
        if h > 0 {
             let remM = m % 60
             return remM > 0 ? "\(h)h \(remM)m" : "\(h)h"
        }
        return "\(m)m"
    }

    func formatDueTime(_ components: DateComponents?) -> String? {
        guard
            let components,
            components.hour != nil,
            components.minute != nil,
            let date = Calendar.current.date(from: components)
        else { return nil }
        return CachedFormatters.shortTime.string(from: date)
    }
    
    func isOverdue(_ components: DateComponents?) -> Bool {
        guard let date = components?.date else { return false }
        return date < Date()
    }
    
    func addEstimate(_ seconds: TimeInterval) {
        let current = estimateStore.getMetadata(for: reminder.calendarItemIdentifier)?.estimatedDuration ?? 0
        estimateStore.updateEstimate(for: reminder.calendarItemIdentifier, duration: current + seconds)
    }
    
    func setEstimate(_ seconds: TimeInterval) {
        estimateStore.updateEstimate(for: reminder.calendarItemIdentifier, duration: seconds)
    }
    
    func addTime(_ seconds: TimeInterval) {
        let current = estimateStore.getMetadata(for: reminder.calendarItemIdentifier)?.timeSpent ?? 0
        // Ensure non-negative
        let newTime = max(0, current + seconds)
        estimateStore.setTimeSpent(for: reminder.calendarItemIdentifier, seconds: newTime)
    }
    
    func setTime(_ seconds: TimeInterval) {
        estimateStore.setTimeSpent(for: reminder.calendarItemIdentifier, seconds: seconds)
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds == 0 { return "Set Est." }
        let m = Int(seconds) / 60
        let h = m / 60
        
        if h > 0 {
            let remM = m % 60
            return remM > 0 ? "\(h)h \(remM)m" : "\(h)h"
        } else {
            // Less than 1 hour
            if m > 0 {
                return "\(m)m"
            } else {
                // Less than 1 minute (show seconds)
                return "\(Int(seconds))s"
            }
            }
        }

    
    func prioritySymbol(for priority: Int) -> String {
        switch priority {
        case 1...4: return "!!!"
        case 5: return "!!"
        case 6...9: return "!"
        default: return ""
        }
    }
    
    func priorityColor(for priority: Int) -> Color {
        switch priority {
        case 1...4: return t.hot
        case 5: return t.warm
        case 6...9: return t.accent
        default: return t.muted2
        }
    }
    
    func formatRecurrence(_ rule: EKRecurrenceRule?) -> String {
        guard let rule = rule else { return "Never" }
        switch rule.frequency {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        @unknown default: return "Custom"
        }
    }
    
    static func == (lhs: ReminderRowView, rhs: ReminderRowView) -> Bool {
        return lhs.reminder.calendarItemIdentifier == rhs.reminder.calendarItemIdentifier &&
               lhs.reminder.isCompleted == rhs.reminder.isCompleted &&
               lhs.reminder.title == rhs.reminder.title &&
               lhs.reminder.notes == rhs.reminder.notes &&
               lhs.reminder.priority == rhs.reminder.priority &&
               lhs.reminder.dueDateComponents == rhs.reminder.dueDateComponents &&
               lhs.isDraggingAppWide == rhs.isDraggingAppWide &&
               lhs.isBeingDragged == rhs.isBeingDragged
    }
}

// MARK: - Subviews

struct TaskStatsView: View {
    @ObservedObject var estimates: EstimateStore.TaskEstimates
    @Binding var showTimeEdit: Bool
    @Binding var showEstimateEdit: Bool
    
    // We pass the popover content builders or just bind the state?
    // The popovers are presented by the PARENT view (ReminderRowView) usually, or we can move them here.
    // If we move popovers here, we need the reminder object.
    let reminder: EKReminder

    @Environment(\.colorScheme) private var colorScheme
    private var t: HelpyPalette { .forScheme(colorScheme) }

    var body: some View {
        HStack(spacing: 4) {
            // Time Spent Button
            Button(action: { showTimeEdit.toggle() }) {
                let spentText = estimates.timeSpent > 0 ? formatCompact(estimates.timeSpent) : "0m"
                Text(spentText)
                    .font(.inter(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(t.ink2)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showTimeEdit) {
                TimeSpentPopover(reminder: reminder, estimates: estimates)
            }
            
            // Divider /
            Text("/")
                .font(.inter(size: 11))
                .foregroundStyle(t.muted2)
                .fixedSize()
            
            // Estimate Button
            Button(action: { showEstimateEdit.toggle() }) {
                let estText = estimates.estimatedDuration > 0 ? formatCompact(estimates.estimatedDuration) : "0m"
                Text(estText)
                    .font(.inter(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(t.muted)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showEstimateEdit) {
                EstimatePopover(reminder: reminder, estimates: estimates)
            }
        }
    }
    
    func formatCompact(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let h = m / 60
        if h > 0 {
             let remM = m % 60
             return remM > 0 ? "\(h)h \(remM)m" : "\(h)h"
        }
        return "\(m)m"
    }
}

// Subview for Estimate Popover
struct EstimatePopover: View {
    let reminder: EKReminder
    @ObservedObject var estimates: EstimateStore.TaskEstimates
    @EnvironmentObject var estimateStore: EstimateStore

    @State private var textInput: String = ""

    var body: some View {
        VStack(spacing: 8) {
            Text("Set Estimate")
                .font(.inter(size: 13, weight: .semibold))

            TextField("HH:MM", text: $textInput)
                .frame(width: 80)
                .font(.inter(size: 13))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .onSubmit { parseAndUpdate(textInput) }
        }
        .padding()
        .onAppear {
            let total = estimates.estimatedDuration
            if total > 0 {
                let h = Int(total) / 3600
                let m = (Int(total) % 3600) / 60
                textInput = String(format: "%02d:%02d", h, m)
            }
        }
        .onDisappear { parseAndUpdate(textInput) }
    }

    private func parseAndUpdate(_ input: String) {
        let cleaned = input.filter { "0123456789:".contains($0) }
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":").map { String($0) }
            if parts.count == 2 {
                let h = Int(parts[0]) ?? 0
                let m = Int(parts[1]) ?? 0
                estimateStore.updateEstimate(for: reminder.calendarItemIdentifier,
                                             duration: TimeInterval(h * 3600 + m * 60))
            }
        } else {
            let digits = cleaned.filter { $0.isNumber }
            if digits.count >= 3 {
                let h = Int(String(digits.dropLast(2))) ?? 0
                let m = Int(String(digits.suffix(2))) ?? 0
                estimateStore.updateEstimate(for: reminder.calendarItemIdentifier,
                                             duration: TimeInterval(h * 3600 + m * 60))
            } else if !digits.isEmpty {
                let m = Int(digits) ?? 0
                estimateStore.updateEstimate(for: reminder.calendarItemIdentifier,
                                             duration: TimeInterval(m * 60))
            }
        }
    }
}

// Subview for Time Spent Popover
struct TimeSpentPopover: View {
    let reminder: EKReminder
    @ObservedObject var estimates: EstimateStore.TaskEstimates
    @EnvironmentObject var estimateStore: EstimateStore

    @State private var textInput: String = ""

    var body: some View {
        VStack(spacing: 8) {
            Text("Set Time Spent")
                .font(.inter(size: 13, weight: .semibold))

            TextField("HH:MM", text: $textInput)
                .frame(width: 80)
                .font(.inter(size: 13))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .onSubmit { parseAndUpdate(textInput) }
        }
        .padding()
        .onAppear {
            let total = estimates.timeSpent
            if total > 0 {
                let h = Int(total) / 3600
                let m = (Int(total) % 3600) / 60
                textInput = String(format: "%02d:%02d", h, m)
            }
        }
        .onDisappear { parseAndUpdate(textInput) }
    }

    private func parseAndUpdate(_ input: String) {
        let cleaned = input.filter { "0123456789:".contains($0) }
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":").map { String($0) }
            if parts.count == 2 {
                let h = Int(parts[0]) ?? 0
                let m = Int(parts[1]) ?? 0
                estimateStore.setTimeSpent(for: reminder.calendarItemIdentifier,
                                           seconds: TimeInterval(h * 3600 + m * 60))
            }
        } else {
            let digits = cleaned.filter { $0.isNumber }
            if digits.count >= 3 {
                let h = Int(String(digits.dropLast(2))) ?? 0
                let m = Int(String(digits.suffix(2))) ?? 0
                estimateStore.setTimeSpent(for: reminder.calendarItemIdentifier,
                                           seconds: TimeInterval(h * 3600 + m * 60))
            } else if !digits.isEmpty {
                let m = Int(digits) ?? 0
                estimateStore.setTimeSpent(for: reminder.calendarItemIdentifier,
                                           seconds: TimeInterval(m * 60))
            }
        }
    }
}

struct TextFieldSpacer: View {
    var body: some View {
        Spacer().frame(width: 12)
    }
}

// MARK: - Performance Optimization
// Cached formatters to avoid expensive initialization during view updates
private struct CachedFormatters {
    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}
