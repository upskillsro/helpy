import AppKit
import Foundation
import SwiftUI

/// Custom icons for Reminders lists.
///
/// The file on disk IS the state. There is no index, no defaults key, and no
/// second record to keep in sync: an icon exists exactly when
/// `ListIcons/<calendarIdentifier>.png` exists, and deleting that file restores
/// the monogram. Two artifacts that must agree is the failure mode this avoids.
@MainActor
final class ListIconStore: ObservableObject {
    /// Bumped on every write so SwiftUI redraws cells whose icon just changed;
    /// a file path alone never looks different to the view system.
    @Published private(set) var revision = 0

    private let directory: URL
    private var cache: [String: NSImage] = [:]

    static let iconSide: CGFloat = 128

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Helpy/ListIcons", isDirectory: true)
    }

    func iconURL(for listId: String) -> URL {
        directory.appendingPathComponent("\(listId).png")
    }

    func hasIcon(for listId: String) -> Bool {
        FileManager.default.fileExists(atPath: iconURL(for: listId).path)
    }

    /// A broken or unreadable file reads as "no icon" so the caller draws the
    /// monogram. A bad image is never an error dialog.
    func image(for listId: String) -> NSImage? {
        if let cached = cache[listId] { return cached }
        guard let image = NSImage(contentsOf: iconURL(for: listId)) else { return nil }
        cache[listId] = image
        return image
    }

    @discardableResult
    func setIcon(from source: URL, for listId: String) -> Bool {
        guard let image = NSImage(contentsOf: source) else {
            AppLogger.ui.error("Could not read list icon at \(source.lastPathComponent, privacy: .public)")
            return false
        }
        return setIcon(image, for: listId)
    }

    @discardableResult
    func setIcon(_ image: NSImage, for listId: String) -> Bool {
        guard let data = Self.pngData(scaling: image, to: Self.iconSide) else {
            AppLogger.ui.error("Could not encode list icon for \(listId, privacy: .public)")
            return false
        }
        do {
            try data.write(to: iconURL(for: listId), options: .atomic)
            cache[listId] = NSImage(data: data)
            revision += 1
            return true
        } catch {
            AppLogger.ui.error("Could not save list icon: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func removeIcon(for listId: String) {
        try? FileManager.default.removeItem(at: iconURL(for: listId))
        cache.removeValue(forKey: listId)
        revision += 1
    }

    /// Drops icons whose list no longer exists. Called on launch with the set of
    /// fetched list identifiers, so a deleted list does not leave a file behind
    /// forever — and, more importantly, cannot hand its icon to a new list that
    /// happens to reuse the identifier.
    func pruneOrphans(keeping listIds: Set<String>) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        for url in contents where url.pathExtension == "png" {
            let identifier = url.deletingPathExtension().lastPathComponent
            guard !listIds.contains(identifier) else { continue }
            try? FileManager.default.removeItem(at: url)
            cache.removeValue(forKey: identifier)
        }
    }

    /// Square, aspect-filled, centre-cropped — a wide photo becomes a square
    /// tile rather than a squashed one.
    static func pngData(scaling image: NSImage, to side: CGFloat) -> Data? {
        let target = NSSize(width: side, height: side)
        let output = NSImage(size: target)

        output.lockFocus()
        NSColor.clear.set()
        NSRect(origin: .zero, size: target).fill()

        let size = image.size
        guard size.width > 0, size.height > 0 else {
            output.unlockFocus()
            return nil
        }
        let scale = max(side / size.width, side / size.height)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        let origin = NSPoint(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2)
        image.draw(
            in: NSRect(origin: origin, size: drawn),
            from: NSRect(origin: .zero, size: size),
            operation: .sourceOver,
            fraction: 1
        )
        output.unlockFocus()

        guard let tiff = output.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// The default icon: the list's own Reminders colour with the first character
/// of its title. Cheap, always available, and never wrong.
enum ListMonogram {
    static func letter(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}
