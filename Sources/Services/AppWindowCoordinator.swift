import AppKit
import SwiftUI
import Foundation
import Combine

// NSPanel subclass that can always become key (required for text input in borderless panels)
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// NSHostingView subclass that accepts the first mouse click even when the window is not key.
// Without this, clicking a button in a non-key panel just activates the window; the action doesn't fire.
class KeyableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The two shapes the app's one window takes.
///
/// `.normal` is the app's home: resizable, standard title bar, Lists and
/// Planning. `.strip` is the 350pt edge-pinned column that focus mode uses.
enum MainWindowMode {
    case normal
    case strip
}

/// Everything about the main window's chrome, in one place.
///
/// Both modes are applied here rather than split across `HelpyApp` and the
/// views, for the same reason `PillWindowStyle` exists: two places setting half
/// a window's style is how a window ends up in a state neither of them intended.
///
/// Both masks keep `.titled`. `NSWindow.canBecomeKey` is read-only and returns
/// false for a `.borderless` window, so a borderless main window would drop
/// every keystroke aimed at the quick-add field.
enum MainWindowStyle {
    static let normalMinSize = NSSize(width: 900, height: 620)
    static let stripWidth: CGFloat = 350

    /// The width the window is pinned to, or nil when it may be sized freely.
    /// The window's delegate reads this to refuse a resize outright: the style
    /// mask and minSize/maxSize are both reapplied by SwiftUI whenever the
    /// scene's root view is rebuilt, so neither of them can hold the strip on
    /// its own. A delegate that declines the new size cannot be overruled.
    private(set) static var lockedWidth: CGFloat?

    static func apply(_ mode: MainWindowMode, to window: NSWindow, settings: SettingsStore = SettingsStore()) {
        switch mode {
        case .normal:
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.level = .normal
            window.collectionBehavior = [.fullScreenPrimary]
            window.isMovable = true
            window.isMovableByWindowBackground = false
            window.minSize = normalMinSize
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            lockedWidth = nil
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = false

        case .strip:
            // .miniaturizable is here for the strip header's own minimise
            // button, not for chrome: the traffic lights stay hidden below, but
            // `miniaturize(_:)` is a no-op on a window whose mask omits it.
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovable = false
            window.isMovableByWindowBackground = false
            window.minSize = NSSize(width: stripWidth, height: 380)
            // Removing .resizable is not enough on its own: SwiftUI reapplies
            // .windowResizability whenever the scene's root view is rebuilt —
            // which changing the accent does — and hands the strip its resize
            // handles back. A hard max width is the constraint it cannot undo.
            window.maxSize = NSSize(width: stripWidth, height: CGFloat.greatestFiniteMagnitude)
            lockedWidth = stripWidth
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            pinToEdge(window, settings: settings)
        }
    }

    /// The strip's frame: bottom-anchored on the chosen side, inset by a margin.
    static func pinToEdge(_ window: NSWindow, settings: SettingsStore = SettingsStore()) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 15
        let fullHeight = visible.height - (margin * 2)
        let height = min(max(fullHeight * settings.panelHeightMode.fraction, 380), fullHeight)
        // Re-asserted on every repin, not just on entering the mode: this runs
        // after appearance and position changes, which is exactly when the
        // clamp is most likely to have been overwritten.
        window.maxSize = NSSize(width: stripWidth, height: CGFloat.greatestFiniteMagnitude)

        let x = settings.panelPosition == .left
            ? visible.minX + margin
            : visible.maxX - stripWidth - margin

        window.setFrame(
            NSRect(x: x, y: visible.minY + margin, width: stripWidth, height: height),
            display: true,
            animate: false
        )
    }

    /// Centres a normal window at a comfortable default the first time it is
    /// shown; a window the user has already sized keeps its frame.
    static func restoreNormalFrame(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = min(max(normalMinSize.width, visible.width * 0.72), visible.width - 40)
        let height = min(max(normalMinSize.height, visible.height * 0.78), visible.height - 40)
        window.setFrame(
            NSRect(
                x: visible.midX - width / 2,
                y: visible.midY - height / 2,
                width: width,
                height: height
            ),
            display: true,
            animate: false
        )
    }
}

@MainActor
final class AppWindowCoordinator: ObservableObject {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("focus.main.window")
    static let pillWindowIdentifier = NSUserInterfaceItemIdentifier("focus.pill.window")

    weak var mainWindow: NSWindow?

    /// The pill is a panel this coordinator creates and owns — never a SwiftUI
    /// `Window` scene. A scene window belongs to SwiftUI, which KVO-observes it;
    /// reaching back in from the view to restyle it wrote to those observed
    /// properties from inside SwiftUI's own update pass and segfaulted the app
    /// every time focus mode started (`_NSSetBoolValueAndNotify`,
    /// "os_unfair_lock is corrupt"). Owning the panel means its chrome is set
    /// once, at creation, before anything observes it.
    private(set) var pillPanel: NSPanel?
    private var pillHosting: KeyableHostingView<AnyView>?
    private let pillTopAnchor = PillWindowTopAnchor()

    /// Whether the cursor is over the pill, which is what swaps its controls in.
    ///
    /// Tracked here, from mouse events, rather than by SwiftUI's `.onHover`:
    /// hover tracking areas only fire while Helpy is the frontmost app, and
    /// during a focus session it never is. The pill's controls were therefore
    /// unreachable in exactly the situation the pill exists for.
    @Published private(set) var isPillHovered = false
    private var pillHoverMonitors: [Any] = []

    private(set) var mainWindowMode: MainWindowMode = .normal
    /// The normal window's frame, kept across a trip into strip mode so coming
    /// back does not throw away a window the user has sized and placed.
    private var normalFrame: NSRect?
    private var hasSizedNormalWindow = false

    /// Switches the one main window between the app's home and the side strip.
    func setMainWindowMode(_ mode: MainWindowMode, animated: Bool = true) {
        guard let window = mainWindow
            ?? NSApp.windows.first(where: { $0.identifier == Self.mainWindowIdentifier })
        else { return }
        mainWindow = window

        if mode == mainWindowMode, mode == .normal, hasSizedNormalWindow { return }

        if mode == .strip && mainWindowMode == .normal {
            normalFrame = window.frame
        }

        mainWindowMode = mode
        MainWindowStyle.apply(mode, to: window)

        switch mode {
        case .normal:
            if let frame = normalFrame, hasSizedNormalWindow {
                window.setFrame(frame, display: true, animate: animated)
            } else {
                MainWindowStyle.restoreNormalFrame(window)
                hasSizedNormalWindow = true
            }
        case .strip:
            MainWindowStyle.pinToEdge(window)
        }

        window.makeKeyAndOrderFront(nil)
    }

    /// Re-pins the strip after a settings change (side or height).
    func repinStripIfNeeded() {
        guard mainWindowMode == .strip, let window = mainWindow else { return }
        MainWindowStyle.pinToEdge(window)
    }

    // Service references set by HelpyApp — used for the menu bar panel.
    weak var timerService: TimerService? {
        didSet { bindTimerService() }
    }
    weak var remindersService: RemindersService?
    weak var subtaskStore: SubtaskStore?
    weak var estimateStore: EstimateStore?

    private var statusItem: NSStatusItem?
    // Panel + hosting view are created once and reused: tearing the panel down
    // on every close deallocates an NSWindow, which AppKit reports as a window
    // close — with all other windows hidden (focus mode) that read as
    // "last window closed" and used to terminate the whole app.
    private var menuBarPanel: NSPanel?
    private var menuBarHosting: KeyableHostingView<MenuBarPanelView>?
    private var clickOutsideMonitor: Any?
    // The dropdown grows when the subtasks section opens. AppKit anchors a
    // resizing window at its bottom-left origin, which would slide the panel
    // down away from the menu bar; this keeps its TOP edge pinned instead.
    private var menuBarPanelTopY: CGFloat = 0
    private var menuBarResizeObserver: NSObjectProtocol?
    private var repinningMenuBarPanel = false
    private var globalClickMonitor: Any?
    private var timerCancellables: Set<AnyCancellable> = []
    private(set) var displayMode: PillDisplayMode = .floatingPill

    /// Keeps the status item timer text in sync with the ticker.
    /// The App scene body deliberately does not re-evaluate on ticker changes
    /// (TimeTicker is decoupled from TimerService for that reason), so an
    /// onChange in HelpyApp never fires — the title must be driven from here.
    private func bindTimerService() {
        timerCancellables.removeAll()
        guard let timerService else { return }

        timerService.ticker.$remainingTime
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMenuBarTitle() }
            .store(in: &timerCancellables)

        // isFocusMode / state / isOnBreak publish on willSet — receive(on:) defers
        // the refresh until the new value is applied.
        timerService.$isFocusMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMenuBarTitle() }
            .store(in: &timerCancellables)

        timerService.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMenuBarTitle() }
            .store(in: &timerCancellables)

        // The focus transition is driven from here, not from a view.
        // A session can be started from the list board, where the side strip
        // that used to own this onChange is not mounted at all — so the pill
        // never appeared and play looked dead.
        timerService.$isFocusMode
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isFocus in
                guard let self else { return }
                if isFocus {
                    self.enterFocusPresentation()
                } else {
                    self.exitFocusPresentation()
                }
            }
            .store(in: &timerCancellables)

        // Completing or stopping the last task leaves focus mode wherever the
        // session was started from. A break has no active task by design, so
        // it keeps the pill up.
        timerService.$activeReminderId
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let timerService = self?.timerService,
                      timerService.activeReminderId == nil,
                      timerService.isFocusMode,
                      !timerService.isOnBreak else { return }
                timerService.isFocusMode = false
            }
            .store(in: &timerCancellables)
    }

    func refreshMenuBarTitle() {
        guard let button = statusItem?.button else { return }
        guard displayMode == .menuBarIcon,
              let timerService,
              timerService.isFocusMode,
              timerService.activeReminderId != nil || timerService.isOnBreak else {
            button.title = ""
            return
        }
        button.title = " \(timerService.formattedTime())"
    }

    /// Create the persistent Helpy menu bar icon. Call once after service refs are set.
    /// The icon is always visible regardless of display mode.
    func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        item.button?.image = Self.menuBarIconImage(from: helperResourceBundle())

        item.button?.imagePosition = .imageLeft
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseDown])
        statusItem = item
    }

    func applyDisplayMode(_ mode: PillDisplayMode) {
        displayMode = mode
        refreshMenuBarTitle()

        // Handle switching modes while focus is already active.
        guard let timerService, timerService.isFocusMode else { return }
        switch mode {
        case .floatingPill:
            showPill()
        case .menuBarIcon:
            hidePill()
        }
    }

    // MARK: - Floating Pill

    /// Builds the pill panel. All of its chrome is set here, before the panel
    /// has a content view and before anything can observe it — see the note on
    /// `pillPanel`. Nothing outside this method may change the style mask,
    /// opacity, or level of a live pill.
    static func makePillPanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 44),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        // Depth comes from the window-server shadow: it traces the RENDERED
        // shape of this transparent panel, outside its bounds, so it can never
        // be clipped into a rectangle the way an in-window shadow was.
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.identifier = pillWindowIdentifier
        return panel
    }

    /// Shows the pill, creating it on first use. Safe to call repeatedly.
    func showPill() {
        guard displayMode == .floatingPill else { return }
        guard let timerService, let remindersService, let subtaskStore, let estimateStore else { return }

        let content = AnyView(
            FloatingPillView()
                .environmentObject(timerService)
                .environmentObject(remindersService)
                .environmentObject(estimateStore)
                .environmentObject(self)
                .environmentObject(subtaskStore)
        )

        let panel: NSPanel
        if let existing = pillPanel, let hosting = pillHosting {
            panel = existing
            hosting.rootView = content
        } else {
            panel = Self.makePillPanel()
            let hosting = KeyableHostingView(rootView: content)
            // Without this the panel is sized once, at open, and the subtasks
            // section unfolds into a window that never grew to hold it.
            hosting.sizingOptions = [.preferredContentSize]
            panel.contentView = hosting
            panel.setFrameAutosaveName("HelpyFloatingPill")
            if panel.frame.origin == .zero { centerPillNearBottom(panel) }
            pillPanel = panel
            pillHosting = hosting
        }

        pillTopAnchor.attach(to: panel)
        panel.orderFront(nil)
        startPillHoverTracking(panel)
    }

    func hidePill() {
        stopPillHoverTracking()
        pillPanel?.orderOut(nil)
    }

    private func startPillHoverTracking(_ panel: NSPanel) {
        stopPillHoverTracking()

        // Global catches the cursor while another app is frontmost; local
        // catches it while Helpy is. A global monitor never sees this app's
        // own events, so both are needed to cover the whole screen.
        //
        // These fire on every mouse move, hundreds of times a second while the
        // cursor is travelling. AppKit already delivers them on the main
        // thread, so assume the isolation rather than spawning a Task per
        // event — that allocation and actor hop was pure overhead.
        let matching: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: matching) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePillHover() }
        } {
            pillHoverMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: matching) { [weak self] event in
            MainActor.assumeIsolated { self?.updatePillHover() }
            return event
        } {
            pillHoverMonitors.append(local)
        }
        _ = panel
        updatePillHover()
    }

    private func stopPillHoverTracking() {
        pillHoverMonitors.forEach(NSEvent.removeMonitor)
        pillHoverMonitors.removeAll()
        isPillHovered = false
    }

    private func updatePillHover() {
        guard let panel = pillPanel, panel.isVisible else {
            if isPillHovered { isPillHovered = false }
            return
        }
        // Both are bottom-left screen coordinates, so they compare directly.
        let inside = panel.frame.contains(NSEvent.mouseLocation)
        if inside != isPillHovered { isPillHovered = inside }
    }

    private func centerPillNearBottom(_ panel: NSPanel) {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        var frame = panel.frame
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.minY + 120
        panel.setFrame(frame, display: false)
    }

    // MARK: - Focus Mode Presentation

    /// Focus mode: the pill takes over and the app's windows fade away.
    ///
    /// Both directions live here so no view can hide a window the coordinator
    /// then tries to raise. Menu-bar mode has no pill — the timer lives in the
    /// status item — so it only fades the windows out.
    func enterFocusPresentation() {
        if displayMode == .floatingPill { showPill() }
        let pill = pillPanel
        let toHide = NSApp.windows.filter { $0 !== pill && $0.isVisible }
        fadeOut(toHide)
    }

    func exitFocusPresentation() {
        let main = mainWindow ?? NSApp.windows.first(where: { $0.identifier == Self.mainWindowIdentifier })
        if let main {
            mainWindow = main
            main.alphaValue = 0
            main.setIsVisible(true)
            main.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pillPanel?.animator().alphaValue = 0
            main?.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in
                // orderOut, never close: the panel instance is reused, and
                // closing the last visible window reads as "quit" to AppKit.
                self?.pillPanel?.orderOut(nil)
                self?.pillPanel?.alphaValue = 1
            }
        }
    }

    private func fadeOut(_ windows: [NSWindow]) {
        for window in windows {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
                window.alphaValue = 1
            }
        }
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseDown {
            // Right-click: show quit menu
            let menu = NSMenu()
            let quitItem = menu.addItem(
                withTitle: "Quit Helpy",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
            quitItem.target = NSApp
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            // Reset menu so left-click doesn't also show it
            DispatchQueue.main.async { [weak self] in
                self?.statusItem?.menu = nil
            }
        } else {
            toggleMenuBarPanel()
        }
    }

    // MARK: - Menu Bar Panel

    func toggleMenuBarPanel() {
        if let panel = menuBarPanel, panel.isVisible {
            hideMenuBarPanel()
        } else {
            showMenuBarPanel()
        }
    }

    func showMenuBarPanel() {
        guard let timerService = timerService,
              let remindersService = remindersService,
              let subtaskStore = subtaskStore else { return }

        let panelWidth: CGFloat = 300
        let cornerRadius: CGFloat = 16

        let content = MenuBarPanelView(
            timerService: timerService,
            remindersService: remindersService,
            subtaskStore: subtaskStore,
            onClose: { [weak self] in self?.hideMenuBarPanel() }
        )

        let panel: NSPanel
        let hostingView: KeyableHostingView<MenuBarPanelView>
        if let existingPanel = menuBarPanel, let existingHosting = menuBarHosting {
            panel = existingPanel
            hostingView = existingHosting
            hostingView.rootView = content
        } else {
            // KeyablePanel: borderless panels can't become key by default, which would
            // make the "Add subtask…" text field ignore all typing.
            panel = KeyablePanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 160),
                styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.becomesKeyOnlyIfNeeded = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.hidesOnDeactivate = false

            hostingView = KeyableHostingView(rootView: content)
            // Without this the panel is sized once, at open, and the subtasks
            // section unfolds into a window that never grew to hold it.
            hostingView.sizingOptions = [.preferredContentSize]
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = cornerRadius
            hostingView.layer?.masksToBounds = false
            hostingView.layer?.backgroundColor = .clear
            panel.contentView = hostingView

            menuBarPanel = panel
            menuBarHosting = hostingView
        }

        // Position below the status item button, clamped to the status item's own screen
        // (NSScreen.main is the *key window's* screen — wrong on multi-monitor setups).
        if let button = statusItem?.button, let buttonWindow = button.window {
            let buttonBounds = button.convert(button.bounds, to: nil)
            let screenFrame = buttonWindow.convertToScreen(buttonBounds)
            let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame
            let x = max(
                visible?.minX ?? 0,
                min(screenFrame.midX - panelWidth / 2,
                    (visible?.maxX ?? panelWidth) - panelWidth)
            )
            // Size the panel to fit content
            hostingView.layout()
            let fittingHeight = hostingView.fittingSize.height
            let panelHeight = max(fittingHeight, 120)
            let y = screenFrame.minY - panelHeight - 4
            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: false)
            menuBarPanelTopY = y + panelHeight
        }

        observeMenuBarPanelResize(panel)
        panel.orderFront(nil)
        addClickOutsideMonitor()
    }

    func hideMenuBarPanel() {
        // orderOut only — the panel instance is kept and reused (see above).
        menuBarPanel?.orderOut(nil)
        removeClickOutsideMonitor()
    }

    private func observeMenuBarPanelResize(_ panel: NSPanel) {
        guard menuBarResizeObserver == nil else { return }
        menuBarResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.repinMenuBarPanelTop() }
        }
    }

    private func repinMenuBarPanelTop() {
        guard !repinningMenuBarPanel, let panel = menuBarPanel, panel.isVisible else { return }
        var frame = panel.frame
        guard abs(frame.maxY - menuBarPanelTopY) > 0.5 else { return }
        repinningMenuBarPanel = true
        frame.origin.y = menuBarPanelTopY - frame.height
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
        repinningMenuBarPanel = false
    }

    private func addClickOutsideMonitor() {
        clickOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.menuBarPanel else { return event }
            if event.window !== panel {
                self.hideMenuBarPanel()
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hideMenuBarPanel()
        }
    }

    private func removeClickOutsideMonitor() {
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m); clickOutsideMonitor = nil }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
    }

    // MARK: - Helpers

    /// Menu bar icon, explicitly sized for the status bar.
    /// The source PNG is far larger than the bar — without constraining
    /// NSImage.size the status item asks for a slot macOS can't fit, and the
    /// icon silently never appears in the menu bar.
    static func menuBarIconImage(from bundle: Bundle) -> NSImage? {
        var icon: NSImage?
        if let iconURL = bundle.url(forResource: "MenuBarIcon", withExtension: "png"),
           let loaded = NSImage(contentsOf: iconURL) {
            icon = loaded
            // NOT a template. Helpy's mark is the white cat, and a template
            // image gets re-inked black on a light menu bar — which is a
            // different mark. Deliberate tradeoff: on a light wallpaper the
            // white cat is low-contrast.
            icon?.isTemplate = false
        } else {
            // The SF Symbol fallback has no colour of its own, so it should
            // follow the menu bar the normal way.
            icon = NSImage(systemSymbolName: "h.circle", accessibilityDescription: "Helpy")
            icon?.isTemplate = true
        }
        icon?.size = NSSize(width: 18, height: 18)
        return icon
    }

    private func helperResourceBundle() -> Bundle {
        if let url = Bundle.main.url(forResource: "Helpy_Helpy", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.main
    }
}
