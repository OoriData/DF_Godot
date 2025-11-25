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
		"resource_path": true, "path": true
	}
	if hidden_exact.has(key):
		return true
	if key.begins_with("_"):
		return true
	if key.ends_with("_id"):
		return true
	return false

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

	for k in keys:
		if not data.has(k):
			continue
		if _should_hide_key(k):
			continue
		var value = data[k]
		if value == null or str(value) == "":
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
		k_lbl.text = _nice_key(k) + ":"
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

func _add_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.custom_minimum_size.y = 8
	parent.add_child(sep)

# Helper to build a single cargo row (raw or aggregated) with styling and inspect connection.
func _build_cargo_row(vehicle_vbox: VBoxContainer, display_name: String, quantity: int, item_data: Dictionary, item_index: int) -> void:
	# Outer wrapper preserves full width; background applied via stylebox so children remain interactive.
	var outer_row := HBoxContainer.new()
	outer_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_row.add_theme_constant_override("separation", 0)
	outer_row.mouse_filter = Control.MOUSE_FILTER_PASS

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
	inspect_button.pressed.connect(_on_inspect_cargo_item_pressed.bind(item_data, vehicle_vbox, outer_row))
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

	var vehicle_details_list: Array = convoy_data_received.get("vehicle_details_list", [])
	if vehicle_details_list.is_empty():
		var no_vehicles_label := Label.new()
		no_vehicles_label.text = "No vehicles in this convoy."
		no_vehicles_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		direct_vbox_ref.add_child(no_vehicles_label)
		return

	var any_cargo_found_in_convoy := false

	# Styled panels per vehicle
	for vehicle_index in range(vehicle_details_list.size()):
		var vehicle_data = vehicle_details_list[vehicle_index]
		if not vehicle_data is Dictionary:
			printerr("ConvoyCargoMenu: Invalid vehicle_data entry.")
			continue

		var vehicle_panel := PanelContainer.new()
		vehicle_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vehicle_margin := MarginContainer.new()
		vehicle_margin.add_theme_constant_override("margin_left", 8)
		vehicle_margin.add_theme_constant_override("margin_right", 8)
		vehicle_margin.add_theme_constant_override("margin_top", 6)
		vehicle_margin.add_theme_constant_override("margin_bottom", 6)
		vehicle_panel.add_child(vehicle_margin)

		var vehicle_vbox := VBoxContainer.new()
		vehicle_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vehicle_vbox.add_theme_constant_override("separation", 4)
		vehicle_margin.add_child(vehicle_vbox)

		var header_hbox := HBoxContainer.new()
		header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var accent := ColorRect.new()
		accent.color = Color(0.25 + 0.05 * (vehicle_index % 3), 0.35, 0.55 + 0.05 * (vehicle_index % 4), 0.9)
		accent.custom_minimum_size = Vector2(6, 24)
		accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var vehicle_name_label := Label.new()
		vehicle_name_label.text = "Vehicle: %s" % vehicle_data.get("name", "Unnamed Vehicle")
		vehicle_name_label.add_theme_font_size_override("font_size", 16)
		vehicle_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vehicle_name_label.modulate = Color(0.95, 0.95, 1, 1)

		header_hbox.add_child(accent)
		header_hbox.add_child(vehicle_name_label)
		vehicle_vbox.add_child(header_hbox)

		# Raw cargo extraction with debug: support both Array and Dictionary shapes
		var vehicle_cargo_list_raw = vehicle_data.get("cargo", [])
		var vehicle_cargo_list: Array = []
		if vehicle_cargo_list_raw is Array:
			vehicle_cargo_list = vehicle_cargo_list_raw
		elif vehicle_cargo_list_raw is Dictionary:
			for v in (vehicle_cargo_list_raw as Dictionary).values():
				vehicle_cargo_list.append(v)
		elif vehicle_cargo_list_raw == null:
			vehicle_cargo_list = []
		else:
			# Unexpected cargo shape; log and skip
			if CARGO_MENU_DEBUG:
				print("[ConvoyCargoMenu][DEBUG] Vehicle cargo unexpected type=", typeof(vehicle_cargo_list_raw), " vehicle=", vehicle_data.get("name"))
			vehicle_cargo_list = []

		if CARGO_MENU_DEBUG:
			print("[ConvoyCargoMenu][DEBUG] Vehicle", vehicle_data.get("name"), "raw cargo count=", vehicle_cargo_list.size())
			for ci in vehicle_cargo_list:
				if ci is Dictionary:
					print("  -> Cargo item name=", ci.get("name"), "base_name=", ci.get("base_name"), "qty=", ci.get("quantity"))
				else:
					print("  -> Non-dict cargo entry type=", typeof(ci))
		var actual_cargo_for_this_vehicle: Array = []
		for item in vehicle_cargo_list:
			if item is Dictionary and item.get("intrinsic_part_id") == null:
				actual_cargo_for_this_vehicle.append(item)

		if actual_cargo_for_this_vehicle.is_empty():
			var no_cargo_in_vehicle_label := Label.new()
			no_cargo_in_vehicle_label.text = "No cargo items in this vehicle."
			no_cargo_in_vehicle_label.modulate = Color(0.75, 0.75, 0.85, 1)
			vehicle_vbox.add_child(no_cargo_in_vehicle_label)
		else:
			any_cargo_found_in_convoy = true
			# Build either aggregated or raw rows
			if AGGREGATE_CARGO:
				var aggregated_cargo_for_vehicle: Dictionary = {}
				for cargo_item_data in actual_cargo_for_this_vehicle:
					if not _is_displayable_cargo(cargo_item_data):
						if CARGO_MENU_DEBUG:
							print("[ConvoyCargoMenu][DEBUG] Skip intrinsic part", cargo_item_data.get("name"))
						continue
					var base_name: String = _extract_item_display_name(cargo_item_data)
					var variant_parts: Array = []
					for variant_key in ["category", "type", "subtype"]:
						if cargo_item_data.has(variant_key) and str(cargo_item_data.get(variant_key, "")) != "":
							variant_parts.append(str(cargo_item_data.get(variant_key)))
					var variant_suffix := ""
					if not variant_parts.is_empty():
						variant_suffix = " (" + "/".join(variant_parts) + ")"
					var agg_key := base_name + variant_suffix
					var q_val = cargo_item_data.get("quantity", 0)
					var item_quantity := int(q_val) if (q_val is int or q_val is float) else 0
					if not aggregated_cargo_for_vehicle.has(agg_key):
						aggregated_cargo_for_vehicle[agg_key] = {"quantity": 0, "item_data_sample": cargo_item_data.duplicate(true)}
					aggregated_cargo_for_vehicle[agg_key]["quantity"] += item_quantity
					if CARGO_MENU_DEBUG:
						print("[ConvoyCargoMenu][DEBUG] Aggregate add", agg_key, "qty=", item_quantity)

				var cargo_names := aggregated_cargo_for_vehicle.keys()
				cargo_names.sort()
				var item_index := 0
				for item_name in cargo_names:
					var agg_data = aggregated_cargo_for_vehicle[item_name]
					_build_cargo_row(vehicle_vbox, item_name, agg_data["quantity"], agg_data["item_data_sample"], item_index)
					item_index += 1
			else:
				var item_index := 0
				for cargo_item_data in actual_cargo_for_this_vehicle:
					var displayable := _is_displayable_cargo(cargo_item_data)
					var n := _extract_item_display_name(cargo_item_data)
					if CARGO_MENU_DEBUG:
						print("[ConvoyCargoMenu][DEBUG] Raw cargo vehicle=", vehicle_data.get("name"), " name=", n, " displayable=", displayable, " qty=", cargo_item_data.get("quantity"))
					if not displayable:
						continue
					var q_val = cargo_item_data.get("quantity", 0)
					var quantity := int(q_val) if (q_val is int or q_val is float) else 0
					_build_cargo_row(vehicle_vbox, n, quantity, cargo_item_data, item_index)
					item_index += 1
				if CARGO_MENU_DEBUG:
					print("[ConvoyCargoMenu][DEBUG] Vehicle", vehicle_data.get("name"), " rendered cargo rows=", item_index)


		direct_vbox_ref.add_child(vehicle_panel)
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

func _on_inspect_cargo_item_pressed(item_data: Dictionary, list_container: VBoxContainer, item_row_hbox: HBoxContainer):
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
	var panel := _build_inline_inspect_panel(item_data, item_row_hbox)
	var row_index := list_container.get_children().find(item_row_hbox)
	if row_index == -1:
		list_container.add_child(panel)
	else:
		list_container.add_child(panel)
		list_container.move_child(panel, row_index + 1)
	item_row_hbox.set_meta("inspect_panel", panel)
	item_row_hbox.remove_meta("inspect_building")

func _build_inline_inspect_panel(item_data: Dictionary, item_row_hbox: HBoxContainer) -> VBoxContainer:
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
	title_lbl.text = "Details: %s" % item_data.get("name", "Item")
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

	# Define primary keys (core info + description + common stats)
	var primary_keys := [
		"name", "description", "quantity", "unit", "category", "type", "subtype",
		"weight", "volume", "value", "quality", "condition"
	]

	var data_copy: Dictionary = item_data.duplicate(true)
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
