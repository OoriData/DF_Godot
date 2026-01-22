extends RefCounted
class_name VendorPanelVehicleSellController

const ItemsData = preload("res://Scripts/Data/Items.gd")

# SELL-mode list shaping extracted from vendor_trade_panel.gd.
# Owns the logic for whether Vehicles should be shown and how to inject sellable vehicles into convoy aggregation.

static func _vendor_has_vehicle_parts(panel: Object) -> bool:
	# 1) Aggregated vendor_items 'parts' bucket
	if panel.vendor_items is Dictionary:
		# Case-insensitive check for a non-empty parts bucket
		var vi: Dictionary = panel.vendor_items
		if vi.has("parts") and vi["parts"] is Dictionary and not (vi["parts"] as Dictionary).is_empty():
			return true
		if vi.has("Parts") and vi["Parts"] is Dictionary and not (vi["Parts"] as Dictionary).is_empty():
			return true

	# 2) Use Items.gd classifier on raw vendor_data inventory
	if panel.vendor_data and (panel.vendor_data is Dictionary) and (panel.vendor_data as Dictionary).has("cargo_inventory"):
		var inv_any: Variant = (panel.vendor_data as Dictionary).get("cargo_inventory")
		if inv_any is Array:
			for raw_any in (inv_any as Array):
				if raw_any is Dictionary and ItemsData.PartItem._looks_like_part_dict(raw_any):
					return true

	# Optional: check nested parts arrays directly (containers exposing parts)
	if panel.vendor_data and (panel.vendor_data is Dictionary) and (panel.vendor_data as Dictionary).has("cargo_inventory"):
		var inv_any2: Variant = (panel.vendor_data as Dictionary).get("cargo_inventory")
		if inv_any2 is Array:
			for raw2_any in (inv_any2 as Array):
				if not (raw2_any is Dictionary):
					continue
				var raw2: Dictionary = raw2_any
				var parts_any: Variant = raw2.get("parts")
				if parts_any is Array and not (parts_any as Array).is_empty():
					var fp_any: Variant = (parts_any as Array)[0]
					if fp_any is Dictionary:
						var fp: Dictionary = fp_any
						var slot_val: Variant = fp.get("slot")
						if slot_val != null and str(slot_val).strip_edges() != "":
							return true

	# 3) Common explicit flags/types on vendor_data (fallbacks)
	if panel.vendor_data and (panel.vendor_data is Dictionary):
		var vd: Dictionary = panel.vendor_data
		if bool(vd.get("sells_parts", false)) or bool(vd.get("sells_vehicle_parts", false)):
			return true
		var vtype: String = str(vd.get("vendor_type", "")).to_lower()
		if vtype.findn("part") != -1:
			return true

	return false


static func should_show_vehicle_sell_category(panel: Object) -> bool:
	if str(panel.current_mode) != "sell":
		return false

	# Updated rule: only show Vehicles in SELL when the vendor actually has vehicles.
	# (If a vendor's vehicle_inventory is empty, vehicles should not show in Sell.)
	if panel.vendor_data and (panel.vendor_data is Dictionary):
		var vd: Dictionary = panel.vendor_data
		var v_inv_any: Variant = vd.get("vehicle_inventory")
		if v_inv_any is Array and not (v_inv_any as Array).is_empty():
			return true

	return false


static func convoy_items_with_sellable_vehicles(panel: Object, base_agg: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if base_agg is Dictionary:
		out = base_agg.duplicate(true)

	# Build Vehicles category from convoy_data when available
	if panel.convoy_data and (panel.convoy_data is Dictionary):
		var cd: Dictionary = panel.convoy_data
		var vlist_any: Variant = cd.get("vehicle_details_list")
		if vlist_any is Array:
			var vehicles_cat: Dictionary = {}
			for v_any in (vlist_any as Array):
				if not (v_any is Dictionary):
					continue
				var v: Dictionary = v_any
				var vid: String = str(v.get("vehicle_id", ""))
				if vid == "":
					continue
				# Each vehicle is a single-quantity sellable item
				var key: String = vid # use id to avoid name collisions
				var entry: Dictionary = {
					"item_data": v,
					"total_quantity": 1,
					"total_weight": 0.0,
					"total_volume": 0.0,
					"display_name": str(v.get("name", "Vehicle"))
				}
				vehicles_cat[key] = entry

			if not vehicles_cat.is_empty():
				out["vehicles"] = vehicles_cat

	return out
