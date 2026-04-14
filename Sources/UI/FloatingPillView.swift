import SwiftUI

// MarqueeText removed in favor of static multi-line text for 0% CPU usage

// Helper to get NSWindow securely
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct FloatingPillView: View {
    @EnvironmentObject var timerService: TimerService
    @EnvironmentObject var remindersService: RemindersService
    @EnvironmentObject var estimateStore: EstimateStore
    @EnvironmentObject var windowCoordinator: AppWindowCoordinator
    @EnvironmentObject var subtaskStore: SubtaskStore
    @AppStorage("appTheme") private var appTheme: AppTheme = .glass

    @State private var isHovering = false
    @State private var showSubtasks = false
    @State private var window: NSWindow?
    @State private var isPulsing = false

    private var isWhiteTheme: Bool { appTheme == .white }
    private var overlayBaseColor: Color { isWhiteTheme ? Color.white.opacity(0.78) : Color.black.opacity(0.3) }
    private var progressTrackColor: Color { isWhiteTheme ? Color.black.opacity(0.1) : Color.white.opacity(0.1) }
    private var borderGradientColors: [Color] {
        isWhiteTheme ? [Color.black.opacity(0.2), Color.black.opacity(0.06)] : [Color.white.opacity(0.3), Color.white.opacity(0.05)]
    }

    var body: some View {
        // Each glass view independently samples the desktop pixels behind its own frame.
        // GlassEffectContainer is intentionally NOT used here — on macOS it creates an
        // NSView-backed container with a default background rect, which prevents each glass
        // from reaching real desktop pixels and breaks colorScheme adaptation.
        VStack(alignment: .center, spacing: 10) {
            pillView

            if showSubtasks, let activeId = timerService.activeReminderId {
                SubtasksPanelView(
                    taskId: activeId,
                    onClose: { showSubtasks = false },
                    subtaskStore: subtaskStore
                )
                // Glass applied here so SubtasksPanelView is a CHILD of the glass effect,
                // meaning its @Environment(\.colorScheme) receives the glass-propagated
                // value — correct adaptation to desktop background, not just system theme.
                // SubtasksPanelView.body has a clipShape that makes the surface transparent
                // (matching the pill), so the glass samples real desktop pixels.
                .liquidGlassContainer(isGlass: appTheme == .glass, cornerRadius: 18)
                .overlay {
                    if appTheme == .glass {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                // Shadow wraps the glass shape (applied after glass, same as the pill).
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
                // Explicit hit area so the full panel surface is tappable.
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                // preferredColorScheme is outside the glass so it doesn't override
                // the glass's downward colorScheme injection.
                .preferredColorScheme(appTheme == .white ? .light : appTheme == .glass ? nil : .dark)
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSubtasks)
        .onAppear {
            if let window { styleWindow(window) }
        }
        .onChange(of: window) { _, newWindow in
            if let win = newWindow { styleWindow(win) }
        }
        .onDisappear {
            if windowCoordinator.pillWindow === window {
                windowCoordinator.pillWindow = nil
            }
            showSubtasks = false
        }
    }

    @ViewBuilder
    private var pillView: some View {
        ZStack {

            if isHovering {
                PillControlsView(
                    isHovering: $isHovering,
                    showSubtasks: $showSubtasks,
                    timerService: timerService,
                    remindersService: remindersService,
                    estimateStore: estimateStore
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else {
                PillInfoView(
                    timerService: timerService,
                    remindersService: remindersService
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .frame(minWidth: 280, minHeight: 42)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(
            ZStack(alignment: .bottom) {
                // Non-glass themes: opaque/vibrancy material
                if appTheme != .glass {
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    overlayBaseColor
                }

                // Pulse Effect for Time's Up
                if timerService.timesUpTriggered {
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(Color.red.opacity(0.5), lineWidth: 2)
                        .background(Color.red.opacity(0.1))
                        .opacity(isPulsing ? 1.0 : 0.0)
                        .animation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                        .onAppear { isPulsing = true }
                        .onDisappear { isPulsing = false }
                }

                // Pulse Effect for Task Alerts (Periodic)
                if timerService.taskAlertTriggered {
                     RoundedRectangle(cornerRadius: 30)
                         .stroke(Color.cyan.opacity(0.8), lineWidth: 2)
                         .background(Color.cyan.opacity(0.15))
                         .opacity(isPulsing ? 1.0 : 0.0)
                         .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
                         .onAppear { isPulsing = true }
                         .onDisappear { isPulsing = false }
                 }

                WindowAccessor(window: $window)

                // Bottom Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(progressTrackColor)
                            .frame(height: 3)

                        Rectangle()
                            .fill(progressBarColor)
                            .frame(width: geo.size.width * CGFloat(progress), height: 3)
                            .shadow(color: progressBarColor.opacity(0.8), radius: 4, x: 0, y: 0)
                    }
                }
                .frame(height: 3)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            Group {
                if appTheme != .glass {
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(
                            LinearGradient(
                                colors: borderGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
        )
        .liquidGlassContainer(isGlass: appTheme == .glass, cornerRadius: 30)
        .overlay {
            if appTheme == .glass {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 4)
        .preferredColorScheme(appTheme == .white ? .light : appTheme == .glass ? nil : .dark)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hover
            }
        }
    }

    private func styleWindow(_ window: NSWindow) {
        window.identifier = AppWindowCoordinator.pillWindowIdentifier
        windowCoordinator.pillWindow = window
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.borderless, .fullSizeContentView]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isMovable = true
        // Use SwiftUI .shadow() instead — prevents rectangular window shadow artifacts.
        window.hasShadow = false
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

    private var progressBarColor: Color {
        return timerService.isOnBreak ? .orange : .green
    }
}

// MARK: - Subviews

struct PillControlsView: View {
    @Binding var isHovering: Bool
    @Binding var showSubtasks: Bool
    @ObservedObject var timerService: TimerService
    @ObservedObject var remindersService: RemindersService
    @ObservedObject var estimateStore: EstimateStore
    @AppStorage("appTheme") private var appTheme: AppTheme = .glass
    @Environment(\.colorScheme) private var colorScheme

    private var dividerColor: Color {
        if appTheme == .white { return Color.black.opacity(0.2) }
        if appTheme == .dark { return Color.white.opacity(0.2) }
        return colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.15)
    }

    var body: some View {
        HStack(spacing: 12) {

            // EXIT FOCUS (Red)
            ControlButton(color: .red, icon: "xmark", help: "Exit Focus Mode") {
                timerService.isFocusMode = false
            }

            // PAUSE/RESUME (Yellow)
            ControlButton(
                color: .yellow,
                icon: timerService.state == .running ? "pause.fill" : "play.fill",
                help: timerService.state == .running ? "Pause" : "Resume"
            ) {
                if timerService.state == .running {
                    timerService.pauseTimer()
                } else {
                    timerService.resumeTimer()
                }
            }

            // COMPLETE / END BREAK (Green)
            if let activeId = timerService.activeReminderId,
               let task = remindersService.reminders.first(where: { $0.calendarItemIdentifier == activeId }) {
                ControlButton(color: .green, icon: "checkmark", help: "Complete Task") {
                    remindersService.toggleComplete(task)
                    timerService.stopTimer()
                }
            } else if timerService.isOnBreak {
                ControlButton(color: .green, icon: "checkmark", help: "End Break") {
                    timerService.endBreak()
                    timerService.isFocusMode = false
                }
            }

            Divider().frame(height: 16).background(dividerColor)

            // EXTEND TIME
            if timerService.timesUpTriggered {
                IconButton(icon: "clock.arrow.circlepath", color: .orange, help: "Extend Time") {
                    timerService.startOvertime()
                }
            }

            // SKIP / NEXT
            if timerService.isOnBreak {
                IconButton(icon: "forward.end.fill", color: .secondary, help: "Skip Break") {
                    timerService.endBreak()
                }
            } else {
                IconButton(icon: "forward.end.fill", color: .secondary, help: "Skip Task") {
                     if let activeId = timerService.activeReminderId,
                        let next = remindersService.getNextTask(after: activeId) {
                         let dur = estimateStore.getMetadata(for: next.calendarItemIdentifier)?.estimatedDuration ?? 1500
                         timerService.startTimer(reminderId: next.calendarItemIdentifier, duration: dur)
                     } else {
                         timerService.stopTimer()
                     }
                }
            }

            // BREAK / LIST
            if !timerService.isOnBreak {
                IconButton(icon: "cup.and.saucer.fill", color: .secondary, help: "Take a Break") {
                    timerService.startBreak(duration: 600)
                }
            } else {
                IconButton(icon: "square.grid.2x2", color: .secondary, help: "Open List") {
                    timerService.isFocusMode = false
                }
            }

            // SUBTASKS — only when a task is active (not on break)
            if let activeId = timerService.activeReminderId, !timerService.isOnBreak {
                IconButton(
                    icon: showSubtasks ? "checklist.checked" : "checklist",
                    color: showSubtasks ? .primary : .secondary,
                    help: showSubtasks ? "Hide Subtasks" : "Show Subtasks"
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
    @AppStorage("appTheme") private var appTheme: AppTheme = .glass
    @Environment(\.colorScheme) private var colorScheme

    private var dividerColor: Color {
        if appTheme == .white { return Color.black.opacity(0.2) }
        if appTheme == .dark { return Color.white.opacity(0.2) }
        return colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.15)
    }

    var body: some View {
        if timerService.isOnBreak {
            HStack(alignment: .center, spacing: 12) {
                Text("Break")
                    .font(.body).fontWeight(.bold)
                    .frame(maxWidth: 180)

                Divider().frame(height: 16).background(dividerColor)

                PillTimerDisplay(ticker: timerService.ticker, service: timerService)
            }
        } else if let activeId = timerService.activeReminderId,
                  let activeTask = remindersService.reminders.first(where: { $0.calendarItemIdentifier == activeId }) {

            HStack(alignment: .center, spacing: 12) {
                PillTitleView(title: activeTask.title)
                    .equatable()

                Divider().frame(height: 16).background(dividerColor)

                if timerService.timesUpTriggered {
                    Text("Time's Up")
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.red)
                        .fixedSize()
                } else {
                    PillTimerDisplay(ticker: timerService.ticker, service: timerService)
                }
            }
        } else {
            Text("No Active Task").font(.body)
        }
    }
}
