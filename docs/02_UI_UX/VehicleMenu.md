---
type: ui-ux
tags:
  - ui
  - codex/vehicle-menu
aliases:
  - "Convoy Vehicle Menu"
created: 2026-05-19
---

# Convoy Vehicle Menu

The Convoy Vehicle Menu (`convoy_vehicle_menu.gd`) allows players to inspect a specific vehicle's stats, active conditions, and installed parts within a convoy.

## Key Files
- **Script**: `Scripts/Menus/convoy_vehicle_menu.gd`

## Core Responsibilities
- **Stat Binding**: Renders health, fuel efficiency, weight capacities, and speed ratings.
- **Part Management**: Provides the UI to view installed parts per vehicle slot.
- **Interactions**: Transitions to the Mechanics menu for part installation/removal.

## Connected Systems
- [Mechanics System](../03_Systems/Mechanics.md)
- [Mechanics Menu](MechanicsMenu.md)
