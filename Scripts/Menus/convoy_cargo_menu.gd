extends Control

signal back_requested

signal return_to_convoy_overview_requested(convoy_data)
var convoy_data_received: Dictionary

@onready var title_label: Label = $MainVBox/TitleLabel
@onready var cargo_items_vbox: VBoxContainer = $MainVBox/ScrollContainer/CargoItemsVBox
@onready var back_button: Button = $MainVBox/BackButton

# Add a reference to GameDataManager
var gdm: Node = null

# Debug toggle for diagnosing missing cargo items
const CARGO_MENU_DEBUG: bool = true
const AGGREGATE_CARGO: bool = false # Set true to merge identical items

func _extract_item_display_name(item: Dictionary) -> String:
	if item.has("name") and str(item.get("name")) != "":
		return str(item.get("name"))
	if item.has("base_name") and str(item.get("base_name")) != "":
		return str(item.get("base_name"))
	if item.has("specific_name") and str(item.get("specific_name")) != "":
		return str(item.get("specific_name"))
	return "Unknown Item"

func _is_displayable_cargo(item: Dictionary) -> bool:
	# Only exclude intrinsic parts; show zero-quantity items (debug) so user knows they exist
	if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
		return false
	return true

func _ready():
	if is_instance_valid(back_button):
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed, CONNECT_ONE_SHOT)
	
	# Make the title label clickable to return to the convoy overview
	if is_instance_valid(title_label):
		title_label.mouse_filter = Control.MOUSE_FILTER_STOP # Allow it to receive mouse events
		title_label.gui_input.connect(_on_title_label_gui_input)
	else:
		printerr("ConvoyCargoMenu: BackButton node not found. Ensure it's named 'BackButton' in the scene.")

	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("convoy_data_updated", Callable(self, "_on_gdm_convoy_data_updated")):
			gdm.convoy_data_updated.connect(_on_gdm_convoy_data_updated)

# ===== Helper functions for cargo inspect UI =====
func _should_hide_key(key: String) -> bool:
	if key.is_empty():
		return true
	var hidden_exact := {
		"id": true, "uuid": true, "guid": true,
		"intrinsic_part_id": true, "template_id": true, "part_id": true,
		"convoy_id": true, "vehicle_id": true, "asset_id": true, "owner_id": true,
		"internal": true, "_internal": true, "debug": true, "_debug": true,
		"is_template": true, "is_system": true, "system": true,
		"metadata": true, "meta": true, "_meta": true,
		"created_at": true, "updated_at": true, "version": true, "schema_version": true,
		"resource_path": true, "path": true,
		# Hide verbose part breakdowns
		"parts": true, "Parts": true
	}
	if hidden_exact.has(key):
		return true
	if key.begins_with("_"):
		return true
	if key.ends_with("_id"):
		return true
	return false

func _is_positive_number(v: Variant) -> bool:
	return (v is float or v is int) and float(v) > 0.0

func _nice_key(key: String) -> String:
	return key.replace("_", " ").capitalize()

func _format_value(val) -> String:
	if val == null:
		return ""
	var t := typeof(val)
	if t == TYPE_BOOL:
		return "Yes" if val else "No"
	elif t == TYPE_ARRAY:
		var parts: Array = []
		for v in val:
			parts.append(str(v))
		return ", ".join(parts)
	elif t == TYPE_DICTIONARY:
		return "(details)"
	else:
		return str(val)

# Build a short, human-friendly stats summary.
func _format_stats_light(val) -> String:
	if val == null:
		return ""
	var parts: Array = []
	if typeof(val) == TYPE_DICTIONARY:
		var dict: Dictionary = val
		var keys := dict.keys()
		keys.sort()
		var shown := 0
		for k in keys:
			var v = dict[k]
			var seg := _format_single_stat(k, v)
			if not seg.is_empty():
				parts.append(seg)
				shown += 1
				if shown >= 6:
					break
		if parts.size() < dict.size():
			parts.append("…")
	elif typeof(val) == TYPE_ARRAY:
		var arr: Array = val
		var shown := 0
		for item in arr:
			if typeof(item) == TYPE_DICTIONARY:
				# Try to use first key/value as summary
				var d: Dictionary = item
				if d.size() > 0:
					var first_k = d.keys()[0]
					var seg := _format_single_stat(str(first_k), d[first_k])
					if not seg.is_empty():
						parts.append(seg)
			else:
				parts.append(str(item))
			shown += 1
			if shown >= 6:
				break
		if arr.size() > shown:
			parts.append("…")
	else:
		return str(val)
	return ", ".join(parts)

func _format_single_stat(key: String, v) -> String:
	if v == null:
		return ""
	var val_str := ""
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		var f := float(v)
		var sgn := "+" if f > 0 else "" # negative will include '-'
		# Trim trailing .0 for integers
		if abs(f - int(f)) < 0.00001:
			val_str = sgn + str(int(f))
		else:
			val_str = sgn + str(snapped(f, 0.01))
	else:
		val_str = str(v)
	return _nice_key(key) + " " + val_str

func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.add_theme_font_size_override("font_size", 18)
	parent.add_child(lbl)

func _add_grid(parent: VBoxContainer, data: Dictionary, keys: Array) -> int:
	# Reworked: build styled row list instead of plain grid.
	var shown := 0
	var rows_container := VBoxContainer.new()
	rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_container.add_theme_constant_override("separation", 2)

	var key_display_map := {
		"weight": "Total Weight",
		"volume": "Total Volume"
	}

	for k in keys:
		if not data.has(k):
			continue
		if _should_hide_key(k):
			continue
		var value = data[k]
		if value == null:
			continue
		# Show numeric values even if they are 0. Hide empty strings.
		if not (value is int or value is float) and str(value).is_empty():
			continue

		# Special handling for description: render as full-width wrapped paragraph.
		if k == "description":
			var desc_label := Label.new()
			desc_label.text = _format_value(value)
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			desc_label.modulate = Color(0.9, 0.9, 0.95, 1)
			rows_container.add_child(desc_label)
			shown += 1
			continue

		# Special handling for stats: build compact summary string
		if k == "stats":
			var stats_label := Label.new()
			stats_label.text = _format_stats_light(value)
			stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			stats_label.modulate = Color(0.85, 0.95, 0.9, 1)
			var line := HBoxContainer.new()
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_theme_constant_override("separation", 6)
			var k_lbl2 := Label.new()
			k_lbl2.text = _nice_key(k) + ":"
			k_lbl2.add_theme_font_size_override("font_size", 14)
			k_lbl2.modulate = Color(0.95, 0.95, 1, 0.95)
			k_lbl2.size_flags_horizontal = Control.SIZE_FILL
			k_lbl2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stats_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(k_lbl2)
			line.add_child(stats_label)
			rows_container.add_child(line)
			shown += 1
			continue

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 6)

		# Alternating row background for readability
		if shown % 2 == 0:
			var bg := ColorRect.new()
			bg.color = Color(0.15, 0.15, 0.18, 0.6)
			bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(bg)
			# We'll put content inside overlay container on top of bg
			var overlay := HBoxContainer.new()
			overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			overlay.add_theme_constant_override("separation", 6)
			row.add_child(overlay)
			row = overlay # redirect additions to overlay

		var k_lbl := Label.new()
		var key_text: String = key_display_map.get(k, _nice_key(k))
		k_lbl.text = key_text + ":"
		k_lbl.add_theme_font_size_override("font_size", 14)
		k_lbl.modulate = Color(0.95, 0.95, 1, 0.95)
		k_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var v_lbl := Label.new()
		v_lbl.text = _format_value(value)
		v_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		v_lbl.modulate = Color(0.85, 0.9, 1, 1)

		# Badge styling for notable numeric/status fields
		_apply_value_styling(k, value, v_lbl)

		row.add_child(k_lbl)
		row.add_child(v_lbl)
		rows_container.add_child(row)
		shown += 1

	if shown > 0:
		parent.add_child(rows_container)
	return shown

# Apply conditional coloring to value label based on key/value semantics.
func _apply_value_styling(key: String, value, value_label: Label) -> void:
	var numeric_val: float = -1.0
	var has_numeric := false
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		numeric_val = float(value)
		has_numeric = true
	# Quality/condition thresholds
	if key == "quality" and has_numeric:
		if numeric_val >= 80:
			value_label.modulate = Color(0.3, 0.85, 0.4, 1)
		elif numeric_val >= 50:
			value_label.modulate = Color(0.85, 0.75, 0.2, 1)
		else:
			value_label.modulate = Color(0.85, 0.35, 0.35, 1)
	elif key == "condition" and has_numeric:
		if numeric_val >= 75:
			value_label.modulate = Color(0.35, 0.8, 0.95, 1)
		elif numeric_val >= 40:
			value_label.modulate = Color(0.95, 0.6, 0.25, 1)
		else:
			value_label.modulate = Color(0.9, 0.25, 0.25, 1)
	elif key == "quantity" and has_numeric:
		value_label.modulate = Color(0.65, 0.9, 0.55, 1)

# Determine if dictionary represents a vehicle part (borrowed logic from vendor_trade_panel with omissions for hidden fields).
func _looks_like_part(d: Dictionary) -> bool:
	if not d:
		return false
	if d.get("is_raw_resource", false):
		return false
	# Exclude pure resource providers (food/water/fuel quantities) so they don't get treated as parts.
	if (d.get("food") is float or d.get("food") is int) and float(d.get("food")) > 0.0:
		return false
	if (d.get("water") is float or d.get("water") is int) and float(d.get("water")) > 0.0:
		return false
	if (d.get("fuel") is float or d.get("fuel") is int) and float(d.get("fuel")) > 0.0:
		return false
	if d.has("slot") and d.get("slot") != null and String(d.get("slot")).length() > 0:
		return true
	if d.has("intrinsic_part_id"):
		return true
	if d.has("parts") and d.get("parts") is Array and not (d.get("parts") as Array).is_empty():
		var first_p = (d.get("parts") as Array)[0]
		if first_p is Dictionary and first_p.has("slot") and first_p.get("slot") != null and String(first_p.get("slot")).length() > 0:
			return true
	if d.has("is_part") and bool(d.get("is_part")):
		return true
	return false

# Extract the dictionary that actually holds modifier keys for summary (unwrap containers).
func _extract_part_core(d: Dictionary) -> Dictionary:
	if d.has("parts") and d.get("parts") is Array and not (d.get("parts") as Array).is_empty():
		var first_p = (d.get("parts") as Array)[0]
		if first_p is Dictionary:
			return first_p
	return d

# Mirror mechanics_menu.gd _part_summary for additive and capacity keys.
func _part_summary(d: Dictionary) -> String:
	var part := _extract_part_core(d)
	var bits: Array[String] = []
	var keys = ["top_speed_add", "efficiency_add", "offroad_capability_add", "cargo_capacity_add", "weight_capacity_add"]
	var labels = {"top_speed_add": "Spd", "efficiency_add": "Eff", "offroad_capability_add": "Off", "cargo_capacity_add": "Cargo", "weight_capacity_add": "Weight"}
	for k in keys:
		var v = part.get(k, null)
		if v != null and (v is String and v.is_valid_float() or v is int or v is float) and float(v) != 0.0:
			bits.append("%s %+.0f" % [labels.get(k, k), float(v)])
	var fuel_cap = part.get("fuel_capacity")
	if fuel_cap != null and (fuel_cap is String and fuel_cap.is_valid_float() or fuel_cap is int or fuel_cap is float) and float(fuel_cap) > 0.0:
		bits.append("FuelCap %.0f" % float(fuel_cap))
	var kwh_cap = part.get("kwh_capacity")
	if kwh_cap != null and (kwh_cap is String and kwh_cap.is_valid_float() or kwh_cap is int or kwh_cap is float) and float(kwh_cap) > 0.0:
		bits.append("kWh %.0f" % float(kwh_cap))
	return "" if bits.is_empty() else "(" + ", ".join(bits) + ")"

# Build a synthetic modifiers summary dictionary entry so it can appear in overview grid.
func _inject_part_modifiers(data: Dictionary) -> void:
	if not _looks_like_part(data):
		return
	var summary := _part_summary(data)
	if summary != "":
		data["modifiers"] = summary

func _add_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.custom_minimum_size.y = 8
	parent.add_child(sep)

# Helper to build a single cargo row (raw or aggregated) with styling and inspect connection.
func _build_cargo_row(vehicle_vbox: VBoxContainer, display_name: String, quantity: int, agg_data: Dictionary, item_index: int) -> void:
	# Outer wrapper preserves full width; background applied via stylebox so children remain interactive.
	var outer_row := HBoxContainer.new()
	outer_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_row.add_theme_constant_override("separation", 0)
	outer_row.mouse_filter = Control.MOUSE_FILTER_PASS

	var item_data = agg_data.item_data_sample
	# Background panel spans full width; content placed inside.
	var bg_panel := PanelContainer.new()
	bg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create flat stylebox with alternating shade.
	var sb := StyleBoxFlat.new()
	if item_index % 2 == 0:
		sb.bg_color = Color(0.13, 0.15, 0.19, 1)
	else:
		sb.bg_color = Color(0.10, 0.12, 0.16, 1)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	sb.border_width_bottom = 1
	sb.border_color = Color(0.18, 0.20, 0.25, 1)
	bg_panel.add_theme_stylebox_override("panel", sb)

	outer_row.add_child(bg_panel)

	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 8)
	bg_panel.add_child(content_row)

	var qty_badge := Label.new()
	qty_badge.text = str(quantity)
	qty_badge.custom_minimum_size = Vector2(34, 22)
	qty_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qty_badge.add_theme_font_size_override("font_size", 14)
	if quantity >= 100:
		qty_badge.modulate = Color(0.3, 0.8, 0.4, 1)
	elif quantity >= 50:
		qty_badge.modulate = Color(0.75, 0.7, 0.25, 1)
	else:
		qty_badge.modulate = Color(0.65, 0.65, 0.7, 1)

	var item_label := Label.new()
	item_label.text = display_name
	item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_label.modulate = Color(0.9, 0.95, 1, 1)
	item_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	# Build consistent column order: Qty | ItemName(expand) | Tag | Quality | Condition | Inspect
	# Add quantity badge first
	content_row.add_child(qty_badge)
	# Item label (expands to take remaining space before fixed columns)
	content_row.add_child(item_label)

	# Tag column (category/type/subtype) with placeholder for alignment
	var tag_holder := HBoxContainer.new()
	tag_holder.custom_minimum_size = Vector2(70, 0) # reserve width
	tag_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tag_text := ""
	for tag_key in ["category", "type", "subtype"]:
		if item_data.has(tag_key) and str(item_data.get(tag_key, "")) != "":
			tag_text = str(item_data.get(tag_key))
			break
	if not tag_text.is_empty():
		var tag_label := Label.new()
		tag_label.text = tag_text
		tag_label.add_theme_font_size_override("font_size", 12)
		tag_label.modulate = Color(0.55, 0.75, 1, 1)
		tag_label.tooltip_text = "Category/Type"
		tag_holder.add_child(tag_label)
	content_row.add_child(tag_holder)

	# Quality column (or placeholder)
	var quality_holder := Control.new()
	quality_holder.custom_minimum_size = Vector2(34, 22)
	if item_data.has("quality"):
		var q_val = int(item_data.get("quality", 0))
		var q_label := Label.new()
		q_label.text = "Q" + str(q_val)
		q_label.add_theme_font_size_override("font_size", 12)
		q_label.custom_minimum_size = Vector2(34, 22)
		q_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if q_val >= 80:
			q_label.modulate = Color(0.3, 0.85, 0.45, 1)
		elif q_val >= 50:
			q_label.modulate = Color(0.85, 0.75, 0.25, 1)
		else:
			q_label.modulate = Color(0.85, 0.45, 0.35, 1)
		quality_holder.add_child(q_label)
	content_row.add_child(quality_holder)

	# Condition column (or placeholder)
	var condition_holder := Control.new()
	condition_holder.custom_minimum_size = Vector2(34, 22)
	if item_data.has("condition"):
		var c_val = int(item_data.get("condition", 0))
		var c_label := Label.new()
		c_label.text = "C" + str(c_val)
		c_label.add_theme_font_size_override("font_size", 12)
		c_label.custom_minimum_size = Vector2(34, 22)
		c_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if c_val >= 75:
			c_label.modulate = Color(0.35, 0.8, 0.95, 1)
		elif c_val >= 40:
			c_label.modulate = Color(0.95, 0.6, 0.25, 1)
		else:
			c_label.modulate = Color(0.9, 0.35, 0.3, 1)
		condition_holder.add_child(c_label)
	content_row.add_child(condition_holder)

	# Inspect button (always last)
	var inspect_button := Button.new()
	inspect_button.text = "Inspect"
	inspect_button.custom_minimum_size = Vector2(90, 26)
	inspect_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inspect_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inspect_button.pressed.connect(_on_inspect_cargo_item_pressed.bind(agg_data, vehicle_vbox, outer_row))
	content_row.add_child(inspect_button)
	vehicle_vbox.add_child(outer_row)

	# Hover highlight: lighten background stylebox only (keeps text consistent)
	outer_row.mouse_entered.connect(func():
		if sb:
			sb.bg_color = sb.bg_color.lightened(0.08)
	)
	outer_row.mouse_exited.connect(func():
		if sb:
			if item_index % 2 == 0:
				sb.bg_color = Color(0.13, 0.15, 0.19, 1)
			else:
				sb.bg_color = Color(0.10, 0.12, 0.16, 1)
	)

func _has_any_keys(data: Dictionary, keys: Array) -> bool:
	for k in keys:
		if not data.has(k):
			continue
		if _should_hide_key(k):
			continue
		var v = data[k]
		if v == null or str(v) == "":
			continue
		return true
	return false

# Creates a styled, collapsible section container (header + grid) or returns null if no visible keys.
func _create_collapsible_section(title: String, keys: Array, data_copy: Dictionary, default_open: bool = true, allow_collapse: bool = true) -> VBoxContainer:
	if not _has_any_keys(data_copy, keys):
		return null
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 2)

	# Panel wrapper for background
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 0)
	outer.add_child(panel)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_vbox.add_theme_constant_override("separation", 4)
	panel.add_child(panel_vbox)

	# Header HBox with toggle button
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var toggle_btn := Button.new()
	var initial_arrow := "▼ " if default_open else "► "
	toggle_btn.text = initial_arrow + title
	toggle_btn.flat = true
	toggle_btn.focus_mode = Control.FOCUS_NONE
	toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_btn.add_theme_font_size_override("font_size", 16)

	panel_vbox.add_child(header)
	header.add_child(toggle_btn)

	var content_box := VBoxContainer.new()
	content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_theme_constant_override("separation", 2)
	panel_vbox.add_child(content_box)

	# Populate grid
	_add_grid(content_box, data_copy, keys)
	content_box.visible = default_open

	if allow_collapse:
		toggle_btn.pressed.connect(func():
			content_box.visible = not content_box.visible
			var arrow := "▼ " if content_box.visible else "► "
			toggle_btn.text = arrow + title
		)
	else:
		# If collapse not allowed, remove arrow indicator
		toggle_btn.text = title

	return outer

func _aggregate_cargo_item(agg_dict: Dictionary, item: Dictionary) -> void:
	# Use name as aggregation key. Could be improved with a more unique ID if available.
	var agg_key = _extract_item_display_name(item)
	
	if not agg_dict.has(agg_key):
		agg_dict[agg_key] = {
			"item_data_sample": item.duplicate(true),
			"display_name": agg_key,
			"total_quantity": 0,
			"total_weight": 0.0,
			"total_volume": 0.0,
		}

	var item_quantity = int(item.get("quantity", 0))
	if item_quantity <= 0: item_quantity = 1 # Assume 1 if quantity is missing/zero for single items

	agg_dict[agg_key].total_quantity += item_quantity
	
	# Sum weight and volume. If item has total weight, use it. Otherwise calculate from unit weight.
	var item_weight = float(item.get("weight", 0.0))
	if item_weight == 0.0 and item.has("unit_weight"):
		item_weight = float(item.get("unit_weight")) * item_quantity
	agg_dict[agg_key].total_weight += item_weight

	var item_volume = float(item.get("volume", 0.0))
	if item_volume == 0.0 and item.has("unit_volume"):
		item_volume = float(item.get("unit_volume")) * item_quantity
	agg_dict[agg_key].total_volume += item_volume

func _add_category_section(parent: VBoxContainer, title: String, agg_data: Dictionary) -> int:
	if agg_data.is_empty():
		return 0

	# Add a header for the category
	var header_panel := PanelContainer.new()
	header_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0.2, 0.22, 0.28, 1)
	header_style.content_margin_left = 8
	header_style.content_margin_top = 4
	header_style.content_margin_bottom = 4
	header_panel.add_theme_stylebox_override("panel", header_style)
	
	var header_label := Label.new()
	header_label.text = title
	header_label.add_theme_font_size_override("font_size", 20)
	header_label.modulate = Color.GOLD
	header_panel.add_child(header_label)
	parent.add_child(header_panel)

	var item_index := 0
	var sorted_keys = agg_data.keys()
	sorted_keys.sort()

	for key in sorted_keys:
		var data = agg_data[key]
		_build_cargo_row(parent, data.display_name, data.total_quantity, data, item_index)
		item_index += 1
	
	return item_index

func initialize_with_data(data: Dictionary):
	# Ensure this function runs only after the node is fully ready and @onready vars are set.
	if not is_node_ready():
		printerr("ConvoyCargoMenu: initialize_with_data called BEFORE node is ready! Deferring.")
		call_deferred("initialize_with_data", data)
		return

	convoy_data_received = data.duplicate() # Duplicate to avoid modifying the original
	# print("ConvoyCargoMenu: Initialized with data: ", convoy_data_received) # DEBUG

	if is_instance_valid(title_label) and convoy_data_received.has("convoy_name"):
		title_label.text = "%s" % convoy_data_received.get("convoy_name", "Unknown Convoy")
	elif is_instance_valid(title_label):
		title_label.text = "Cargo Hold"
	
	_populate_cargo_list()

func _populate_cargo_list():
	# Diagnostic: Try to get the node directly here
	var main_vbox_node: VBoxContainer = get_node_or_null("MainVBox")
	if not is_instance_valid(main_vbox_node):
		printerr("ConvoyCargoMenu: _populate_cargo_list - MainVBox node NOT FOUND via get_node_or_null. Path: MainVBox")
		printerr("ConvoyCargoMenu: _populate_cargo_list - State of @onready var cargo_items_vbox: %s" % [cargo_items_vbox])
		return

	var scroll_container_node: ScrollContainer = main_vbox_node.get_node_or_null("ScrollContainer")
	if not is_instance_valid(scroll_container_node):
		printerr("ConvoyCargoMenu: _populate_cargo_list - ScrollContainer node NOT FOUND as child of MainVBox. Path: MainVBox/ScrollContainer")
		printerr("ConvoyCargoMenu: _populate_cargo_list - State of @onready var cargo_items_vbox: %s" % [cargo_items_vbox])
		return

	var direct_vbox_ref: VBoxContainer = scroll_container_node.get_node_or_null("CargoItemsVBox")
	if not is_instance_valid(direct_vbox_ref):
		printerr("ConvoyCargoMenu: _populate_cargo_list - CargoItemsVBox node NOT FOUND as child of ScrollContainer. Full attempted path: MainVBox/ScrollContainer/CargoItemsVBox")
		printerr("ConvoyCargoMenu: _populate_cargo_list - State of @onready var cargo_items_vbox: %s" % [cargo_items_vbox])
		return

	# Clear any previous items
	for child in direct_vbox_ref.get_children():
		child.queue_free()

	var aggregated_missions: Dictionary = {}
	var aggregated_parts: Dictionary = {}
	var aggregated_resources: Dictionary = {}
	var aggregated_other: Dictionary = {} # Fallback category

	var vehicle_details_list: Array = convoy_data_received.get("vehicle_details_list", [])
	if vehicle_details_list.is_empty():
		var no_vehicles_label := Label.new()
		no_vehicles_label.text = "No vehicles in this convoy."
		no_vehicles_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		direct_vbox_ref.add_child(no_vehicles_label)
		return

	var any_cargo_found_in_convoy := false

	for vehicle_data in vehicle_details_list:
		if not vehicle_data is Dictionary:
			printerr("ConvoyCargoMenu: Invalid vehicle_data entry.")
			continue

		var vehicle_cargo_list_raw = vehicle_data.get("cargo", [])
		var vehicle_cargo_list: Array = []
		if vehicle_cargo_list_raw is Array:
			vehicle_cargo_list = vehicle_cargo_list_raw
		elif vehicle_cargo_list_raw is Dictionary:
			vehicle_cargo_list = (vehicle_cargo_list_raw as Dictionary).values()

		for item in vehicle_cargo_list:
			if not (item is Dictionary and _is_displayable_cargo(item)):
				continue
			
			any_cargo_found_in_convoy = true
			
			# Categorize and aggregate
			if item.get("recipient") != null or item.get("delivery_reward") != null:
				_aggregate_cargo_item(aggregated_missions, item)
			elif _looks_like_part(item):
				_aggregate_cargo_item(aggregated_parts, item)
			elif (_is_positive_number(item.get("food")) or \
				  _is_positive_number(item.get("water")) or \
				  _is_positive_number(item.get("fuel"))) or \
				  item.get("is_raw_resource", false):
				_aggregate_cargo_item(aggregated_resources, item)
			else:
				_aggregate_cargo_item(aggregated_other, item)

	_add_category_section(direct_vbox_ref, "Mission Cargo", aggregated_missions)
	_add_category_section(direct_vbox_ref, "Part Cargo", aggregated_parts)
	_add_category_section(direct_vbox_ref, "Resource Cargo", aggregated_resources)
	_add_category_section(direct_vbox_ref, "Other Cargo", aggregated_other)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	direct_vbox_ref.add_child(spacer)

	if not any_cargo_found_in_convoy and not vehicle_details_list.is_empty():
		var no_cargo_overall_label := Label.new()
		no_cargo_overall_label.text = "This convoy is carrying no cargo items (only vehicle parts)."
		no_cargo_overall_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		direct_vbox_ref.add_child(no_cargo_overall_label)

func _on_back_button_pressed():
	# print("ConvoyCargoMenu: Back button pressed. Emitting 'back_requested' signal.") # DEBUG
	emit_signal("back_requested")

func _on_inspect_cargo_item_pressed(agg_data: Dictionary, list_container: VBoxContainer, item_row_hbox: HBoxContainer):
	# Prevent re-entrancy (e.g., double click during build)
	if item_row_hbox.has_meta("inspect_building"):
		return

	# If panel already shown, safely remove it deferred
	if item_row_hbox.has_meta("inspect_panel"):
		var existing_panel: Node = item_row_hbox.get_meta("inspect_panel")
		if is_instance_valid(existing_panel):
			list_container.call_deferred("remove_child", existing_panel)
			existing_panel.call_deferred("queue_free")
		item_row_hbox.remove_meta("inspect_panel")
		return

	item_row_hbox.set_meta("inspect_building", true)
	var panel := _build_inline_inspect_panel(agg_data, item_row_hbox)
	var row_index := list_container.get_children().find(item_row_hbox)
	if row_index == -1:
		list_container.add_child(panel)
	else:
		list_container.add_child(panel)
		list_container.move_child(panel, row_index + 1)
	item_row_hbox.set_meta("inspect_panel", panel)
	item_row_hbox.remove_meta("inspect_building")

func _build_inline_inspect_panel(agg_data: Dictionary, item_row_hbox: HBoxContainer) -> VBoxContainer:
	var item_data_sample: Dictionary = agg_data.item_data_sample
	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 4)

	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)

	# Header (title + hide + advanced toggle)
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_lbl := Label.new()
	title_lbl.text = "Details: %s" % item_data_sample.get("name", "Item")
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hide_btn := Button.new()
	hide_btn.text = "Hide"
	hide_btn.pressed.connect(func():
		if container.get_parent():
			container.get_parent().remove_child(container)
			container.queue_free()
		if item_row_hbox.has_meta("inspect_panel") and item_row_hbox.get_meta("inspect_panel") == container:
			item_row_hbox.remove_meta("inspect_panel")
	)

	header.add_child(title_lbl)
	header.add_child(hide_btn)
	inner.add_child(header)

	var data_copy: Dictionary = item_data_sample.duplicate(true)
	# Overwrite with aggregated data for display
	data_copy["quantity"] = agg_data.total_quantity
	data_copy["weight"] = agg_data.total_weight
	data_copy["volume"] = agg_data.total_volume

	# Ensure unit values exist for display in "Other Details"
	var f_quantity = float(data_copy.quantity)
	if not data_copy.has("unit_weight") and f_quantity > 0 and data_copy.weight > 0:
		data_copy["unit_weight"] = data_copy.weight / f_quantity
	if not data_copy.has("unit_volume") and f_quantity > 0 and data_copy.volume > 0:
		data_copy["unit_volume"] = data_copy.volume / f_quantity

	# Define primary keys dynamically (core info + description + common stats)
	var primary_keys: Array = [
		"name", "description", "quantity", "unit",
		"category", "type", "subtype",
		"water", "food", "fuel",
		"weight", "volume", "value", "quality", "condition"
	]
	# If item looks like a part, inject modifiers and surface stats dictionary summary when available.
	_inject_part_modifiers(data_copy)
	if _looks_like_part(data_copy) and data_copy.has("stats") and data_copy.get("stats") is Dictionary and not (data_copy.get("stats") as Dictionary).is_empty():
		primary_keys.append("stats")
	if data_copy.has("modifiers"):
		primary_keys.append("modifiers")

	var used: Dictionary = {}

	# Primary section
	var primary_box := VBoxContainer.new()
	primary_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary_box.add_theme_constant_override("separation", 4)
	_add_section_header(primary_box, "Item Overview")
	_add_grid(primary_box, data_copy, primary_keys)
	for k in primary_keys:
		if data_copy.has(k): used[k] = true
	inner.add_child(primary_box)

	# Other remaining keys (single collapsible section)
	var other_keys: Array = []
	for k in data_copy.keys():
		if used.has(k):
			continue
		if _should_hide_key(k):
			continue
		var v = data_copy[k]
		if v == null or str(v) == "":
			continue
		var t = typeof(v)
		if t == TYPE_ARRAY and (v as Array).size() <= 50: # allow larger arrays
			other_keys.append(k)
		elif t in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			other_keys.append(k)
	other_keys.sort()
	var other_box := _create_collapsible_section("Other Details", other_keys, data_copy, false, true)
	if other_box:
		inner.add_child(other_box)

	frame.add_child(inner)
	container.add_child(frame)
	return container

func _on_title_label_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		print("ConvoyCargoMenu: Title clicked. Emitting 'return_to_convoy_overview_requested'.")
		emit_signal("return_to_convoy_overview_requested", convoy_data_received)
		get_viewport().set_input_as_handled()

func _on_gdm_convoy_data_updated(all_convoy_data: Array) -> void:
	# Update convoy_data_received if this convoy is present in the update
	if not convoy_data_received or not convoy_data_received.has("convoy_id"):
		return
	var current_id = str(convoy_data_received.get("convoy_id"))
	for convoy in all_convoy_data:
		if convoy.has("convoy_id") and str(convoy.get("convoy_id")) == current_id:
			convoy_data_received = convoy.duplicate(true)
			_populate_cargo_list()
			break
