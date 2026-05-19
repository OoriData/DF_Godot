---
type: ui-ux
tags:
  - ui
  - codex/settlement-menu
aliases:
  - "Convoy Settlement Menu"
created: 2026-05-19
---

# Convoy Settlement Menu

The Convoy Settlement Menu (`convoy_settlement_menu.gd`) is the primary interface for interacting with the local settlement services when a convoy is parked.

## Key Files
- **Script**: `Scripts/Menus/convoy_settlement_menu.gd`

## Core Responsibilities
- **Local Information**: Displays settlement details and status.
- **Service Hub**: Acts as a springboard to access Vendor Panels, Warehouses, and refueling options.
- **Dynamic Capabilities**: Enables/disables buttons based on the `sett_type` (e.g., dome vs. village).

## Connected Systems
- [Vendor Panel](VendorPanel/VendorPanelOverview.md)
- [Warehouse Menu](WarehouseMenu.md)
