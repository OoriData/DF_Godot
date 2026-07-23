---
type: ui-ux
tags:
  - ui
  - codex/convoy-menu
aliases:
  - "Convoy Menu"
created: 2026-05-18
---

# Convoy Menu

The Convoy Menu (`convoy_menu.gd`) is the **primary landing screen** for a selected convoy. It is the hub from which all other convoy sub-menus are reached and the most heavily modified file in the codebase.

## Scene Layout

```text
MainVBox
├── TopBarHBox
│   ├── BackButton
│   └── TitleLabel
├── ScrollContainer  (scroll DISABLED — layout must fit without scrolling)
│   └── ContentVBox  → split at runtime into MainSplit (HBoxContainer)
│       ├── StatsColumn (Left Side, ~25% width)
│       │   ├── ResourceStatsHBox  (Fuel / Water / Food bars, vertical stack)
│       │   ├── PerformanceStatsHBox  (Speed / Offroad / Efficiency — HBoxContainer, compact side-by-side)
│       │   ├── CargoBarsHBox  (Volume and Weight progress bars)
│       │   └── ConvoyVisualizer  (hero panel, expands to fill remaining height)
│       └── ContentColumn (Right Side, ~75% width)
│           └── VendorPreviewPanel
│               └── VendorPreviewVBox
│                   ├── PreviewTitleLabel
│                   ├── VendorTabsHBox  (e.g., Active Deliveries, Available Parts)
│                   └── VendorContentPanel
│                       └── VendorContentScroll  (VERTICAL scroll — cards stack down)
│                           └── VendorItemGrid  (GridContainer, columns = 1)
└── BottomBarPanel  (navigation bar — managed by MenuManager)
```

---

## Key Responsibilities

### 1. Resource & Performance Display
Reads directly from the `convoy` snapshot in `GameStore`:
- **Fuel / Water / Food**: displayed as `ProgressBar` + label pairs with colour-coded fill.
- **Speed / Offroad / Efficiency**: displayed as fixed-colour stat boxes.
- **Cargo Volume & Weight**: dual progress bars showing used vs. total capacity.

### 2. Vendor Preview Panel
The panel at the bottom of the scroll area provides a tabbed preview of local settlement data **without opening the Vendor Trade Panel**. It has 4 tabs:

| Tab | Button label | Content |
|---|---|---|
| `CONVOY_MISSIONS` | "Active Deliveries" | Active mission items in this convoy's cargo that match vendors at the current settlement |
| `SETTLEMENT_MISSIONS` | "Available Deliveries" | Mission items available *from* this settlement's vendors |
| `COMPATIBLE_PARTS` | "Available Parts" | Parts available at the settlement that fit vehicles in this convoy |
| `JOURNEY` | "Journey" | Active journey progress, destination, and ETA |

> Tab labels do **not** include item counts (e.g. no `(10)` suffix). The count was removed — it was noise at this point in the flow, before the user has opened any tab.

#### Available Parts — per-vehicle fit annotation

Each part in the `COMPATIBLE_PARTS` tab is annotated with **which convoy vehicles can use it**, matched by slot. The fit set is computed once per rebuild from `_convoy_vehicle_slot_map()` (each vehicle's available slots, derived from its installed parts) and `_vehicle_names_for_slot()`, then stashed in the part's meta (`"fits": [vehicle_name, …]`).

- **Meta line**: `_format_item_meta()` renders `<Slot>  •  Fits: <A>, <B>` for the tab; the `Fits:` line is omitted when no convoy vehicle exposes the slot (rather than asserting a misleading "none").
- **Highlight**: parts that fit ≥1 vehicle get a **green** accent strip and green `Fits:` text (`UITheme.STATUS_GOOD`) so they read as actionable; non-fitting parts stay brass/muted. The fit count is cached on the button as the `fits_count` meta so `_style_vendor_item_button()` keeps the colour after the tap-to-reset restyle.
- **Sort**: parts are ordered **most-compatible first** (by fit count, ties broken by name) before the list is built.

Part names/slots come from the `MechanicsService` mechanic-probe snapshot (`cargo_id_to_slot`), so this preview depends on the same warmup pipeline as the Mechanics menu.

### 3. Full Convoy Payload Guard
Because `SignalHub` sometimes emits shallow convoy dictionaries (missing capacity/resource max fields), `ConvoyMenu` has an explicit completeness heuristic:

```gdscript
func _is_convoy_payload_complete(c: Dictionary) -> bool:
    var has_capacity := c.has("total_cargo_capacity") or c.has("max_cargo_volume")
    var has_resource_max := c.has("max_fuel") or c.has("max_water")
    return has_capacity and has_resource_max
```

If the payload is incomplete, it calls `ConvoyService.refresh_single(convoy_id)` once to fetch the full snapshot. This is tracked with `_requested_full_convoy_id` to prevent duplicate requests.

### 4. Destinations Cache
On `initialize_with_data`, the menu scans all cargo items to build `_destinations_cache` — a `Dictionary` mapping item name to resolved destination string. This cache is used by the Vendor Preview to annotate mission item buttons without re-scanning every frame.

### 5. Vendor Detail Warmup
When a convoy is at a settlement, `ConvoyMenu` requests full vendor details via `VendorService.request_vendor()` for every vendor whose `cargo_inventory` is empty in the map snapshot. This ensures the tabs have populated data when the user first opens the menu.

---

## Signals (Custom)

| Signal | Purpose |
|---|---|
| `open_settlement_menu_with_focus_requested(convoy_data, focus_intent)` | Deep-links to the Settlement sub-menu with a pre-selected focus (e.g. scroll to vendor) |
| `open_cargo_menu_inspect_requested(convoy_data, item_data)` | Deep-links to the Cargo sub-menu with a specific item auto-selected in the inspector |

---

## Debounce Pattern

Vendor preview updates are **debounced** via a 100ms `Timer` (`_vendor_preview_update_timer`) to prevent cascading redraws when multiple signals fire simultaneously (e.g. `vendor_updated` + `vendor_preview_ready` on the same frame).

```gdscript
func _queue_vendor_preview_update() -> void:
    if _vendor_preview_update_timer == null:
        _vendor_preview_update_pending = true
        return
    if not _vendor_preview_update_timer.is_stopped():
        return  # already queued
    _vendor_preview_update_timer.start()
```

> [!IMPORTANT]
> If `_vendor_preview_update_timer` is `null` (not yet in tree), the update is deferred via `_vendor_preview_update_pending`. The `_ready()` function checks this flag.

---

## Portrait / Landscape Responsiveness

`_update_mobile_dependent_layout()` is called on `NOTIFICATION_RESIZED`. Key breakpoints:

| Layout | `VENDOR_ITEM_BUTTON_HEIGHT` | `VENDOR_ITEM_BUTTON_MIN_WIDTH` |
|---|---|---|
| Desktop | 72px | 190px |
| Mobile Landscape | 100px | 220px |
| Mobile Portrait | 280px | 340px |

The vendor item grid always targets **2 rows** of horizontal scrolling, with column count calculated as `ceil(item_count / 2.0)`.

---

## Mission Sort

The "Active Missions" tab includes a sortable `OptionButton` with 5 sort metrics:
1. Profit Margin / Unit
2. Profit Density / Weight
3. Profit Density / Volume
4. Total Order Profit
5. Distance to Recipient

The user's sort preference is persisted to `SettingsManager` under the key `ui.cargo_sort_metric`.

---

## Primary Files

- **Script**: `Scripts/Menus/convoy_menu.gd`
- **Scene**: `Scenes/Menus/ConvoyMenu.tscn`
- **Related**: [VendorPanelOverview](VendorPanel/VendorPanelOverview.md), [MenuBase Contract](MenuBase.md), [Items & Missions](../03_Systems/ItemsAndMissions.md)
