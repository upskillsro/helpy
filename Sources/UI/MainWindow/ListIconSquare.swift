import AppKit
import EventKit
import SwiftUI
import UniformTypeIdentifiers

/// A list's icon: an uploaded image if there is one, otherwise a monogram on the
/// list's own Reminders colour.
///
/// The store's `revision` is read in the body on purpose — a file path never
/// looks different to SwiftUI, so without it a freshly uploaded icon would not
/// appear until something else redrew the cell.
struct ListIconSquare: View {
    let listId: String
    let title: String
    let color: Color
    var side: CGFloat = 17
    var cornerRadius: CGFloat = 5
    /// Set on the grid cell so a dropped image lands on the right list.
    var acceptsDrop: Bool = false

    @EnvironmentObject var iconStore: ListIconStore
    @State private var isTargeted = false

    private var fontSize: CGFloat { max(8, side * 0.5) }

    var body: some View {
        let _ = iconStore.revision

        Group {
            if let image = iconStore.image(for: listId) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                color.overlay(
                    Text(ListMonogram.letter(for: title))
                        .font(.inter(size: fontSize, weight: .bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                )
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
        )
        .modifier(IconDropTarget(enabled: acceptsDrop, listId: listId, isTargeted: $isTargeted))
    }
}

/// Drag an image onto the square to set the icon. Applied conditionally so the
/// small read-only copies in toolbars are not drop targets.
private struct IconDropTarget: ViewModifier {
    let enabled: Bool
    let listId: String
    @Binding var isTargeted: Bool

    @EnvironmentObject var iconStore: ListIconStore

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
                loadIcon(from: providers)
            }
        } else {
            content
        }
    }

    private func loadIcon(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in iconStore.setIcon(from: url, for: listId) }
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                guard let image = image as? NSImage else { return }
                Task { @MainActor in iconStore.setIcon(image, for: listId) }
            }
            return true
        }

        return false
    }
}

/// Opens a picker for a list's icon. Shared by the cell's context menu and the
/// board toolbar so there is one code path for choosing a file.
@MainActor
enum ListIconPicker {
    static func present(for listId: String, in store: ListIconStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use as icon"
        panel.message = "Choose an image for this list"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setIcon(from: url, for: listId)
    }
}

extension EKCalendar {
    /// The list's Reminders colour, or the app accent when it has none.
    var helpyColor: Color {
        guard let cgColor else { return Color(hex: 0x0086E8) }
        return Color(cgColor)
    }
}
