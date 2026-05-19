---
type: ui-ux
tags:
  - ui
  - technical
  - codex/convoy-cargo-menu
aliases:
  - "Convoy Cargo Menu"
created: 2026-05-19
---

# Convoy Cargo Menu

The Convoy Cargo Menu (`convoy_cargo_menu.gd`) is the primary interface for inspecting and organizing items loaded onto a selected convoy's vehicles. It handles sorting, grouping, and displaying item details through a highly customized, responsive Inspector layout.

---

## Visual & Node Hierarchy

```
MainVBox (VBoxContainer)
├── TitleLabel (Label - MSDF font)
├── SortSettingsContainer (HBoxContainer)
│   ├── OrganizeButton (Button - toggles Group by Type / Group by Vehicle)
│   └── CargoSortOptionButton (OptionButton)
├── ScrollContainer
│   └── CargoItemsVBox (VBoxContainer)
│       ├── (Aggregated Cargo Rows / Section Headers)
│       └── (Collapsible Inspector Panels on Row Selection)
└── BackButton (Button - managed by MenuManager)
```

---

## Core Systems & Logic

### 1. The Multi-Metric Sorting System
The `CargoSortOptionButton` provides 5 distinct sort metrics to organize items, especially useful for managing delivery rewards:
1. **Profit Margin/Unit**: Compares buying price vs. reward.
2. **Profit Density/Weight**: Prioritizes cargo with high financial reward relative to weight.
3. **Profit Density/Volume**: Prioritizes cargo with high financial reward relative to volume.
4. **Total Order Profit**: Sorts by total stack profitability.
5. **Distance to Recipient**: Evaluates physical navigation distance (calculated using coordinate logic).

User sort preferences are persistent through `SettingsManager` using the key `ui.cargo_sort_metric`.

---

### 2. Grouping Toggles (Organization Modes)
The `OrganizeButton` allows the player to dynamically swap the grouping strategy of the cargo list:

| Mode | Visual Structure | Aggregation Rule |
|---|---|---|
| `by_vehicle` (Default) | Vehicle Header (Capacity bars) → Cargo list | Items grouped *per vehicle*. |
| `by_type` | Delivery Cargo → Parts → Consumables | Items aggregated globally across the convoy. |

- **Filtering rules**: Installed vehicle parts (marked `installed: true` or intrinsic parts with `intrinsic_part_id`) are automatically hidden from the cargo menu as they are managed via the [Mechanics System](../03_Systems/Mechanics.md).
- **Aggregation logic**: Stacks are merged using the display name as the lookup key to maintain a clean UI during list rebuilds.

---

### 3. Alternating Alternate-Row Inspector Panels
Clicking an item row toggles an inline **Inspector Panel**. 
- It tracks expanded rows in `_open_inspects` using `cargo_id` keys.
- Alternate rows have alternating dark backgrounds (`Color(0.15, 0.15, 0.18, 0.6)`) to improve readability.
- Description strings autowrap as a full-width paragraph at the top of the grid.
- Modifiers and part stats are unified into a highlighted green label.
- High-priority indicators (Quality, Condition, Quantity) receive custom badge-like coloring.

---

### 4. Debounced Rebuild Guards
To prevent rapid-fire data refreshes from abruptly closing active inspector panels, the menu implements a refresh-suppression window:
- When a user interacts with an inspect panel, `_suppress_refresh_until_msec` is pushed forward.
- If a `convoys_changed` signal arrives during this window, the payload is stashed in `_deferred_convoy_payload` instead of forcing a redraw.
- Once the window expires, `_schedule_deferred_refresh()` safely updates the lists.

---

## Portrait & Landscape Responsiveness

`_is_mobile()` checks both platform features and whether the viewport is vertical (`y > x`).
Key mobile structural overrides:
- Option and toggle buttons expand from **44px** to **100px** height.
- Fonts scale up to **2.8x** to combat high-DPI sizing limits on phones.
- Separations and vertical padding expand to create comfortable touch targets.
- Grids adapt to two columns, and horizontal scroll limits are strictly disabled to prevent drifting.

---

## 🛠️ Diagnostics & Debugging

The menu uses double diagnostic prints to trace state:
1. **`CARGO_MENU_DEBUG`**: Controls snippet-based JSON prints for checking raw item dictionary payloads.
2. **`DIAG_ENABLED` / `_diag()`**: Tracks sequences, timers, and inspector panels (`_snapshot_open_inspects()`).

---

## 🚧 Upcoming: Cargo Destination Clickable Links

As part of the [Cargo Destination Button Plan](../04_Technical/CargoDestinationButtonImplementation.md), the `_add_grid()` layout generator will be modified to support:
- Inspecting destination coordinate fields.
- Replacing static labels with clickable navigators.
- Emitting a camera focus request via `SignalHub` to pan the map camera directly to the recipient settlement.

---

## Primary Files

- **Script**: `Scripts/Menus/convoy_cargo_menu.gd`
- **Scene**: `Scenes/Menus/ConvoyCargoMenu.tscn`
- **Model**: `Scripts/Data/Items.gd`
- **Related**: [Convoy Menu](ConvoyMenu.md), [Items & Missions](../03_Systems/ItemsAndMissions.md), [Destination Implementation](../04_Technical/CargoDestinationButtonImplementation.md)
