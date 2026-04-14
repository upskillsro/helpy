# Helpy Polish & Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the time estimate input bug, add a pill/menu-bar display toggle, fix pill text layout, add app-only subtasks to the floating pill, and conditionally apply iOS 26 Liquid Glass to the glass theme.

**Architecture:** Five independent changes touching UI, a new data store, settings, and conditional OS API usage. Each task is self-contained. The SubtaskStore follows the same UserDefaults+Codable pattern as EstimateStore. Liquid Glass is gated behind `#available(macOS 26.0, *)` so the app continues to compile and run on macOS 14+.

**Tech Stack:** SwiftUI, AppKit, EventKit, UserDefaults (Codable), XCTest, `glassEffect`/`GlassEffectContainer` (macOS 26+)

---

## File Map

| Action | Path | Responsibility |
|--------|------|---------------|
| Modify | `Sources/UI/ReminderRowView.swift` | Fix EstimatePopover + TimeSpentPopover parse-on-commit |
| Modify | `Sources/UI/FloatingPillView.swift` | Fix PillTitleView layout; add showSubtasks state + SubtasksPanelView; pass binding to PillControlsView; conditional glass background |
| Modify | `Sources/Services/SettingsStore.swift` | Add PillDisplayMode enum + setting |
| Modify | `Sources/Services/AppWindowCoordinator.swift` | Add NSStatusItem management |
| Modify | `Sources/UI/EmbeddedSettingsView.swift` | Add display mode toggle; update GlassyBackground |
| Modify | `Sources/HelpyApp.swift` | Gate pill window on display mode; observe ticker for status item; inject SubtaskStore |
| Create | `Sources/Services/SubtaskStore.swift` | SubtaskItem model + SubtaskStore |
| Create | `Tests/HelpyTests/SubtaskStoreTests.swift` | Unit tests for SubtaskStore |
| Modify | `Sources/UI/IceGlass.swift` | Add conditional macOS 26 liquidGlassBackground function |
| Modify | `Sources/UI/ReminderRowView.swift` | Update glassOverlayBase to use liquid glass on macOS 26+ |

---

## Task 1: Fix time estimate input — parse on commit only

**Files:**
- Modify: `Sources/UI/ReminderRowView.swift` — `EstimatePopover` and `TimeSpentPopover`

The bug: both popovers call `parseAndUpdate` inside the `set:` closure of the `TextField` binding, which fires on every keystroke. Fix: update only `textInput` on each keystroke; call `parseAndUpdate` in `onSubmit` and `onDisappear`.

- [ ] **Step 1: Update `EstimatePopover`**

Replace the entire `EstimatePopover` struct with:

```swift
struct EstimatePopover: View {
    let reminder: EKReminder
    @ObservedObject var estimates: EstimateStore.TaskEstimates
    @EnvironmentObject var estimateStore: EstimateStore

    @State private var textInput: String = ""

    var body: some View {
        VStack(spacing: 8) {
            Text("Set Estimate")
                .font(.headline)

            TextField("HH:MM", text: $textInput)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .onSubmit { parseAndUpdate(textInput) }
        }
        .padding()
        .onAppear {
            let total = estimates.estimatedDuration
            if total > 0 {
                let h = Int(total) / 3600
                let m = (Int(total) % 3600) / 60
                textInput = String(format: "%02d:%02d", h, m)
            }
        }
        .onDisappear { parseAndUpdate(textInput) }
    }

    private func parseAndUpdate(_ input: String) {
        let cleaned = input.filter { "0123456789:".contains($0) }
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":").map { String($0) }
            if parts.count == 2 {
                let h = Int(parts[0]) ?? 0
                let m = Int(parts[1]) ?? 0
                estimateStore.updateEstimate(for: reminder.calendarItemIdentifier,
                                             duration: TimeInterval(h * 3600 + m * 60))
            }
        } else {
            let digits = cleaned.filter { $0.isNumber }
            if digits.count >= 3 {
                let h = Int(String(digits.dropLast(2))) ?? 0
                let m = Int(String(digits.suffix(2))) ?? 0
                estimateStore.updateEstimate(for: reminder.calendarItemIdentifier,
                                             duration: TimeInterval(h * 3600 + m * 60))
            } else if !digits.isEmpty {
                let m = Int(digits) ?? 0
                estimateStore.updateEstimate(for: reminder.calendarItemIdentifier,
                                             duration: TimeInterval(m * 60))
            }
        }
    }
}
```

- [ ] **Step 2: Update `TimeSpentPopover`**

Replace the entire `TimeSpentPopover` struct with:

```swift
struct TimeSpentPopover: View {
    let reminder: EKReminder
    @ObservedObject var estimates: EstimateStore.TaskEstimates
    @EnvironmentObject var estimateStore: EstimateStore

    @State private var textInput: String = ""

    var body: some View {
        VStack(spacing: 8) {
            Text("Set Time Spent")
                .font(.headline)

            TextField("HH:MM", text: $textInput)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .onSubmit { parseAndUpdate(textInput) }
        }
        .padding()
        .onAppear {
            let total = estimates.timeSpent
            if total > 0 {
                let h = Int(total) / 3600
                let m = (Int(total) % 3600) / 60
                textInput = String(format: "%02d:%02d", h, m)
            }
        }
        .onDisappear { parseAndUpdate(textInput) }
    }

    private func parseAndUpdate(_ input: String) {
        let cleaned = input.filter { "0123456789:".contains($0) }
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":").map { String($0) }
            if parts.count == 2 {
                let h = Int(parts[0]) ?? 0
                let m = Int(parts[1]) ?? 0
                estimateStore.setTimeSpent(for: reminder.calendarItemIdentifier,
                                           seconds: TimeInterval(h * 3600 + m * 60))
            }
        } else {
            let digits = cleaned.filter { $0.isNumber }
            if digits.count >= 3 {
                let h = Int(String(digits.dropLast(2))) ?? 0
                let m = Int(String(digits.suffix(2))) ?? 0
                estimateStore.setTimeSpent(for: reminder.calendarItemIdentifier,
                                           seconds: TimeInterval(h * 3600 + m * 60))
            } else if !digits.isEmpty {
                let m = Int(digits) ?? 0
                estimateStore.setTimeSpent(for: reminder.calendarItemIdentifier,
                                           seconds: TimeInterval(m * 60))
            }
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
cd /Users/lungusebi/Desktop/AI/Apps/Helpy && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 4: Manual test**

Run the app. Open a task's estimate popover. Type "1" — verify nothing is saved yet. Type ":30" so it reads "1:30". Press Enter. Hover away and reopen — should show "01:30". Backspace to clear, dismiss — should save "00:00" (0 duration).

- [ ] **Step 5: Commit**

```bash
git add Sources/UI/ReminderRowView.swift
git commit -m "fix: parse time estimate only on submit/dismiss, not per keystroke"
```

---

## Task 2: Fix pill title text layout

**Files:**
- Modify: `Sources/UI/FloatingPillView.swift` — `PillTitleView`

Remove the conflicting `.frame(maxWidth: 180)` from `PillTitleView`. The pill's outer `minWidth: 280` is the correct constraint.

- [ ] **Step 1: Update `PillTitleView`**

Find `PillTitleView` in `Sources/UI/FloatingPillView.swift` (around line 322). Replace the `body` with:

```swift
var body: some View {
    Text(title)
        .font(.body)
        .fontWeight(.medium)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)
}
```

(Remove the `.frame(maxWidth: 180)` line.)

- [ ] **Step 2: Build and verify**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/FloatingPillView.swift
git commit -m "fix: remove conflicting maxWidth on pill title, fix text rendering"
```

---

## Task 3: Add PillDisplayMode to SettingsStore

**Files:**
- Modify: `Sources/Services/SettingsStore.swift`

- [ ] **Step 1: Add enum and property**

Add to `Sources/Services/SettingsStore.swift` after the `AppTheme` enum:

```swift
enum PillDisplayMode: String, CaseIterable {
    case floatingPill
    case menuBarIcon
}
```

Add inside the `SettingsStore` class, after `@AppStorage("appTheme") var appTheme`:

```swift
@AppStorage("pillDisplayMode") var pillDisplayMode: PillDisplayMode = .floatingPill
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Services/SettingsStore.swift
git commit -m "feat: add PillDisplayMode setting (floatingPill / menuBarIcon)"
```

---

## Task 4: Menu bar mode — AppWindowCoordinator + HelpyApp

**Files:**
- Modify: `Sources/Services/AppWindowCoordinator.swift`
- Modify: `Sources/HelpyApp.swift`

- [ ] **Step 1: Add status item management to AppWindowCoordinator**

Replace the entire contents of `Sources/Services/AppWindowCoordinator.swift` with:

```swift
import AppKit
import Foundation

@MainActor
final class AppWindowCoordinator: ObservableObject {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("focus.main.window")
    static let pillWindowIdentifier = NSUserInterfaceItemIdentifier("focus.pill.window")

    weak var mainWindow: NSWindow?
    weak var pillWindow: NSWindow?
    var hasPrewarmedPillWindow = false

    private var statusItem: NSStatusItem?

    func applyDisplayMode(_ mode: PillDisplayMode) {
        switch mode {
        case .floatingPill:
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        case .menuBarIcon:
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timer")
            item.button?.imagePosition = .imageLeft
            statusItem = item
        }
    }

    func updateMenuBarTitle(_ text: String) {
        guard let button = statusItem?.button else { return }
        button.title = " \(text)"
    }
}
```

- [ ] **Step 2: Gate pill window and feed ticker to menu bar in HelpyApp**

In `Sources/HelpyApp.swift`, add `@AppStorage` for `pillDisplayMode` at the top of `HelpyApp`:

```swift
@AppStorage("pillDisplayMode") private var pillDisplayMode: PillDisplayMode = .floatingPill
```

Find the `Window("Timer", id: "timer-pill")` scene. Change the condition from:

```swift
if timerService.isFocusMode && (timerService.activeReminderId != nil || timerService.isOnBreak) {
    FloatingPillView()
        ...
}
```

to:

```swift
if timerService.isFocusMode &&
   (timerService.activeReminderId != nil || timerService.isOnBreak) &&
   pillDisplayMode == .floatingPill {
    FloatingPillView()
        .environmentObject(timerService)
        .environmentObject(remindersService)
        .environmentObject(estimateStore)
        .environmentObject(windowCoordinator)
}
```

Then, inside the `.onAppear` block of the main `SideStripView` (after the existing setup), add:

```swift
// Apply initial display mode
windowCoordinator.applyDisplayMode(pillDisplayMode)
```

After the closing brace of `.onAppear`, add two `.onChange` modifiers on the `SideStripView`:

```swift
.onChange(of: pillDisplayMode) { _, mode in
    windowCoordinator.applyDisplayMode(mode)
}
.onChange(of: timerService.ticker.tick) { _, _ in
    guard pillDisplayMode == .menuBarIcon,
          timerService.isFocusMode else { return }
    windowCoordinator.updateMenuBarTitle(timerService.formattedTime())
}
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -10
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/Services/AppWindowCoordinator.swift Sources/HelpyApp.swift
git commit -m "feat: add menu bar icon mode — NSStatusItem shows timer when pill is hidden"
```

---

## Task 5: Add display mode toggle to EmbeddedSettingsView

**Files:**
- Modify: `Sources/UI/EmbeddedSettingsView.swift`

- [ ] **Step 1: Add the toggle row**

In `Sources/UI/EmbeddedSettingsView.swift`, inside the `// APPEARANCE` `VStack`, after the `HStack(spacing: 20)` that holds the theme cards (and before the closing brace of the Appearance VStack), add:

```swift
HStack {
    Text("Show Timer As")
        .foregroundColor(.primary)
    Spacer()

    Menu {
        Button("Floating Pill") { settings.pillDisplayMode = .floatingPill }
        Button("Menu Bar Icon") { settings.pillDisplayMode = .menuBarIcon }
    } label: {
        HStack {
            Text(settings.pillDisplayMode == .floatingPill ? "Floating Pill" : "Menu Bar Icon")
                .foregroundColor(menuTextColor)
                .fontWeight(.medium)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 160)
        .background(GlassyBackground(theme: settings.appTheme))
    }
    .menuStyle(.borderlessButton)
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Manual test**

Run the app. Open Settings. Switch to "Menu Bar Icon". Enter focus mode — verify the floating pill disappears and a timer appears in the menu bar. Switch back to "Floating Pill" — verify pill returns.

- [ ] **Step 4: Commit**

```bash
git add Sources/UI/EmbeddedSettingsView.swift
git commit -m "feat: add Show Timer As toggle in settings (floating pill / menu bar icon)"
```

---

## Task 6: Create SubtaskStore with tests

**Files:**
- Create: `Sources/Services/SubtaskStore.swift`
- Create: `Tests/HelpyTests/SubtaskStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/HelpyTests/SubtaskStoreTests.swift`:

```swift
import XCTest
@testable import Helpy

final class SubtaskStoreTests: XCTestCase {
    private var store: SubtaskStore!
    private let taskId = "test-task-abc"
    private let testDefaults = UserDefaults(suiteName: "com.helpy.subtask-tests")!

    override func setUp() {
        super.setUp()
        testDefaults.removePersistentDomain(forName: "com.helpy.subtask-tests")
        store = SubtaskStore(defaults: testDefaults)
    }

    func testAddSubtask() {
        store.addSubtask(title: "Do the thing", for: taskId)
        let items = store.subtasks(for: taskId)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Do the thing")
        XCTAssertFalse(items[0].isCompleted)
    }

    func testToggleSubtaskCompletion() {
        store.addSubtask(title: "Do the thing", for: taskId)
        let id = store.subtasks(for: taskId)[0].id
        store.toggleSubtask(id: id, for: taskId)
        XCTAssertTrue(store.subtasks(for: taskId)[0].isCompleted)
        store.toggleSubtask(id: id, for: taskId)
        XCTAssertFalse(store.subtasks(for: taskId)[0].isCompleted)
    }

    func testDeleteSubtask() {
        store.addSubtask(title: "Do the thing", for: taskId)
        let id = store.subtasks(for: taskId)[0].id
        store.deleteSubtask(id: id, for: taskId)
        XCTAssertEqual(store.subtasks(for: taskId).count, 0)
    }

    func testSubtasksForUnknownTaskAreEmpty() {
        XCTAssertEqual(store.subtasks(for: "no-such-task").count, 0)
    }

    func testMultipleTasksAreIsolated() {
        store.addSubtask(title: "Task A subtask", for: "task-a")
        store.addSubtask(title: "Task B subtask", for: "task-b")
        XCTAssertEqual(store.subtasks(for: "task-a").count, 1)
        XCTAssertEqual(store.subtasks(for: "task-b").count, 1)
        XCTAssertEqual(store.subtasks(for: "task-a")[0].title, "Task A subtask")
    }

    func testPersistence() {
        store.addSubtask(title: "Persisted", for: taskId)
        let store2 = SubtaskStore(defaults: testDefaults)
        XCTAssertEqual(store2.subtasks(for: taskId).count, 1)
        XCTAssertEqual(store2.subtasks(for: taskId)[0].title, "Persisted")
    }
}
```

- [ ] **Step 2: Run tests — verify they fail (SubtaskStore not yet defined)**

```bash
swift test --filter SubtaskStoreTests 2>&1 | tail -10
```

Expected: compile error — `cannot find type 'SubtaskStore' in scope`

- [ ] **Step 3: Create SubtaskStore**

Create `Sources/Services/SubtaskStore.swift`:

```swift
import Foundation
import SwiftUI

struct SubtaskItem: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool = false
}

class SubtaskStore: ObservableObject {
    private let key = "subtasks_v1"
    private let defaults: UserDefaults
    @Published private var store: [String: [SubtaskItem]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func subtasks(for taskId: String) -> [SubtaskItem] {
        store[taskId] ?? []
    }

    func addSubtask(title: String, for taskId: String) {
        var items = store[taskId] ?? []
        items.append(SubtaskItem(title: title))
        store[taskId] = items
        save()
    }

    func toggleSubtask(id: UUID, for taskId: String) {
        guard var items = store[taskId],
              let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isCompleted.toggle()
        store[taskId] = items
        save()
    }

    func deleteSubtask(id: UUID, for taskId: String) {
        guard var items = store[taskId] else { return }
        items.removeAll { $0.id == id }
        store[taskId] = items
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        defaults.set(data, forKey: key)
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [SubtaskItem]].self, from: data)
        else { return }
        store = decoded
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
swift test --filter SubtaskStoreTests 2>&1 | tail -15
```

Expected: `Test Suite 'SubtaskStoreTests' passed` — 6 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Services/SubtaskStore.swift Tests/HelpyTests/SubtaskStoreTests.swift
git commit -m "feat: add SubtaskStore — app-only per-task subtasks with UserDefaults persistence"
```

---

## Task 7: Add subtask panel to FloatingPillView

**Files:**
- Modify: `Sources/UI/FloatingPillView.swift`
- Modify: `Sources/HelpyApp.swift`

- [ ] **Step 1: Inject SubtaskStore in HelpyApp**

In `Sources/HelpyApp.swift`, add alongside the other `@StateObject` declarations:

```swift
@StateObject var subtaskStore = SubtaskStore()
```

Add `.environmentObject(subtaskStore)` to both the `SideStripView()` and `FloatingPillView()` chains. The FloatingPillView chain becomes:

```swift
FloatingPillView()
    .environmentObject(timerService)
    .environmentObject(remindersService)
    .environmentObject(estimateStore)
    .environmentObject(windowCoordinator)
    .environmentObject(subtaskStore)
```

The SideStripView chain gains:

```swift
.environmentObject(subtaskStore)
```

- [ ] **Step 2: Add showSubtasks state and SubtaskStore to FloatingPillView**

In `Sources/UI/FloatingPillView.swift`, inside `FloatingPillView`, add:

```swift
@EnvironmentObject var subtaskStore: SubtaskStore
@State private var showSubtasks = false
```

- [ ] **Step 3: Pass showSubtasks binding to PillControlsView**

In `FloatingPillView.body`, change the `PillControlsView(...)` call to:

```swift
PillControlsView(
    isHovering: $isHovering,
    showSubtasks: $showSubtasks,
    timerService: timerService,
    remindersService: remindersService,
    estimateStore: estimateStore
)
```

- [ ] **Step 4: Add SubtasksPanelView below the info/controls ZStack**

In `FloatingPillView.body`, the outer content is currently:

```swift
ZStack {
    if isHovering { PillControlsView(...) } else { PillInfoView(...) }
}
.frame(minWidth: 280, minHeight: 42)
.fixedSize(horizontal: true, vertical: true)
.padding(.horizontal, 6)
.padding(.vertical, 7)
```

Wrap that entire `ZStack` + modifiers in a `VStack` and add the panel below:

```swift
VStack(spacing: 0) {
    ZStack {
        if isHovering {
            PillControlsView(
                isHovering: $isHovering,
                showSubtasks: $showSubtasks,
                timerService: timerService,
                remindersService: remindersService,
                estimateStore: estimateStore
            )
            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        } else {
            PillInfoView(
                timerService: timerService,
                remindersService: remindersService
            )
            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        }
    }
    .frame(minWidth: 280, minHeight: 42)
    .fixedSize(horizontal: true, vertical: true)
    .padding(.horizontal, 6)
    .padding(.vertical, 7)

    if showSubtasks, let activeId = timerService.activeReminderId {
        Divider()
            .background(isWhiteTheme ? Color.black.opacity(0.15) : Color.white.opacity(0.15))
        SubtasksPanelView(taskId: activeId, onClose: { showSubtasks = false })
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
.animation(.easeInOut(duration: 0.2), value: showSubtasks)
```

- [ ] **Step 5: Update PillControlsView to accept showSubtasks binding and add checklist button**

Replace the `PillControlsView` struct signature and add the button. Find `struct PillControlsView: View` and update:

```swift
struct PillControlsView: View {
    @Binding var isHovering: Bool
    @Binding var showSubtasks: Bool
    @ObservedObject var timerService: TimerService
    @ObservedObject var remindersService: RemindersService
    @ObservedObject var estimateStore: EstimateStore
    @AppStorage("appTheme") private var appTheme: AppTheme = .glass

    private var dividerColor: Color {
        appTheme == .white ? Color.black.opacity(0.2) : Color.white.opacity(0.2)
    }

    var body: some View {
        HStack(spacing: 12) {
            // EXIT FOCUS (Red)
            ControlButton(color: .red, icon: "xmark", help: "Exit Focus Mode") {
                timerService.isFocusMode = false
            }

            // PAUSE/RESUME (Yellow)
            ControlButton(
                color: .yellow,
                icon: timerService.state == .running ? "pause.fill" : "play.fill",
                help: timerService.state == .running ? "Pause" : "Resume"
            ) {
                if timerService.state == .running {
                    timerService.pauseTimer()
                } else {
                    timerService.resumeTimer()
                }
            }

            // COMPLETE / END BREAK (Green)
            if let activeId = timerService.activeReminderId,
               let task = remindersService.reminders.first(where: { $0.calendarItemIdentifier == activeId }) {
                ControlButton(color: .green, icon: "checkmark", help: "Complete Task") {
                    remindersService.toggleComplete(task)
                    timerService.stopTimer()
                }
            } else if timerService.isOnBreak {
                ControlButton(color: .green, icon: "checkmark", help: "End Break") {
                    timerService.endBreak()
                    timerService.isFocusMode = false
                }
            }

            Divider().frame(height: 16).background(dividerColor)

            // EXTEND TIME
            if timerService.timesUpTriggered {
                IconButton(icon: "clock.arrow.circlepath", color: .orange, help: "Extend Time") {
                    timerService.startOvertime()
                }
            }

            // SKIP / NEXT
            if timerService.isOnBreak {
                IconButton(icon: "forward.end.fill", color: .secondary, help: "Skip Break") {
                    timerService.endBreak()
                }
            } else {
                IconButton(icon: "forward.end.fill", color: .secondary, help: "Skip Task") {
                    if let activeId = timerService.activeReminderId,
                       let next = remindersService.getNextTask(after: activeId) {
                        let dur = estimateStore.getMetadata(for: next.calendarItemIdentifier)?.estimatedDuration ?? 1500
                        timerService.startTimer(reminderId: next.calendarItemIdentifier, duration: dur)
                    } else {
                        timerService.stopTimer()
                    }
                }
            }

            // BREAK / LIST
            if !timerService.isOnBreak {
                IconButton(icon: "cup.and.saucer.fill", color: .secondary, help: "Take a Break") {
                    timerService.startBreak(duration: 600)
                }
            } else {
                IconButton(icon: "square.grid.2x2", color: .secondary, help: "Open List") {
                    timerService.isFocusMode = false
                }
            }

            // SUBTASKS — only when a task is active (not on break)
            if timerService.activeReminderId != nil && !timerService.isOnBreak {
                IconButton(
                    icon: showSubtasks ? "checklist.checked" : "checklist",
                    color: showSubtasks ? .primary : .secondary,
                    help: showSubtasks ? "Hide Subtasks" : "Show Subtasks"
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSubtasks.toggle()
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 6: Add SubtasksPanelView struct**

Add this new struct at the bottom of `Sources/UI/FloatingPillView.swift`, before the closing:

```swift
struct SubtasksPanelView: View {
    let taskId: String
    let onClose: () -> Void

    @EnvironmentObject var subtaskStore: SubtaskStore
    @AppStorage("appTheme") private var appTheme: AppTheme = .glass

    @State private var newTitle: String = ""
    @FocusState private var isInputFocused: Bool

    private var isWhiteTheme: Bool { appTheme == .white }
    private var labelColor: Color { isWhiteTheme ? Color.black.opacity(0.45) : Color.white.opacity(0.4) }
    private var textColor: Color { isWhiteTheme ? Color.primary : Color.white.opacity(0.85) }
    private var completedColor: Color { isWhiteTheme ? Color.secondary : Color.white.opacity(0.35) }
    private var inputBackground: Color { isWhiteTheme ? Color.black.opacity(0.06) : Color.white.opacity(0.06) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subtasks")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(labelColor)
                .textCase(.uppercase)
                .tracking(0.5)

            let items = subtaskStore.subtasks(for: taskId)

            if !items.isEmpty {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Button {
                            subtaskStore.toggleSubtask(id: item.id, for: taskId)
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(item.isCompleted ? Color.green : Color.secondary.opacity(0.5),
                                                  lineWidth: 1.5)
                                    .frame(width: 14, height: 14)
                                if item.isCompleted {
                                    Circle().fill(Color.green).frame(width: 14, height: 14)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(.black.opacity(0.7))
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Text(item.title)
                            .font(.system(size: 12))
                            .foregroundColor(item.isCompleted ? completedColor : textColor)
                            .strikethrough(item.isCompleted)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            subtaskStore.deleteSubtask(id: item.id, for: taskId)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .opacity(0.6)
                    }
                }
            }

            // Add subtask input
            HStack(spacing: 6) {
                Text("+")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.5))

                TextField("Add subtask…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .focused($isInputFocused)
                    .onSubmit {
                        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        subtaskStore.addSubtask(title: trimmed, for: taskId)
                        newTitle = ""
                        isInputFocused = true
                    }
                    .onExitCommand {
                        onClose()
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(inputBackground)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 268)
    }
}
```

- [ ] **Step 7: Build**

```bash
swift build 2>&1 | tail -10
```

Expected: `Build complete!`

- [ ] **Step 8: Manual test**

Run the app. Enter focus mode on a task. Hover the pill — verify the checklist icon appears on the right of the controls. Click it — verify the pill expands with a "Subtasks" panel. Type a subtask name and press Enter — verify it appears with a circle checkbox. Click the checkbox — verify it turns green and text strikes through. Click checklist icon again — verify panel collapses.

- [ ] **Step 9: Commit**

```bash
git add Sources/UI/FloatingPillView.swift Sources/HelpyApp.swift
git commit -m "feat: add subtask panel to floating pill — toggle button in hover controls, app-only persistence"
```

---

## Task 8: Conditional Liquid Glass in IceGlass.swift

**Files:**
- Modify: `Sources/UI/IceGlass.swift`

Adds a `liquidGlassBackground(cornerRadius:)` free function that uses `glassEffect` on macOS 26+ and falls back to `IceGlassSurface` on older OS. This is the single source of truth used by Tasks 9 and 10.

- [ ] **Step 1: Add liquidGlassBackground function**

At the bottom of `Sources/UI/IceGlass.swift`, after the `IceGrainOverlay` struct, add:

```swift
/// Returns the appropriate glass background for the current OS.
/// On macOS 26+, uses Apple's native Liquid Glass via `.glassEffect()`.
/// On earlier macOS, falls back to the custom IceGlassSurface.
@ViewBuilder
func liquidGlassBackground(cornerRadius: CGFloat) -> some View {
    if #available(macOS 26.0, *) {
        Color.clear
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    } else {
        IceGlassSurface(cornerRadius: cornerRadius)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/IceGlass.swift
git commit -m "feat: add liquidGlassBackground helper — macOS 26+ native glass, older OS fallback"
```

---

## Task 9: Apply Liquid Glass to FloatingPillView background

**Files:**
- Modify: `Sources/UI/FloatingPillView.swift`

- [ ] **Step 1: Replace pill background with liquidGlassBackground on glass theme**

In `Sources/UI/FloatingPillView.swift`, find the `.background(...)` modifier on the `VStack` (the large ZStack containing `VisualEffectView`, `overlayBaseColor`, pulse effects, `WindowAccessor`, and progress bar).

Replace that entire `.background(...)` block with:

```swift
.background(
    ZStack(alignment: .bottom) {
        if appTheme == .glass {
            liquidGlassBackground(cornerRadius: 30)
        } else {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            overlayBaseColor
        }

        // Pulse Effect for Time's Up
        if timerService.timesUpTriggered {
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.red.opacity(0.5), lineWidth: 2)
                .background(Color.red.opacity(0.1))
                .opacity(isPulsing ? 1.0 : 0.0)
                .animation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { isPulsing = true }
                .onDisappear { isPulsing = false }
        }

        // Pulse Effect for Task Alerts
        if timerService.taskAlertTriggered {
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.cyan.opacity(0.8), lineWidth: 2)
                .background(Color.cyan.opacity(0.15))
                .opacity(isPulsing ? 1.0 : 0.0)
                .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { isPulsing = true }
                .onDisappear { isPulsing = false }
        }

        WindowAccessor(window: $window)

        // Bottom Progress Bar
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(progressTrackColor)
                    .frame(height: 3)

                Rectangle()
                    .fill(progressBarColor)
                    .frame(width: geo.size.width * CGFloat(progress), height: 3)
                    .shadow(color: progressBarColor.opacity(0.8), radius: 4, x: 0, y: 0)
            }
        }
        .frame(height: 3)
    }
)
```

Also update the `.overlay` that draws the border stroke — on macOS 26+ with glass theme, skip the custom stroke (glassEffect provides its own edge treatment):

Replace the existing `.overlay(RoundedRectangle(cornerRadius: 30).stroke(...))` with:

```swift
.overlay {
    if appTheme != .glass {
        RoundedRectangle(cornerRadius: 30)
            .stroke(
                LinearGradient(
                    colors: borderGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    } else if #available(macOS 26.0, *) {
        // glassEffect provides its own edge treatment — no manual stroke
    } else {
        IceGlassStroke(cornerRadius: 30)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/FloatingPillView.swift
git commit -m "feat: use native Liquid Glass for floating pill background on macOS 26+"
```

---

## Task 10: Apply Liquid Glass to ReminderRowView and GlassyBackground

**Files:**
- Modify: `Sources/UI/ReminderRowView.swift` — `glassOverlayBase`
- Modify: `Sources/UI/EmbeddedSettingsView.swift` — `GlassyBackground`

- [ ] **Step 1: Update glassOverlayBase in ReminderRowView**

Find the `glassOverlayBase(grainOpacity:)` function in `Sources/UI/ReminderRowView.swift` and replace it:

```swift
@ViewBuilder
private func glassOverlayBase(grainOpacity: Double) -> some View {
    if #available(macOS 26.0, *) {
        liquidGlassBackground(cornerRadius: 12)
    } else {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .withinWindow)
            GrainOverlay(opacity: grainOpacity)
            LinearGradient(
                colors: [.white.opacity(0.14), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
```

- [ ] **Step 2: Update GlassyBackground in EmbeddedSettingsView**

Find the `GlassyBackground` struct in `Sources/UI/EmbeddedSettingsView.swift` and update its `body`:

```swift
struct GlassyBackground: View {
    let theme: AppTheme

    var body: some View {
        Group {
            if theme == .glass {
                if #available(macOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.4))
                        RoundedRectangle(cornerRadius: 8).fill(.thinMaterial).opacity(0.5)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
            } else if theme == .white {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.black.opacity(0.16), Color.black.opacity(0.06)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            } else {
                // Dark theme
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.4))
                    RoundedRectangle(cornerRadius: 8).fill(.thinMaterial).opacity(0.5)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            }
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 4: Run all tests**

```bash
swift test 2>&1 | tail -15
```

Expected: all test suites pass.

- [ ] **Step 5: Manual test — glass theme**

Run the app. Set theme to Glass. Verify:
- Main panel task rows have native glass overlay on hover actions (macOS 26+) or fall back gracefully (macOS < 26)
- Settings controls use native glass or fallback correctly
- Floating pill uses native glass or fallback
- Dark and White themes are visually unchanged

- [ ] **Step 6: Commit**

```bash
git add Sources/UI/ReminderRowView.swift Sources/UI/EmbeddedSettingsView.swift
git commit -m "feat: apply native Liquid Glass to task row overlay and settings controls on macOS 26+"
```

---

## Post-implementation verification

- [ ] All 5 features work end-to-end: estimate input commits on Enter; pill/menu-bar toggle in settings; pill title renders without squish; subtask panel opens/closes from hover controls and persists across app launches; glass theme uses native glass on macOS 26+.
- [ ] `swift test` passes with no failures.
- [ ] Switching between Dark, White, and Glass themes produces correct visuals for each — no regressions.
- [ ] On macOS < 26: glass theme falls back to `IceGlassSurface` / `GrainOverlay`, app compiles and runs normally.
