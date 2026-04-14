import SwiftUI

/// Applies native Liquid Glass at the container level so child content inherits
/// an adaptive color scheme from the sampled background.
struct LiquidGlassContainerModifier: ViewModifier {
    let isGlass: Bool
    let cornerRadius: CGFloat
    var interactive: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isGlass {
            if #available(macOS 26.0, *) {
                content.glassEffect(
                    .regular.interactive(interactive),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            } else {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    func liquidGlassContainer(
        isGlass: Bool,
        cornerRadius: CGFloat,
        interactive: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassContainerModifier(
                isGlass: isGlass,
                cornerRadius: cornerRadius,
                interactive: interactive
            )
        )
    }
}
