---
type: ui-ux
tags:
  - ui
  - ux
  - codex/menubase
aliases:
  - "MenuBase Contract"
created: 2026-05-18
updated: 2026-05-21
---

# MenuBase Contract

`MenuBase` (`Scripts/Menus/MenuBase.gd`) is the abstract base class that **every full-screen convoy menu** must extend. It provides a standardized lifecycle, automatic store subscriptions, responsive layout helpers, and a premium visual layer — so individual menus only need to implement their own data-display logic.

---

## Where It Fits in the UI Stack

```
GameStore (Autoload)
    │  convoys_changed signal
    ▼
MenuBase._on_convoys_changed()
    │  calls _refresh_from_store()
    ▼
MenuBase._update_ui(convoy: Dictionary)   ← overridden by each menu
    │
    ▼
[Visual Components in .tscn scene]
```

`MenuBase` sits between the raw data layer (`GameStore`) and the visual presentation. It is **orchestrated by `MenuManager`**, which:
1. Instantiates the `.tscn` scene whose root script extends `MenuBase`.
2. Calls `initialize_with_data()` (deferred, one frame after add to tree).
3. Connects the standard navigation signals (`back_requested`, `open_vehicle_menu_requested`, etc.) to its own open-menu functions.
4. Manages transitions and persistence — `MenuBase` never navigates itself.

### Menus That Extend MenuBase

| Menu Script | Scene | Menu Type Key |
| :--- | :--- | :--- |
| `convoy_menu.gd` | `ConvoyMenu.tscn` | `convoy_overview` |
| `convoy_vehicle_menu.gd` | `ConvoyVehicleMenu.tscn` | `convoy_vehicle_submenu` |
| `convoy_journey_menu.gd` | `ConvoyJourneyMenu.tscn` | `convoy_journey_submenu` |
| `convoy_settlement_menu.gd` | `ConvoySettlementMenu.tscn` | `convoy_settlement_submenu` |
| `convoy_cargo_menu.gd` | `ConvoyCargoMenu.tscn` | `convoy_cargo_submenu` |
| `warehouse_menu.gd` | `WarehouseMenu.tscn` | `warehouse_submenu` |
| `mechanics_menu.gd` | `MechanicsMenu.tscn` | `mechanics_submenu` |
| `map_menu.gd` | *(map-related scene)* | — |

---

## Lifecycle

```
MenuManager calls initialize_with_data(data_or_id, extra_arg?)
    │
    ├─ data is Dictionary ──► set convoy_id, call _update_top_banner_text, call _update_ui
    └─ data is String (id) ──► set convoy_id, call _refresh_from_store
                                    │
                                    ▼
                           GameStore.get_convoy_by_id(convoy_id)
                                    │
                          ┌─────────┴──────────┐
                    found & changed?         not found / empty
                          │                       │
                    _update_ui(convoy)        reset_view()
```

### Key Phases

1. **Instantiation** — `MenuManager` instantiates the `.tscn`. `_ready()` fires: subscribes to `GameStore.convoys_changed`, applies the Oori background texture, and applies standard side margins.
2. **Initialization** — `initialize_with_data()` is called (deferred). Accepts either a full convoy `Dictionary` snapshot or a `String convoy_id`. Sets `convoy_id` for the lifetime of this node.
3. **Data Refresh** — `_refresh_from_store()` looks up the convoy in `GameStore`, diffhashes the new data against `_last_convoy_data`, and calls `_update_ui()` only if something changed.
4. **Live Updates** — `_on_convoys_changed()` fires every time `GameStore.convoys_changed` is emitted. It calls `_refresh_from_store()` — but only if the menu is visible and has a `convoy_id`.
5. **Visibility Restore** — `_notification(NOTIFICATION_VISIBILITY_CHANGED)` forces a refresh when the node becomes visible again (important for menus embedded in hidden tabs that may have missed updates).
6. **Cleanup** — `_exit_tree()` disconnects the `convoys_changed` signal to prevent stale callbacks.

---

## Signals (Navigation Contract)

These signals are declared on `MenuBase` and are connected by `MenuManager` when a menu is opened. Menus **emit** them; they never act on them directly.

| Signal | When to Emit |
| :--- | :--- |
| `back_requested` | User taps the back/close action |
| `open_vehicle_menu_requested(convoy_data)` | Navigate to Vehicle sub-menu |
| `open_journey_menu_requested(convoy_data)` | Navigate to Journey sub-menu |
| `open_settlement_menu_requested(convoy_data)` | Navigate to Settlement sub-menu |
| `open_cargo_menu_requested(convoy_data)` | Navigate to Cargo sub-menu |
| `return_to_convoy_overview_requested(convoy_data)` | Jump back to the Convoy Overview |

> [!IMPORTANT]
> The static bottom navigation bar (Vehicles / Journey / Settlement / Cargo) lives in `MenuManager`, **not** in individual menus. Menus only emit intent signals — `MenuManager` decides the actual transition.

---

## Virtual Methods to Override

```gdscript
## Called when fresh convoy data is ready. Build or rebuild your UI here.
func _update_ui(_convoy: Dictionary) -> void:
    pass

## Called when convoy data is missing/empty. Clear your UI to a safe blank state.
func reset_view() -> void:
    pass

## Override to make the change-detection smarter (only specific keys matter).
func _has_relevant_changes(old_data: Dictionary, new_data: Dictionary) -> bool:
    return old_data.hash() != new_data.hash()

## Return a snapshot of scrollable/interactive UI state (e.g. scroll position).
func get_ui_state() -> Dictionary:
    return {}

## Restore UI from a snapshot saved by MenuManager before navigation.
func apply_ui_state(_state: Dictionary) -> void:
    pass
```

---

## Loadout Card Helpers

`MenuBase` provides a set of shared helpers for rendering vehicle parts as **loadout cards** — used by the Parts tab (`convoy_vehicle_menu.gd`) and the Service/Parts tab (`mechanics_menu.gd`) so both surfaces stay visually consistent.

### `_slot_accent(slot_name: String) -> Color`

Returns the accent color for a given slot type. The mapping:

| Slot(s) | Color |
|---|---|
| `engine`, `ice`, `motor` | Green `#9ec459` |
| `battery`, `cell` | Teal `#5ccaa6` |
| `tune`, `ecu`, `chip` | Amber `#f0c74a` |
| `transmission`, `trans`, `gearbox`, `drivetrain` | Blue `#7d9eda` |
| `tires`, `tire`, `wheels`, `wheel` | Purple `#bd8dd9` |
| `chassis`, `frame`, `suspension` | Coral `#d48f6b` |
| *(everything else)* | Neutral grey `#8c99b2` |

### `_make_card_style(filled: bool, accent: Color) -> StyleBoxFlat`

Returns a rounded `StyleBoxFlat` for a card surface:
- **Filled** (installed): dark blue-grey background, 3px left border in the slot accent color.
- **Empty** (no part): slightly darker background, 1px dashed-look border, no accent.

### `_make_slot_badge(slot_name, accent, is_empty) -> Control`

Returns a small `PanelContainer` with the slot's initial letter centred inside, tinted by accent. Used as the leading element in the card header row.

### `_make_slot_container(parent: Control) -> Container`

Builds and attaches the appropriate card container to `parent` for the current orientation:
- **Portrait** → 2-column `GridContainer` (`SIZE_EXPAND_FILL`).
- **Landscape** → `HBoxContainer` (`SIZE_SHRINK_BEGIN`) inside a `ScrollContainer` (`horizontal_scroll_mode = AUTO`, `vertical_scroll_mode = DISABLED`). Returns the inner `HBoxContainer` so cards are added directly to it.

> [!IMPORTANT]
> In practice, menus do **not** use `_make_slot_container` to create nested scroll containers. Instead they switch the **outer** tab scroll container's direction at runtime (`parts_scroll.horizontal_scroll_mode = ...`) and add a flat `HBoxContainer` directly to the VBox. Nested scroll containers fail in Godot 4 — the outer clips the inner's rect and both compete for touch events.

### `_landscape_card_width() -> int`

Returns the fixed minimum card width for a landscape horizontal-scroll strip: `220px` desktop, `190px` mobile. Menus set `card.custom_minimum_size.x = _landscape_card_width()` and `card.size_flags_horizontal = SIZE_SHRINK_BEGIN` so cards don't stretch to fill the HBox.

### `_card_is_mobile() -> bool`

Orientation/device check used internally by the card helpers (portrait = treated as mobile for sizing purposes).

---

## Visual Helpers

`MenuBase` provides several pre-built visual helpers that menus call from `_update_ui` or `_ready`:

### `setup_convoy_top_banner(title_node, menu_name_suffix, break_out_siblings, use_dark_bg)`
Replaces a placeholder title node with a fully styled top banner:
- A **dark PanelContainer** with an Oori-accent blue bottom border.
- A **clickable convoy name button** (warm gold text) that emits `return_to_convoy_overview_requested` when tapped. Useful as a breadcrumb.
- A **suffix label** showing the current sub-menu name (e.g. `" | CARGO"`).
- If `break_out_siblings = true`, sibling nodes in the same parent HBox are moved into a secondary `HFlowContainer` panel below the banner instead of being placed inline.

### `_apply_oori_background()`
Adds the standard tileable `Oori Backround.png` texture behind all content. It also calls `_maximize_transparency_recursive()` to strip opaque `StyleBoxFlat` backgrounds from all descendant `PanelContainer`, `Panel`, `TabContainer`, `ScrollContainer`, and `ProgressBar` nodes so the texture shows through.

Set `auto_apply_oori_background = false` on a subclass if you need a custom background.

### `_apply_standard_margins()`
Checks `DeviceStateManager.get_is_portrait()` and applies a 14px inset on all sides to `MainVBox` in portrait mode (to keep content off the screen edge). In landscape/desktop the inset is 0.

### `style_back_button(btn)` / `style_convoy_nav_button(btn)`
Apply consistent button styles — `style_back_button` produces a dark navy rounded button; `style_convoy_nav_button` produces a light grey button matching the static nav bar.

### `_update_navigation_bar_visibility(convoy)`
Calls `MenuManager.set_nav_button_visible("convoy_settlement_submenu", not has_journey)` to hide the Settlement nav button when the convoy is on a journey. Falls back to a local `BottomMenuButtonsHBox` node for legacy scenes.

---

## Menu State Persistence

Menus can opt in to node-level persistence so that UI state (scroll positions, selected tabs) survives navigation:

1. Set `persistence_enabled = true` in the subclass.
2. `MenuManager` will `remove_child()` (detach) instead of `queue_free()` when navigating away, storing the live node in `_persistent_menu_cache`.
3. On return, the node is `reparent()`-ed back and mouse input is restored via `_restore_mouse_recursive()`.
4. For non-persistent menus, override `get_ui_state()` / `apply_ui_state()` — `MenuManager` serializes and restores the returned Dictionary manually.

The cache key is `get_menu_state_key()` → defaults to `"<menu_type>_<convoy_id>"`.

---

## Update Optimization

`MenuBase` only calls `_update_ui` when data actually changes:

```gdscript
func _has_relevant_changes(old_data: Dictionary, new_data: Dictionary) -> bool:
    return old_data.hash() != new_data.hash()
```

Override this in a subclass when only specific keys are relevant to the menu's display:

```gdscript
# Example: cargo menu only cares about cargo changes
func _has_relevant_changes(old: Dictionary, new: Dictionary) -> bool:
    return old.get("cargo") != new.get("cargo")
```

---

## Loading & Empty States

| State | Mechanism |
| :--- | :--- |
| Data not yet in store | `_refresh_from_store()` → `reset_view()` |
| Waiting for a transaction | Show inline `ProgressBar` or dimmed overlay within the menu |
| Initial login / global sync | `MainScreen` manages a full-screen scrim; menus do not |
| Errors | Routed to `ErrorManager` → `ErrorDialog.tscn`; menus do not implement their own error popups |

---

## Example Implementation Pattern

```gdscript
extends MenuBase

@onready var cargo_list = $MainVBox/Scroll/List

func _ready() -> void:
    super._ready() # Applies background + margins

func _update_ui(convoy: Dictionary) -> void:
    # Standard header — creates the breadcrumb banner
    setup_convoy_top_banner($MainVBox/TitleRow, "Cargo")

    # Clear and repopulate
    for child in cargo_list.get_children():
        child.queue_free()
    for item in convoy.get("cargo", []):
        var row = create_row(item)
        cargo_list.add_child(row)

func reset_view() -> void:
    for child in cargo_list.get_children():
        child.queue_free()

func get_ui_state() -> Dictionary:
    return {"scroll_v": $MainVBox/Scroll.scroll_vertical}

func apply_ui_state(state: Dictionary) -> void:
    $MainVBox/Scroll.scroll_vertical = state.get("scroll_v", 0)
```

---

## Quick Reference: Properties

| Property | Type | Default | Purpose |
| :--- | :--- | :--- | :--- |
| `convoy_id` | `String` | `""` | ID of the convoy this menu is bound to |
| `extra` | `Variant` | `null` | Optional secondary context (e.g. `vehicle_id` for deep links) |
| `auto_apply_oori_background` | `bool` | `true` | Automatically tile the Oori background texture on ready |
| `persistence_enabled` | `bool` | `false` | Opt in to node-level cache persistence in MenuManager |
| `_last_convoy_data` | `Dictionary` | `{}` | Internal snapshot for change detection |

---

## Notes

- **Lightweight Init**: Prefer `convoy_id` + `GameStore` over passing full data snapshots. The store is the source of truth.
- **Visibility Guards**: `_on_convoys_changed` skips updates if the menu is hidden. No special guard is needed in subclass implementations of `_update_ui`.
- **No Direct Navigation**: Menus emit signals — they never call `MenuManager` directly. This keeps the dependency graph one-directional.
- **`extra` arg pattern**: `MenuManager` stores a second argument in `_next_menu_extra_arg` before calling `open_*` functions. It is passed through `initialize_with_data(data, extra_arg)` to `MenuBase.extra`. Subclasses read `self.extra` in `_update_ui` to handle deep links (e.g. jump-to-vehicle, jump-to-cargo-item).
