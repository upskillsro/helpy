# List board (Backlog → This week → Today → Completed)

## Purpose

One Reminders list shown as a four-column board. Dragging a card between
columns is how a task gets rescheduled, so the columns have to mean something a
due date can express.

## Architecture

- `Sources/Services/TaskBucket.swift` — `TaskBucket` (the four columns) and
  `HelpyWeek` (all the date arithmetic). Nothing else does week maths.
- `Sources/UI/MainWindow/ListBoardView.swift` — groups the list into columns and
  handles drops (`place(_:into:at:)`).
- `Sources/UI/MainWindow/BoardColumnView.swift` — one column, its drop slots.
- `Sources/Services/RemindersService.placeReminder` — ordering within a column.

A bucket is always **derived** from the due date, never stored. A drop writes
the due date the target column implies, so the move round-trips through EventKit
and shows up in Apple Reminders on the phone. Completed is the exception: it is
a flag, not a date, and comes from its own fetch.

Column rules (`HelpyWeek`):

- **Today** — due before tomorrow (so: due today, or overdue).
- **This week** — due before `thisWeekEnd`.
- **Backlog** — undated, or due after this week. "Backlog" means *not this
  week*, not *undated*; without that rule a task due next month would vanish.

`thisWeekEnd` is normally the start of next week. On the final day of the week
it rolls forward a week — see the decision below.

## Decisions

- 2026-08-30 — On the **last day of the week**, "This week" means the week that
  starts tomorrow. Before this, the remaining-week window was empty on that day,
  so a card dragged from Today into This week was handed today's date back and
  snapped straight home: the column was a dead drop target one day in seven (on
  a Monday-start calendar, every Sunday) and read as a broken board. Trade-off:
  for that one day the board's "this week" is the week ahead while the Planning
  tab still shows the current calendar week. Accepted — on the last day of a
  week there is nothing left to plan in it.
- 2026-08-30 — A drop target writes **day components only**, never a time.
  Deriving components from a `Date` used to stamp every card dropped into Today
  as due at 9:00, alarm included.
- 2026-08-30 — Priority shows as an inset capsule on the card's leading edge,
  and the row no longer draws a priority flag icon. The flag repeated what the
  bar already said, and EventKit exposes no separate "flagged" field for
  reminders, so it could never mean anything else.
