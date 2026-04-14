import SwiftUI
import AppKit

struct IceGlassSurface: View {
    var cornerRadius: CGFloat? = nil
    var material: NSVisualEffectView.Material = .underWindowBackground
    var secondaryMaterial: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var secondaryOpacity: Double = 0.78
    var tintOpacity: Double = 0.012
    var highlightOpacity: Double = 0.14
    var glowOpacity: Double = 0.055
    var grainOpacity: Double = 0.035

    var body: some View {
        Group {
            if let cornerRadius {
                layers
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                layers
            }
        }
    }

    private var layers: some View {
        ZStack {
            VisualEffectView(material: material, blendingMode: blendingMode)

            VisualEffectView(material: secondaryMaterial, blendingMode: blendingMode)
                .opacity(secondaryOpacity)

            Color(red: 0.92, green: 0.98, blue: 0.95).opacity(tintOpacity)

            LinearGradient(
                colors: [
                    Color.white.opacity(highlightOpacity * 0.55),
                    Color(red: 0.9, green: 0.98, blue: 0.95).opacity(highlightOpacity),
                    Color(red: 0.78, green: 0.92, blue: 0.88).opacity(highlightOpacity * 0.38)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.8, green: 0.94, blue: 0.9).opacity(glowOpacity),
                    .clear
                ],
                center: .topLeading,
                startRadius: 8,
                endRadius: 240
            )

            IceGrainOverlay(opacity: grainOpacity)
        }
        .allowsHitTesting(false)
    }
}

struct IceGlassStroke: View {
    var cornerRadius: CGFloat
    var opacity: Double = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.62 * opacity),
                        Color(red: 0.88, green: 0.98, blue: 0.95).opacity(0.32 * opacity),
                        Color(red: 0.78, green: 0.92, blue: 0.88).opacity(0.28 * opacity)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

struct IceGrainOverlay: View {
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 2.0
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    let noise = deterministicNoise(x: x, y: y)
                    if noise > 0.82 {
                        let alpha = (noise - 0.82) * 2.2 * opacity
                        let dot = CGRect(x: x, y: y, width: 1, height: 1)
                        context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(alpha)))
                    } else if noise < 0.08 {
                        let alpha = (0.08 - noise) * 1.5 * opacity
                        let dot = CGRect(x: x, y: y, width: 1, height: 1)
                        context.fill(Path(ellipseIn: dot), with: .color(.black.opacity(alpha * 0.18)))
                    }
                    y += step
                }
                x += step
            }
        }
        .allowsHitTesting(false)
    }

    private func deterministicNoise(x: CGFloat, y: CGFloat) -> Double {
        let value = sin(Double(x) * 12.9898 + Double(y) * 78.233) * 43758.5453
        return value - floor(value)
    }
}

/// Returns the appropriate glass background for the current OS.
/// On macOS 26+, uses Apple's native Liquid Glass via `.glassEffect()`.
/// On earlier macOS, falls back to the custom IceGlassSurface.
@ViewBuilder
func liquidGlassBackground(cornerRadius: CGFloat) -> some View {
    if #available(macOS 26.0, *) {
        Color.clear
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    } else {
        VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
