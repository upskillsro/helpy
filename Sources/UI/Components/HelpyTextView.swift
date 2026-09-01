import AppKit
import SwiftUI

/// A plain-text box that grows with its content and treats Return as a line
/// break.
///
/// SwiftUI's `TextField(axis: .vertical)` commits on Return on macOS and no
/// modifier changes that, so anything meant to hold more than one paragraph has
/// to be an `NSTextView`. This one sizes itself to its text instead of
/// scrolling: every place it is used already sits inside a scroll view, and a
/// nested scroller would swallow the wheel.
struct HelpyTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: Color
    var lineSpacing: CGFloat = 0
    /// Floor for the box, so a short note still has a target big enough to
    /// click into.
    var minHeight: CGFloat = 0

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextView {
        // An explicit TextKit 1 stack. A bare `NSTextView()` comes up on
        // TextKit 2 and only falls back the first time `layoutManager` is
        // touched, which is exactly what the height measurement below does —
        // so build the stack we are going to measure with up front.
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)

        // The layout manager's back-reference to its storage is not an owning
        // one, so the coordinator holds it for the life of the view.
        context.coordinator.storage = storage

        let view = NSTextView(frame: .zero, textContainer: container)
        view.delegate = context.coordinator
        view.isRichText = false
        view.drawsBackground = false
        view.allowsUndo = true
        // Substitutions rewrite what the user typed behind their back, and the
        // value here is stored as plain text elsewhere in the app.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.textContainerInset = NSSize(width: 0, height: 0)
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.string = text
        applyStyle(to: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.text = $text
        // Assigning `string` moves the insertion point, so only do it when the
        // value actually came from somewhere other than this view.
        if view.string != text {
            view.string = text
            context.coordinator.styleSignature = nil
        }
        applyStyle(to: view, coordinator: context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let container = nsView.textContainer, let manager = nsView.layoutManager else { return nil }
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0, width < .greatestFiniteMagnitude else { return nil }

        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        // An empty box still has to be one line tall or the placeholder has
        // nowhere to sit.
        let used = manager.usedRect(for: container).height
        let oneLine = manager.defaultLineHeight(for: font)
        return CGSize(width: width, height: max(minHeight, ceil(max(used, oneLine))))
    }

    /// Typing attributes cover what comes next; the text storage pass covers
    /// what is already there, which is what makes a theme switch repaint text
    /// the user typed in the other appearance.
    ///
    /// Only when the style actually changed. Rewriting the storage on every
    /// update means doing it on every keystroke, which walks over marked text —
    /// the half-composed state a dead key or an IME is in mid-character.
    private func applyStyle(to view: NSTextView, coordinator: Coordinator) {
        let signature = "\(font.fontName)|\(font.pointSize)|\(lineSpacing)|\(textColor)"
        guard coordinator.styleSignature != signature else { return }
        coordinator.styleSignature = signature

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(textColor),
            .paragraphStyle: paragraph
        ]
        view.typingAttributes = attributes
        view.insertionPointColor = NSColor(textColor)
        if let storage = view.textStorage, storage.length > 0 {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var storage: NSTextStorage?
        var styleSignature: String?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}

/// `HelpyTextView` with a placeholder. The placeholder is a SwiftUI overlay
/// rather than anything on the text view: AppKit only exposes one on
/// `NSTextField`, and this is deliberately not a field.
struct HelpyNotesField: View {
    let placeholder: String
    @Binding var text: String
    var font: NSFont
    var textColor: Color
    var placeholderColor: Color
    var lineSpacing: CGFloat = 0
    var minHeight: CGFloat = 0

    var body: some View {
        HelpyTextView(
            text: $text,
            font: font,
            textColor: textColor,
            lineSpacing: lineSpacing,
            minHeight: minHeight
        )
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(Font(font))
                        .foregroundStyle(placeholderColor)
                        .allowsHitTesting(false)
                }
            }
    }
}
