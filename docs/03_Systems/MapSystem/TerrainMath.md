---
type: system
tags:
  - system
  - system/map
  - codex/terrain-math
aliases:
  - "Terrain Math & Hex Logic"
created: 2026-05-19
---

# Terrain Math & Hex Logic

The spatial engine maps visual hex tiles (`Vector2i`) to physical travel metrics and resource consumption calculations.

## Core Features
1. **Terrain Multipliers**:
   - Different tile types (e.g., Highway vs. Desert) apply multipliers to a convoy's base speed and fuel consumption within `route_service.gd`.
2. **Fog of War**:
   - Dynamic visibility masking calculated via distance formulas from active convoy coordinates.
3. **Hex to World Translation**:
   - Offsets visual elements by converting integer hex steps into pixel coordinates via the tilemap's `map_to_local` functions.

## Key Files
- **Route Engine**: `Scripts/System/Services/route_service.gd`
- **Map Service**: `Scripts/System/Services/map_service.gd`

## Connected Systems
- [Map Rendering](Rendering.md)
