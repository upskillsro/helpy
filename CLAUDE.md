# Helpy

A native macOS companion for Apple Reminders: a side strip on the desktop, a
floating focus pill (or menu bar timer), and local voice-to-task assistance.
Swift package, SwiftUI, macOS 14+ with macOS 26 Liquid Glass APIs behind
availability checks.

## Run, build, test

- `swift build` — compile.
- `swift test` — 98 XCTest cases, all should pass.
- `./package_dmg.sh` — release build, `.app` bundle, icons, signing, DMG.

**Changes are invisible until you repackage.** `swift build` alone does not
update `Helpy.app`, so anything you want to see on screen has to go through
`package_dmg.sh` (or `build_and_create_dmg.sh`).

## Conventions and gotchas

- **The coordinator owns windows.** `AppWindowCoordinator` raises, hides and
  styles every window including the pill. Views must never hide a window the
  coordinator later raises, and window transitions triggered by timer state are
  wired in `bindTimerService()`, not in a view's `.onChange` — a view can be
  unmounted, the coordinator never is.
- **`TimeTicker` is deliberately separate from `TimerService`** so a per-second
  tick does not invalidate the whole view tree. The App scene body does not
  observe it, which is why the menu bar title is refreshed from the coordinator.
- **Nothing in the pill animates in SwiftUI.** It sits on screen for whole work
  sessions, so anything that moves continuously must be Core Animation over a
  once-rasterised layer (`CAMarqueeText`, `RollingTimeText`). SwiftUI redraws
  the whole pill per frame; that cost 26% CPU while visible and another ~20%
  while the pill was *hidden*, because the coordinator keeps the hosting view
  alive. See `docs/pill-rendering.md`.
- Subtasks are app-only and never sync to Apple Reminders.
- Don't nest `glassEffect`. Use the shared Liquid Glass container modifier.
- Estimates and time spent live in `EstimateStore`, not in Reminders.

## Docs

`docs/ROOT.md` is the index. Read the doc for the area alongside the code.
