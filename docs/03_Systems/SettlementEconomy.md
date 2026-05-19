---
type: system
tags:
  - system
  - system/economy
  - codex/economy
aliases:
  - "Warehouse & Bulk Economy"
created: 2026-05-19
---

# Warehouse Transfers & Bulk Services

This module governs physical item movements and bulk resource acquisitions when a convoy is docked at a settlement.

## Core Features
1. **Warehouse Transactions**:
   - Handles the strict rules for depositing or withdrawing specific quantities of cargo/parts into local settlement grids via the `WarehouseService`.
2. **Bulk Refueling & Supplies**:
   - Separate from the item-based trading system, the `VendorService` orchestrates liquid transfers (fuel) and bulk consummables without cluttering the cargo manifest.

## Key Files
- **Warehouse Logic**: `Scripts/System/Services/warehouse_service.gd`
- **Vendor Bulk Transactions**: `Scripts/System/Services/vendor_service.gd`

## Connected Systems
- [Warehouse Menu](../02_UI_UX/WarehouseMenu.md)
- [Vendor Panel](../02_UI_UX/VendorPanel/VendorPanelOverview.md)
