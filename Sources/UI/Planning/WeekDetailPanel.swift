import EventKit
import SwiftUI

/// The side panel for one week: the goal, the scored tasks, the list it mirrors
/// into, and the reward.
///
/// Every task write goes through `WeeklyPlanSync` rather than the store, so a
/// week linked to a Reminders list stays in step with it. Nothing here knows
/// how that mirroring works.
struct WeekDetailPanel: View {
    let week: PlanWeek
    let onClose: () -> Void

    @EnvironmentObject var planStore: WeeklyPlanStore
    @EnvironmentObject var remindersService: RemindersService
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("planningDefaultListId") private var defaultListId = ""

    @State private var goalDraft = ""
    @State private var rewardDraft = ""
    @State private var notesDraft = ""
    @State private var isPickingList = false

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var plan: WeeklyPlan { planStore.plan(for: week.id) }

    private var sync: WeeklyPlanSync {
        WeeklyPlanSync(
            store: planStore,
            reminders: remindersService,
            defaultListId: defaultListId.isEmpty ? nil : defaultListId
        )
    }

    private var linkedList: EKCalendar? { sync.linkedList(for: week) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field(
                        "Goal",
                        placeholder: "What is this week for?",
                        text: $goalDraft,
                        commit: { planStore.setGoal(goalDraft, for: week.id) }
                    )

                    syncRow
                    tasksSection
                    notesSection
                    rewardSection
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 320)
        .background(t.panelFill)
        .overlay(alignment: .leading) {
            Rectangle().fill(t.line).frame(width: 1)
        }
        .onAppear {
            loadDrafts()
            sync.refreshFromReminders(for: week)
        }
        .onChange(of: week.id) { _, _ in
            loadDrafts()
            sync.refreshFromReminders(for: week)
        }
        // Ticking a mirrored task on the board takes it out of the incomplete
        // set, so this catches the change without polling.
        .onChange(of: remindersService.remindersByList.mapValues(\.count)) { _, _ in
            sync.refreshFromReminders(for: week)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(week.rangeLabel)
                        .font(.inter(size: 15, weight: .bold))
                        .foregroundStyle(t.onAccent)
                    Text(week.isCurrent ? "This week" : "Week \(week.id)")
                        .font(.inter(size: 10))
                        .foregroundStyle(t.onAccent.opacity(0.8))
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(t.onAccent)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                headerRing

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(plan.earnedPoints)/\(plan.availablePoints) pts")
                        .font(.inter(size: 17, weight: .bold))
                        .foregroundStyle(t.onAccent)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.18), value: plan.earnedPoints)
                    Text(statusLine)
                        .font(.inter(size: 10.5))
                        .foregroundStyle(t.onAccent.opacity(0.85))
                }

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(HelpyHeaderBackground(palette: t).ignoresSafeArea(edges: .top))
    }

    /// The header sits on the accent, so the ring is drawn in white here rather
    /// than reusing `WeekProgressRing`'s on-canvas colours.
    private var headerRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, plan.progress))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.28), value: plan.progress)
            if plan.isRewardEarned {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(t.onAccent)
            } else {
                Text("\(Int(plan.progress * 100))")
                    .font(.inter(size: 12, weight: .bold))
                    .foregroundStyle(t.onAccent)
                    .monospacedDigit()
            }
        }
        .frame(width: 44, height: 44)
    }

    /// The target is the board, so this counts tasks rather than repeating the
    /// number already shown above it.
    private var statusLine: String {
        if plan.tasks.isEmpty { return "Add tasks to set the target" }
        if plan.isRewardEarned { return "Every task done" }
        let left = plan.tasks.count - plan.doneCount
        return "\(plan.doneCount) of \(plan.tasks.count) done · \(left) left"
    }

    // MARK: - Sync

    private var syncRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Syncs with")

            // A Button and a popover rather than a Menu: macOS draws a
            // borderless Menu as a pop-up button and throws the custom label
            // away, which left this control as a bare chevron with no way to
            // see which list the week was pointed at.
            Button { isPickingList = true } label: {
                HStack(spacing: 8) {
                    if let linkedList {
                        ListIconSquare(
                            listId: linkedList.calendarIdentifier,
                            title: linkedList.title,
                            color: linkedList.helpyColor,
                            side: 16,
                            cornerRadius: 4
                        )
                        Text(linkedList.title)
                            .font(.inter(size: 11.5, weight: .medium))
                            .foregroundStyle(t.ink)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 11))
                            .foregroundStyle(t.muted2)
                        Text("Not synced")
                            .font(.inter(size: 11.5))
                            .foregroundStyle(t.muted2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(t.muted2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                        .fill(t.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                        .stroke(t.fieldBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPickingList, arrowEdge: .bottom) { listChooser }

            if linkedList != nil {
                Text("New tasks also land in that list, due this week.")
                    .font(.inter(size: 9.5))
                    .foregroundStyle(t.muted2)
            }
        }
    }

    private var listChooser: some View {
        VStack(alignment: .leading, spacing: 2) {
            chooserRow(title: "Don\u{2019}t sync", list: nil, isPicked: linkedList == nil)

            if !remindersService.lists.isEmpty {
                Divider().padding(.vertical, 3)
                ForEach(remindersService.lists, id: \.calendarIdentifier) { list in
                    chooserRow(
                        title: list.title,
                        list: list,
                        isPicked: linkedList?.calendarIdentifier == list.calendarIdentifier
                    )
                }
            }
        }
        .padding(6)
        .frame(width: 240)
    }

    private func chooserRow(title: String, list: EKCalendar?, isPicked: Bool) -> some View {
        Button {
            setLinkedList(list?.calendarIdentifier)
            isPickingList = false
        } label: {
            HStack(spacing: 8) {
                if let list {
                    ListIconSquare(
                        listId: list.calendarIdentifier,
                        title: list.title,
                        color: list.helpyColor,
                        side: 16,
                        cornerRadius: 4
                    )
                } else {
                    Image(systemName: "link.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(t.muted2)
                        .frame(width: 16, height: 16)
                }
                Text(title)
                    .font(.inter(size: 12))
                    .foregroundStyle(t.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if isPicked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(t.rail)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setLinkedList(_ listId: String?) {
        sync.setLinkedList(listId, for: week)
        // The last list you picked becomes the default for weeks you have not
        // pointed anywhere yet — that is the "by default" part. Switching this
        // week off leaves the default alone; it is a decision about one week.
        if let listId { defaultListId = listId }
    }

    // MARK: - Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Tasks")
                Spacer()
                if !plan.tasks.isEmpty {
                    Text("\(plan.doneCount)/\(plan.tasks.count)")
                        .font(.inter(size: 9.5, weight: .semibold))
                        .foregroundStyle(t.muted2)
                        .monospacedDigit()
                }
            }

            if plan.tasks.isEmpty {
                Text("Nothing scored yet. Add what would make this week a win.")
                    .font(.inter(size: 11))
                    .foregroundStyle(t.muted2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(plan.tasks) { task in
                WeekTaskRow(
                    task: task,
                    palette: t,
                    onToggle: { sync.toggle(task, in: week) },
                    onDelete: { sync.delete(task, in: week) },
                    onRename: { sync.rename(task, to: $0, in: week) },
                    onPoints: { sync.setPoints($0, for: task, in: week) }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            WeekTaskComposer(palette: t) { title, points in
                withAnimation(.easeOut(duration: 0.16)) {
                    sync.addTask(title: title, points: points, to: week)
                }
            }
        }
        .animation(.easeOut(duration: 0.16), value: plan.tasks.count)
    }

    // MARK: - Notes

    /// Free text for the week, and the one place in the panel where Return is a
    /// line break rather than a commit — see `HelpyTextView`.
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Notes")

            HelpyNotesField(
                placeholder: "Anything worth remembering about this week\u{2026}",
                text: $notesDraft,
                font: .inter(size: 12),
                textColor: t.ink,
                placeholderColor: t.placeholder,
                lineSpacing: 2,
                minHeight: 52
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                    .fill(t.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                    .stroke(t.fieldBorder, lineWidth: 1)
            )
            .onChange(of: notesDraft) { _, new in planStore.setNotes(new, for: week.id) }
        }
    }

    // MARK: - Reward

    private var rewardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            field(
                "Reward",
                placeholder: "What do you get?",
                text: $rewardDraft,
                commit: { planStore.setReward(rewardDraft, for: week.id) }
            )

            if plan.isRewardEarned && !plan.reward.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                    Text("Earned — go collect it.")
                        .font(.inter(size: 11, weight: .semibold))
                }
                .foregroundStyle(t.success)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                        .fill(t.success.opacity(0.12))
                )
                .transition(.opacity)
            } else if plan.availablePoints > 0 {
                Text("\(plan.availablePoints - plan.earnedPoints) points to go")
                    .font(.inter(size: 10))
                    .foregroundStyle(t.muted2)
            }
        }
        .animation(.easeOut(duration: 0.2), value: plan.isRewardEarned)
    }

    // MARK: - Building blocks

    private func field(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        commit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.inter(size: 12))
                .foregroundStyle(t.ink)
                .lineLimit(1...4)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                        .fill(t.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                        .stroke(t.fieldBorder, lineWidth: 1)
                )
                .onSubmit(commit)
                .onChange(of: text.wrappedValue) { _, _ in commit() }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.inter(size: 9, weight: .bold))
            .kerning(0.9)
            .foregroundStyle(t.muted2)
    }

    private func loadDrafts() {
        let current = plan
        goalDraft = current.goal
        rewardDraft = current.reward
        notesDraft = current.notes
    }
}

// MARK: - Task row

/// One scored task. Points are edited in place with the stepper that appears on
/// hover, and the title with a double-click — a task you cannot correct after
/// adding it is a task you have to delete and retype.
///
/// The title is one line, and the hover controls are drawn as an overlay on top
/// of the row rather than as siblings of the title — the same arrangement
/// `ReminderRowView` uses on the board. Laying them out inline stole width from
/// the title, so pointing at a row was enough to make it re-wrap and grow.
private struct WeekTaskRow: View {
    let task: WeeklyPlanTask
    let palette: HelpyPalette
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void
    let onPoints: (Int) -> Void

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool

    private static let maxPoints = 99

    private var showsActions: Bool { isHovering && !isEditing }

    private var rowFill: Color { isHovering ? palette.surfaceHover : palette.surface }

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(task.isDone ? palette.success : palette.checkBorder, lineWidth: 1.5)
                        .frame(width: 15, height: 15)
                    if task.isDone {
                        Circle().fill(palette.success).frame(width: 15, height: 15)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)

            if isEditing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.inter(size: 11.5))
                    .foregroundStyle(palette.ink)
                    .focused($isFieldFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { isEditing = false }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(task.title)
                    .font(.inter(size: 11.5))
                    .foregroundStyle(task.isDone ? palette.muted2 : palette.ink)
                    .strikethrough(task.isDone, color: palette.muted2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .help(task.title)
                    .onTapGesture(count: 2) {
                        draft = task.title
                        isEditing = true
                        isFieldFocused = true
                    }
            }

            // Resting state. Hidden rather than removed while the actions are
            // up, so the title keeps exactly the width it had.
            HStack(spacing: 6) {
                if task.reminderId != nil {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8.5))
                        .foregroundStyle(palette.muted2)
                        .help("Mirrored into the linked list")
                }
                pointsChip
            }
            .fixedSize()
            .opacity(showsActions ? 0 : 1)
            .animation(.easeInOut(duration: 0.14), value: showsActions)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .trailing) {
            if showsActions { actions }
        }
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                .fill(rowFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    private var pointsChip: some View {
        Text("\(task.points)")
            .font(.inter(size: 10, weight: .semibold))
            .foregroundStyle(palette.chipText)
            .monospacedDigit()
            .frame(minWidth: 12)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(palette.chipFill))
    }

    /// The hover controls, painted over the row on an opaque fill that fades in
    /// from the left so a long title runs under them instead of into them.
    private var actions: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 26)

            HStack(spacing: 3) {
                stepper("minus", enabled: task.points > 0) {
                    onPoints(task.points - 1)
                }

                pointsChip

                stepper("plus", enabled: task.points < Self.maxPoints) {
                    onPoints(task.points + 1)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.dangerHoverIcon)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(palette.dangerHoverFill)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 8)
        }
        .frame(maxHeight: .infinity)
        .background(rowFill)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .white.opacity(0.9), location: 0.14),
                    .init(color: .white, location: 0.24),
                    .init(color: .white, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func stepper(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(enabled ? palette.controlIcon : palette.muted2)
                .frame(width: 16, height: 16)
                .background(Circle().fill(palette.controlHoverFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func commitRename() {
        isEditing = false
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        onRename(trimmed)
    }
}

// MARK: - Composer

/// Add-a-task, with its points. Collapsed it is a single line; the points row
/// only appears once you are actually writing something, so the common case
/// stays one field and one Return.
private struct WeekTaskComposer: View {
    let palette: HelpyPalette
    let onAdd: (String, Int) -> Void

    @State private var title = ""
    @State private var points = 1
    @State private var isFocused = false
    @FocusState private var fieldFocused: Bool

    private var isOpen: Bool { isFocused || !title.isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.muted2)
                TextField("Add a task…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.inter(size: 11.5))
                    .foregroundStyle(palette.ink)
                    .focused($fieldFocused)
                    .onSubmit(commit)
            }

            if isOpen {
                HStack(spacing: 8) {
                    Text("Worth")
                        .font(.inter(size: 10))
                        .foregroundStyle(palette.muted2)

                    HStack(spacing: 4) {
                        pointsButton("minus", enabled: points > 0) { points -= 1 }
                        Text("\(points)")
                            .font(.inter(size: 11, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .monospacedDigit()
                            .frame(minWidth: 14)
                        pointsButton("plus", enabled: points < 99) { points += 1 }
                    }

                    Text("pts")
                        .font(.inter(size: 10))
                        .foregroundStyle(palette.muted2)

                    Spacer()

                    Button("Add", action: commit)
                        .buttonStyle(HelpyPrimaryButtonStyle(palette: palette, cornerRadius: 8))
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                .fill(palette.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                .stroke(isOpen ? palette.rail.opacity(0.6) : palette.fieldBorder, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.14), value: isOpen)
        .onChange(of: fieldFocused) { _, focused in isFocused = focused }
    }

    private func pointsButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(enabled ? palette.controlIcon : palette.muted2)
                .frame(width: 17, height: 17)
                .background(Circle().fill(palette.controlHoverFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func commit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed, points)
        title = ""
        points = 1
        fieldFocused = true
    }
}
