---
type: ui-ux
tags:
  - ui
  - codex/settlement-menu
aliases:
  - "Settlement Menu System"
created: 2026-05-19
updated: 2026-06-30
---

# Settlement Menu System

The settlement UI is a **two-screen stack**: a hub overview screen followed by a single-vendor trade screen. This replaces the old single-screen multi-vendor layout from before Sprint 5.5.

## Navigation Flow

```
Settlement nav button (or pinned map label tap)
        ↓
SettlementOverviewMenu  ("settlement_hub" or "settlement_overview")
        ├─ Tap vendor card  →  ConvoySettlementMenu (single-vendor mode)
        └─ Tap Warehouse   →  WarehouseMenu
```

---

## Screen 1 — Settlement Overview Hub

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/SettlementOverviewMenu.tscn` |
| **Script** | `Scripts/Menus/settlement_overview_menu.gd` |
| **Extends** | `MenuBase` |
| **Menu Types** | `settlement_hub` (convoy present) · `settlement_overview` (map preview only) |

### Responsibilities
- Displays settlement name, type, and coordinates as info chips.
- Renders a vendor grid (2-col or 1-col in portrait) with name, trade summary, and "Trade ›" affordance.
- Routes to `open_vendor_requested(convoy, vendor_id)` when a vendor card is tapped and a convoy is present.
- Routes to `open_warehouse_menu_requested` for the Warehouse entry.
- In **map-preview mode** (no convoy): vendor cards are informational only; warehouse button still opens the warehouse.

### Data Wiring
- Convoy-present mode: subscribes `GameStore.convoys_changed` + `map_changed`; resolves the settlement from the convoy's coordinates via `GameStore`.
- Map-preview mode: receives a bare settlement dict; no store subscriptions.

### Map Trigger
Tapping a **pinned settlement label** on the map emits `MapInteractionManager.settlement_preview_requested(coords)` → `main_screen.gd` → `open_settlement_overview_menu(settlement)`. The `›` chevron appended to pinned labels by `UI_manager.gd` is the tappable cue.

---

## Screen 2 — Single-Vendor Trade Menu

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/ConvoySettlementMenu.tscn` |
| **Script** | `Scripts/Menus/convoy_settlement_menu.gd` |
| **Extends** | `MenuBase` |
| **Opens via** | `menu_manager.open_convoy_settlement_menu_with_focus(convoy, vendor_id)` |

### Single-Vendor Mode
When opened with a `vendor_id` focus the menu:
- Builds **only** that vendor's tab (skips all others).
- Hides the tab strip and vendor selector (`_single_vendor_id` flag).
- Replaces the convoy breadcrumb banner with a compact **"‹ Settlement"** back button stacked above the vendor name (`_apply_single_vendor_banner`).
- `back_requested` → `MenuManager.go_back()` pops the stack back to the hub.

### Cargo Refresh
`_refresh_active_vendor_panel()` is called from `_update_ui` so the single visible panel's convoy cargo refreshes on snapshot updates (the generic `_refresh_all_vendor_panels` skips tabs that aren't active).

---

## Key Files

| File | Role |
|---|---|
| `Scripts/Menus/settlement_overview_menu.gd` | Hub screen — vendor grid, warehouse entry, dual mode |
| `Scripts/Menus/convoy_settlement_menu.gd` | Single-vendor trade screen |
| `Scripts/Menus/VendorPanel/top_up_planner.gd` | Pure calculator: `calculate_plan(convoy, settlement, budget)` — consumed by the Top Up button in `convoy_menu.gd` |
| `Scripts/Menus/menu_manager.gd` | `open_settlement_overview_menu`, `open_convoy_settlement_menu_with_focus`, `_on_overview_open_vendor` |
| `Scripts/Menus/vendor_trade_panel.gd` | Trade UI shell: Buy/Sell segmented switch + sort inline (settings drawer removed) |
| `Scripts/Map/map_interaction_manager.gd` | Emits `settlement_preview_requested` for pinned-label taps |
| `Scripts/UI/UI_manager.gd` | Appends `›` chevron to pinned settlement labels |

---

## Connected Systems
- [Vendor Panel](VendorPanel/VendorPanelOverview.md)
- [Warehouse Menu](WarehouseMenu.md)
- [MenuManager](MenuManager.md)
