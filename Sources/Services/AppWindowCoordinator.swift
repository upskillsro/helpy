import AppKit
import SwiftUI
import Foundation
import Combine

// NSPanel subclass that can always become key (required for text input in borderless panels)
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// NSHostingView subclass that accepts the first mouse click even when the window is not key.
// Without this, clicking a button in a non-key panel just activates the window; the action doesn't fire.
private class KeyableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppWindowCoordinator: ObservableObject {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("focus.main.window")
    static let pillWindowIdentifier = NSUserInterfaceItemIdentifier("focus.pill.window")

    weak var mainWindow: NSWindow?
    weak var pillWindow: NSWindow?
    var hasPrewarmedPillWindow = false

    // Service references set by HelpyApp — used for the menu bar panel.
    weak var timerService: TimerService? {
        didSet { bindTimerService() }
    }
    weak var remindersService: RemindersService?
    weak var subtaskStore: SubtaskStore?

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
            pillWindow?.orderFront(nil)
        case .menuBarIcon:
            pillWindow?.orderOut(nil)
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
