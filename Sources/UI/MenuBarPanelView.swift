import SwiftUI
import EventKit

/// Panel shown when the user left-clicks the Helpy menu bar icon.
/// Displays the current timer, task info, and focus controls.
struct MenuBarPanelView: View {
    @ObservedObject var timerService: TimerService
    @ObservedObject var remindersService: RemindersService
    @ObservedObject var subtaskStore: SubtaskStore
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showSubtasks = false
    @State private var newSubtaskTitle = ""
    @FocusState private var isSubtaskInputFocused: Bool

    private var t: HelpyPalette { .forScheme(colorScheme) }

    private var activeTask: EKReminder? {
        guard let id = timerService.activeReminderId else { return nil }
        return remindersService.reminders.first { $0.calendarItemIdentifier == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            controlsRow

            if showSubtasks, let id = timerService.activeReminderId {
                Rectangle().fill(t.line).frame(height: 1).padding(.horizontal, 14)
                subtasksList(for: id)
            }
        }
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(t.canvas)
        .clipShape(RoundedRectangle(cornerRadius: HelpyMetrics.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HelpyMetrics.panelCornerRadius, style: .continuous)
                .strokeBorder(t.panelBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Header: brand + task name + timer

    /// Full-bleed gradient that sweeps into rounded BOTTOM corners; the panel's
    /// own clip rounds the top two. Same shape language as the sidebar header.
    private var headerRow: some View {
        HStack(spacing: 12) {
            HelpyMark(size: 26)

            VStack(alignment: .leading, spacing: 1) {
                if timerService.isOnBreak {
                    Text("Break")
                        .font(.inter(size: 14, weight: .semibold))
                        .foregroundStyle(t.onAccent)
                } else if let task = activeTask {
                    Text(task.title)
                        .font(.inter(size: 13, weight: .semibold))
                        .foregroundStyle(t.onAccent)
                        .lineLimit(2)
                } else {
                    Text("No Active Task")
                        .font(.inter(size: 13, weight: .medium))
                        .foregroundStyle(t.onAccent.opacity(0.75))
                }
            }

            Spacer(minLength: 8)

            MenuBarTimerText(ticker: timerService.ticker, service: timerService, palette: t)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 15)
        .background(HelpyHeaderBackground(palette: t))
    }

    // MARK: - Controls row

    private var controlsRow: some View {
        HStack(spacing: 3) {
            // Exit Focus
            PillControlButton(icon: "xmark", help: "Exit Focus", tone: .danger, palette: t) {
                timerService.isFocusMode = false
                onClose()
            }

            // Pause / Resume
            PillControlButton(
                icon: timerService.state == .running ? "pause.fill" : "play.fill",
                help: timerService.state == .running ? "Pause" : "Resume",
                palette: t
            ) {
                timerService.state == .running ? timerService.pauseTimer() : timerService.resumeTimer()
            }

            // Complete / End Break
            if let task = activeTask {
                PillControlButton(icon: "checkmark", help: "Complete Task", tone: .go, palette: t) {
                    remindersService.toggleComplete(task)
                    timerService.stopTimer()
                    onClose()
                }
            } else if timerService.isOnBreak {
                PillControlButton(icon: "checkmark", help: "End Break", tone: .go, palette: t) {
                    timerService.endBreak()
                    timerService.isFocusMode = false
                    onClose()
                }
            }

            // Break / Skip
            if !timerService.isOnBreak {
                PillControlButton(icon: "cup.and.saucer.fill", help: "Take a Break", palette: t) {
                    timerService.startBreak() // uses the Break Duration setting
                }
            } else {
                PillControlButton(icon: "forward.end.fill", help: "Skip Break", palette: t) {
                    timerService.endBreak()
                }
            }

            // Subtasks toggle
            if timerService.activeReminderId != nil, !timerService.isOnBreak {
                PillControlButton(
                    icon: showSubtasks ? "checklist.checked" : "checklist",
                    help: showSubtasks ? "Hide Subtasks" : "Show Subtasks",
                    isActive: showSubtasks,
                    palette: t
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
        VStack(alignment: .leading, spacing: 7) {
            ForEach(items) { item in
                HStack(spacing: 9) {
                    Button {
                        subtaskStore.toggleSubtask(id: item.id, for: taskId)
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(item.isCompleted ? t.accent : t.checkBorder, lineWidth: 1.5)
                                .background(Circle().fill(item.isCompleted ? t.accent : .clear))
                                .frame(width: 14, height: 14)
                            if item.isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(t.onAccent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .animation(.easeOut(duration: 0.16), value: item.isCompleted)

                    Text(item.title)
                        .font(.inter(size: 12))
                        .foregroundStyle(item.isCompleted ? t.muted : t.ink2)
                        .strikethrough(item.isCompleted)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        subtaskStore.deleteSubtask(id: item.id, for: taskId)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(t.muted2)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Add input
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.muted2)
                TextField("Add subtask…", text: $newSubtaskTitle)
                    .textFieldStyle(.plain)
                    .font(.inter(size: 12))
                    .foregroundStyle(t.ink)
                    .focused($isSubtaskInputFocused)
                    .onSubmit {
                        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        subtaskStore.addSubtask(title: title, for: taskId)
                        newSubtaskTitle = ""
                        isSubtaskInputFocused = true
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.fieldFill))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(t.fieldBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 13)
    }
}

/// The dropdown's clock has to observe the TICKER, not TimerService.
/// TimeTicker is deliberately decoupled so a per-second tick doesn't invalidate
/// every TimerService observer — which also means a view that only observes
/// TimerService never redraws on a tick. Reading `formattedTime()` from a view
/// bound to `timerService` alone is why this label sat frozen at the value it
/// happened to have when the panel opened.
private struct MenuBarTimerText: View {
    @ObservedObject var ticker: TimeTicker
    @ObservedObject var service: TimerService
    let palette: HelpyPalette

    var body: some View {
        Text(service.formattedTime())
            .font(.inter(size: 17, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(palette.onAccent)
            .contentTransition(.numericText(countsDown: !service.isStopwatch && !service.isOvertime))
            .animation(.snappy, value: service.formattedTime())
            .fixedSize()
    }
}
