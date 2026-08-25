import SwiftUI

// MARK: - Marquee

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Single-line text that slides back and forth when it doesn't fit.
///
/// The scroll is ONE Core Animation-driven `.offset` (repeatForever +
/// autoreverses), not a per-frame timer: the pill sits on screen for entire
/// work sessions, so a ticking marquee would burn CPU the whole time. easeInOut
/// supplies the pause at each end that a hold keyframe would.
struct MarqueeText: View {
    let text: String
    let width: CGFloat
    var font: Font = .inter(size: 13, weight: .medium)
    var color: Color = .primary
    /// Points per second — long titles take proportionally longer.
    var speed: CGFloat = 26

    @State private var textWidth: CGFloat = 0
    @State private var shifted = false

    private var overflow: CGFloat { max(0, textWidth - width) }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: MarqueeWidthKey.self, value: geo.size.width)
                }
            )
            .offset(x: shifted ? -overflow : 0)
            .frame(width: width, alignment: .leading)
            .clipped()
            .mask(edgeFade)
            .onPreferenceChange(MarqueeWidthKey.self) { measured in
                guard abs(measured - textWidth) > 0.5 else { return }
                textWidth = measured
                restartAnimation()
            }
            .onAppear { restartAnimation() }
    }

    /// Only fade the edge the text actually runs past; a static title that fits
    /// shouldn't look clipped.
    private var edgeFade: some View {
        let needsFade = overflow > 0.5
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: needsFade ? 0.94 : 1),
                .init(color: needsFade ? .clear : .black, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func restartAnimation() {
        let distance = overflow
        guard distance > 0.5 else {
            withAnimation(.easeOut(duration: 0.2)) { shifted = false }
            return
        }
        let duration = Double(distance / speed) + 1.6   // +hold at each end
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            shifted = true
        }
    }
}

/// Equatable wrapper: the pill redraws on every timer tick, and re-evaluating
/// the marquee would restart its animation each second.
struct PillTitleView: View, Equatable {
    let title: String
    let color: Color
    var width: CGFloat = 186

    var body: some View {
        MarqueeText(
            text: title,
            width: width,
            font: .inter(size: 13, weight: .medium),
            color: color
        )
    }

    static func == (lhs: PillTitleView, rhs: PillTitleView) -> Bool {
        lhs.title == rhs.title && lhs.width == rhs.width
    }
}

// MARK: - Controls

enum PillControlTone {
    case neutral
    case danger
    case go
}

/// One monochrome 28×28 control in the pill's hover row. The old build used
/// red/yellow/green traffic-light dots; the redesign keeps the pill plain and
/// puts colour only in the progress rail and alert states.
struct PillControlButton: View {
    let icon: String
    let help: String
    var tone: PillControlTone = .neutral
    var isActive: Bool = false
    let palette: HelpyPalette
    let action: () -> Void

    @State private var isHovering = false

    private var iconColor: Color {
        if isHovering {
            switch tone {
            case .neutral: return palette.ink
            case .danger: return palette.dangerHoverIcon
            case .go: return palette.goHoverIcon
            }
        }
        return isActive ? palette.ink : palette.controlIcon
    }

    private var fillColor: Color {
        guard isHovering else { return isActive ? palette.controlHoverFill : .clear }
        switch tone {
        case .neutral: return palette.controlHoverFill
        case .danger: return palette.dangerHoverFill
        case .go: return palette.goHoverFill
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(fillColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.13)) { isHovering = hover }
        }
        .help(help)
    }
}

// MARK: - Timer

struct PillTimerDisplay: View {
    @ObservedObject var ticker: TimeTicker
    @ObservedObject var service: TimerService
    let palette: HelpyPalette

    var body: some View {
        Text(service.formattedTime())
            .font(.inter(size: 17, weight: .bold))
            .monospacedDigit()
            .foregroundColor(service.isOvertime ? palette.warm : palette.ink)
            .contentTransition(.numericText(countsDown: !service.isStopwatch && !service.isOvertime))
            .animation(.snappy, value: service.formattedTime())
            .fixedSize()
    }
}
