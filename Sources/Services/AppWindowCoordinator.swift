import AppKit
import SwiftUI
import Foundation

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
    weak var timerService: TimerService?
    weak var remindersService: RemindersService?
    weak var subtaskStore: SubtaskStore?

    private var statusItem: NSStatusItem?
    private var menuBarPanel: NSPanel?
    private var clickOutsideMonitor: Any?
    private var globalClickMonitor: Any?

    /// Create the persistent Helpy menu bar icon. Call once after service refs are set.
    /// The icon is always visible regardless of display mode.
    func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Use the bundled Helpy icon as a template image so it adapts to light/dark menu bar.
        if let iconURL = helperResourceBundle().url(forResource: "MenuBarIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.isTemplate = true
            item.button?.image = icon
        } else {
            item.button?.image = NSImage(systemSymbolName: "h.circle", accessibilityDescription: "Helpy")
        }

        item.button?.imagePosition = .imageLeft
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseDown])
        statusItem = item
    }

    func applyDisplayMode(_ mode: PillDisplayMode) {
        switch mode {
        case .floatingPill:
            // Clear any timer text when switching back to floating pill mode
            statusItem?.button?.title = ""
        case .menuBarIcon:
            // Timer text is updated via updateMenuBarTitle when focus is active
            break
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

    func updateMenuBarTitle(_ text: String) {
        guard let button = statusItem?.button else { return }
        button.title = " \(text)"
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

        hideMenuBarPanel()

        let panelWidth: CGFloat = 300
        let cornerRadius: CGFloat = 16

        let content = MenuBarPanelView(
            timerService: timerService,
            remindersService: remindersService,
            subtaskStore: subtaskStore,
            onClose: { [weak self] in self?.hideMenuBarPanel() }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 160),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false

        let hostingView = KeyableHostingView(rootView: content)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = cornerRadius
        hostingView.layer?.masksToBounds = false
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView

        // Position below the status item button
        if let button = statusItem?.button, let buttonWindow = button.window {
            let buttonBounds = button.convert(button.bounds, to: nil)
            let screenFrame = buttonWindow.convertToScreen(buttonBounds)
            let x = max(
                NSScreen.main?.visibleFrame.minX ?? 0,
                min(screenFrame.midX - panelWidth / 2,
                    (NSScreen.main?.visibleFrame.maxX ?? panelWidth) - panelWidth)
            )
            // Size the panel to fit content
            hostingView.layout()
            let fittingHeight = hostingView.fittingSize.height
            let panelHeight = max(fittingHeight, 120)
            let y = screenFrame.minY - panelHeight - 4
            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: false)
        }

        panel.orderFront(nil)
        menuBarPanel = panel
        addClickOutsideMonitor()
    }

    func hideMenuBarPanel() {
        menuBarPanel?.orderOut(nil)
        menuBarPanel = nil
        removeClickOutsideMonitor()
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

    private func helperResourceBundle() -> Bundle {
        if let url = Bundle.main.url(forResource: "Helpy_Helpy", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.main
    }
}
