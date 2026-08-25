import SwiftUI
import AppKit

/// Keeps the pill window's TOP edge fixed while it auto-resizes to content
/// (subtasks panel opening/closing). AppKit anchors a resizing window at its
/// bottom-left origin, which visually shoved the whole pill up/down; re-pinning
/// maxY on every resize step means only the bottom section grows or collapses.
final class PillWindowTopAnchor {
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var topY: CGFloat = 0
    private var lastHeight: CGFloat = 0
    private var adjusting = false

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        detach()
        self.window = window
        topY = window.frame.maxY
        lastHeight = window.frame.height

        let handler: (Notification) -> Void = { [weak self] note in
            guard let self, let win = note.object as? NSWindow, win === self.window else { return }
            self.windowFrameChanged(win)
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main, using: handler))
        observers.append(center.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main, using: handler))
    }

    func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        window = nil
    }

    deinit {
        detach()
    }

    private func windowFrameChanged(_ window: NSWindow) {
        guard !adjusting else { return }
        let frame = window.frame
        if abs(frame.height - lastHeight) < 0.5 {
            // Pure move (user dragged the pill): adopt the new top edge.
            topY = frame.maxY
            return
        }
        lastHeight = frame.height
        guard abs(frame.maxY - topY) > 0.5 else { return }
        adjusting = true
        var pinned = frame
        pinned.origin.y = topY - pinned.height
        window.setFrame(pinned, display: true)
        // The window-server shadow is computed from rendered content; recompute
        // it as the panel animates open/closed so it never lags the new shape.
        window.invalidateShadow()
        adjusting = false
    }
}

/// Hairline separator between the pill's title and its clock. `Divider()`
/// ignores `.background`, so this draws the rule directly.
struct PillDivider: View {
    let color: Color
    var height: CGFloat = 17

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 1, height: height)
    }
}

struct FloatingPillView: View {
    @EnvironmentObject var timerService: TimerService
    @EnvironmentObject var remindersService: RemindersService
    @EnvironmentObject var estimateStore: EstimateStore
    @EnvironmentObject var windowCoordinator: AppWindowCoordinator
    @EnvironmentObject var subtaskStore: SubtaskStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showSubtasks = false
    @State private var isPulsing = false

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var radius: CGFloat { HelpyMetrics.pillCornerRadius }

    /// Hover is tracked by the coordinator, not by `.onHover`: SwiftUI's hover
    /// only fires while Helpy is the frontmost app, and during focus mode it
    /// never is — the pill floats over whatever you are actually working in.
    private var isHovering: Bool { windowCoordinator.isPillHovered }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            pillView

            if showSubtasks, let activeId = timerService.activeReminderId {
                SubtasksPanelView(
                    taskId: activeId,
                    onClose: { showSubtasks = false },
                    subtaskStore: subtaskStore
                )
                // SubtasksPanelView paints its own surface. No in-window
                // shadow here either — it clips at the window edge into a gray
                // rectangle (see the pill's carrier comment); the AppKit window
                // shadow covers the panel's shape too.
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSubtasks)
        .onDisappear { showSubtasks = false }
    }

    @ViewBuilder
    private var pillView: some View {
        // Both states stay in the layout so the pill keeps one stable size.
        // Swapping them in/out resized the pill under the cursor, which could
        // flip hover off/on in a loop (visible as flicker at the pill's edge).
        ZStack {
            PillControlsView(
                showSubtasks: $showSubtasks,
                timerService: timerService,
                remindersService: remindersService,
                estimateStore: estimateStore,
                palette: t
            )
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)

            PillInfoView(
                timerService: timerService,
                remindersService: remindersService,
                palette: t
            )
            .opacity(isHovering ? 0 : 1)
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .frame(minWidth: 268, minHeight: 30)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(
            ZStack(alignment: .bottom) {
                // Plain opaque fill — the redesign has no glass anywhere.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(t.pillFill)

                // Bottom progress rail
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(t.railTrack)
                            .frame(height: 3)

                        Rectangle()
                            .fill(railColor)
                            .frame(width: geo.size.width * CGFloat(progress), height: 3)
                    }
                }
                .frame(height: 3)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        // NEVER draw a shadow (SwiftUI .shadow or otherwise) inside this
        // window: it hugs its content, so the shadow's blur field fills the
        // window and is clipped at the rectangular window edge — a faint gray
        // RECTANGLE behind the pill (pixel-proved: full-bleed low-alpha wash
        // in the window's own rendering). Depth comes from the AppKit window
        // shadow instead (hasShadow = true on the panel), which the window
        // server draws around the rendered shape, outside the bounds.
        .overlay {
            // strokeBorder insets the line, so the full width survives the clip.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(alertRingColor ?? t.pillBorder, lineWidth: alertRingColor == nil ? 1 : 2)
                .opacity(alertRingColor == nil ? 1 : (isPulsing ? 1.0 : 0.22))
                .animation(
                    alertRingColor == nil
                        ? nil
                        : .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .allowsHitTesting(false)
        }
        .onChange(of: alertRingColor == nil) { _, quiet in
            isPulsing = !quiet
        }
        .onAppear { isPulsing = alertRingColor != nil }
    }

    // Logic for Progress Bar
    private var progress: Double {
        if timerService.isOnBreak {
            let total = timerService.initialDuration
            let remaining = timerService.remainingTime
            let elapsed = total - remaining
            return total > 0 ? min(max(elapsed / total, 0.0), 1.0) : 0.0
        } else if let activeId = timerService.activeReminderId,
                  let _ = remindersService.reminders.first(where: { $0.calendarItemIdentifier == activeId }) {
            let duration = estimateStore.getMetadata(for: activeId)?.estimatedDuration ?? 1800
            let elapsed = estimateStore.getMetadata(for: activeId)?.timeSpent ?? 0
            return duration > 0 ? min(elapsed / duration, 1.0) : 0.0
        }
        return 0.0
    }

    /// Blue while the work is on track, amber on a break or in overtime, coral
    /// once the estimate has blown past. Flat, like every other filled surface.
    private var railColor: Color {
        if timerService.timesUpTriggered { return t.hot }
        if timerService.isOnBreak || timerService.isOvertime { return t.warm }
        return t.rail
    }

    /// nil means "no alert" — the pill wears its resting 1pt border instead.
    private var alertRingColor: Color? {
        if timerService.timesUpTriggered { return t.hot }
        if timerService.taskAlertTriggered { return t.accent }
        return nil
    }
}

// MARK: - Subviews

struct PillControlsView: View {
    @Binding var showSubtasks: Bool
    @ObservedObject var timerService: TimerService
    @ObservedObject var remindersService: RemindersService
    @ObservedObject var estimateStore: EstimateStore
    let palette: HelpyPalette

    var body: some View {
        HStack(spacing: 2) {

            // EXIT FOCUS
            PillControlButton(icon: "xmark", help: "Exit Focus Mode", tone: .danger, palette: palette) {
                timerService.isFocusMode = false
            }

            // PAUSE / RESUME
            PillControlButton(
                icon: timerService.state == .running ? "pause.fill" : "play.fill",
                help: timerService.state == .running ? "Pause" : "Resume",
                palette: palette
            ) {
                if timerService.state == .running {
                    timerService.pauseTimer()
                } else {
                    timerService.resumeTimer()
                }
            }

            // COMPLETE / END BREAK
            if let activeId = timerService.activeReminderId,
               let task = remindersService.reminders.first(where: { $0.calendarItemIdentifier == activeId }) {
                PillControlButton(icon: "checkmark", help: "Complete Task", tone: .go, palette: palette) {
                    remindersService.toggleComplete(task)
                    timerService.stopTimer()
                }
            } else if timerService.isOnBreak {
                PillControlButton(icon: "checkmark", help: "End Break", tone: .go, palette: palette) {
                    timerService.endBreak()
                    timerService.isFocusMode = false
                }
            }

            PillDivider(color: palette.line).padding(.horizontal, 5)

            // EXTEND TIME
            if timerService.timesUpTriggered {
                PillControlButton(icon: "clock.arrow.circlepath", help: "Extend Time", palette: palette) {
                    timerService.startOvertime()
                }
            }

            // SKIP / NEXT
            if timerService.isOnBreak {
                PillControlButton(icon: "forward.end.fill", help: "Skip Break", palette: palette) {
                    timerService.endBreak()
                }
            } else {
                PillControlButton(icon: "forward.end.fill", help: "Skip Task", palette: palette) {
                     if let activeId = timerService.activeReminderId,
                        let next = remindersService.getNextTask(after: activeId) {
                         // 0 = no estimate -> stopwatch mode (same as everywhere else)
                         let dur = estimateStore.getMetadata(for: next.calendarItemIdentifier)?.estimatedDuration ?? 0
                         timerService.startTimer(reminderId: next.calendarItemIdentifier, duration: dur)
                     } else {
                         timerService.stopTimer()
                     }
                }
            }

            // BREAK / LIST
            if !timerService.isOnBreak {
                PillControlButton(icon: "cup.and.saucer.fill", help: "Take a Break", palette: palette) {
                    timerService.startBreak() // uses the Break Duration setting
                }
            } else {
                PillControlButton(icon: "square.grid.2x2", help: "Open List", palette: palette) {
                    timerService.isFocusMode = false
                }
            }

            // SUBTASKS — only when a task is active (not on break)
            if timerService.activeReminderId != nil, !timerService.isOnBreak {
                PillControlButton(
                    icon: showSubtasks ? "checklist.checked" : "checklist",
                    help: showSubtasks ? "Hide Subtasks" : "Show Subtasks",
                    isActive: showSubtasks,
                    palette: palette
                ) {
                    showSubtasks.toggle()
                }
            }
        }
    }
}

struct PillInfoView: View {
    @ObservedObject var timerService: TimerService
    @ObservedObject var remindersService: RemindersService
    let palette: HelpyPalette

    var body: some View {
        Group {
            if timerService.isOnBreak {
                HStack(alignment: .center, spacing: 11) {
                    Text("Break")
                        .font(.inter(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink2)
                        .frame(width: 186, alignment: .leading)

                    PillDivider(color: palette.line)

                    PillTimerDisplay(ticker: timerService.ticker, service: timerService, palette: palette)
                }
            } else if let activeId = timerService.activeReminderId,
                      let activeTask = remindersService.reminders.first(where: { $0.calendarItemIdentifier == activeId }) {

                HStack(alignment: .center, spacing: 11) {
                    PillTitleView(title: activeTask.title, color: palette.ink2)
                        .equatable()

                    PillDivider(color: palette.line)

                    if timerService.timesUpTriggered {
                        Text("Time's Up")
                            .font(.inter(size: 13, weight: .bold))
                            .foregroundStyle(palette.hot)
                            .fixedSize()
                    } else {
                        PillTimerDisplay(ticker: timerService.ticker, service: timerService, palette: palette)
                    }
                }
            } else {
                Text("No Active Task")
                    .font(.inter(size: 13, weight: .medium))
                    .foregroundStyle(palette.muted)
            }
        }
        .padding(.horizontal, 9)
    }
}
