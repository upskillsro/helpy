import SwiftUI

struct SubtasksPanelView: View {
    let taskId: String
    let onClose: () -> Void

    @ObservedObject var subtaskStore: SubtaskStore
    @AppStorage("appTheme") private var appTheme: AppTheme = .glass
    @Environment(\.colorScheme) private var colorScheme

    @State private var newTitle = ""
    @FocusState private var isInputFocused: Bool

    private let panelCornerRadius: CGFloat = 18
    private let inputCornerRadius: CGFloat = 10

    private var subtasks: [SubtaskItem] {
        subtaskStore.subtasks(for: taskId)
    }

    private var isWhiteTheme: Bool { appTheme == .white }
    private var isDarkTheme: Bool { appTheme == .dark }

    private var labelColor: Color {
        if isWhiteTheme { return Color.black.opacity(0.45) }
        if isDarkTheme { return Color.white.opacity(0.4) }
        return .secondary
    }

    private var textColor: Color {
        isDarkTheme ? Color.white.opacity(0.85) : .primary
    }

    private var emptyStateColor: Color {
        if isDarkTheme { return Color.white.opacity(0.5) }
        return .secondary
    }

    private var inputFillColor: Color {
        if isWhiteTheme { return Color.black.opacity(0.06) }
        if isDarkTheme { return Color.white.opacity(0.08) }
        return Color.primary.opacity(0.06)  // glass: Color.primary adapts via glass-propagated colorScheme
    }

    private var inputStrokeColor: Color {
        if isWhiteTheme { return Color.black.opacity(0.08) }
        if isDarkTheme { return Color.white.opacity(0.14) }
        return Color.primary.opacity(0.1)  // glass: adaptive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subtasks")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(labelColor)
                .textCase(.uppercase)
                .tracking(0.5)

            if subtasks.isEmpty {
                Text("No subtasks yet")
                    .font(.system(size: 12))
                    .foregroundStyle(emptyStateColor)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(subtasks) { item in
                        SubtaskPanelRow(
                            item: item,
                            textColor: textColor,
                            completedColor: emptyStateColor,
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
                textColor: textColor,
                fillColor: inputFillColor,
                strokeColor: inputStrokeColor,
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
            if isWhiteTheme {
                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.95))
            } else if isDarkTheme {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
            }
        }
        .overlay {
            if appTheme != .glass {
                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .stroke(
                        isWhiteTheme ? Color.black.opacity(0.12) : Color.white.opacity(0.15),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
        }
        // clipShape confines the rendered surface to the rounded rect — same as the pill.
        // Without this, the NSHostingView's system-appearance background fills the rectangular
        // frame, which is what glassEffect samples instead of the real desktop pixels.
        // With the clip, all corners are transparent; the glass looks through to the desktop.
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        // Glass is applied from FloatingPillView (outside this struct), making
        // SubtasksPanelView a child of the glass so @Environment(\.colorScheme)
        // receives the glass-propagated value for correct text/color adaptation.
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
    let textColor: Color
    let completedColor: Color
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(item.isCompleted ? Color.green : Color.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 12))
                .foregroundStyle(item.isCompleted ? completedColor : textColor)
                .strikethrough(item.isCompleted)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.55))
            }
            .buttonStyle(.plain)
            .opacity(0.85)
        }
    }
}

private struct SubtaskInputRow: View {
    @Binding var title: String
    let textColor: Color
    let fillColor: Color
    let strokeColor: Color
    let cornerRadius: CGFloat
    @FocusState.Binding var isFocused: Bool
    let onClose: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.8))

            TextField("Add subtask…", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(textColor)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onClose)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}
