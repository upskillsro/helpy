import Foundation
import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case lists
    case planning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lists: return "Lists"
        case .planning: return "Planning"
        }
    }
}

/// Where the user is in the three-tier hierarchy.
///
///     normal window  →  side strip (one list's Today)  →  floating pill
///
/// The first two rungs live here. The third is `TimerService.isFocusMode`, which
/// keeps its own meaning: pill up, windows hidden. Splitting them is the point —
/// entering the strip and starting a timer used to be one button.
@MainActor
final class AppNavigation: ObservableObject {
    @Published var tab: MainTab = .lists

    /// nil = the grid of lists. Set = that list's board is open.
    @Published var openListId: String?

    /// nil = normal window. Set = the window is the side strip, scoped to that
    /// list's Today bucket.
    @Published var focusedListId: String?

    /// The week whose side panel is open in Planning.
    @Published var selectedWeekId: String?

    var isFocused: Bool { focusedListId != nil }

    func openList(_ listId: String) {
        openListId = listId
    }

    func closeList() {
        openListId = nil
    }

    /// Enter the strip. Remembers which board to come back to.
    func focus(on listId: String) {
        openListId = listId
        focusedListId = listId
    }

    func exitFocus() {
        focusedListId = nil
    }
}
