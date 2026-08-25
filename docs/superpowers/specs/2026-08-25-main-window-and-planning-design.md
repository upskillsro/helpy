# Helpy — main window, list boards, and weekly planning

Date: 2026-08-25
Status: approved design, not yet implemented

## Goal

Helpy today is a single 350pt side strip pinned to the edge of the screen. It
shows one Reminders list at a time and has one button that both narrows the app
to a timer and starts it.

This design makes a normal resizable window the app's home. The side strip stops
being the app and becomes one rung on a ladder: a focused view of a single
list's Today bucket. The window gains a second tab, Planning, holding an
app-only weekly goal / points / reward loop that Apple Reminders has no place
for.

## The three tiers

```
  Normal window            Side strip                 Floating pill
  (Lists | Planning)  →    (one list, Today only) →   (one task + timer)
       ▲                        ▲                          │
       └──────── back ──────────┴──── stop / exit ─────────┘
```

1. **Normal window.** Resizable, standard macOS title bar, two tabs.
   Lists shows a grid of every Reminders list; clicking a cell opens that list
   as a three-column board.
2. **Side strip.** Entered by pressing *Focus Today* in a board's Today column.
   The same window shrinks to the 350pt edge-pinned strip and shows only that
   list's Today bucket.
3. **Floating pill.** Entered by starting a timer on a task in the strip. The
   strip hides; the pill floats above everything. This tier already works and is
   unchanged.

Each step down narrows the scope; each step back up restores the one above. The
window is the same `NSWindow` throughout — only its chrome and content change.

## Window architecture

`HelpyApp` keeps its single `WindowGroup`. What changes is the root view and who
owns the window's chrome.

- The `WindowGroup` hosts a new `MainWindowView` instead of `SideStripView`.
  `SideStripView` becomes a child that `MainWindowView` shows in strip mode.
- The window has two modes, `MainWindowMode.normal` and `.strip`, applied by a
  single `MainWindowStyle.apply(mode:to:)` in `AppWindowCoordinator`. This
  mirrors `PillWindowStyle`: one place owns the style mask, level, movability,
  and frame for each mode, so no view can set half of it and drift.
  - `.normal` — `[.titled, .closable, .miniaturizable, .resizable]`, level
    `.normal`, movable, resizable, min size 900×620, remembered frame.
  - `.strip` — the existing look: `[.titled, .fullSizeContentView]`, level
    `.floating`, `isMovable = false`, 350pt wide, edge-pinned by
    `setupWindowPosition`, `.canJoinAllSpaces`.
- The style mask stays `.titled` in both modes. `NSWindow.canBecomeKey` is
  read-only and false for `.borderless`; a borderless window drops keystrokes.
  This is the same trap that crashed focus mode (see *Already landed*).

`AppNavigation` (new, `@MainActor final class … ObservableObject`) holds where
the user is:

```swift
enum MainTab { case lists, planning }

@Published var tab: MainTab = .lists
@Published var openListId: String?      // nil = grid
@Published var focusedListId: String?   // non-nil = strip mode
```

`AppWindowCoordinator` observes `focusedListId` and applies the window mode.
`TimerService.isFocusMode` keeps its current meaning — pill up, windows hidden —
and is now a separate, deeper step rather than a synonym for the strip.

## Lists tab

A grid of every Reminders list, **7 columns**, cells square (`aspect-ratio 1:1`),
9pt gutters, 14pt page padding. Column count is fixed rather than fluid; the
900pt minimum window width keeps a cell at roughly 110pt, which is the smallest
size the two peeked task lines stay legible at.

Each cell:

- **Header line** — a small icon square (17pt, radius 5) followed by the list
  name, one line, truncating tail.
- **Peek** — the first two incomplete tasks in the list, 8.5pt, muted, then a
  `+N` line when more remain.
- No progress bar and no task count.

A trailing dashed cell creates a new list: it takes a name inline and saves an
`EKCalendar(for: .reminder)` into the store's default reminders source. If no
source is writable the cell is hidden rather than failing on click.

### List icons

Default is a monogram: a rounded square filled with the list's own Reminders
colour, holding the first character of the list title in white, bold.

Uploading replaces it. `ListIconStore` (new) copies the chosen image to
`~/Library/Application Support/Helpy/ListIcons/<calendarIdentifier>.png`,
downscaled to 128×128. The file's existence *is* the state — there is no
parallel index to keep in sync, and deleting the file restores the monogram.
Drop a file on the square or click it to open a picker.

Icons are keyed by `calendarIdentifier`, which Apple Reminders keeps stable for
the life of a list. If a list is deleted its icon file is orphaned; a sweep on
launch removes icon files whose identifier no longer matches a fetched list.

## Board view

Clicking a cell opens that list as three columns, left to right:

**Backlog · This week · Today**

Today's column is tinted (`surfaceActive` fill, `surfaceActiveBorder`) — it is
the column the user acts on. Each column has a small uppercase header with a
count, a `＋ Add task…` row at the bottom, and Today additionally carries the
**Focus Today** button.

Cards are `ReminderRowView` exactly as it exists today: flat `surface` fill, 1px
border, radius 12, circle checkbox, 3pt `hot` bar on a high-priority task,
estimate chip, hover-swapped control buttons. No board-specific row type is
written; the strip and the board show the same component so they cannot drift.

### Bucket rules

A task's column is derived from its due date, never stored separately:

| Column | Rule |
|---|---|
| Today | due today, or overdue |
| This week | due after today and on or before the end of the current week |
| Backlog | no due date, **or** due after the end of the current week |

The last clause matters: without it a task due next month belongs to no column
and disappears from the board. "Backlog" therefore means "not this week",
not "undated".

The week ends according to `Calendar.current.firstWeekday`, so Helpy's weeks
match the user's system and the Planning tab. One `Week` helper computes the
boundaries and both features call it.

### Dragging

Dragging a card between columns rewrites its due date through
`RemindersService.updateDueDate`, so the move round-trips to Apple Reminders and
shows up on iPhone:

- → Today: due date set to today, 9:00 local, unless it already has a time today.
- → This week: due date set to the last day of the current week, 9:00 local.
- → Backlog: due date cleared, alarms cleared.

Dropping a card into the column it is already in reorders it within that column
via the existing `moveReminder`/`commitSortOrder` path; the sort-order key gains
the bucket so the three columns keep independent orders.

The drag preview reuses the strip's existing treatment: dashed border, faint
fill, ~1.4° rotation, soft shadow.

## Focus mode shows Today only

Pressing **Focus Today** sets `AppNavigation.focusedListId` to the open list. The
window becomes the strip and `SideStripView` renders **only that list's Today
bucket** — not the whole list, which is what it does today.

`SideStripView` gains one parameter, `listId: String`, and shows that list's
Today bucket. Its header becomes the list icon, the list name, "Today", and a
back chevron that returns to the board.

The header's list-picker dropdown goes away. The strip is scoped by where you
came from, not by a menu — and with the normal window as the app's home there
is no longer a path that opens the strip on Today-across-all-lists, so that
mode is not kept.

The footer button no longer does two jobs. In the strip it reads **Start Focus**
and does what it does now: start the timer on the first task and raise the pill.
Entering the strip is the board's job.

## Planning tab

A grid of week cards. Scope is a **rolling window**: the four weeks before the
current one, the current week, and the eight after — thirteen cards, current
week highlighted and scrolled into view on open. Weeks outside the window are
not shown and not created.

Clicking a week opens a right-hand side panel holding:

- **Goal** — one line of free text for the week.
- **Tasks** — an ordered list of app-only rows, each with a title, a point
  value, and a done checkbox. Add, edit, delete, reorder.
- **Points** — earned vs. target, from the checked tasks. A target is set per
  week.
- **Reward** — one line of free text, shown as earned once points ≥ target.

Points are per-week only. There is no lifetime ledger, no streak, and no
carry-over: a new week starts at zero.

### Why app-only

Weekly plan tasks are Helpy's own records, not `EKReminder`s. They are not
things to do at a time; they are the week's scoreboard. Pushing them into
Reminders would put untimed scoring rows into the user's real lists and into
iOS. They stay in Helpy.

`WeeklyPlanStore` (new) follows `SubtaskStore`: a JSON blob in `UserDefaults`
under `weeklyPlans_v1`, keyed by ISO week (`"2026-W35"`), decoded on init and
saved on every mutation.

```swift
struct WeeklyPlanTask: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var points: Int
    var isDone: Bool = false
}

struct WeeklyPlan: Codable {
    var goal: String = ""
    var pointsTarget: Int = 0
    var reward: String = ""
    var tasks: [WeeklyPlanTask] = []
}
```

A week with no entry decodes as an empty `WeeklyPlan`; nothing is written until
the user types something, so the store stays small and the rolling window needs
no backfill.

## Data layer

`RemindersService` currently fetches one list at a time into a flat
`reminders` array, selected by `activeListId`. The grid needs a peek at every
list and the board needs all of one list's tasks, so it gains a second path:

```swift
@Published var remindersByList: [String: [EKReminder]] = [:]
func fetchAllLists()          // populates remindersByList
func reminders(in listId: String) -> [EKReminder]
```

The existing `reminders` / `activeListId` path is left alone. The strip, the
pill, the menu bar dropdown, and the assistant keep reading it, so none of the
tiers that already work are touched by this change.

`fetchAllLists` runs on window open, on tab switch to Lists, and after any
mutation that could move a task between lists. Sorting reuses the existing
saved-order logic per list.

## Error handling

- **No Reminders access.** The grid shows the existing `accessDeniedView`
  full-window; Planning still works, because it does not touch EventKit.
- **A list is deleted while its board is open.** `fetchAllLists` finds no
  entry, the board pops back to the grid with no alert.
- **An icon file is unreadable.** The monogram is drawn. A broken image is never
  an error dialog.
- **A weekly plan fails to decode.** That week decodes as empty rather than
  taking the whole store down; other weeks are unaffected.
- Every EventKit mutation already logs through `AppLogger.reminders` and leaves
  the UI on its last good state. No new failure surface is introduced.

## Testing

Unit tests, `swift test`, no UI automation:

- `TaskBucketTests` — bucket derivation across the boundaries: overdue, due
  today, due at the end of the week, due next week, no due date. Injected
  "now" and an injected `firstWeekday`, both Sunday-start and Monday-start.
- `DueDateForBucketTests` — the drop rules produce the date each column expects,
  and dropping into Backlog clears alarms.
- `WeeklyPlanStoreTests` — round-trip encode/decode against an injected
  `UserDefaults`, empty week returns an empty plan, earned points sum only
  checked tasks, corrupt JSON for one week does not lose the others.
- `ListIconStoreTests` — a written icon is found, a missing icon reports absent,
  the orphan sweep removes only identifiers not in the passed-in list set.
- `MainWindowStyleTests` — like `PillWindowStyleTests`: both modes produce a
  key-able window, and applying a mode twice is idempotent.

Visual work — grid density, board spacing, the strip's Today-only header — is
checked by running the app, not by tests.

## Already landed

Two items from the same request are done and are not part of the work above:

- **Focus-mode crash fixed.** `FloatingPillView` called `object_setClass` on the
  pill window to make a `.borderless` window key-able. SwiftUI had already
  KVO-observed that window, so the swizzle subclassed KVO's own
  `NSKVONotifying_*` class and corrupted its bookkeeping; the next write to an
  observed property died inside `_NSSetBoolValueAndNotify`. The swizzling is
  gone, the mask is `[.titled, .fullSizeContentView]`, and all pill chrome now
  lives in one `PillWindowStyle.apply(to:)` that both `FloatingPillView` and
  `SideStripView` call. Covered by `PillWindowStyleTests`.
- **Hot corner removed.** `startHotCornerMonitoring`, `pollHotCorner`,
  `revealMainWindow`, the 0.2s poll timer, the `hotCornerEnabled` setting, and
  its Settings toggle are deleted.

## Out of scope

- Syncing weekly plans to iOS or to Reminders.
- A lifetime points ledger, streaks, or carry-over between weeks.
- Editing list names, colours, or membership from the grid — those stay in
  Apple Reminders.
- Reworking `ReminderRowView` or the assistant.
- A detail pane on the board. Task detail stays where it is, behind the row's
  hover controls.

## Files

New:

```
Sources/Services/AppNavigation.swift
Sources/Services/WeeklyPlanStore.swift
Sources/Services/ListIconStore.swift
Sources/Services/TaskBucket.swift        (bucket rules + Week helper)
Sources/UI/MainWindow/MainWindowView.swift
Sources/UI/MainWindow/ListsGridView.swift
Sources/UI/MainWindow/ListCellView.swift
Sources/UI/MainWindow/ListIconSquare.swift
Sources/UI/MainWindow/ListBoardView.swift
Sources/UI/MainWindow/BoardColumnView.swift
Sources/UI/Planning/PlanningView.swift
Sources/UI/Planning/WeekCardView.swift
Sources/UI/Planning/WeekDetailPanel.swift
```

Changed:

```
Sources/HelpyApp.swift                   host MainWindowView; window sizing
Sources/Services/AppWindowCoordinator.swift   MainWindowStyle, mode switching
Sources/Services/RemindersService.swift  remindersByList + fetchAllLists
Sources/UI/SideStripView.swift           listId scope; Today-only; back chevron
```

`SideStripView` is already 889 lines. Adding scope to it is a few lines, but the
settings sheet it embeds and the assistant panel it hosts belong elsewhere. That
split is worth doing while the file is open, and is the only refactor this
design invites.
