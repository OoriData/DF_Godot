---
type: ui-ux
tags:
  - ui
  - codex/mechanics-menu
aliases:
  - "Mechanics Menu"
created: 2026-05-19
updated: 2026-06-24
---

# Mechanics Menu

`mechanics_menu.gd` / `Scenes/MechanicsMenu.tscn`

Handles vehicle part swapping and is embedded as the **Service tab** inside `ConvoyVehicleMenu`. It can also run standalone (e.g. launched directly from a settlement).

---

## Tab Structure

Two inner tabs rendered via custom pill buttons (`TabsRow / TabScroll / TabHBox`):

| Tab | Content |
|---|---|
| `Parts` | Installed slots as loadout cards — swappable slots only. Installed cards first, empty/swappable slots at the bottom. |
| `Cart` | Pending swaps with per-vehicle stat overview, cost breakdown, and Remove actions. Apply Changes button commits. |

---

## Parts Tab — Loadout Cards

`_rebuild_parts_tab()` renders each swappable slot as a **loadout card** via `_create_slot_card()`. Cards use the shared `MenuBase` helpers — see [MenuBase Contract](MenuBase.md#loadout-card-helpers).

### Card anatomy

```
┌─── accent border (left, 3px) ───────────────────┐
│  [E]  Engine                 ← badge + slot name │
│  V8 TurboMax  (or "Empty")   ← part name         │
│  Top speed +18, Eff −4       ← stat summary      │
│  [ Swap… ] / [ Install… ]    ← action button     │
└─────────────────────────────────────────────────-┘
```

- **Installed** slots: filled card background, colored left border, part name and stat delta.
- **Empty** slots: dimmed card, dashed border, "Empty" label, "Install…" action.
- Empty slots always sort to the bottom of the grid/strip.
- Non-swappable slots (no inventory or vendor candidate available) are omitted entirely.

### Responsive layout

| Orientation | Layout |
|---|---|
| Portrait | 2-column `GridContainer`. Outer `parts_scroll` scrolls **vertically**. |
| Landscape | Single flat `HBoxContainer` (`SIZE_SHRINK_BEGIN`). Outer `parts_scroll` switches to **horizontal scroll** (`horizontal_scroll_mode = AUTO`, `vertical_scroll_mode = DISABLED`). Cards get a fixed minimum width (`_landscape_card_width()`). |

> [!IMPORTANT]
> **No nested `ScrollContainer`s.** `parts_scroll` (the tab's outer scroll container) is the only scroll container for this tab. Its direction is switched at runtime in `_rebuild_parts_tab()`. Adding an inner `ScrollContainer` fails in Godot 4 — the outer clips the inner's rect and both compete for touch events.

### Orientation reflow (Sprint 7)
`_ready()` connects to `DeviceStateManager.layout_mode_changed`; the disconnect is in `_exit_tree()`. On rotation, `_on_layout_mode_changed` re-runs `_setup_custom_tabs()`, re-applies the Apply-button height, and rebuilds the Parts + Cart tabs for the selected vehicle — restoring highlights from caches (`_compat_cache`, availability dicts) so it fires **no** network calls. This makes the Parts grid/strip switch on rotation in place; before, it only updated when the vehicle was re-picked. Applies to both standalone and Service-tab-embedded instances.

### Key internal state

| Variable | Purpose |
|---|---|
| `_slot_grid: Container` | The active card container (GridContainer portrait / HBoxContainer landscape). Nil-checked before use. |
| `_slot_vendor_availability` | Per-slot bool — true when vendor has a compatible candidate. Used to color Swap buttons. |
| `_slot_inventory_availability` | Per-slot bool — true when convoy cargo holds a compatible part. |
| `_compat_cache` | `vehicle_id||cargo_id → payload` — avoids re-requesting compatibility for already-checked pairs. |

### Compat highlight path

The vendor compatibility check is async. When `_on_part_compatibility_ready(payload)` fires:
1. Result is stored in `_compat_cache`.
2. `_restyle_swap_buttons_for_slot(slot_name)` calls `_all_slot_cards()` to find cards by `meta("slot_name")`.
3. `_ensure_slot_row(slot_name)` adds a placeholder card if the slot wasn't in the initial parts list.

`_all_slot_cards()` iterates `_slot_grid.get_children()` — works for both GridContainer and HBoxContainer.

---

## Cart Tab

`_rebuild_pending_tab()` builds one row per pending swap. Row styling uses the same accent color as the slot's card (left border color = `_slot_accent(slot_name)`), with rounded corners to match the card language.

Each row shows:
- Slot → from-part → to-part (with source indicator: Vendor / Inventory)
- Part cost + installation cost (vendor items only; inventory items show install cost only)
- Vehicle value delta
- Stat delta summary (speed, efficiency, off-road, etc.)
- **Remove** button

Below all rows: cost summary (parts cost + installation + total) and the **Apply Changes** button.

---

## Embedded Mode

When embedded as the Service tab inside `ConvoyVehicleMenu`:
- `embedded_mode = true` is set by the parent.
- `_apply_embedded_mode_visibility()` hides redundant chrome (title label, vehicle dropdown, back button).
- The vehicle dropdown and data are driven by the parent menu's selection — `mechanics_menu.gd` receives the vehicle via `initialize_with_data()`.

---

## Scaling Rule

`_get_font_size()` returns `base` unchanged — no orientation boosts. `UIScaleManager` owns all scaling. Previously this function multiplied by `2.5×` (portrait) / `1.6×` (mobile-landscape) / `1.2×` (desktop), double-scaling every font on top of `UIScaleManager`'s `content_scale_factor`. Fixed June 2026. See [Responsive UI / Scaling](ui_system.md).

---

## Connected Systems
- [Mechanics System](../03_Systems/Mechanics.md)
- [Mechanics Service](../03_Systems/MechanicsService.md)
- [Vehicle Menu](VehicleMenu.md)
- [MenuBase Contract](MenuBase.md)
