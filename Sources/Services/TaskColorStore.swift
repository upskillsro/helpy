import Foundation

/// The colour a task shows on the calendar, when it should not just follow its
/// list's colour.
///
/// Deliberately not a field on `TaskMetadata`: adding a property to the
/// SwiftData model risks a migration, and a failed one takes every estimate and
/// every tracked minute with it. A block's colour is a display preference, so
/// it lives in defaults where the worst case is a forgotten colour.
@MainActor
final class TaskColorStore: ObservableObject {
    static let shared = TaskColorStore()

    /// What the detail panel offers. Anything else a task already has is kept.
    static let palette: [UInt32] = [
        0x0086E8, 0x5E5CE6, 0xAF52DE, 0xFF2D55,
        0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759,
    ]

    private let key = "calendarTaskColors"
    @Published private var colors: [String: UInt32]

    private init() {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        colors = stored.mapValues { UInt32(truncatingIfNeeded: $0) }
    }

    func color(for id: String) -> UInt32? { colors[id] }

    /// `nil` puts the task back on its list's colour.
    func setColor(_ hex: UInt32?, for id: String) {
        if let hex {
            guard colors[id] != hex else { return }
            colors[id] = hex
        } else {
            guard colors[id] != nil else { return }
            colors.removeValue(forKey: id)
        }
        UserDefaults.standard.set(colors.mapValues { Int($0) }, forKey: key)
    }
}
