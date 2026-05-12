# Maintenance Checklist

Use this guide when modifying Vendor Panel behavior to prevent common regressions (selection flicker, stale caches, math errors).

## Where to Change Behavior
| Feature | Primary File |
| :--- | :--- |
| Selection logic / Restore keys | `vendor_panel_selection_controller.gd` |
| Refresh timing / Debouncing | `vendor_panel_refresh_controller.gd` |
| Buy/Sell constraints / Max button | `vendor_panel_transaction_controller.gd` |
| Capacity math / Bar colors | `vendor_panel_convoy_stats_controller.gd` |
| Compatibility / Install rules | `vendor_panel_compat_controller.gd` |
| Inspector content / Section layout | `inspector_builder.gd` |
| Cargo grouping / Categories | `cargo_aggregator.gd` |
| Tree row visuals | `tree_builder.gd` |

## Pre-Flight Checklist
- [ ] **Thin Panel**: Is your new logic in a controller? Keep `vendor_trade_panel.gd` for wiring only.
- [ ] **Atomic Sequence**: If you modified the refresh path, did you preserve the `Disconnect -> Rebuild -> Restore -> Reconnect` order?
- [ ] **Stable Keys**: If you changed cargo grouping, did you update the `stable_key` generation in `cargo_aggregator.gd`?
- [ ] **Typed Accessors**: Did you use `_get_*` and `_emit_*` wrappers to satisfy strict lint requirements?

## Post-Flight Checklist
- [ ] **Selection Stability**: Select an item, click "Buy". Does the selection stay on the same row after the refresh?
- [ ] **Quantity Reset**: Does the quantity spinbox only reset to 1 when you change the logical selection?
- [ ] **Math Check**: Does the "Max" button correctly account for *all* constraints (Money, Weight, and Volume)?
- [ ] **Flicker Test**: Rapidly click Buy/Sell. Is there any unintended UI "jumping"?
