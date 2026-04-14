# Helpy — Polish & Features Design
**Date:** 2026-04-13

---

## Overview

Five targeted changes to the Helpy macOS app: a time estimate input fix, a pill/menu-bar display toggle, a pill text layout fix, an app-only subtask system in the floating pill, and an iOS 26 Liquid Glass upgrade for the glass theme.

---

## 1. Time Estimate Input Fix

**Problem:** `EstimatePopover` and `TimeSpentPopover` call `parseAndUpdate` on every keystroke via the `set:` binding. Backspacing mid-entry saves garbage values (e.g. typing "01" saves 1 minute before you finish entering "01:30").

**Fix:** Decouple the live editing string from the store write.

- `textInput` state is used purely for display while typing.
- `parseAndUpdate` is called only on `onSubmit` (Enter key) and on popover dismiss (`.onDisappear`).
- The `set:` binding on the `TextField` updates only `textInput` — no store write.
- The existing HH:MM auto-colon formatting logic stays intact (it only affects `textInput`, not the store).

**Files affected:** `Sources/UI/ReminderRowView.swift` — `EstimatePopover` and `TimeSpentPopover` structs.

---

## 2. Pill vs Menu Bar Display Mode

**Goal:** A setting in `EmbeddedSettingsView` that switches the focus timer display between a floating pill window and a menu bar icon.

### Data model
Add to `SettingsStore`:
```swift
enum PillDisplayMode: String, CaseIterable {
    case floatingPill
    case menuBarIcon
}
@AppStorage("pillDisplayMode") var pillDisplayMode: PillDisplayMode = .floatingPill
```

### Behaviour
- **`.floatingPill`** (default): current behaviour — pill window floats on screen.
- **`.menuBarIcon`**: pill window is hidden; an `NSStatusItem` is created showing the formatted timer string (e.g. `"24:13"` or `"Break"`). Clicking the status item opens the main panel.

### Implementation
- `AppWindowCoordinator` observes `pillDisplayMode` and toggles `pillWindow.orderOut` / `NSStatusBar.system.statusItem`.
- The `NSStatusItem` is only created when mode is `.menuBarIcon`; it is removed when switching back to `.floatingPill`.
- Menu bar item title updates on every timer tick via the existing `TimerService.ticker`.

### Settings UI
Add a segmented control or toggle row in `EmbeddedSettingsView` under the existing Appearance section:
```
Display Timer As:  [ Floating Pill ]  [ Menu Bar Icon ]
```

**Files affected:** `SettingsStore.swift`, `AppWindowCoordinator.swift`, `EmbeddedSettingsView.swift`, `HelpyApp.swift` (status item lifecycle).

---

## 3. Pill Text Rendering Fix

**Problem:** `PillTitleView` uses `.frame(maxWidth: 180)` inside a `fixedSize(horizontal: true, vertical: true)` container, causing layout conflicts that occasionally squish or mis-wrap text.

**Fix:** Remove `.frame(maxWidth: 180)` from `PillTitleView`. The pill's outer `.frame(minWidth: 280)` already constrains width. `lineLimit(2)` and `fixedSize(horizontal: false, vertical: true)` continue to handle multi-line wrapping correctly without a conflicting max-width.

**Files affected:** `Sources/UI/FloatingPillView.swift` — `PillTitleView`.

---

## 4. Floating Pill Subtask Panel

### Overview
App-only subtasks (not written to Reminders) attached to each task, accessible from the floating pill. A new button in `PillControlsView` (the hover control bar) toggles an inline expansion panel below the pill header.

### Data model — `SubtaskStore`
New file: `Sources/Services/SubtaskStore.swift`

```swift
struct SubtaskItem: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool = false
}

class SubtaskStore: ObservableObject {
    // Keyed by calendarItemIdentifier
    func subtasks(for taskId: String) -> [SubtaskItem]
    func addSubtask(_ title: String, for taskId: String)
    func toggleSubtask(_ id: UUID, for taskId: String)
    func deleteSubtask(_ id: UUID, for taskId: String)
}
```

Persistence: `UserDefaults` via `JSONEncoder`/`JSONDecoder`, key `"subtasks_v1"`. Stored as `[String: [SubtaskItem]]`.

### UI — `PillControlsView` button
Add an `IconButton` to `PillControlsView` using `systemImage: "checklist"`. It is only shown when there is an active task (not on break). Tapping toggles `@State var showSubtasks: Bool` on `FloatingPillView`.

The button shows a badge dot if there are incomplete subtasks (small filled circle overlay on the icon).

### UI — `SubtasksPanelView`
A new view rendered below the pill header row when `showSubtasks == true`:

```
┌─────────────────────────────────────┐
│  Write quarterly report  │  24:13  ✕ │  ← existing header
├─────────────────────────────────────┤
│  Subtasks                            │
│  ○  Draft executive summary          │
│  ✓  Research competitors  (struck)   │
│  ○  Review with manager              │
│  [+ Add subtask…          ]          │
└─────────────────────────────────────┘
       ██████████░░░░░░░░░░░  ← progress bar
```

- Each row: circle checkbox button + title text. Tapping checkbox calls `subtaskStore.toggleSubtask`.
- "Add subtask…" is a `TextField` with `.plain` style; pressing Enter commits and clears the field.
- Panel collapses when `showSubtasks` is set to false (✕ in header, or pressing the checklist button again, or `onExitCommand`).
- Animation: `.easeInOut(duration: 0.2)` on height change.
- The pill window auto-resizes because it uses `fixedSize` — the intrinsic content size drives the window frame.

**Files affected:** New `SubtaskStore.swift`; `FloatingPillView.swift` (state, button, panel); `HelpyApp.swift` (inject `SubtaskStore` as environment object).

---

## 5. iOS 26 Liquid Glass Theme

### Goal
When the glass theme is active on macOS 26+, use Apple's native `.glassEffect()` modifier instead of the custom `IceGlassSurface` stack. Fall back to the existing `IceGlass` implementation on macOS < 26.

### API used (macOS 26+ / iOS 26+)
```swift
// Basic surface
view.glassEffect(.regular, in: RoundedRectangle(cornerRadius: r, style: .continuous))

// Grouped glass elements (shared sampling region)
GlassEffectContainer { ... }

// Morphing between states
.glassEffectID("id", in: namespace)
```

### Implementation
`IceGlass.swift` gets a conditional wrapper:

```swift
@ViewBuilder
func liquidGlassSurface(cornerRadius: CGFloat) -> some View {
    if #available(macOS 26.0, *) {
        Color.clear
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    } else {
        IceGlassSurface(cornerRadius: cornerRadius)
    }
}
```

The same pattern is applied to `IceGlassStroke` — on macOS 26+ the stroke is dropped (`.glassEffect` renders its own edge treatment). On older macOS, `IceGlassStroke` is used unchanged.

The `IceGrainOverlay` and green-tinted gradient are removed from the macOS 26 path — Apple's liquid glass handles all surface qualities.

`FloatingPillView` wraps its background in `GlassEffectContainer` on macOS 26+ so that the pill header and subtask panel share a single glass sampling region and morph cleanly when the panel opens/closes.

**Files affected:** `Sources/UI/IceGlass.swift`; `Sources/UI/FloatingPillView.swift`; `Sources/UI/ReminderRowView.swift` (glass overlay); `Sources/UI/EmbeddedSettingsView.swift` (`GlassyBackground`).

---

## What is NOT changing

- Notes editor in `ReminderRowView` — unchanged.
- Reminders data model — subtasks are fully app-side, no `EKReminder` writes.
- Dark and white themes — unaffected by liquid glass changes.
- Timer logic, break system, assistant feature — untouched.
