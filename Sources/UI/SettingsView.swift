import SwiftUI
import AppKit

struct SettingsView: View {
    @StateObject private var settings = SettingsStore()
    
    let sounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
    
    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings, sounds: sounds)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 450, height: 400) // Fixed size for settings
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    let sounds: [String]
    
    var body: some View {
        Form {
            // PANEL POSITION
            Section("Panel Position") {
                HStack(spacing: 20) {
                    PositionCard(position: .left, selected: settings.panelPosition == .left) {
                        settings.panelPosition = .left
                        updateWindowPosition(position: .left)
                    }
                    
                    PositionCard(position: .right, selected: settings.panelPosition == .right) {
                        settings.panelPosition = .right
                        updateWindowPosition(position: .right)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // BREAK SETTINGS
            Section("Break Timer") {
                Picker("Default Length", selection: $settings.breakDuration) {
                    Text("5 min").tag(300.0)
                    Text("10 min").tag(600.0)
                    Text("15 min").tag(900.0)
                    Text("30 min").tag(1800.0)
                    Text("45 min").tag(2700.0)
                    Text("1 hour").tag(3600.0)
                }
                .pickerStyle(.menu)
            }
            
            Section("App Behavior") {
                Toggle("Quit app when closing main window", isOn: $settings.quitOnClose)
            }

            Section("Assistant") {
                AssistantSettingsControls(settings: settings, isEmbedded: false)
            }
            
            // ALERT SETTINGS
            Section("Time's Up Alert") {
                Toggle("Enable Sound", isOn: $settings.isAlertEnabled)
                
                if settings.isAlertEnabled {
                    HStack {
                        Picker("Sound", selection: $settings.alertSound) {
                            ForEach(sounds, id: \.self) { sound in
                                Text(sound).tag(sound)
                            }
                        }
                        .disabled(!settings.isAlertEnabled)
                        
                        Button(action: {
                            playSound(named: settings.alertSound, volume: settings.alertVolume)
                        }) {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(!settings.isAlertEnabled)
                    }
                    
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(value: $settings.alertVolume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    .disabled(!settings.isAlertEnabled)
                }
            }
        }
        .padding()
    }
    
    func playSound(named name: String, volume: Double) {
        if let sound = NSSound(named: name) {
            sound.volume = Float(volume)
            sound.play()
        }
    }
    
    func updateWindowPosition(position: PanelPosition) {
        // Post notification or directly update if possible. 
        // Ideally, the main window observes this setting.
        NotificationCenter.default.post(name: NSNotification.Name("UpdatePanelPosition"), object: nil)
    }
}

struct PositionCard: View {
    let position: PanelPosition
    let selected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                // Preview
                ZStack(alignment: position == .left ? .leading : .trailing) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 40)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(selected ? Color.accentColor : Color.gray)
                        .frame(width: 15, height: 36)
                        .padding(position == .left ? .leading : .trailing, 2)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                        .padding(-4)
                )
                
                Text(position.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
