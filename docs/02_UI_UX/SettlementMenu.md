---
type: ui-ux
tags:
  - layer/ui
  - kind/deep-dive
  - status/current
aliases:
  - "Settlement Menu System"
created: 2026-05-19
updated: 2026-07-31
verified_against_code: 2026-07-30
status: current
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

### Refresh vs. Rebuild — the tab lifecycle contract

> **This menu owns the `VendorTradePanel` instances.** Freeing one mid-transaction drops the API reply on
> a dead node, which is how a purchase could succeed server-side with nothing in the UI acknowledging it.
> The rules below exist for that reason (S13-13).

`_display_settlement_info()` is reached from five places — `_ready`, `initialize_with_data`,
`MenuBase._update_ui`, every `GameStore.map_changed` snapshot, and every `layout_mode_changed`. It used
to `_clear_tabs()` and re-instantiate on **all** of them. Now:

| Rule | Mechanism |
|---|---|
| One pass per frame | every caller goes through `_queue_display_settlement_info()`; `call_deferred()` alone does **not** de-duplicate, which used to build two panels per menu open |
| Rebuild only on a real vendor change | `_desired_vendor_ids()` vs `_mounted_vendor_ids()` (each tab's `vendor_id` node meta); equal ⇒ refresh in place and return |
| Never free a panel mid-transaction | `_defer_rebuild_for_active_transaction()`, capped at 10 s |
| Rotation re-lays out, never re-instantiates | each panel handles its own `layout_mode_changed` |

Diagnostic line for the skip path: `[VendorPanel][DIAG] settlement rebuild SKIPPED — vendor set unchanged`.

### Cargo Refresh
`_refresh_active_vendor_panel()` is called from `_update_ui` **and from the skip path above**, so the
single visible panel's convoy cargo refreshes on snapshot updates (the generic `_refresh_all_vendor_panels`
only marks non-active tabs dirty for a lazy refresh on tab change). It **no-ops while that panel has a
transaction in flight** — a `/map`-sourced re-aggregation would otherwise discard the optimistic
projection the panel is currently showing.

Both this function and `_on_vendor_tab_changed()` resolve the vendor through
`_vendor_data_for_panel(panel)`, which reads the `vendor_id` node meta that `_create_vendor_tab()` sets
and looks it up with `_find_vendor_by_id()` — the same handle `_mounted_vendor_ids()` uses, so the two
always agree. `_find_vendor_by_name()` survives only as a fallback for a tab mounted without the meta;
taking it logs `[VendorPanel][DIAG] vendor_id '…' not in snapshot — falling back to name '…'`. Resolving
by node name was the old behaviour and was unsafe because Godot uniquifies duplicate sibling names, so a
settlement with two identically named vendors produced a `Depot2` panel that matched no vendor at all
(**S13-14**).

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
