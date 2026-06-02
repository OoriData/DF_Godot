---
type: ui-ux
tags:
  - ui
  - ux
  - codex/ui_system
aliases:
  - "Responsive UI System"
created: 2026-05-18
---

# Responsive UI System

This document outlines the standard architecture for creating UI windows and menus in *Desolate Frontiers* that automatically adapt to Desktop, Mobile Landscape, and Mobile Portrait orientations.

## System Audit & Architecture (June 2026)

> [!NOTE]
> **Scaling refactor (June 2026).** Three overlapping scaling systems were collapsed into one. The old `TextScale` autoload (per-node font registration) and `DeviceStateManager.get_scaled_base_font_size()` / `get_font_multiplier()` (runtime font multipliers) were **deleted**. There is no per-node font scaling anywhere anymore. `UIScaleManager` is now the *only* scaling mechanism: it locks one fixed logical width per orientation via `content_scale_size`, and Godot's `canvas_items` stretch scales the entire frame — fonts, layout, icons — proportionally. Fonts use fixed logical sizes (in the theme or as plain `add_theme_font_size_override` constants); they are never multiplied at runtime.

After significant debugging of horizontal UI clipping on mobile devices, the UI architecture has been formalized into a strict top-down scaling system.

### How the UI Works (The "Single Source of Truth")

1. **Global Scaling Engine (`UIScaleManager`)**
   The `ui_scale_manager` autoload is the absolute authority on screen sizing. It does **no** manual multiplier math on individual nodes; it leverages Godot 4's native `content_scale_size` combined with Project Settings (`stretch/mode = canvas_items` and `stretch/aspect = expand`). It picks one **fixed** logical width for the current orientation and sets it once; the engine stretches the whole canvas to the physical window.
   - **Portrait Target**: Fixed logical width of **800px**. The narrow logical width means everything (including text) is physically larger — no per-node font overrides required.
   - **Mobile Landscape Target**: Fixed logical width of **1600px**.
   - **Desktop Target**: **1920px**, optionally divided by the user's desktop UI-scale slider (`ui.scale`, default 1.4) for a manual zoom. Narrow desktop windows (< 1200px) fall back to a 1200px target.

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
