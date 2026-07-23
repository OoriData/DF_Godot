---
type: ui-ux
tags:
  - ui
  - codex/warehouse-menu
aliases:
  - "Warehouse Menu"
created: 2026-05-18
---

# Warehouse Menu

The Warehouse Menu (`warehouse_menu.gd`) handles purchasing, upgrading, and managing a settlement warehouse. It is the largest single script in the codebase and manages a significant amount of dynamic layout construction at runtime.

---

## States

The menu operates in two distinct states depending on whether the convoy's current settlement has an owned warehouse:

| State | UI shown | Condition |
|---|---|---|
| **No Warehouse** | Info card with `BuyButton` | `_warehouse` dict is empty |
| **Owned Warehouse** | `OwnedTabs` (Overview / Cargo / Vehicles) | `_warehouse` dict is populated |

The `BuyButton` triggers `_on_buy_pressed`, which calls `WarehouseService` to purchase a warehouse at the current settlement. Purchase price is looked up from the `WAREHOUSE_PRICES` constant, keyed by settlement type:

```gdscript
const WAREHOUSE_PRICES := {
    "dome": 5_000_000, "city-state": 4_000_000, "city": 3_000_000,
    "town": 1_000_000, "village": 500_000, "military_base": null,
}
```

---

## Layout Architecture

### Dual-Column Layout (Runtime Construction)
`_setup_dual_column_layout()` runs in `_ready()` and **restructures the scene tree at runtime**. It extracts the `Overview` tab from `OwnedTabs` and moves it into a left-side `LeftPanel` (`PanelContainer`), leaving the remaining tabs (Cargo, Vehicles) in a right `RightColumn`.

```
Body (VBoxContainer)
└── Columns (BoxContainer, vertical=false in landscape)
    ├── LeftPanel (PanelContainer)  ← Storage Monitor + Radial Gauge + Upgrade buttons
    └── RightColumn (VBoxContainer)
        └── OwnedTabs (TabContainer)
            ├── Cargo Tab
            └── Vehicles Tab
```

> [!IMPORTANT]
> Because the scene is restructured at runtime, **node paths in the scene file may not match the actual runtime tree**. Always navigate via `find_child()` or cached references, not hardcoded paths, when adding new features.

### Radial Gauge
A `radial_progress_gauge.gd` instance is instantiated programmatically inside the Overview tab's `LeftColumn`. It replaces the `OverviewCargoBar` (which is hidden). The gauge reference is stored as node metadata: `get_meta("radial_gauge")`.

---

## Tabs

### Overview Tab
- Radial gauge showing cargo capacity fill %
- Vehicle slot bar (standard `ProgressBar` styled with theme blue fill)
- Expand Cargo capacity button (`ExpandCargoBtn`)
- Expand Vehicle capacity button (`ExpandVehicleBtn`)

Expand prices are looked up from `WAREHOUSE_UPGRADE_PRICES`. While an expansion is in flight, `_upgrade_in_progress = true` disables the buttons to prevent double-submits.

### Cargo Tab
| Control | Purpose |
|---|---|
| `CargoStoreDropdown` | Select cargo item from the convoy to store |
| `CargoQtyStore` (SpinBox-like) | Quantity to store |
| `StoreCargoBtn` | Trigger store operation |
| `CargoRetrieveDropdown` | Select item from warehouse to retrieve |
| `CargoRetrieveVehicleDropdown` | Target vehicle for retrieval |
| `CargoQtyRetrieve` | Quantity to retrieve |
| `RetrieveCargoBtn` | Trigger retrieve operation |
| `CargoInventoryPanel` | Scrollable grid of warehouse cargo cards |

Clicking a cargo card in the inventory grid auto-selects it in the retrieve dropdown via `_on_cargo_card_selected()`.

### Vehicles Tab
| Control | Purpose |
|---|---|
| `VehicleStoreDropdown` | Select convoy vehicle to store |
| `StoreVehicleBtn` | Trigger store |
| `VehicleRetrieveDropdown` | Select stored vehicle to retrieve |
| `RetrieveVehicleBtn` | Trigger retrieve |
| `SpawnVehicleDropdown` + `SpawnNameInput` + `SpawnConvoyBtn` | Purchase and deploy a vehicle from the warehouse |

---

## Signals Consumed (from Hub)

| Signal | Handler | Purpose |
|---|---|---|
| `warehouse_created` | `_on_hub_warehouse_created` | First-time purchase confirmation |
| `warehouse_updated` | `_on_hub_warehouse_received` | Refresh full warehouse state |
| `warehouse_expanded` | `_on_hub_warehouse_action` | Post-upgrade refresh |
| `warehouse_cargo_stored` | `_on_hub_warehouse_action` | Post-store refresh |
| `warehouse_cargo_retrieved` | `_on_hub_warehouse_action` | Post-retrieve refresh |
| `warehouse_vehicle_stored` | `_on_hub_warehouse_action` | Post-store refresh |
| `warehouse_vehicle_retrieved` | `_on_hub_warehouse_action` | Post-retrieve refresh |
| `warehouse_convoy_spawned` | `_on_hub_warehouse_action` | Post-spawn refresh |
| `error_occurred` | `_on_hub_error` | Inline error display |

---

## Responsive Layout

`_on_layout_mode_changed()` is connected to `DeviceStateManager.layout_mode_changed`. On orientation change it:
1. Calls `_apply_column_responsiveness()` — `Columns.vertical` stacks the panels in portrait; in **landscape** `LeftPanel`/`RightColumn` are `SIZE_EXPAND_FILL` with **1:2 stretch ratios** so they share the full row width (fixes the old right-side deadspace).
2. Calls `_style_buy_menu_ui()` — rescales buttons, dropdowns, and fonts.
3. Calls `_tune_inventory_panels_layout()` — updates tab heights and action-row direction.
4. Calls `_update_ui()` — redraws data.
5. Calls `_render_cargo_grid()` + `_render_vehicle_grid()` — rebuilds inventory cards.

### Portrait is a short bottom sheet (Sprint 7)
In portrait the whole menu is a **full-width bottom sheet** — the map stays pinned above it (`main_screen.gd` sizes it to 55–72% of viewport height). So the design goal is **compact height using the full width**, not tall stacking:

- **Action rows stay on one horizontal line** (`_tune_inventory_panels_layout` sets `hbox.vertical = false`). Dropdown + `[− qty +]` + button fit across the full-width sheet; stacking them vertically wasted the scarce height.
- **Controls shrunk to 72px** (were 120px) — dropdowns, quantity steppers, inputs. Action buttons **140×72** (were 280×130). Tab bar **60px** (was 100).
- **Dropdowns set `fit_to_longest_item = false` + `clip_text = true`** — an `OptionButton` defaults to growing to its widest item, so once populated with cargo names it blew the row past the screen edge (overflow appeared the frame items loaded). Now they honour `SIZE_EXPAND_FILL` and clip.
- **Long labels autowrap** (`_apply_label_wrapping`) so "Upgrade Cargo Capacity (Cap: …)" etc. don't force a wide minimum.

> [!IMPORTANT]
> **The warehouse itself was not the cause of the portrait "cramps and clips off both edges" bug.** The top bar (`user_info_display.gd`) at font 26 summed to a ~833px minimum width, forcing `SafeRegionContainer` — and every menu under it — 33px past the 800px viewport. Fixed in the top bar (fonts 26→20, edge paddings halved). If a menu clips symmetrically off both edges in portrait, measure the **top bar / SafeRegionContainer** min-width before touching the menu. See the debugging protocol in [AI_ONBOARDING.md](../AI_ONBOARDING.md).

---

## The `_diag()` Pattern

This menu uses named diagnostic callbacks prefixed with `_diag_` to verify button signal wiring without changing primary logic:

```gdscript
func _diag_expand_cargo_pressed() -> void:
    print("[WarehouseMenu][Diag] expand_cargo_btn pressed (raw signal)")
```

A deferred `_post_ready_expand_diag()` check also runs after scene stabilization to confirm connections.

---

## Primary Files

- **Script**: `Scripts/Menus/warehouse_menu.gd`
- **Scene**: `Scenes/Menus/WarehouseMenu.tscn`
- **Service**: `Scripts/System/Services/warehouse_service.gd`
- **Gauge**: `Scripts/UI/radial_progress_gauge.gd`
- **Related**: [MenuBase Contract](MenuBase.md), [UISystemIndex](UISystemIndex.md)
