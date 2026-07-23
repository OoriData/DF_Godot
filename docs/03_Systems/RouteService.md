---
type: system
tags:
  - system
  - codex/route-service
aliases:
  - "Route Service"
created: 2026-05-19
---

# Route Service

The Route Service (`route_service.gd`) governs map navigation, path calculations, and travel lifecycle events.

## Key Files
- **Script**: `Scripts/System/Services/route_service.gd`

## Core Responsibilities
- **Pathfinding**: Requests and processes valid paths from the backend or local navigation mesh.
- **Travel Mechanics**: Calculates ETA, hazard risks, and resource consumption based on distance and vehicle stats.
- **Journey State**: Commits departures, tracks mid-route positions, and processes arrival events.

## Connected Systems
- [Game Lifecycle](GameLifecycle.md)
- [Journey Menu](../02_UI_UX/JourneyMenu.md)
