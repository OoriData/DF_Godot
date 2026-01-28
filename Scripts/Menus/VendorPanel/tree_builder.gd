extends Node
class_name VendorTreeBuilder

# Minimal, schema-tolerant tree population. Returns row count.
# agg: { category_name: { key: item_dict, ... }, ... }
static func populate_tree_from_agg(tree: Tree, agg: Dictionary, category_order: Array = []) -> int:
	if not is_instance_valid(tree):
		return 0
	tree.clear()
	var root = tree.create_item()
	if agg == null or agg.is_empty():
		return 0
	var cats = category_order.duplicate()
	if cats.is_empty():
		cats = agg.keys()
	var total_rows = 0
	for cat in cats:
		if not agg.has(cat):
			continue
		var bucket = agg[cat]
		if not (bucket is Dictionary):
			continue
		var cat_item = tree.create_item(root)
		cat_item.set_text(0, _title_case(str(cat)))
		for key in bucket.keys():
			var entry = bucket[key]
			var row = tree.create_item(cat_item)
			var row_name = _display_name(entry)
			row.set_text(0, row_name)
			# Optional columns if present
			if entry is Dictionary:
				if entry.has("quantity"):
					row.set_text(1, str(entry.quantity))
				if entry.has("price") and (entry.price is float or entry.price is int):
					row.set_text(2, str(entry.price))
			total_rows += 1
	return total_rows

# Prepare a display-friendly aggregation map and re-bucket parts that may have landed in 'other'.
# Returns a deep-ish copy safe for UI consumption without mutating the source.
static func make_display_agg_with_parts_rebucket(agg: Dictionary) -> Dictionary:
	var display_agg: Dictionary = {}
	if agg == null:
		return display_agg
	# Ensure buckets
	for cat in ["missions", "vehicles", "parts", "other", "resources"]:
		display_agg[cat] = {}
	# Shallow-copy entries into display buckets
	for cat in agg.keys():
		if agg[cat] is Dictionary:
			for k in agg[cat].keys():
				display_agg[cat][k] = agg[cat][k]
	# Move any 'other' entries that look like parts into 'parts'
	if display_agg.has("other") and (display_agg["other"] is Dictionary):
		var move_keys: Array = []
		for k in display_agg["other"].keys():
			var entry = display_agg["other"][k]
			if entry is Dictionary and entry.has("item_data") and (entry.item_data is Dictionary):
				var slot_text := ""
				if entry.item_data.has("slot") and entry.item_data.get("slot") != null:
					slot_text = str(entry.item_data.get("slot"))
				elif entry.item_data.has("parts") and (entry.item_data.get("parts") is Array) and not (entry.item_data.get("parts") as Array).is_empty():
					var nested_first: Dictionary = (entry.item_data.get("parts") as Array)[0]
					if nested_first.has("slot") and nested_first.get("slot") != null:
						slot_text = str(nested_first.get("slot"))
				if not slot_text.is_empty():
					display_agg["other"][k].item_data["slot"] = slot_text
					move_keys.append(k)
		if not move_keys.is_empty():
			for mk in move_keys:
				display_agg["parts"][mk] = display_agg["other"][mk]
				display_agg["other"].erase(mk)
	return display_agg

# Vendor panel specific rendering: preserves metadata, icons, simple resource emphasis, and category order.
# Returns number of leaf rows created.
static func populate_tree_vendor_rows(tree: Tree, agg: Dictionary) -> int:
	if not is_instance_valid(tree):
		return 0
	tree.clear()
	var root = tree.create_item()
	var display_agg: Dictionary = make_display_agg_with_parts_rebucket(agg)
	var total_rows := 0
	for category in ["missions", "vehicles", "parts", "other", "resources"]:
		if not display_agg.has(category):
			continue
		var bucket = display_agg[category]
		if not (bucket is Dictionary) or (bucket as Dictionary).is_empty():
			continue
		var category_item = tree.create_item(root)
		category_item.set_text(0, _title_case(str(category)))
		category_item.set_selectable(0, false)
		category_item.set_custom_color(0, Color.GOLD)
		for item_key in bucket.keys():
			var agg_data = bucket[item_key]
			var display_qty = agg_data.total_quantity if (agg_data is Dictionary and agg_data.has("total_quantity")) else 0
			# For raw resources, prefer the largest explicit resource amount for the quantity preview
			if category == "resources" and agg_data is Dictionary and (agg_data as Dictionary).has("item_data") and (agg_data.item_data is Dictionary) and agg_data.item_data.get("is_raw_resource", false):
				var res_qty := 0
				if (agg_data.has("total_fuel") and (agg_data.total_fuel is float or agg_data.total_fuel is int)) and int(agg_data.total_fuel) > res_qty:
					res_qty = int(agg_data.total_fuel)
				if (agg_data.has("total_water") and (agg_data.total_water is float or agg_data.total_water is int)) and int(agg_data.total_water) > res_qty:
					res_qty = int(agg_data.total_water)
				if (agg_data.has("total_food") and (agg_data.total_food is float or agg_data.total_food is int)) and int(agg_data.total_food) > res_qty:
					res_qty = int(agg_data.total_food)
				if res_qty > display_qty:
					display_qty = res_qty
			var display_name: String = str(item_key)
			if agg_data is Dictionary and agg_data.has("item_data") and (agg_data.item_data is Dictionary):
				var n = agg_data.item_data.get("name")
				if n is String and not n.is_empty():
					display_name = n
			var row_item = tree.create_item(category_item)
			row_item.set_text(0, display_name)
			row_item.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD)
			# Bold for raw resources to match panel emphasis
			if category == "resources" and agg_data is Dictionary and agg_data.has("item_data") and (agg_data.item_data is Dictionary) and agg_data.item_data.get("is_raw_resource", false):
				var bold_font = _get_bold_font_for_tree(tree)
				if bold_font != null:
					row_item.set_custom_font(0, bold_font)
			# Optional icon and metadata
			if agg_data is Dictionary and agg_data.has("item_data") and (agg_data.item_data is Dictionary) and agg_data.item_data.has("icon"):
				var item_icon = agg_data.item_data.get("icon")
				if item_icon:
					row_item.set_icon(0, item_icon)
			row_item.set_metadata(0, agg_data)
			total_rows += 1
	return total_rows

static func _get_bold_font_for_tree(node: Control) -> FontVariation:
	var default_font = node.get_theme_font("font") if is_instance_valid(node) else null
	if default_font:
		var bf = FontVariation.new()
		bf.set_base_font(default_font)
		bf.set_variation_embolden(1.0)
		return bf
	return null

# Helper: count columns with panel-compatible defaulting.
static func _tree_column_count(tree: Tree) -> int:
	if not is_instance_valid(tree):
		return 1
	if tree.has_meta("cols"):
		var v = tree.get_meta("cols")
		if v is int:
			return int(v)
	return 1

static func _normalize_category_title(category_name: String) -> String:
	var title := category_name
	var _lc := str(category_name).to_lower()
	if _lc == "parts":
		title = "Part Cargo"
	elif _lc == "resources":
		title = "Resource Cargo"
	elif _lc == "other":
		title = "Other Cargo"
	return title

# Populate a single category section mirroring panel styling and metadata.
static func populate_category(target_tree: Tree, root_item: TreeItem, category_name: String, agg_dict: Dictionary) -> void:
	if agg_dict == null or agg_dict.is_empty():
		return
	var title := _normalize_category_title(category_name)
	var _lc := str(category_name).to_lower()
	var category_item = target_tree.create_item(root_item)
	category_item.set_text(0, title)
	category_item.set_selectable(0, false)
	category_item.set_custom_color(0, Color.GOLD)
	# Header-like background
	var header_bg := Color(0.2, 0.22, 0.28, 1.0)
	var _cols_header: int = _tree_column_count(target_tree)
	for c in range(_cols_header):
		category_item.set_custom_bg_color(c, header_bg)

	# Sort rows by display name (case-insensitive)
	var rows: Array = []
	for agg_key in agg_dict.keys():
		var agg_data = agg_dict[agg_key]
		var dn: String = ""
		if agg_data is Dictionary and agg_data.has("display_name"):
			dn = str(agg_data.get("display_name"))
		elif agg_data is Dictionary and agg_data.has("item_data") and (agg_data.item_data is Dictionary) and agg_data.item_data.has("name"):
			dn = str(agg_data.item_data.get("name"))
		else:
			dn = str(agg_key)
		rows.append({"key": agg_key, "data": agg_data, "dn": dn, "sort": dn.to_lower()})
	rows.sort_custom(func(a, b): return a["sort"] < b["sort"])

	var row_index: int = 0
	for row in rows:
		var agg_data = row["data"]
		var display_name: String = row["dn"]
		var tree_child_item = target_tree.create_item(category_item)
		tree_child_item.set_text(0, display_name)
		tree_child_item.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD)

		# Emphasis for raw resources
		if agg_data is Dictionary and agg_data.has("item_data") and (agg_data.item_data is Dictionary) and agg_data.item_data.get("is_raw_resource", false):
			var bold_font = _get_bold_font_for_tree(target_tree)
			if bold_font != null:
				tree_child_item.set_custom_font(0, bold_font)

		# Icon & metadata
		if agg_data is Dictionary and agg_data.has("item_data") and (agg_data.item_data is Dictionary) and agg_data.item_data.has("icon"):
			var item_icon = agg_data.item_data.get("icon")
			if item_icon:
				tree_child_item.set_icon(0, item_icon)
		tree_child_item.set_metadata(0, agg_data)

		# Tooltip with mission/vendor and locations
		var tooltip_lines: Array = []
		if agg_data is Dictionary:
			var dd: Dictionary = agg_data
			if dd.has("mission_vendor_name") and str(dd.get("mission_vendor_name", "")) != "":
				tooltip_lines.append("Destination: " + str(dd.get("mission_vendor_name")))
			if dd.has("locations") and dd["locations"] is Dictionary and (dd["locations"] as Dictionary).size() > 0:
				var loc_parts: Array = []
				for loc in (dd["locations"] as Dictionary).keys():
					loc_parts.append(str(loc) + ": " + str((dd["locations"] as Dictionary)[loc]))
				tooltip_lines.append("Locations: " + ", ".join(loc_parts))
		if tooltip_lines.size() > 0:
			tree_child_item.set_tooltip_text(0, "\n".join(tooltip_lines))

		# Optional numeric columns
		var cols: int = _tree_column_count(target_tree)
		var qty: Variant = null
		var wt: Variant = null
		var vol: Variant = null
		if agg_data is Dictionary:
			if (agg_data as Dictionary).has("total_quantity"):
				qty = (agg_data as Dictionary).get("total_quantity")
			if (agg_data as Dictionary).has("total_weight"):
				wt = (agg_data as Dictionary).get("total_weight")
			if (agg_data as Dictionary).has("total_volume"):
				vol = (agg_data as Dictionary).get("total_volume")
		if cols > 1:
			tree_child_item.set_text(1, NumberFormat.fmt_qty(qty))
			target_tree.set_column_expand(1, false)
			target_tree.set_column_custom_minimum_width(1, 60)
		if cols > 2:
			var wt_str: String = ""
			if wt != null:
				wt_str = NumberFormat.fmt_float(wt, 2)
			tree_child_item.set_text(2, wt_str)
			target_tree.set_column_expand(2, false)
			target_tree.set_column_custom_minimum_width(2, 70)
		if cols > 3:
			var vol_str: String = ""
			if vol != null:
				vol_str = NumberFormat.fmt_float(vol, 2)
			tree_child_item.set_text(3, vol_str)
			target_tree.set_column_expand(3, false)
			target_tree.set_column_custom_minimum_width(3, 70)

		# Alternating row backgrounds and subtle badge colors
		var alt_bg_a := Color(0.15, 0.16, 0.20, 0.40)
		var alt_bg_b := Color(0.10, 0.11, 0.14, 0.20)
		var row_bg := alt_bg_a if (row_index % 2 == 0) else alt_bg_b
		for c in range(cols):
			row_item_set_bg(tree_child_item, c, row_bg)
		if cols > 1 and qty != null and int(qty) > 0:
			tree_child_item.set_custom_color(1, Color(0.95, 0.95, 1.0, 0.95))
		if cols > 2 and wt != null:
			tree_child_item.set_custom_color(2, Color(0.85, 0.95, 0.90, 0.95))
		if cols > 3 and vol != null:
			tree_child_item.set_custom_color(3, Color(0.85, 0.90, 1.0, 0.95))
		row_index += 1

static func row_item_set_bg(item: TreeItem, column: int, color: Color) -> void:
	if is_instance_valid(item):
		item.set_custom_bg_color(column, color)

static func _display_name(d: Variant) -> String:
	if d is Dictionary:
		for k in ["display_name", "name", "item_name", "title", "id"]:
			if d.has(k) and str(d[k]) != "":
				return str(d[k])
	return "Item"

static func _title_case(s: String) -> String:
	if s == "":
		return s
	var parts := s.split("_")
	if parts.size() <= 1:
		parts = s.split(" ")
	var out := []
	for p in parts:
		if p.length() == 0:
			continue
		out.append(p.substr(0,1).to_upper() + p.substr(1))
	return String(" ").join(out)
