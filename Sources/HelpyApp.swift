import SwiftUI
import AppKit

private final class ResourceBundleProbe {}

final class HelpyAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        SettingsStore().quitOnClose
    }
}

final class MainWindowCloseDelegate: NSObject, NSWindowDelegate {
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
    private let mainWindowCloseDelegate = MainWindowCloseDelegate()
    @StateObject var remindersService = RemindersService()
    @StateObject var estimateStore = EstimateStore()
    @StateObject var timerService = TimerService()
    @StateObject var windowCoordinator = AppWindowCoordinator()
    @State private var panelPositionObserver: NSObjectProtocol?
    @State private var appearanceObserver: NSObjectProtocol?
    @State private var lastAppliedDarkIconState: Bool?
    @AppStorage("pillDisplayMode") private var pillDisplayMode: PillDisplayMode = .floatingPill
    
    init() {
        // Link services
        // We can't do this easily in init because of @StateObject lazy init order, 
        // but we can do it in onAppear or by passing it.
        // However, accessing the underlying objects of StateObject in init is tricky.
        // Let's rely on .onAppear or a separate setup method.
    }

    var body: some Scene {
        WindowGroup("Helpy") {
            SideStripView()
                .environmentObject(remindersService)
                .environmentObject(timerService)
                .environmentObject(estimateStore)
                .environmentObject(windowCoordinator)
                .frame(minWidth: 300, maxWidth: 350)
                .onAppear {
                    // Link Dependencies
                    timerService.estimateStore = estimateStore
                    
                    // Ensure Dock icon
                    NSApp.setActivationPolicy(.regular)
                    
                    // Apply icon after launch plumbing completes so the Dock icon
                    // doesn't get reset back to the bundle default.
                    DispatchQueue.main.async {
                        applySystemAppearanceIcon()
                    }
                    
                    // Position Main Window as Sidebar
                    DispatchQueue.main.async {
                        if let window = NSApplication.shared.windows.first {
                            window.identifier = mainWindowIdentifier
                            window.delegate = mainWindowCloseDelegate
                            windowCoordinator.mainWindow = window
                            setupWindowPosition(window)
                            
                            // Observe position changes once per lifecycle
                            if panelPositionObserver == nil {
                                panelPositionObserver = NotificationCenter.default.addObserver(
                                    forName: NSNotification.Name("UpdatePanelPosition"),
                                    object: nil,
                                    queue: .main
                                ) { _ in
                                    withAnimation {
                                        setupWindowPosition(window)
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
                .onChange(of: timerService.ticker.remainingTime) { _, _ in
                    guard pillDisplayMode == .menuBarIcon, timerService.isFocusMode else { return }
                    windowCoordinator.updateMenuBarTitle(timerService.formattedTime())
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
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 350, height: 800)
        
        // Floating Pill - Single Instance Window
        Window("Timer", id: "timer-pill") {
            if timerService.isFocusMode &&
               (timerService.activeReminderId != nil || timerService.isOnBreak) &&
               pillDisplayMode == .floatingPill {
                FloatingPillView()
                    .environmentObject(timerService)
                    .environmentObject(remindersService)
                    .environmentObject(estimateStore)
                    .environmentObject(windowCoordinator)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        Settings {
            SettingsView()
        }
    }
    
    func setupWindowPosition(_ window: NSWindow) {
        let settings = SettingsStore() // Read purely for positioning
        
        window.level = .floating // Stay on top
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        if let screen = window.screen {
            let visibleFrame = screen.visibleFrame
            let width = window.frame.width
            let margin: CGFloat = 15
            let x: CGFloat = settings.panelPosition == .left ? visibleFrame.minX + margin : visibleFrame.maxX - width - margin
            
            let newFrame = NSRect(
                x: x,
                y: visibleFrame.minY + margin,
                width: width,
                height: visibleFrame.height - (margin * 2)
            )
            window.setFrame(newFrame, display: true)
        }
        
        // Visuals
        window.backgroundColor = .clear
        window.isOpaque = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovable = false // Lock position
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
