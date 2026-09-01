import SwiftUI
import AppKit

// MARK: - Marquee

/// Single-line text that slides back and forth when it doesn't fit.
///
/// The scroll is one Core Animation on a layer whose glyphs were rasterised
/// once (see `CAMarqueeText`). The earlier SwiftUI version — `repeatForever`
/// on `.offset`, clipped and masked — looked equivalent but re-rasterised
/// every glyph on every frame, ~8% CPU for as long as a task was active.
struct MarqueeText: View {
    let text: String
    let width: CGFloat
    var font: NSFont = .inter(size: 13, weight: .medium)
    var color: Color = .primary
    /// Points per second — long titles take proportionally longer.
    var speed: CGFloat = 26

    var body: some View {
        CAMarqueeText(
            text: text,
            width: width,
            font: font,
            color: NSColor(color),
            speed: speed
        )
        .frame(width: width)
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
        // The roll is Core Animation (see `RollingTimeText`). The previous
        // `.contentTransition(.numericText)` + `.animation(.snappy)` fired a
        // blurred per-frame glyph morph every second and cost ~13% CPU on a
        // 120Hz display — the pill's single largest expense.
        RollingTimeText(
            text: service.formattedTime(),
            font: .inter(size: 17, weight: .bold),
            color: NSColor(service.isOvertime ? palette.warm : palette.ink)
        )
        .fixedSize()
    }
}
