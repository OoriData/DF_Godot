extends RefCounted
class_name VendorAuthoritativeCache

# S15-7 — keeps the authoritative /vendor/get item detail alive across /map-snapshot rebuilds.
#
# Why this exists: the vendor panel is fed from TWO sources. `/vendor/get` returns full item objects
# (computed `value`, real `unit_price`, parts); the binary `/map` snapshot carries a thin subset. The
# settlement menu re-feeds the panel from the /map snapshot on EVERY store update
# (convoy_settlement_menu.gd `_refresh_active_vendor_panel` -> `_vendor_data_for_panel`), which in a
# live session fires roughly once a second. So the authoritative payload would land, and then be
# thrown away moments later — the panel fell back to the index's numbers and stayed there.
#
# That is what shipped the "listed price is not the price you're charged" report: /map carried the
# chassis-only `base_value` and no `value`, so `VendorTradeVM.vehicle_price()` fell through to the
# cheaper key. The same seam leaves cargo with `base_price = 0` (S15-2).
#
# Storage is `static`, mirroring VendorOptimisticStock, so it survives the panel being destroyed and
# re-instantiated (tab rebuilds, orientation changes).
#
# Lives in the data layer, not under Menus/, and is FILLED BY VendorService the moment a /vendor/get
# payload arrives — not by a panel signal handler. That distinction was load-bearing: a settlement with
# several vendors has one panel instance per tab, each guarding on its own `_active_vendor_id`, so
# whether any instance recorded the payload depended on tab state. On device the response arrived and
# the cache stayed empty, leaving the buy gate stuck. Capture belongs where the data provably lands.
#
# ━━━ The one rule this module enforces ━━━
# Hydration only ever ADDS keys the incoming record is missing. It never overwrites a value the /map
# snapshot supplied. That matters: /map is the fresher source for stock counts, and the optimistic-
# stock deltas (VendorOptimisticStock) are applied downstream of this. Filling gaps is safe; taking
# sides on a field both sources carry is not.

## How long a stored payload keeps hydrating. Long enough to cover a vendor visit, short enough that
## a vendor left open in the background doesn't price against a stale snapshot forever.
const TTL_MS: int = 300000

## Stamped onto every item that came from (or was hydrated by) an authoritative payload. The buy gate
## reads this — see VendorTradeVM.is_price_authoritative(). Leading underscore marks it as a
## client-side annotation, not a server field.
const AUTHORITATIVE_FLAG: String = "_price_authoritative"

# vendor_id -> { "vehicles": {vehicle_id: Dictionary}, "cargo": {cargo_id: Dictionary}, "stamp_ms": int }
static var _by_vendor: Dictionary = {}


static func _entry_for(vendor_id: String) -> Dictionary:
	if vendor_id == "":
		return {}
	var rec: Variant = _by_vendor.get(vendor_id)
	if not (rec is Dictionary):
		return {}
	var entry: Dictionary = rec
	if Time.get_ticks_msec() - int(entry.get("stamp_ms", 0)) > TTL_MS:
		_by_vendor.erase(vendor_id)
		return {}
	return entry


## Record an authoritative /vendor/get payload. Stamps the payload's own items in place, so the
## dictionary the caller goes on to assign to `panel.vendor_data` is already marked.
static func store(vendor_data: Variant) -> void:
	if not (vendor_data is Dictionary):
		return
	var vd: Dictionary = vendor_data
	var vendor_id: String = str(vd.get("vendor_id", vd.get("id", ""))).strip_edges()
	if vendor_id == "":
		return

	var vehicles: Dictionary = {}
	for v_any in _as_array(vd.get("vehicle_inventory")):
		if not (v_any is Dictionary):
			continue
		var v: Dictionary = v_any
		var vid: String = str(v.get("vehicle_id", "")).strip_edges()
		if vid == "":
			continue
		v[AUTHORITATIVE_FLAG] = true
		vehicles[vid] = v.duplicate(true)

	var cargo: Dictionary = {}
	for c_any in _as_array(vd.get("cargo_inventory")):
		if not (c_any is Dictionary):
			continue
		var c: Dictionary = c_any
		var cid: String = str(c.get("cargo_id", c.get("part_id", ""))).strip_edges()
		if cid == "":
			continue
		c[AUTHORITATIVE_FLAG] = true
		cargo[cid] = c.duplicate(true)

	_by_vendor[vendor_id] = {
		"vehicles": vehicles,
		"cargo": cargo,
		"stamp_ms": Time.get_ticks_msec(),
	}


## Fill gaps in a (typically /map-derived) vendor payload from the last authoritative one for the same
## vendor. Returns the input unchanged when there is nothing stored, so this is safe to call on every
## refresh regardless of what arrived.
static func hydrate(vendor_data: Variant) -> Variant:
	if not (vendor_data is Dictionary):
		return vendor_data
	var vd: Dictionary = vendor_data
	var vendor_id: String = str(vd.get("vendor_id", vd.get("id", ""))).strip_edges()
	var entry: Dictionary = _entry_for(vendor_id)
	if entry.is_empty():
		return vendor_data

	var vehicles: Dictionary = entry.get("vehicles", {})
	for v_any in _as_array(vd.get("vehicle_inventory")):
		if v_any is Dictionary:
			_fill_missing(v_any, vehicles.get(str((v_any as Dictionary).get("vehicle_id", "")).strip_edges()))

	var cargo: Dictionary = entry.get("cargo", {})
	for c_any in _as_array(vd.get("cargo_inventory")):
		if c_any is Dictionary:
			var c: Dictionary = c_any
			_fill_missing(c, cargo.get(str(c.get("cargo_id", c.get("part_id", ""))).strip_edges()))

	return vd


## Copy across only the keys `target` lacks. Never overwrites — see the rule in the header comment.
static func _fill_missing(target: Dictionary, source_any: Variant) -> void:
	if not (source_any is Dictionary):
		return
	var source: Dictionary = source_any
	for k in source.keys():
		if not target.has(k):
			target[k] = source[k]


static func _as_array(v: Variant) -> Array:
	return v if v is Array else []


## True when we hold authoritative detail for this vendor. The buy gate uses this to tell "still
## loading" apart from "this vendor was never fetched".
static func has_vendor(vendor_id: String) -> bool:
	return not _entry_for(vendor_id).is_empty()


## The stored record for one item, or {} if we don't have it. Lets the panel hydrate the CURRENT
## selection without waiting for a full list rebuild — the selection holds a reference into the
## aggregated buckets, so a payload that arrives outside a refresh cycle would otherwise not reach it.
static func get_item(vendor_id: String, item_id: String) -> Dictionary:
	if item_id == "":
		return {}
	var entry: Dictionary = _entry_for(vendor_id)
	if entry.is_empty():
		return {}
	var vehicles: Dictionary = entry.get("vehicles", {})
	if vehicles.has(item_id):
		return vehicles[item_id]
	var cargo: Dictionary = entry.get("cargo", {})
	if cargo.has(item_id):
		return cargo[item_id]
	return {}


## Fill gaps in a single item dict in place, from the authoritative record for the same id.
## Missing keys only, same rule as hydrate().
static func hydrate_item(vendor_id: String, item: Dictionary) -> void:
	var item_id: String = str(item.get("vehicle_id", item.get("cargo_id", item.get("part_id", "")))).strip_edges()
	_fill_missing(item, get_item(vendor_id, item_id))


## Drop a vendor's stored detail. Call when the panel knows the vendor changed under it.
static func clear_vendor(vendor_id: String) -> void:
	if vendor_id != "":
		_by_vendor.erase(vendor_id)


## Test/teardown hook.
static func clear_all() -> void:
	_by_vendor.clear()
