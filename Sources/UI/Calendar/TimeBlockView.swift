import SwiftUI

/// One task on the grid.
///
/// The block is tinted with its colour rather than the flat `surface` the
/// board's rows use. A row already sits inside a column that names its list; a
/// block does not, and on an all-lists week the colour is the only thing saying
/// which project just ate the afternoon.
struct TimeBlockView: View {
    let item: ScheduledItem
    let minutes: Int
    let palette: HelpyPalette
    let height: CGFloat
    let isMoving: Bool
    /// The block whose detail panel is open.
    var isSelected: Bool = false
    /// The pointer is over the rail: this drop takes the block off the week.
    var willUnschedule: Bool = false
    /// Where the block is heading while it is being dragged. The label has to
    /// read the target, not the stored start, or the time under the pointer is
    /// an hour out of date until the drop lands.
    var displayStart: Date?
    let onComplete: () -> Void
    let onUnschedule: () -> Void
    /// Live translation of the bottom edge, in points.
    let onResize: (CGFloat) -> Void
    let onResizeEnd: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var t: HelpyPalette { palette }
    private var isDark: Bool { colorScheme == .dark }
    /// A colour chosen in the detail panel wins; otherwise the block follows its
    /// list. Priority used to win here, but once the left bar went the whole
    /// block turned hot, and a flagged task read as an emergency all week.
    private var color: Color {
        if let hex = item.overrideColorHex { return Color(hex: hex) }
        return Color(hex: item.listColorHex)
    }

    /// Under ~34pt there is only room for the title; under ~52pt the title has
    /// to stay on one line or it pushes the time out of the block.
    private var showsTime: Bool { height >= 34 }
    private var titleLines: Int { height >= 52 ? 2 : 1 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(isDark ? 0.17 : 0.10))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    color.opacity(isSelected ? 0.95 : (isDark ? 0.42 : 0.34)),
                    lineWidth: isSelected ? 1.8 : 1
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.inter(size: 10.5, weight: .semibold))
                    .foregroundStyle(t.ink)
                    .strikethrough(item.isDone, color: t.muted)
                    .lineLimit(titleLines)
                    .multilineTextAlignment(.leading)
                if showsTime {
                    Text(timeLabel)
                        .font(.inter(size: 9.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(t.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: max(height, 18), alignment: .topLeading)
        .opacity(willUnschedule ? 0.4 : (item.isDone ? 0.55 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(item.isDone ? "Mark as not done" : "Mark as done", action: onComplete)
            Button("Unschedule", action: onUnschedule)
        }
        // Last, so the handle sits above the block's own content shape rather
        // than nested inside it, and an edge drag is never ambiguous.
        .overlay(alignment: .bottom) { resizeHandle }
    }

    private var timeLabel: String {
        let start = displayStart ?? item.start
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        return "\(CalendarFormat.clock(start)) – \(CalendarFormat.clock(end))"
    }

    /// The bottom edge is the estimate. Dragging it is the fastest way to give
    /// a task one, which is why the handle is the only affordance on the block.
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 9)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(color.opacity(0.75))
                    .frame(width: 24, height: 3)
                    .opacity(isHovering ? 1 : 0)
            }
            // The grid's space, never `.local`. The handle rides the bottom of
            // the block, so in its own space every snap moved the origin under
            // the pointer, the translation shrank back by the same amount, and
            // the block oscillated between two lengths for the whole drag.
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(CalendarTabView.space))
                    .onChanged { onResize($0.translation.height) }
                    .onEnded { _ in onResizeEnd() }
            )
    }
}
