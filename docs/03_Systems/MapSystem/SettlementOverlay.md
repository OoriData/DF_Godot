---
type: system
tags:
  - system
  - system/map
  - codex/visuals
aliases:
  - "Settlement Overlay System"
created: 2026-05-29
---

# Settlement Overlay System

The **Settlement Overlay System** draws world-space visual annotations on top of the map to communicate convoy-settlement relationships at a glance. It consists of a custom `Node2D` drawing script (`settlement_overlay_draw.gd`) and integration logic inside `UI_manager.gd` that feeds it data each frame.

---

## Overview of Visual Elements

| Element | Purpose |
|:--------|:--------|
| **Callout tails** | Filled triangle connecting a label panel's bottom-center to its tile center. |
| **Tile outlines** | Contrasting rectangle drawn exactly around a settlement tile at all zoom levels. |
| **Focus pins** | Location-pin shape above the tile that is the active focus origin (selected/pinned convoy or settlement). |
| **Route arcs** | Thin curved arrows from a focus origin to each of its cargo destinations. |

---

## Architecture: Two-Overlay Pattern

All drawing is done by `settlement_overlay_draw.gd` — a single `Node2D` script that accepts data arrays and redraws in `_draw()`. Two instances of this script are created at runtime by `UIManager`:

```
settlement_label_container  (Node2D, world-space)
├── _settlement_overlay     (settlement_overlay_draw.gd, z_index = -1)
│     draws: arcs, tile outlines, callout tails
└── _pin_overlay            (settlement_overlay_draw.gd, z_index = 10)
      draws: focus pins only
```

**Why two nodes?** Settlement label panels sit between z=-1 and z=0 by default. Putting tails and outlines at z=-1 places them behind the panels (correct). But focus pins need to be visible *above* panels, so they live at z=10 in a separate overlay node that otherwise draws nothing.

### Creation

`UIManager._ensure_settlement_overlay()` lazily creates both nodes as children of `settlement_label_container` (the same Node2D container that holds label panels). The method is idempotent — if the nodes already exist, it returns immediately.

---

## `settlement_overlay_draw.gd`

**Location:** `Scripts/UI/settlement_overlay_draw.gd`

### Data Arrays (set each frame by UIManager)

| Variable | Shape | Description |
|:---------|:------|:------------|
| `tail_data` | `Array[{panel_bottom_center, tile_center, bg_color, panel_scale}]` | One entry per visible panel. |
| `outline_data` | `Array[{tile_center, color}]` | One entry per settlement tile to outline. |
| `focus_pins_data` | `Array[{tile_center, color}]` | One entry per focus-origin tile. |
| `arc_data` | `Array[{from, to, color}]` | One arc per source→destination pair. |

All coordinates are **world-space** (`Vector2`, SubViewport coordinate system).

### Public API

```gdscript
# Push fresh data and trigger redraw.
func update_frame(
    p_tail_data:        Array,
    p_outline_data:     Array,
    p_zoom:             float,
    p_tile_size:        Vector2,
    p_focus_pins_data:  Array = [],
    p_arc_data:         Array = []
) -> void

# Clear all data and trigger redraw (used when map labels are hidden).
func clear_frame() -> void
```

### Drawing Order (layering)

```
_draw_arcs()          ← beneath everything
_draw_tile_outlines()
_draw_tails()
_draw_focus_pins()    ← on top
```

### Appearance Tweakables

All size values are in **screen-pixels** and are divided by zoom before drawing so they remain constant regardless of camera zoom.

| Variable | Default | Effect |
|:---------|:--------|:-------|
| `tail_half_width_px` | 5.5 | Half-width of the callout triangle base. |
| `outline_width_px` | 2.0 | Stroke width of the tile rectangle. |
| `outline_inset_px` | 1.0 | Inset from the tile edge (prevents overlap with tile border). |
| `pin_head_radius_px` | 5.0 | Radius of the pin's circular head. |
| `pin_gap_px` | 2.0 | Gap between the pin tip and the tile's top edge. |
| `arc_width_px` | 1.5 | Stroke width of route arcs. |
| `arc_arrow_size_px` | 7.0 | Arrowhead triangle size. |
| `arc_segments` | 28 | Bezier curve resolution. |
| `arc_bow_fraction` | 0.28 | How much arcs bow sideways as a fraction of chord length. |

---

## Route Arcs (Quadratic Bézier)

Arcs are drawn as quadratic Bézier curves bowing to the **left of the travel direction**, giving each route a visually distinct path even when source and destination are colinear.

**Control point calculation:**

```gdscript
var dir:  Vector2 = (dst - src) / chord
var perp: Vector2 = Vector2(-dir.y, dir.x)           # 90° left of travel
var ctrl: Vector2 = (src + dst) * 0.5 + perp * chord * arc_bow_fraction
```

**Sampling:**

```gdscript
for i in range(arc_segments + 1):
    var t  = float(i) / float(arc_segments)
    var mt = 1.0 - t
    pts[i] = mt*mt*src + 2.0*mt*t*ctrl + t*t*dst
```

**Arrowhead:** The final tangent at `t=1` is `(dst - ctrl).normalized()`. The arrowhead is a filled triangle pointing in that direction, centered at `dst`.

Arcs shorter than half a tile width are skipped to avoid visual noise for adjacent tiles.

---

## Focus Pins

A focus pin is drawn above any tile that is the **active focus origin** — meaning the player has selected or pinned the convoy/settlement associated with that tile.

**Pin anatomy (bottom to top):**

```
  ●   ← head circle with inner white dot
  ▲   ← body triangle pointing down
  ·   ← gap above tile top
  ═   ← tile top edge
```

The pin tip touches the gap above the tile's top edge. The head center is positioned `head_r * 1.8` above the tip. A drop shadow is drawn first as a slightly offset, lower-alpha filled circle.

**Sources of focus-pin data** (evaluated in `UIManager._refresh_settlement_overlay()`):

1. Convoys in `_selected_convoy_ids_cache` (currently selected).
2. Convoys returned by `convoy_label_manager.get_pinned_convoy_ids()` (manually pinned via long-press/pin gesture).
3. Settlement coordinates in `_pinned_settlement_coords`.
4. The hovered settlement (temporary, cleared when hover moves away).

These are resolved to world-space `tile_center` using `terrain_tilemap.map_to_local(Vector2i(...))` directly — not through the panel draw loop — so pins persist even when the cursor is elsewhere.

### Settlement-pin API (`UIManager`)

`_pinned_settlement_coords` is mutated through these methods (each triggers `_force_draw_interactive_labels_deferred()`):

| Method | Purpose |
|:-------|:--------|
| `toggle_settlement_pin(coords)` | User long-press / map-click toggle (does **not** itself redraw). |
| `add_settlement_pin(coords)` | **Idempotent** add — pin a settlement so its label/pin shows. |
| `remove_settlement_pin(coords)` | **Idempotent** remove. |
| `is_settlement_pinned(coords)` | Query without mutating. |
| `clear_all_settlement_pins()` | Drop all pins. |

### Settlement menu auto-pins its settlement

When `ConvoySettlementMenu` opens, it pins the current settlement so the **name shows on the map** (the in-header settlement-name label was removed — see [Vendor ResponsiveRefactor §10](../../02_UI_UX/VendorPanel/ResponsiveRefactor.md)). Flow (unidirectional, via SignalHub):

```
ConvoySettlementMenu._activate_settlement_map_label()
  → SignalHub.settlement_menu_pin_requested(coords, true)
    → MainScreen._on_settlement_menu_pin_requested()
      → UIManager.add_settlement_pin(coords)   # only if not already pinned
```

On close (`_exit_tree` → `..._deactivate_settlement_map_label()`) it emits `settlement_menu_pin_requested(coords, false)`. **Ownership guard:** `MainScreen` only removes the pin on close if *it* added it (`_menu_pinned_settlement_coords`) — it never clears a settlement the player pinned manually.

---

## Color Coding and Dimming

When one or more convoys are focused, the overlay shifts into **correlation mode**:

- **Related panels** (the focused convoy's current settlement, its cargo destinations, and settlements route-linked to the hovered panel) are shown at full alpha.
- **Unrelated panels** are dimmed to `modulate.a = 0.25`.
- **Tile outline and tail colors** are multiplied by the panel's `modulate.a` so dimmed settlements also have faded visuals.
- **Border accent color** on each settlement panel is set to the focused convoy's accent color, making convoy↔settlement correlation obvious.

The `_apply_settlement_panel_dimming()` method in `UIManager` manages the `panel.modulate` values each frame. It reads `_coords_to_targeting_convoys` (a dictionary built during the label loop mapping settlement coords → list of convoy IDs targeting that settlement) to determine the related set.

---

## Smooth Zoom Transitions

Settlement panel scale (`panel.scale = Vector2(1/zoom, 1/zoom)`) previously snapped instantly when the camera zoom changed. This was replaced with a lerp in `UIManager._process()`:

```gdscript
func _process(delta: float) -> void:
    if is_equal_approx(_display_zoom, _current_map_zoom_cache):
        return
    _display_zoom = lerp(_display_zoom, _current_map_zoom_cache,
                         clampf(delta * zoom_lerp_speed, 0.0, 1.0))
    if absf(_display_zoom - _current_map_zoom_cache) < 0.0005:
        _display_zoom = _current_map_zoom_cache
    _draw_interactive_labels(_current_hover_info_cache)
```

`zoom_lerp_speed` (default `10.0`) is an `@export` on UIManager under the "Zoom Smoothing" group. The overlay's `update_frame()` always receives `_current_map_zoom_cache` (true camera zoom) for world-space size calculations, while panels use `_display_zoom` for their scale.

---

## Hitbox Coordinate Fix

**Problem:** Settlement and convoy label hit-tests were triggering a few tiles above the actual visual position.

**Root cause:** `MapInteractionManager` stores a reference to the `MapDisplay` TextureRect for SubViewport coordinate conversion. The reference was set via a hardcoded `get_node` path, but `MapDisplay` gets **reparented** before `initialize()` is called, making the path stale and leaving `_map_texture_rect` as `null`. With no TextureRect, coordinate conversion skipped the SubViewport scaling step entirely.

**Fix:** `initialize()` now accepts an optional `p_map_texture_rect: TextureRect = null` parameter. `main.gd` passes the TextureRect directly:

```gdscript
# main.gd
map_interaction_manager.initialize(
    terrain_tilemap, ui_manager_node, ...,
    map_display   # TextureRect passed directly after reparenting
)
```

```gdscript
# map_interaction_manager.gd
func initialize(..., p_map_texture_rect: TextureRect = null):
    if is_instance_valid(p_map_texture_rect):
        _map_texture_rect = p_map_texture_rect
    else:
        _map_texture_rect = get_node_or_null("../MapContainer/MapDisplay")
    if not is_instance_valid(_map_texture_rect):
        printerr("MapInteractionManager: _map_texture_rect is invalid — coordinate conversion degraded!")
```

All hit-tests, drag offsets, and drag-clamp logic in `map_interaction_manager.gd` use `_screen_to_subvp_world()` which requires a valid `_map_texture_rect` to account for SubViewport scaling.

---

## Related Files

| File | Role |
|:-----|:-----|
| `Scripts/UI/settlement_overlay_draw.gd` | Node2D drawing script for all overlay elements. |
| `Scripts/UI/UI_manager.gd` | Builds data arrays, manages overlays, applies dimming/color logic. |
| `Scripts/UI/convoy_label_manager.gd` | Provides `get_pinned_convoy_ids()`, sets `is_focus_source` meta on convoy panels. |
| `Scripts/Map/map_interaction_manager.gd` | Hit-test and drag logic; requires valid `_map_texture_rect` for coordinate conversion. |
| `Scripts/System/main.gd` | Passes `MapDisplay` TextureRect directly to `map_interaction_manager.initialize()`. |
