# Calendar tab

## Purpose

Time allocation. The board says *when a task is due*; the calendar says *when
you are going to do it*. A week of columns, real clock times, and dragging as
the only way to put work in a slot.

## Architecture

**A block is a reminder, not a new record.** A task is scheduled when its due
date carries an hour (`TaskSchedule.isScheduled`). A date-only due date means
unscheduled, so it sits in the rail. Nothing else stores position, which is why
scheduling here moves the task on the board and syncs to the phone, and why
unscheduling leaves nothing behind.

**A block's length is its estimate.** Height comes from
`EstimateStore.getMetadata(for:)?.estimatedDuration`. No estimate draws 30
minutes and still stores zero; dragging the bottom edge is what turns that into
a real estimate, and the same number then shows on the board and in focus mode.

### Files

- `Sources/Services/CalendarSchedule.swift` — all the arithmetic, no views.
  `CalendarGrid` (minute ↔ y, 15-minute snapping, window widening),
  `CalendarWeek` (the seven days and the title), `CalendarLayout` (lane packing
  for overlapping blocks, booked totals), `TaskSchedule` (the due-date rules).
  Covered by `Tests/HelpyTests/CalendarScheduleTests.swift`.
- `Sources/UI/Calendar/CalendarTabView.swift` — root. Owns the week offset, the
  list filter, the rail drag and the selected task. Derives `items` and
  `unscheduled` from `RemindersService` on every render; both are dictionary
  lookups.
- `Sources/UI/Calendar/UnscheduledRailView.swift` — the rail, the list picker,
  and `CalendarFormat` (durations and clock strings).
- `Sources/UI/Calendar/CalendarWeekGrid.swift` — week bar, day headers, the
  seven columns, both drop paths, and the move/resize drag state.
- `Sources/UI/Calendar/TimeBlockView.swift` — one block.
- `Sources/UI/Calendar/TaskDetailPanel.swift` — the right-hand panel for the
  selected block.
- `Sources/Services/TaskColorStore.swift` — per-task colour overrides.
- `RemindersService.schedule / unschedule` — the only writers.

### Two drag mechanisms, on purpose

- **Rail → grid** is an `NSItemProvider` drop with a `DropDelegate`. It has to
  be: the drag crosses from one view tree into another.
- **A block already on the grid** is moved with a `DragGesture` in the named
  coordinate space `helpy.calendar`. That keeps the part of the block the
  pointer grabbed, and it is what lets a block dragged back over the rail
  unschedule itself instead of landing somewhere.

The moving block stays a child of its own day column and is drawn with an
`offset` equal to the move that will be written. Re-parenting it into the target
column mid-drag rebuilds the view, which restarts the gesture and throws away
the translation collected before the crossing.

### The detail panel

Clicking a block opens a 296pt panel on the right: title, colour, when, notes,
subtasks, and a footer that can mark the task done or take it off the week. It
writes through the same paths as everything else — `RemindersService` for the
title, notes and completion, `EstimateStore` for the length, `TaskColorStore`
for the colour — so nothing in it is a second source of truth.

Colour is `override ?? list colour`. The list is the default because on an
all-lists week the colour is the only thing saying which project just ate the
afternoon; the override is there for the one task you want to pick out of it.

When is three controls, not three menus: a strip of the week's seven days, a
`.stepperField` `DatePicker` for the start time, and one-tap chips for the
common lengths. The real length is spelled out next to the chips, because a
3h 15m block matches no chip and would otherwise look unset. Anything between
the chips is still set by dragging the block's bottom edge.

### Rendering during a drag

A day column is `Equatable` and rendered with `.equatable()`, so a drag only
re-renders the column that owns the block and the one under the pointer. The
drag state lives in `CalendarWeekGrid`, not in the tab, or every pointer sample
would rebuild the rail too. The now-line is a `TimelineView(.everyMinute)`;
`.periodic(from: .now, …)` re-schedules on every render, because `.now` is a new
date each time.

### Window

`CalendarGrid.fitting` starts from the settings hours (default 8–20) and widens
to include anything scheduled outside them, so a 6:30 block can never hide. The
visible hours are a default, not a limit.

## Decisions

- 2026-09-09 — The resize handle's `DragGesture` reads the grid's named
  coordinate space, not `.local`. The handle rides the bottom of the block, so
  in its own space every 15-minute snap moved the gesture's origin down under
  the pointer, the translation shrank back by exactly that much, and the block
  oscillated between two lengths for the whole drag. This, not the move drag,
  was the flicker that survived the first two passes.
- 2026-09-09 — Priority no longer tints a block. It used to win over the list
  colour, which was fine while it only coloured a 3pt bar; once the bar went the
  whole block turned hot and a flagged task read as an emergency all week.
- 2026-09-09 — The block's left colour bar is gone. The fill and border already
  carry the colour, and the bar made every block look like a notification.
- 2026-09-09 — Task colours live in `UserDefaults`, not `TaskMetadata`. Adding a
  property to the SwiftData model risks a migration, and a failed one takes
  every estimate and every tracked minute with it. A colour is a display
  preference; the worst case in defaults is a forgotten colour.
- 2026-09-09 — Move/resize drag state moved from `CalendarTabView` into
  `CalendarWeekGrid`, and `DayColumn` became `Equatable`. Guarding the writes
  was not enough on its own: the state still sat above the rail, so every
  committed sample rebuilt the whole tab.
- 2026-09-09 — Drag state is written only when the *snapped* target changes, not
  on every pointer sample. A write per sample rebuilt the rail and all seven
  columns ~60 times a second, which is what the flickering was.
- 2026-09-09 — `dropExited` clears the ghost on the next runloop pass. Crossing a
  column boundary fires exit and enter in either order; clearing immediately
  blinked the ghost out for a frame at every boundary.
- 2026-09-09 — The resize handle is overlaid *after* the block's
  `contentShape`, so the edge is unambiguously on top of the block's own hit
  region rather than nested inside it.
- 2026-09-09 — Blocks written from the calendar carry no `EKAlarm` by default
  (`calendarBlockAlarms`, off). A due time normally means "remind me", but here
  it means "this is when I plan to do it", and a planned week would otherwise be
  a week of notifications on the phone. `updateDueDate(_:components:alarm:)`
  takes the flag; every other caller keeps the old behaviour.
- 2026-09-09 — Unscheduling keeps the day and drops only the hour, so a task
  pulled off Thursday is still due Thursday and stays in the board column it
  was in.
- 2026-09-09 — `reminder(withId:)` falls back to `remindersByList` and
  `completedByList`. `reminders` is a scoped fetch, so a backlog task from a
  list that is not the active one was unreachable and scheduling it failed
  silently.
- 2026-09-09 — Scheduling is a due date with an hour rather than a separate
  store, matching the board's rule that the bucket is derived from the due
  date. One source of truth, and the phone gets it for free.
