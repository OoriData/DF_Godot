# Rendering: TileMaps & Fog of War

The map uses Godot 4's `TileMapLayer` nodes to efficiently render thousands of hexes and dynamic visibility masks.

## Layer Stack

The `MapView` contains several layers ordered by Z-index:

| Layer | Node Type | Purpose |
| :--- | :--- | :--- |
| **Terrain** | `TileMapLayer` | Base hex grid (Sand, Rock, Water). |
| **Overlay** | `TileMapLayer` | Landmarks and location markers. |
| **Fog** | `TileMapLayer` | Semi-transparent "Unexplored" mask. |
| **Routes** | `Node2D` | `Line2D` nodes for active journey paths. |
| **Convoys** | `Node2D` | Parent for all `ConvoyNode` instances. |

## Tile Generation Flow

```mermaid
graph TD
    Data[Map Data: Binary Payload] --> Parser[Tools.deserialize_map_data]
    Parser --> Store[GameStore: Tiles Snapshot]
    Store --> MapView[MapView: update_map]
    
    MapView --> Terrain[Set Terrain Tiles]
    MapView --> Landmarks[Set Landmark Overlays]
    MapView --> Fog[Initialize Fog Layer]
```

## Fog of War

The **FogTileMap** acts as a shroud over the entire map.
- **Initialization**: Every tile starts as "Unexplored" (typically a dark, semi-transparent hex).
- **Clearing**: As the player's convoy moves, the `FogManager` updates the TileMap at the convoy's current coordinates to "Explored" (null or transparent tile).
- **Persistence**: Fog state is currently managed by the client but is based on the `explored` flags in the backend map payload.

## Route Visualization
Journey routes are drawn using **`Line2D`** nodes.
- **Interpolation**: The line follows the exact path of tiles returned by the `RouteService`.
- **Styling**: Colors change based on convoy status (e.g., active journey vs. previewed route).
- **Anti-Aliasing**: Map routes use standard Godot anti-aliasing to maintain clarity at high zoom levels.
