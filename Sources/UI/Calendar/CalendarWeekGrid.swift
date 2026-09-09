import EventKit
import SwiftUI
import UniformTypeIdentifiers

/// Seven days of time, an hour ruler down the left, and the blocks on it.
///
/// Two different drags land here and they are deliberately different mechanisms:
/// a card arriving from the rail is a normal item-provider drop (it crosses
/// views, so it has to be), while a block already on the grid is moved with a
/// drag *gesture* in the tab's coordinate space. The gesture is what makes a
/// move keep the part of the block the pointer grabbed, and what lets a block
/// dragged back over the rail unschedule itself.
///
/// Every piece of drag state lives here rather than in the tab. A drag updates
/// several times a second, and from the tab it rebuilt the rail and recomputed
/// the whole week on each one. From here it rebuilds the grid, and `DayColumn`
/// is `Equatable`, so in practice only the column under the pointer redraws.
struct CalendarWeekGrid: View {
    let week: CalendarWeek
    let grid: CalendarGrid
    let items: [ScheduledItem]
    let palette: HelpyPalette
    let capacityMinutes: Int
    let railDrag: RailDrag?
    let selectedId: String?
    @Binding var blockOverRail: Bool
    @Binding var weekOffset: Int
    let onScheduleDrop: (String, Date, Int) -> Void
    let onMove: (String, Int, Int) -> Void
    let onResize: (String, Int) -> Void
    let onUnschedule: (String) -> Void
    let onComplete: (String) -> Void
    let onSelect: (String?) -> Void

    @State private var dropPreview: DropPreview?
    @State private var blockDrag: BlockDrag?
    @State private var resize: BlockResize?

    private var t: HelpyPalette { palette }
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            bar
            GeometryReader { geo in
                let columnWidth = max(56, (geo.size.width - CalendarTabView.gutterWidth) / 7)
                VStack(spacing: 0) {
                    headerRow(columnWidth)
                    ScrollView {
                        HStack(alignment: .top, spacing: 0) {
                            gutter
                            ForEach(0..<7, id: \.self) { index in
                                column(index, width: columnWidth)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 14)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .background(t.canvas)
        .onChange(of: railDrag == nil) { _, ended in
            if ended { dropPreview = nil }
        }
    }

    // MARK: - Bar

    private var bar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                stepButton("chevron.left") { weekOffset -= 1 }
                stepButton("chevron.right") { weekOffset += 1 }
            }

            Text(week.title())
                .font(.inter(size: 13.5, weight: .bold))
                .foregroundStyle(t.ink)

            Button { weekOffset = 0 } label: {
                Text("Today")
                    .font(.inter(size: 11, weight: .semibold))
                    .foregroundStyle(weekOffset == 0 ? t.muted2 : t.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(t.line, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(weekOffset == 0)

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Text("Booked")
                    .font(.inter(size: 11))
                    .foregroundStyle(t.muted)
                Text(CalendarFormat.duration(minutes: CalendarLayout.bookedMinutes(items)))
                    .font(.inter(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(t.ink)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(t.controlIcon)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(t.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day headers

    /// Fixed height on purpose: `Color.clear` in the gutter slot fills whatever
    /// it is offered, and without a height the row ate the space above the grid
    /// and left the day names floating in the middle of the window.
    private func headerRow(_ columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: CalendarTabView.gutterWidth)
            ForEach(0..<7, id: \.self) { index in
                dayHeader(index).frame(width: columnWidth)
            }
        }
        .frame(height: 54)
        .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
    }

    private func dayHeader(_ index: Int) -> some View {
        let day = week.days[index]
        let booked = CalendarLayout.bookedMinutes(dayItems(index))
        let over = capacityMinutes > 0 && booked > capacityMinutes
        let today = calendar.isDateInToday(day)

        return VStack(spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.inter(size: 9, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(t.muted2)
            Text(day.formatted(.dateTime.day()))
                .font(.inter(size: 14.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(today ? t.onAccent : t.ink)
                .padding(.horizontal, today ? 7 : 0)
                .padding(.vertical, today ? 1 : 0)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(today ? t.accent : .clear)
                )
            Text(CalendarFormat.duration(minutes: booked))
                .font(.inter(size: 9.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(over ? t.chipHotText : t.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .overlay(alignment: .leading) {
            if index > 0 { Rectangle().fill(t.line).frame(width: 1) }
        }
    }

    // MARK: - Grid body

    private var gutter: some View {
        VStack(spacing: 0) {
            ForEach(grid.hours, id: \.self) { hour in
                ZStack(alignment: .topTrailing) {
                    Color.clear
                    Text(CalendarFormat.clock(minuteOfDay: hour * 60, on: week.days[0]))
                        .font(.inter(size: 9.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(t.muted2)
                        .offset(y: -5)
                        .padding(.trailing, 8)
                }
                .frame(height: grid.hourHeight)
            }
        }
        .frame(width: CalendarTabView.gutterWidth)
    }

    private func column(_ index: Int, width: CGFloat) -> some View {
        let day = week.days[index]
        // Only the column the block started in gets the drag. Handing it to the
        // others would invalidate all seven on every pointer step, and the
        // block is drawn as an offset from where it still lives anyway.
        let drag = blockDrag.flatMap { owns($0, index) ? $0 : nil }

        return DayColumn(
            dayIndex: index,
            day: day,
            width: width,
            isWeekend: calendar.isDateInWeekend(day),
            isToday: calendar.isDateInToday(day),
            grid: grid,
            palette: t,
            blocks: placed(index),
            drag: drag,
            resize: resize.flatMap { r in
                dayItems(index).contains { $0.id == r.id } ? r : nil
            },
            preview: railDrag != nil && dropPreview?.dayIndex == index ? dropPreview : nil,
            selectedId: selectedId,
            targetDay: drag.map(targetDay),
            targetMinute: drag.map(targetMinute),
            onComplete: onComplete,
            onUnschedule: onUnschedule,
            onSelect: onSelect,
            onDragChanged: { item, value in
                dragChanged(item, dayIndex: index, columnWidth: width, value: value)
            },
            onDragEnded: { item in dragEnded(item) },
            onResizeChanged: { item, delta in resizeChanged(item, delta: delta) },
            onResizeEnded: { item in commitResize(item) }
        )
        .equatable()
        // The column holding the dragged block draws over the ones after it, so
        // a block moved to the right is not painted over by its neighbours.
        .zIndex(drag == nil ? 0 : 5)
        .onDrop(
            of: [.text],
            delegate: DayDropDelegate(
                dayIndex: index,
                day: day,
                grid: grid,
                minutes: railDrag?.minutes ?? ScheduledItem.defaultMinutes,
                preview: $dropPreview,
                onDrop: onScheduleDrop
            )
        )
    }

    // MARK: - Moves

    private func dragChanged(
        _ item: ScheduledItem, dayIndex: Int, columnWidth: CGFloat, value: DragGesture.Value
    ) {
        var drag = blockDrag ?? BlockDrag(
            id: item.id,
            dayIndex: dayIndex,
            startMinute: CalendarGrid.minuteOfDay(item.start),
            minutes: item.minutes
        )
        guard drag.id == item.id else { return }
        drag.overRail = value.location.x < CalendarTabView.railWidth
        drag.dayDelta = Int((value.translation.width / columnWidth).rounded())
        drag.minuteDelta = grid.snap(
            Int((value.translation.height / grid.hourHeight * 60).rounded())
        )
        // Only when the snapped target actually changes. Writing on every
        // pointer sample is what made the grid flicker.
        guard drag != blockDrag else { return }
        blockDrag = drag
        if blockOverRail != drag.overRail { blockOverRail = drag.overRail }
    }

    private func dragEnded(_ item: ScheduledItem) {
        guard let drag = blockDrag, drag.id == item.id else { return }
        blockDrag = nil
        if blockOverRail { blockOverRail = false }
        if drag.overRail {
            onUnschedule(item.id)
        } else if drag.dayDelta != 0 || drag.minuteDelta != 0 {
            onMove(item.id, targetDay(drag), targetMinute(drag))
        }
    }

    private func resizeChanged(_ item: ScheduledItem, delta: CGFloat) {
        let added = grid.snap(Int((delta / grid.hourHeight * 60).rounded()))
        let raw = item.minutes + added
        let ceiling = max(ScheduledItem.minimumMinutes,
                          grid.lastMinute - CalendarGrid.minuteOfDay(item.start))
        let next = BlockResize(
            id: item.id,
            minutes: min(max(raw, ScheduledItem.minimumMinutes), ceiling)
        )
        if next != resize { resize = next }
    }

    private func commitResize(_ item: ScheduledItem) {
        guard let resize, resize.id == item.id else { return }
        let minutes = resize.minutes
        self.resize = nil
        guard minutes != item.minutes else { return }
        onResize(item.id, minutes)
    }

    // MARK: - Placement

    private func dayItems(_ index: Int) -> [ScheduledItem] {
        items.filter { calendar.isDate($0.start, inSameDayAs: week.days[index]) }
    }

    private func placed(_ index: Int) -> [CalendarLayout.Placed] {
        CalendarLayout.pack(dayItems(index))
    }

    private func owns(_ drag: BlockDrag, _ index: Int) -> Bool {
        guard let item = items.first(where: { $0.id == drag.id }) else { return false }
        return calendar.isDate(item.start, inSameDayAs: week.days[index])
    }

    private func targetDay(_ drag: BlockDrag) -> Int {
        min(max(drag.dayIndex + drag.dayDelta, 0), 6)
    }

    private func targetMinute(_ drag: BlockDrag) -> Int {
        grid.clampStart(minute: drag.startMinute + drag.minuteDelta, duration: drag.minutes)
    }
}

// MARK: - One day

/// `Equatable` on purpose. Without it every pointer step during a drag rebuilds
/// all seven columns, their hour lines and every block on them; with it SwiftUI
/// skips the six columns whose contents did not change.
private struct DayColumn: View, Equatable {
    let dayIndex: Int
    let day: Date
    let width: CGFloat
    let isWeekend: Bool
    let isToday: Bool
    let grid: CalendarGrid
    let palette: HelpyPalette
    let blocks: [CalendarLayout.Placed]
    let drag: BlockDrag?
    let resize: BlockResize?
    let preview: DropPreview?
    let selectedId: String?
    /// Where the dragged block is heading, resolved by the grid so the column
    /// does not need the whole week to work it out.
    let targetDay: Int?
    let targetMinute: Int?
    let onComplete: (String) -> Void
    let onUnschedule: (String) -> Void
    let onSelect: (String?) -> Void
    let onDragChanged: (ScheduledItem, DragGesture.Value) -> Void
    let onDragEnded: (ScheduledItem) -> Void
    let onResizeChanged: (ScheduledItem, CGFloat) -> Void
    let onResizeEnded: (ScheduledItem) -> Void

    static func == (a: DayColumn, b: DayColumn) -> Bool {
        a.dayIndex == b.dayIndex && a.day == b.day && a.width == b.width
            && a.isWeekend == b.isWeekend && a.isToday == b.isToday
            && a.grid == b.grid && a.blocks == b.blocks && a.drag == b.drag
            && a.resize == b.resize && a.preview == b.preview
            && a.selectedId == b.selectedId
            && a.targetDay == b.targetDay && a.targetMinute == b.targetMinute
    }

    private var t: HelpyPalette { palette }
    private let calendar = Calendar.current

    var body: some View {
        ZStack(alignment: .topLeading) {
            hourLines
            ForEach(blocks, id: \.id) { block in
                blockView(block)
            }
            .zIndex(1)
            if let preview { dropGhost(preview) }
            nowLine
        }
        .frame(width: width, height: grid.totalHeight, alignment: .topLeading)
        .background(isWeekend ? t.surface : t.canvas)
        .overlay(alignment: .leading) { Rectangle().fill(t.line).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(nil) }
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(grid.hours, id: \.self) { _ in
                Color.clear
                    .frame(height: grid.hourHeight)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(t.line.opacity(0.75)).frame(height: 1)
                    }
            }
        }
    }

    /// `.everyMinute` rather than `.periodic(from: .now,…)`: `.now` is a new
    /// value on every render, so a periodic schedule was rebuilt constantly.
    @ViewBuilder
    private var nowLine: some View {
        if isToday {
            TimelineView(.everyMinute) { context in
                let minute = CalendarGrid.minuteOfDay(context.date)
                if minute >= grid.firstMinute, minute <= grid.lastMinute {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(t.hot).frame(height: 1.5)
                        Circle().fill(t.hot).frame(width: 7, height: 7).offset(x: -3)
                    }
                    .offset(y: grid.y(forMinuteOfDay: minute))
                }
            }
        }
    }

    private func dropGhost(_ preview: DropPreview) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(t.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.accent.opacity(0.07))
            )
            .frame(height: grid.height(forMinutes: preview.minutes) - 3)
            .overlay(alignment: .topLeading) {
                Text(CalendarFormat.clock(minuteOfDay: preview.minute, on: day))
                    .font(.inter(size: 9.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(t.accent)
                    .padding(.leading, 8)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 3)
            .offset(y: grid.y(forMinuteOfDay: preview.minute) + 1.5)
    }

    private func blockView(_ placed: CalendarLayout.Placed) -> some View {
        let item = placed.item
        let laneWidth = (width - 6) / CGFloat(placed.columns)
        let moving = drag?.id == item.id ? drag : nil
        let minutes = resize?.id == item.id ? resize?.minutes ?? item.minutes : item.minutes
        // A block being dragged is drawn full width: it is leaving whatever it
        // was sharing the day with.
        let blockWidth = moving == nil ? laneWidth - 2 : width - 8

        return TimeBlockView(
            item: item,
            minutes: minutes,
            palette: t,
            height: grid.height(forMinutes: minutes) - 3,
            isMoving: moving != nil,
            isSelected: selectedId == item.id,
            willUnschedule: moving?.overRail == true,
            displayStart: moving == nil ? nil : movingStart(),
            onComplete: { onComplete(item.id) },
            onUnschedule: { onUnschedule(item.id) },
            onResize: { onResizeChanged(item, $0) },
            onResizeEnd: { onResizeEnded(item) }
        )
        .frame(width: blockWidth, alignment: .topLeading)
        .offset(
            x: 3 + laneWidth * CGFloat(placed.column) + offsetX(moving),
            y: grid.y(for: item.start) + 1.5 + offsetY(moving)
        )
        .zIndex(moving == nil ? Double(placed.column) : 10)
        .onTapGesture { onSelect(item.id) }
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(CalendarTabView.space))
                .onChanged { onDragChanged(item, $0) }
                .onEnded { _ in onDragEnded(item) }
        )
    }

    /// Exactly the move that will be written, so what is on screen during the
    /// drag cannot disagree with where the block lands.
    private func offsetX(_ drag: BlockDrag?) -> CGFloat {
        guard let drag, let targetDay else { return 0 }
        return CGFloat(targetDay - drag.dayIndex) * width
    }

    private func offsetY(_ drag: BlockDrag?) -> CGFloat {
        guard let drag, let targetMinute else { return 0 }
        return CGFloat(targetMinute - drag.startMinute) / 60 * grid.hourHeight
    }

    private func movingStart() -> Date? {
        guard let targetMinute, let targetDay, let drag else { return nil }
        let dayShift = targetDay - drag.dayIndex
        guard let shifted = calendar.date(byAdding: .day, value: dayShift, to: day) else { return nil }
        return calendar.date(
            bySettingHour: targetMinute / 60, minute: targetMinute % 60, second: 0, of: shifted
        )
    }
}

// MARK: - Drop

struct DropPreview: Equatable {
    let dayIndex: Int
    let minute: Int
    let minutes: Int
}

/// A card arriving from the rail. The ghost follows the pointer through
/// `dropUpdated`, so the block lands where it was shown, not a row away.
struct DayDropDelegate: DropDelegate {
    let dayIndex: Int
    let day: Date
    let grid: CalendarGrid
    let minutes: Int
    @Binding var preview: DropPreview?
    let onDrop: (String, Date, Int) -> Void

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    /// Deferred, because crossing a column boundary fires this day's exit and
    /// the next day's enter in either order. By the time this runs the preview
    /// already names the new column, so the ghost never blinks out between two
    /// days — it only clears when the pointer really left the grid.
    func dropExited(info: DropInfo) {
        DispatchQueue.main.async {
            if preview?.dayIndex == dayIndex { preview = nil }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let minute = grid.minute(atY: info.location.y, duration: minutes)
        preview = nil
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let identifier = object as? String else { return }
            Task { @MainActor in onDrop(identifier, day, minute) }
        }
        return true
    }

    private func update(_ info: DropInfo) {
        let next = DropPreview(
            dayIndex: dayIndex,
            minute: grid.minute(atY: info.location.y, duration: minutes),
            minutes: minutes
        )
        if next != preview { preview = next }
    }
}
