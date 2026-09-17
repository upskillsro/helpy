# Focus mode

## Purpose

Focus mode is the app's innermost rung: one task, a running timer, and every
Helpy window out of the way. It exists so a session survives the app not being
frontmost.

## Architecture

Three rungs, deliberately separate (see the note on `AppNavigation`):

    normal window  →  side strip (one list's Today)  →  focus mode

The first two are `AppNavigation.openListId` and `focusedListId`. The third is
`TimerService.isFocusMode`, which means "session surface up, windows hidden".
Splitting them is the point: entering the strip and starting a timer used to be
one button.

The session surface depends on the `pillDisplayMode` setting:

- `.floatingPill` — a borderless `NSPanel` at `.floating` level, built once by
  `AppWindowCoordinator.makePillPanel()` and reused.
- `.menuBarIcon` — no panel; the countdown is the status item's title, refreshed
  by `refreshMenuBarTitle()`.

### Who drives the transition

`AppWindowCoordinator.bindTimerService()` subscribes to
`TimerService.$isFocusMode` and calls `enterFocusPresentation()` /
`exitFocusPresentation()`. It also watches `$activeReminderId` and drops out of
focus mode when the last task ends (a break has no active task, so it keeps the
surface up).

Both subscriptions use `.receive(on: RunLoop.main)` because `@Published` fires
on `willSet`; deferring lets the property settle before anything reads it back.

The coordinator is the right owner because it owns every window, and because it
is always alive — a view is not.

### Moving the pill

The pill panel is borderless, so there is no title bar to drag it by, and
`isMovableByWindowBackground` does nothing on it: `NSHostingView` takes the
mouse-down and tracks it in its own loop, so AppKit never gets the chance to
start a window drag. Measured against the real panel settings — the identical
panel with a plain `NSView` content view drags; with the SwiftUI content view
it does not, and the mouse-down is swallowed. A drag-handling `NSView` behind
the SwiftUI content does not fix it either: the background fill wins the hit
test, and making the fill non-hit-testable stops the event reaching the app at
all.

`FloatingPillView.PillWindowDrag` applies `WindowDragGesture` (macOS 15+)
instead, so the drag starts inside SwiftUI. The hover controls keep working
because a `Button` claims the gesture over its own area. `PillWindowTopAnchor`
treats a pure move as the new resting top edge, so a dragged pill still grows
downwards when the subtask panel opens.

### Sizing the pill window

Nothing in AppKit resizes the pill window when the subtask panel unfolds, so
`PillHostingView` does it: on every layout pass it sets the window's content
size to the SwiftUI `fittingSize`. `sizingOptions = [.preferredContentSize]`
looked like it covered this and does not — that value is only read by an
`NSHostingController` presentation, and a plain hosting view as `contentView`
leaves the window at its opening size. `PillWindowTopAnchor` then turns the
growth downwards, so the pill holds its place and the panel unfolds beneath it.

### Starting a session

- Side strip footer "Start Timer" — starts the first visible task if none is
  running, then flips `isFocusMode`.
- The pill and menu bar panel — their own controls.
- A task card's play button, in `ReminderRowView` — everywhere the card
  appears, so the strip and the board behave the same.

## Decisions

- 2026-08-29 — The focus transition moved from `SideStripView.onChange` into
  `AppWindowCoordinator.bindTimerService()`. The strip is not mounted when a
  list board is open, so a session started from the board set `isFocusMode` and
  nothing happened. The auto-exit on `activeReminderId == nil` moved with it,
  for the same reason.
- 2026-08-29 — A card's play button always summons focus mode, on the board and
  in the strip. It first shipped as board-only, on the reasoning that the strip
  already renders the countdown, but two behaviours behind one icon was the
  worse trade: start-then-press-a-second-button was the odd step everywhere.
- 2026-09-17 — The pill moves with `WindowDragGesture`, not
  `isMovableByWindowBackground`. The panel had been movable-by-background since
  it was written, but nothing could ever drag it, because SwiftUI's hosting
  view consumes the mouse-down before the window sees it. `WindowDragHandler`
  (the `performDrag` NSView) stays unused — behind SwiftUI content it never
  receives the click.
- 2026-09-17 — The pill window sizes itself from `fittingSize` in
  `PillHostingView.layout()`. Before that the subtask panel unfolded into a
  300x44 window and was clipped to the top of its own header, with the pill
  pushed out of frame above it — measured on the commit before the drag fix
  too, so the two are unrelated.
