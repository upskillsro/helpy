import EventKit
import SwiftUI

/// The app's root. One window, two shapes.
///
/// Normal: a standard macOS window with Lists and Planning in the real title
/// bar. Focused: the same window as the 350pt side strip, showing one list's
/// Today bucket. The window's chrome is switched by `AppWindowCoordinator`, not
/// here — this view only decides what is on screen.
struct MainWindowView: View {
    @EnvironmentObject var navigation: AppNavigation
    @EnvironmentObject var remindersService: RemindersService
    @EnvironmentObject var windowCoordinator: AppWindowCoordinator
    @EnvironmentObject var iconStore: ListIconStore
    @Environment(\.colorScheme) private var colorScheme

    private var t: HelpyPalette { .forScheme(colorScheme) }

    private var openList: EKCalendar? {
        guard let id = navigation.openListId else { return nil }
        return remindersService.lists.first { $0.calendarIdentifier == id }
    }

    var body: some View {
        Group {
            if let focusedListId = navigation.focusedListId {
                SideStripView(
                    focusedListId: focusedListId,
                    onExitFocus: { navigation.exitFocus() }
                )
                .frame(minWidth: 300, maxWidth: 350, maxHeight: .infinity)
            } else {
                normalContent
                    .frame(
                        minWidth: MainWindowStyle.normalMinSize.width,
                        minHeight: MainWindowStyle.normalMinSize.height
                    )
            }
        }
        .toolbar(navigation.isFocused ? .hidden : .visible, for: .windowToolbar)
        .toolbar { toolbarContent }
        // No window title at all: the open list names itself in its own header
        // above the board, as one object rather than an icon beside a title.
        .navigationTitle("")
        .onAppear { applyWindowMode() }
        .onChange(of: navigation.focusedListId) { _, _ in applyWindowMode() }
    }

    /// Resized on the next runloop turn on purpose: the strip's content is
    /// 350pt wide and the normal window's is 900pt, and SwiftUI has to lay the
    /// new branch out before its minimum stops fighting the frame we set.
    private func applyWindowMode() {
        let mode: MainWindowMode = navigation.isFocused ? .strip : .normal
        DispatchQueue.main.async {
            windowCoordinator.setMainWindowMode(mode)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var normalContent: some View {
        switch navigation.tab {
        case .lists:
            if let openList {
                ListBoardView(list: openList)
            } else {
                ListsGridView()
            }
        case .planning:
            PlanningView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if navigation.tab == .lists, navigation.openListId != nil {
            ToolbarItem(placement: .navigation) {
                Button {
                    navigation.closeList()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back to all lists")
            }
        }

        ToolbarItem(placement: .principal) {
            Picker("", selection: $navigation.tab) {
                ForEach(MainTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
        }

        ToolbarItem(placement: .primaryAction) {
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
    }
}
