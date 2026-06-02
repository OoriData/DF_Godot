---
type: ui-ux
tags:
  - ui
  - ux
  - codex/devicestate
aliases:
  - "Device State & Orientation Management"
created: 2026-05-18
---

# Device State & Orientation Management

This system coordinates hardware orientation, viewport scaling, and UI safe-area adjustments to ensure a consistent experience across all devices.

## The Coordination Loop

When a device rotates or the window resizes, the following chain of events occurs:

```mermaid
graph TD
    Resize[Viewport Size Changed] --> DSM[DeviceStateManager]
    DSM -->|Detect Orientation| Orientation{Orientation?}
    
    Orientation -->|Portrait| Port[Set Logical Width: 800px]
    Orientation -->|Landscape| Land[Set Logical Width: 1600px]
    
    Port --> Scale[UIScaleManager: Apply content_scale_factor]
    Land --> Scale
    
    Scale --> Safe[SafeAreaHandler: Recalculate Margins]
    Safe --> Menu[MenuBase: Re-apply Layout Adjustments]
    
    Menu --> Redraw[Final UI Redraw]
```

> [!NOTE]
> As of the June 2026 scaling refactor, `DeviceStateManager` no longer scales fonts. The old `get_font_multiplier()` / `get_scaled_base_font_size()` methods were removed. The single `content_scale_size` set by `UIScaleManager` scales all text via the canvas; DeviceStateManager only reports orientation/mode for layout decisions.

## Key Components

### 1. DeviceStateManager (`device_state_manager.gd`)
The primary listener for window/hardware events. 
- **Responsibility**: Detects if the device is in portrait or landscape mode.
- **Signals**: Emits `orientation_changed(mode)` to trigger the rest of the chain.

### 2. UIScaleManager (`ui_scale_manager.gd`)
The authority on viewport scaling.
- **Responsibility**: Calculates `content_scale_factor` = `physical_window_width / target_logical_width` for the active orientation. This is the only scaling operation — no per-node font math.
- **Rule**: All UI logic must assume these logical units, not raw physical pixels.

### 3. SafeAreaHandler (`safe_area_handler.gd`)
Handles hardware notches and islands.
- **Component**: `SafeRegionContainer`
- **Logic**: Uses `DisplayServer.get_display_safe_area()` and converts it into logical coordinates using the current scale.

## Debugging Orientation
You can simulate orientation shifts in the Godot Editor by resizing the game window. The `DeviceStateManager` will automatically trigger the scale shift when the aspect ratio crosses the 1.0 threshold.
