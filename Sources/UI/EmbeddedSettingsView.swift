import SwiftUI

struct EmbeddedSettingsView: View {
    @ObservedObject var settings: SettingsStore
    var onClose: () -> Void
    
    let sounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
    
    private var isWhiteTheme: Bool { settings.appTheme == .white }
    private var dividerColor: Color { isWhiteTheme ? Color.black.opacity(0.12) : Color.white.opacity(0.1) }
    private var toggleTint: Color { isWhiteTheme ? Color.blue.opacity(0.85) : Color.white.opacity(0.8) }
    private var menuTextColor: Color { isWhiteTheme ? Color.primary : Color.white }
    private var sectionHeaderBackground: Color { isWhiteTheme ? Color.black.opacity(0.05) : Color.black.opacity(0.2) }
    private var sliderAccentColor: Color { isWhiteTheme ? Color.blue : Color.white }
    private var sliderTrackColor: Color { isWhiteTheme ? Color.black.opacity(0.12) : Color.white.opacity(0.1) }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(sectionHeaderBackground)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    
                    // APPEARANCE
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Appearance")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 20) {
                            ThemePreviewCard(theme: .glass, isSelected: settings.appTheme == .glass) {
                                settings.appTheme = .glass
                            }

                            ThemePreviewCard(theme: .dark, isSelected: settings.appTheme == .dark) {
                                settings.appTheme = .dark
                            }

                            ThemePreviewCard(theme: .white, isSelected: settings.appTheme == .white) {
                                settings.appTheme = .white
                            }
                        }

                        HStack {
                            Text("Show Timer As")
                                .foregroundColor(.primary)
                            Spacer()

                            Menu {
                                Button("Floating Pill") { settings.pillDisplayMode = .floatingPill }
                                Button("Menu Bar Icon") { settings.pillDisplayMode = .menuBarIcon }
                            } label: {
                                HStack {
                                    Text(settings.pillDisplayMode == .floatingPill ? "Floating Pill" : "Menu Bar Icon")
                                        .foregroundColor(menuTextColor)
                                        .fontWeight(.medium)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(width: 160)
                                .background(GlassyBackground(theme: settings.appTheme))
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }

                    Divider().background(dividerColor)
                    
                    // PANEL POSITION
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Panel Position")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 20) {
                            PositionPreviewCard(position: .left, theme: settings.appTheme, isSelected: settings.panelPosition == .left) {
                                updatePosition(.left)
                            }
                            
                            PositionPreviewCard(position: .right, theme: settings.appTheme, isSelected: settings.panelPosition == .right) {
                                updatePosition(.right)
                            }
                        }
                    }
                    
                    Divider().background(dividerColor)
                    
                    // TIMER SETTINGS
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Timer Defaults")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Break Duration")
                                .foregroundColor(.primary)
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
                                        .foregroundColor(menuTextColor)
                                        .fontWeight(.medium)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(width: 120) // Fixed width for consistent look
                                .background(GlassyBackground(theme: settings.appTheme))
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }
                    
                    Divider().background(dividerColor)
                    
                    // APP BEHAVIOR
                    VStack(alignment: .leading, spacing: 16) {
                        Text("App Behavior")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Quit app when closing main window")
                                .foregroundColor(.primary)
                            Spacer()
                            Toggle("", isOn: $settings.quitOnClose)
                                .toggleStyle(SwitchToggleStyle(tint: toggleTint))
                                .labelsHidden()
                        }
                    }
                    
                    Divider().background(dividerColor)

                    // ASSISTANT
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Assistant")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        AssistantSettingsControls(settings: settings, theme: settings.appTheme)
                    }
                    
                    Divider().background(dividerColor)
                    
                    // TASK ALERTS
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Task Alerts")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("", isOn: $settings.isTaskAlertEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: toggleTint))
                                .labelsHidden()
                        }
                        
                        if settings.isTaskAlertEnabled {
                            VStack(alignment: .leading, spacing: 16) {
                                // Interval Selector
                                HStack {
                                    Text("Interval")
                                        .foregroundColor(.primary)
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
                                                .foregroundColor(menuTextColor)
                                                .fontWeight(.medium)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(width: 120)
                                        .background(GlassyBackground(theme: settings.appTheme))
                                    }
                                    .menuStyle(.borderlessButton)
                                }
                                
                                // Sound Info
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Sound")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
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
                                                    .foregroundColor(menuTextColor)
                                                    .fontWeight(.medium)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(width: 140)
                                            .background(GlassyBackground(theme: settings.appTheme))
                                        }
                                        .menuStyle(.borderlessButton)
                                        
                                        Spacer()
                                        
                                        // Play Button
                                        Button(action: {
                                            playSound(named: settings.taskAlertSound, volume: settings.taskAlertVolume)
                                        }) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(menuTextColor)
                                                .frame(width: 32, height: 32)
                                                .background(GlassyBackground(theme: settings.appTheme))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                // Volume Slider
                                HStack(spacing: 12) {
                                    Image(systemName: "speaker.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Slider(value: $settings.taskAlertVolume, in: 0...1)
                                        .accentColor(sliderAccentColor)
                                        .background(
                                            Capsule()
                                                .fill(sliderTrackColor)
                                                .frame(height: 4)
                                        )
                                    
                                    Image(systemName: "speaker.wave.3.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.leading, 4)
                        }
                    }
                    
                    Divider().background(dividerColor)
                    
                    // ALERT SETTINGS
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Alerts")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("", isOn: $settings.isAlertEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: toggleTint))
                                .labelsHidden()
                        }
                        
                        if settings.isAlertEnabled {
                            VStack(alignment: .leading, spacing: 16) {
                                // Sound Info
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Sound")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
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
                                                    .foregroundColor(menuTextColor)
                                                    .fontWeight(.medium)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(width: 140) // Fixed width for consistency
                                            .background(GlassyBackground(theme: settings.appTheme))
                                        }
                                        .menuStyle(.borderlessButton)
                                        
                                        Spacer()
                                        
                                        // Play Button
                                        Button(action: {
                                            playSound(named: settings.alertSound, volume: settings.alertVolume)
                                        }) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(menuTextColor)
                                                .frame(width: 32, height: 32)
                                                .background(GlassyBackground(theme: settings.appTheme))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                // Volume Slider
                                HStack(spacing: 12) {
                                    Image(systemName: "speaker.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Slider(value: $settings.alertVolume, in: 0...1)
                                        .accentColor(sliderAccentColor)
                                        .background(
                                            Capsule()
                                                .fill(sliderTrackColor)
                                                .frame(height: 4)
                                        )
                                    
                                    Image(systemName: "speaker.wave.3.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    func updatePosition(_ pos: PanelPosition) {
        settings.panelPosition = pos
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
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    
    private var isWhiteTheme: Bool { theme == .white }
    private var frameStrokeColor: Color { isWhiteTheme ? Color.black.opacity(0.1) : Color.white.opacity(0.1) }
    private var panelColor: Color {
        if isSelected {
            return isWhiteTheme ? Color.blue.opacity(0.9) : Color.white
        }
        return Color.primary.opacity(0.5)
    }
    private var labelColor: Color {
        if isSelected {
            return isWhiteTheme ? .primary : .white
        }
        return .secondary
    }
    private var cardFillColor: Color {
        if isWhiteTheme {
            return isSelected ? Color.black.opacity(0.08) : Color.black.opacity(0.03)
        }
        return isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.05)
    }
    private var cardStrokeColor: Color {
        if isWhiteTheme {
            return isSelected ? Color.black.opacity(0.25) : Color.black.opacity(0.08)
        }
        return isSelected ? Color.white : .clear
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Desktop Visual
                ZStack {
                    // Wallpaper / Screen
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(gradient: Gradient(colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.3)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(frameStrokeColor, lineWidth: 1)
                        )
                    
                    // The App Panel
                    HStack {
                        if position == .right { Spacer() }
                        RoundedRectangle(cornerRadius: 2)
                            .fill(panelColor)
                            .frame(width: 16, height: 48)
                            .padding(position == .left ? .leading : .trailing, 6)
                            .shadow(radius: 2)
                        if position == .left { Spacer() }
                    }
                }
                
                // Label
                Text(position == .left ? "Screen Left" : "Screen Right")
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(labelColor)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(cardStrokeColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

struct GlassyBackground: View {
    let theme: AppTheme

    var body: some View {
        if theme == .glass {
            liquidGlassBackground(cornerRadius: 8)
        } else {
            ZStack {
                if theme == .white {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.95))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.4))

                    RoundedRectangle(cornerRadius: 8)
                        .fill(.thinMaterial)
                        .opacity(0.5)
                }
            }
            .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    theme == .white
                    ? LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.16),
                            Color.black.opacity(0.06)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.05)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
        }
    }
}
