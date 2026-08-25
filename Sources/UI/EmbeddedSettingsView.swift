import SwiftUI

struct EmbeddedSettingsView: View {
    @ObservedObject var settings: SettingsStore
    var onClose: () -> Void
    
    let sounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
    
    @Environment(\.colorScheme) private var colorScheme
    private var t: HelpyPalette { .forScheme(colorScheme) }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HelpyMark(size: 22)
                Text("Settings")
                    .font(.inter(size: 19, weight: .bold))
                    .foregroundStyle(t.onAccent)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(t.onAccent)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
            // Same rule as the sidebar header: bleed up under the title bar,
            // stop dead at the header's own bottom edge.
            .background(
                HelpyHeaderBackground(palette: t)
                    .ignoresSafeArea(edges: .top)
            )
            
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    
                    // APPEARANCE
                    // No theme or accent picker: Helpy has exactly one look, and
                    // it follows the system light/dark setting.
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle("Appearance")

                        HStack {
                            Text("Show Timer As")
                                .font(.inter(size: 13))
                                .foregroundStyle(t.ink)
                            Spacer()

                            Menu {
                                Button("Floating Pill") { settings.pillDisplayMode = .floatingPill }
                                Button("Menu Bar Icon") { settings.pillDisplayMode = .menuBarIcon }
                            } label: {
                                HStack {
                                    Text(settings.pillDisplayMode == .floatingPill ? "Floating Pill" : "Menu Bar Icon")
                                        .font(.inter(size: 13, weight: .medium))
                                        .foregroundStyle(t.ink)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(width: 160)
                                .background(HelpyChipBackground(palette: t))
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }

                    Rectangle().fill(t.line).frame(height: 1)
                    
                    // PANEL POSITION
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle("Panel Position")
                        
                        HStack(spacing: 20) {
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

struct PositionPreviewCard: View {
    let position: PanelPosition
    let palette: HelpyPalette
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Desktop Visual
                ZStack {
                    // Wallpaper / Screen
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.header.opacity(0.28))
                        .frame(height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(palette.line, lineWidth: 1)
                        )

                    // The App Panel
                    HStack {
                        if position == .right { Spacer() }
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isSelected ? palette.accent : palette.muted2)
                            .frame(width: 16, height: 48)
                            .padding(position == .left ? .leading : .trailing, 6)
                        if position == .left { Spacer() }
                    }
                }

                // Label
                Text(position == .left ? "Screen Left" : "Screen Right")
                    .font(.inter(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? palette.ink : palette.muted)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .fill(isSelected ? palette.surfaceActive : palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? palette.surfaceActiveBorder : palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.16), value: isSelected)
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
