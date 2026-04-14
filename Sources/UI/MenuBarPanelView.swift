import SwiftUI
import EventKit

/// Panel shown when the user left-clicks the Helpy menu bar icon.
/// Displays the current timer, task info, and focus controls.
struct MenuBarPanelView: View {
    @ObservedObject var timerService: TimerService
    @ObservedObject var remindersService: RemindersService
    @ObservedObject var subtaskStore: SubtaskStore
    let onClose: () -> Void

    @AppStorage("appTheme") private var appTheme: AppTheme = .glass
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSubtasks = false
    @State private var newSubtaskTitle = ""
    @FocusState private var isSubtaskInputFocused: Bool

    private var activeTask: EKReminder? {
        guard let id = timerService.activeReminderId else { return nil }
        return remindersService.reminders.first { $0.calendarItemIdentifier == id }
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider().background(dividerColor).padding(.horizontal, 12)
            controlsRow

            if showSubtasks, let id = timerService.activeReminderId {
                Divider().background(dividerColor).padding(.horizontal, 12)
                subtasksList(for: id)
            }
        }
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(MenuBarGlassModifier(appTheme: appTheme))
        .preferredColorScheme(appTheme == .white ? .light : appTheme == .glass ? nil : .dark)
    }

    // MARK: - Header: task name + timer

    private var headerRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if timerService.isOnBreak {
                    Text("Break")
                        .font(.headline)
                        .foregroundStyle(.primary)
                } else if let task = activeTask {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                } else {
                    Text("No Active Task")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            PillTimerDisplay(ticker: timerService.ticker, service: timerService)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Controls row

    private var controlsRow: some View {
        HStack(spacing: 6) {
            // Exit Focus
            menuBarButton(icon: "xmark.circle.fill", color: .red, help: "Exit Focus") {
                timerService.isFocusMode = false
                onClose()
            }

            // Pause / Resume
            menuBarButton(
                icon: timerService.state == .running ? "pause.circle.fill" : "play.circle.fill",
                color: .yellow,
                help: timerService.state == .running ? "Pause" : "Resume"
            ) {
                timerService.state == .running ? timerService.pauseTimer() : timerService.resumeTimer()
            }

            // Complete / End Break
            if let task = activeTask {
                menuBarButton(icon: "checkmark.circle.fill", color: .green, help: "Complete Task") {
                    remindersService.toggleComplete(task)
                    timerService.stopTimer()
                    onClose()
                }
            } else if timerService.isOnBreak {
                menuBarButton(icon: "checkmark.circle.fill", color: .green, help: "End Break") {
                    timerService.endBreak()
                    timerService.isFocusMode = false
                    onClose()
                }
            }

            // Break / Skip
            if !timerService.isOnBreak {
                menuBarButton(icon: "cup.and.saucer.fill", color: .secondary, help: "Take a Break") {
                    timerService.startBreak(duration: 600)
                }
            } else {
                menuBarButton(icon: "forward.end.fill", color: .secondary, help: "Skip Break") {
                    timerService.endBreak()
                }
            }

            // Subtasks toggle
            if timerService.activeReminderId != nil, !timerService.isOnBreak {
                menuBarButton(
                    icon: showSubtasks ? "checklist.checked" : "checklist",
                    color: showSubtasks ? .primary : .secondary,
                    help: showSubtasks ? "Hide Subtasks" : "Show Subtasks"
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { showSubtasks.toggle() }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Inline subtasks

    @ViewBuilder
    private func subtasksList(for taskId: String) -> some View {
        let items = subtaskStore.subtasks(for: taskId)
        VStack(alignment: .leading, spacing: 6) {
            if !items.isEmpty {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Button {
                            subtaskStore.toggleSubtask(id: item.id, for: taskId)
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(item.isCompleted ? Color.green : Color.secondary.opacity(0.5), lineWidth: 1.5)
                                    .frame(width: 14, height: 14)
                                if item.isCompleted {
                                    Circle().fill(Color.green).frame(width: 14, height: 14)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(.black.opacity(0.7))
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Text(item.title)
                            .font(.system(size: 12))
                            .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                            .strikethrough(item.isCompleted)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            subtaskStore.deleteSubtask(id: item.id, for: taskId)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Add input
            HStack(spacing: 6) {
                Text("+")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                TextField("Add subtask…", text: $newSubtaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isSubtaskInputFocused)
                    .onSubmit {
                        let t = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        subtaskStore.addSubtask(title: t, for: taskId)
                        newSubtaskTitle = ""
                        isSubtaskInputFocused = true
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: - Helpers

    private func menuBarButton(icon: String, color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Glass modifier for the menu bar panel

private struct MenuBarGlassModifier: ViewModifier {
    let appTheme: AppTheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if appTheme == .glass {
            if #available(macOS 26.0, *) {
                content.glassEffect(
                    .regular.interactive(false),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            } else {
                content.background(
                    VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                )
            }
        } else if appTheme == .white {
            content
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.97))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
        } else {
            content
                .background(
                    VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}
