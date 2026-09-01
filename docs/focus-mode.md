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
