---
type: ui-ux
tags:
  - ui
  - codex/vehicle-menu
aliases:
  - "Convoy Vehicle Menu"
created: 2026-05-19
updated: 2026-06-24
---

# Convoy Vehicle Menu

The Convoy Vehicle Menu (`convoy_vehicle_menu.gd`) lets players inspect a vehicle's stats, installed parts, service options, and cargo within a convoy.

## Key Files
- **Scene**: `Scenes/ConvoyVehicleMenu.tscn`
- **Script**: `Scripts/Menus/convoy_vehicle_menu.gd`

## Core Responsibilities
- **Stat Binding**: Renders top speed, offroad, efficiency, cargo/weight capacity, and seats.
- **Part Management**: View installed parts per category with Inspect and Remove actions.
- **Service**: Embedded Mechanics menu (hidden when convoy is on a journey).
- **Cargo**: Per-vehicle cargo rows with weight/volume; links to full convoy manifest.

---

## Tab Structure

The menu uses a `TabContainer` (`VehicleTabContainer`) with **custom pill buttons** rendered in a `TabScroll / TabHBox` strip above the container (native tabs are hidden via `tabs_visible = false`).

| Tab | Content |
|---|---|
| `Summary` | Stat pill grid + compact info grid + collapsible description (portrait only) |
| `Parts` | Installed parts as **loadout cards** grouped by category (portrait: 2-col grid, vertical scroll; landscape: single horizontal-scroll strip) |
| `Service` | Embedded `MechanicsMenu` scene — same loadout-card layout (hidden during journeys) |
| `Cargo` | Aggregated cargo rows (qty, weight, volume) + "View Convoy Manifest" button |

---

## Custom Tab Buttons

Built in `_setup_custom_tabs()`. Each tab gets a `Button` node in `TabHBox`:

| Property | Portrait | Landscape |
|---|---|---|
| Font size | 20px | 20px |
| Min height | 80px | 60px |
| Min width | 160px | 120px |
| Vertical padding | 14px top/bottom | 10px top/bottom |
| Strip height (`TabScroll`) | 92px | 72px |

Active tab: `bg_color = Color(0.25, 0.35, 0.55, 0.9)`, blue border. Inactive: dark `Color(0.15, 0.15, 0.18, 0.9)`, dim border.

---

## Vehicle Dropdown (`VehicleOptionButton`)

Sized and styled in `_ready()`:

| Property | Portrait | Landscape/Desktop |
|---|---|---|
| Button height | 88px | 80px mobile / 48px desktop |
| Button font | 20px | 20px |
| Popup font | 20px | 20px |
| Popup v_separation | 20px mobile | 8px desktop |

The popup's `panel` StyleBox is explicitly overridden with a flat `StyleBoxFlat` (8px margin all sides, dark `#1f2430` bg, blue-tinted border). This prevents Godot inheriting a theme stylebox with a large `content_margin_top` that would push items toward the bottom of the deployed popup box.

---

## Summary Tab Layout

Built by `_populate_summary_tab()`. Layout differs by orientation.

### Portrait
Full-width vertical stack:
1. **Stat pill grid** — 3 columns, 2 rows (6 stats)
2. `HSeparator`
3. **Info grid** — 1 column, up to 6 rows (Name, Make/Model, Color, Shape, Base Value, Current Value)
4. `HSeparator` + **collapsible description** (if present; clamped to 3 lines with More ▾ / Less ▴ toggle)

### Landscape
`HBoxContainer` split — pills left (40%), info right (60%) — using `size_flags_stretch_ratio`:

```
Left column (ratio 2.0)      │  Right column (ratio 3.0)
─────────────────────────────┼────────────────────────────
 [ Speed  ] [ Offroad  ]     │  Name:          Dusty Runner
 [  val   ] [   val    ]     │  Make/Model:    Toyota Hilux
 [ Effic. ] [ Cargo    ]     │  Color:         Sand
 [  val   ] [   val    ]     │  Shape:         Pickup
 [ Weight ] [  Seats   ]     │  Base Value:    $12,000
 [  val   ] [   val    ]     │  Current Value: $9,400
```

- Left: 2-col pill grid (3 rows). Compact pill sizes (see table below).
- Right: 1-col info grid. At ~60% of menu width each cell has ~570px — no clipping.
- Description is **portrait-only**; landscape height is used by the info grid.

### Stat Pill Sizes (`_build_stat_pill`)

| Element | Portrait | Landscape |
|---|---|---|
| Label font | 18px | 13px |
| Value font | 30px | 22px |
| Button min-height (mobile) | 52px | 32px |
| Button min-height (desktop) | 36px | 36px |

### Info Cell Padding (`_add_info_cell`)

| Context | Padding |
|---|---|
| Mobile portrait | 11px |
| Mobile landscape | 7px |
| Desktop | 5px |

---

## Parts Tab — Loadout Cards

`_populate_parts_tab()` renders each installed part as a **loadout card** via `_add_inspectable_part_card_r()`. Cards use the shared `MenuBase` helpers — see [MenuBase Contract](MenuBase.md#loadout-card-helpers).

### Card anatomy

```
┌─── accent border (left, 3px) ───────────────────┐
│  [E]  Engine                 ← badge + slot name │
│  V8 TurboMax                 ← part name         │
│  Top speed +18, Eff −4       ← stat summary      │
│  [ Inspect ]                 ← action button     │
└─────────────────────────────────────────────────-┘
```

- **Badge** — slot initial in a rounded pill, tinted by the slot's accent color.
- **Accent color** — keyed by slot type via `MenuBase._slot_accent()`: Engine/Ice = green, Battery = teal, Tune = amber, Transmission = blue, Tires = purple, Chassis = coral, other = neutral grey.
- **Stat line** — `_get_part_summary_string()` output; row is omitted when empty.
- **Action** — "Inspect" button opens the part detail dialog via `_on_inspect_part_pressed()`.

### Responsive layout

| Orientation | Layout |
|---|---|
| Portrait | Per-category `GridContainer` (2 columns), category labels shown. `PartsScroll` scrolls **vertically**. |
| Landscape | All parts in a single flat `HBoxContainer` (`SIZE_SHRINK_BEGIN`). Category labels and the `PartsHeader` column row are hidden. `PartsScroll` switches to **horizontal scroll** (`horizontal_scroll_mode = AUTO`, `vertical_scroll_mode = DISABLED`). |

> [!IMPORTANT]
> **No nested `ScrollContainer`s.** The outer `PartsScroll` scene node is the only scroll container for the Parts tab. The scroll direction is switched at runtime in `_populate_parts_tab()`. Adding an inner `ScrollContainer` inside the existing one fails in Godot 4 — the outer clips the inner's rect and both compete for touch events, making the inner non-scrollable.

---

## Scaling Rule

`_get_font_size()` returns `base` unchanged — no orientation boosts, no multipliers. `UIScaleManager` owns all scaling via a global `content_scale_factor`. This applies to `convoy_vehicle_menu.gd`, `mechanics_menu.gd` (Service tab), `route_selection_menu.gd`, and `settings_menu.gd` — all were migrated to this rule as of June 2026. See [Responsive UI / Scaling](ui_system.md).

---

## Connected Systems
- [Mechanics System](../03_Systems/Mechanics.md)
- [Mechanics Menu](MechanicsMenu.md)
- [MenuBase Contract](MenuBase.md)
- [MenuManager](MenuManager.md)
