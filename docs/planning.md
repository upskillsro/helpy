# Planning

## Purpose

The Planning tab is the long game beside the short one: a roadmap column on the
left (one goal, the thinking behind it, milestones and steps), a rolling grid of
weeks in the middle, and a side panel for whichever week you open.

A week is a slice of time; the roadmap is what the slices add up to. That is why
the roadmap sits beside the weeks rather than inside one.

## Architecture

- `Sources/UI/Planning/PlanningView.swift` — the three-column layout and the
  rolling window of weeks.
- `RoadmapColumn.swift` — the roadmap: goal, notes, and the two-level checklist.
- `WeekCardView.swift` — a week in the grid, plus the hero card for the current
  week.
- `WeekDetailPanel.swift` — the open week: goal, the list it mirrors into, the
  scored tasks, notes, and the reward. `WeekTaskRow` and `WeekTaskComposer` live
  here too.
- `Sources/Services/RoadmapStore.swift`, `WeeklyPlanStore.swift` — one JSON blob
  each in `UserDefaults`. `WeeklyPlanSync.swift` mirrors a week's tasks into a
  Reminders list; every task write in the panel goes through it, never the store
  directly.
- `Sources/UI/Components/HelpyTextView.swift` — the multi-line text box used by
  the roadmap goal, the roadmap notes and the week notes.

### Free text: why not TextField

`TextField(axis: .vertical)` commits on Return on macOS, and no modifier changes
that, so none of the free-text fields here could hold a line break. They are all
`HelpyTextView`: an `NSTextView` on an explicit TextKit 1 stack that reports its
height through `sizeThatFits` and grows with its content instead of scrolling.

Two things it does deliberately:

- It builds its own text storage / layout manager / container rather than taking
  a bare `NSTextView()`. A bare one comes up on TextKit 2 and only falls back the
  first time `layoutManager` is touched — which is what the height measurement
  does on every layout pass.
- It restyles the text storage only when the style actually changed. Doing it on
  every update means doing it on every keystroke, which walks over marked text
  (the half-composed state a dead key or an IME is in mid-character).

### Adding a field to a stored plan

`WeeklyPlan` decodes every key with `decodeIfPresent`. Swift's synthesised
decoder throws `keyNotFound` for a property that stored data predates — and
`WeeklyPlanStore` drops a week it cannot decode — so a field added the
synthesised way would quietly delete every plan written before it.

## Decisions

- 2026-08-31 — Week task titles are one line, and the hover controls are drawn as
  an overlay on top of the row (the arrangement `ReminderRowView` uses on the
  board) rather than as siblings of the title. Laid out inline they stole width,
  so pointing at a row was enough to make it re-wrap and grow.
- 2026-08-31 — A week gets a free-text notes field. Not scored, not mirrored into
  Reminders: it is the place for the context a task title cannot carry.
- 2026-08-31 — The roadmap goal and notes accept Return as a line break, via
  `HelpyTextView`. A goal you cannot break into lines is a goal you have to write
  as one run-on sentence.
- The target for a week IS the total points on its board. A target the user could
  set independently of the tasks was a second place for the same fact to be wrong.
