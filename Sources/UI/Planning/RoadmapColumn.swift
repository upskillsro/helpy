import SwiftUI

/// The roadmap: the one goal everything else is in service of, the thinking
/// behind it, and a two-level checklist of milestones and their steps.
///
/// It sits to the left of the weeks rather than inside a week on purpose. A
/// week is a slice of time; this is the thing the slices add up to, and it has
/// to stay visible while you plan them.
struct RoadmapColumn: View {
    @EnvironmentObject var roadmapStore: RoadmapStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var goalDraft = ""
    @State private var notesDraft = ""
    @State private var milestoneDraft = ""
    @State private var collapsed: Set<UUID> = []
    @State private var addingStepTo: UUID?
    @State private var stepDraft = ""
    @State private var editingId: UUID?
    @State private var titleDraft = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case milestone
        case step(UUID)
        case title(UUID)
    }

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var roadmap: Roadmap { roadmapStore.roadmap }

    static let width: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    goalField
                    notesField
                    checklist
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: Self.width)
        .background(t.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(t.line).frame(width: 1)
        }
        .onAppear {
            goalDraft = roadmap.goal
            notesDraft = roadmap.notes
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("ROADMAP")
                    .font(.inter(size: 9, weight: .bold))
                    .kerning(1.1)
                    .foregroundStyle(t.muted2)

                Spacer(minLength: 0)

                if !roadmap.milestones.isEmpty {
                    Text("\(roadmap.doneMilestones)/\(roadmap.milestones.count)")
                        .font(.inter(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(t.chipText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(t.chipFill))
                }
            }

            if !roadmap.milestones.isEmpty {
                WeekProgressBar(progress: roadmap.progress, palette: t, height: 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Goal and notes

    // Both are `HelpyTextView`, not `TextField(axis: .vertical)`: on macOS a
    // vertical text field still commits on Return, so there was no way to break
    // either of these into lines.
    private var goalField: some View {
        HelpyNotesField(
            placeholder: "The big goal",
            text: $goalDraft,
            font: .inter(size: 21, weight: .bold),
            textColor: t.ink,
            placeholderColor: t.placeholder,
            lineSpacing: 1
        )
        // Committing on every keystroke would rewrite the store per letter;
        // committing only on submit would lose the text when focus moves.
        .onChange(of: goalDraft) { _, new in roadmapStore.setGoal(new) }
    }

    private var notesField: some View {
        HelpyNotesField(
            placeholder: "What it looks like when this is done\u{2026}",
            text: $notesDraft,
            font: .inter(size: 12),
            textColor: t.ink2,
            placeholderColor: t.placeholder,
            lineSpacing: 2
        )
        .onChange(of: notesDraft) { _, new in roadmapStore.setNotes(new) }
    }

    // MARK: - Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(t.line).frame(height: 1)

            ForEach(roadmap.milestones) { milestone in
                milestoneBlock(milestone)
            }

            addMilestoneRow
        }
    }

    private func milestoneBlock(_ milestone: RoadmapMilestone) -> some View {
        let isOpen = !collapsed.contains(milestone.id)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        if isOpen { collapsed.insert(milestone.id) } else { collapsed.remove(milestone.id) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(t.muted2)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                RoadmapCheckbox(isOn: milestone.isComplete, side: 15, palette: t) {
                    roadmapStore.toggleMilestone(milestone.id)
                }

                editableTitle(
                    milestone.title,
                    id: milestone.id,
                    font: .inter(size: 13, weight: .semibold),
                    color: milestone.isComplete ? t.muted : t.ink,
                    struck: milestone.isComplete
                ) { roadmapStore.renameMilestone(milestone.id, to: $0) }

                Spacer(minLength: 4)

                if !milestone.tasks.isEmpty {
                    Text("\(milestone.doneCount)/\(milestone.tasks.count)")
                        .font(.inter(size: 9.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(t.muted2)
                        .fixedSize()
                }

                Menu {
                    Button("Add step") { beginStep(on: milestone.id) }
                    Button("Rename") { beginTitleEdit(milestone.id, milestone.title) }
                    Divider()
                    Button("Delete milestone", role: .destructive) {
                        roadmapStore.deleteMilestone(milestone.id)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(t.muted2)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(milestone.tasks) { task in
                        stepRow(task, in: milestone)
                    }

                    if addingStepTo == milestone.id {
                        stepComposer(for: milestone.id)
                    } else {
                        Button { beginStep(on: milestone.id) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Step")
                                    .font(.inter(size: 12))
                            }
                            .foregroundStyle(t.muted2)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 26)
            }
        }
        .padding(.vertical, 3)
    }

    private func stepRow(_ task: RoadmapTask, in milestone: RoadmapMilestone) -> some View {
        HStack(spacing: 8) {
            RoadmapCheckbox(isOn: task.isDone, side: 14, palette: t) {
                roadmapStore.toggleTask(task.id, in: milestone.id)
            }

            editableTitle(
                task.title,
                id: task.id,
                font: .inter(size: 12.5),
                color: task.isDone ? t.muted : t.ink2,
                struck: task.isDone
            ) { roadmapStore.renameTask(task.id, in: milestone.id, to: $0) }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename") { beginTitleEdit(task.id, task.title) }
            Button("Delete step", role: .destructive) {
                roadmapStore.deleteTask(task.id, in: milestone.id)
            }
        }
    }

    // MARK: - Editing

    /// A milestone or step title that turns into a field on a double click.
    ///
    /// It commits when it loses focus as well as on Return: clicking away from
    /// a rename you have already typed and finding the old title back is the
    /// worse of the two surprises. Escape still cancels.
    @ViewBuilder
    private func editableTitle(
        _ title: String,
        id: UUID,
        font: Font,
        color: Color,
        struck: Bool,
        rename: @escaping (String) -> Void
    ) -> some View {
        if editingId == id {
            TextField("Title", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(t.ink)
                .focused($focus, equals: .title(id))
                .onSubmit { commitTitleEdit(rename) }
                .onExitCommand { endTitleEdit() }
                .onChange(of: focus) { _, new in
                    if new != .title(id) { commitTitleEdit(rename) }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(t.accent.opacity(0.8), lineWidth: 1.5)
                )
        } else {
            Text(title)
                .font(font)
                .foregroundStyle(color)
                .strikethrough(struck, color: t.muted2)
                .lineLimit(2)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { beginTitleEdit(id, title) }
                .help("Double-click to rename")
        }
    }

    private func beginTitleEdit(_ id: UUID, _ title: String) {
        titleDraft = title
        editingId = id
        // One turn later: the field has to exist before it can take focus.
        DispatchQueue.main.async { focus = .title(id) }
    }

    private func commitTitleEdit(_ rename: (String) -> Void) {
        guard editingId != nil else { return }
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        endTitleEdit()
        guard !trimmed.isEmpty else { return }
        rename(trimmed)
    }

    private func endTitleEdit() {
        editingId = nil
        if case .title = focus { focus = nil }
    }

    // MARK: - Composers

    private func stepComposer(for milestoneId: UUID) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(t.muted2)

            TextField("New step", text: $stepDraft)
                .textFieldStyle(.plain)
                .font(.inter(size: 12.5))
                .foregroundStyle(t.ink)
                .focused($focus, equals: .step(milestoneId))
                .onSubmit { commitStep(to: milestoneId) }
                .onExitCommand { endStep() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.fieldFill)
        )
    }

    private var addMilestoneRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(t.muted2)

            TextField("Add a milestone", text: $milestoneDraft)
                .textFieldStyle(.plain)
                .font(.inter(size: 12, weight: .medium))
                .foregroundStyle(t.ink)
                .focused($focus, equals: .milestone)
                .onSubmit {
                    if roadmapStore.addMilestone(title: milestoneDraft) != nil { milestoneDraft = "" }
                    focus = .milestone
                }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(t.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .padding(.top, 2)
    }

    private func beginStep(on milestoneId: UUID) {
        collapsed.remove(milestoneId)
        stepDraft = ""
        addingStepTo = milestoneId
        focus = .step(milestoneId)
    }

    /// Stays open after each step so a milestone can be filled in one go.
    private func commitStep(to milestoneId: UUID) {
        guard roadmapStore.addTask(title: stepDraft, to: milestoneId) != nil else {
            endStep()
            return
        }
        stepDraft = ""
        focus = .step(milestoneId)
    }

    private func endStep() {
        addingStepTo = nil
        stepDraft = ""
        focus = nil
    }
}

/// A checkbox that is only ever a checkbox: no drag, no hover actions, no
/// second meaning. Used at both levels of the roadmap, at two sizes.
struct RoadmapCheckbox: View {
    let isOn: Bool
    let side: CGFloat
    let palette: HelpyPalette
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack {
                Circle()
                    .strokeBorder(isOn ? palette.success : palette.checkBorder, lineWidth: 1.5)
                    .frame(width: side, height: side)

                if isOn {
                    Circle()
                        .fill(palette.success)
                        .frame(width: side, height: side)
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.52, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side + 2, height: side + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.24, dampingFraction: 0.62), value: isOn)
    }
}
