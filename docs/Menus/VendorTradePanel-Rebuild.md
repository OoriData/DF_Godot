# Vendor Trade Panel — Robust Rebuild Plan

This document outlines fixes and a structured approach to make the vendor trade panel reliable, selection-stable, and accurate for pricing and mass/volume projections.

## Goals
- Accurate pricing and projections (no zero values unless truly zero).
- Stable selection during refreshes; avoid flicker and quantity resets.
- Clean data flow through services and VM; minimal UI rebuilds.
- Clear, consistent display for Vehicles, Parts, Mission Cargo, and Resources.

## Known Issues
- Transaction mass bar shows 0 regardless of item/quantity.
- Price often displays as 0 due to missing/incorrect data wiring.
- Vehicle pricing/attributes not reliably reaching the panel; must use `vehicle.value` from `/vehicle/get`.
- Mission cargo destination not ready at view time; needs vendor recipient prefetch.

## Architecture Overview
- Panel: `Scripts/Menus/vendor_trade_panel.gd` (extends Control, not MenuBase)
- ViewModel: `Scripts/Menus/VendorPanel/vendor_trade_vm.gd`
- Services: `Scripts/System/Services/vendor_service.gd` (vendor data fetch + domain events)
- Helpers: `Scripts/Menus/VendorPanel/compat_adapter.gd` (install/compat), `price_util.gd`, `number_format.gd`, `inspector_builder.gd`, etc.

Panel subscribes lightly to store/hub events to refresh data without full rebuilds and uses VM helpers for pricing and presentation. Transaction outcomes should trigger debounced authoritative refreshes via services.

## Data Contracts and Prefetch
- Vehicles:
  - Source: `/vehicle/get` → Vehicle object must include `value` and attributes (speed, efficiency, offroad, weight_capacity, volume_capacity).
  - Panel must resolve vehicle details by `vehicle_id` for items flagged as vehicles (see VM `is_vehicle_item()`).
- Mission Cargo:
  - Source: `/vendor/get` by `recipient_id`. Data must be ready prior to opening settlement menu or at latest when cargo is selected in previous menu (prefetch).
- Resources (bulk and cargo):
  - Unit price via `PriceUtil.get_contextual_unit_price()` for buy/sell; resource sell price is 50% (non-vehicle only) as per VM.

## Display Specifications

### Vehicles
- Summary: speed, efficiency, offroad, weight capacity, volume capacity.
- Pricing: use `vehicle.value` from `/vehicle/get`.

### Parts
- Summary: speed/efficiency/offroad modifiers (from part payload/modifiers).
- Pricing: part `value`/price.

### Mission Cargo
- Prefetch recipient vendor via `/vendor/get` using cargo’s `recipient_id`.
- Summary: destination (vendor name), quantity, unit + total weight, unit + total volume.
- Pricing: unit + total delivery reward, unit + total cost (contextual price).

### Resource Bulk
- Summary: quantity.
- Pricing: buy price (unit + total).

### Resource Cargo (e.g., MRE boxes)
- Summary: contained resource quantity.
- Pricing: item price (unit + total).

## Pricing Rules (VM-driven)
- Vehicles: unit price = `vehicle.value`.
- Non-vehicles: unit price = contextual; in sell mode, halve non-vehicle price.
- Total price = unit × quantity.
- Delivery reward fields: include when present on item source.
- Formatting via `NumberFormat.format_money()`.

## Mass/Volume Projection and Bars
- VM `build_price_presenter()` computes `added_weight`/`added_volume` from `unit_weight`/`unit_volume` or derived from `weight/quantity` and `volume/quantity`.
- Sell mode: projections are negative (removing cargo).
- Panel must:
  - Read convoy’s `used_weight/total_weight` and `used_volume/total_volume` from store snapshot.
  - Update bars with `current + added` values for the active quantity.
  - Disable or gray-out bars when unit metrics unavailable.

## Event Wiring and Refresh Strategy
- Listen to `SignalHub.vendor_updated`, `SignalHub.vendor_panel_ready` for vendor payload updates.
- Listen to `GameStore.convoys_changed` for convoy stat snapshots.
- On transaction completion: debounce and request authoritative refresh via `VendorService`.
- Preserve selection:
  - Track `_last_selected_tree`, `_last_selected_restore_id`, `_last_selection_unique_key`.
  - After refresh, re-select matching item and restore quantity.

## Caching and Compatibility
- Compat cache for vehicle+part payloads to avoid repeated checks.
- Optional install price cache keyed by vehicle||part.
- VM and panel should use `CompatAdapter` for `can_show_install_button()` and payload extraction.

## Testing (GUT)
- Price math: unit/total, sell halving, vehicle.value usage.
- Aggregation: tree builder categories, mission cargo details.
- Selection restore: after vendor refresh and store changes.
- Compatibility decisions: install button visibility and payload correctness.
- Mass/volume projections: non-zero values for items with metrics; correct sign in sell mode.

---

## Implementation Checklist

### Phase 1 — Pricing + Mass/Volume Fixes
- [x] Wire panel to use VM `build_price_presenter()` exclusively for price/mass/volume.
- [x] Ensure non-vehicle sell mode halves price; vehicles unaffected.
- [x] Read convoy stats from store and update bars with `added_weight/added_volume`.
- [x] Show placeholders when unit metrics unavailable; avoid showing 0 unless truly zero.
- [x] Add GUT tests for mass/volume projection and zero-value guards.

### Phase 2 — Vehicles Data Pipeline
- [x] On selecting a vehicle item, request `/vehicle/get` via `APICalls` routed through `VendorService`.
- [x] Cache resolved vehicle object by `vehicle_id`; enrich item data source for VM.
- [x] Display vehicle attributes: speed, efficiency, offroad, weight capacity, volume capacity.
- [x] Price from `vehicle.value`.
- [x] Add GUT tests verifying price and attribute display.

### Phase 3 — Mission Cargo Prefetch
- [x] Identify mission cargo items and extract `recipient_id`.
- [x] Prefetch `/vendor/get` for recipient in previous menu or immediately on selection (with debounce).
- [x] Store recipient vendor name/id in panel state; display destination.
- [x] Compute unit/total weight/volume and delivery rewards.
- [x] Add GUT tests for destination resolution and summary/pricing correctness.

### Phase 4 — UI Stability and Refresh
- [x] Debounce authoritative refreshes after transactions.
- [x] Preserve selection and quantity across refreshes using stable keys.
- [x] Avoid full rebuilds; refresh only affected sections.
- [x] Add tests for selection stability and minimal rebuild behavior.

### Phase 5 — Formatting and Edge Cases
- [x] Ensure `NumberFormat.format_money()` is used everywhere for price/reward.
- [x] Clamp negatives in sell mode where appropriate (e.g., display positives for totals, keep sign for projections).
- [x] Handle missing fields gracefully; no crashes on nulls.

---

## File-Level Tasks

### `Scripts/Menus/vendor_trade_panel.gd`
- [x] Use VM `build_price_presenter()` for pricing/mass/volume and update `price_label`, `delivery_reward_label`, and bars.
- [x] Integrate selection-stability keys on refresh.
- [x] Trigger vehicle detail fetch and mission cargo recipient prefetch through services.

### `Scripts/Menus/VendorPanel/vendor_trade_vm.gd`
- [x] Confirm vehicle detection and pricing via `vehicle.value`.
- [x] Ensure item price components correctly expose resource vs container values.
- [x] Return complete presenter dict including `bbcode_text`, prices, and projections.

### `Scripts/System/Services/vendor_service.gd`
- [x] Add helper to request vehicle by ID and route result (if not already present in `APICalls`).
- [x] Add method to prefetch recipient vendor by ID for mission cargo.
- [x] Emit service-level events for panel updates (`vendor_panel_ready`, `vendor_preview_ready`).

### `Scripts/System/api_calls.gd`
- [x] Ensure `/vehicle/get` and `/vendor/get` requests exist and emit transport-level signals (`vendor_data_received`, plus vehicle data signal if needed).
- [x] Route results via `VendorService` to hub events.

---

## Acceptance Criteria
- Prices and rewards show correct values for all item types (vehicles, parts, mission cargo, resources).
- Mass and volume bars update based on quantity and reflect sell-mode reductions.
- Vehicle details show speed, efficiency, offroad, weight capacity, volume capacity; price uses `vehicle.value`.
- Mission cargo shows destination with unit/total weight/volume and rewards; data available without delay.
- Selection remains stable across refreshes; no UI flicker or quantity reset.

## Risks and Mitigations
- Vehicle and vendor prefetch latency → debounce selection-triggered fetches and show skeleton state.
- Incomplete data from API → fallback display with clear placeholders; log for diagnostics.
- Over-refresh causing flicker → maintain `_refresh_in_flight` and sequence IDs; limit UI updates.

## Next Steps
- Implement Phase 1 tasks and add GUT tests.
- Integrate vehicle and mission cargo prefetch paths via services.
- Iterate on UI polish and selection stability.
