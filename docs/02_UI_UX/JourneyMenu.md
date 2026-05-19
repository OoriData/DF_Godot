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

## Core Responsibilities
- **Route Selection**: Displays paths provided by the `RouteService`.
- **Resource Projections**: Calculates estimated fuel, food, and water consumption for the trip.
- **Map Camera Binding**: Coordinates with map elements to preview the route visually.
- **Travel State**: Tracks journey progress, pausing, and completion events.

## Connected Systems
- [Route Service](../03_Systems/RouteService.md)
- [Map System Overview](../03_Systems/MapSystem/MapSystemOverview.md)
