# VendorTradePanel — Overview

Goals: keep the panel responsive, modular, and selection-stable while delegating data to services and store snapshots.

Structure (helpers live under `Scripts/Menus/VendorPanel/`):
- `price_util.gd`, `number_format.gd`, `tree_builder.gd`, `selection_manager.gd`, `inspector_builder.gd`, `compat_adapter.gd`, `vendor_trade_vm.gd`.

Contract:
- Extends `Control` (not `MenuBase`).
- Inputs: `initialize(vendor: Dictionary, convoy: Dictionary, settlement: Dictionary, all_settlements: Array)` and `refresh_data(vendor, convoy, settlement, all_settlements)`.
- Subscriptions: light listening to store/service events (e.g., `VendorService.vendor_updated`, `GameStore.convoys_changed`) to perform minimal UI refreshes that preserve selection; avoid full rebuilds on every tick.
- Emits: `purchase_completed`, `sale_completed`, and relies on `ErrorTranslator` for inline error suppression where appropriate.

Testing:
- GUT suites for price math, aggregation, selection restore, and compatibility decisions.
