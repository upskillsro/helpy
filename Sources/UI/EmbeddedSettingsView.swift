import SwiftUI

struct EmbeddedSettingsView: View {
    @ObservedObject var settings: SettingsStore
    var onClose: () -> Void
    /// The side strip has no title bar of its own, so its header runs up behind
    /// the window chrome. A settings window that keeps its title bar must not.
    var bleedsUnderTitleBar = true
    
    let sounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
    
    @Environment(\.colorScheme) private var colorScheme
    private var t: HelpyPalette { .forScheme(colorScheme) }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header. Quiet on purpose: the accent band belongs to the task
            // list, where it marks the app's one live surface. Settings is a
            // page you pass through, and a full-bleed blue bar over it reads
            // as another app.
            HStack(spacing: 9) {
                // The mark is a white template by default, for the accent
                // header it used to sit on. On canvas it has to be inked.
                HelpyMark(size: 20, color: t.accent)
                Text("Settings")
                    .font(.inter(size: 17, weight: .bold))
                    .foregroundStyle(t.ink)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(t.muted)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(t.fieldFill))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, bleedsUnderTitleBar ? 30 : 14)
            .padding(.bottom, 14)
            .background(
                t.canvas
                    .ignoresSafeArea(edges: bleedsUnderTitleBar ? .top : [])
            )
            .overlay(alignment: .bottom) {
                Rectangle().fill(t.line).frame(height: 1)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    
                    // APPEARANCE
                    // No theme or accent picker: Helpy has exactly one look, and
                    // it follows the system light/dark setting.
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle("Appearance")

                        VStack(alignment: .leading, spacing: 9) {
                            Text("Accent color")
                                .font(.inter(size: 13))
                                .foregroundStyle(t.ink)

                            HStack(spacing: 7) {
                                ForEach(HelpyAccent.presets) { preset in
                                    AccentSwatch(
                                        color: preset.color,
                                        name: preset.name,
                                        isSelected: settings.accentHex == preset.hex,
                                        palette: t
                                    ) { settings.accentHex = preset.hex }
                                }

                                Spacer(minLength: 6)

                                // The eighth swatch is whatever they want it to
                                // be; the presets are shortcuts, not the limit.
                                ColorPicker("", selection: Binding(
                                    get: { Color(hex: settings.accentHex) },
                                    set: { picked in
                                        if let hex = picked.helpyHex { settings.accentHex = hex }
                                    }
                                ), supportsOpacity: false)
                                .labelsHidden()
                            }

                            Text("Used for the header, progress, and every selected thing.")
                                .font(.inter(size: 10.5))
                                .foregroundStyle(t.muted2)
                        }

                        Rectangle().fill(t.line).frame(height: 1).padding(.vertical, 2)

                        Text("Where the timer lives while you work")
                            .font(.inter(size: 11.5))
                            .foregroundStyle(t.muted)

                        HStack(spacing: 14) {
                            TimerDisplayPreviewCard(
                                mode: .floatingPill,
                                palette: t,
                                isSelected: settings.pillDisplayMode == .floatingPill
                            ) { settings.pillDisplayMode = .floatingPill }

                            TimerDisplayPreviewCard(
                                mode: .menuBarIcon,
                                palette: t,
                                isSelected: settings.pillDisplayMode == .menuBarIcon
                            ) { settings.pillDisplayMode = .menuBarIcon }
                        }
                    }

                    Rectangle().fill(t.line).frame(height: 1)
                    
                    // PANEL POSITION
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle("Panel Position")
                        
                        HStack(spacing: 14) {
                            PositionPreviewCard(position: .left, palette: t, isSelected: settings.panelPosition == .left) {
                                updatePosition(.left)
                            }

                            PositionPreviewCard(position: .right, palette: t, isSelected: settings.panelPosition == .right) {
                                updatePosition(.right)
                            }
                        }

                        // Height presets — bottom-anchored short / medium / full
                        HStack {
                            Text("Panel Height")
                                .font(.inter(size: 13))
                                .foregroundStyle(t.ink)
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(PanelHeightMode.allCases, id: \.self) { mode in
                                    Button(action: { updateHeight(mode) }) {
                                        let picked = settings.panelHeightMode == mode
                                        Text(mode.label)
                                            .font(.inter(size: 12, weight: picked ? .semibold : .medium))
                                            .foregroundStyle(picked ? t.onAccent : t.muted)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule().fill(picked ? t.accent : Color.clear)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(3)
                            .background(HelpyChipBackground(palette: t))
                        }
                    }
                    
                    Rectangle().fill(t.line).frame(height: 1)
                    
                    // TIMER SETTINGS
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle("Timer Defaults")
                        
                        HStack {
                            Text("Break Duration")
                                .font(.inter(size: 13))
                                .foregroundStyle(t.ink)
                            Spacer()
                            
                            Menu {
                                Button("5 min") { settings.breakDuration = 300.0 }
                                Button("10 min") { settings.breakDuration = 600.0 }
                                Button("15 min") { settings.breakDuration = 900.0 }
                                Button("30 min") { settings.breakDuration = 1800.0 }
                                Button("45 min") { settings.breakDuration = 2700.0 }
                                Button("1 hour") { settings.breakDuration = 3600.0 }
                            } label: {
                                HStack {
                                    Text(formatDuration(settings.breakDuration))
                                        .font(.inter(size: 13, weight: .medium))
                                        .foregroundStyle(t.ink)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(width: 120) // Fixed width for consistent look
                                .background(HelpyChipBackground(palette: t))
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }
                    
                    Rectangle().fill(t.line).frame(height: 1)
                    
                    // APP BEHAVIOR
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle("App Behavior")
                        
                        HStack {
                            Text("Quit app when closing main window")
                                .font(.inter(size: 13))
                                .foregroundStyle(t.ink)
                            Spacer()
                            Toggle("", isOn: $settings.quitOnClose)
                                .toggleStyle(SwitchToggleStyle(tint: t.accent))
                                .labelsHidden()
                        }
                    }
                    
                    Rectangle().fill(t.line).frame(height: 1)

                    // ASSISTANT
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle("Assistant")

                        AssistantSettingsControls(settings: settings, isEmbedded: true)
                    }
                    
                    Rectangle().fill(t.line).frame(height: 1)
                    
                    // TASK ALERTS
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            sectionTitle("Task Alerts")
                            Spacer()
                            Toggle("", isOn: $settings.isTaskAlertEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: t.accent))
                                .labelsHidden()
                        }
                        
                        if settings.isTaskAlertEnabled {
                            VStack(alignment: .leading, spacing: 16) {
                                // Interval Selector
                                HStack {
                                    Text("Interval")
                                        .font(.inter(size: 13))
                                        .foregroundStyle(t.ink)
                                    Spacer()
                                    
                                    Menu {
                                        Button("5 min") { settings.taskAlertInterval = 300.0 }
                                        Button("10 min") { settings.taskAlertInterval = 600.0 }
                                        Button("15 min") { settings.taskAlertInterval = 900.0 }
                                        Button("30 min") { settings.taskAlertInterval = 1800.0 }
                                        Button("1 hour") { settings.taskAlertInterval = 3600.0 }
                                    } label: {
                                        HStack {
                                            Text(formatDuration(settings.taskAlertInterval))
                                                .font(.inter(size: 13, weight: .medium))
                                                .foregroundStyle(t.ink)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(width: 120)
                                        .background(HelpyChipBackground(palette: t))
                                    }
                                    .menuStyle(.borderlessButton)
                                }
                                
                                // Sound Info
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Sound")
                                        .font(.inter(size: 12, weight: .medium))
                                        .foregroundStyle(t.muted)
                                    
                                    HStack(spacing: 12) {
                                        // Sound Picker
                                        Menu {
                                            ForEach(sounds, id: \.self) { sound in
                                                Button(action: { settings.taskAlertSound = sound }) {
                                                    HStack {
                                                        if settings.taskAlertSound == sound {
                                                            Image(systemName: "checkmark")
                                                        }
                                                        Text(sound)
                                                    }
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                Text(settings.taskAlertSound)
                                                    .font(.inter(size: 13, weight: .medium))
                                                    .foregroundStyle(t.ink)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(width: 140)
                                            .background(HelpyChipBackground(palette: t))
                                        }
                                        .menuStyle(.borderlessButton)
                                        
                                        Spacer()
                                        
                                        // Play Button
                                        Button(action: {
                                            playSound(named: settings.taskAlertSound, volume: settings.taskAlertVolume)
                                        }) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(t.ink)
                                                .frame(width: 32, height: 32)
                                                .background(HelpyChipBackground(palette: t))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                // Volume Slider
                                HStack(spacing: 12) {
                                    Image(systemName: "speaker.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(t.muted)
                                    
                                    Slider(value: $settings.taskAlertVolume, in: 0...1)
                                        .tint(t.accent)
                                    
                                    Image(systemName: "speaker.wave.3.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(t.muted)
                                }
                            }
                            .padding(.leading, 4)
                        }
                    }
                    
                    Rectangle().fill(t.line).frame(height: 1)
                    
                    // ALERT SETTINGS
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            sectionTitle("Alerts")
                            Spacer()
                            Toggle("", isOn: $settings.isAlertEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: t.accent))
                                .labelsHidden()
                        }
                        
                        if settings.isAlertEnabled {
                            VStack(alignment: .leading, spacing: 16) {
                                // Sound Info
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Sound")
                                        .font(.inter(size: 12, weight: .medium))
                                        .foregroundStyle(t.muted)
                                    
                                    HStack(spacing: 12) {
                                        // Sound Picker
                                        Menu {
                                            ForEach(sounds, id: \.self) { sound in
                                                Button(action: { settings.alertSound = sound }) {
                                                    HStack {
                                                        if settings.alertSound == sound {
                                                            Image(systemName: "checkmark")
                                                        }
                                                        Text(sound)
                                                    }
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                Text(settings.alertSound)
                                                    .font(.inter(size: 13, weight: .medium))
                                                    .foregroundStyle(t.ink)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(width: 140) // Fixed width for consistency
                                            .background(HelpyChipBackground(palette: t))
                                        }
                                        .menuStyle(.borderlessButton)
                                        
                                        Spacer()
                                        
                                        // Play Button
                                        Button(action: {
                                            playSound(named: settings.alertSound, volume: settings.alertVolume)
                                        }) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(t.ink)
                                                .frame(width: 32, height: 32)
                                                .background(HelpyChipBackground(palette: t))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                // Volume Slider
                                HStack(spacing: 12) {
                                    Image(systemName: "speaker.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(t.muted)
                                    
                                    Slider(value: $settings.alertVolume, in: 0...1)
                                        .tint(t.accent)
                                    
                                    Image(systemName: "speaker.wave.3.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(t.muted)
                                }
                            }
                            .padding(.leading, 4)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(24)
            }
        }
        .background(t.canvas)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.inter(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.0)
            .foregroundStyle(t.muted2)
    }

    func updatePosition(_ pos: PanelPosition) {
        settings.panelPosition = pos
        NotificationCenter.default.post(name: NSNotification.Name("UpdatePanelPosition"), object: nil)
    }

    func updateHeight(_ mode: PanelHeightMode) {
        settings.panelHeightMode = mode
        NotificationCenter.default.post(name: NSNotification.Name("UpdatePanelPosition"), object: nil)
    }

    func formatDuration(_ seconds: Double) -> String {
        let min = Int(seconds) / 60
        return "\(min) min"
    }
    
    func playSound(named name: String, volume: Double) {
        if let sound = NSSound(named: name) {
            sound.volume = Float(volume)
            sound.play()
        }
    }
}

// MARK: - Subviews & Styles

/// One accent option. A ring rather than a checkmark: at this size a glyph
/// on a saturated circle is a smudge, and the ring reads at a glance.
private struct AccentSwatch: View {
    let color: Color
    let name: String
    let isSelected: Bool
    let palette: HelpyPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 17, height: 17)
                .overlay(
                    Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1)
                )
                .padding(2.5)
                .overlay(
                    Circle().strokeBorder(isSelected ? color : .clear, lineWidth: 1.8)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .animation(.easeOut(duration: 0.14), value: isSelected)
    }
}

/// A miniature Mac: the real desktop picture, a menu bar and a dock, with
/// whatever the setting being previewed placed on top.
///
/// The wallpaper is the user's own (see `DesktopWallpaper`) so the card reads
/// as a picture of their screen rather than an abstract diagram.
struct HelpyDesktopPreview<Content: View>: View {
    let palette: HelpyPalette
    var menuBarItems = true
    @ViewBuilder var content: () -> Content

    static var cornerRadius: CGFloat { 7 }
    static var menuBarHeight: CGFloat { 8 }

    var body: some View {
        ZStack(alignment: .top) {
            wallpaper

            VStack(spacing: 0) {
                menuBar
                Spacer(minLength: 0)
                dock
            }

            content()
        }
        .frame(height: 86)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var wallpaper: some View {
        if let picture = DesktopWallpaper.image {
            picture
                .resizable()
                .scaledToFill()
        } else {
            // Only when the desktop picture cannot be read at all.
            LinearGradient(
                colors: [
                    Color(red: 0.24, green: 0.26, blue: 0.62),
                    Color(red: 0.52, green: 0.30, blue: 0.72),
                    Color(red: 0.83, green: 0.42, blue: 0.62)
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        }
    }

    private var menuBar: some View {
        HStack(spacing: 3) {
            Image(systemName: "apple.logo")
                .font(.system(size: 4.5))
                .foregroundStyle(.white.opacity(0.85))
            if menuBarItems {
                ForEach([7.0, 5.0, 6.0], id: \.self) { width in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(.white.opacity(0.5))
                        .frame(width: width, height: 2)
                }
            }
            Spacer(minLength: 0)
            ForEach([4.0, 4.0], id: \.self) { width in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.white.opacity(0.42))
                    .frame(width: width, height: 2)
            }
            RoundedRectangle(cornerRadius: 0.5)
                .fill(.white.opacity(0.55))
                .frame(width: 9, height: 2)
        }
        .padding(.horizontal, 4)
        .frame(height: Self.menuBarHeight)
        .background(.black.opacity(0.32))
    }

    private var dock: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(.white.opacity(index == 2 ? 0.75 : 0.45))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.white.opacity(0.20))
        )
        .padding(.bottom, 3)
    }
}

/// The frame every preview card shares. The selected state lives here, on the
/// card, rather than as a ring drawn around the little screen — the thing you
/// are choosing is the option, not the picture of it.
private struct PreviewCardShell<Content: View>: View {
    let label: String
    let caption: String
    let palette: HelpyPalette
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var preview: () -> Content

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview()

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.inter(size: 11.5, weight: .semibold))
                        .foregroundStyle(isSelected ? palette.ink : palette.ink2)
                    Text(caption)
                        .font(.inter(size: 9.5))
                        .foregroundStyle(palette.muted2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .fill(isSelected ? palette.surfaceActive : (isHovering ? palette.surfaceHover : palette.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? palette.accent : palette.line, lineWidth: isSelected ? 2.5 : 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onHover { hovering in isHovering = hovering }
        .animation(.easeOut(duration: 0.16), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// Which edge the side strip lives on, shown as the strip sitting on a desktop.
struct PositionPreviewCard: View {
    let position: PanelPosition
    let palette: HelpyPalette
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        PreviewCardShell(
            label: position == .left ? "Left" : "Right",
            caption: position == .left ? "Strip on the left edge" : "Strip on the right edge",
            palette: palette,
            isSelected: isSelected,
            action: action
        ) {
            HelpyDesktopPreview(palette: palette) {
                HStack(spacing: 0) {
                    if position == .right { Spacer(minLength: 0) }
                    miniStrip
                    if position == .left { Spacer(minLength: 0) }
                }
                .padding(.top, HelpyDesktopPreview<EmptyView>.menuBarHeight + 3)
                .padding(.bottom, 13)
                .padding(.horizontal, 3)
            }
        }
    }

    /// Helpy at thumbnail scale: accent header, a timer readout, task rows with
    /// one of them ticked, and the add row at the foot.
    private var miniStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Circle().fill(.white).frame(width: 3, height: 3)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.white.opacity(0.9))
                    .frame(width: 11, height: 2.5)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
            .frame(height: 10)
            .frame(maxWidth: .infinity)
            .background(palette.accent)

            HStack(spacing: 2) {
                Image(systemName: "play.fill")
                    .font(.system(size: 3.5))
                    .foregroundStyle(palette.accent)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.white.opacity(0.85))
                    .frame(width: 12, height: 2.5)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2.5)
            .background(.white.opacity(0.14))
            .padding(.horizontal, 2.5)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 2.5) {
                        if row == 1 {
                            Circle().fill(palette.accent).frame(width: 3.5, height: 3.5)
                        } else {
                            Circle()
                                .strokeBorder(.white.opacity(0.55), lineWidth: 0.7)
                                .frame(width: 3.5, height: 3.5)
                        }
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(.white.opacity(row == 1 ? 0.32 : 0.55))
                            .frame(width: row == 2 ? 12 : 18, height: 2.5)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 1)

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 1.5)
                .strokeBorder(.white.opacity(0.30), style: StrokeStyle(lineWidth: 0.7, dash: [1.5, 1.5]))
                .frame(height: 6)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
        .frame(width: 34)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.black.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.7)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Where the running timer shows up: a pill floating over the desktop, or a
/// readout in the menu bar.
struct TimerDisplayPreviewCard: View {
    let mode: PillDisplayMode
    let palette: HelpyPalette
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        PreviewCardShell(
            label: mode == .floatingPill ? "Floating Pill" : "Menu Bar",
            caption: mode == .floatingPill ? "Always on top of your work" : "Tucked away up top",
            palette: palette,
            isSelected: isSelected,
            action: action
        ) {
            HelpyDesktopPreview(palette: palette, menuBarItems: mode == .floatingPill) {
                if mode == .floatingPill {
                    floatingPill
                } else {
                    menuBarReadout
                }
            }
        }
    }

    private var floatingPill: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 4.5))
                    .foregroundStyle(palette.accent)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.white.opacity(0.92))
                    .frame(width: 16, height: 3)
                Capsule()
                    .fill(.white.opacity(0.28))
                    .frame(width: 1, height: 7)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.white.opacity(0.55))
                    .frame(width: 9, height: 2.5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.78)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
    }

    private var menuBarReadout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    Circle().fill(palette.accent).frame(width: 3.5, height: 3.5)
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(.white.opacity(0.95))
                        .frame(width: 10, height: 2.5)
                }
                .padding(.horizontal, 2.5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(.white.opacity(0.22)))

                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.white.opacity(0.42))
                    .frame(width: 4, height: 2)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.white.opacity(0.55))
                    .frame(width: 9, height: 2)
            }
            .padding(.horizontal, 4)
            .frame(height: HelpyDesktopPreview<EmptyView>.menuBarHeight)

            Spacer(minLength: 0)
        }
    }
}

/// The small inset surface behind settings menus and chips. Replaces the old
/// GlassyBackground now that nothing in Helpy is translucent.
struct HelpyChipBackground: View {
    let palette: HelpyPalette

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(palette.fieldFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(palette.fieldBorder, lineWidth: 1)
            )
    }
}
