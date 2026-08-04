---
type: system
tags:
  - layer/ui
  - kind/deep-dive
  - status/current
aliases:
  - "Tile Coordinate Math"
created: 2026-05-19
updated: 2026-07-28
verified_against_code: 2026-07-28
status: current
---

# Tile Coordinate Math

How integer tile coordinates become pixel positions, and where that conversion must agree across the
map's overlay layers.

> [!NOTE]
> **Rewritten 2026-07-28.** The previous version described a **hex** grid, **Fog of War**, and
> client-side **terrain speed/fuel multipliers**. None of the three exist — the grid is a square
> `TileMapLayer`, there is no fog system anywhere in `Scripts/`, and all travel maths is server-side.
> See [DocumentationAudit § F11](../../DocumentationAudit.md#f11--autoload-coverage-is-inverse-to-importance).

## The grid

The world is a square-cell **`TileMapLayer`** (`TerrainTileMap`, inside `MapView`'s `SubViewport`).
Tile coordinates are `Vector2i`. There is no hex geometry, offset-row math, or axial coordinate system.

## Tile → pixel

Always convert through the tilemap itself — never reimplement the arithmetic:

```gdscript
var px: Vector2 = terrain_tilemap.map_to_local(tile_coords)  # returns the cell CENTRE
```

Two consequences that have caused real bugs:

1. **`map_to_local` returns the cell centre, not its corner.** To get the top-left, subtract half a tile:
   ```gdscript
   var origin: Vector2 = terrain_tilemap.map_to_local(used.position) - tile_size * 0.5
   ```
   `Scripts/UI/UI_manager.gd` does exactly this when placing the grid-overlay origin.
2. **Overlay nodes must be children of the tilemap** so their local coordinates share its space. The grid
   overlay is parented that way deliberately — reparenting it elsewhere silently offsets every cell.

## Who does this conversion

Three places must stay in agreement. If a map overlay is misaligned, check whether they still do:

| Consumer | File | Use |
|---|---|---|
| Convoy positioning | `Scripts/Map/convoy_node.gd` | interpolates along a journey's tile path via `map_to_local` |
| Grid overlay | `Scripts/UI/map_grid_overlay.gd` | draws cell boundaries; its coords are documented as matching `map_to_local` |
| Labels & markers | `Scripts/UI/UI_manager.gd` | grid origin and per-tile centres for settlement markers |

## What is *not* here

- **Travel cost, ETA, hazard, and fuel consumption are server-side.** `RouteService` is a ~59-line
  passthrough (`request_choices` / `start_journey` / `cancel_journey`) and computes none of them. Don't
  add client-side estimates without first deciding which side is authoritative.
- **No fog of war or visibility masking** exists in this project.

## Related

- **See also:** [Rendering](Rendering.md) — SubViewport sizing and the `IGNORE_SIZE` incident · [Camera](Camera.md) — clamping against the tilemap rect · [Data](Data.md) — the binary tile payload
- **Constrained by:** [Autoload Register](../../04_Technical/AutoloadOrder.md) — `RouteService` is a passthrough
- **Live status:** [TODO.md](../../TODO.md)
