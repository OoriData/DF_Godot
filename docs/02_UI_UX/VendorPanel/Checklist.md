---
type: ui-ux
tags:
  - layer/ui
  - kind/deep-dive
  - status/current
aliases:
  - "Maintenance Checklist"
created: 2026-05-18
updated: 2026-07-30
verified_against_code: 2026-07-30
status: current
---

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
| Optimistic vendor stock | `vendor_optimistic_stock.gd` |
| Transaction timeout / stuck buttons | `vendor_transaction_watchdog.gd` |
| Vendor **tab** create/destroy | `convoy_settlement_menu.gd` (not this panel) |

## Pre-Flight Checklist
- [ ] **Thin Panel**: Is your new logic in a controller? Keep `vendor_trade_panel.gd` for wiring only.
- [ ] **Atomic Sequence**: If you modified the refresh path, did you preserve the `Disconnect -> Rebuild -> Restore -> Reconnect` order?
- [ ] **Stable Keys**: If you changed cargo grouping, did you update the `stable_key` generation in `cargo_aggregator.gd`?
- [ ] **Typed Accessors**: Did you use `_get_*` and `_emit_*` wrappers to satisfy strict lint requirements?
- [ ] **Survives a rebuild**: Does any new state need to outlive the panel instance? The panel is created
      and freed by `ConvoySettlementMenu`. If the answer is yes, it belongs in a `static` registry
      (`vendor_optimistic_stock.gd` / `vendor_transaction_watchdog.gd`), **not** a panel member.

## Post-Flight Checklist
- [ ] **Quantity Reset**: Does the quantity spinbox only reset to 1 when you change the logical selection?
- [ ] **Math Check**: Does the "Max" button correctly account for *all* constraints (Money, Weight, Volume, and raw-resource headroom)?
- [ ] **Flicker Test**: Rapidly click Buy/Sell. Is there any unintended UI "jumping"?
- [ ] **Panel identity**: Grep the log for `[VendorPanel][DIAG] _ready instance_id=`. There must be **one
      per vendor per settlement visit** — not one per map snapshot, menu reopen, or rotation. Re-entering
      the vendor from the hub should print `settlement rebuild SKIPPED`, never a new `_ready`.
- [ ] **Successive purchases**: Buy the same item twice without leaving (e.g. 5 then 4 out of 120).
      Expect `120 -> 115` then `115 -> 111`. `115 -> 106` means the accumulated delta was applied to
      already-adjusted buckets — see [Transactions § Optimistic Projections](Transactions.md#optimistic-projections).
- [ ] **Hidden-panel error**: Tap Buy, immediately switch menus so the panel is hidden when the reply
      lands, then come back. The button must read "Buy", not a disabled "Processing…".

> **Note:** selection is *deliberately cleared* after every transaction (`show_transaction_feedback`),
> so "does the selection survive a Buy?" is currently **no** by design — tracked as **S13-15**. The
> refresh path does restore selection across a rebuild; the two disagree.

## Related

- **See also:** [VendorPanelOverview](VendorPanelOverview.md) — architecture behind these checks
- **See also:** [Lifecycle](Lifecycle.md) — the refresh order this checklist protects
