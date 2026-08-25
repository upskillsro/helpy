import SwiftUI

struct AssistantSettingsControls: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var ollamaModels = LocalOllamaModelStore()
    @State private var assistantStatusMessage: String?
    @State private var showAdvanced = false

    /// True inside Helpy's own settings pane, false in the standard macOS
    /// Settings window — the latter keeps AppKit's native control chrome.
    let isEmbedded: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var availableModels: [String] {
        let detected = ollamaModels.models.map(\.name)
        let current = settings.assistantOllamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = current.isEmpty ? detected : detected + [current]
        return Array(Set(combined)).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if isEmbedded {
                    Text("Enable Assistant")
                        .font(.inter(size: 13))
                        .foregroundColor(t.ink)
                    Spacer()
                    Toggle("", isOn: $settings.assistantEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: t.accent))
                        .labelsHidden()
                } else {
                    Toggle("Enable Assistant", isOn: $settings.assistantEnabled)
                    Spacer()
                }
                Button(showAdvanced ? "Hide advanced" : "Advanced") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAdvanced.toggle()
                    }
                }
                .buttonStyle(HelpyQuietButtonStyle(palette: t))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Assistant model")
                        .font(.inter(size: 11))
                        .foregroundColor(t.muted)
                    Spacer()
                    Button {
                        Task {
                            await refreshDetectedModels()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(HelpyQuietButtonStyle(palette: t))
                    .help("Refresh detected Ollama models")
                }

                if availableModels.isEmpty {
                    assistantTextFieldControl("Ollama Model", text: $settings.assistantOllamaModel)
                } else {
                    Picker("Assistant model", selection: $settings.assistantOllamaModel) {
                        ForEach(availableModels, id: \.self) { modelName in
                            Text(modelName).tag(modelName)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .modifier(AssistantFieldChrome(palette: t, enabled: isEmbedded))
                }

                if !ollamaModels.models.isEmpty {
                    Text("Detected \(ollamaModels.models.count) local model\(ollamaModels.models.count == 1 ? "" : "s").")
                        .font(.inter(size: 11))
                        .foregroundColor(t.muted)
                }

                if let lastError = ollamaModels.lastError {
                    Text(lastError)
                        .font(.inter(size: 11))
                        .foregroundColor(t.muted)
                }

                Text("Use Handy for dictation if you want voice, then paste the transcript here.")
                    .font(.inter(size: 11))
                    .foregroundColor(t.muted)
            }

            if showAdvanced {
                advancedFields
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let assistantStatusMessage {
                Text(assistantStatusMessage)
                    .font(.inter(size: 11))
                    .foregroundColor(t.muted)
            }
        }
        .task(id: settings.assistantOllamaBaseURL) {
            await refreshDetectedModels()
        }
    }

    @ViewBuilder
    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            assistantField(title: "Ollama Base URL", text: $settings.assistantOllamaBaseURL)
            Text("Advanced settings only affect the local Ollama connection. Helpy's assistant is text-only for now.")
                .font(.inter(size: 11))
                .foregroundColor(t.muted)

            assistantActionButton("Test Ollama") {
                Task {
                    let coordinator = AssistantCoordinator()
                    assistantStatusMessage = await coordinator.testOllamaConnection()
                    await refreshDetectedModels()
                }
            }
        }
    }

    @ViewBuilder
    private func assistantField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.inter(size: 11))
                .foregroundColor(t.muted)
            assistantTextFieldControl(title, text: text)
        }
    }

    private func refreshDetectedModels() async {
        await ollamaModels.load(from: settings.assistantOllamaBaseURL)
    }

    @ViewBuilder
    private func assistantTextFieldControl(_ title: String, text: Binding<String>) -> some View {
        if isEmbedded {
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .modifier(AssistantFieldChrome(palette: t, enabled: true))
        } else {
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func assistantActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        if isEmbedded {
            Button(title, action: action)
                .buttonStyle(.plain)
                .modifier(AssistantButtonChrome(palette: t, enabled: true))
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)   // native Settings window keeps AppKit chrome
        }
    }
}

private struct AssistantFieldChrome: ViewModifier {
    let palette: HelpyPalette
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .font(.inter(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .foregroundColor(palette.ink)
                .helpyCard(palette, fill: palette.fieldFill, border: palette.fieldBorder, cornerRadius: 10)
        } else {
            content
        }
    }
}

private struct AssistantButtonChrome: ViewModifier {
    let palette: HelpyPalette
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .font(.inter(size: 12, weight: .medium))
                .foregroundColor(palette.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .helpyCard(palette, fill: palette.fieldFill, border: palette.fieldBorder, cornerRadius: 10)
        } else {
            content
        }
    }
}
