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
    private var dividerColor: Color {
        isWhiteTheme ? Color.black.opacity(0.15) : Color.white.opacity(0.15)
    }

    var body: some View {
        VStack(spacing: 0) {
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

            if showSubtasks, let activeId = timerService.activeReminderId {
                Divider()
                    .background(dividerColor)
                SubtasksPanelView(taskId: activeId, onClose: { showSubtasks = false })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSubtasks)
        .background(
            ZStack(alignment: .bottom) {
                if appTheme == .glass {
                    liquidGlassBackground(cornerRadius: 30)
                } else {
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
        .cornerRadius(30)
        .overlay(
            Group {
                if appTheme == .glass {
                    if #available(macOS 26.0, *) {
                        // glassEffect provides its own edge treatment — no stroke needed
                        EmptyView()
                    } else {
                        IceGlassStroke(cornerRadius: 30)
                    }
                } else {
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
        .preferredColorScheme(isWhiteTheme ? .light : .dark)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hover
            }
        }
        .onAppear {
            if let window {
                styleWindow(window)
            }
        }
        .onChange(of: window) { _, newWindow in
            if let win = newWindow {
                styleWindow(win)
            }
        }
        .onDisappear {
            if windowCoordinator.pillWindow === window {
                windowCoordinator.pillWindow = nil
            }
        }
    }

    private func styleWindow(_ window: NSWindow) {
        window.identifier = AppWindowCoordinator.pillWindowIdentifier
        windowCoordinator.pillWindow = window
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.borderless, .fullSizeContentView]

        // Hide standard buttons explicitly
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // Ensure floating level
        window.level = .floating

        // Enable native dragging via background
        window.isMovableByWindowBackground = true
        window.isMovable = true
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

    private var dividerColor: Color {
        appTheme == .white ? Color.black.opacity(0.2) : Color.white.opacity(0.2)
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
            if timerService.activeReminderId != nil && !timerService.isOnBreak {
                IconButton(
                    icon: showSubtasks ? "checklist.checked" : "checklist",
                    color: showSubtasks ? .primary : .secondary,
                    help: showSubtasks ? "Hide Subtasks" : "Show Subtasks"
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSubtasks.toggle()
                    }
                }
            }
        }
    }
}

struct PillInfoView: View {
    @ObservedObject var timerService: TimerService
    @ObservedObject var remindersService: RemindersService
    @AppStorage("appTheme") private var appTheme: AppTheme = .glass

    private var dividerColor: Color {
        appTheme == .white ? Color.black.opacity(0.2) : Color.white.opacity(0.2)
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

// Optimization: Equatable wrapper to stop redraws from TimerService updates
struct PillTitleView: View, Equatable {
    let title: String

    var body: some View {
        Text(title)
            .font(.body)
            .fontWeight(.medium)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    static func == (lhs: PillTitleView, rhs: PillTitleView) -> Bool {
        return lhs.title == rhs.title
    }
}

// MARK: - Subtasks Panel

struct SubtasksPanelView: View {
    let taskId: String
    let onClose: () -> Void

    @EnvironmentObject var subtaskStore: SubtaskStore
    @AppStorage("appTheme") private var appTheme: AppTheme = .glass

    @State private var newTitle: String = ""
    @FocusState private var isInputFocused: Bool

    private var isWhiteTheme: Bool { appTheme == .white }
    private var labelColor: Color { isWhiteTheme ? Color.black.opacity(0.45) : Color.white.opacity(0.4) }
    private var textColor: Color { isWhiteTheme ? Color.primary : Color.white.opacity(0.85) }
    private var completedColor: Color { isWhiteTheme ? Color.secondary : Color.white.opacity(0.35) }
    private var inputBackground: Color { isWhiteTheme ? Color.black.opacity(0.06) : Color.white.opacity(0.06) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subtasks")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(labelColor)
                .textCase(.uppercase)
                .tracking(0.5)

            let items = subtaskStore.subtasks(for: taskId)

            if !items.isEmpty {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Button {
                            subtaskStore.toggleSubtask(id: item.id, for: taskId)
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(item.isCompleted ? Color.green : Color.secondary.opacity(0.5),
                                                  lineWidth: 1.5)
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
                            .foregroundColor(item.isCompleted ? completedColor : textColor)
                            .strikethrough(item.isCompleted)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            subtaskStore.deleteSubtask(id: item.id, for: taskId)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .opacity(0.6)
                    }
                }
            }

            // Add subtask input
            HStack(spacing: 6) {
                Text("+")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.5))

                TextField("Add subtask…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .focused($isInputFocused)
                    .onSubmit {
                        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        subtaskStore.addSubtask(title: trimmed, for: taskId)
                        newTitle = ""
                        isInputFocused = true
                    }
                    .onExitCommand {
                        onClose()
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(inputBackground)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 268)
    }
}

// MARK: - Reusable Components

struct ControlButton: View {
    let color: Color
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear.frame(width: 24, height: 24)
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.black.opacity(0.6))
                    )
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct IconButton: View {
    let icon: String
    let color: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear.frame(width: 24, height: 24)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct PillTimerDisplay: View {
    @ObservedObject var ticker: TimeTicker
    @ObservedObject var service: TimerService
    @AppStorage("appTheme") private var appTheme: AppTheme = .glass

    var body: some View {
        Text(service.formattedTime())
            .font(.title2).fontWeight(.bold).monospacedDigit()
            .foregroundColor(timerColor)
            .contentTransition(.numericText(countsDown: !service.isStopwatch && !service.isOvertime))
            .animation(.snappy, value: service.formattedTime())
            .fixedSize()
    }

    private var timerColor: Color {
        if service.isOvertime { return .orange }
        return appTheme == .white ? Color.black.opacity(0.9) : .white
    }
}
