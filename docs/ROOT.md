# Helpy docs

Index of the durable notes. One line per doc.

- [list-board.md](list-board.md) — the four board columns, how a due date maps
  to a column, and the week-boundary rules behind the drag targets.
- [focus-mode.md](focus-mode.md) — the three-tier hierarchy (window → strip →
  pill), who owns the transition, and how a focus session is started.
- [floating-pill-subtasks.md](floating-pill-subtasks.md) — the pill's detached
  subtask panel and its glass container.
- [pill-rendering.md](pill-rendering.md) — why the pill's scrolling title and
  rolling clock are Core Animation, and the measurements behind it.
- [planning.md](planning.md) — the roadmap column, the week grid and the week
  panel, plus why every free-text field there is an NSTextView.
- apple_liquid_glass_page1-5.md — captured Apple reference on Liquid Glass.
- superpowers/ — historical specs and plans, kept for context only.

## Stack

Swift package, SwiftUI, AppKit for windows and panels, EventKit for Reminders.
macOS 14+ deployment, macOS 26 APIs behind availability checks. Ollama and a
local Whisper CLI back the assistant; both are optional.

## Source layout

- `Sources/Services/` — state and side effects. `RemindersService` (EventKit),
  `TimerService` + `TimeTicker`, `EstimateStore`, `SubtaskStore`,
  `AppNavigation`, `AppWindowCoordinator` (owns every window), `SettingsStore`,
  weekly plan and roadmap stores, `Assistant/` (Ollama, transcription).
- `Sources/UI/MainWindow/` — the normal window: lists grid, one list as a board.
- `Sources/UI/SideStripView.swift` — the 350pt strip.
- `Sources/UI/FloatingPillView.swift`, `MenuBarPanelView.swift` — focus surfaces.
- `Sources/UI/ReminderRowView.swift` — the task card, shared by strip and board.
- `Sources/UI/Planning/` — the Planning tab: roadmap column, week grid, week panel.
- `Sources/UI/Components/` — small shared pieces. `HelpyTextView` is the
  multi-line text box that takes Return as a line break; `CAMarqueeText` and
  `RollingTimeText` are the pill's Core Animation title and clock.
- `Sources/UI/Theme.swift` — palette, metrics, fonts.
