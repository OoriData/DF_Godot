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
updated: 2026-07-29
verified_against_code: 2026-07-28
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
| `ui.scale` | `1.0` | `ui_scale_manager.set_global_ui_scale()` — desktop manual zoom only |
| `ui.menu_open_ratio` | `0.5` | read by `main_screen.gd` when (re)laying out the menu sheet |
| `ui.cargo_sort_metric` | `0` | read by `vendor_trade_panel.gd`; index into `CargoSorter.SortMetric` |
| `access.high_contrast` | `false` | — |
| `display.fullscreen` | `false` | `DisplayServer.window_set_mode()` **+ deferred `reapply_scale()`** |
| `controls.invert_pan` | `false` | read by `main_screen.gd` |
| `controls.invert_zoom` | `false` | read by `main_screen.gd` |
| `map.*` (6 keys) | `false` | mirrored by `MapSettingsService` / the overlay options panel |

> [!NOTE]
> `settings_menu.gd:247` reads `SM.get_value("ui.scale", 1.4)`. That `1.4` is **dead** — the key always
> exists in `data`, so the effective default is `1.0`. Reconciling it is tracked in
> [TODO.md § Sprint 12](../TODO.md).

## Display & fullscreen

`display.fullscreen` is the **only** fullscreen control in the project. Verified 2026-07-28:

- **There is no keyboard shortcut.** `project.godot` has no `[input]` section at all, so no custom action
  exists, and no `KEY_F11` / `KEY_ESCAPE` handler exists anywhere in `Scripts/`. The single entry point
  is the `FullscreenCheck` checkbox in the settings menu (`settings_menu.gd:4`, `:247`, `:258`).
  Adding a shortcut is tracked as **TODO Sprint 12 · S12-6**.
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
