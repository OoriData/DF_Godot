# Responsive UI System

This document outlines the standard architecture for creating UI windows and menus in *Desolate Frontiers* that automatically adapt to Desktop, Mobile Landscape, and Mobile Portrait orientations.

## System Audit & Architecture (April 2026)

After significant debugging of horizontal UI clipping on mobile devices, the UI architecture has been formalized into a strict top-down scaling system.

### How the UI Works (The "Single Source of Truth")

1. **Global Scaling Engine (`UIScaleManager`)**
   The `ui_scale_manager` autoload is the absolute authority on screen sizing. Instead of relying on manual multiplier math, it leverages Godot 4's native `content_scale_size` combined with Project Settings (`stretch/mode = canvas_items` and `stretch/aspect = expand`).
   - **Portrait Target**: Forces a logical width of **800px**. This ensures the layout is "zoomed in" and text remains perfectly readable without requiring manual font size overrides.
   - **Landscape/Desktop Targets**: Forces logical widths of **1600px** and **1920px** respectively to provide wider views.

2. **Container Fluidity (Breaking the "Ghost" Constraints)**
   The primary cause of UI clipping was rigid `custom_minimum_size` constraints buried deep within nested containers. When the global scale zoomed in, these rigid containers refused to shrink, pushing the UI off the edge of the screen.
   - **Grid Containers**: Grids MUST NOT calculate their column counts based on their parent's width if the parent is an expanding container (this causes an infinite loop). Always use `get_viewport_rect().size.x` for available width calculations.
   - **Labels**: Long labels in `HBoxContainers` force minimum widths. All text-heavy labels must have `autowrap_mode = TextServer.AUTOWRAP_WORD_SMART` AND `size_flags_horizontal = Control.SIZE_EXPAND_FILL` to allow them to shrink below their unwrapped text size.

### What Doesn't Work (Anti-Patterns to Avoid)

- ❌ **Local Font Boosts**: DO NOT multiply font sizes in local scripts (e.g., `font_size * 3.2`). Because the global scaling engine already zooms the viewport to 800px, multiplying the font size locally creates comically huge text that explodes the layout containers horizontally.
- ❌ **`DisplayServer.window_get_size()` for Layout**: This returns physical hardware pixels. Because we use logical scaling (`content_scale_size`), physical pixels are meaningless for UI math. **Rule**: ALWAYS use `get_viewport_rect().size`.
- ❌ **Hardcoded Container Minimums**: Avoid setting `custom_minimum_size.x` greater than `0` on high-level containers. Let the children dictate size fluidly.

### What We Should Improve

1. **Unify Theme Inheritance**: Instead of manually styling buttons and panels via script in every menu (e.g., `StyleBoxFlat.new()`), we should migrate all Oori-style visual tokens into a single global Godot Theme resource (`.tres`).
2. **Remove `DeviceStateManager` Redundancy**: `DeviceStateManager` currently handles some font scaling multipliers (`font_multiplier_portrait`). These should ideally be phased out in favor of the global viewport scaling provided by `UIScaleManager`, simplifying the pipeline.
3. **Safe Area Management**: The `SafeAreaHandler` currently calculates padding in physical pixels, which conflicts with our logical viewport scale. It needs to be refactored to apply margins dynamically in logical space to prevent notch clipping on newer iPhones/Androids.

---

## Core Components

To build a responsive modal/window, rely on the following components:

### 1. `UIScaleManager`
The autoload that forces the viewport logical resolution. Automatically runs on boot to lock the width to the appropriate target for the current hardware orientation.

### 2. `ResponsiveModalPanel`
Any UI popup that should look like a floating menu on Desktop but seamlessly transition to full screen on Mobile Portrait should extend this class. It inherits from `CanvasLayer` to guarantee perfectly centered coordinates across all aspect ratios without OS Window shifting bugs!

**How to use:**
1. In your script: `extends ResponsiveModalPanel`.
2. Do not write your own `.popup()` logic. Call `open_modal()` when you want the menu to appear, and `close_modal()` to hide it.
3. Call `super._ready()` inside your `_ready()` function!
4. Instead of using `add_child(my_vbox)`, you MUST use `add_content(my_vbox)`! Because this panel is actually a `CanvasLayer`, doing the latter ensures your UI is placed safely inside the floating background panel rather than naked on the screen glass.

### 3. `ResponsiveMarginContainer`
A generic structural container that changes its internal padding automatically based on the device.
- Portrait: Snug margins (e.g. 12px) to maximize screen space.
- Desktop: Generous margins (e.g. 24px-32px).

---

## Troubleshooting Checklist

If your UI is clipping off the side of the screen on mobile:
1. **Check for Local Font Boosts**: Search your script for `add_theme_font_size_override` multiplied by a variable. Remove it and rely on the global scale.
2. **Check Grid Columns**: Ensure `GridContainers` are not calculating dynamic columns based on an expanding parent.
3. **Check Label Wrapping**: Ensure long text blocks have `SIZE_EXPAND_FILL`.
4. **Check HBoxes**: Check any `HBoxContainer` or `HFlowContainer` for elements with large `custom_minimum_size.x`.
