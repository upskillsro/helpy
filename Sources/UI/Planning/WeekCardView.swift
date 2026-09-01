import SwiftUI

/// One week in the Planning grid.
///
/// The card is meant to be readable without opening it: goal, how far through
/// the points you are, and whether the reward is still in play. A week nobody
/// has touched says so quietly rather than showing an empty scoreboard.
struct WeekCardView: View {
    let week: PlanWeek
    let plan: WeeklyPlan
    let isSelected: Bool
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var isPast: Bool { !week.isCurrent && week.end <= Date() }

    private var fill: Color {
        if isSelected { return t.surfaceActive }
        return isHovering ? t.surfaceHover : t.surface
    }

    private var border: Color {
        if isSelected { return t.rail }
        if isHovering { return t.surfaceActiveBorder }
        return week.isCurrent ? t.surfaceActiveBorder : t.line
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(week.rangeLabel)
                        .font(.inter(size: 11.5, weight: .semibold))
                        .foregroundStyle(t.ink)
                    Spacer(minLength: 4)
                    WeekStatusBadge(week: week, plan: plan, palette: t)
                }

                Text(plan.goal.isEmpty ? "No goal set" : plan.goal)
                    .font(.inter(size: 11))
                    .foregroundStyle(plan.goal.isEmpty ? t.muted2 : t.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                if plan.tasks.isEmpty {
                    if plan.reward.isEmpty {
                        Text("Nothing planned")
                            .font(.inter(size: 10))
                            .foregroundStyle(t.muted2)
                    } else {
                        rewardLine
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        WeekScoreLine(plan: plan, palette: t)
                        WeekProgressBar(plan: plan, palette: t, height: 4)
                        if !plan.reward.isEmpty { rewardLine }
                    }
                }
            }
            .padding(12)
            .frame(height: 128, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .stroke(border, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(
                color: Color.black.opacity(isHovering && !isSelected ? 0.10 : 0),
                radius: 8,
                y: 3
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Past weeks stay legible but stop competing with the ones you can
        // still do something about.
        .opacity(isPast && !isSelected ? 0.62 : 1)
        .scaleEffect(isHovering && !isSelected ? 1.012 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
    }

    private var rewardLine: some View {
        HStack(spacing: 4) {
            Image(systemName: plan.isRewardEarned ? "gift.fill" : "gift")
                .font(.system(size: 9))
            Text(plan.reward)
                .font(.inter(size: 10))
                .lineLimit(1)
        }
        .foregroundStyle(plan.isRewardEarned ? t.success : t.muted2)
    }
}

/// The hero card for the week you are actually in.
struct CurrentWeekCard: View {
    let week: PlanWeek
    let plan: WeeklyPlan
    let isSelected: Bool
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var t: HelpyPalette { .forScheme(colorScheme) }

    private var daysLeft: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let last = calendar.startOfDay(for: week.lastDay)
        return max(0, calendar.dateComponents([.day], from: today, to: last).day ?? 0)
    }

    private var subtitle: String {
        if plan.isRewardEarned { return "Week won" }
        if plan.tasks.isEmpty { return "Nothing planned yet" }
        let remaining = plan.availablePoints - plan.earnedPoints
        return "\(remaining) pts to go"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                WeekProgressRing(plan: plan, palette: t, size: 54, lineWidth: 6)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text("THIS WEEK")
                            .font(.inter(size: 8.5, weight: .bold))
                            .kerning(0.8)
                            .foregroundStyle(t.onAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(t.rail))
                        Text(week.rangeLabel)
                            .font(.inter(size: 11, weight: .medium))
                            .foregroundStyle(t.muted)
                        Text("·").foregroundStyle(t.muted2)
                        Text(daysLeft == 0 ? "last day" : "\(daysLeft) days left")
                            .font(.inter(size: 11))
                            .foregroundStyle(t.muted2)
                    }

                    Text(plan.goal.isEmpty ? "Set a goal for this week" : plan.goal)
                        .font(.inter(size: 15, weight: .semibold))
                        .foregroundStyle(plan.goal.isEmpty ? t.muted2 : t.ink)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        WeekScoreLine(plan: plan, palette: t, size: 11)
                        Text("·").foregroundStyle(t.muted2)
                        Text(subtitle)
                            .font(.inter(size: 11))
                            .foregroundStyle(plan.isRewardEarned ? t.success : t.muted2)
                    }
                }

                Spacer(minLength: 8)

                if !plan.reward.isEmpty {
                    VStack(alignment: .trailing, spacing: 3) {
                        Image(systemName: plan.isRewardEarned ? "gift.fill" : "gift")
                            .font(.system(size: 13))
                        Text(plan.reward)
                            .font(.inter(size: 10.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(plan.isRewardEarned ? t.success : t.muted)
                    .frame(maxWidth: 150, alignment: .trailing)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.muted2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .fill(isHovering ? t.surfaceHover : t.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .stroke(isSelected ? t.rail : t.surfaceActiveBorder, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
    }
}

/// NOW for the live week, a tick for a week that was won, nothing otherwise —
/// a badge on every card would just be noise.
private struct WeekStatusBadge: View {
    let week: PlanWeek
    let plan: WeeklyPlan
    let palette: HelpyPalette

    var body: some View {
        if week.isCurrent {
            Text("NOW")
                .font(.inter(size: 8, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(palette.onAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(palette.rail))
        } else if plan.isRewardEarned {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11))
                .foregroundStyle(palette.success)
        }
    }
}

extension PlanWeek {
    private static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var rangeLabel: String {
        "\(Self.dayMonth.string(from: start)) – \(Self.dayMonth.string(from: lastDay))"
    }
}
