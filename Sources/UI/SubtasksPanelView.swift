import SwiftUI

struct SubtasksPanelView: View {
    let taskId: String
    let onClose: () -> Void

    @ObservedObject var subtaskStore: SubtaskStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var newTitle = ""
    @FocusState private var isInputFocused: Bool

    private let panelCornerRadius = HelpyMetrics.panelCornerRadius
    private let inputCornerRadius: CGFloat = 10

    private var t: HelpyPalette { .forScheme(colorScheme) }

    private var subtasks: [SubtaskItem] {
        subtaskStore.subtasks(for: taskId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subtasks")
                .font(.inter(size: 10, weight: .semibold))
                .foregroundStyle(t.muted2)
                .textCase(.uppercase)
                .tracking(1.0)

            if subtasks.isEmpty {
                Text("No subtasks yet")
                    .font(.inter(size: 12))
                    .foregroundStyle(t.muted)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(subtasks) { item in
                        SubtaskPanelRow(
                            item: item,
                            palette: t,
                            onToggle: {
                                subtaskStore.toggleSubtask(id: item.id, for: taskId)
                            },
                            onDelete: {
                                subtaskStore.deleteSubtask(id: item.id, for: taskId)
                            }
                        )
                    }
                }
            }

            SubtaskInputRow(
                title: $newTitle,
                palette: t,
                cornerRadius: inputCornerRadius,
                isFocused: $isInputFocused,
                onClose: onClose,
                onSubmit: submitSubtask
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 268)
        .background {
            // Plain fill, not a behind-window VisualEffectView: its backdrop
            // is a window-server rectangle that ignores clipShape and goes
            // stale when the pill window auto-resizes (visible gray rect).
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(t.panelFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .strokeBorder(t.panelBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        // Focus is claimed the moment the panel opens so the first click that
        // makes the pill window key also lands the caret in the field. (The
        // window only accepts keystrokes at all because of
        // makePillWindowKeyable in FloatingPillView.)
        .onAppear { isInputFocused = true }
    }

    private func submitSubtask() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtaskStore.addSubtask(title: trimmed, for: taskId)
        newTitle = ""
        isInputFocused = true
    }
}

private struct SubtaskPanelRow: View {
    let item: SubtaskItem
    let palette: HelpyPalette
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(item.isCompleted ? palette.accent : palette.checkBorder, lineWidth: 1.5)
                        .background(Circle().fill(item.isCompleted ? palette.accent : .clear))
                        .frame(width: 14, height: 14)

                    if item.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(palette.onAccent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.16), value: item.isCompleted)

            Text(item.title)
                .font(.inter(size: 12))
                .foregroundStyle(item.isCompleted ? palette.muted : palette.ink2)
                .strikethrough(item.isCompleted)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.muted2)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SubtaskInputRow: View {
    @Binding var title: String
    let palette: HelpyPalette
    let cornerRadius: CGFloat
    @FocusState.Binding var isFocused: Bool
    let onClose: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.muted2)

            TextField("Add subtask…", text: $title)
                .textFieldStyle(.plain)
                .font(.inter(size: 12))
                .foregroundStyle(palette.ink)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onClose)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.fieldFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(palette.fieldBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}
