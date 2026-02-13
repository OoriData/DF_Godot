# Vendor Overview (Vendor Trade Panel)

This document explains how the **Vendor Trade Panel** works end-to-end, with an emphasis on how its subsystems interact. It is intended to be “reference grade”: when you need to modify behavior later (refresh timing, selection restore, price math, install/compat, etc.), you should be able to find the owning module, its entrypoints, what state it reads/writes, and what other systems it depends on.

Primary implementation file:
- [Scripts/Menus/vendor_trade_panel.gd](../../Scripts/Menus/vendor_trade_panel.gd)

Primary subsystem modules (controllers/builders):
- [Scripts/Menus/VendorPanel/vendor_panel_refresh_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_refresh_controller.gd)
- [Scripts/Menus/VendorPanel/vendor_panel_refresh_scheduler_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_refresh_scheduler_controller.gd)
- [Scripts/Menus/VendorPanel/vendor_panel_selection_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_selection_controller.gd)
- [Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd)
- [Scripts/Menus/VendorPanel/vendor_panel_compat_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_compat_controller.gd)
- [Scripts/Menus/VendorPanel/vendor_panel_convoy_stats_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_convoy_stats_controller.gd)
- [Scripts/Menus/VendorPanel/vendor_panel_context_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_context_controller.gd)
- [Scripts/Menus/VendorPanel/vendor_panel_inspector_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_inspector_controller.gd)
- [Scripts/Menus/VendorPanel/vendor_panel_vehicle_sell_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_vehicle_sell_controller.gd)
- [Scripts/Menus/VendorPanel/vendor_panel_tutorial_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_tutorial_controller.gd)
- [Scripts/Menus/VendorPanel/cargo_aggregator.gd](../../Scripts/Menus/VendorPanel/cargo_aggregator.gd)
- [Scripts/Menus/VendorPanel/tree_builder.gd](../../Scripts/Menus/VendorPanel/tree_builder.gd)
- [Scripts/Menus/VendorPanel/inspector_builder.gd](../../Scripts/Menus/VendorPanel/inspector_builder.gd)
- [Scripts/Menus/VendorPanel/vendor_trade_vm.gd](../../Scripts/Menus/VendorPanel/vendor_trade_vm.gd)
- [Scripts/Menus/VendorPanel/selection_manager.gd](../../Scripts/Menus/VendorPanel/selection_manager.gd)

Related tests:
- [Tests/test_vendor_panel_convoy_stats_controller.gd](../../Tests/test_vendor_panel_convoy_stats_controller.gd)

---

## Design goals and constraints

### “Thin panel, fat controllers”
The vendor panel script is intentionally a **wiring + state shell**. Complex logic lives in controller modules (mostly `RefCounted` with `static func`), which operate on the panel instance to preserve existing behavior (and avoid a risky architectural rewrite).

### Strict lint posture
This project treats warnings as errors in several contexts. As a result:
- Some locals must be explicitly typed.
- Some private members appear “unused” to Godot’s linter when accessed only by external controllers; the panel therefore contains small accessor/wrapper methods (e.g., `_get_*`, `_emit_*`) to establish “usage.”

### Behavioral stability over theoretical purity
The systems are decomposed, but they preserve the old semantics:
- A selection change is often deferred by one idle frame to avoid UI race conditions.
- Refresh requests are debounced and guarded to reduce selection flicker.
- Refresh processing is “atomic” (disconnect tree signals, rebuild, restore selection, reconnect) to prevent intermediate UI states.

---

## High-level mental model

The vendor panel is a UI that renders two inventories and drives trade actions:

1. **Vendor inventory tree** (left)
2. **Convoy inventory tree** (left/middle)
3. **Inspector** (middle): rich item info, fitment summary, mission destination, etc.
4. **Transaction controls** (right): quantity, max, buy/sell, install
5. **Convoy capacity + stats** (bottom/right): volume/weight bars and textual summary

Under the hood, the panel continually combines:

- **Authoritative snapshots** (from `VendorService` + `GameStore`)
- **Derived view models** (aggregation buckets, stable selection keys)
- **Optimistic projections** (transaction in-flight capacity/money projection)

### System interaction diagram (conceptual)

```
UI events (Tree select / Buy/Sell / Max / Tab)
			|
			v
vendor_trade_panel.gd  (wiring + state)
			|
			+--> VendorPanelSelectionController  (selection key, prefetch, inspector+txn refresh)
			|
			+--> VendorPanelTransactionController (max qty, optimistic projection, dispatch)
			|
			+--> VendorPanelCompatController (install button + compat cache update)
			|
			+--> VendorPanelConvoyStatsController (capacity math + bars)
			|
			+--> VendorPanelRefreshController (refresh orchestration + atomic rebuild)
			|
			+--> VendorPanelRefreshSchedulerController (debounce + watchdog)
			|
			+--> VendorPanelContextController (settlement/vendor caches)
			|
			+--> VendorPanelInspectorController + VendorInspectorBuilder (inspector UI)
			|
			+--> VendorCargoAggregator + VendorTreeBuilder (inventory trees)

External services:
- GameStore: convoy/user/settlement snapshots
- SignalHub: vendor_panel_ready, vendor_preview_ready
- VendorService: request_vendor_panel, buy/sell calls, request_vehicle
- MechanicsService: check_part_compatibility
- APICalls: part_compatibility_checked signal
```

---

## Data and terminology

### Raw snapshots
The panel’s “authoritative” data inputs are dictionaries, typically shaped like:

- `vendor_data: Dictionary`
	- `vendor_id` (string)
	- `cargo_inventory: Array[Dictionary]`
	- `vehicle_inventory: Array[Dictionary]`
	- raw resources: `fuel`, `water`, `food` and prices `fuel_price`, `water_price`, `food_price`

- `convoy_data: Dictionary`
	- `convoy_id` (string)
	- volume capacity keys: `total_cargo_capacity`, `total_free_space`
	- weight capacity keys (varying): `total_cargo_weight_capacity` / `total_weight_capacity` / `weight_capacity`
	- free weight keys (varying): `total_free_weight` / `free_weight`
	- `vehicle_details_list: Array[Dictionary]` (each includes cargo/parts arrays)
	- optionally: raw resources `fuel`, `water`, `food`

### Aggregated “row” dictionaries (tree metadata)
Both trees store **aggregated row dictionaries** in `TreeItem.metadata[0]`. These “agg entries” are the shared contract across selection/restore/transaction/inspector.

Common fields:
- `item_data: Dictionary` (the underlying “representative” dictionary for the row)
- `display_name: String` (sometimes)
- `total_quantity: int`
- `total_weight: float`
- `total_volume: float`
- `stable_key: String` (convoy aggregation only; used for stable row identity)

Some aggregations also include:
- `items: Array[Dictionary]` (for convoy aggregation where multiple stacks are grouped)
- `locations: Dictionary` (counts per vehicle name)
- `mission_vendor_name: String` (used for mission destination display)

### Selection identity keys
To avoid selection flicker and to restore selection after a refresh, selection is tracked using multiple “layers”:

- **Preferred**: `stable_key` (when present on agg data)
- Otherwise:
	- `cargo:<cargo_id>` / raw `cargo_id` for restore
	- `veh:<vehicle_id>` / raw `vehicle_id` for restore
	- `res:fuel`, `res:water`, `res:food` for bulk resources
	- `name:<item name>` fallback

The panel stores:
- `_last_selection_unique_key` (semantic unique key)
- `_last_selected_restore_id` (key used by restore selection)
- `_last_selected_tree` (“vendor” or “convoy”)

---

## Lifecycle: how the panel runs

### 1) Panel creation and wiring (`_ready`)
In [Scripts/Menus/vendor_trade_panel.gd](../../Scripts/Menus/vendor_trade_panel.gd):

- Connects UI signals:
	- `vendor_item_tree.item_selected` → `_on_vendor_item_selected`
	- `convoy_item_tree.item_selected` → `_on_convoy_item_selected`
	- `trade_mode_tab_container.tab_changed` → `_on_tab_changed`
	- `quantity_spinbox.value_changed` → `_on_quantity_changed`
	- `max_button.pressed` → `_on_max_button_pressed`
	- `action_button.pressed` → `_on_action_button_pressed`
	- `install_button.pressed` → `_on_install_button_pressed`

- Discovers services (autoloads) by path:
	- `/root/GameStore` → `_store`
	- `/root/SignalHub` → `_hub`
	- `/root/VendorService` → `_vendor_service`
	- `/root/MechanicsService` → `_mechanics_service`
	- `/root/APICalls` → `_api`

- Subscribes to “canonical sources”:
	- `SignalHub.vendor_panel_ready` and `vendor_preview_ready` (if present)
	- `APICalls.part_compatibility_checked` (if present)
	- `VendorService.vehicle_data_received` (if present)

### 2) External entrypoint: `initialize(...)`
`initialize(p_vendor_data, p_convoy_data, p_current_settlement_data, p_all_settlement_data_global)` sets the initial snapshot state and then requests an authoritative refresh.

Important details:
- It *does not* assume the passed-in data is complete or “fresh.”
- It immediately requests an authoritative refresh via `VendorPanelRefreshController.request_authoritative_refresh`.
- It performs initial tree population using the current data (so UI isn’t blank), then switches to authoritative service-driven updates.

### 3) Refresh orchestration (authoritative updates)
There are multiple possible refresh triggers:

- On open / initialize
- After buy/sell actions
- After install actions (indirect)
- When the hub emits vendor panel updates
- When a watchdog fires because expected payload didn’t arrive

All paths converge on:

1) **Request** refresh: `VendorPanelRefreshController.request_authoritative_refresh(panel, convoy_id, vendor_id)`
2) **Receive** vendor snapshot: `VendorPanelRefreshController.on_hub_vendor_panel_ready(panel, vendor_dict)`
3) **Process** when vendor and convoy contexts are both consistent: `VendorPanelRefreshController.try_process_refresh(panel)`
4) **Atomic rebuild**: `VendorPanelRefreshController.process_panel_payload_ready(panel)`

#### Why the “atomic rebuild” matters
During `process_panel_payload_ready`:
- Tree selection signals are temporarily disconnected.
- Trees are repopulated.
- Convoy stats UI is recomputed.
- Prior selection is restored (by stable key / cargo_id / vehicle_id / resource key / name fallback).
- If restore fails, inspector is cleared and buttons disabled.
- Signals are reconnected.

This avoids mid-refresh selection events firing on partially rebuilt trees.

### 4) Debounced refresh and watchdog
Some refreshes are deferred and/or retried:

- **Debounce**: a short timer prevents multiple rapid rebuilds while the user is interacting.
	- Entry: panel `_schedule_refresh()` delegates to `VendorPanelRefreshSchedulerController.schedule_refresh`.
- **Selection flicker guard**: recent selection changes cause refresh processing to defer.
	- `VendorSelectionManager.should_defer_selection(last_selection_change_ms, DATA_READY_COOLDOWN_MS)`
- **Watchdog**: if a refresh is “in flight” but no payload arrives in time, it retries once.
	- `VendorPanelRefreshSchedulerController.start_refresh_watchdog` + `on_refresh_watchdog_timeout`

---

## Inventory trees: aggregation → rendering → selection

### Aggregation (data → buckets)
Aggregation happens in [Scripts/Menus/VendorPanel/cargo_aggregator.gd](../../Scripts/Menus/VendorPanel/cargo_aggregator.gd):

- `VendorCargoAggregator.build_vendor_buckets(vendor_data, perf_log_enabled, get_vendor_name_for_recipient)`
- `VendorCargoAggregator.build_convoy_buckets(convoy_data, vendor_data, current_mode, perf_log_enabled, get_vendor_name_for_recipient, allow_vehicle_sell)`

Buckets are dictionaries with standard category keys:
- `missions`, `vehicles`, `parts`, `other`, `resources`

#### Vendor aggregation specifics
- Skips “intrinsic” parts (`intrinsic_part_id`) so they don’t show as separate inventory.
- Classifies “part cargo” via robust heuristics (slot, nested parts, flags, stat hints).
- Creates virtual rows for bulk resources from `vendor_data.fuel/water/food` (if the corresponding price exists).
- Aggregates vehicles from `vendor_data.vehicle_inventory` (keyed by vehicle_id).

#### Convoy aggregation specifics
- Traverses `convoy_data.vehicle_details_list`:
	- Cargo items are aggregated into categories.
	- Parts are aggregated into the `parts` bucket.
	- Optionally injects vehicles into a `vehicles` bucket when SELL mode + vendor supports vehicle selling.
- Creates virtual rows for bulk resources from convoy reserves, priced using the vendor’s raw resource prices.

#### Stable keys (critical for duplicates + restore)
Convoy aggregation uses `_stable_key_for_convoy_item(item)` (inside the aggregator) to produce a semantic `stable_key` used for grouping and selection restore.

This is intentionally **not** per-stack `cargo_id` in cases where multiple stacks represent the same logical item—this prevents duplicated convoy rows.

---

## Sellability rules (what a vendor will buy)

In **SELL** mode, the convoy tree only shows items that the current vendor is allowed to buy.

- **Normal cargo (non-resource-bearing)**: sellable to any vendor.
- **Bulk resources** (virtual rows like `Fuel (Bulk)`): only shown when the vendor has a **positive** `<resource>_price`.
- **Resource-bearing cargo** (containers like jerry cans / drums that have `fuel`/`water`/`food` > 0): only sellable when the vendor has a **positive price** for the contained resource type.
	- This rule is enforced both in aggregation (so the row is hidden) and in the transaction controller (so a stale selection can’t dispatch an invalid API call).

### Rendering (buckets → TreeItems)
Rendering is handled by [Scripts/Menus/VendorPanel/tree_builder.gd](../../Scripts/Menus/VendorPanel/tree_builder.gd):

- `VendorTreeBuilder.populate_category(tree, root_item, category_name, agg_dict)`
- `VendorTreeBuilder.populate_tree_vendor_rows(tree, agg)` (used by `_populate_tree_from_agg` for performance)

Key behaviors:
- Category headers are non-selectable and styled.
- Leaf rows:
	- include icon when `item_data.icon` exists
	- store the aggregated dictionary in `metadata[0]`
	- show location and mission destination tooltips when present
	- emphasize raw resources with a bold font

### Selection flow (Tree click → inspector/transaction)
Selection is *always* funneled through the selection controller.

1) User clicks a Tree row.
2) Panel handler captures selection metadata and defers actual handling:
	 - `_on_vendor_item_selected` and `_on_convoy_item_selected` do `call_deferred("_handle_new_item_selection", item)`
	 - This avoids a known UI race where the Tree can lose focus/deselect on resize in the same frame.
3) `_handle_new_item_selection(item)` delegates to:
	 - `VendorPanelSelectionController.handle_new_item_selection(panel, item)`

The selection controller:
- Computes selection identity keys (`stable_key` preferred).
- Updates panel selection tracking fields.
- Sets quantity spinbox max and value (reset to 1 only when the semantic selection changes).
- Triggers data prefetch:
	- For vehicles: `VendorService.request_vehicle(vehicle_id)` if details are shallow.
	- For mission recipients: `VendorService.request_vendor_preview(recipient_id)` if name unknown.
- Calls panel UI updates:
	- `_update_inspector()`
	- `_update_comparison()` (currently stubbed for most things)
	- `_update_transaction_panel()`
	- `_update_install_button_state()`
- For parts: triggers `MechanicsService.check_part_compatibility(vehicle_id, part_uid)` for each convoy vehicle (only if not cached).

---

## Inspector: non-vehicle vs vehicle, and segmented panels

### Inspector orchestration (panel-side)
`vendor_trade_panel.gd` owns the “when” of inspector updates:
- `_update_inspector()` is called after selection changes.
- It classifies the selected data:
	- If selection is a vehicle (`VendorTradeVM.is_vehicle_item`), it uses a dedicated vehicle path.
	- Otherwise it uses `VendorPanelInspectorController.update_non_vehicle(...)`.

### Inspector rendering (controller)
[Scripts/Menus/VendorPanel/vendor_panel_inspector_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_inspector_controller.gd) owns the middle-column content:

- `update_non_vehicle(...)`
	- Sets name, icon visibility
	- Sets up description toggle behavior
	- Suppresses the legacy “plain text fitment” panel
	- Delegates the real content construction to `VendorInspectorBuilder.rebuild_info_sections(...)`

- `update_vehicle(panel, vehicle_data)`
	- Similar description handling
	- Builds vehicle spec bbcode
	- Delegates segmented panels to `VendorInspectorBuilder.rebuild_info_sections(...)`

### Segmented info panels (builder)
[Scripts/Menus/VendorPanel/inspector_builder.gd](../../Scripts/Menus/VendorPanel/inspector_builder.gd) creates a UI container (`InfoSectionsContainer`) next to the RichTextLabel and populates it with styled `PanelContainer` sections.

The builder is where most “what do we show?” logic lives:
- Summary panel (mission destination, vehicle stats, part modifiers)
- Per-unit panel (for non-vehicle, non-part items)
- Total order panel (aggregate totals)
- Stats panel (if stats dict exists)
- Fitment panel (for parts, using compat cache)
- Locations panel (SELL mode location breakdown)

This keeps the inspector controller simple and prevents the main panel file from accumulating UI layout logic.

---

## Transaction system: max quantity, optimistic projection, dispatch

### Quantity + “Max” button
[Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd) owns Max logic.

`on_max_button_pressed(panel)`:
- In SELL mode: max is simply the selected aggregate quantity (or resource amount for bulk resources).
- In BUY mode: max is constrained by:
	- vendor stock
	- money affordability
	- remaining convoy weight capacity
	- remaining convoy volume capacity
	- vehicles are special-cased: capacity constraints are skipped

### Buy/Sell dispatch
`on_action_button_pressed(panel)`:
- Guards against double-click with `_transaction_in_progress`.
- Reads `vendor_id` and `convoy_id` from current snapshots.
- Computes unit price and total price (via `VendorTradeVM`, which wraps `PriceUtil`).
- Computes weight/volume deltas.

#### Optimistic projection
Before the server confirms the transaction, the UI projects the expected change:
- Updates money label if visible
- Calls `panel._refresh_capacity_bars(volume_delta, weight_delta)`
	- which delegates to `VendorPanelConvoyStatsController.refresh_capacity_bars`

This is why `VendorPanelConvoyStatsController` also caches `_convoy_used_*` and `_convoy_total_*` values.

#### Dispatch paths
The transaction controller dispatches to `VendorService` methods:
- Vehicles: `buy_vehicle` / `sell_vehicle`
- Bulk resources: `buy_resource` / `sell_resource`
- Cargo: `buy_cargo` / `sell_cargo`

After each dispatch, it requests an authoritative refresh (`panel._request_authoritative_refresh`).

#### Emitted signals
The panel emits outward-facing signals for other menus:
- `item_purchased(item, quantity, total_price)`
- `item_sold(item, quantity, total_price)`
- `install_requested(item, quantity, vendor_id)`

Signals are emitted via tiny wrapper methods (`_emit_item_purchased`, etc.) so controller calls count as “usage” under strict lint.

---

## Pricing and presentation: `VendorTradeVM` + `PriceUtil`

[Scripts/Menus/VendorPanel/vendor_trade_vm.gd](../../Scripts/Menus/VendorPanel/vendor_trade_vm.gd) is the panel-facing view-model utility.

Use cases:
- `VendorTradeVM.is_vehicle_item(d)`:
	- Treats dictionaries with `vehicle_id` (and not cargo/resource) as vehicles.
	- This is intentionally “relaxed” so shallow vehicle dictionaries trigger detail prefetch.
- `VendorTradeVM.contextual_unit_price(...)`:
	- Primary: `PriceUtil.get_contextual_unit_price`
	- Fallback: common keys like `unit_price`, `price`, `value` when PriceUtil cannot infer.
- `VendorTradeVM.build_price_presenter(...)`:
	- Produces bbcode for the price area and returns computed deltas (weight/volume)

Panel usage:
- `_update_transaction_panel()` calls `VendorTradeVM.build_price_presenter` and then updates capacity bars based on the returned deltas.

---

## Compatibility and install system

### Compatibility checks
When a part-like item is selected, the selection controller requests compatibility checks across all convoy vehicles:

- For each vehicle in `convoy_data.vehicle_details_list`:
	- Build key: `VendorTradeVM.compat_key(vehicle_id, part_uid)`
	- If not in `_compat_cache`, request `MechanicsService.check_part_compatibility(vehicle_id, part_uid)`

Compatibility results arrive via `APICalls.part_compatibility_checked`.

### Cache update + install price
[Scripts/Menus/VendorPanel/vendor_panel_compat_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_compat_controller.gd):

- `on_part_compatibility_ready(panel, payload)` stores:
	- raw payload into `panel._compat_cache[key]`
	- extracted install price into `panel._install_price_cache[key]` when present

### Install button state and click
- `update_install_button_state(panel)` uses `VendorTradeVM.can_show_install_button` (CompatAdapter semantics) and updates visibility/disabled state.
- `on_install_button_pressed(panel)` emits `install_requested` with the selected item.

Important: install itself is not performed by the vendor panel; it delegates to the owning menu via the signal.

---

## Convoy stats and capacity bars

This subsystem is isolated because it had historically buggy/flaky math paths.

[Scripts/Menus/VendorPanel/vendor_panel_convoy_stats_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_convoy_stats_controller.gd):

### `update_convoy_info_display(panel)`
Responsibilities:
- Compute used/total volume:
	- Uses `total_cargo_capacity` and `total_free_space`.
- Compute weight capacity + used weight with multiple fallbacks:
	- capacity keys may vary; checks a list of possible keys
	- if free weight exists, derives used weight
	- otherwise sums `vehicle_details_list[*].cargo[*].weight` and `parts[*].weight`
	- if total volume/weight capacity missing, estimates from vehicle list
- Cache results into the panel:
	- `_convoy_used_volume`, `_convoy_total_volume`, `_convoy_used_weight`, `_convoy_total_weight`
- Update the summary label and call `refresh_capacity_bars(panel, 0, 0)`.

### `refresh_capacity_bars(panel, projected_volume_delta, projected_weight_delta)`
Responsibilities:
- If total capacity is 0, hides the bar.
- Otherwise:
	- clamps projected used values into `[0, total]`
	- sets bar max/value/tooltips
	- color-codes by utilization percentage:
		- green ≤ 70%
		- yellow ≤ 90%
		- red > 90%

### Test coverage
[Tests/test_vendor_panel_convoy_stats_controller.gd](../../Tests/test_vendor_panel_convoy_stats_controller.gd) provides regression coverage for:
- missing keys behavior
- negative “free” fields producing over-capacity used values (clamped)
- weight fallback summation
- projection + color thresholds

---

## Vendor/settlement context and name resolution

[Scripts/Menus/VendorPanel/vendor_panel_context_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_context_controller.gd) centralizes “where is this vendor / what is this vendor named?” logic.

### Settlements snapshot ingestion
`set_latest_settlements_snapshot(panel, settlements)`:
- Stores the list into `_latest_settlements` and `all_settlement_data_global`.
- Builds fast lookup caches:
	- `_vendors_from_settlements_by_id`
	- `_vendor_id_to_settlement`
	- `_vendor_id_to_name`

### Vendor name resolution
`get_vendor_name_for_recipient(panel, recipient_id)`:
- First checks `_vendor_id_to_name` (including previews cached).
- Falls back to settlement-derived vendor dictionaries.
- Final fallback returns `"Unknown Vendor"`.

### Vendor preview updates
When `SignalHub.vendor_preview_ready` arrives, the panel caches vendor name via `VendorPanelContextController.cache_vendor_name`.

---

## SELL-mode vehicle category gating and injection

When selling, the convoy tree can optionally include a **Vehicles** category for selling vehicles.

[Scripts/Menus/VendorPanel/vendor_panel_vehicle_sell_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_vehicle_sell_controller.gd):

- `should_show_vehicle_sell_category(panel)`:
	- true only in SELL mode
	- requires evidence that the vendor is a “vehicle parts/vehicle dealer”
	- uses `_vendor_has_vehicle_parts(panel)` heuristics plus vendor flags/inventory

- `convoy_items_with_sellable_vehicles(panel, base_agg)`:
	- deep-ish duplicates `base_agg`
	- builds `vehicles` category from `convoy_data.vehicle_details_list`
	- uses `vehicle_id` keys to avoid name collisions

This logic is deliberately separated so BUY mode aggregation stays simple and SELL-specific behavior doesn’t leak.

---

## Tutorial helper surface

The panel exposes a small API used by tutorial/highlight code.
Those helpers are isolated in:

- [Scripts/Menus/VendorPanel/vendor_panel_tutorial_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_tutorial_controller.gd)

Functions:
- `get_action_button_node(panel)` → returns the Buy/Sell button
- `focus_buy_tab(panel)` → selects the Buy tab
- `get_vendor_item_rect_by_text_contains(panel, substr)` → traverses vendor tree and returns the global rect of a matching row

The panel keeps the same public methods (`get_action_button_node`, etc.) but delegates internally.

---

## Refresh and selection: the “don’t flicker” rules

These are the key invariants that keep UX stable.

### Selection is deferred
The selection handlers do `call_deferred("_handle_new_item_selection", item)`.

Rationale:
- Tree selection + Control resize can conflict in the same frame.
- Deferring prevents the Tree from losing focus and deselecting unexpectedly.

### Refresh processing defers if selection is fresh
`VendorPanelRefreshController.try_process_refresh` checks `VendorSelectionManager.should_defer_selection`.

If the user just selected something, the refresh will delay processing to avoid:
- rebuilding the tree mid-click
- losing selection
- changing quantity max unexpectedly

### Atomic rebuild disconnects selection signals
During `process_panel_payload_ready` the controller disconnects and reconnects tree selection signals. This prevents selection callbacks firing while we are in the middle of rebuilding.

### Restore selection uses semantic keys
Restore selection is centralized via `VendorSelectionManager.restore_selection` and panel `_matches_restore_key`.

Order of preference:
- `stable_key`
- `cargo_id` / `vehicle_id`
- `name:` fallback
- `res:` keys

This is specifically to keep convoy selection stable even if aggregation references change between refresh cycles.

---

## Debugging and extension notes

### Useful toggles
- `perf_log_enabled` on the panel enables a lot of timing and trace output.
- `show_loading_overlay` exists but is effectively non-blocking right now (overlay helpers are no-ops to avoid tutorial interaction issues).

### Where to change behavior
Common “where do I implement X?” mapping:

- “Selection should do X” → `VendorPanelSelectionController`
- “Refresh should happen earlier/later/less often” → `VendorPanelRefreshController` and `VendorPanelRefreshSchedulerController`
- “Max button or buy/sell constraints wrong” → `VendorPanelTransactionController`
- “Capacity bars/convoy stats wrong” → `VendorPanelConvoyStatsController` (and add tests)
- “Install button or compat cache wrong” → `VendorPanelCompatController` + compat adapter
- “Inspector content/layout wrong” → `VendorPanelInspectorController` + `VendorInspectorBuilder`
- “Trees show duplicates or missing categories” → `VendorCargoAggregator` + `VendorTreeBuilder`
- “Vendor/settlement name mismatch” → `VendorPanelContextController`
- “Tutorial highlight targets wrong” → `VendorPanelTutorialController`

### Adding new UI-visible item types
If a new type of cargo is introduced, update in this order:
1) classification/aggregation in `VendorCargoAggregator`
2) display rules in `VendorTreeBuilder` (if needed)
3) selection key rules in `VendorPanelSelectionController` / `_matches_restore_key`
4) price + inspector presentation in `VendorTradeVM` + `VendorInspectorBuilder`

### Testing guidance
For math-heavy or schema-tolerant logic (like convoy capacity and fallbacks), prefer adding GUT tests like [Tests/test_vendor_panel_convoy_stats_controller.gd](../../Tests/test_vendor_panel_convoy_stats_controller.gd).

---

## Change checklist

Use this section as a “pre-flight / post-flight” checklist when changing vendor panel behavior. It is biased toward catching the kinds of regressions this panel historically hit: selection flicker, duplicate rows, stale caches, and schema drift.

### Before you change anything
- Identify the owning subsystem first (see “Where to change behavior”). Avoid adding new logic to [Scripts/Menus/vendor_trade_panel.gd](../../Scripts/Menus/vendor_trade_panel.gd) unless it’s pure wiring.
- Confirm which snapshot fields you are relying on (vendor vs convoy). If you’re reading a “maybe present” key, plan a fallback.

### Refresh changes (timing, debouncing, flicker)
- Update logic in [Scripts/Menus/VendorPanel/vendor_panel_refresh_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_refresh_controller.gd) and/or [Scripts/Menus/VendorPanel/vendor_panel_refresh_scheduler_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_refresh_scheduler_controller.gd), not in the panel.
- Preserve the “atomic rebuild” sequence:
	- disconnect tree selection signals
	- rebuild trees + convoy stats
	- restore selection
	- reconnect signals
- Re-check selection deferral guards:
	- `VendorSelectionManager.should_defer_selection(...)`
	- `VendorSelectionManager.perform_refresh_guard(...)`
- If you add a new refresh trigger, ensure it converges on `request_authoritative_refresh` (don’t create a second parallel refresh path).
- Validation:
	- enable `perf_log_enabled` and confirm only one rebuild per transaction
	- verify selection does not drop during rapid buy/sell clicks

### Selection / restore changes
- All selection handling should remain in [Scripts/Menus/VendorPanel/vendor_panel_selection_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_selection_controller.gd).
- If you add a new kind of row identity:
	- extend `handle_new_item_selection` to produce a stable unique key
	- extend panel `_matches_restore_key` logic (used by restore)
	- keep restore keys backward compatible where possible (so old keys still restore)
- Validation:
	- select an item, trigger refresh (buy/sell), ensure the same row is re-selected
	- confirm quantity resets only when the semantic selection changes

### Aggregation / duplicate row changes
- Adjust bucketing/keying only in [Scripts/Menus/VendorPanel/cargo_aggregator.gd](../../Scripts/Menus/VendorPanel/cargo_aggregator.gd).
- When changing convoy aggregation, ensure grouped rows share a stable `stable_key` and that it remains deterministic across refreshes.
- If you change category placement (missions/parts/etc.), ensure [Scripts/Menus/VendorPanel/tree_builder.gd](../../Scripts/Menus/VendorPanel/tree_builder.gd) still renders it correctly and metadata contracts remain unchanged.
- Validation:
	- confirm convoy tree does not show duplicate logical items
	- confirm tooltips (locations/destination) still appear when expected

### Transaction changes (max quantity, projection, dispatch)
- Update constraints/dispatch in [Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd).
- If you modify price math, do it in [Scripts/Menus/VendorPanel/vendor_trade_vm.gd](../../Scripts/Menus/VendorPanel/vendor_trade_vm.gd) or the underlying `PriceUtil` (not in the controller).
- Preserve optimistic projection semantics:
	- set `_transaction_in_progress`
	- compute and store `_pending_tx` deltas
	- apply `_refresh_capacity_bars(...)`
	- ensure error path reverts projection (`on_api_transaction_error`)
- Validation:
	- click Buy/Sell and confirm bars move immediately, then settle after refresh
	- simulate error and confirm projection is reverted

### Compatibility / install changes
- Install visibility rules live in [Scripts/Menus/VendorPanel/vendor_panel_compat_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_compat_controller.gd) and `CompatAdapter`.
- If you change compat key semantics, update both:
	- selection-time compatibility requests (selection controller)
	- payload caching (`on_part_compatibility_ready`)
- Validation:
	- select a part; confirm compat checks fire only when not cached
	- confirm install button visibility matches Buy mode and selection type

### Convoy stats / capacity math changes
- Keep math and fallbacks in [Scripts/Menus/VendorPanel/vendor_panel_convoy_stats_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_convoy_stats_controller.gd).
- If you add new schema keys, add them as additional fallbacks (don’t remove old keys unless the backend schema is fully migrated).
- Update/extend tests in [Tests/test_vendor_panel_convoy_stats_controller.gd](../../Tests/test_vendor_panel_convoy_stats_controller.gd).
- Validation:
	- test missing keys: bars hidden and no crash
	- test over-capacity conditions: values clamp and colors match thresholds

### Inspector content changes
- Non-vehicle orchestration belongs in [Scripts/Menus/VendorPanel/vendor_panel_inspector_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_inspector_controller.gd).
- Section layout and per-type display rules belong in [Scripts/Menus/VendorPanel/inspector_builder.gd](../../Scripts/Menus/VendorPanel/inspector_builder.gd).
- Validation:
	- check vehicle vs non-vehicle paths
	- confirm fitment/compat section reflects cache contents

### Tutorial API changes
- Keep tutorial-facing methods stable in the panel, but implement details in [Scripts/Menus/VendorPanel/vendor_panel_tutorial_controller.gd](../../Scripts/Menus/VendorPanel/vendor_panel_tutorial_controller.gd).
- Validation:
	- tutorial highlight rects still resolve even when categories are collapsed


