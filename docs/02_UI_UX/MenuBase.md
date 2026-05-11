# MenuBase Contract

Purpose: Standardize initialization, navigation, and state management across all menus.

## Contract

### Signals
- `back_requested`: Emitted when the user wants to return to the previous screen.
- `open_vehicle_menu_requested(convoy_data)`: Intent to open the vehicle sub-menu.
- `open_journey_menu_requested(convoy_data)`: Intent to open the journey sub-menu.
- `open_settlement_menu_requested(convoy_data)`: Intent to open the settlement sub-menu.
- `open_cargo_menu_requested(convoy_data)`: Intent to open the cargo sub-menu.
- `return_to_convoy_overview_requested(convoy_data)`: Intent to return to the main convoy screen.

### Core Methods
- `initialize_with_data(data_or_id: Variant, extra: Variant = null)`: Accepts a convoy `Dictionary` or a `String convoy_id`.
- `_update_ui(convoy: Dictionary)`: Virtual. Called when data is ready or changed.
- `reset_view()`: Virtual. Clears UI state when data is missing.

### Helper Methods (Styling & Layout)
- `setup_convoy_top_banner(title_node, suffix, break_out_siblings)`: Creates the standard premium header with clickable breadcrumbs.
- `style_convoy_nav_button(button)`: Applies touch-friendly mobile styling.
- `_apply_standard_margins()`: Automatically applies responsive side buffers.

---

## Loading & Empty States

To maintain a premium feel, menus must handle "missing" or "pending" data gracefully.

1.  **Implicit Loading**: When a menu is opened, if the requested `convoy_id` is not yet in the `GameStore`, `MenuBase` calls `reset_view()`. 
2.  **Explicit Loading**: If you are waiting for a specific transaction (e.g., pathfinding), show a `ProgressBar` or a dimmed overlay within the menu.
3.  **The "Sync" Scrim**: For high-stakes operations (like initial login), the `MainScreen` manages a global loading overlay.
4.  **Error Handling**: All `fetch_error` signals from `APICalls` are routed to the `ErrorManager` and displayed via `ErrorDialog.tscn`. Menus do not need to implement their own error popups.

---

## Menu State Persistence

Menus can opt-in to persistence to preserve UI state (like scroll positions) when navigating away and back.

1. **Node Persistence**: Set `persistence_enabled = true`. `MenuManager` will detach the node from the tree instead of freeing it.
2. **State Serialization**:
   - `get_ui_state() -> Dictionary`: Return a snapshot of UI state (e.g., `{"scroll": 120}`).
   - `apply_ui_state(state: Dictionary)`: Restore UI from the snapshot.
   - `get_menu_state_key() -> String`: Returns a unique key (default: `menu_type + convoy_id`).

---

## Update Optimization

To prevent expensive UI redraws on every `GameStore` change, `MenuBase` provides a hashing check:

```gdscript
func _has_relevant_changes(old_data: Dictionary, new_data: Dictionary) -> bool:
    # Default implementation compares the hash of the whole dictionary.
    # Override this to check specific keys if only certain data affects your UI.
    return old_data.hash() != new_data.hash()
```

---

## Example Implementation Pattern

```gdscript
extends MenuBase

@onready var cargo_list = $MainVBox/Scroll/List

func _update_ui(convoy: Dictionary) -> void:
    # Standard header setup
    setup_convoy_top_banner($MainVBox/Title, "Cargo")
    
    # Efficiently populate list
    for item in convoy.get("cargo", []):
        var row = create_row(item)
        cargo_list.add_child(row)

func get_ui_state() -> Dictionary:
    return {"scroll_v": cargo_list.scroll_vertical}

func apply_ui_state(state: Dictionary) -> void:
    cargo_list.scroll_vertical = state.get("scroll_v", 0)
```

---

## Notes
- **Lightweight Init**: Avoid deep copies; rely on `convoy_id` and `GameStore`.
- **Visibility Guards**: `_on_convoys_changed` automatically skips updates if the menu is hidden.
- **Auto-Background**: Set `auto_apply_oori_background = true` to get the standard tiled texture.
