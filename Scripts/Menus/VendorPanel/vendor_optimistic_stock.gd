extends RefCounted
class_name VendorOptimisticStock

# S13-5 / S13-13 — optimistic vendor-stock deltas, held OUTSIDE any panel instance.
#
# Why this exists: after a buy/sell the panel decrements the vendor row so the change is visible
# immediately, ~1s before the authoritative /vendor/get refresh lands. That edit used to live on the
# VendorTradePanel instance, so anything that destroyed and re-instantiated the panel — or merely pushed
# it a fresh /map snapshot — threw the decrement away and re-aggregated the stale server number. The
# reporter saw a 300 → 155 buy followed by a 30 sell that started from 300 again.
#
# Storage is `static`, so it survives a panel rebuild by construction. Deltas are deliberately
# short-lived: they are dropped the moment authoritative vendor data for that vendor arrives
# (clear_vendor), and expire on their own after TTL_MS so a reply that never comes cannot leave a
# vendor's numbers permanently skewed.
#
# Vendor buckets are keyed by display NAME (cargo_aggregator.gd:690) but the transaction dispatches by
# `cargo_id` (vendor_panel_transaction_controller.gd:265). We record the cargo_id and match on it first,
# falling back to the name — two different vendor rows can share a display name, and the name is also
# the only handle we have for the virtual "Fuel (Bulk)" style resource rows, which carry no cargo_id.

## How long an unconfirmed delta keeps being re-applied. Comfortably longer than a round-trip, short
## enough that a dropped reply self-heals within one vendor visit.
const TTL_MS: int = 30000

# vendor_id -> {
#   "cargo":    { key: { "cargo_id": String, "name": String, "delta": int } },
#   "vehicles": { vehicle_id: true },
#   "stamp_ms": int,
# }
static var _by_vendor: Dictionary = {}


static func _entry_for(vendor_id: String, create: bool) -> Dictionary:
	if vendor_id == "":
		return {}
	var rec: Variant = _by_vendor.get(vendor_id)
	if rec is Dictionary:
		if Time.get_ticks_msec() - int((rec as Dictionary).get("stamp_ms", 0)) > TTL_MS:
			_by_vendor.erase(vendor_id)
		else:
			return rec
	if not create:
		return {}
	var fresh: Dictionary = {"cargo": {}, "vehicles": {}, "stamp_ms": Time.get_ticks_msec()}
	_by_vendor[vendor_id] = fresh
	return fresh


## Record a stock change for a cargo row. `qty_delta` is negative for a buy, positive for a sell.
## Repeated transactions on the same row accumulate rather than replace — two buys before the refresh
## lands must both be reflected.
static func record_cargo(vendor_id: String, cargo_id: String, item_name: String, qty_delta: int) -> void:
	if vendor_id == "" or qty_delta == 0:
		return
	var rec: Dictionary = _entry_for(vendor_id, true)
	if rec.is_empty():
		return
	var key: String = cargo_id if cargo_id != "" else "name:" + item_name
	var cargo: Dictionary = rec["cargo"]
	var row: Dictionary = cargo.get(key, {"cargo_id": cargo_id, "name": item_name, "delta": 0})
	row["delta"] = int(row.get("delta", 0)) + qty_delta
	# A later transaction may carry the id when an earlier one didn't (or vice versa); keep whatever we
	# know so matching stays as precise as possible.
	if cargo_id != "":
		row["cargo_id"] = cargo_id
	if item_name != "":
		row["name"] = item_name
	cargo[key] = row
	rec["stamp_ms"] = Time.get_ticks_msec()
	print("[VendorPanel][DIAG] optimistic RECORD vendor=%s '%s' (cargo_id='%s') delta=%d total_delta=%d" % [vendor_id, item_name, cargo_id, qty_delta, int(row["delta"])])


## Record a vehicle that just left the vendor (bought). Vehicles are keyed by vehicle_id in the
## "vehicles" bucket, so they are removed outright rather than decremented.
static func record_vehicle_removed(vendor_id: String, vehicle_id: String) -> void:
	if vendor_id == "" or vehicle_id == "":
		return
	var rec: Dictionary = _entry_for(vendor_id, true)
	if rec.is_empty():
		return
	(rec["vehicles"] as Dictionary)[vehicle_id] = true
	rec["stamp_ms"] = Time.get_ticks_msec()
	print("[VendorPanel][DIAG] optimistic RECORD vendor=%s vehicle removed id=%s" % [vendor_id, vehicle_id])


## Drop every pending delta for a vendor. Call this the moment authoritative vendor data arrives — the
## server's numbers already include the transaction, so continuing to apply the delta would double it.
static func clear_vendor(vendor_id: String) -> void:
	if vendor_id == "" or not _by_vendor.has(vendor_id):
		return
	print("[VendorPanel][DIAG] optimistic CLEARED vendor=%s (authoritative data arrived)" % vendor_id)
	_by_vendor.erase(vendor_id)


static func has_pending(vendor_id: String) -> bool:
	var rec: Dictionary = _entry_for(vendor_id, false)
	if rec.is_empty():
		return false
	return not (rec["cargo"] as Dictionary).is_empty() or not (rec["vehicles"] as Dictionary).is_empty()


## Apply ONE delta to whatever the buckets currently hold. Use this — never apply_to_buckets() — right
## after a transaction, because _update_vendor_ui() re-renders the *cached* bucket set rather than
## re-aggregating: those buckets already carry every earlier delta. Applying the accumulated total there
## re-applies the whole history each time (buy 5 then 4 off 120 gave 115 then 106 instead of 111).
## Returns 1 if a row was changed, 0 if nothing matched.
static func apply_single_delta(buckets: Dictionary, cargo_id: String, item_name: String, qty_delta: int, reason: String) -> int:
	if qty_delta == 0:
		return 0
	return _apply_delta(buckets, cargo_id, item_name, qty_delta, reason)


## Re-apply every pending delta to a FRESHLY AGGREGATED bucket set — one built straight from server data,
## carrying none of our projections yet. Called from _populate_vendor_list(), the single choke point all
## refresh paths funnel through, so a rebuild off the lagging /map snapshot can no longer resurrect the
## pre-transaction number. `reason` only labels the diagnostic line.
## Returns the number of rows it changed.
static func apply_to_buckets(vendor_id: String, buckets: Dictionary, reason: String) -> int:
	var rec: Dictionary = _entry_for(vendor_id, false)
	if rec.is_empty():
		return 0
	var changed: int = 0

	var sold_vehicles: Dictionary = rec["vehicles"]
	if not sold_vehicles.is_empty():
		var vb: Variant = buckets.get("vehicles")
		if vb is Dictionary:
			for sold_id in sold_vehicles.keys():
				if (vb as Dictionary).has(sold_id):
					(vb as Dictionary).erase(sold_id)
					changed += 1
					print("[VendorPanel][DIAG] optimistic %s vendor=%s removed vehicle %s" % [reason, vendor_id, sold_id])

	for key in (rec["cargo"] as Dictionary).keys():
		var row: Dictionary = (rec["cargo"] as Dictionary)[key]
		changed += _apply_delta(buckets, str(row.get("cargo_id", "")), str(row.get("name", "")), int(row.get("delta", 0)), reason)

	return changed


## Adjust one aggregated row's quantity in place. Shared by both application modes above; the ONLY
## difference between them is which number they hand in — one increment, or the running total.
static func _apply_delta(buckets: Dictionary, cargo_id: String, item_name: String, delta: int, reason: String) -> int:
	if delta == 0:
		return 0
	var hit: Dictionary = _find_entry(buckets, cargo_id, item_name)
	if hit.is_empty():
		print("[VendorPanel][DIAG] optimistic %s MISS '%s' (cargo_id='%s') — not in any bucket" % [reason, item_name, cargo_id])
		return 0
	var entry: Dictionary = hit["entry"]
	var old_qty: int = int(entry.get("total_quantity", 0))
	var new_qty: int = maxi(0, old_qty + delta)
	entry["total_quantity"] = new_qty
	# Raw-resource rows carry their amount on item_data too, and the bulk Fuel/Water/Food rows are
	# built straight off vendor_data — keep both in step or the list and the inspector disagree.
	var item_data: Variant = entry.get("item_data")
	if item_data is Dictionary and bool((item_data as Dictionary).get("is_raw_resource", false)):
		(item_data as Dictionary)["quantity"] = new_qty
	print("[VendorPanel][DIAG] optimistic %s '%s' in bucket '%s': %d -> %d (delta=%d)" % [reason, str(hit["name"]), str(hit["bucket"]), old_qty, new_qty, delta])
	return 1


## Locate an aggregated row by cargo_id first, display name second.
## Returns {"entry": Dictionary, "bucket": String, "name": String} or {} when nothing matches.
static func _find_entry(buckets: Dictionary, cargo_id: String, item_name: String) -> Dictionary:
	var target_name: String = item_name.strip_edges()
	var name_hit: Dictionary = {}
	for bucket_key in buckets.keys():
		var bucket: Variant = buckets.get(bucket_key)
		if not (bucket is Dictionary):
			continue
		for row_key in (bucket as Dictionary).keys():
			var entry: Variant = (bucket as Dictionary)[row_key]
			if not (entry is Dictionary):
				continue
			if cargo_id != "":
				var item_data: Variant = (entry as Dictionary).get("item_data")
				if item_data is Dictionary and str((item_data as Dictionary).get("cargo_id", "")) == cargo_id:
					return {"entry": entry, "bucket": str(bucket_key), "name": str(row_key)}
			if name_hit.is_empty() and target_name != "" and str(row_key).strip_edges() == target_name:
				name_hit = {"entry": entry, "bucket": str(bucket_key), "name": str(row_key)}
	return name_hit
