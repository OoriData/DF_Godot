---
type: technical
tags:
  - layer/autoload
  - kind/deep-dive
  - concept/scaling
  - concept/persistence
  - status/current
aliases:
  - "User Settings & Preferences"
created: 2026-05-19
updated: 2026-08-04
verified_against_code: 2026-08-04
status: current
---

# User Settings & Preferences

The Settings system acts as the local storage mechanism for non-gameplay configurations, persisting visual, audio, and accessibility choices.

## Core Features
1. **SettingsManager**:
   - Reads and writes to `user://settings.cfg`.
   - Tracks audio levels, UI interaction flags, tutorial completions, and cargo sorting metrics.
2. **Scale Normalization**:
   - `UI_scale_manager` binds to the `ui.scale` setting (desktop manual zoom). It sets `content_scale_factor` — a pure multiplier that scales the entire canvas (fonts, layout, icons) together. There is no separate font-scaling system.

## Keys and defaults

Audited against `SettingsManager.data` on 2026-07-28. **`data` is the authoritative default list** — a
`get_value(key, fallback)` fallback for a key that appears here can never fire.

| Key | Default | Runtime side effect on save |
|---|---|---|
| `ui.scale` | `1.0` | `ui_scale_manager.set_global_ui_scale()` — desktop manual zoom only. **Bounded `0.75 … 1.30`** (`MIN_USER_SCALE` / `MAX_USER_SCALE`); see the note below |
| `ui.menu_open_ratio` | `0.5` | read by `main_screen.gd` when (re)laying out the menu sheet. **A lerp position between the `UITheme.MENU_RATIO_*` band ends, NOT a screen fraction** |
| `ui.cargo_sort_metric` | `0` | read by `vendor_trade_panel.gd`; index into `CargoSorter.SortMetric` |
| `access.high_contrast` | `false` | — |
| `display.fullscreen` | `false` | `DisplayServer.window_set_mode()` **+ deferred `reapply_scale()`** |
| `controls.invert_pan` | `false` | read by `main_screen.gd` |
| `controls.invert_zoom` | `false` | read by `main_screen.gd` |
| `map.*` (6 keys) | `false` | mirrored by `MapSettingsService` / the overlay options panel |

> [!NOTE]
> **Resolved 2026-07-31.** `settings_menu.gd` previously read `SM.get_value("ui.scale", 1.4)`; that `1.4`
> was **dead** (the key always exists in `data`, so the effective default was always `1.0`) and is now
> written as `1.0`. Reconciled alongside **S13-2**.

> [!IMPORTANT]
> **`ui.scale` bounds, and why a stored value may not be the one in force (2026-08-04, S13-23).**
> The old `0.5 … 4.0` clamp is gone. `ui_scale_manager.get_effective_max_scale()` is now the single
> source for **both** the settings slider's range and `set_global_ui_scale()`'s clamp — deriving them
> independently is what allowed a stored `3.65` to run while the slider displayed a lower ceiling.
> - Product bounds: `MIN_USER_SCALE = 0.75`, `MAX_USER_SCALE = 1.30`.
> - `get_max_safe_scale()` binds *below* the cap on narrow windows (≈`1.04` under 1200px wide).
> - A value outside the **product** bounds is normalised once on the next Settings open. It is
>   deliberately **not** normalised to the window-derived ceiling — that would destroy a legitimate
>   `1.30` preference merely because Settings was opened on a small window.
>
> **The two sliders carry no numeric readout.** One existed briefly on 2026-08-04 as a calibration aid
> and was removed once the bands were set. Full rationale and the band table:
> [ui_system § `ui.menu_open_ratio` is a lerp position](../02_UI_UX/ui_system.md#uimenu_open_ratio-is-a-lerp-position-not-a-screen-fraction).

## Display & fullscreen

`display.fullscreen` is the **only** fullscreen *setting* in the project — every control below writes to
it rather than touching `DisplayServer`. Verified 2026-07-28, **updated 2026-07-31 for S12-6**:

- **Two entry points, one setting:**
  - The `FullscreenCheck` checkbox in the settings menu (`settings_menu.gd:4`, `:247`, `:258`).
  - **A keyboard shortcut (added 2026-07-31, S12-6):** `F11` on all platforms, `Alt+Enter` /
    `Alt+KP_Enter` on Windows/Linux, and `Cmd+Ctrl+F` on macOS. Handled by
    `SettingsManager._unhandled_key_input()` → `_is_fullscreen_shortcut()` → `toggle_fullscreen()`.
- **The shortcut is *not* an InputMap action, and `project.godot` still has no `[input]` section.** The
  keys are matched directly on the `InputEventKey`. This is deliberate — hand-authored `InputEventKey`
  literals in `project.godot` are fragile and the binding set is platform-conditional — but it does mean
  **the shortcut will not appear in the editor's Input Map panel**, so grep `_is_fullscreen_shortcut`
  rather than looking there.
- **`SettingsManager` runs at `PROCESS_MODE_ALWAYS`** so the shortcut still works pre-login, where
  `GameScreenManager` holds `get_tree().paused = true`. It is handled on that autoload rather than
  `main_screen.gd` because MainScreen is `PROCESS_MODE_DISABLED` for the whole of login.
- **The checkbox tracks external changes.** `settings_menu.gd` subscribes to
  `SettingsManager.setting_changed` and applies them with `set_pressed_no_signal()`, so a shortcut press
  while the menu is open updates the checkbox without re-entering `toggled` → `set_and_save`.
- The mode used is `DisplayServer.WINDOW_MODE_FULLSCREEN` (**exclusive**), not the borderless variant.
- **Anything that changes the window mode must go through this setting, not `DisplayServer` directly.**
  The logical UI scale is derived from window size (`factor = window_width / target_width`), so
  `_apply_runtime_side_effect()` calls `ui_scale_manager.reapply_scale()` **deferred**, after the new
  geometry settles. Bypassing it leaves the UI at the previous mode's scale and laid out offset —
  the exact failure mode that comment exists to prevent (`settings_manager.gd:76-79`).

> [!NOTE]
> Scaling statements here mirror
> [AI_ONBOARDING § The Law of Logical Pixels](../AI_ONBOARDING.md) — that page wins on conflict.

## Key Files
- **Settings Store**: `Scripts/System/settings_manager.gd`
- **UI Scalar**: `Scripts/UI/UI_scale_manager.gd`
- **Settings UI**: `Scripts/Menus/settings_menu.gd` (opened outside `MenuManager`, on a `CanvasLayer` at
  layer 100 — a known lifecycle inconsistency, see [TODO.md § Tech Debt](../TODO.md))

## Connected Systems
- [Diagnostics & Settings](Diagnostics.md)
- [Responsive UI / Scaling](../02_UI_UX/ui_system.md) — how `ui.scale` interacts with logical pixel sizing
