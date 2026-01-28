# VendorPanel Modules

This folder contains small, testable helpers extracted from the legacy `vendor_trade_panel.gd`.

- `number_format.gd` — formatting helpers for quantities, floats, and money.
- `price_util.gd` — price resolution for cargo/resources/vehicles; context-aware unit prices.
- `tree_builder.gd` — schema-tolerant population of `Tree` from aggregated buckets.

Next planned modules:
- `selection_manager.gd` — atomic refresh + selection restore helpers.
- `inspector_builder.gd` — segmented inspector UI assembly.
- `compat_adapter.gd` — mechanics-aligned fitment/compatibility gates.
- `vendor_trade_vm.gd` — thin view-model façade for the panel.
