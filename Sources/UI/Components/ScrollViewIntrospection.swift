import SwiftUI
import AppKit

struct ScrollConfigurator: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ScrollViewIntrospector())
    }
}

extension View {
    func configureScrollView() -> some View {
        self.modifier(ScrollConfigurator())
    }
}

struct ScrollViewIntrospector: NSViewRepresentable {
    final class Coordinator {
        var didConfigure = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.didConfigure else { return }

        DispatchQueue.main.async {
            guard let scrollView = nsView.enclosingScrollView else { return }
            context.coordinator.didConfigure = true

            scrollView.scrollerStyle = .overlay
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.drawsBackground = false

            // Deliberately does NOT touch contentInsets: SwiftUI hoists the
            // content's own padding into them, and zeroing them here silently
            // deletes that padding.
        }
    }
}
