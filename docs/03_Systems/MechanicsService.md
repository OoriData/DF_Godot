---
type: system
tags:
  - system
  - codex/mechanics-service
aliases:
  - "Mechanics Service"
created: 2026-05-19
---

# Mechanics Service

The Mechanics Service (`mechanics_service.gd`) manages the strict business logic for vehicle parts, capacity calculations, and mechanical compatibility.

## Key Files
- **Script**: `Scripts/System/Services/mechanics_service.gd`

## Core Responsibilities
- **Compatibility Rules**: Validates if a `PartItem` can be installed on a given vehicle slot based on weight, dimensions, and type constraints.
- **Stat Math**: Calculates the net modifiers for fuel efficiency, speed, and carry capacities after parts are attached.
- **Durability**: Handles condition degradation and repair logic.

## Connected Systems
- [Mechanics & Parts](Mechanics.md)
- [Mechanics Menu](../02_UI_UX/MechanicsMenu.md)
