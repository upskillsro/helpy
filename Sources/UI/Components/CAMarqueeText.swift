import SwiftUI
import AppKit

/// Single-line text that slides back and forth when it doesn't fit, drawn by
/// Core Animation rather than SwiftUI.
///
/// **Why not a SwiftUI `.offset`.** The obvious version — a `repeatForever`
/// animation on `.offset`, clipped and masked — reads as if Core Animation
/// drives it, but it does not. SwiftUI cannot hand a masked, clipped subtree to
/// the render server as a layer transform, so it rebuilds the pill's display
/// list and re-rasterises every glyph on every frame. Profiled on a 120Hz
/// display that alone cost ~8% CPU for as long as a task was active, and it
/// was ~7% of the pill's measured 26%.
///
/// Here the glyphs are rasterised **once** into a bitmap and the layer's
/// position is animated. The render server interpolates it, this process does
/// nothing per frame, and the same scroll measures ~0.2%. Swapping the mask for
/// an overlay or shortening the animation were both tried first and neither
/// helped: the cost is the per-frame glyph work, not the mask.
struct CAMarqueeText: NSViewRepresentable {
    let text: String
    let width: CGFloat
    var font: NSFont
    var color: NSColor
    /// Points per second — long titles take proportionally longer.
    var speed: CGFloat = 26

    func makeNSView(context: Context) -> CAMarqueeView { CAMarqueeView() }

    func updateNSView(_ view: CAMarqueeView, context: Context) {
        view.configure(text: text, width: width, font: font, color: color, speed: speed)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CAMarqueeView, context: Context) -> CGSize? {
        CGSize(width: width, height: nsView.contentHeight)
    }
}

final class CAMarqueeView: NSView {
    private let textLayer = CALayer()
    private let fade = CAGradientLayer()
    private var applied: Applied?

    private struct Applied: Equatable {
        let text: String
        let width: CGFloat
        let fontName: String
        let fontSize: CGFloat
        let color: NSColor
        let speed: CGFloat
    }

    private(set) var contentHeight: CGFloat = 17

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: applied?.width ?? NSView.noIntrinsicMetric, height: contentHeight)
    }

    func configure(text: String, width: CGFloat, font: NSFont, color: NSColor, speed: CGFloat) {
        let next = Applied(text: text, width: width, fontName: font.fontName,
                           fontSize: font.pointSize, color: color, speed: speed)
        guard applied != next else { return }
        applied = next

        wantsLayer = true
        let host = layer ?? CALayer()
        layer = host
        host.masksToBounds = true

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        contentHeight = ceil(size.height)

        // The one and only rasterisation of these glyphs.
        let image = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)))
        image.lockFocus()
        string.draw(at: .zero)
        image.unlockFocus()

        textLayer.contents = image
        textLayer.contentsScale = window?.backingScaleFactor ?? 2
        textLayer.anchorPoint = CGPoint(x: 0, y: 0)
        textLayer.frame = CGRect(x: 0, y: 0, width: ceil(size.width), height: ceil(size.height))
        textLayer.removeAllAnimations()
        if textLayer.superlayer == nil { host.addSublayer(textLayer) }

        let overflow = max(0, ceil(size.width) - width)
        if overflow > 0.5 {
            // ONE animation on the layer's position. easeInEaseOut supplies the
            // pause at each end that a hold keyframe would.
            let scroll = CABasicAnimation(keyPath: "position.x")
            scroll.fromValue = 0
            scroll.toValue = -overflow
            scroll.duration = Double(overflow / speed) + 1.6
            scroll.autoreverses = true
            scroll.repeatCount = .infinity
            scroll.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            textLayer.add(scroll, forKey: "marquee")

            // Only fade the edge the text actually runs past; a static title
            // that fits shouldn't look clipped. The gradient is a GPU mask set
            // once, not something redrawn with the scroll.
            fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
            fade.locations = [0, 0.94, 1]
            fade.startPoint = CGPoint(x: 0, y: 0.5)
            fade.endPoint = CGPoint(x: 1, y: 0.5)
            host.mask = fade
        } else {
            host.mask = nil
        }

        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        textLayer.contentsScale = window?.backingScaleFactor ?? 2
    }
}
