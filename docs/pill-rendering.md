# Pill rendering

## Purpose

Why the floating pill's two moving parts — the scrolling task title and the
rolling clock — are drawn by Core Animation instead of SwiftUI, and what was
measured to get there. Read this before "simplifying" either one back into
plain SwiftUI.

## Context

The pill is a 288x44 borderless panel. In August 2026 it measured **~26% CPU
for as long as any task was active**, on a 120Hz built-in display, with no
other Helpy window on screen.

`sample` showed the main thread spending ~35% of its time in CoreAnimation
transaction flush: `CALayer _display` → `CGDrawingLayer.draw` → glyph
rasterisation (`CGGlyphBitmapCreateWithPathAndDilation`) and a CPU Gaussian
blur (`RB::CGContext::apply_blur` → `vImageSepConvolve_ARGB8888`), plus ~500
samples blocked in `wait_for_synchronize` waiting on WindowServer for a
backing store. In other words the whole pill was being re-rasterised every
display frame.

Two things caused it, and each one on its own was enough to do it. Measured in
a standalone rig that reproduced the pill, each variant timed on its own:

| title | clock | CPU |
| --- | --- | --- |
| SwiftUI scroll | `.numericText` roll every second | 11.8% |
| SwiftUI scroll | no roll | 8.3% |
| no scroll | `.numericText` roll every second | 12.2% |
| no scroll | no roll | **0.2%** |
| Core Animation scroll | Core Animation roll | **0.2%** |

The rig runs roughly half of what Activity Monitor reports for the real app,
which used a custom font and a larger view tree.

### What did not work

These were each tried and measured before landing on Core Animation. None of
them helped, and two made it worse:

- **Swapping the marquee's `.mask()` for an overlay gradient.** 15.1% vs 14.3%.
  The mask was not the problem; the per-frame glyph work was.
- **Shortening the clock's animation** from `.snappy` to `.easeInOut(0.18)`.
  14.8% vs 14.3%. The cost tracks how *often* the transition fires, not how
  long it runs.
- **Giving the clock its own layer with `.drawingGroup()`.** 16.7%, worse. The
  extra offscreen composite costs more than it saves.
- **Shrinking what repaints.** The clock *alone* in a 60x30 window, where
  nothing else exists to repaint, still measured 13.0% — the same as inside the
  full pill (13.0%). The pill's area was never the cost; five digits were.
- **Capping the frame rate.** The display is 120Hz ProMotion, but SwiftUI
  exposes no frame-rate cap on macOS, and halving it would still leave ~6.5%.

## Architecture

Both components live in `Sources/UI/Components/` and are `NSViewRepresentable`
wrappers over a `CALayer`. The shared principle: **rasterise the glyphs once,
then only ever animate a layer property that the render server interpolates.**
The app does no work per frame.

### `CAMarqueeText`

Draws the title into one bitmap, then animates `position.x` with a
`repeatForever`, autoreversing `CABasicAnimation`. The edge fade is a
`CAGradientLayer` used as the layer's mask, set once.

`MarqueeText` in `FloatingPillComponents.swift` is now a thin SwiftUI wrapper
over it, so `PillTitleView` and its `.equatable()` are unchanged.

### `RollingTimeText`

Replaces `.contentTransition(.numericText)` on `PillTimerDisplay`.

Every glyph 0-9 is drawn once into a single tall strip image. Each digit
position is a layer showing a one-row window onto that strip via
`contentsRect`; a digit change animates `contentsRect`, which the render server
interpolates. No glyph is ever rasterised again, so the roll costs the same
whether it fires once a minute or once a second.

The strip is **two descending 9…0 cycles (20 rows)**, so row `r` shows
`9 - (r % 10)`. Descending rows make travel direction map onto counting
direction: down the strip decrements, up increments. Each roll takes whichever
direction is the shorter travel, so a countdown crossing 0 → 9 moves one row
rather than spinning nine, and a stopwatch crossing 9 → 0 does the same. Two
cycles give enough runway to cross a wrap in one continuous move, after which
the layer re-seats onto the identical row a cycle away — invisible, because both
rows show the same glyph.

Digits all share one cell width, which is what `.monospacedDigit()` did before.
Non-digit characters (`:` and overtime's leading `+`) are static bitmaps. A
change of *shape* — `MM:SS` → `HH:MM:SS`, or overtime appearing — rebuilds the
slots; a change of digits only rolls them.

### The pill keeps rendering while hidden

`AppWindowCoordinator` hides the pill with `orderOut`, never `close`, and keeps
the panel and its `NSHostingView` alive to reuse them. A SwiftUI animation in
that view tree therefore keeps running with the window off screen, and SwiftUI
re-evaluates and diffs the display list every display cycle for a window nobody
can see.

That is why Helpy measured ~20% CPU **with the timer off and only the list tab
open**: the old `MarqueeText`'s `repeatForever` was still scrolling the hidden
pill's title. `sample` showed the per-cycle
`NSDisplayCycleFlush` -> `NSHostingView.layout()` ->
`ViewGraphRootValueUpdater.render` path doing display-list merges
(`discardContainingClips`, `RBPathBoundingRect`) with no glyph rasterisation —
the tell-tale shape of a window being rendered but never drawn.

Core Animation fixes this for free: the animation lives on a layer the render
server owns, and an off-screen window's layers cost this process nothing. After
the rewrite the same idle state measures **0.0%**.

### Hover tracking

`AppWindowCoordinator.startPillHoverTracking` watches `.mouseMoved` globally,
which fires hundreds of times a second while the cursor travels. It used to
spawn a `Task { @MainActor }` per event. AppKit already delivers these on the
main thread, so it now uses `MainActor.assumeIsolated`.

## Decisions

- 2026-09-01 — Helpy's ~20% idle CPU (timer off, list tab only) was the *hidden*
  pill: `orderOut` keeps the hosting view alive, so the SwiftUI marquee kept
  animating a window nobody could see. The Core Animation rewrite fixed it
  without any change to window handling. Measured 0.0% idle afterwards.
- 2026-09-01 — The pill's clock roll is Core Animation (`RollingTimeText`), not
  `.contentTransition(.numericText)`. The SwiftUI version cost ~13% CPU on its
  own and could not be made cheaper by shrinking the repaint area, isolating the
  layer, or shortening the animation, because the cost is per-frame glyph
  rasterisation plus a blur. Measured replacement: ~0.2%, with the roll still
  firing every second.
- 2026-09-01 — The pill's title scroll is Core Animation (`CAMarqueeText`), not
  a SwiftUI `.offset`. The old code's comment claimed the `repeatForever`
  offset was "Core Animation-driven, not a per-frame timer"; that was not true,
  because a clipped and masked subtree cannot be handed to the render server as
  a layer transform. It cost ~8%.
- 2026-09-01 — Pill CPU went from ~26% to ~1% with no feature removed. The roll
  and the scroll both still happen, every second, exactly as before.
