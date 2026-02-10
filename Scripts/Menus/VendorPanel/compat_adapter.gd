extends Node
class_name VendorCompatAdapter

static func has_install_slot(item_data: Dictionary) -> bool:
	if item_data.has("slot") and item_data.get("slot") != null and not str(item_data.get("slot")).is_empty():
		return true
	if item_data.has("parts") and item_data.get("parts") is Array and not (item_data.get("parts") as Array).is_empty():
		var first_p = (item_data.get("parts") as Array)[0]
		if first_p is Dictionary and first_p.has("slot") and first_p.get("slot") != null and not str(first_p.get("slot")).is_empty():
			return true
	return false

static func can_show_install_button(_is_buy_mode: bool, selected_item: Variant) -> bool:
	if selected_item == null or not (selected_item is Dictionary) or not (selected_item as Dictionary).has("item_data"):
		return false
	var idata: Dictionary = (selected_item as Dictionary).item_data
	return has_install_slot(idata)

static func compat_key(vehicle_id: String, part_uid: String) -> String:
	return "%s||%s" % [vehicle_id, part_uid]

static func compat_payload_is_compatible(payload: Variant) -> bool:
	if not (payload is Dictionary):
		return false
	var pd: Dictionary = payload
	var status := int(pd.get("status", 0))
	var data_any = pd.get("data")
	if data_any is Dictionary:
		var dd: Dictionary = data_any
		if dd.has("compatible"):
			return bool(dd.get("compatible"))
		if dd.has("fitment") and dd.get("fitment") is Dictionary:
			var fit: Dictionary = dd.get("fitment")
			return bool(fit.get("compatible", false))
	elif data_any is Array and status >= 200 and status < 300:
		return (data_any as Array).size() > 0
	return false

static func extract_install_price(payload: Dictionary) -> float:
	var d = payload.get("data")
	if d is Dictionary and (d as Dictionary).has("installation_price"):
		return float((d as Dictionary).get("installation_price", 0.0))
	if d is Array and (d as Array).size() > 0 and (d[0] is Dictionary) and (d[0] as Dictionary).has("installation_price"):
		return float((d[0] as Dictionary).get("installation_price", 0.0))
	return -1.0

# Look up part modifier stats from cached compatibility payloads keyed by vehicle.
static func get_part_modifiers_from_cache(part_uid: String, convoy_data: Dictionary, compat_cache: Dictionary) -> Dictionary:
	var speed_val: Variant = null
	var eff_val: Variant = null
	var offroad_val: Variant = null
	if part_uid == "" or not (convoy_data is Dictionary):
		return {"speed": speed_val, "efficiency": eff_val, "offroad": offroad_val}
	if convoy_data.has("vehicle_details_list"):
		for v in convoy_data.vehicle_details_list:
			if not (v is Dictionary):
				continue
			var vid: String = str((v as Dictionary).get("vehicle_id", ""))
			if vid == "":
				continue
			var key := compat_key(vid, part_uid)
			if compat_cache.has(key):
				var payload: Variant = compat_cache[key]
				var d = (payload as Dictionary).get("data") if (payload is Dictionary) else null
				var pd: Dictionary = {}
				if d is Array and (d as Array).size() > 0 and (d[0] is Dictionary):
					pd = d[0]
				elif d is Dictionary:
					pd = d
				if pd.size() > 0:
					if speed_val == null and pd.has("top_speed_add") and pd["top_speed_add"] != null:
						speed_val = pd["top_speed_add"]
					if eff_val == null and pd.has("efficiency_add") and pd["efficiency_add"] != null:
						eff_val = pd["efficiency_add"]
					if offroad_val == null and pd.has("offroad_capability_add") and pd["offroad_capability_add"] != null:
						offroad_val = pd["offroad_capability_add"]
				if speed_val != null or eff_val != null or offroad_val != null:
					break
	return {"speed": speed_val, "efficiency": eff_val, "offroad": offroad_val}
