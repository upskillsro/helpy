import AppKit
import SwiftUI

struct AssistantPromptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    let fontSize: CGFloat = 13
    let horizontalInset: CGFloat = 14
    let verticalInset: CGFloat = 12

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: horizontalInset, height: verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        scrollView.documentView = textView
        update(textView: textView)
        context.coordinator.updateMeasuredHeight(for: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        update(textView: textView)
        context.coordinator.updateMeasuredHeight(for: textView)
    }

    private func update(textView: NSTextView) {
        let palette = HelpyPalette.forScheme(colorScheme)
        textView.font = .inter(size: fontSize)
        textView.textColor = NSColor(palette.ink)
        textView.insertionPointColor = NSColor(palette.accent)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var contentHeight: CGFloat

        init(text: Binding<String>, contentHeight: Binding<CGFloat>) {
            _text = text
            _contentHeight = contentHeight
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            updateMeasuredHeight(for: textView)
        }

        func updateMeasuredHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let measuredHeight = ceil(usedRect.height + textView.textContainerInset.height * 2)

            if abs(contentHeight - measuredHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.contentHeight = measuredHeight
                }
            }
        }
    }
}
