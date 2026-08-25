import SwiftUI

/// The Planning tab: a rolling window of weeks, each opening a side panel with
/// that week's goal, scored tasks, and reward.
///
/// Weekly plans are Helpy's own — they never touch Apple Reminders — so this tab
/// keeps working when Reminders access has not been granted.
struct PlanningView: View {
    @EnvironmentObject var planStore: WeeklyPlanStore
    @EnvironmentObject var navigation: AppNavigation
    @Environment(\.colorScheme) private var colorScheme

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private let weeks = PlanWeek.rollingWindow()

    private var selectedWeek: PlanWeek? {
        guard let id = navigation.selectedWeekId else { return nil }
        return weeks.first { $0.id == id }
    }

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 10)]

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(weeks) { week in
                            WeekCardView(
                                week: week,
                                plan: planStore.plan(for: week.id),
                                isSelected: navigation.selectedWeekId == week.id,
                                onOpen: { select(week) }
                            )
                            .id(week.id)
                        }
                    }
                    .padding(14)
                }
                .onAppear {
                    // Land on this week rather than four weeks of history.
                    if let current = weeks.first(where: \.isCurrent) {
                        proxy.scrollTo(current.id, anchor: .top)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if let selectedWeek {
                WeekDetailPanel(week: selectedWeek) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        navigation.selectedWeekId = nil
                    }
                }
                .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.canvas)
    }

    private func select(_ week: PlanWeek) {
        withAnimation(.easeOut(duration: 0.16)) {
            navigation.selectedWeekId = navigation.selectedWeekId == week.id ? nil : week.id
        }
    }
}
