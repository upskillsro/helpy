import SwiftUI
import AppKit

private final class ResourceBundleProbe {}

final class HelpyAppDelegate: NSObject, NSApplicationDelegate {
    /// Helpy is menu-bar resident: focus mode intentionally hides every window,
    /// so a stray window close (e.g. the menu bar dropdown panel being torn down)
    /// must never take the app down with it. Quitting is explicit only:
    /// closing the main window with quitOnClose enabled, the status item's
    /// Quit menu, or Cmd-Q.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon while all windows are hidden brings the sidebar back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        if let main = NSApp.windows.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("focus.main.window") }) {
            main.setIsVisible(true)
            main.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return false
        }
        return true
    }
}

final class MainWindowCloseDelegate: NSObject, NSWindowDelegate {
    /// One instance, installed from two places. The strip's window accessor
    /// used to bring a second delegate of its own, and whichever ran last won:
    /// that is how the strip ended up with a window nobody was holding to
    /// 350pt. A window has one delegate, so there is one object for it.
    static let shared = MainWindowCloseDelegate()

    /// Focus mode's strip is a fixed-width panel, and dragging it wider left a
    /// pane of empty window beside content that stops at 350. Refusing the
    /// resize here is the only place the lock holds: removing .resizable from
    /// the style mask and setting maxSize are both undone by SwiftUI the next
    /// time it reapplies .windowResizability.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let locked = MainWindowStyle.lockedWidth else { return frameSize }
        return NSSize(width: locked, height: frameSize.height)
    }

    /// The backstop for a resize that never asked: SwiftUI sizes the window
    /// itself when it rebuilds the scene's root view, and that path does not
    /// go through windowWillResize.
    ///
    /// The correction is deferred to the next runloop turn, never applied
    /// here. This notification arrives from inside AppKit's layout pass, and
    /// setting a frame from within that pass throws — an uncaught exception,
    /// not a warning, so the app dies rather than mislaying a window.
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let locked = MainWindowStyle.lockedWidth,
              abs(window.frame.width - locked) > 0.5 else { return }

        DispatchQueue.main.async {
            // Re-read the lock: the window may have left strip mode in between.
            guard let locked = MainWindowStyle.lockedWidth,
                  abs(window.frame.width - locked) > 0.5 else { return }
            var frame = window.frame
            frame.size.width = locked
            window.setFrame(frame, display: true, animate: false)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if SettingsStore().quitOnClose {
            NSApp.terminate(nil)
            return false
        }
        return true
    }
}

@main
struct HelpyApp: App {
    private let mainWindowIdentifier = NSUserInterfaceItemIdentifier("focus.main.window")
    @NSApplicationDelegateAdaptor(HelpyAppDelegate.self) private var appDelegate
    private let mainWindowCloseDelegate = MainWindowCloseDelegate.shared
    @StateObject var remindersService = RemindersService()
    @StateObject var estimateStore = EstimateStore()
    @StateObject var timerService = TimerService()
    @StateObject var windowCoordinator = AppWindowCoordinator()
    @StateObject var subtaskStore = SubtaskStore()
    @StateObject var navigation = AppNavigation()
    @StateObject var planStore = WeeklyPlanStore()
    @StateObject var roadmapStore = RoadmapStore()
    @StateObject var iconStore = ListIconStore()
    @State private var panelPositionObserver: NSObjectProtocol?
    @State private var appearanceObserver: NSObjectProtocol?
    @State private var lastAppliedDarkIconState: Bool?
    @AppStorage("pillDisplayMode") private var pillDisplayMode: PillDisplayMode = .floatingPill
    // Palettes are read through a static, so changing the accent has to rebuild
    // the window for the new colour to reach every view at once.
    @AppStorage("accentHex") private var accentHex = Int(HelpyAccent.defaultHex)
    
    init() {
        // Inter ships in the bundle and must be registered before the first
        // view is built, or every .custom("Inter-…") lookup this launch
        // silently resolves to the system font.
        HelpyFonts.register()

        // Same reason: the accent has to be in place before anything draws.
        HelpyAccent.loadFromDefaults()

        // Services are linked in .onAppear: reading a @StateObject's wrapped
        // value from init is not safe.
    }

    var body: some Scene {
        WindowGroup("Helpy") {
            MainWindowView()
                .id(accentHex)
                .environmentObject(remindersService)
                .environmentObject(timerService)
                .environmentObject(estimateStore)
                .environmentObject(windowCoordinator)
                .environmentObject(subtaskStore)
                .environmentObject(navigation)
                .environmentObject(planStore)
                .environmentObject(roadmapStore)
                .environmentObject(iconStore)
                .onAppear {
                    // Link Dependencies
                    timerService.estimateStore = estimateStore

                    // Provide service refs to coordinator for menu bar panel
                    windowCoordinator.timerService = timerService
                    windowCoordinator.remindersService = remindersService
                    windowCoordinator.subtaskStore = subtaskStore
                    windowCoordinator.estimateStore = estimateStore

                    // Always show the Helpy menu bar icon
                    windowCoordinator.setupStatusItem()
                    
                    // Ensure Dock icon
                    NSApp.setActivationPolicy(.regular)
                    
                    // Apply icon after launch plumbing completes so the Dock icon
                    // doesn't get reset back to the bundle default.
                    DispatchQueue.main.async {
                        applySystemAppearanceIcon()
                    }
                    
                    // Hand the window to the coordinator; it owns the chrome
                    // for both the normal window and the side strip.
                    DispatchQueue.main.async {
                        if let window = NSApplication.shared.windows.first {
                            window.identifier = mainWindowIdentifier
                            window.delegate = mainWindowCloseDelegate
                            windowCoordinator.mainWindow = window
                            windowCoordinator.setMainWindowMode(
                                navigation.isFocused ? .strip : .normal,
                                animated: false
                            )

                            // Observe position changes once per lifecycle
                            if panelPositionObserver == nil {
                                panelPositionObserver = NotificationCenter.default.addObserver(
                                    forName: NSNotification.Name("UpdatePanelPosition"),
                                    object: nil,
                                    queue: .main
                                ) { _ in
                                    Task { @MainActor in
                                        withAnimation {
                                            windowCoordinator.repinStripIfNeeded()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    setupAppearanceObserver()

                    // Apply initial display mode
                    windowCoordinator.applyDisplayMode(pillDisplayMode)
                }
                .onChange(of: pillDisplayMode) { _, mode in
                    windowCoordinator.applyDisplayMode(mode)
                }
                .onDisappear {
                    if let observer = panelPositionObserver {
                        NotificationCenter.default.removeObserver(observer)
                        panelPositionObserver = nil
                    }
                    if let observer = appearanceObserver {
                        DistributedNotificationCenter.default().removeObserver(observer)
                        appearanceObserver = nil
                    }
                }
        }
        // No .windowStyle here on purpose: MainWindowStyle owns the chrome for
        // both modes, and a scene-level hiddenTitleBar would fight it — and take
        // the toolbar (the Lists/Planning switcher) with it.
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 720)

        // The floating pill is deliberately NOT a scene: AppWindowCoordinator
        // creates and owns that panel. See the note on `pillPanel`.

        Settings {
            SettingsView()
        }
        // Helpy's own header sits at the top of the settings screen; a system
        // title bar above it would be a second, emptier one.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
    
    func applySystemAppearanceIcon() {
        let shouldUseDarkIcon = isSystemDarkModeEnabled()
        
        if lastAppliedDarkIconState == shouldUseDarkIcon {
            return
        }
        
        let iconName = shouldUseDarkIcon ? "AppIconDark" : "AppIcon"
        let resourceBundle = iconResourceBundle()
        
        let iconImage: NSImage?
        if let iconURL = resourceBundle.url(forResource: iconName, withExtension: "icns"),
           let loaded = NSImage(contentsOf: iconURL) {
            iconImage = loaded
        } else if let iconURL = resourceBundle.url(forResource: iconName, withExtension: "png"),
                  let loaded = NSImage(contentsOf: iconURL) {
            iconImage = loaded
        } else {
            iconImage = nil
        }
        
        NSApplication.shared.applicationIconImage = iconImage
        persistAppBundleIcon(iconImage, iconName: iconName, resourceBundle: resourceBundle)
        
        lastAppliedDarkIconState = shouldUseDarkIcon
    }
    
    func setupAppearanceObserver() {
        guard appearanceObserver == nil else { return }
        
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            applySystemAppearanceIcon()
        }
    }
    
    func isSystemDarkModeEnabled() -> Bool {
        if let interfaceStyle = CFPreferencesCopyValue(
            "AppleInterfaceStyle" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? String {
            return interfaceStyle.caseInsensitiveCompare("Dark") == .orderedSame
        }
        
        let bestMatch = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return bestMatch == .darkAqua
    }
    
    func iconResourceBundle() -> Bundle {
        if let embeddedBundleURL = Bundle.main.url(forResource: "Helpy_Helpy", withExtension: "bundle"),
           let embeddedBundle = Bundle(url: embeddedBundleURL) {
            return embeddedBundle
        }
        
        let fallbackBundle = Bundle(for: ResourceBundleProbe.self)
        if let siblingBundleURL = fallbackBundle.url(forResource: "Helpy_Helpy", withExtension: "bundle"),
           let siblingBundle = Bundle(url: siblingBundleURL) {
            return siblingBundle
        }
        
        return Bundle.main
    }
    
    func persistAppBundleIcon(_ iconImage: NSImage?, iconName: String, resourceBundle: Bundle) {
        guard let bundlePath = appBundlePath() else { return }
        syncBundleIconFile(iconName: iconName, resourceBundle: resourceBundle, bundlePath: bundlePath)
        if !NSWorkspace.shared.setIcon(iconImage, forFile: bundlePath, options: []) {
            _ = NSWorkspace.shared.setIcon(iconImage, forFile: Bundle.main.bundlePath, options: [])
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: bundlePath)
        NSWorkspace.shared.noteFileSystemChanged(bundlePath)
    }
    
    func syncBundleIconFile(iconName: String, resourceBundle: Bundle, bundlePath: String) {
        guard
            let sourceIconURL = resourceBundle.url(forResource: iconName, withExtension: "icns")
        else { return }
        
        let targetIconURL = URL(fileURLWithPath: bundlePath)
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("AppIcon.icns")
        
        guard let sourceData = try? Data(contentsOf: sourceIconURL) else { return }
        let existingData = try? Data(contentsOf: targetIconURL)
        
        if existingData == sourceData {
            return
        }
        
        try? sourceData.write(to: targetIconURL, options: .atomic)
    }
    
    func appBundlePath() -> String? {
        var url = URL(fileURLWithPath: Bundle.main.bundlePath)
        
        while url.path != "/" {
            if url.pathExtension == "app" {
                return url.path
            }
            url.deleteLastPathComponent()
        }
        
        return nil
    }
}
