import SwiftUI
import AppKit

/// The Settings window. It hosts the very same view the side strip does, so
/// there is one settings screen in Helpy rather than two that drift apart —
/// the system Form version had already fallen behind on several settings.
struct SettingsView: View {
    @StateObject private var settings = SettingsStore()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        EmbeddedSettingsView(settings: settings, onClose: { dismiss() })
            .frame(width: 440, height: 640)
    }
}
