import SwiftUI

/// The "task done" burst: one expanding ring plus eight dots fired along fixed
/// spokes.
///
/// Deliberately monochrome — it takes the checkbox's own tint so it reads as
/// the check landing rather than as confetti. The previous version threw twelve
/// randomly coloured circles in random directions, which fought a design that
/// spends its colour budget on a single accent.
///
/// Two independent drivers so position and opacity can have different curves:
/// `spread` eases OUT (fast launch, gentle settle), `fade` eases IN (holds
/// visible, then drops). Sharing one value made the dots vanish before they
/// had travelled anywhere.
struct ParticleEffectView: View {
    @Binding var trigger: Bool
    var tint: Color = .accentColor

    @State private var isFiring = false
    @State private var spread: CGFloat = 0
    @State private var fade: Double = 0

    private static let spokes: [Double] = (0..<8).map { Double($0) * 45 }
    private let travel: CGFloat = 16

    var body: some View {
        ZStack {
            if isFiring {
                Circle()
                    .strokeBorder(tint, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                    .scaleEffect(0.45 + spread * 1.15)
                    .opacity(fade * 0.9)

                ForEach(Array(Self.spokes.enumerated()), id: \.offset) { _, angle in
                    let radians = angle * .pi / 180
                    Circle()
                        .fill(tint)
                        .frame(width: 3, height: 3)
                        .offset(
                            x: cos(radians) * travel * spread,
                            y: sin(radians) * travel * spread
                        )
                        .opacity(fade)
                }
            }
        }
        .frame(width: 46, height: 46)
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, isTriggered in
            if isTriggered { fire() }
        }
    }

    private func fire() {
        isFiring = true
        spread = 0
        fade = 1

        withAnimation(.easeOut(duration: 0.5)) { spread = 1 }
        withAnimation(.easeIn(duration: 0.45)) { fade = 0 }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            isFiring = false
        }
    }
}
