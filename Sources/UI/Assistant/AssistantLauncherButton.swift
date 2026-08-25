import SwiftUI

struct AssistantLauncherButton: View {
    let isOpen: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    private var t: HelpyPalette { .forScheme(colorScheme) }

    var body: some View {
        Button(action: action) {
            Image(systemName: isOpen ? "xmark" : "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isOpen ? t.accent : (isHovering ? t.ink : t.muted))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isOpen ? t.accent.opacity(0.12)
                                     : (isHovering ? t.controlHoverFill : Color.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hover }
        }
        .help(isOpen ? "Close Assistant" : "Open Assistant")
    }
}
