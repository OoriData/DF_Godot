# Responsive UI System

This document outlines the standard architecture for creating UI windows and menus in *Desolate Frontiers* that automatically adapt to Desktop, Mobile Landscape, and Mobile Portrait orientations without relying on hacks like `custom_minimum_size` manipulation or manual tree climbs.

## Core Lessons & Limitations Discovered

During our initial iterations of the UI system, we discovered several Godot-specific limitations that dictate how we build menus:

1. **PopupPanel vs CanvasLayer Limitations**: Godot's native `PopupPanel` and OS-level `Window` nodes have their own aggressive positioning logic. Modifying their coordinates manually often results in the window being reset or jammed into the corner of the screen. **Solution**: The `ResponsiveModalPanel` explicitly inherits from `CanvasLayer` instead of `PopupPanel`, establishing a virtual viewport layer that relies entirely on dependable Container Math (`Control.SIZE_SHRINK_CENTER`) rather than buggy OS-level popup boundaries.
2. **DisplayServer vs Viewport Scaling**: Because the `ui_scale_manager` forces `content_scale_factor` multipliers on the scene to make it readable, retrieving physical screen bounds via `DisplayServer.window_get_size()` will return absolute hardware pixels. Mixing physical hardware sizes with multiplied logical container coordinates forces your UI to balloon massively out of frame. **Rule**: ONLY use `get_viewport().get_visible_rect().size` if you ever need to read screen geometries. 
3. **Corner Clipping on Mobile**: Extending a layout to absolutely 100% of the screen limits on portrait mode results in UI elements hiding under modern phone hardware bezels, camera notches, or rounded corners. **Rule**: Never use a 100% fullscreen stretch without padding. `ResponsiveModalPanel` enforces a rigid 4-5% hardware safety buffer on portrait layout, preserving visibility regardless of device model.

---

## Core Components

To build a responsive modal/window, rely on the following components:

### 1. `DeviceStateManager`
An Autoload script (`/root/DeviceStateManager`) that determines the current layout device state automatically.
- **Signal**: `layout_mode_changed(mode, screen_size, is_mobile)`
- **Enum LayoutMode**: `DESKTOP`, `MOBILE_LANDSCAPE`, `MOBILE_PORTRAIT`
- Use `DeviceStateManager.get_layout_mode()` to check layout state.
- **Fonts**: Use `DeviceStateManager.get_scaled_base_font_size(base_size_here)` if a specific custom label requires scaling explicitly (though the system handles global UI themes implicitly).

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
- Simply replace any root `MarginContainer` in your popups with a `ResponsiveMarginContainer.new()` and configure its export variables:
  `mobile_portrait_margins`, `desktop_margins`, `mobile_landscape_margins`.

---

## Migration Guide for Existing Windows

If you are refactoring legacy windows (like `settings_menu.gd` or `cargo_menu.gd`):

1. **Delete manual overrides**: Remove `_is_portrait()`, `_is_mobile()`, `_get_font_size()` from the script.
2. **Delete loop checks**: Remove any `_apply_ui_scaling_recursive` functions. 
3. **Delete manual font boots**: Remove hardcoded font sizes. `ResponsiveModalPanel` generates an adaptive Godot Theme at its root level natively. Modifying individual font sizes is generally unnecessary unless dealing with special header weights or dynamically instantiated UI nodes that might bypass the global theme. In such edge cases, a local sizing helper like `_get_font_size(base_size)` may be necessary to ensure mobile clarity.
4. **Extend**: Change `extends PopupPanel` to `extends ResponsiveModalPanel`.
5. **Adjust Spawning Logic**: Replace `popup_centered(...)` with `open_modal()`. Replace `hide()` with `close_modal()`.
6. **Adjust Content Insertion**: Rename all top layer `add_child(xyz)` statements where `xyz` is your root UI struct to `add_content(xyz)`.
7. **Adjust Containers**: Wrap elements that need to break fluidly into a `FlowContainer` rather than calculating if they fit. Allow `ScrollContainers` to stretch vertically using `Control.SIZE_EXPAND_FILL` without injecting arbitrary minimum lengths (`custom_minimum_size`).

---

## Troubleshooting

- **Text clipping outside the panel**: Check if you have hardcoded a `custom_minimum_size` value on children (like line edits or textures) that exceeds the newly padded screen width on portrait mode.
- **Scroll area is "tiny"**: Remove `custom_minimum_size` on the scroll container. Ensure `size_flags_vertical = Control.SIZE_EXPAND_FILL` is set so it recursively climbs to fill available height below your headers without squeezing into a rigid hardcoded box.
- **Window stuck on huge size**: Double-check that none of your scripts are doing coordinate math with `DisplayServer.window_get_size()`.
