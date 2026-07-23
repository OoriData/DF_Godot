---
type: system
tags:
  - system
  - codex/state
aliases:
  - "Local State & Cursor"
created: 2026-05-19
---

# Local Reactive State & Cursor

This document details how *Desolate Frontiers* manages data persistence in the local client and dictates the active context for UI rendering.

## Core Features
1. **GameStore (The Single Source of Truth)**:
   - Maintains the complete local replica of user payloads, active convoys, and settlement information.
   - Triggers UI rebuilds passively by emitting domain events through `SignalHub` when new data is parsed.
2. **ConvoySelectionService (The Global Cursor)**:
   - Manages *which* convoy is actively being inspected by the player.
   - Used by the map camera to determine focus points and by UI sub-menus (Cargo, Journey, Vehicle) to fetch the correct data slices from `GameStore`.

## Key Files
- **Reactive Store**: `Scripts/System/Services/game_store.gd`
- **Context Cursor**: `Scripts/System/Services/convoy_selection_service.gd`

## Connected Systems
- [Architecture Index](../01_Architecture/ArchitectureIndex.md)
