# Implementing the Cargo Destination Button

## Objective
Enable direct map navigation for delivery cargo by adding a clickable destination button in the cargo inspector panel. When pressed, the map camera should pan to the coordinates of the destination settlement.

## Problem Context
Currently, the `ConvoyCargoMenu` renders all item metadata as static `Label` nodes within the inspector sub-panel (handled in `_add_grid()`). There is no interactive mechanism to jump to the location of a destination or recipient vendor directly from the cargo screen. Furthermore, `SignalHub` and `MenuBase` lack a standardized signal for initiating an arbitrary map pan event outside of the standard convoy selection flow.

## Implementation Plan

### 1. Update the Inspector Rendering Loop (`convoy_cargo_menu.gd`)
Within `Scripts/Menus/convoy_cargo_menu.gd`, locate the `_add_grid()` function (approx. line 586).
Currently, it creates a key-value row for each detail property:
- It creates `v_lbl` as a `Label.new()` and assigns the value.

**Changes required:**
1. Check if the key `k` is related to destination or recipient (e.g., `k == "recipient_settlement_name"` or `k == "destination"` or `k == "recipient"`).
2. If it is a destination key, instantiate a `Button` instead of a `Label`.
3. Style the button to match the interactive elements (e.g., using a flat stylebox, vibrant text color, and hover effects).
4. Connect the button's `pressed` signal to a new handler `_on_destination_button_pressed(data)`.

### 2. Resolving the Coordinates
In `_on_destination_button_pressed(data: Dictionary)`:
1. Extract the `recipient_id` or `destination_vendor_id`.
2. Look up the settlement from the local caches (`_vendor_id_to_settlement` or `_latest_all_settlements`).
3. Extract `coord_x` and `coord_y` from the resolved settlement dictionary.
4. Construct a `Vector2i(int(x), int(y))` representing the map tile coordinate.

### 3. Add Global Routing Signal (`SignalHub.gd`)
To avoid tight coupling between menus and `main_screen.gd`, introduce a new signal in `Scripts/System/Services/signal_hub.gd`:
```gdscript
# Add to SignalHub.gd under Map and Settlements section
signal map_focus_requested(tile_coord: Vector2i)
```

Emit this signal from the button's press handler in `convoy_cargo_menu.gd`:
```gdscript
if _hub.has_signal("map_focus_requested"):
    _hub.emit_signal("map_focus_requested", Vector2i(x, y))
```

### 4. Connect and Handle Pan in MainScreen (`main_screen.gd`)
In `Scripts/UI/main_screen.gd`:
1. During `_ready()` or `initialize()`, connect to the new `SignalHub` signal:
```gdscript
var hub = get_node_or_null("/root/SignalHub")
if is_instance_valid(hub) and hub.has_signal("map_focus_requested"):
    hub.map_focus_requested.connect(_on_map_focus_requested)
```
2. Implement the handler to instruct the `map_camera_controller`:
```gdscript
func _on_map_focus_requested(tile_coord: Vector2i):
    if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("focus_on_tile"):
        # Optionally close the current menu using MenuManager so the map is fully visible
        # MenuManager.close_all_menus() 
        map_camera_controller.focus_on_tile(tile_coord)
```

## Considerations
- **Menu Occlusion**: Since panning happens while a menu might be open, if the menu remains open, the focus logic might need to account for menu occlusion padding using `smooth_focus_on_world_pos` instead of `focus_on_tile` or by updating the camera offset.
- **Coordinate Transformation**: Ensure that `focus_on_tile(tile_coord)` correctly translates tile indices to world positions, which the `map_camera_controller.gd` already handles appropriately.
