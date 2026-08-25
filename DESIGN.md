# Helpy — Design

One theme. It follows the system light/dark setting; there is no theme picker
and no accent picker. Every colour, radius, and font in the app comes from
`Sources/UI/Theme.swift` — if a view hard-codes a hex or a `.system(size:)`,
that is a bug, not a style choice.

## Direction

**Sky** (light) and **Midnight** (dark). Flat surfaces, one saturated blue, and
a lot of white space. No transparency, no Liquid Glass, no `NSVisualEffectView`,
no material blurs, no drop shadows on content. Depth comes from a 1px border and
a hover fill.

Typeface is **Inter**, bundled in `Sources/Resources/Fonts` and registered at
launch by `HelpyFonts.register()`. Call it as `.inter(size:weight:)`, never
`.system(size:)`.

## The mark

The white cat is the brand. It appears:

- in the menu bar (`MenuBarIcon.png`, **not** a template image)
- on the sidebar header, the menu bar dropdown header, and the settings header
  (`HelpyMark`)

It never appears in the floating pill.

Menu bar note: because the icon is deliberately not a template, macOS does not
re-ink it black on a light menu bar. That is the intended mark at the cost of
contrast on a light wallpaper.

The app icon is the blue gradient icon (`AppIcon.icns`), rendered on Apple's
824/1024 macOS icon grid.

## Tokens

Defined once in `HelpyPalette` (`.light` / `.dark`, selected by
`HelpyPalette.forScheme(colorScheme)`). Views hold
`private var t: HelpyPalette { .forScheme(colorScheme) }` and read from it. No
view takes a `theme:` parameter.

| Group | Tokens |
|---|---|
| Ground | `canvas`, `surface`, `surfaceHover`, `surfaceActive`, `surfaceActiveBorder`, `line` |
| Text | `ink`, `ink2`, `muted`, `muted2` |
| Accent | `accent`, `headerGradient`, `onAccent` |
| Progress | `railTrack`, `railFill` |
| State | `warm` (overtime / break), `hot` (time's up / high priority), `success` |
| Chips | `chipFill`, `chipText`, `chipHotFill`, `chipHotText` |
| Inputs | `checkBorder`, `fieldFill`, `fieldBorder`, `placeholder` |
| Controls | `controlIcon`, `controlHoverFill`, `dangerHoverFill`, `dangerHoverIcon`, `goHoverFill`, `goHoverIcon` |
| Detached | `pillFill`, `pillBorder`, `panelFill`, `panelBorder` |

Radii live in `HelpyMetrics`: header 20, card 14, row 12, field 12, button 14,
pill 22, panel 18.

## Header (version B)

The blue gradient runs full-bleed to the window edges and sweeps into rounded
**bottom** corners — square at the top, `headerCornerRadius` at the bottom.
`HelpyHeaderBackground(palette:)` + `BottomRoundedRectangle` own this shape. It
is used by the sidebar header, the menu bar dropdown, and the settings header,
and it is the only place the three-stop gradient appears.

Two layout rules keep it honest, both learned the hard way:

- The decorative glow is an **overlay** on the gradient, never a ZStack sibling.
  As a sibling its fixed 150pt circle set the whole background's height, so the
  gradient rendered 150pt tall centred on a 93pt header and spilled ~28pt past
  the bottom edge — swallowing the top of the first task card and putting the
  rounded sweep in the wrong place. An overlay cannot feed back into layout.
- The gradient bleeds **upward only**, via `.ignoresSafeArea(edges: .top)` on
  the background, so it reaches the window's top edge behind the traffic lights.
  The bottom edge must stay exactly at the header's frame.

## Floating pill

- White (`pillFill`), never blue. 1px `pillBorder`, radius 22.
- **No cat**, and **no state dot**.
- A long task title scrolls as a marquee (`MarqueeText`) — one Core Animation
  `.offset` with `repeatForever(autoreverses:)`, not a per-frame timer. The pill
  is on screen for whole sessions, so a display-link animation is not affordable.
- A 3pt progress rail runs along the bottom: `railFill` normally, `warm` on
  break/overtime, `warm`→`hot` when time is up.
- Time's up pulses the border in `hot`; a task alert pulses it in `accent`.
- Never draw a shadow inside the pill window — see the comment in
  `FloatingPillView.swift`.

## Controls

One control language everywhere: `PillControlButton`, 28×28, radius 9,
monochrome icon in `controlIcon`, tinted only on hover
(`neutral` / `danger` / `go`). The floating pill, the menu bar dropdown, the
active-task card, and the task-row hover actions all use it — the old
red/yellow/green traffic lights are gone.

## Rows

Flat `surface` fill, 1px `line` border, radius 12, no shadow. Hover swaps to
`surfaceHover` + `surfaceActiveBorder`. A priority task gets a 3pt colour bar on
its leading edge; that bar and the flag chip are the only colour in the list.
Checkboxes are circles — filled `accent` (or the priority colour) with a white
checkmark when done.

## Motion

Short and cheap. `.easeOut(duration: 0.12–0.18)` for hover and selection,
`.snappy` + `.contentTransition(.numericText())` for the timer digits,
`.easeInOut(0.75).repeatForever` for alert pulses. Nothing spins, nothing
bounces.

## Packaging

Code changes are invisible until the app is repackaged:

```
./package_dmg.sh
```

`AppIcon.icns` is written to `CustomIcons/`, `Resources/`, and
`Sources/Resources/` from one generated source so the script's preferred-source
branch and its regenerate branch cannot disagree.
