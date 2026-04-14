# Floating Pill Subtasks

Last Updated: 2026-04-14

## Purpose

Keep the floating pill's subtask affordance visually consistent with the glass theme while preserving the separate floating panel behavior used for keyboard input and click handling.

## Architecture

- `FloatingPillView` owns the checklist toggle in the hover controls.
- `AppWindowCoordinator` presents `SubtasksPanelView` in a borderless child `NSPanel` positioned under the pill.
- `SubtasksPanelView` is responsible only for rendering the panel UI and calling `SubtaskStore` actions.
- `LiquidGlassContainerModifier` centralizes the container-level native glass treatment shared by the pill and the subtask panel.

## Liquid Glass Rules

- On the glass theme, both the pill and the subtask panel use container-level `glassEffect` so child foreground colors adapt to sampled content behind the window.
- The subtask panel uses the interactive glass variant because it contains buttons and a text field.
- Inner chrome stays light: no extra frosted card stacks inside the panel, only a subtle bordered input surface for the add-subtask field.
- White and dark themes keep their existing fallback materials and explicit borders.

## Files

- `Sources/UI/FloatingPillView.swift`
- `Sources/UI/SubtasksPanelView.swift`
- `Sources/UI/Shared/LiquidGlassContainerModifier.swift`
- `Sources/Services/AppWindowCoordinator.swift`
