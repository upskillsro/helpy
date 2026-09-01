import SwiftUI

/// The Planning tab: the week you are in, then the weeks ahead, then the ones
/// behind you — each opening a side panel with its goal, scored tasks, and
/// reward.
///
/// Plans live in Helpy. A week can additionally mirror its tasks into a
/// Reminders list, but nothing here requires Reminders access: without it the
/// tab still plans, it just has nowhere to mirror to.
struct PlanningView: View {
    @EnvironmentObject var planStore: WeeklyPlanStore
    @EnvironmentObject var remindersService: RemindersService
    @EnvironmentObject var navigation: AppNavigation
    @Environment(\.colorScheme) private var colorScheme

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private let weeks = PlanWeek.rollingWindow()

    private var currentWeek: PlanWeek? { weeks.first(where: \.isCurrent) }
    private var upcoming: [PlanWeek] {
        guard let currentWeek else { return weeks }
        return weeks.filter { $0.start > currentWeek.start }
    }
    private var earlier: [PlanWeek] {
        guard let currentWeek else { return [] }
        return weeks.filter { $0.start < currentWeek.start }.reversed()
    }

    private var selectedWeek: PlanWeek? {
        guard let id = navigation.selectedWeekId else { return nil }
        return weeks.first { $0.id == id }
    }

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 10)]

    var body: some View {
        HStack(spacing: 0) {
            RoadmapColumn()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let currentWeek {
                        CurrentWeekCard(
                            week: currentWeek,
                            plan: planStore.plan(for: currentWeek.id),
                            isSelected: navigation.selectedWeekId == currentWeek.id,
                            onOpen: { select(currentWeek) }
                        )
                    }

                    section("Coming up", weeks: upcoming)
                    section("Earlier", weeks: earlier)
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity)
            .scrollBounceBehavior(.basedOnSize)

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
        // Planning can be the first tab you open, and the week panel's list
        // picker is empty until something has actually fetched the lists.
        .onAppear { remindersService.fetchAllLists() }
    }

    @ViewBuilder
    private func section(_ title: String, weeks: [PlanWeek]) -> some View {
        if !weeks.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(title.uppercased())
                        .font(.inter(size: 9, weight: .bold))
                        .kerning(0.9)
                        .foregroundStyle(t.muted2)
                    Rectangle()
                        .fill(t.line)
                        .frame(height: 1)
                }

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
            }
        }
    }

    private func select(_ week: PlanWeek) {
        withAnimation(.easeOut(duration: 0.16)) {
            navigation.selectedWeekId = navigation.selectedWeekId == week.id ? nil : week.id
        }
    }
}
