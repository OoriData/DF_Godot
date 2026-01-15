extends Node
class_name VendorInspectorBuilder
const CompatAdapter = preload("res://Scripts/Menus/VendorPanel/compat_adapter.gd")

static func get_stat_value(item_data_source: Dictionary, key: String) -> Variant:
	if item_data_source.has(key) and item_data_source[key] != null:
		return item_data_source[key]
	if item_data_source.has("parts") and item_data_source.parts is Array and not item_data_source.parts.is_empty():
		var first_part: Dictionary = item_data_source.parts[0]
		if first_part.has(key) and first_part[key] != null:
			return first_part[key]
	return null

static func _make_panel(title: String, rows: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.20, 0.24, 0.9)
	sb.border_color = Color(0.45, 0.50, 0.58, 0.9)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	var hdr := Label.new()
	hdr.text = title
	hdr.add_theme_font_size_override("font_size", 16)
	hdr.modulate = Color(1.0, 0.85, 0.35, 1.0)
	vb.add_child(hdr)

	for r in rows:
		if not (r is Dictionary):
			continue
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var k := Label.new()
		k.text = str(r.get("k", ""))
		k.add_theme_font_size_override("font_size", 13)
		k.modulate = Color(0.92, 0.94, 1.0, 0.95)
		k.size_flags_horizontal = Control.SIZE_FILL
		k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var v := Label.new()
		v.text = str(r.get("v", ""))
		v.add_theme_font_size_override("font_size", 13)
		v.modulate = Color(0.86, 0.92, 1.0, 1)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		v.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.add_child(k)
		line.add_child(v)
		vb.add_child(line)
	return panel

static func rebuild_info_sections(item_info_rich_text: RichTextLabel, item_data_source: Dictionary, selected_item: Variant, current_mode: String, convoy_data: Dictionary, compat_cache: Dictionary) -> void:
	var parent_node: Node = null
	if is_instance_valid(item_info_rich_text):
		parent_node = item_info_rich_text.get_parent()
	if not is_instance_valid(parent_node):
		return
	var container: Node = parent_node.get_node_or_null("InfoSectionsContainer")
	if container == null:
		container = VBoxContainer.new()
		container.name = "InfoSectionsContainer"
		container.add_theme_constant_override("separation", 6)
		parent_node.add_child(container)
		var idx: int = parent_node.get_children().find(item_info_rich_text)
		if idx != -1:
			parent_node.move_child(container, idx + 1)

	for ch in container.get_children():
		ch.queue_free()

	var rows_summary: Array = []
	print("[Inspector] item_data_source:", item_data_source)
	var is_vehicle := VendorTradeVM.is_vehicle_item(item_data_source)
	var is_part := _looks_like_part(item_data_source)
	print("[Inspector] is_part:", is_part, "is_vehicle:", is_vehicle)

	if selected_item and (selected_item is Dictionary) and (selected_item as Dictionary).has("mission_vendor_name") and str((selected_item as Dictionary).mission_vendor_name) != "":
		rows_summary.append({"k": "Destination", "v": str((selected_item as Dictionary).mission_vendor_name)})

	if is_vehicle:
		var stat_map = {
			"top_speed": "Top Speed",
			"fuel_efficiency": "Efficiency",
			"offroad_capability": "Off-road",
			"weight_capacity": "Weight Capacity",
			"cargo_capacity": "Volume Capacity"
		}
		var unit_map = {
			"top_speed": "",
			"fuel_efficiency": "",
			"offroad_capability": "",
			"weight_capacity": "kg",
			"cargo_capacity": "m³"
		}
		for key in stat_map:
			var v: Variant = null
			# Vehicle payloads commonly use base_* keys.
			match key:
				"top_speed":
					v = item_data_source.get("top_speed", item_data_source.get("base_top_speed"))
				"fuel_efficiency":
					v = item_data_source.get("fuel_efficiency", item_data_source.get("base_fuel_efficiency"))
					if v == null:
						v = item_data_source.get("efficiency")
				"offroad_capability":
					v = item_data_source.get("offroad_capability", item_data_source.get("base_offroad_capability"))
				"weight_capacity":
					v = item_data_source.get("weight_capacity", item_data_source.get("base_weight_capacity"))
				"cargo_capacity":
					v = item_data_source.get("cargo_capacity", item_data_source.get("base_cargo_capacity"))
				_:
					v = item_data_source.get(key)
			if v != null:
				var unit = unit_map.get(key, "")
				var val_str: String
				if v is float or v is int:
					val_str = str(int(round(float(v))))
				else:
					val_str = str(v)
				if not str(unit).is_empty():
					val_str += " " + unit
				rows_summary.append({"k": stat_map[key], "v": val_str})
	elif is_part:
		# Show capacity/resource-related part modifiers from top-level or first part in parts array.
		var stat_fields = [
			{"key": "weight_capacity_add", "label": "Weight Capacity", "unit": "kg"},
			{"key": "cargo_capacity_add", "label": "Volume Capacity", "unit": "m³"},
			{"key": "fuel_capacity", "label": "Fuel Capacity", "unit": "L"},
			{"key": "water_capacity", "label": "Water Capacity", "unit": "L"}
		]
		for field in stat_fields:
			var v = get_stat_value(item_data_source, field.key)
			print("[Inspector] Checking field:", field.key, "value:", v)
			if v != null and (v is float or v is int):
				var f = float(v)
				var s = NumberFormat.fmt_float(f, 2)
				if f > 0.0:
					s = "+" + s
				elif f < 0.0:
					s = s
				else:
					s = "0"
				if field.unit != "":
					s += " " + field.unit
				rows_summary.append({"k": field.label, "v": s})

		# For engine-type parts, show kw and nm if present (from top-level or first part)
		var engine_fields = [
			{"key": "kw", "label": "Power", "unit": "kW"},
			{"key": "nm", "label": "Torque", "unit": "Nm"}
		]
		for field in engine_fields:
			var v_engine = get_stat_value(item_data_source, field.key)
			if v_engine != null and (v_engine is float or v_engine is int):
				var s_engine = str(int(round(float(v_engine))))
				rows_summary.append({"k": field.label, "v": s_engine})

		# Core driving stats (Speed/Efficiency/Off-road) from compatibility/part modifiers.
		var part_mods: Dictionary = _get_part_modifiers(item_data_source, convoy_data, compat_cache)
		var core_fields = [
			{"key": "speed", "label": "Top Speed", "unit": ""},
			{"key": "efficiency", "label": "Efficiency", "unit": ""},
			{"key": "offroad", "label": "Off-road", "unit": ""}
		]
		for field in core_fields:
			if part_mods.has(field.key):
				var mv = part_mods[field.key]
				if mv != null and (mv is float or mv is int):
					var f_core = float(mv)
					if f_core == 0.0:
						continue
					var s_core = str(int(round(f_core)))
					if f_core > 0.0:
						s_core = "+" + s_core
					rows_summary.append({"k": field.label, "v": s_core})

		# Also show any additional stats in the nested stats dictionary, skipping the above
		if item_data_source.has("stats") and item_data_source.stats is Dictionary and not item_data_source.stats.is_empty():
			var skip := ["top_speed_add", "speed_add", "top_speed_mod", "top_speed_modifier", "efficiency_add", "fuel_efficiency_add", "efficiency_mod", "efficiency_modifier", "offroad_capability_add", "offroad_add", "offroad_mod", "offroad_capability_modifier", "kw", "nm", "speed", "efficiency", "offroad"]
			var shown := 0
			for stat_name in item_data_source.stats:
				if skip.has(str(stat_name)):
					continue
				rows_summary.append({"k": str(stat_name).capitalize(), "v": str(item_data_source.stats[stat_name])})
				shown += 1
				if shown >= 6:
					break
	elif selected_item and (selected_item is Dictionary):
		var total_quantity_hdr: int = int((selected_item as Dictionary).get("total_quantity", 0))
		if total_quantity_hdr > 0:
			rows_summary.append({"k": "Quantity", "v": NumberFormat.format_number(total_quantity_hdr)})

	if rows_summary.size() > 0:
		container.add_child(_make_panel("Summary", rows_summary))

	# Vehicles: show pricing/value in its own stylized block.
	if is_vehicle:
		var rows_price: Array = []
		var v_price: float = VendorTradeVM.vehicle_price(item_data_source)
		if v_price > 0.0:
			rows_price.append({"k": "Value", "v": NumberFormat.format_money(v_price)})
		if rows_price.size() > 0:
			container.add_child(_make_panel("Pricing", rows_price))

	# Show pricing/weight/volume per unit for parts too (they're transactional items).
	if not is_vehicle:
		var rows_unit: Array = []
		var contextual_unit_price: float = VendorTradeVM.contextual_unit_price(item_data_source, str(current_mode))
		var price_label_text := "Unit Price"
		if str(current_mode) == "sell":
			price_label_text = "Sell Price"
		elif str(current_mode) == "buy":
			price_label_text = "Buy Price"
		if contextual_unit_price > 0.0:
			rows_unit.append({"k": price_label_text, "v": "$" + NumberFormat.fmt_float(contextual_unit_price, 2)})
		var unit_weight := 0.0
		if selected_item and (selected_item is Dictionary):
			var tq: int = int((selected_item as Dictionary).get("total_quantity", 0))
			var tw: float = float((selected_item as Dictionary).get("total_weight", 0.0))
			if tq > 0 and tw > 0.0:
				unit_weight = tw / float(tq)
		if unit_weight <= 0.0:
			if item_data_source.has("unit_weight") and item_data_source.get("unit_weight") != null:
				unit_weight = float(item_data_source.get("unit_weight", 0.0))
			elif item_data_source.has("weight") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 1.0)) > 0.0:
				unit_weight = float(item_data_source.get("weight", 0.0)) / float(item_data_source.get("quantity", 1.0))
		if unit_weight > 0.0:
			rows_unit.append({"k": "Weight", "v": NumberFormat.fmt_float(unit_weight, 2)})
		var unit_volume := 0.0
		if selected_item and (selected_item is Dictionary):
			var tq2: int = int((selected_item as Dictionary).get("total_quantity", 0))
			var tv: float = float((selected_item as Dictionary).get("total_volume", 0.0))
			if tq2 > 0 and tv > 0.0:
				unit_volume = tv / float(tq2)
			elif item_data_source.has("volume") and item_data_source.has("quantity") and float(item_data_source.get("quantity", 1.0)) > 0.0:
				unit_volume = float(item_data_source.get("volume", 0.0)) / float(item_data_source.get("quantity", 1.0))
		if unit_volume > 0.0:
			rows_unit.append({"k": "Volume", "v": NumberFormat.fmt_float(unit_volume, 2)})
		var unit_delivery_reward_val = item_data_source.get("unit_delivery_reward")
		if (unit_delivery_reward_val is float or unit_delivery_reward_val is int) and float(unit_delivery_reward_val) > 0.0:
			rows_unit.append({"k": "Delivery Reward", "v": "$" + NumberFormat.fmt_float(unit_delivery_reward_val, 2)})
		if rows_unit.size() > 0:
			container.add_child(_make_panel("Per Unit", rows_unit))

	var rows_total: Array = []
	if not is_vehicle and not is_part:
		var total_quantity = 0
		if selected_item and (selected_item is Dictionary):
			total_quantity = (selected_item as Dictionary).get("total_quantity", 0)
		if int(total_quantity) > 0:
			rows_total.append({"k": "Quantity", "v": NumberFormat.format_number(int(total_quantity))})
		var total_weight = 0.0
		if selected_item and (selected_item is Dictionary):
			total_weight = (selected_item as Dictionary).get("total_weight", 0.0)
		if float(total_weight) > 0.0:
			rows_total.append({"k": "Total Weight", "v": NumberFormat.fmt_float(total_weight, 2)})
		var total_volume = 0.0
		if selected_item and (selected_item is Dictionary):
			total_volume = (selected_item as Dictionary).get("total_volume", 0.0)
		if float(total_volume) > 0.0:
			rows_total.append({"k": "Total Volume", "v": NumberFormat.fmt_float(total_volume, 2)})
		var total_food = 0.0
		if selected_item and (selected_item is Dictionary):
			total_food = (selected_item as Dictionary).get("total_food", 0.0)
		if float(total_food) > 0.0:
			rows_total.append({"k": "Food", "v": NumberFormat.fmt_float(total_food, 2)})
		var total_water = 0.0
		if selected_item and (selected_item is Dictionary):
			total_water = (selected_item as Dictionary).get("total_water", 0.0)
		if float(total_water) > 0.0:
			rows_total.append({"k": "Water", "v": NumberFormat.fmt_float(total_water, 2)})
		var total_fuel = 0.0
		if selected_item and (selected_item is Dictionary):
			total_fuel = (selected_item as Dictionary).get("total_fuel", 0.0)
		if float(total_fuel) > 0.0:
			rows_total.append({"k": "Fuel", "v": NumberFormat.fmt_float(total_fuel, 2)})
	if rows_total.size() > 0:
		container.add_child(_make_panel("Total Order", rows_total))

	if item_data_source.has("stats") and item_data_source.stats is Dictionary and not item_data_source.stats.is_empty():
		var rows_stats: Array = []
		for stat_name in item_data_source.stats:
			rows_stats.append({"k": str(stat_name).capitalize(), "v": str(item_data_source.stats[stat_name])})
		container.add_child(_make_panel("Stats", rows_stats))

	if is_part:
		var rows_fit: Array = []
		var slot_name: String = ""
		if item_data_source.has("slot") and item_data_source.get("slot") != null:
			slot_name = str(item_data_source.get("slot"))
		if not slot_name.is_empty():
			rows_fit.append({"k": "Slot", "v": slot_name})
		var compat_lines: Array = []
		if convoy_data and convoy_data.has("vehicle_details_list") and convoy_data.vehicle_details_list is Array:
			var part_uid: String = ""
			if item_data_source.has("cargo_id") and item_data_source.get("cargo_id") != null:
				part_uid = str(item_data_source.get("cargo_id"))
			elif item_data_source.has("part_id") and item_data_source.get("part_id") != null:
				part_uid = str(item_data_source.get("part_id"))
			for v in convoy_data.vehicle_details_list:
				var vid: String = str(v.get("vehicle_id", ""))
				if vid == "" or part_uid == "":
					continue
				var key: String = CompatAdapter.compat_key(vid, part_uid)
				var compat_ok: bool = CompatAdapter.compat_payload_is_compatible(compat_cache.get(key, {}))
				var vname: String = v.get("name", "Vehicle")
				if compat_ok:
					compat_lines.append(vname)
		if compat_lines.size() > 0:
			rows_fit.append({"k": "Compatible Vehicles", "v": ", ".join(compat_lines)})
		if rows_fit.size() > 0:
			container.add_child(_make_panel("Fitment", rows_fit))

	if str(current_mode) == "sell" and selected_item and (selected_item is Dictionary) and (selected_item as Dictionary).has("locations"):
		var locs: Variant = (selected_item as Dictionary).get("locations")
		if locs is Dictionary and not (locs as Dictionary).is_empty():
			var rows_locs: Array = []
			for vehicle_name in (locs as Dictionary).keys():
				rows_locs.append({"k": str(vehicle_name), "v": str((locs as Dictionary)[vehicle_name])})
			container.add_child(_make_panel("Locations", rows_locs))

static func _looks_like_part(item_data_source: Dictionary) -> bool:
	# Similar heuristic as panel
	if item_data_source == null:
		return false
	if item_data_source.has("slot") and item_data_source.get("slot") != null and str(item_data_source.get("slot")).length() > 0:
		return true
	if item_data_source.has("parts") and item_data_source.get("parts") is Array and not (item_data_source.get("parts") as Array).is_empty():
		var nested_first: Dictionary = (item_data_source.get("parts") as Array)[0]
		if nested_first.has("slot") and nested_first.get("slot") != null:
			return true
	if item_data_source.has("is_part") and item_data_source.get("is_part"):
		return true
	var type_s := str(item_data_source.get("type", "")).to_lower()
	var itype_s := str(item_data_source.get("item_type", "")).to_lower()
	if type_s == "part" or itype_s == "part":
		return true
	var stat_keys := ["top_speed_add", "efficiency_add", "offroad_capability_add", "cargo_capacity_add", "weight_capacity_add", "fuel_capacity", "kwh_capacity"]
	for sk in stat_keys:
		if item_data_source.has(sk) and item_data_source[sk] != null:
			return true
		# Many payloads carry part modifiers under a nested `stats` dictionary.
		if item_data_source.has("stats") and item_data_source.stats is Dictionary and (item_data_source.stats as Dictionary).has(sk) and (item_data_source.stats as Dictionary)[sk] != null:
			return true
	return false

static func _get_part_modifiers(item_data_source: Dictionary, convoy_data: Dictionary, compat_cache: Dictionary) -> Dictionary:
	var speed_val: Variant = _get_modifier_value(item_data_source, ["top_speed_add", "speed_add", "top_speed_mod", "top_speed_modifier"]) 
	var eff_val: Variant = _get_modifier_value(item_data_source, ["efficiency_add", "fuel_efficiency_add", "efficiency_mod", "efficiency_modifier"]) 
	var offroad_val: Variant = _get_modifier_value(item_data_source, ["offroad_capability_add", "offroad_add", "offroad_mod", "offroad_capability_modifier"]) 
	if speed_val != null and eff_val != null and offroad_val != null:
		return {"speed": speed_val, "efficiency": eff_val, "offroad": offroad_val}
	var part_uid: String = str(item_data_source.get("cargo_id", item_data_source.get("part_id", "")))
	var from_cache = CompatAdapter.get_part_modifiers_from_cache(part_uid, convoy_data, compat_cache)
	return {
		"speed": speed_val if speed_val != null else from_cache.get("speed"),
		"efficiency": eff_val if eff_val != null else from_cache.get("efficiency"),
		"offroad": offroad_val if offroad_val != null else from_cache.get("offroad")
	}

static func _get_modifier_value(item_data_source: Dictionary, keys: Array) -> Variant:
	for k in keys:
		if item_data_source.has(k) and item_data_source[k] != null:
			return item_data_source[k]
		if item_data_source.has("stats") and item_data_source.stats is Dictionary and (item_data_source.stats as Dictionary).has(k):
			var v = (item_data_source.stats as Dictionary)[k]
			if v != null:
				return v
	return null
