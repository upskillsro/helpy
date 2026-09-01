import SwiftUI
import AppKit

/// A clock whose digits roll, drawn by Core Animation rather than SwiftUI.
///
/// **Why not `.contentTransition(.numericText)`.** That modifier renders each
/// digit into an offscreen bitmap and cross-fades them through a Gaussian blur
/// on every frame of the transition. Fired once a second on a 120Hz display it
/// measured ~13% CPU, and it was the single largest cost the pill had. The cost
/// is the glyph work, not the pill: the same clock alone in a 60x30 window
/// measured the same 13%, and giving it its own layer with `drawingGroup()`
/// made it *worse* (~16%), so neither shrinking the repaint area nor capping
/// the frame rate is the answer.
///
/// Here every glyph 0-9 is rasterised **once** into a single tall strip. Each
/// digit is a layer showing one window onto that strip, and a change animates
/// `contentsRect`, which the render server interpolates. No glyph is ever
/// rasterised again, so the roll costs the same whether it fires once a minute
/// or once a second: measured ~0.2%, cheaper than not animating at all.
struct RollingTimeText: NSViewRepresentable {
    /// Digits roll; every other character (":" and the overtime "+") is static.
    let text: String
    var font: NSFont
    var color: NSColor

    func makeNSView(context: Context) -> RollingTimeView {
        let view = RollingTimeView()
        view.configure(text: text, font: font, color: color, animated: false)
        return view
    }

    func updateNSView(_ view: RollingTimeView, context: Context) {
        view.configure(text: text, font: font, color: color, animated: true)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RollingTimeView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

final class RollingTimeView: NSView {
    /// The strip is two descending 9…0 cycles, so row `r` shows `9 - (r % 10)`.
    ///
    /// Descending rows mean travel direction maps straight onto counting
    /// direction: moving *down* the strip decrements the digit, moving *up*
    /// increments it. Two cycles give enough runway to cross a 0 → 9 wrap in
    /// one continuous move, after which the layer re-seats onto the identical
    /// row a cycle away — invisibly, because both rows show the same glyph.
    static let cycle = 10
    static let rowCount = 20
    static func digit(atRow row: Int) -> Int { 9 - (row % cycle) }
    static func row(showing digit: Int) -> Int { 9 - digit }

    /// Where a digit change travels on the strip.
    ///
    /// Down the strip decrements, up increments; whichever is the shorter
    /// travel wins, so a countdown crossing 0 -> 9 moves one row rather than
    /// spinning nine. `from` may sit a cycle below `current` when going up —
    /// the two rows show the same glyph, so re-seating there is invisible —
    /// and `settled` is always back inside `0..<cycle`.
    static func travel(fromRow current: Int, showing currentDigit: Int, to digit: Int)
        -> (from: Int, to: Int, settled: Int) {
        let down = (currentDigit - digit + cycle) % cycle
        let up = (digit - currentDigit + cycle) % cycle
        let target = down <= up ? current + down : current - up
        let from = target < 0 ? current + cycle : current
        let to = target < 0 ? target + cycle : target
        return (from, to, ((to % cycle) + cycle) % cycle)
    }

    private struct Style: Equatable {
        let fontName: String
        let fontSize: CGFloat
        let color: NSColor
    }

    /// One character position. Digits carry a current row into the strip;
    /// static characters just carry their own bitmap.
    private struct Slot {
        let layer: CALayer
        let isDigit: Bool
        /// Always kept in `0..<cycle` between rolls.
        var row: Int
        var digit: Int
    }

    private var slots: [Slot] = []
    private var strip: NSImage?
    private var digitSize = CGSize.zero
    private var style: Style?
    /// The digit/non-digit pattern the current slots were built for. A change
    /// of shape (MM:SS → HH:MM:SS, or overtime's leading "+") rebuilds them.
    private var shape = ""

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        guard !slots.isEmpty else {
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        let width = slots.reduce(0) { $0 + $1.layer.bounds.width }
        return NSSize(width: ceil(width), height: ceil(digitSize.height))
    }

    func configure(text: String, font: NSFont, color: NSColor, animated: Bool) {
        let nextStyle = Style(fontName: font.fontName, fontSize: font.pointSize, color: color)
        let nextShape = text.map { $0.isNumber ? "#" : String($0) }.joined()

        if style != nextStyle || shape != nextShape {
            rebuild(text: text, font: font, color: color, style: nextStyle, shape: nextShape)
        } else {
            apply(text: text, animated: animated)
        }
    }

    // MARK: - Building

    private func rebuild(text: String, font: NSFont, color: NSColor, style: Style, shape: String) {
        self.style = style
        self.shape = shape

        wantsLayer = true
        let host = layer ?? CALayer()
        layer = host
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        slots.removeAll()

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]

        // Every digit gets the same cell width so the clock never jitters —
        // this is what `.monospacedDigit()` did for the SwiftUI version.
        var cell = CGSize.zero
        for d in 0...9 {
            let size = NSAttributedString(string: String(d), attributes: attributes).size()
            cell.width = max(cell.width, size.width)
            cell.height = max(cell.height, size.height)
        }
        digitSize = CGSize(width: ceil(cell.width), height: ceil(cell.height))
        strip = makeStrip(attributes: attributes)

        let scale = window?.backingScaleFactor ?? 2
        var x: CGFloat = 0
        for character in text {
            let layer = CALayer()
            layer.contentsScale = scale

            if character.isNumber {
                let digit = character.wholeNumberValue ?? 0
                let row = Self.row(showing: digit)
                layer.contents = strip
                layer.masksToBounds = true
                layer.frame = CGRect(x: x, y: 0, width: digitSize.width, height: digitSize.height)
                layer.contentsRect = Self.rowRect(row)
                slots.append(Slot(layer: layer, isDigit: true, row: row, digit: digit))
                x += digitSize.width
            } else {
                let string = NSAttributedString(string: String(character), attributes: attributes)
                let size = string.size()
                let width = ceil(size.width)
                let image = NSImage(size: NSSize(width: width, height: digitSize.height))
                image.lockFocus()
                string.draw(at: NSPoint(x: 0, y: (digitSize.height - size.height) / 2))
                image.unlockFocus()
                layer.contents = image
                layer.frame = CGRect(x: x, y: 0, width: width, height: digitSize.height)
                slots.append(Slot(layer: layer, isDigit: false, row: 0, digit: -1))
                x += width
            }
            host.addSublayer(layer)
        }

        invalidateIntrinsicContentSize()
    }

    private func makeStrip(attributes: [NSAttributedString.Key: Any]) -> NSImage {
        let size = NSSize(width: digitSize.width, height: digitSize.height * CGFloat(Self.rowCount))
        let image = NSImage(size: size)
        image.lockFocus()
        for row in 0..<Self.rowCount {
            let string = NSAttributedString(string: String(Self.digit(atRow: row)), attributes: attributes)
            let glyph = string.size()
            // AppKit draws from the bottom, so row 0 has to sit at the top.
            string.draw(at: NSPoint(x: (digitSize.width - glyph.width) / 2,
                                    y: size.height - digitSize.height * CGFloat(row + 1)))
        }
        image.unlockFocus()
        return image
    }

    private static func rowRect(_ row: Int) -> CGRect {
        CGRect(x: 0, y: CGFloat(row) / CGFloat(rowCount), width: 1, height: 1 / CGFloat(rowCount))
    }

    // MARK: - Rolling

    private func apply(text: String, animated: Bool) {
        for (index, character) in text.enumerated() where index < slots.count {
            guard slots[index].isDigit, let digit = character.wholeNumberValue else { continue }
            guard digit != slots[index].digit else { continue }
            roll(slot: index, to: digit, animated: animated)
        }
    }

    private func roll(slot index: Int, to digit: Int, animated: Bool) {
        let layer = slots[index].layer
        let (from, to, settled) = Self.travel(
            fromRow: slots[index].row,
            showing: slots[index].digit,
            to: digit
        )

        slots[index].digit = digit
        slots[index].row = settled

        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.removeAnimation(forKey: "roll")
            layer.contentsRect = Self.rowRect(settled)
            CATransaction.commit()
            return
        }

        let roll = CABasicAnimation(keyPath: "contentsRect")
        roll.fromValue = Self.rowRect(from)
        roll.toValue = Self.rowRect(to)
        roll.duration = 0.32
        roll.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Land on the settled row up front so there is no flash if the
        // animation is dropped; the animation supplies the travel.
        layer.contentsRect = Self.rowRect(settled)
        layer.add(roll, forKey: "roll")
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        slots.forEach { $0.layer.contentsScale = scale }
    }
}
