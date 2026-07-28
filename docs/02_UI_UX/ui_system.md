---
type: ui-ux
tags:
  - layer/ui
  - kind/deep-dive
  - concept/scaling
  - status/current
aliases:
  - "Responsive UI System"
created: 2026-05-18
updated: 2026-07-28
verified_against_code: 2026-07-28
status: current
---

# Responsive UI System

This document outlines the standard architecture for creating UI windows and menus in *Desolate Frontiers* that automatically adapt to Desktop, Mobile Landscape, and Mobile Portrait orientations.

## System Audit & Architecture (June 2026)

> [!NOTE]
> **Scaling refactor (June 2026).** Three overlapping scaling systems were collapsed into one. The old `TextScale` autoload (per-node font registration) and `DeviceStateManager.get_scaled_base_font_size()` / `get_font_multiplier()` (runtime font multipliers) were **deleted**. There is no per-node font scaling anywhere anymore. `UIScaleManager` is now the *only* scaling mechanism: it locks one fixed logical width per orientation via `content_scale_size`, and Godot's `canvas_items` stretch scales the entire frame — fonts, layout, icons — proportionally. Fonts use fixed logical sizes (in the theme or as plain `add_theme_font_size_override` constants); they are never multiplied at runtime.

After significant debugging of horizontal UI clipping on mobile devices, the UI architecture has been formalized into a strict top-down scaling system.

### How the UI Works (The "Single Source of Truth")

1. **Global Scaling Engine (`UIScaleManager`)**
   The `ui_scale_manager` autoload is the absolute authority on all UI sizing. It sets **`content_scale_factor`** — a pure float multiplier applied uniformly to the entire rendered canvas by Godot's `canvas_items` stretch system. Every Control, Label, and Button scales together with no per-node code. The factor is derived from the current window width divided by the target logical width for the active orientation.
   - **Portrait Target**: Fixed logical width of **800px**. The narrow logical width means everything (including text) is physically larger — no per-node font overrides required.
   - **Mobile Landscape Target**: Fixed logical width of **1600px**.
   - **Desktop Target**: **1920px**, optionally divided by the user's desktop UI-scale slider (`ui.scale`, default **1.0**) for a manual zoom. Narrow desktop windows (< 1200px) fall back to a 1200px target.

> [!NOTE]
> **Corrected 2026-07-28.** This line previously documented the `ui.scale` default as **1.4**. The real
> default is **1.0** (`Scripts/System/settings_manager.gd` `data["ui.scale"]`). The `1.4` comes from a
> dead fallback argument — `settings_menu.gd:247` reads `SM.get_value("ui.scale", 1.4)`, but the key is
> always present in `SettingsManager.data`, so that fallback can never fire. The code still carries the
> stale `1.4`; reconciling it is tracked in [TODO.md § Sprint 12](../TODO.md).

### Desktop scaling contract (and why fixed-width panels drift)

This is the single mechanism behind three separate open bugs (Sprint 12 · S12-1, S12-4, and the Sprint 11
UI-scale-slider item). Understand it before "fixing" any one of them in isolation.

`UIScaleManager._apply_logical_resolution()` does, in order:

```
target_w = 1920                       # desktop; 1200 if window < 1200px wide
target_w = target_w / _user_scale     # DESKTOP ONLY — _user_scale is `ui.scale`, clamped 0.5 … 4.0
factor   = physical_window_width / target_w
window.content_scale_factor = factor
```

The consequence that keeps biting: **the desktop zoom slider does not magnify the UI — it *shrinks the
logical viewport*.** At `ui.scale = 2.0` on a 1920px window the logical viewport is **960 logical px
wide**, not 1920. Therefore:

| Sizing style | Behaviour as `ui.scale` rises | Verdict |
|---|---|---|
| Fraction of viewport (`win.x * 0.75`) | Constant share of the screen | ✅ safe |
| Fixed logical px (`custom_minimum_size.x = 440`) | **Grows as a share of the screen** | ⚠️ drifts |
| Fixed logical px + `SIZE_EXPAND_FILL` on the other axis | Grows on one axis, full-bleed on the other | ❌ the S12-4 shape |

Mobile and portrait are immune because `_user_scale` is ignored there — the fixed per-orientation target
width is authoritative. **This is why a PC-only layout complaint can be real even when "Mac and mobile
look fine":** Mac at the default `ui.scale = 1.0` sits at the one point where fixed-logical-px sizing
happens to look correct, and `settings.cfg` is per-machine so the two desktops rarely share a value.

**Rules for new desktop UI:**
1. A panel that should occupy a *share* of the screen must be expressed as a fraction of
   `get_viewport_rect().size`, never as a fixed logical width.
2. A panel sized in fixed logical px must also carry a **max fraction** cap, or it will eventually eat
   the screen at high `ui.scale`.
3. Anything that spans an axis with `SIZE_EXPAND_FILL` inside a full-rect parent is **full-screen on that
   axis, at every scale** — say so deliberately or add a max size.

**Diagnostics that already exist — use them instead of guessing.** Both print unconditionally in exported
builds:
- `[UIScale] win=… factor=… target_w=… vp=… screen=… screen_size=…` — `UI_scale_manager.gd`, on every
  apply. Gives the window size, the chosen factor, the target width, and which monitor.
- `[LAYOUT-OVERFLOW] …` — `main_screen.gd::_diag_dump_offscreen()`, lists every Control crossing a
  horizontal screen edge.

### Never latch a value you derived by DIVIDING by the scale

`UIScaleManager.get_logical_safe_margins()` converts the platform's **physical** safe-area inset to
logical px by dividing by `content_scale_factor`. That divisor is the one number that is *not*
trustworthy during an exported/Steam boot: the window can report a bogus size for a frame, pinning
the factor at the `_MIN_SAFE_FACTOR` (**0.05**) floor. A ~47px macOS menu-bar/notch inset then
converts to **~940 logical px**.

That alone is survivable — the poll re-applies a good factor a frame later. What is *not* survivable
is a consumer that **writes the bad value somewhere sticky and never recomputes**:

> **Case study — the "blank screen, only the background art" Steam bug (2026-07-28).**
> `UserInfoDisplay._update_safe_margins()` writes the inset into its panel stylebox
> (`content_margin_top = 4.0 + safe.position.y`), which feeds the bar's **minimum height**. Its only
> re-trigger was `NOTIFICATION_RESIZED`, and `_on_ui_scale_changed()` — the one handler that fires on
> exactly the event that invalidates the value — was an empty `pass`. So a boot-time
> `content_margin_top ≈ 944` was latched forever. The top bar's minimum height then exceeded the
> whole viewport, `MainContent` (and with it `MapDisplay`) was pushed below the screen at **zero
> height**, and the only thing left rendering was the top bar's own darkened Oori tile — a
> full-screen background pattern and nothing else.
>
> **Why it was export/Steam-only and unreproducible in the editor:** the editor hands the window a
> valid size on frame 1, so the divisor is never pathological. This is the same near-zero-boot-size
> family as the previously-fixed blank *login* screen; `UIScaleManager` was hardened against it
> (re-apply across the first frames + a 0.5s settle + a per-frame poll) but **its consumers were
> not**.
>
> **Log signature** (`user://logs/godot*.log`): a healthy run shows
> `[RESIZE] map_rect=[P: (0.0, 80.0), S: (2133.0, 1056.0)]` — y = top-bar height, full size. The
> broken state shows `map_rect=[P: (0.0, 1610.136), S: (2133.0, 0.0)]` — **zero height, y far below
> the viewport**. `main_screen.gd::_diag_dump_map_ancestor_sizes()` now dumps the ancestor chain with
> each control's `combined_minimum_size` when that degenerate rect survives a retry, so the culprit
> can be named from a log alone.

**Rules:**
1. `get_logical_safe_margins()` returns **zero margins until `is_scale_settled()`** and clamps every
   inset to ≤ 20 % of the logical viewport. A safe area is a notch, never a third of the screen.
2. **Because of rule 1, every consumer MUST re-query on `UIScaleManager.scale_changed`** — otherwise
   it latches the zero instead of the giant. Most already do via their own `size_changed` hooks
   (`map_overlay_settings_panel`, `menu_manager`); `UserInfoDisplay` now does too.
3. Never write a scale-derived value into a `custom_minimum_size` or stylebox `content_margin`
   without a recompute path. Minimum sizes propagate *upward* through every container above them.

> [!WARNING]
> **Known violation of the physical-vs-logical rule below.** `Scripts/System/device_state_manager.gd`
> derives the layout mode (and the `screen_size` it broadcasts on `layout_mode_changed`) from
> `DisplayServer.window_get_size()` — **physical pixels**. Meanwhile `main_screen.gd::_is_portrait()` and
> `map_overlay_settings_panel.gd::_is_portrait()` answer the same question from
> `get_viewport_rect().size` — **logical pixels**. They agree today only because `content_scale_factor` is
> a uniform multiplier. Do not add a fourth source of truth; consolidating these is tracked in
> [TODO.md § Sprint 12 · S12-4](../TODO.md).

### 2. Container Fluidity (Breaking the "Ghost" Constraints)
   The primary cause of UI clipping was rigid `custom_minimum_size` constraints buried deep within nested containers. When the global scale zoomed in, these rigid containers refused to shrink, pushing the UI off the edge of the screen.
   - **Grid Containers**: Grids MUST NOT calculate their column counts based on their parent's width if the parent is an expanding container (this causes an infinite loop). Always use `get_viewport_rect().size.x` for available width calculations.
   - **Labels**: Long labels in `HBoxContainers` force minimum widths. All text-heavy labels must have `autowrap_mode = TextServer.AUTOWRAP_WORD_SMART` AND `size_flags_horizontal = Control.SIZE_EXPAND_FILL` to allow them to shrink below their unwrapped text size.

---

## Core Components

### 1. `UIScaleManager`
The autoload that forces the viewport logical resolution. Automatically runs on boot to lock the width to the appropriate target for the current hardware orientation.

### 2. `MenuManager`
The central hub for all full-screen UI navigation. It manages the lifecycle of menus, ensures only one "active" menu is visible, and handles directional sliding transitions.

### 3. `SafeAreaHandler`
A script attached to root `MarginContainers` that automatically applies margins based on the `UIScaleManager`'s logical safe area calculations. This prevents UI from being clipped by "notches" or "islands".

### 4. `ResponsiveModalPanel`
Any UI popup that should look like a floating menu on Desktop but seamlessly transition to full screen on Mobile Portrait should extend this class. It inherits from `CanvasLayer` to guarantee perfectly centered coordinates across all aspect ratios.

---

## Mobile-First Design Patterns

To ensure a premium feel on mobile, adhere to these standards:

### 1. Touch Targets
- All interactive buttons should have a minimum logical height of **70px** in portrait and **50px** in landscape.
- Use `MenuBase.style_convoy_nav_button(button)` to apply standardized, touch-friendly styling to auxiliary buttons.

### 2. Logical Scaling vs. Physical Pixels
- **Rule**: Never use `DisplayServer.window_get_size()` for layout math.
- **Rule**: Never multiply a font size at runtime (no `base * multiplier`, no `get_scaled_base_font_size()`, no `TextScale` — all removed). Set a fixed logical size and let the canvas do the work.
- The `UIScaleManager` handles the "zoom" at the viewport level. If text is too small, check that the logical resolution (e.g., 800px) is correctly set for the orientation, rather than boosting the font.

### 3. Safe Zones & Margins
- Use **14px** as the standard side-margin for portrait layouts. This is automatically applied by `MenuBase._apply_standard_margins()`.
- Top banners should use `MenuBase.setup_convoy_top_banner()` to ensure consistent depth and safe-area compatibility.

---

## Troubleshooting Checklist

If your UI is clipping off the side of the screen on mobile:
1. **Check for Local Font Boosts**: Search your script for any font size multiplied by a variable (e.g. a local `_get_font_size(base)` helper that applies a per-orientation boost). Remove the boost and rely on the global canvas scale.
2. **Check Grid Columns**: Ensure `GridContainers` are not calculating dynamic columns based on an expanding parent.
3. **Check Label Wrapping**: Ensure long text blocks have `SIZE_EXPAND_FILL`.
4. **Check HBoxes**: Check any `HBoxContainer` or `HFlowContainer` for elements with large `custom_minimum_size.x`.
