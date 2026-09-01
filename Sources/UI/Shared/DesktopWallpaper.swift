import AppKit
import SwiftUI

/// The user's actual desktop picture, small.
///
/// The position and timer previews are pictures of their screen, so they should
/// use their wallpaper the way macOS's own Displays settings does — a drawn
/// gradient always looks like somebody else's Mac. Loaded once and downscaled;
/// a 6K desktop picture behind a 90pt thumbnail is not worth the memory.
enum DesktopWallpaper {
    private static let previewWidth: CGFloat = 420

    static let image: Image? = load()

    private static func load() -> Image? {
        guard let url = currentURL(), let full = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: downscaled(full))
    }

    private static func currentURL() -> URL? {
        if let screen = NSScreen.main,
           let url = NSWorkspace.shared.desktopImageURL(for: screen),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // A dynamic desktop or a wallpaper the app cannot see: fall back to
        // whatever ships with the OS rather than showing nothing.
        let system = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: system, includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { ["heic", "jpg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    private static func downscaled(_ image: NSImage) -> NSImage {
        let size = image.size
        guard size.width > previewWidth, size.width > 0 else { return image }
        let scaled = NSSize(
            width: previewWidth,
            height: (previewWidth * size.height / size.width).rounded()
        )
        let thumbnail = NSImage(size: scaled)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: scaled))
        thumbnail.unlockFocus()
        return thumbnail
    }
}
