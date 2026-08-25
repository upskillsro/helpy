import SwiftUI

/// Compact subtask checklist embedded under a reminder row.
/// Subtasks are app-only (SubtaskStore / UserDefaults) — they are never
/// written to Apple Reminders.
struct SubtaskChecklist: View {
    let taskId: String

    @EnvironmentObject var subtaskStore: SubtaskStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var newTitle = ""
    @FocusState private var isInputFocused: Bool

    private var t: HelpyPalette { .forScheme(colorScheme) }

    var body: some View {
        let items = subtaskStore.subtasks(for: taskId)

        VStack(alignment: .leading, spacing: 8) {
            if !items.isEmpty {
                HStack(spacing: 6) {
                    Text("Subtasks")
                        .font(.inter(size: 10, weight: .semibold))
                        .foregroundStyle(t.muted2)
                        .textCase(.uppercase)
                        .tracking(1.0)

                    Text("\(items.filter(\.isCompleted).count)/\(items.count)")
                        .font(.inter(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(t.muted2)
                }

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(items) { item in
                        SubtaskChecklistRow(
                            item: item,
                            palette: t,
                            onToggle: { subtaskStore.toggleSubtask(id: item.id, for: taskId) },
                            onDelete: { subtaskStore.deleteSubtask(id: item.id, for: taskId) }
                        )
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(t.muted2)

                TextField("Add a step…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.inter(size: 12))
                    .foregroundStyle(t.ink)
                    .focused($isInputFocused)
                    .onSubmit(submit)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(t.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(t.fieldBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            )
        }
    }

    private func submit() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtaskStore.addSubtask(title: trimmed, for: taskId)
        newTitle = ""
        isInputFocused = true
    }
}

private struct SubtaskChecklistRow: View {
    let item: SubtaskItem
    let palette: HelpyPalette
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            item.isCompleted ? palette.accent : palette.checkBorder,
                            lineWidth: 1.5
                        )
                        .frame(width: 13, height: 13)
                    if item.isCompleted {
                        Circle().fill(palette.accent).frame(width: 13, height: 13)
                        Image(systemName: "checkmark")
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.16), value: item.isCompleted)

            Text(item.title)
                .font(.inter(size: 12))
                .foregroundStyle(item.isCompleted ? palette.muted2 : palette.ink2)
                .strikethrough(item.isCompleted)
                .lineLimit(2)

            Spacer(minLength: 6)

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(palette.muted2)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hover }
        }
    }
}
