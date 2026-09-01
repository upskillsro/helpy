import SwiftUI

/// A week's points as a dial. The arc carries the shape of the week at a
/// glance; the number in the middle is the answer when you actually stop to
/// read it.
///
/// There is no separate target to draw against — the target is everything on
/// the board, so a full ring means the week is done.
struct WeekProgressRing: View {
    let plan: WeeklyPlan
    let palette: HelpyPalette
    var size: CGFloat = 46
    var lineWidth: CGFloat = 5

    private var tint: Color {
        plan.isRewardEarned ? palette.success : palette.rail
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.railTrack, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, plan.progress))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.28), value: plan.progress)

            if plan.isRewardEarned {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(palette.success)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("\(Int(plan.progress * 100))%")
                    .font(.inter(size: size * 0.26, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.2), value: plan.isRewardEarned)
    }
}

/// The flat version, for cards too small to give a ring room.
struct WeekProgressBar: View {
    let progress: Double
    let palette: HelpyPalette
    var isComplete = false
    var height: CGFloat = 5

    /// Weeks pass a plan; the roadmap passes its own number.
    init(plan: WeeklyPlan, palette: HelpyPalette, height: CGFloat = 5) {
        self.progress = plan.progress
        self.palette = palette
        self.isComplete = plan.isRewardEarned
        self.height = height
    }

    init(progress: Double, palette: HelpyPalette, height: CGFloat = 5) {
        self.progress = progress
        self.palette = palette
        self.isComplete = progress >= 1
        self.height = height
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.railTrack)
                Capsule()
                    .fill(isComplete ? palette.success : palette.rail)
                    .frame(width: max(0, geo.size.width * progress))
                    .animation(.easeOut(duration: 0.28), value: progress)
            }
        }
        .frame(height: height)
    }
}

/// "3 of 5 done · 6/10 pts" — the two numbers people actually check.
struct WeekScoreLine: View {
    let plan: WeeklyPlan
    let palette: HelpyPalette
    var size: CGFloat = 10

    var body: some View {
        HStack(spacing: 5) {
            Text("\(plan.doneCount) of \(plan.tasks.count) done")
                .foregroundStyle(palette.muted)
            Text("·").foregroundStyle(palette.muted2)
            Text("\(plan.earnedPoints)/\(plan.availablePoints) pts")
                .foregroundStyle(plan.isRewardEarned ? palette.success : palette.muted)
        }
        .font(.inter(size: size, weight: .medium))
        .monospacedDigit()
    }
}
