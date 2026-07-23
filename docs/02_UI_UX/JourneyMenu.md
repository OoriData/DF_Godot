---
type: ui-ux
tags:
  - ui
  - codex/journey-menu
aliases:
  - "Convoy Journey Menu"
created: 2026-05-19
---

# Convoy Journey Menu

The Convoy Journey Menu (`convoy_journey_menu.gd`) handles the player's routing options and travel states when navigating between settlements.

## Key Files
- **Script**: `Scripts/Menus/convoy_journey_menu.gd`
- **Scene**: `Scenes/ConvoyJourneyMenu.tscn`

## Core Responsibilities
- **Route Selection**: Displays paths provided by the `RouteService`.
- **Resource Projections**: Calculates estimated fuel, food, and water consumption for the trip.
- **Map Camera Binding**: Coordinates with map elements to preview the route visually.
- **Travel State**: Tracks journey progress, pausing, and completion events.

## Scene Tree & Persistent Chrome

The `.tscn` is minimal scaffolding (`MainVBox` → `TitleLabel`, `ScrollContainer/ContentVBox`, `BackButton`); the rest is built in script. `_ready()` replaces the title with the standard convoy banner, then `_build_planning_chrome()` injects two **persistent** nodes into `MainVBox` around the scroll container:

```
MainVBox
├─ TopBannerPanel        (from MenuBase.setup_convoy_top_banner)
├─ JourneySubHeader      ← injected: "‹ Change" + destination/route/ETA   (hidden by default)
├─ ScrollContainer/ContentVBox   ← the scrollable body
├─ JourneyStickyFooter   ← injected: Top Up / Next Route / Confirm        (hidden by default)
└─ BackButton            (hidden; nav handled by MenuManager's static bar)
```

The sub-header and footer are created **once** and toggled together via `_set_planning_chrome_visible()`. They are shown only during route confirmation and hidden in the planner-list and in-transit views. Keeping the action buttons in the sticky footer (outside `ScrollContainer`) means **the only scrolling region is the body** — actions never scroll off-screen.

## Three View States

`_update_ui()` (called by `MenuBase` on every `GameStore` snapshot) selects one of three renders. A guard skips the rebuild while a confirmation preview is open so background refreshes don't clobber it.

1. **Planner list** (no active journey) — `_populate_destination_list()` builds a scrollable list of tap-to-select destination rows, delivery destinations sorted to the top. Chrome hidden.
2. **Confirmation preview** (a route has been chosen) — `_show_confirmation_panel()` renders the projections in `ContentVBox` and shows the chrome. See below.
3. **In-transit details** (active journey) — ETA headline, location grid, progress bar, and a Cancel Journey button. Chrome hidden.

## Confirmation Preview — Responsive Layout

`_show_confirmation_panel(route_data)`:
- Computes all data first (resource need/have/status, per-vehicle kWh energy, delivery manifest + earnings).
- Drives the **sub-header** (`_update_sub_header()`): destination name, "Route X of N", distance + ETA. The old big centered title/sub-info labels were removed — that info now lives in the sticky sub-header.
- Renders three compact **cards** — Resources, Vehicle energy, Delivery cargo — built by shared `_section_label` / `_mk_card` helpers.
- Resources use a single 4-column `GridContainer` (Resource · Need · Have/Cap · After) instead of per-resource card blocks. Warning/critical rows tint their name + "After" cells (red/amber) and append a one-line warning.
- Layout branches on orientation:
  - **Portrait**: single column — Resources → Energy → Cargo stacked.
  - **Landscape** (wider panel): Resources | Cargo side-by-side in an `HBoxContainer`, Vehicle energy full-width below.
- Builds the footer via `_build_footer(route_data)`; sets `_severity_state` (drives `_apply_severity_styling()` on the footer Confirm button).

### Sticky Footer (`_build_footer`)
Rebuilt fresh each time so button visibility tracks current state:
- **Top Up** — only when parked at a settlement with vendors (`_find_current_settlement()`); wired to the top-up purchase plan.
- **Next Route** — only when `_route_choices_cache.size() > 1`; `_cycle_route(1)` re-runs `_show_confirmation_panel` (sub-header route count updates).
- **Confirm Journey** — always present, given extra stretch so it reads as the primary action; recolored by severity (green / amber / red).

Footer buttons are touch containers built by `_make_touch_button()`, which encapsulates the press-feedback + tap-distance pattern used throughout (label stored under meta `"label"` so `_set_btn_text` / `_set_btn_disabled` work uniformly).

## Orientation Changes

`MenuManager` only re-applies the nav bar on `layout_mode_changed`; it does **not** rebuild menu content. The journey menu therefore connects `DeviceStateManager.layout_mode_changed` itself (`_on_layout_mode_changed`): it re-sizes the sub-header font and, if a confirmation preview is open, re-runs `_show_confirmation_panel` so the body switches between the portrait stack and the landscape two-column form.

## Destination Row Press Handling

Destination rows are tap containers (`MOUSE_FILTER_PASS` so the list still scrolls). The press-highlight is set on press and cleared on release — but on touch, a scroll gesture can consume the release, leaving rows stuck highlighted. Two guards keep exactly one row lit:
- **Clear-on-press**: each press first calls `_clear_destination_highlights()`, resetting every row's stylebox to the normal color.
- **Clear-on-drag**: an `InputEventMouseMotion` branch drops the highlight as soon as the press moves ≥10px (a scroll, not a tap).

## Connected Systems
- [Route Service](../03_Systems/RouteService.md)
- [Map System Overview](../03_Systems/MapSystem/MapSystemOverview.md)
- [Responsive UI / Scaling](ui_system.md)
