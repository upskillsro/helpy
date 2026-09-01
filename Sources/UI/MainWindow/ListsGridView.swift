import EventKit
import SwiftUI

/// The Lists tab: every Reminders list as a square cell.
///
/// Cells size themselves between 190 and 250pt. Below 190 the task cards inside
/// stop reading as cards, and above 250 a square cell wastes half its height on
/// nothing — so the count flexes with the window instead of being fixed.
struct ListsGridView: View {
    @EnvironmentObject var remindersService: RemindersService
    @EnvironmentObject var iconStore: ListIconStore
    @EnvironmentObject var navigation: AppNavigation
    @Environment(\.colorScheme) private var colorScheme

    private var t: HelpyPalette { .forScheme(colorScheme) }
    @State private var isCreatingList = false

    private let columns = [GridItem(.adaptive(minimum: 228, maximum: 300), spacing: 14)]

    var body: some View {
        Group {
            if !remindersService.isAccessGranted {
                RemindersAccessDeniedView()
            } else if remindersService.lists.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.canvas)
        .onAppear {
            remindersService.fetchAllLists()
        }
        .onChange(of: remindersService.lists.map(\.calendarIdentifier)) { _, identifiers in
            // A deleted list must not keep handing its icon to whatever comes next.
            iconStore.pruneOrphans(keeping: Set(identifiers))
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(remindersService.lists, id: \.calendarIdentifier) { list in
                    ListCellView(
                        list: list,
                        reminders: remindersService.reminders(in: list.calendarIdentifier),
                        onOpen: { navigation.openList(list.calendarIdentifier) }
                    )
                }

                if remindersService.canCreateLists {
                    NewListCell { isCreatingList = true }
                }
            }
            .padding(14)
        }
        .sheet(isPresented: $isCreatingList) {
            NewListSheet(
                onCreate: { name, color, icon in
                    isCreatingList = false
                    // The icon is keyed by the identifier the save hands back,
                    // so it can only be written once the list exists.
                    guard let created = remindersService.createList(named: name, color: color) else { return }
                    if let icon { iconStore.setIcon(icon, for: created.calendarIdentifier) }
                },
                onCancel: { isCreatingList = false }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 30))
                .foregroundStyle(t.muted2)
            Text("No lists yet")
                .font(.inter(size: 14, weight: .semibold))
                .foregroundStyle(t.ink)
            Text("Create a list in Apple Reminders and it shows up here.")
                .font(.inter(size: 11))
                .foregroundStyle(t.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown wherever Helpy needs Reminders and does not have it. Planning still
/// works without access, which is why this is scoped to a pane rather than
/// taking over the window.
struct RemindersAccessDeniedView: View {
    @EnvironmentObject var remindersService: RemindersService
    @Environment(\.colorScheme) private var colorScheme

    private var t: HelpyPalette { .forScheme(colorScheme) }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(t.muted)
            Text("Access Required")
                .font(.inter(size: 16, weight: .semibold))
                .foregroundStyle(t.ink)
            Text("Helpy needs access to Reminders to show your lists.")
                .font(.inter(size: 12))
                .foregroundStyle(t.muted)
                .multilineTextAlignment(.center)
            Button("Grant Access") { remindersService.requestAccess() }
                .buttonStyle(HelpyPrimaryButtonStyle(palette: t))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
