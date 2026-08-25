import Foundation
import SwiftUI

enum PanelPosition: String, CaseIterable {
    case left
    case right
}

class SettingsStore: ObservableObject {
    @AppStorage("panelPosition") var panelPosition: PanelPosition = .left
    @AppStorage("breakDuration") var breakDuration: Double = 300 // 5 minutes default
    
    // Alert Settings
    @AppStorage("isAlertEnabled") var isAlertEnabled: Bool = true
    @AppStorage("alertSound") var alertSound: String = "Glass"
    @AppStorage("alertVolume") var alertVolume: Double = 1.0
    
    // Task Alerts
    @AppStorage("isTaskAlertEnabled") var isTaskAlertEnabled: Bool = false
    @AppStorage("taskAlertInterval") var taskAlertInterval: Double = 600.0
    @AppStorage("taskAlertSound") var taskAlertSound: String = "Tink"
    @AppStorage("taskAlertVolume") var taskAlertVolume: Double = 0.5
    
    // Appearance
    // Helpy has one design (see Theme.swift). It follows the system light/dark
    // appearance, so there is no stored theme or accent preference.
    @AppStorage("pillDisplayMode") var pillDisplayMode: PillDisplayMode = .floatingPill
    @AppStorage("panelHeightMode") var panelHeightMode: PanelHeightMode = .full

    // App lifecycle
    @AppStorage("quitOnClose") var quitOnClose: Bool = true

    // Assistant
    @AppStorage("assistantEnabled") var assistantEnabled: Bool = true
    @AppStorage("assistantOllamaBaseURL") var assistantOllamaBaseURL: String = "http://127.0.0.1:11434"
    @AppStorage("assistantOllamaModel") var assistantOllamaModel: String = "qwen3.5:0.8b"
    @AppStorage("assistantTranscriptionCommand") var assistantTranscriptionCommand: String = ""
    @AppStorage("assistantTranscriptionArgs") var assistantTranscriptionArgs: String = ""
    @AppStorage("assistantTranscriptionModelPath") var assistantTranscriptionModelPath: String = ""
    @AppStorage("assistantMaxDrafts") var assistantMaxDrafts: Int = 5

    init() {
        applyRecommendedAssistantDefaultsIfNeeded()
    }

    func applyRecommendedAssistantDefaultsIfNeeded() {
        let defaultTranscriptionCommand = AssistantBundledAssets.transcriptionCommandPath ?? "/opt/homebrew/bin/whisper-cli"
        let defaultTranscriptionArgs = "-m {model} -f {input} -nt"
        let defaultTranscriptionModelPath = AssistantBundledAssets.transcriptionModelPath ?? InstalledTranscriptionModels.recommendedDefaultModelPath

        if assistantTranscriptionCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           FileManager.default.isExecutableFile(atPath: defaultTranscriptionCommand) {
            assistantTranscriptionCommand = defaultTranscriptionCommand
        }

        if assistantTranscriptionArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            assistantTranscriptionArgs = defaultTranscriptionArgs
        }

        if assistantTranscriptionModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           FileManager.default.fileExists(atPath: defaultTranscriptionModelPath) {
            assistantTranscriptionModelPath = defaultTranscriptionModelPath
        }
    }
}

enum PillDisplayMode: String, CaseIterable {
    case floatingPill
    case menuBarIcon
}

enum PanelHeightMode: String, CaseIterable {
    case short
    case medium
    case full

    var fraction: CGFloat {
        switch self {
        case .short: return 0.42
        case .medium: return 0.65
        case .full: return 1.0
        }
    }

    var label: String {
        switch self {
        case .short: return "Short"
        case .medium: return "Medium"
        case .full: return "Full"
        }
    }
}
