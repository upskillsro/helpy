import SwiftUI
import EventKit
import AppKit

struct SideStripView: View {
    /// Set when the strip is focus mode for one list. The strip then shows only
    /// that list's Today bucket — the tier below the board, not a second copy
    /// of it.
    var focusedListId: String? = nil
    /// Called by the back chevron; restores the normal window.
    var onExitFocus: (() -> Void)? = nil

    @EnvironmentObject var remindersService: RemindersService
    @EnvironmentObject var timerService: TimerService
    @EnvironmentObject var estimateStore: EstimateStore
    @EnvironmentObject var windowCoordinator: AppWindowCoordinator
    
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
    @AppStorage("assistantEnabled") private var assistantEnabled: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    private let completionCommitDelay: TimeInterval = 0.18
    private let completionAnimation = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.8, blendDuration: 0.1)

    private var t: HelpyPalette { .forScheme(colorScheme) }

    /// What the strip actually lists. In focus mode that is Today only; the
    /// rest of the list stays on the board where it belongs.
    var visibleReminders: [EKReminder] {
        guard focusedListId != nil else { return remindersService.reminders }
        let week = HelpyWeek()
        return remindersService.reminders.filter { week.bucket(for: $0) == .today }
    }

    private var focusedList: EKCalendar? {
        guard let focusedListId else { return nil }
        return remindersService.lists.first { $0.calendarIdentifier == focusedListId }
    }

    /// The window the header's minimise and close buttons act on. The
    /// coordinator's reference is the one the accessor below installs; the
    /// lookup by identifier is the fallback for the first frame, before that
    /// accessor has run.
    private var stripWindow: NSWindow? {
        windowCoordinator.mainWindow
            ?? NSApp.windows.first { $0.identifier == AppWindowCoordinator.mainWindowIdentifier }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                t.canvas.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    if !isSettingsOpen {
                        headerView
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
                        }
                        .transition(.opacity) // Smoother fade transition for content
                    }
                }

                if assistantEnabled && assistantCoordinator.isPanelPresented && !isSettingsOpen {
                    VStack {
                        Spacer()
                        AssistantPanel(
                            coordinator: assistantCoordinator,
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
            .frame(minWidth: 300, maxWidth: 350, maxHeight: .infinity)
            .onAppear {
                assistantCoordinator.remindersService = remindersService
            }
            // Entering and leaving focus mode is handled by
            // AppWindowCoordinator.bindTimerService(). It used to live here,
            // which meant a session started from the list board — where this
            // view is not mounted — never raised the pill.
        }
    }
    
    
    /// Version B header: the gradient runs full-bleed to the window edges and
    /// sweeps into rounded BOTTOM corners. Everything on it is white, which is
    /// also why the mark is the white cat.
    var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HelpyMark(size: 24)

                headerTitleControl

                Spacer()

                // The strip hides the real traffic lights — they would sit on
                // top of the mark and the title — so minimise and close live
                // here, in the header's own idiom.
                HStack(spacing: 6) {
                    HeaderCircleButton(icon: "minus", help: "Minimize", palette: t) {
                        stripWindow?.miniaturize(nil)
                    }

                    HeaderCircleButton(icon: "xmark", help: "Close", palette: t) {
                        // performClose, not close: it goes through the window's
                        // delegate, which is what honours "quit when closed".
                        stripWindow?.performClose(nil)
                    }

                    HeaderCircleButton(
                        icon: "gearshape",
                        help: "Settings",
                        palette: t,
                        isActive: isSettingsOpen
                    ) {
                        withAnimation { isSettingsOpen.toggle() }
                    }
                }
            }

            // Stats line
            let activeCount = visibleReminders.count
            let completedCount = remindersService.recentCompletedReminders.count
            let totalCount = activeCount + completedCount
            let progress = totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0.0

            let totalSeconds = visibleReminders.reduce(0.0) { result, reminder in
                result + (estimateStore.getMetadata(for: reminder.calendarItemIdentifier)?.estimatedDuration ?? 0)
            }
            let hours = Int(totalSeconds) / 3600
            let minutes = (Int(totalSeconds) % 3600) / 60

            VStack(alignment: .leading, spacing: 7) {
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
                .font(.inter(size: 11, weight: .medium))
                .foregroundStyle(t.onAccent.opacity(0.82))

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.28))
                        Capsule()
                            .fill(t.onAccent)
                            .frame(width: max(0, geo.size.width * CGFloat(progress)))
                    }
                }
                .frame(height: 4)
                .animation(.easeOut(duration: 0.25), value: progress)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 15)
        // The window draws its own title bar area, so the gradient is told to
        // bleed upward past it — and only upward. The bottom edge stays exactly
        // where the header's frame ends, which is where the rounded sweep sits.
        .background(
            HelpyHeaderBackground(palette: t)
                .ignoresSafeArea(edges: .top)
        )
    }
    
    /// In focus mode the strip is scoped by where you came from, so the title is
    /// the list you focused plus a way back to its board. Outside focus mode it
    /// keeps the list picker.
    @ViewBuilder
    var headerTitleControl: some View {
        if let focusedListId {
            HStack(spacing: 8) {
                Button {
                    onExitFocus?()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(t.onAccent)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Back to the board")

                VStack(alignment: .leading, spacing: 0) {
                    Text(focusedList?.title ?? "List")
                        .font(.inter(size: 12, weight: .semibold))
                        .foregroundStyle(t.onAccent.opacity(0.85))
                        .lineLimit(1)
                    Text("Today")
                        .font(.inter(size: 19, weight: .bold))
                        .foregroundStyle(t.onAccent)
                }
            }
            .onAppear { scopeServiceToFocusedList(focusedListId) }
            .onChange(of: focusedListId) { _, newValue in
                scopeServiceToFocusedList(newValue)
            }
        } else {
            Menu {
                Button {
                    remindersService.activeListId = nil
                } label: {
                    HStack {
                        if remindersService.activeListId == nil { Image(systemName: "checkmark") }
                        Text("Today")
                    }
                }

                Divider()

                ForEach(remindersService.lists, id: \.calendarIdentifier) { list in
                    Button {
                        remindersService.activeListId = list.calendarIdentifier
                    } label: {
                        HStack {
                            if remindersService.activeListId == list.calendarIdentifier {
                                Image(systemName: "checkmark")
                            }
                            Text(list.title)
                            Image(systemName: "circle.fill")
                                .foregroundColor(Color(list.cgColor))
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(remindersService.activeListId == nil
                         ? "Today"
                         : (remindersService.lists.first(where: { $0.calendarIdentifier == remindersService.activeListId })?.title ?? "List"))
                        .font(.inter(size: 19, weight: .bold))
                        .foregroundStyle(t.onAccent)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(t.onAccent.opacity(0.7))
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .onChange(of: remindersService.activeListId) { _, _ in
                remindersService.fetchReminders()
            }
        }
    }

    /// Point the service at the focused list so the strip, the timer and the
    /// pill all read the same set of tasks.
    private func scopeServiceToFocusedList(_ listId: String?) {
        guard let listId, remindersService.activeListId != listId else { return }
        remindersService.activeListId = listId
        remindersService.fetchReminders()
    }

    var accessDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundStyle(t.muted)
            Text("Access Required")
                .font(.inter(size: 16, weight: .semibold))
                .foregroundStyle(t.ink)
            Text("Please grant access to Reminders to use this app.")
                .multilineTextAlignment(.center)
                .font(.inter(size: 12))
                .foregroundStyle(t.muted)
                .padding(.horizontal)

            Button("Open System Settings") {
                // In a real app we might deep link or just prompt again
                remindersService.requestAccess()
            }
            .buttonStyle(HelpyPrimaryButtonStyle(palette: t))
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
            .padding(.top, 14)
            .padding(.bottom, 10)
            // Has to be applied to the CONTENT: from outside the ScrollView,
            // `enclosingScrollView` is nil and the config silently no-ops.
            .configureScrollView()
        }
        // `.scrollIndicators` has to sit on the ScrollView itself — applied to
        // the content it did nothing and the overlay scroller kept painting over
        // the cards' right edge.
        .scrollIndicators(.hidden)
        // The list runs straight into the quick-add field, so the last row used
        // to be sliced off mid-card. Fade the final few points instead.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.955),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }
    
    var breakModeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                // Main Content
                VStack(alignment: .leading, spacing: 4) {
                    // 1. Top Label
                    Text("Current Session")
                        .font(.inter(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1.0)
                        .foregroundStyle(t.muted2)
                    
                    // 2. Content Row
                    HStack(alignment: .center, spacing: 0) {
                        Text("☕️ Break")
                            .font(.inter(size: 15, weight: .medium))
                            .foregroundStyle(t.ink)
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
                            PillControlButton(icon: "forward.end.fill", help: "Skip Break", palette: t) {
                                timerService.endBreak()
                            }
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
                            .fill(t.railTrack)
                            .frame(height: 3)

                        // Dynamic Progress Calculation for Break
                        let progress: Double = {
                            let total = timerService.initialDuration
                            let remaining = timerService.remainingTime
                            let elapsed = total - remaining
                            return total > 0 ? min(max(elapsed / total, 0.0), 1.0) : 0.0
                        }()

                        Rectangle()
                            .fill(LinearGradient(colors: [t.warm, t.warm.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(progress), height: 3)
                    }
                }
                .frame(height: 3)
            }
            .background(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .fill(t.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(t.line, lineWidth: 1)
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
                        .font(.inter(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1.0)
                        .foregroundStyle(t.muted2)
                        .opacity(isHoveringActiveTask ? 0 : 1)
                    
                    // 2. Content Row
                    HStack(alignment: .center, spacing: 0) {
                        if isHoveringActiveTask {
                            // HOVER STATE: Full Controls (Swapped in)
                            // Same monochrome control set as the floating pill and the
                            // menu bar dropdown, so one hover language runs everywhere.
                            HStack(alignment: .center, spacing: 2) {
                                PillControlButton(icon: "xmark", help: "Stop Timer", tone: .danger, palette: t) {
                                    timerService.stopTimer()
                                }

                                PillControlButton(
                                    icon: timerService.state == .running ? "pause.fill" : "play.fill",
                                    help: timerService.state == .running ? "Pause" : "Resume",
                                    palette: t
                                ) {
                                    timerService.state == .running ? timerService.pauseTimer() : timerService.resumeTimer()
                                }

                                PillControlButton(icon: "checkmark", help: "Complete Task", tone: .go, palette: t) {
                                    guard !isCompletingActive else { return }
                                    withAnimation(completionAnimation) { isCompletingActive = true }
                                    NSSound(named: "Glass")?.play()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + completionCommitDelay) {
                                        remindersService.toggleComplete(activeTask)
                                        timerService.stopTimer()
                                        isCompletingActive = false
                                    }
                                }
                                .scaleEffect(isCompletingActive ? 1.15 : 1.0)

                                PillDivider(color: t.line)
                                    .padding(.horizontal, 5)

                                if timerService.timesUpTriggered {
                                    PillControlButton(icon: "clock.arrow.circlepath", help: "Extend Time", isActive: true, palette: t) {
                                        timerService.startOvertime()
                                    }
                                }

                                PillControlButton(icon: "forward.end.fill", help: "Skip Task", palette: t) {
                                    if let next = remindersService.getNextTask(after: activeTask.calendarItemIdentifier) {
                                        let dur = estimateStore.getMetadata(for: next.calendarItemIdentifier)?.estimatedDuration ?? 0
                                        timerService.startTimer(reminderId: next.calendarItemIdentifier, duration: dur)
                                    } else {
                                        timerService.stopTimer()
                                    }
                                }

                                PillControlButton(icon: "cup.and.saucer.fill", help: "Take a Break", palette: t) {
                                    timerService.startBreak()
                                }
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            // NORMAL STATE: Title & Timer
                            HStack(alignment: .center, spacing: 8) {
                                Text(activeTask.title)
                                    .font(.inter(size: 15, weight: .medium))
                                    .foregroundStyle(t.ink)
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
                            .fill(t.railTrack)
                            .frame(height: 3)

                        // Simple progress calculation (visual)
                        let progress: Double = {
                            let duration = estimateStore.getMetadata(for: activeTask.calendarItemIdentifier)?.estimatedDuration ?? 1800
                            let elapsed = estimateStore.getMetadata(for: activeTask.calendarItemIdentifier)?.timeSpent ?? 0
                            return duration > 0 ? min(elapsed / duration, 1.0) : 0.0
                        }()

                        Rectangle()
                            .fill(t.rail)
                            .frame(width: geo.size.width * CGFloat(progress), height: 3)
                    }
                }
                .frame(height: 3)
            }
            .background(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .fill(t.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(t.line, lineWidth: 1)
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
        ForEach(visibleReminders) { reminder in
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
        .animation(.default, value: visibleReminders)
    }
    
    var completedListSection: some View {
        VStack(spacing: 0) {
            if !remindersService.recentCompletedReminders.isEmpty {
                Rectangle()
                    .fill(t.line)
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Text("Recently Completed")
                    .font(.inter(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1.0)
                    .foregroundStyle(t.muted2)
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
    
    /// Quick add has to put the task where the strip can show it. The strip
    /// lists Today only, and in focus mode a list is always active — so the old
    /// "date it only when no list is active" rule stamped nothing, the task
    /// landed in Backlog, and pressing Return looked like it did nothing.
    private func submitQuickAdd() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let selectedCalendar = remindersService.lists.first(where: { $0.calendarIdentifier == remindersService.activeListId })

        var dueDate: DateComponents? = nil
        if focusedListId != nil || remindersService.activeListId == nil {
            dueDate = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        }

        remindersService.createReminder(title: title, in: selectedCalendar, dueDate: dueDate)
        newTaskTitle = ""
    }

    var quickAddView: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.muted)
            TextField("Add task...", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.inter(size: 13))
                .foregroundStyle(t.ink)
                .onSubmit { submitQuickAdd() }

            if assistantEnabled && !assistantCoordinator.isPanelPresented {
                AssistantLauncherButton(
                    isOpen: assistantCoordinator.isPanelPresented,
                    action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            assistantCoordinator.togglePanel()
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                .fill(t.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                .strokeBorder(t.fieldBorder, lineWidth: 1)
        )
        .padding(.horizontal, 15)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
    
    var footerView: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(t.line)
                .frame(height: 1)
            // FOOTER - Focus Mode Toggle
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        if !timerService.isFocusMode && timerService.activeReminderId == nil {
                             // Auto-start the first visible task — in focus mode
                             // that is the first thing due today, not the first
                             // thing in the whole list.
                             if let firstTask = visibleReminders.first {
                                 let metadata = estimateStore.getMetadata(for: firstTask.calendarItemIdentifier)
                                 let duration = metadata?.estimatedDuration ?? 0 // Default to 0 (stopwatch) if no estimate
                                 timerService.startTimer(reminderId: firstTask.calendarItemIdentifier, duration: duration)
                             }
                        }
                        timerService.isFocusMode.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: timerService.isFocusMode ? "list.bullet" : "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(timerService.isFocusMode ? "Exit Timer" : "Start Timer")
                            .font(.inter(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(t.onAccent)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background(focusButtonBackground)
                    .contentShape(Rectangle())
                    .scaleEffect(isHoveringFocusButton ? 1.015 : 1.0)
                    .onHover { hover in
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isHoveringFocusButton = hover
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 15)
            }
            .padding(.vertical, 12)
        }
    }
    
    private var focusButtonBackground: some View {
        // The one saturated surface in the body — it wears the header's exact
        // colour so the eye reads header and primary action as the same accent.
        RoundedRectangle(cornerRadius: HelpyMetrics.buttonCornerRadius, style: .continuous)
            .fill(timerService.isFocusMode ? t.warm : t.rail)
    }
}

/// A control on the strip's gradient header: a white translucent disc that
/// brightens on hover. One type for all three so minimise, close and settings
/// read as one cluster rather than three separately-tuned buttons.
private struct HeaderCircleButton: View {
    let icon: String
    let help: String
    let palette: HelpyPalette
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.onAccent)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(Color.white.opacity(isHovering || isActive ? 0.22 : 0.12))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.13)) { isHovering = hover }
        }
    }
}

private struct MainWindowAccessor: NSViewRepresentable {
    let windowCoordinator: AppWindowCoordinator
    
    /// Installs the app's own window delegate rather than one of its own.
    /// This runs on every SwiftUI update, so a private delegate here quietly
    /// displaced the app's — taking the strip's fixed width with it.
    private func configureWindow(_ window: NSWindow?) {
        guard let window else { return }
        window.identifier = AppWindowCoordinator.mainWindowIdentifier
        window.delegate = MainWindowCloseDelegate.shared
        windowCoordinator.mainWindow = window
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(nsView.window)
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
    @Environment(\.colorScheme) private var colorScheme

    private var t: HelpyPalette { .forScheme(colorScheme) }

    var body: some View {
        // Optimization: Do not render/update if app is in Focus Mode (Pill is active) to save CPU
        if !service.isFocusMode {
            Text(service.formattedTime())
                .font(.inter(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(service.isOvertime ? t.warm : t.ink)
                .contentTransition(.numericText(countsDown: !service.isStopwatch && !service.isOvertime))
                .animation(.snappy, value: service.formattedTime())
                .fixedSize()
        }
    }
}
