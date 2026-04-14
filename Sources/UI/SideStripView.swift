import SwiftUI
import EventKit
import AppKit

/// Applies `.glassEffect(.regular, in: Rectangle())` to the sidebar container on macOS 26+.
/// Applying to the container (not to a nested Color.clear) lets the glass propagate an adaptive
/// colorScheme to all children based on sampled background brightness.
private struct GlassSidebarModifier: ViewModifier {
    let isGlass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isGlass {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: Rectangle())
            } else {
                content.background(
                    VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                        .ignoresSafeArea()
                )
            }
        } else {
            content
        }
    }
}

struct SideStripView: View {
    @EnvironmentObject var remindersService: RemindersService
    @EnvironmentObject var timerService: TimerService
    @EnvironmentObject var estimateStore: EstimateStore
    @EnvironmentObject var windowCoordinator: AppWindowCoordinator
    @Environment(\.openWindow) var openWindow
    
    @State private var isHoveringActiveTask: Bool = false
    @State private var draggedReminder: EKReminder? // Track visually dragged item
    @State private var isCompletingActive = false
    
    @State private var isSettingsOpen = false
    @State private var settingsStore = SettingsStore() // Local instance for embedded view
    @State private var isHoveringFocusButton = false // Focus Button Hover State
    @StateObject private var assistantCoordinator = AssistantCoordinator()
    
    // Quick Add State
    @State private var newTaskTitle = ""
    @State private var isPulsing = false // For task alert animation
    @AppStorage("appTheme") private var appTheme: AppTheme = .glass
    @AppStorage("assistantEnabled") private var assistantEnabled: Bool = true
    
    private let completionCommitDelay: TimeInterval = 0.18
    private let completionAnimation = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.8, blendDuration: 0.1)
    private let accentBlue = Color(red: 67.0 / 255.0, green: 166.0 / 255.0, blue: 1.0)
    
    private var isWhiteTheme: Bool { appTheme == .white }
    private var panelOverlayColor: Color {
        switch appTheme {
        case .glass: return .clear
        case .dark: return Color.black.opacity(0.3)
        case .white: return Color.black.opacity(0.05)
        }
    }
    private var sessionCardFillColor: Color {
        switch appTheme {
        case .glass:
            return Color.primary.opacity(0.06)
        case .dark:
            return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .white:
            return Color.white.opacity(0.95)
        }
    }
    private var cardBorderColor: Color { isWhiteTheme ? Color.black.opacity(0.12) : Color.white.opacity(0.1) }
    private var progressTrackColor: Color { isWhiteTheme ? Color.black.opacity(0.1) : Color.white.opacity(0.1) }
    private var controlDividerColor: Color { isWhiteTheme ? Color.black.opacity(0.2) : Color.white.opacity(0.2) }
    private var quickAddFillColor: Color {
        switch appTheme {
        case .glass: return Color.white.opacity(0.06)
        case .dark: return Color.black.opacity(0.3)
        case .white: return Color.white.opacity(0.94)
        }
    }
    private var quickAddMaterialOpacity: Double {
        switch appTheme {
        case .glass: return 0.0
        case .dark: return 0.3
        case .white: return 0.2
        }
    }
    private var quickAddBorderColor: Color { isWhiteTheme ? Color.black.opacity(0.14) : Color.white.opacity(0.1) }
    private var focusForegroundColor: Color { .white }
    private var focusFillColor: Color {
        if isWhiteTheme {
            return accentBlue
        }
        return appTheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.22)
    }
    private var focusGlowColor: Color { isWhiteTheme ? accentBlue.opacity(0.45) : Color.white.opacity(0.4) }
    private var focusStrokeGradient: [Color] { [Color.white.opacity(0.3), Color.white.opacity(0.05)] }
    private var listTitleColor: Color { isWhiteTheme ? accentBlue : .primary }
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if appTheme == .glass {
                    if #available(macOS 26.0, *) {
                        Color.clear
                            .glassEffect(.regular, in: Rectangle())
                            .ignoresSafeArea()
                    } else {
                        VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                            .ignoresSafeArea()
                    }
                } else {
                    (isWhiteTheme ? Color.white : Color(nsColor: .windowBackgroundColor))
                        .ignoresSafeArea()
                }
                
                VStack(spacing: 0) {
                    // Header
                    if !isSettingsOpen {
                        headerView
                            .background(panelOverlayColor)
                            .zIndex(1)
                    }
                    
                    // Content Switcher
                    if isSettingsOpen {
                        EmbeddedSettingsView(settings: settingsStore) {
                            withAnimation { isSettingsOpen = false }
                        }
                        .transition(.move(edge: .trailing))
                    } else {
                        Group {
                            // Content
                            if !remindersService.isAccessGranted {
                                accessDeniedView
                            } else {
                                reminderListView
                            }
                            
                            // Quick Add
                            quickAddView
                                .zIndex(1)
                            
                            // Footer
                            footerView
                                 .background(panelOverlayColor)
                        }
                        .transition(.opacity) // Smoother fade transition for content
                    }
                }

                if assistantEnabled && assistantCoordinator.isPanelPresented && !isSettingsOpen {
                    VStack {
                        Spacer()
                        AssistantPanel(
                            coordinator: assistantCoordinator,
                            theme: appTheme,
                            onClose: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    assistantCoordinator.isPanelPresented = false
                                }
                            },
                            availableHeight: proxy.size.height
                        )
                        .padding(.horizontal, 7)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .zIndex(3)
                }
            }
            .background(MainWindowAccessor(windowCoordinator: windowCoordinator))
            .preferredColorScheme(isWhiteTheme ? .light : appTheme == .dark ? .dark : nil)
            .frame(minWidth: 300, maxWidth: 350, maxHeight: .infinity)
            .onAppear {
                assistantCoordinator.remindersService = remindersService
                prewarmPillWindowIfNeeded()
            }
            .onChange(of: timerService.isFocusMode) { _, isFocus in
                if isFocus {
                    // Enter Focus: show/reuse pill first, then hide main window.
                    if windowCoordinator.pillWindow == nil,
                       let existingPill = NSApp.windows.first(where: { $0.identifier == AppWindowCoordinator.pillWindowIdentifier }) {
                        windowCoordinator.pillWindow = existingPill
                    }
                    
                    if windowCoordinator.pillWindow == nil {
                        openWindow(id: "timer-pill")
                    }
                    
                    // Poll for Pill Window and animate the transition only when it is ready.
                    func animatePillIn(attempts: Int = 0) {
                        Task { @MainActor in
                            if let pillWindow = windowCoordinator.pillWindow {
                                // Ensure window chrome is stripped before first visible frame.
                                pillWindow.isOpaque = false
                                pillWindow.backgroundColor = .clear
                                pillWindow.identifier = AppWindowCoordinator.pillWindowIdentifier
                                pillWindow.titleVisibility = .hidden
                                pillWindow.titlebarAppearsTransparent = true
                                pillWindow.styleMask = [.borderless, .fullSizeContentView]
                                pillWindow.standardWindowButton(.closeButton)?.isHidden = true
                                pillWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
                                pillWindow.standardWindowButton(.zoomButton)?.isHidden = true
                                pillWindow.level = .floating
                                pillWindow.isMovableByWindowBackground = true
                                
                                pillWindow.alphaValue = 0
                                pillWindow.makeKeyAndOrderFront(nil)
                                NSAnimationContext.runAnimationGroup { context in
                                    context.duration = 0.3
                                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                                    pillWindow.animator().alphaValue = 1
                                }
                                
                                let windowsToHide = NSApp.windows.filter { $0 !== pillWindow && $0.isVisible }
                                windowsToHide.forEach { window in
                                    NSAnimationContext.runAnimationGroup { context in
                                        context.duration = 0.2
                                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                                        window.animator().alphaValue = 0
                                    } completionHandler: {
                                        window.orderOut(nil)
                                        window.alphaValue = 1
                                    }
                                }
                            } else if attempts < 20 {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    animatePillIn(attempts: attempts + 1)
                                }
                            }
                        }
                    }
                    animatePillIn()
                    
                } else {
                    // Exit Focus: Cross-fade (Pill OUT, Main IN)
                    let pillWindow = windowCoordinator.pillWindow ?? NSApp.windows.first(where: { $0.identifier == AppWindowCoordinator.pillWindowIdentifier })
                    let mainWindow = windowCoordinator.mainWindow ?? NSApp.windows.first(where: { $0.identifier == AppWindowCoordinator.mainWindowIdentifier })
                    
                    // Prepare Main Window
                    if let main = mainWindow {
                        windowCoordinator.mainWindow = main
                        main.alphaValue = 0
                        main.makeKeyAndOrderFront(nil)
                        main.setIsVisible(true)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.3
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        
                        // Animate Pill OUT
                        pillWindow?.animator().alphaValue = 0
                        
                        // Animate Main IN
                        mainWindow?.animator().alphaValue = 1
                        
                    } completionHandler: {
                        // Keep the same pill window instance and just hide it; this avoids
                        // titlebar/chrome glitches when a brand-new window is recreated.
                        pillWindow?.orderOut(nil)
                        pillWindow?.alphaValue = 1
                    }
                }
            }
            .onChange(of: timerService.activeReminderId) { _, newValue in
                // Only exit focus mode if we are NOT on a break
                if newValue == nil && timerService.isFocusMode && !timerService.isOnBreak {
                    timerService.isFocusMode = false
                }
            }
        }
    }
    
    private func prewarmPillWindowIfNeeded() {
        guard !windowCoordinator.hasPrewarmedPillWindow else { return }
        windowCoordinator.hasPrewarmedPillWindow = true
        
        openWindow(id: "timer-pill")
        
        func waitForPillWindow(attempts: Int = 0) {
            Task { @MainActor in
                if let pillWindow = windowCoordinator.pillWindow {
                    // Keep the prewarmed instance hidden until focus mode is enabled.
                    if !timerService.isFocusMode {
                        pillWindow.orderOut(nil)
                    }
                } else if attempts < 30 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        waitForPillWindow(attempts: attempts + 1)
                    }
                }
            }
        }
        
        waitForPillWindow()
    }
    
    var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // List Selection Menu
                Menu {
                    // Option: Today
                    Button(action: {
                        remindersService.activeListId = nil
                    }) {
                        HStack {
                            if remindersService.activeListId == nil { Image(systemName: "checkmark") }
                            Text("Today")
                        }
                    }
                    
                    Divider()
                    
                    // Option: Specific Lists
                    ForEach(remindersService.lists, id: \.calendarIdentifier) { list in
                        Button(action: {
                            remindersService.activeListId = list.calendarIdentifier
                        }) {
                            HStack {
                                if remindersService.activeListId == list.calendarIdentifier { Image(systemName: "checkmark") }
                                Text(list.title)
                                Image(systemName: "circle.fill")
                                    .foregroundColor(Color(list.cgColor))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(remindersService.activeListId == nil ? "Today" : (remindersService.lists.first(where: { $0.calendarIdentifier == remindersService.activeListId })?.title ?? "List"))
                            .font(.custom("Times New Roman", size: 28))
                            .italic()
                            .foregroundColor(listTitleColor)
                    }
                }
                .menuStyle(.borderlessButton)
                .onChange(of: remindersService.activeListId) { _, _ in
                    remindersService.fetchReminders()
                }

                Spacer()
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation {
                            isSettingsOpen.toggle()
                        }
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(isSettingsOpen ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(.secondary)
                .font(.system(size: 14))
            }
            
            // Stats line
                // Computed Stats
                let activeCount = remindersService.reminders.count
                let completedCount = remindersService.recentCompletedReminders.count
                let totalCount = activeCount + completedCount
                let progress = totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0.0
                
                let totalSeconds = remindersService.reminders.reduce(0.0) { result, reminder in
                    result + (estimateStore.getMetadata(for: reminder.calendarItemIdentifier)?.estimatedDuration ?? 0)
                }
                let hours = Int(totalSeconds) / 3600
                let minutes = (Int(totalSeconds) % 3600) / 60
                
                HStack {
                    if hours > 0 {
                        Text("Est: \(hours)h \(minutes)m")
                    } else if minutes > 0 {
                        Text("Est: \(minutes)m")
                    } else {
                         Text("Est: 0m")
                    }
                    
                    Spacer()
                    Text("\(completedCount)/\(totalCount) Done")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                // Progress bar
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 4)
                    .overlay(
                        GeometryReader { geo in
                            Capsule()
                                .fill(isWhiteTheme ? accentBlue : Color.primary)
                                .frame(width: geo.size.width * CGFloat(progress)) // Real Progress
                        }
                    )
        }
        .padding(.horizontal, 15)
        .padding(.top, 8)
        .padding(.bottom, 12)

    }
    
    var accessDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Access Required")
                .font(.headline)
            Text("Please grant access to Reminders to use this app.")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button("Open System Settings") {
                // In a real app we might deep link or just prompt again
                remindersService.requestAccess()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var reminderListView: some View {
        ScrollView {
            VStack(spacing: 8) {
                if timerService.isOnBreak {
                    breakModeSection
                } else if let activeId = timerService.activeReminderId,
                          let activeTask = remindersService.reminders.first(where: { $0.calendarItemIdentifier == activeId }) {
                    activeTaskSection(activeTask)
                }
                
                standardListSection
            }
            .padding(.vertical)
            .scrollIndicators(.hidden)
            .configureScrollView()
        }
    }
    
    var breakModeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                // Main Content
                VStack(alignment: .leading, spacing: 4) {
                    // 1. Top Label
                    Text("Current Session")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                    
                    // 2. Content Row
                    HStack(alignment: .center, spacing: 0) {
                        Text("☕️ Break")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(alignment: .center, spacing: 12) {
                            // Timer
                            TimerDisplayView(ticker: timerService.ticker, service: timerService)
                                .scaleEffect(isPulsing ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.3), value: isPulsing)
                                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerTaskAlertAnimation"))) { _ in
                                    isPulsing = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isPulsing = false
                                    }
                                }
                            
                            // Skip Break Button
                            Button(action: {
                                timerService.endBreak()
                            }) {
                                Image(systemName: "forward.end.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(height: 32)
                }
                .padding(.top, 12)
                .padding(.bottom, 16)
                .padding(.horizontal, 16)
                
                // Bottom Progress Bar (Visual consistency)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(progressTrackColor)
                            .frame(height: 3)
                        
                        // Dynamic Progress Calculation for Break
                        let progress: Double = {
                            let total = timerService.initialDuration
                            let remaining = timerService.remainingTime
                            let elapsed = total - remaining
                            return total > 0 ? min(max(elapsed / total, 0.0), 1.0) : 0.0
                        }()
                        
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: geo.size.width * CGFloat(progress), height: 3)
                            .shadow(color: .orange.opacity(0.8), radius: 4, x: 0, y: 0) // Orange Glow
                    }
                }
                .frame(height: 3)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(sessionCardFillColor)
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12)) // Clip content to rounded corners
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(cardBorderColor, lineWidth: 1)
            )
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 7)
        .padding(.top, 8)
    }

    func activeTaskSection(_ activeTask: EKReminder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Active task pill
            ZStack(alignment: .bottom) {
                // Main Content
                VStack(alignment: .leading, spacing: 4) {
                    // 1. Top Label
                    Text("Active Task")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                        .opacity(isHoveringActiveTask ? 0 : 1)
                    
                    // 2. Content Row
                    HStack(alignment: .center, spacing: 0) {
                        if isHoveringActiveTask {
                            // HOVER STATE: Full Controls (Swapped in)
                            HStack(alignment: .center, spacing: 16) {
                                // Traffic Light Group
                                HStack(spacing: 12) {
                                    // 1. Close/Stop (Red Traffic Light)
                                    Button(action: { timerService.stopTimer() }) {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 14, height: 14)
                                            .overlay(
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(.black.opacity(0.5))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help("Stop Timer")
                                    
                                    // 2. Pause/Resume (Yellow Traffic Light)
                                    Button(action: { timerService.state == .running ? timerService.pauseTimer() : timerService.resumeTimer() }) {
                                        Circle()
                                            .fill(Color.yellow)
                                            .frame(width: 14, height: 14)
                                            .overlay(
                                                Image(systemName: timerService.state == .running ? "pause.fill" : "play.fill")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(.black.opacity(0.5))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help(timerService.state == .running ? "Pause" : "Resume")
                                    
                                    // 3. Complete (Green Traffic Light)
                                    Button(action: {
                                        guard !isCompletingActive else { return }
                                        withAnimation(completionAnimation) { isCompletingActive = true }
                                        NSSound(named: "Glass")?.play()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + completionCommitDelay) {
                                            remindersService.toggleComplete(activeTask)
                                            timerService.stopTimer()
                                            isCompletingActive = false
                                        }
                                    }) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.green)
                                                .frame(width: 14, height: 14)
                                                .overlay(
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.black.opacity(0.5))
                                                )
                                            ParticleEffectView(trigger: $isCompletingActive)
                                        }
                                        .frame(width: 14, height: 14)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Complete Task")
                                    .scaleEffect(isCompletingActive ? 1.2 : 1.0)
                                }
                                
                                Divider()
                                    .frame(height: 16)
                                    .background(controlDividerColor)
                                
                                // Secondary Actions Group
                                HStack(spacing: 12) {
                                    // 4. Skip Task
                                    Button(action: {
                                        if let next = remindersService.getNextTask(after: activeTask.calendarItemIdentifier) {
                                            let dur = estimateStore.getMetadata(for: next.calendarItemIdentifier)?.estimatedDuration ?? 0
                                            timerService.startTimer(reminderId: next.calendarItemIdentifier, duration: dur)
                                        } else {
                                            timerService.stopTimer()
                                        }
                                    }) {
                                        Image(systemName: "forward.end.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Skip Task")
                                    
                                    // 5. Break
                                    Button(action: { timerService.startBreak(duration: 600) }) {
                                        Image(systemName: "cup.and.saucer.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Take a Break")
                                    
                                    // 6. Extend (Conditional)
                                    if timerService.timesUpTriggered {
                                        Button(action: { timerService.startOvertime() }) {
                                            Image(systemName: "clock.arrow.circlepath")
                                                .font(.system(size: 14))
                                                .foregroundColor(.orange)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Extend Time")
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity)
                        } else {
                            // NORMAL STATE: Title & Timer
                            HStack(alignment: .center, spacing: 8) {
                                Text(activeTask.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                TimerDisplayView(ticker: timerService.ticker, service: timerService)
                            }
                        }
                    }
                    .frame(minHeight: 32) // Flexible height instead of fixed 32
                }
                .padding(.top, 12)
                .padding(.bottom, 16)
                .padding(.horizontal, 16)
                
                // Bottom Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(progressTrackColor)
                            .frame(height: 3)
                        
                        // Simple progress calculation (visual)
                        let progress: Double = {
                            let duration = estimateStore.getMetadata(for: activeTask.calendarItemIdentifier)?.estimatedDuration ?? 1800
                            let elapsed = estimateStore.getMetadata(for: activeTask.calendarItemIdentifier)?.timeSpent ?? 0
                            return duration > 0 ? min(elapsed / duration, 1.0) : 0.0
                        }()
                        
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(progress), height: 3)
                            .shadow(color: .green.opacity(0.8), radius: 4, x: 0, y: 0)
                    }
                }
                .frame(height: 3)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(sessionCardFillColor)
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12)) // Clip content to rounded corners
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(cardBorderColor, lineWidth: 1)
            )
            .overlay(ParticleEffectView(trigger: $isCompletingActive))
            .padding(.horizontal, 8) 
            .onHover { isHovering in withAnimation(.easeInOut(duration: 0.2)) { isHoveringActiveTask = isHovering } }
        }
        .padding(.horizontal, 7).padding(.top, 8)
    }

    var standardListSection: some View {
        LazyVStack(spacing: 8) {
            activeListSection
            completedListSection
        }
    }
    
    var activeListSection: some View {
        ForEach(remindersService.reminders) { reminder in
            if reminder.calendarItemIdentifier != timerService.activeReminderId {
                ReminderRowView(
                    reminder: reminder,
                    isDraggingAppWide: draggedReminder != nil,
                    isBeingDragged: draggedReminder?.calendarItemIdentifier == reminder.calendarItemIdentifier
                )
                .equatable()
                .padding(.horizontal, 7)
                .background(Color.clear)
                .onDrag({
                    self.draggedReminder = reminder
                    return NSItemProvider(object: reminder.calendarItemIdentifier as NSString)
                }, preview: {
                    Color.clear
                        .frame(width: 1, height: 1)
                })
                .onDrop(of: [.text], delegate: ReminderDropDelegate(
                    item: reminder,
                    remindersService: remindersService,
                    draggedItem: $draggedReminder
                ))
            }
        }
        .animation(.default, value: remindersService.reminders)
    }
    
    var completedListSection: some View {
        VStack(spacing: 0) {
            if !remindersService.recentCompletedReminders.isEmpty {
                Divider()
                    .padding(.vertical, 8)
                
                Text("Recently Completed")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                
                ForEach(remindersService.recentCompletedReminders) { reminder in
                    ReminderRowView(reminder: reminder)
                        .equatable()
                        .padding(.horizontal, 7)
                        .opacity(0.7)
                }
            }
        }
    }
    
    var quickAddView: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .foregroundColor(.secondary)
            TextField("Add task...", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .onSubmit {
                    guard !newTaskTitle.isEmpty else { return }
                    let selectedCalendar = remindersService.lists.first(where: { $0.calendarIdentifier == remindersService.activeListId })

                    var dueDate: DateComponents? = nil
                    if remindersService.activeListId == nil {
                         dueDate = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                    }

                    remindersService.createReminder(title: newTaskTitle, in: selectedCalendar, dueDate: dueDate)
                    newTaskTitle = ""
                }

            if assistantEnabled && !assistantCoordinator.isPanelPresented {
                AssistantLauncherButton(
                    isOpen: assistantCoordinator.isPanelPresented,
                    action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            assistantCoordinator.togglePanel()
                        }
                    },
                    theme: appTheme
                )
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(quickAddFillColor)

                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
                    .opacity(quickAddMaterialOpacity)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(quickAddBorderColor, lineWidth: 1)
        )
        .padding(.horizontal, 7)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
    
    var footerView: some View {
        VStack(spacing: 0) {
            Divider()
            // FOOTER - Focus Mode Toggle
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        if !timerService.isFocusMode && timerService.activeReminderId == nil {
                             // Auto-start first task if available
                             if let firstTask = remindersService.reminders.first {
                                 let metadata = estimateStore.getMetadata(for: firstTask.calendarItemIdentifier)
                                 let duration = metadata?.estimatedDuration ?? 0 // Default to 0 (stopwatch) if no estimate
                                 timerService.startTimer(reminderId: firstTask.calendarItemIdentifier, duration: duration)
                             }
                        }
                        timerService.isFocusMode.toggle()
                    }
                }) {
                    HStack {
                        Image(systemName: timerService.isFocusMode ? "list.bullet" : "viewfinder")
                        Text(timerService.isFocusMode ? "Exit Focus" : "Focus Mode")
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 14))
                    .foregroundColor(focusForegroundColor)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        focusButtonBackground
                    )
                    .shadow(color: isHoveringFocusButton ? focusGlowColor : Color.clear, radius: 10, x: 0, y: 0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: focusStrokeGradient),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
                    .scaleEffect(timerService.isFocusMode ? 0.95 : 1.0) // Subtle press effect state
                    .onHover { hover in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHoveringFocusButton = hover
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 7)
            }
            .padding(.vertical, 12)
        }
    }
    
    @ViewBuilder
    private var focusButtonBackground: some View {
        if isWhiteTheme {
            RoundedRectangle(cornerRadius: 16)
                .fill(focusFillColor)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thinMaterial)
                
                RoundedRectangle(cornerRadius: 16)
                    .fill(focusFillColor)
                
                if appTheme == .glass {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                }
            }
        }
    }
}

private struct MainWindowAccessor: NSViewRepresentable {
    let windowCoordinator: AppWindowCoordinator
    
    final class Coordinator: NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if SettingsStore().quitOnClose {
                NSApp.terminate(nil)
                return false
            }
            return true
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    private func configureWindow(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.identifier = AppWindowCoordinator.mainWindowIdentifier
        window.delegate = coordinator
        windowCoordinator.mainWindow = window
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(view.window, coordinator: context.coordinator)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(nsView.window, coordinator: context.coordinator)
        }
    }
}

struct ReminderDropDelegate: DropDelegate {
    let item: EKReminder
    let remindersService: RemindersService
    @Binding var draggedItem: EKReminder?
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        
        if draggedItem != item {
            guard let from = remindersService.reminders.firstIndex(where: { $0.calendarItemIdentifier == draggedItem.calendarItemIdentifier }),
                  let to = remindersService.reminders.firstIndex(where: { $0.calendarItemIdentifier == item.calendarItemIdentifier }) 
            else { return }
            
            if remindersService.reminders[to].calendarItemIdentifier != draggedItem.calendarItemIdentifier {
                withAnimation {
                    remindersService.moveInMemory(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
                }
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        remindersService.commitSortOrder()
        self.draggedItem = nil
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// Optimization: Isolated View for Time Display to prevent SideStripView redraws
struct TimerDisplayView: View {
    @ObservedObject var ticker: TimeTicker
    @ObservedObject var service: TimerService // To access isOvertime/active state for formatting
    @AppStorage("appTheme") private var appTheme: AppTheme = .glass

    var body: some View {
        // Optimization: Do not render/update if app is in Focus Mode (Pill is active) to save CPU
        if !service.isFocusMode {
            Text(service.formattedTime())
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(timerColor)
                .contentTransition(.numericText(countsDown: !service.isStopwatch && !service.isOvertime))
                .animation(.snappy, value: service.formattedTime())
                .fixedSize()
        }
    }

    private var timerColor: Color {
        if service.isOvertime { return .orange }
        if appTheme == .white { return Color.black.opacity(0.85) }
        if appTheme == .dark { return .white }
        return .primary  // glass: adapts to system appearance (dark mode = white, light mode = dark)
    }
}
