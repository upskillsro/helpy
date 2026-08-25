import SwiftUI

/// The side panel for one week: the goal, the scored tasks, and the reward.
struct WeekDetailPanel: View {
    let week: PlanWeek
    let onClose: () -> Void

    @EnvironmentObject var planStore: WeeklyPlanStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var goalDraft = ""
    @State private var rewardDraft = ""
    @State private var targetDraft = ""
    @State private var newTaskTitle = ""
    @State private var newTaskPoints = "1"
    @FocusState private var isNewTaskFocused: Bool

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var plan: WeeklyPlan { planStore.plan(for: week.id) }

    private static let range: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field(
                        "Goal",
                        placeholder: "What is this week for?",
                        text: $goalDraft,
                        commit: { planStore.setGoal(goalDraft, for: week.id) }
                    )

                    tasksSection

                    rewardSection
                }
                .padding(16)
            }
        }
        .frame(width: 300)
        .background(t.panelFill)
        .overlay(alignment: .leading) {
            Rectangle().fill(t.line).frame(width: 1)
        }
        .onAppear(perform: loadDrafts)
        .onChange(of: week.id) { _, _ in loadDrafts() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Self.range.string(from: week.start)) – \(Self.range.string(from: week.lastDay))")
                        .font(.inter(size: 14, weight: .bold))
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

            HStack(spacing: 8) {
                Text("\(plan.earnedPoints)/\(max(plan.pointsTarget, plan.availablePoints)) pts")
                    .font(.inter(size: 11, weight: .semibold))
                    .foregroundStyle(t.onAccent)
                Spacer()
                HStack(spacing: 4) {
                    Text("Target")
                        .font(.inter(size: 10))
                        .foregroundStyle(t.onAccent.opacity(0.8))
                    TextField("0", text: $targetDraft)
                        .textFieldStyle(.plain)
                        .font(.inter(size: 11, weight: .semibold))
                        .foregroundStyle(t.onAccent)
                        .multilineTextAlignment(.center)
                        .frame(width: 34)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                        )
                        .onSubmit { commitTarget() }
                        .onChange(of: targetDraft) { _, _ in commitTarget() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(HelpyHeaderBackground(palette: t).ignoresSafeArea(edges: .top))
    }

    // MARK: - Sections

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Tasks")

            if plan.tasks.isEmpty {
                Text("Nothing scored yet.")
                    .font(.inter(size: 11))
                    .foregroundStyle(t.muted2)
            }

            ForEach(plan.tasks) { task in
                WeekTaskRow(
                    task: task,
                    palette: t,
                    onToggle: { planStore.toggleTask(id: task.id, in: week.id) },
                    onDelete: { planStore.deleteTask(id: task.id, in: week.id) }
                )
            }

            HStack(spacing: 6) {
                TextField("Add a task…", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.inter(size: 11))
                    .foregroundStyle(t.ink)
                    .focused($isNewTaskFocused)
                    .onSubmit(addTask)

                TextField("1", text: $newTaskPoints)
                    .textFieldStyle(.plain)
                    .font(.inter(size: 11, weight: .semibold))
                    .foregroundStyle(t.muted)
                    .multilineTextAlignment(.center)
                    .frame(width: 26)
                    .onSubmit(addTask)

                Text("pts")
                    .font(.inter(size: 9))
                    .foregroundStyle(t.muted2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                    .fill(t.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                    .stroke(t.fieldBorder, lineWidth: 1)
            )
        }
    }

    private var rewardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            field(
                "Reward",
                placeholder: "What do you get?",
                text: $rewardDraft,
                commit: { planStore.setReward(rewardDraft, for: week.id) }
            )

            if plan.isRewardEarned && !plan.reward.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                    Text("Earned")
                        .font(.inter(size: 11, weight: .semibold))
                }
                .foregroundStyle(t.success)
            } else if plan.pointsTarget > 0 {
                Text("\(max(0, plan.pointsTarget - plan.earnedPoints)) points to go")
                    .font(.inter(size: 10))
                    .foregroundStyle(t.muted2)
            }
        }
    }

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

    // MARK: - Actions

    private func loadDrafts() {
        let current = plan
        goalDraft = current.goal
        rewardDraft = current.reward
        targetDraft = current.pointsTarget > 0 ? String(current.pointsTarget) : ""
    }

    private func commitTarget() {
        planStore.setPointsTarget(Int(targetDraft) ?? 0, for: week.id)
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        planStore.addTask(title: title, points: Int(newTaskPoints) ?? 1, to: week.id)
        newTaskTitle = ""
        newTaskPoints = "1"
        isNewTaskFocused = true
    }
}

private struct WeekTaskRow: View {
    let task: WeeklyPlanTask
    let palette: HelpyPalette
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
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

            Text(task.title)
                .font(.inter(size: 11.5))
                .foregroundStyle(task.isDone ? palette.muted2 : palette.ink)
                .strikethrough(task.isDone, color: palette.muted2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
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

            Text("\(task.points)")
                .font(.inter(size: 10, weight: .semibold))
                .foregroundStyle(palette.chipText)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(palette.chipFill))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                .fill(isHovering ? palette.surfaceHover : palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}
