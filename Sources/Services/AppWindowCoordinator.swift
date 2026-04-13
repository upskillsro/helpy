import AppKit
import Foundation

@MainActor
final class AppWindowCoordinator: ObservableObject {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("focus.main.window")
    static let pillWindowIdentifier = NSUserInterfaceItemIdentifier("focus.pill.window")

    weak var mainWindow: NSWindow?
    weak var pillWindow: NSWindow?
    var hasPrewarmedPillWindow = false

    private var statusItem: NSStatusItem?

    func applyDisplayMode(_ mode: PillDisplayMode) {
        switch mode {
        case .floatingPill:
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        case .menuBarIcon:
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timer")
            item.button?.imagePosition = .imageLeft
            statusItem = item
        }
    }

    func updateMenuBarTitle(_ text: String) {
        guard let button = statusItem?.button else { return }
        button.title = " \(text)"
    }
}
