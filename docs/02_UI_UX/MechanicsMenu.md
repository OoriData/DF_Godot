---
type: ui-ux
tags:
  - ui
  - codex/mechanics-menu
aliases:
  - "Mechanics Menu"
created: 2026-05-19
---

# Mechanics Menu

The Mechanics Menu (`mechanics_menu.gd`) is the complex UI layer where players repair vehicles and install or swap parts on vehicle slots.

## Key Files
- **Script**: `Scripts/Menus/mechanics_menu.gd`

## Core Responsibilities
- **Repair UI**: Manages the interface for applying repair kits or spending credits to restore vehicle/part health.
- **Slot Management**: Displays compatible parts for specific vehicle slots and handles the swap/equip flow.
- **Condition Warnings**: Alerts players to incompatible part weights, type mismatches, or missing items.

## Connected Systems
- [Mechanics System](../03_Systems/Mechanics.md)
- [Mechanics Service](../03_Systems/MechanicsService.md)
