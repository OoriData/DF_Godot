---
type: system
tags:
  - system
  - codex/convoy-service
aliases:
  - "Convoy Service"
created: 2026-05-19
---

# Convoy Service

The Convoy Service (`convoy_service.gd`) is the core domain logic handler for all convoy-related operations, synchronization, and backend communication.

## Key Files
- **Script**: `Scripts/System/Services/convoy_service.gd`

## Core Responsibilities
- **State Synchronization**: Fetches and parses convoy payload data from `APICalls` to update `GameStore`.
- **Convoy Creation**: Handles the initial spawning or purchasing of new convoys.
- **Active Operations**: Facilitates renaming, disbanding, and active tracking of convoys.
- **Signals**: Emits `convoy_updated` to the `SignalHub` for specific updates.

## Connected Systems
- [SignalHub Event Bus](../04_Technical/SignalHub.md)
