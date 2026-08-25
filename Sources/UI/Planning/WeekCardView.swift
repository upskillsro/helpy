import SwiftUI

/// One week in the Planning grid.
struct WeekCardView: View {
    let week: PlanWeek
    let plan: WeeklyPlan
    let isSelected: Bool
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var t: HelpyPalette { .forScheme(colorScheme) }

    private static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private var rangeLabel: String {
        "\(Self.dayMonth.string(from: week.start)) – \(Self.dayMonth.string(from: week.lastDay))"
    }

    private var fill: Color {
        if isSelected { return t.surfaceActive }
        return isHovering ? t.surfaceHover : t.surface
    }

    private var border: Color {
        if isSelected { return t.rail }
        return week.isCurrent ? t.surfaceActiveBorder : t.line
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Text(rangeLabel)
                        .font(.inter(size: 11.5, weight: .semibold))
                        .foregroundStyle(t.ink)
                    Spacer(minLength: 4)
                    if week.isCurrent {
                        Text("NOW")
                            .font(.inter(size: 8, weight: .bold))
                            .kerning(0.6)
                            .foregroundStyle(t.onAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(t.rail))
                    }
                }

                Text(plan.goal.isEmpty ? "No goal set" : plan.goal)
                    .font(.inter(size: 11))
                    .foregroundStyle(plan.goal.isEmpty ? t.muted2 : t.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                if plan.pointsTarget > 0 {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("\(plan.earnedPoints)/\(plan.pointsTarget) pts")
                                .font(.inter(size: 10, weight: .medium))
                                .foregroundStyle(t.muted)
                            Spacer()
                            if plan.isRewardEarned {
                                Text("Earned")
                                    .font(.inter(size: 9, weight: .semibold))
                                    .foregroundStyle(t.success)
                            }
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(t.railTrack)
                                Capsule()
                                    .fill(plan.isRewardEarned ? t.success : t.rail)
                                    .frame(width: max(0, geo.size.width * plan.progress))
                            }
                        }
                        .frame(height: 4)
                    }
                } else if !plan.reward.isEmpty {
                    Text(plan.reward)
                        .font(.inter(size: 10))
                        .foregroundStyle(t.muted2)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(height: 118, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                    .stroke(border, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}
