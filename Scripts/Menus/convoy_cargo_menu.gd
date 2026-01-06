extends Control
const DIAG_ENABLED := true
var _diag_seq := 0
func _diag(tag: String, msg: String, data: Variant = null) -> void:
	if not DIAG_ENABLED:
		return
	_diag_seq += 1
	var ts := Time.get_ticks_msec()
	var line := "[CargoDiag] %s #%s t=%s :: %s" % [tag, _diag_seq, ts, msg]
	if data != null:
		if typeof(data) == TYPE_DICTIONARY or typeof(data) == TYPE_ARRAY or typeof(data) == TYPE_STRING:
			line += " | " + str(data)
		else:
			line += " | (data)"
	print(line)

const ItemsData = preload("res://Scripts/Data/Items.gd")

signal back_requested

signal return_to_convoy_overview_requested(convoy_data)
var convoy_data_received: Dictionary

@onready var title_label: Label = $MainVBox/TitleLabel
@onready var cargo_items_vbox: VBoxContainer = $MainVBox/ScrollContainer/CargoItemsVBox
@onready var back_button: Button = $MainVBox/BackButton

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
var _latest_all_settlements: Array = []
var _vendors_by_id: Dictionary = {} # vendor_id -> vendor Dictionary
var _item_to_inspect_on_load = null

var _organize_button: Button

# Debounce UI refresh to prevent instant inspect closure
var _suppress_refresh_until_msec: int = 0
var _open_inspects: Dictionary = {}

func _snapshot_open_inspects(tag: String) -> void:
	# Emit a compact summary of currently tracked open inspect cargo_ids
	var ids: Array = _open_inspects.keys()
	var sample_ids: Array = []
	var limit: int = min(6, ids.size())
	for i in range(limit):
		sample_ids.append(str(ids[i]))
	_diag(tag, "open_ids", {"count": ids.size(), "sample": sample_ids})

var organization_mode: String = "by_type" # "by_type" or "by_vehicle"

# Debug toggle for diagnosing missing cargo items
const CARGO_MENU_DEBUG: bool = true
const AGGREGATE_CARGO: bool = false # Set true to merge identical items

# Pretty-print helper with truncation to avoid console limits
const DEBUG_JSON_CHAR_LIMIT := 4000
func _json_snippet(data: Variant, label: String = "") -> void:
	var encoded := JSON.stringify(data, "  ")
	var total_len := encoded.length()
	if total_len > DEBUG_JSON_CHAR_LIMIT:
		encoded = encoded.substr(0, DEBUG_JSON_CHAR_LIMIT) + "...<truncated " + str(total_len - DEBUG_JSON_CHAR_LIMIT) + " chars>"
	if label != "":
		print('[CargoMenu][DEBUG][JSON]', label, '=', encoded)
	else:
		print(encoded)

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
	_diag("ready", "ConvoyCargoMenu ready")
	if is_instance_valid(back_button):
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed, CONNECT_ONE_SHOT)

	# --- NEW: Single Organization Toggle Button ---
	_organize_button = Button.new()
	_organize_button.name = "OrganizeButton"

	# --- NEW: Custom Styling for the button ---
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.2, 0.22, 0.25, 0.9)
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.5, 0.55, 0.6, 0.9)
	style_normal.corner_radius_top_left = 5
	style_normal.corner_radius_top_right = 5
	style_normal.corner_radius_bottom_left = 5
	style_normal.corner_radius_bottom_right = 5
	style_normal.content_margin_left = 12
	style_normal.content_margin_right = 12
	style_normal.content_margin_top = 6
	style_normal.content_margin_bottom = 6

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = style_normal.bg_color.lightened(0.1)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = style_normal.bg_color.darkened(0.1)

	_organize_button.add_theme_stylebox_override("normal", style_normal)
	_organize_button.add_theme_stylebox_override("hover", style_hover)
	_organize_button.add_theme_stylebox_override("pressed", style_pressed)

	var main_vbox = get_node_or_null("MainVBox")
	if is_instance_valid(main_vbox):
		# Place button in a container to center it
		var organize_container = HBoxContainer.new()
		organize_container.name = "OrganizeContainer"
		organize_container.alignment = BoxContainer.ALIGNMENT_CENTER
		organize_container.add_child(_organize_button)
		main_vbox.add_child(organize_container)
		main_vbox.move_child(organize_container, 1) # Place it after the title
	else:
		printerr("ConvoyCargoMenu: MainVBox not found, cannot add organization button.")

	_organize_button.pressed.connect(_on_organize_button_pressed)

	# Make the title label clickable to return to the convoy overview
	if is_instance_valid(title_label):
		title_label.mouse_filter = Control.MOUSE_FILTER_STOP # Allow it to receive mouse events
		title_label.gui_input.connect(_on_title_label_gui_input)
	else:
		printerr("ConvoyCargoMenu: BackButton node not found. Ensure it's named 'BackButton' in the scene.")

	# Phase C: subscribe to canonical sources instead of GameDataManager.
	if is_instance_valid(_store):
		if _store.has_signal("convoys_changed") and not _store.convoys_changed.is_connected(_on_store_convoys_changed):
			_store.convoys_changed.connect(_on_store_convoys_changed)
		if _store.has_signal("map_changed") and not _store.map_changed.is_connected(_on_store_map_changed):
			_store.map_changed.connect(_on_store_map_changed)
		if _store.has_method("get_settlements"):
			var pre_cached = _store.get_settlements()
			if pre_cached is Array:
				_latest_all_settlements = pre_cached
	if is_instance_valid(_hub) and _hub.has_signal("vendor_updated") and not _hub.vendor_updated.is_connected(_on_vendor_updated):
		_hub.vendor_updated.connect(_on_vendor_updated)

	# Set initial button text
	_update_organize_button_text()

	# Disable horizontal scrolling to prevent content drifting off-screen
	var sc := get_node_or_null("MainVBox/ScrollContainer")
	if sc is ScrollContainer:
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

func _update_organize_button_text() -> void:
	if organization_mode == "by_type":
		_organize_button.text = "Group by Vehicle"
	else:
		_organize_button.text = "Group by Type"

func _on_organize_button_pressed() -> void:
	organization_mode = "by_vehicle" if organization_mode == "by_type" else "by_type"
	_update_organize_button_text()
	_populate_cargo_list()
	_diag("organize", "mode_changed", {"mode": organization_mode})

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

# Resolve a vendor name from a vendor_id via cached vendor/settlement data; fallback to id.
func _resolve_vendor_name(vendor_id: String) -> String:
	if vendor_id.is_empty():
		return ""
	if _vendors_by_id.has(vendor_id):
		var v0 = _vendors_by_id[vendor_id]
		if v0 is Dictionary:
			var n0 := String((v0 as Dictionary).get("name", ""))
			if not n0.is_empty():
				return n0
	for settlement in _latest_all_settlements:
		if not (settlement is Dictionary):
			continue
		var vendors: Array = (settlement as Dictionary).get("vendors", [])
		for v in vendors:
			if v is Dictionary and String((v as Dictionary).get("vendor_id", "")) == vendor_id:
				var n := String((v as Dictionary).get("name", ""))
				if not n.is_empty():
					return n
	return vendor_id

# Optionally resolve settlement name from vendor id
func _resolve_settlement_name_for_vendor(vendor_id: String) -> String:
	if vendor_id.is_empty():
		return ""
	for settlement in _latest_all_settlements:
		if not (settlement is Dictionary):
			continue
		var vendors: Array = (settlement as Dictionary).get("vendors", [])
		for v in vendors:
			if v is Dictionary and String((v as Dictionary).get("vendor_id", "")) == vendor_id:
				var nm := String((settlement as Dictionary).get("name", (settlement as Dictionary).get("settlement_name", "")))
				if not nm.is_empty():
					return nm
	return ""


func _on_store_map_changed(_tiles: Array, settlements: Array) -> void:
	if settlements is Array:
		_latest_all_settlements = settlements


func _on_vendor_updated(vendor: Dictionary) -> void:
	if not (vendor is Dictionary):
		return
	var vendor_id := String(vendor.get("vendor_id", vendor.get("id", "")))
	if vendor_id != "":
		_vendors_by_id[vendor_id] = vendor

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
			var stats_text := _format_stats_light(value)
			# If a modifiers summary exists, prepend it to the stats for unified display
			if data.has("modifiers") and str(data.get("modifiers")).strip_edges() != "":
				var mod_text := str(data.get("modifiers")).strip_edges()
				# Ensure spacing between modifiers and stats
				stats_text = mod_text + (" " if not mod_text.ends_with(" ") else "") + stats_text
			stats_label.text = stats_text
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

		# Build a row: use a PanelContainer with a StyleBox for alternating backgrounds
		var row_panel := PanelContainer.new()
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		if shown % 2 == 0:
			sb.bg_color = Color(0.15, 0.15, 0.18, 0.6)
		else:
			sb.bg_color = Color(0, 0, 0, 0)
		row_panel.add_theme_stylebox_override("panel", sb)

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 6)
		row_panel.add_child(row)

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
		v_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD

		# Badge styling for notable numeric/status fields
		_apply_value_styling(k, value, v_lbl)

		row.add_child(k_lbl)
		row.add_child(v_lbl)
		rows_container.add_child(row_panel)
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
	# Defer to the centralized classification logic in the ItemsData factory.
	return ItemsData.PartItem._looks_like_part_dict(d)

func _looks_like_mission(d: Dictionary) -> bool:
	if not d:
		return false
	# Concrete rule alignment: prefer presence of recipient.
	if d.has("recipient") and d.get("recipient") != null:
		return true
	# Keep additional Item rules for compatibility with older data.
	if d.get("is_mission", false):
		return true
	if d.has("mission_id") and d.get("mission_id") != null and str(d.get("mission_id")) != "":
		return true
	if d.has("mission_vendor_id") and d.get("mission_vendor_id") != null and str(d.get("mission_vendor_id")) != "":
		return true
	if d.has("delivery_reward"):
		var dr = d.get("delivery_reward")
		if dr != null and (dr is float or dr is int) and float(dr) > 0.0:
			return true
	return false

# Determine if dictionary represents a resource cargo item (raw resources or supplies).
func _looks_like_resource(d: Dictionary) -> bool:
	if not d:
		return false
	if d.get("is_raw_resource", false):
		return true
	if d.has("resource_type"):
		return true
	# Presence-based detection aligned with Items.gd (includes capital 'Fuel').
	for k in ["water", "food", "fuel", "Fuel"]:
		if d.has(k) and d.get(k) != null:
			return true
	# Keep category hint as a soft compatibility aid.
	if str(d.get("category", "")).to_lower() == "resource":
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
	outer_row.set_meta("agg_data", agg_data)
	outer_row.add_theme_constant_override("separation", 0)
	outer_row.mouse_filter = Control.MOUSE_FILTER_PASS

	var item_data = agg_data["item_data_sample"]
	if CARGO_MENU_DEBUG:
		print("[CargoUI] BuildRow idx:", item_index, " name:", display_name, " qty:", quantity, " tw:", agg_data.get("total_weight", 0.0), " tv:", agg_data.get("total_volume", 0.0))
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

	# Build consistent column order: Qty | ItemName(expand) | Quality | Condition | Inspect
	# Add quantity badge first
	content_row.add_child(qty_badge)
	# Item label (expands to take remaining space before fixed columns)
	content_row.add_child(item_label)

	# NEW: Context column for vehicle or item type
	var context_label := Label.new()
	context_label.custom_minimum_size = Vector2(120, 22)
	context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	context_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	context_label.modulate = Color(0.8, 0.8, 0.8, 1)
	content_row.add_child(context_label)

	if organization_mode == "by_type":
		var locations: Dictionary = agg_data.get("locations", {})
		if not locations.is_empty():
			if locations.size() == 1:
				context_label.text = locations.keys()[0]
			else:
				context_label.text = "Multiple"
			
			var tooltip_parts: Array[String]
			for v_name in locations:
				tooltip_parts.append("%s (x%d)" % [v_name, locations[v_name]])
			context_label.tooltip_text = "In: " + ", ".join(tooltip_parts)
	else: # "by_vehicle" mode
		# Use the same broad categories as the "by type" view for consistency.
		var typed_item = ItemsData.from_dict(item_data)
		var category_name: String = typed_item.category
		if CARGO_MENU_DEBUG:
			print("[CargoUI][ByVehicle] Row classify name:", display_name, " initial:", category_name, " looks_like_part:", _looks_like_part(item_data))
		# Safeguard: if classifier returns 'other' but data looks like a part, treat as part
		if category_name == "other" and _looks_like_part(item_data):
			category_name = "part"
			if CARGO_MENU_DEBUG:
				print("[CargoUI][ByVehicle] Forced category to 'part' for:", display_name)
		
		var display_text: String
		match category_name:
			"mission":
				display_text = "Mission Cargo"
			"part":
				display_text = "Part Cargo"
			"resource":
				display_text = "Resource Cargo"
			_: # "other", "vehicle", or anything else
				display_text = "Other Cargo"
		context_label.text = display_text

	# Add Weight and Volume labels to the main row
	var weight_label := Label.new()
	weight_label.text = "%.2f kg" % agg_data.get("total_weight", 0.0)
	weight_label.custom_minimum_size = Vector2(80, 22)
	weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weight_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weight_label.modulate = Color(0.8, 0.85, 0.9, 1)
	content_row.add_child(weight_label)

	var volume_label := Label.new()
	volume_label.text = "%.2f m³" % agg_data.get("total_volume", 0.0)
	volume_label.custom_minimum_size = Vector2(80, 22)
	volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	volume_label.modulate = Color(0.8, 0.9, 0.85, 1)
	content_row.add_child(volume_label)

	# (Removed) Tag column: omit category/type/subtype label per request.

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

	# Weight/Volume displayed in Item Overview; omit row badges per request.

	# Inspect/Hide toggle button (always last)
	var inspect_button := Button.new()
	inspect_button.name = "InspectButton"
	inspect_button.text = "Inspect"
	inspect_button.custom_minimum_size = Vector2(90, 26)
	inspect_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inspect_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inspect_button.pressed.connect(_on_inspect_cargo_item_pressed.bind(agg_data, vehicle_vbox, outer_row, inspect_button))
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

func _aggregate_cargo_item(agg_dict: Dictionary, item: Dictionary, vehicle_name: String = "") -> void:
	# Use name as aggregation key. Could be improved with a more unique ID if available.
	var agg_key = _extract_item_display_name(item)
	
	if not agg_dict.has(agg_key):
		agg_dict[agg_key] = {
			"item_data_sample": item.duplicate(true),
			"display_name": agg_key,
			"total_quantity": 0,
			"total_weight": 0.0,
			"total_volume": 0.0,
			"locations": {},
			"items": []
		}

	var item_quantity = int(item.get("quantity", 0))
	if item_quantity <= 0: item_quantity = 1 # Assume 1 if quantity is missing/zero for single items

	agg_dict[agg_key]["total_quantity"] += item_quantity
	if CARGO_MENU_DEBUG:
		print("[CargoAgg][", agg_key, "] +quantity:", item_quantity)
	
	# Track locations
	if not vehicle_name.is_empty():
		if not agg_dict[agg_key].locations.has(vehicle_name):
			agg_dict[agg_key].locations[vehicle_name] = 0
		agg_dict[agg_key].locations[vehicle_name] += item_quantity
	
	# NEW: Store the raw item for later lookup
	agg_dict[agg_key]["items"].append(item)

	# Sum weight and volume. This logic is structured to first determine the
	# unit weight/volume of the item stack, then multiply by quantity. This is more
	# robust for ambiguous raw item data, following the convention from Items.gd.

	# --- Determine unit weight and add to total ---
	var unit_w := 0.0
	if item.has("unit_weight") and item.get("unit_weight") != null:
		unit_w = float(item.get("unit_weight", 0.0))
	elif item.has("weight") and item.get("weight") != null:
		var total_w = float(item.get("weight", 0.0))
		if item_quantity > 0:
			unit_w = total_w / float(item_quantity)
	agg_dict[agg_key]["total_weight"] += unit_w * item_quantity
	if CARGO_MENU_DEBUG:
		print("[CargoAgg][", agg_key, "] unit_w:", unit_w, " qty:", item_quantity, " -> total_weight:", agg_dict[agg_key]["total_weight"])

	# --- Determine unit volume and add to total ---
	var unit_v := 0.0
	if item.has("unit_volume") and item.get("unit_volume") != null:
		unit_v = float(item.get("unit_volume", 0.0))
	elif item.has("volume") and item.get("volume") != null:
		var total_v = float(item.get("volume", 0.0))
		if item_quantity > 0:
			unit_v = total_v / float(item_quantity)
	agg_dict[agg_key]["total_volume"] += unit_v * item_quantity
	if CARGO_MENU_DEBUG:
		print("[CargoAgg][", agg_key, "] unit_v:", unit_v, " qty:", item_quantity, " -> total_volume:", agg_dict[agg_key]["total_volume"])

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

	if CARGO_MENU_DEBUG:
		print("[CargoUI] Building category '", title, "' with ", sorted_keys.size(), " keys")
	for key in sorted_keys:
		var data = agg_data[key]
		if CARGO_MENU_DEBUG:
			print("[CargoUI] Row ", item_index, " key:", key, " name:", data["display_name"], " qty:", data["total_quantity"], " tw:", data.get("total_weight", 0.0), " tv:", data.get("total_volume", 0.0))
		_build_cargo_row(parent, data["display_name"], data["total_quantity"], data, item_index)
		item_index += 1
	
	return item_index

func initialize_with_data(data: Dictionary, item_to_inspect = null):
	# Ensure this function runs only after the node is fully ready and @onready vars are set.
	if not is_node_ready():
		printerr("ConvoyCargoMenu: initialize_with_data called BEFORE node is ready! Deferring.")
		call_deferred("initialize_with_data", data, item_to_inspect)
		return

	convoy_data_received = data.duplicate()
	_item_to_inspect_on_load = item_to_inspect
	# print("ConvoyCargoMenu: Initialized with data: ", convoy_data_received) # DEBUG

	if is_instance_valid(title_label) and convoy_data_received.has("convoy_name"):
		title_label.text = "%s" % convoy_data_received.get("convoy_name", "Unknown Convoy")
	elif is_instance_valid(title_label):
		title_label.text = "Cargo Hold"
	
	_populate_cargo_list()
	_diag("populate", "called_from_initialize")
	if _item_to_inspect_on_load != null:
		call_deferred("_inspect_item_on_load")

func _populate_cargo_list():
	_diag("populate", "start", {"mode": organization_mode})
	_snapshot_open_inspects("inspect_state_before_populate")
	if organization_mode == "by_type":
		_populate_by_type()
	else: # "by_vehicle"
		_populate_by_vehicle()
	_diag("populate", "done")
	_reopen_inspects()

func _populate_by_type():
	_diag("populate_type", "start")
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
	var _clr := direct_vbox_ref.get_child_count()
	_diag("clear_rows", "type_begin", {"children": _clr})
	_snapshot_open_inspects("inspect_state_before_clear_type")
	for child in direct_vbox_ref.get_children():
		child.queue_free()
	_diag("clear_rows", "type_end", {"removed": _clr})

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
		var vehicle_name: String = str(vehicle_data.get("name", "Unknown Vehicle"))
		if not vehicle_data is Dictionary:
			printerr("ConvoyCargoMenu: Invalid vehicle_data entry.")
			continue

		# Prefer typed cargo if provided by GameDataManager
		if vehicle_data.has("cargo_items_typed") and vehicle_data["cargo_items_typed"] is Array and not (vehicle_data["cargo_items_typed"] as Array).is_empty():
			if CARGO_MENU_DEBUG:
				print("\n--- DEBUG: Processing 'cargo_items_typed' for vehicle: %s ---" % vehicle_data.get("vehicle_name", "Unknown"))
				for typed_item_to_print in vehicle_data["cargo_items_typed"]:
					# Print the underlying raw dictionary, as that's what's used for aggregation.
					# This shows us exactly what the calculation logic will see.
					print(JSON.stringify(typed_item_to_print.raw, "  "))

			for typed in vehicle_data["cargo_items_typed"]:
				if not typed is CargoItem:
					continue
				# Filter out non-displayable items like intrinsic vehicle parts (e.g., fuel tanks).
				if not _is_displayable_cargo(typed.raw):
					continue
				any_cargo_found_in_convoy = true
				# Use underlying raw dict for existing aggregation utilities
				var raw_item: Dictionary = typed.raw.duplicate(true)
				# Ensure quantity reflects typed normalization
				raw_item["quantity"] = typed.quantity
				# Inject normalized total weight/volume from the typed object.
				# This is now reliable after fixing the bug in Items.gd.
				raw_item["weight"] = typed.total_weight
				raw_item["volume"] = typed.total_volume
				# Part-specific enrichment (use duck typing since PartItem class not globally named here)
				if typed.has_method("get_modifier_summary"):
					var mods_val = typed.get_modifier_summary()
					if mods_val is String and mods_val.strip_edges() != "":
						raw_item["modifiers"] = mods_val
					# stats present on parts only; copied verbatim
					if "stats" in typed and typed.stats is Dictionary and not typed.stats.is_empty():
						raw_item["stats"] = typed.stats.duplicate(true)
				# Safeguard: if typed says 'other' but data looks like a part/resource/mission, override.
				var effective_category: String = String(typed.category)
				if effective_category == "other":
					if _looks_like_part(raw_item):
						effective_category = "part"
						# Ensure hints
						raw_item["category"] = "part"
						_inject_part_modifiers(raw_item)
						if CARGO_MENU_DEBUG:
							print("[CargoClassify][Typed][Rebucket] OTHER -> PART:", JSON.stringify(raw_item.get("name", raw_item.get("base_name", ""))))
					elif _looks_like_resource(raw_item):
						effective_category = "resource"
						raw_item["category"] = "resource"
						if CARGO_MENU_DEBUG:
							print("[CargoClassify][Typed][Rebucket] OTHER -> RESOURCE:", JSON.stringify(raw_item.get("name", raw_item.get("base_name", ""))))
					elif _looks_like_mission(raw_item):
						effective_category = "mission"
						raw_item["category"] = "mission"
						if CARGO_MENU_DEBUG:
							print("[CargoClassify][Typed][Rebucket] OTHER -> MISSION:", JSON.stringify(raw_item.get("name", raw_item.get("base_name", ""))))

				match effective_category:
					"mission":
						_aggregate_cargo_item(aggregated_missions, raw_item, vehicle_name)
					"part":
						_aggregate_cargo_item(aggregated_parts, raw_item, vehicle_name)
					"resource":
						_aggregate_cargo_item(aggregated_resources, raw_item, vehicle_name)
					_:
						if CARGO_MENU_DEBUG:
							print("[CargoClassify][Typed] item -> OTHER name:", JSON.stringify(raw_item.get("name", raw_item.get("base_name", ""))))
							_json_snippet(raw_item, "[Typed OTHER raw]")
						_aggregate_cargo_item(aggregated_other, raw_item, vehicle_name)
		else:
			if CARGO_MENU_DEBUG:
				print("\n--- DEBUG: Processing legacy 'cargo' and 'parts' for vehicle: %s ---" % vehicle_data.get("vehicle_name", "Unknown"))
				# Print the raw arrays that will be iterated over. This helps diagnose issues
				# with older, non-typed data structures.
				print("CARGO: ", JSON.stringify(vehicle_data.get("cargo", []), "  "))
				print("PARTS: ", JSON.stringify(vehicle_data.get("parts", []), "  "))

			var vehicle_cargo_list_raw = vehicle_data.get("cargo", [])
			var vehicle_cargo_list: Array = []
			if vehicle_cargo_list_raw is Array:
				vehicle_cargo_list = vehicle_cargo_list_raw
			elif vehicle_cargo_list_raw is Dictionary:
				vehicle_cargo_list = (vehicle_cargo_list_raw as Dictionary).values()

			# This fallback logic is now aligned with `vendor_trade_panel.gd` to ensure consistent categorization.
			for item in vehicle_cargo_list:
				if not (item is Dictionary and _is_displayable_cargo(item)):
					continue
				any_cargo_found_in_convoy = true
				# Mission items: prefer presence-based recipient signal.
				if item.get("recipient") != null:
					_aggregate_cargo_item(aggregated_missions, item, vehicle_name)
				# Detect parts even if they appear in the main cargo list
				elif _looks_like_part(item):
					# Normalize hint to aid downstream UI and filtering
					item["category"] = "part"
					# Enrich with modifiers so they surface in the inspector
					_inject_part_modifiers(item)
					if CARGO_MENU_DEBUG:
						print("[CargoClassify] LEGACY cargo item -> PART:", JSON.stringify(item.get("name", item.get("base_name", ""))))
					_aggregate_cargo_item(aggregated_parts, item, vehicle_name)
				# Resources and supplies: presence-based keys, include Fuel and resource_type
				elif (item.has("food") and item.get("food") != null) or (item.has("water") and item.get("water") != null) or (item.has("fuel") and item.get("fuel") != null) or (item.has("Fuel") and item.get("Fuel") != null) or item.get("is_raw_resource", false) or item.has("resource_type") or str(item.get("category", "")).to_lower() == "resource":
					_aggregate_cargo_item(aggregated_resources, item, vehicle_name)
				else:
					if CARGO_MENU_DEBUG:
						print("[CargoClassify] LEGACY cargo item -> OTHER name:", JSON.stringify(item.get("name", item.get("base_name", ""))))
						_json_snippet(item, "[Legacy OTHER raw]")
					_aggregate_cargo_item(aggregated_other, item, vehicle_name)

			# Separately process the 'parts' list, if it exists, which is consistent with `vendor_trade_panel`.
			for item in vehicle_data.get("parts", []):
				if not (item is Dictionary and _is_displayable_cargo(item)):
					continue
				any_cargo_found_in_convoy = true
				# Enrich part data with modifiers/stats so they surface in UI
				var part_copy: Dictionary = item.duplicate(true)
				_inject_part_modifiers(part_copy)
				_aggregate_cargo_item(aggregated_parts, part_copy, vehicle_name)

	# --- Final safeguard re-bucketing: move misclassified parts from Other -> Parts ---
	if not aggregated_other.is_empty():
		var moved_keys: Array = []
		for key in aggregated_other.keys():
			var entry: Dictionary = aggregated_other[key]
			var sample: Dictionary = entry.get("item_data_sample", {})
			if _looks_like_part(sample):
				# Ensure category hint and modifiers present
				sample["category"] = "part"
				_inject_part_modifiers(sample)
				# Merge the entire aggregated entry, not just the sample
				if aggregated_parts.has(key):
					aggregated_parts[key].total_quantity += entry.total_quantity
					aggregated_parts[key].total_weight += entry.total_weight
					aggregated_parts[key].total_volume += entry.total_volume
					for loc_key in entry.get("locations", {}):
						if not aggregated_parts[key].locations.has(loc_key):
							aggregated_parts[key].locations[loc_key] = 0
						aggregated_parts[key].locations[loc_key] += entry.locations[loc_key]
				else:
					aggregated_parts[key] = entry
				
				moved_keys.append(key)
				if CARGO_MENU_DEBUG:
					print("[CargoClassify][Rebucket] OTHER -> PART:", key)
			else:
				if CARGO_MENU_DEBUG:
					print("[CargoClassify][InspectOther] sample name:", JSON.stringify(sample.get("name", sample.get("base_name", ""))))
					_json_snippet(sample, "[InspectOther sample raw]")
		# Remove moved entries from Other so they don't duplicate
		for k in moved_keys:
			aggregated_other.erase(k)

	_add_category_section(direct_vbox_ref, "Mission Cargo", aggregated_missions)
	_add_category_section(direct_vbox_ref, "Part Cargo", aggregated_parts)
	_add_category_section(direct_vbox_ref, "Resource Cargo", aggregated_resources)
	_add_category_section(direct_vbox_ref, "Other Cargo", aggregated_other)
	_diag("populate_type", "sections_added", {"missions": aggregated_missions.size(), "parts": aggregated_parts.size(), "resources": aggregated_resources.size(), "other": aggregated_other.size()})

	# Debug counts summary
	if CARGO_MENU_DEBUG:
		print("[ConvoyCargoMenu][DEBUG] Category counts -> Missions:%d Parts:%d Resources:%d Other:%d" % [aggregated_missions.size(), aggregated_parts.size(), aggregated_resources.size(), aggregated_other.size()])
		if aggregated_parts.size() > 0:
			print("[CargoClassify] Parts keys:", JSON.stringify(aggregated_parts.keys()))
		if aggregated_other.size() > 0:
			print("[CargoClassify] Other keys:", JSON.stringify(aggregated_other.keys()))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	direct_vbox_ref.add_child(spacer)

	if not any_cargo_found_in_convoy and not vehicle_details_list.is_empty():
		var no_cargo_overall_label := Label.new()
		no_cargo_overall_label.text = "This convoy is carrying no cargo items (only vehicle parts)."
		no_cargo_overall_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		direct_vbox_ref.add_child(no_cargo_overall_label)

func _populate_by_vehicle():
	_diag("populate_vehicle", "start")
	var direct_vbox_ref: VBoxContainer = cargo_items_vbox
	
	# Clear any previous items
	var _clr := direct_vbox_ref.get_child_count()
	_diag("clear_rows", "vehicle_begin", {"children": _clr})
	_snapshot_open_inspects("inspect_state_before_clear_vehicle")
	for child in direct_vbox_ref.get_children():
		child.queue_free()
	_diag("clear_rows", "vehicle_end", {"removed": _clr})

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

		# A single aggregation dictionary for all cargo within this vehicle.
		var vehicle_aggregated_all_cargo: Dictionary = {}
		
		var has_cargo_in_this_vehicle := false
		var vehicle_name := str(vehicle_data.get("name", "Unknown Vehicle"))

		# Process typed cargo first
		if vehicle_data.has("cargo_items_typed") and vehicle_data["cargo_items_typed"] is Array and not (vehicle_data["cargo_items_typed"] as Array).is_empty():
			for typed in vehicle_data["cargo_items_typed"]:
				if not typed is CargoItem or not _is_displayable_cargo(typed.raw):
					continue
				
				has_cargo_in_this_vehicle = true
				any_cargo_found_in_convoy = true
				
				var raw_item: Dictionary = typed.raw.duplicate(true)
				raw_item["quantity"] = typed.quantity
				raw_item["weight"] = typed.total_weight
				raw_item["volume"] = typed.total_volume
				# --- Definitive Fix ---
				# The "by vehicle" mode re-classifies items later. We must ensure the data
				# passed to the classifier has all the hints the 'typed' object already figured out.
				# 1. Inject the known category. This is the most important hint.
				raw_item["category"] = typed.category
				# 2. If it's a part, also inject the slot, as it's another strong hint for classification.
				if typed.category == "part" and typed.slot != "":
					raw_item["slot"] = typed.slot
				if typed.has_method("get_modifier_summary"):
					var mods_val = typed.get_modifier_summary()
					if mods_val is String and mods_val.strip_edges() != "":
						raw_item["modifiers"] = mods_val
					if "stats" in typed and typed.stats is Dictionary and not typed.stats.is_empty():
						raw_item["stats"] = typed.stats.duplicate(true)
				
				# Rebucket safeguard for typed 'other'
				var effective_category: String = String(typed.category)
				if effective_category == "other":
					if _looks_like_part(raw_item):
						effective_category = "part"
						raw_item["category"] = "part"
						_inject_part_modifiers(raw_item)
						if CARGO_MENU_DEBUG:
							print("[CargoClassify][ByVehicle][Typed][Rebucket] OTHER -> PART:", JSON.stringify(raw_item.get("name", raw_item.get("base_name", ""))))
					elif _looks_like_resource(raw_item):
						effective_category = "resource"
						raw_item["category"] = "resource"
						if CARGO_MENU_DEBUG:
							print("[CargoClassify][ByVehicle][Typed][Rebucket] OTHER -> RESOURCE:", JSON.stringify(raw_item.get("name", raw_item.get("base_name", ""))))
					elif _looks_like_mission(raw_item):
						effective_category = "mission"
						raw_item["category"] = "mission"
						if CARGO_MENU_DEBUG:
							print("[CargoClassify][ByVehicle][Typed][Rebucket] OTHER -> MISSION:", JSON.stringify(raw_item.get("name", raw_item.get("base_name", ""))))

				_aggregate_cargo_item(vehicle_aggregated_all_cargo, raw_item)
				# If still 'other', log it for diagnosis
				if CARGO_MENU_DEBUG and effective_category == "other":
					print("[CargoClassify][ByVehicle][Typed] item -> OTHER name:", JSON.stringify(raw_item.get("name", raw_item.get("base_name", ""))))
					_json_snippet(raw_item, "[ByVehicle Typed OTHER raw]")
		else: # Fallback to legacy cargo
			var vehicle_cargo_list_raw = vehicle_data.get("cargo", [])
			var vehicle_cargo_list: Array = []
			if vehicle_cargo_list_raw is Array: vehicle_cargo_list = vehicle_cargo_list_raw
			elif vehicle_cargo_list_raw is Dictionary: vehicle_cargo_list = (vehicle_cargo_list_raw as Dictionary).values()

			for item in vehicle_cargo_list:
				if not (item is Dictionary and _is_displayable_cargo(item)): continue
				has_cargo_in_this_vehicle = true
				any_cargo_found_in_convoy = true
				# Replicate the classification logic from `_populate_by_type` to ensure
				# the `category` hint is correctly injected before aggregation. This helps
				# the ItemsData factory correctly classify the item later.
				if _looks_like_mission(item):
					item["category"] = "mission"
				elif _looks_like_part(item):
					item["category"] = "part"
					_inject_part_modifiers(item)
				elif _looks_like_resource(item):
					item["category"] = "resource"
				_aggregate_cargo_item(vehicle_aggregated_all_cargo, item)
			
			for item in vehicle_data.get("parts", []):
				if not (item is Dictionary and _is_displayable_cargo(item)): continue
				has_cargo_in_this_vehicle = true
				any_cargo_found_in_convoy = true
				var part_copy: Dictionary = item.duplicate(true)
				part_copy["category"] = "part" # Ensure it's categorized as a part for the factory
				_inject_part_modifiers(part_copy)
				_aggregate_cargo_item(vehicle_aggregated_all_cargo, part_copy)

		if has_cargo_in_this_vehicle:
			# Use the existing category section function, but with the vehicle's name as the title.
			# This creates the "yellow banner" with the vehicle name.
			_add_category_section(direct_vbox_ref, vehicle_name, vehicle_aggregated_all_cargo)
			_add_separator(direct_vbox_ref)

	if not any_cargo_found_in_convoy and not vehicle_details_list.is_empty():
		var no_cargo_overall_label := Label.new()
		no_cargo_overall_label.text = "This convoy is carrying no cargo items (only vehicle parts)."
		no_cargo_overall_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		direct_vbox_ref.add_child(no_cargo_overall_label)
	_diag("populate_vehicle", "done")

func _on_back_button_pressed():
	# print("ConvoyCargoMenu: Back button pressed. Emitting 'back_requested' signal.") # DEBUG
	emit_signal("back_requested")

func _on_inspect_cargo_item_pressed(agg_data: Dictionary, list_container: VBoxContainer, item_row_hbox: HBoxContainer, toggle_button: Button = null):
	# Prevent re-entrancy (e.g., double click during build)
	if item_row_hbox.has_meta("inspect_building"):
		return

	# Debounce any external refreshes that rebuild the list (e.g., convoy_data_updated)
	_suppress_refresh_until_msec = Time.get_ticks_msec() + 400
	_diag("inspect", "open_requested", {"suppress_until": _suppress_refresh_until_msec, "name": agg_data.get("display_name", "")})

	# If panel already shown, safely remove it deferred
	if item_row_hbox.has_meta("inspect_panel"):
		var existing_panel: Node = item_row_hbox.get_meta("inspect_panel")
		if is_instance_valid(existing_panel):
			list_container.call_deferred("remove_child", existing_panel)
			existing_panel.call_deferred("queue_free")
			_diag("inspect", "existing_removed")
		item_row_hbox.remove_meta("inspect_panel")
		# Remove cargo_ids for this row from persistence set
		if agg_data.has("items") and agg_data["items"] is Array:
			for it in agg_data["items"]:
				var cid := str((it as Dictionary).get("cargo_id", ""))
				if not cid.is_empty():
					_open_inspects.erase(cid)
					_diag("inspect", "persist_remove", {"cargo_id": cid})
		if is_instance_valid(toggle_button):
			toggle_button.text = "Inspect"
		return

	item_row_hbox.set_meta("inspect_building", true)
	var panel := _build_inline_inspect_panel(agg_data, item_row_hbox)
	var row_index := list_container.get_children().find(item_row_hbox)
	if row_index == -1:
		list_container.add_child(panel)
	else:
		list_container.add_child(panel)
		list_container.move_child(panel, row_index + 1)
	_diag("inspect", "panel_added", {"row_index": row_index})
	item_row_hbox.set_meta("inspect_panel", panel)
	item_row_hbox.remove_meta("inspect_building")
	# Persist cargo_ids for this row so we can reopen after refresh
	if agg_data.has("items") and agg_data["items"] is Array:
		for it in agg_data["items"]:
			var cid := str((it as Dictionary).get("cargo_id", ""))
			if not cid.is_empty():
				_open_inspects[cid] = true
				_diag("inspect", "persist_add", {"cargo_id": cid})
	if is_instance_valid(toggle_button):
		toggle_button.text = "Hide"

	# Post-open verification: check if panel remains after short delays
	var verify_token := "" 
	if agg_data.has("items") and agg_data["items"] is Array and agg_data["items"].size() > 0:
		var first: Variant = agg_data["items"][0]
		var first_dict: Dictionary = first if first is Dictionary else {}
		verify_token = str(first_dict.get("cargo_id", agg_data.get("display_name", "")))
	_call_verify_inspect_persistence(item_row_hbox, verify_token, 0.5)
	_call_verify_inspect_persistence(item_row_hbox, verify_token, 1.2)

func _call_verify_inspect_persistence(row: HBoxContainer, token: String, delay_sec: float) -> void:
	# Use a timer to re-check panel presence and log if missing
	var t := get_tree().create_timer(delay_sec)
	t.timeout.connect(func():
		var present := row.has_meta("inspect_panel") and is_instance_valid(row.get_meta("inspect_panel"))
		var status := "present" if present else "missing"
		_diag("inspect_verify", status, {"after_sec": delay_sec, "token": token})
	)

func _reopen_inspects() -> void:
	# Re-open inspect panels for any rows whose cargo_ids intersect `_open_inspects`
	if _open_inspects.is_empty():
		return
	var reopen_count := 0
	for child in cargo_items_vbox.get_children():
		if child.has_meta("agg_data"):
			var agg_data: Dictionary = child.get_meta("agg_data")
			var items: Array = agg_data.get("items", [])
			var should_reopen := false
			for it in items:
				var cid := str((it as Dictionary).get("cargo_id", ""))
				if not cid.is_empty() and _open_inspects.has(cid):
					should_reopen = true
					break
			if should_reopen:
				var toggle_button: Button = child.find_child("InspectButton", true, false)
				if is_instance_valid(toggle_button):
					_on_inspect_cargo_item_pressed(agg_data, cargo_items_vbox, child, toggle_button)
					_diag("inspect_reopen", "row", {"name": agg_data.get("display_name", ""), "count_items": items.size()})
					reopen_count += 1
	_diag("inspect_reopen", "done", {"count": reopen_count})

func _build_inline_inspect_panel(agg_data: Dictionary, _item_row_hbox: HBoxContainer) -> VBoxContainer:
	var item_data_sample: Dictionary = agg_data["item_data_sample"]
	_diag("inspect_panel", "build_start", {"name": agg_data.get("display_name", ""), "qty": agg_data.get("total_quantity", 0)})
	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 4)

	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)

	# No header controls; panel is toggled via the row button.

	var data_copy: Dictionary = item_data_sample.duplicate(true)
	# Overwrite/ensure core aggregated values are present and correct.
	# This is the source of truth for the entire stack. We use .get() and float()
	# to be defensive against malformed data, ensuring we always have a number to display.
	data_copy["quantity"] = agg_data["total_quantity"]
	data_copy["weight"] = float(agg_data.get("total_weight", 0.0))
	data_copy["volume"] = float(agg_data.get("total_volume", 0.0))

	# Fallback: synthesize totals from unit values if totals are missing/zero
	var f_qty := float(data_copy.get("quantity", 0))
	var unit_w := 0.0
	var unit_v := 0.0
	if data_copy.has("unit_weight") and data_copy.get("unit_weight") != null:
		unit_w = float(data_copy.get("unit_weight", 0.0))
	elif data_copy.has("weight") and f_qty > 0 and float(data_copy.get("weight", 0.0)) > 0:
		# Infer unit from total if needed
		unit_w = float(data_copy.get("weight", 0.0)) / f_qty
	if data_copy.has("unit_volume") and data_copy.get("unit_volume") != null:
		unit_v = float(data_copy.get("unit_volume", 0.0))
	elif data_copy.has("volume") and f_qty > 0 and float(data_copy.get("volume", 0.0)) > 0:
		unit_v = float(data_copy.get("volume", 0.0)) / f_qty

	if float(data_copy.get("weight", 0.0)) <= 0.0 and unit_w > 0.0 and f_qty > 0.0:
		data_copy["weight"] = unit_w * f_qty
	if float(data_copy.get("volume", 0.0)) <= 0.0 and unit_v > 0.0 and f_qty > 0.0:
		data_copy["volume"] = unit_v * f_qty

	# Ensure unit values exist for display in "Other Details"
	var f_quantity = float(data_copy.get("quantity", 0))
	var total_w = float(data_copy.get("weight", 0))
	var total_v = float(data_copy.get("volume", 0))
	if not data_copy.has("unit_weight") and f_quantity > 0 and total_w > 0:
		data_copy["unit_weight"] = total_w / f_quantity
	if not data_copy.has("unit_volume") and f_quantity > 0 and total_v > 0:
		data_copy["unit_volume"] = total_v / f_quantity

	# If item looks like a part, inject modifiers so they can appear in Other Details.
	_inject_part_modifiers(data_copy)

	# Collect all other keys to display in a single grid.
	var all_details_keys: Array = []
	var is_resource := _looks_like_resource(data_copy)

	# Translate recipient/destination vendor IDs to names for readability
	# Prefer explicit vendor id fields, otherwise try 'recipient' value directly
	var recipient_id := String(data_copy.get("recipient_vendor_id", data_copy.get("destination_vendor_id", data_copy.get("mission_vendor_id", ""))))
	if recipient_id == "" and data_copy.has("recipient") and (data_copy.get("recipient") is String):
		recipient_id = String(data_copy.get("recipient"))
	if recipient_id != "":
		var recip_name := _resolve_vendor_name(recipient_id)
		if recip_name != "":
			# Replace plain recipient string if it equals the id
			if data_copy.has("recipient") and (data_copy.get("recipient") is String):
				var rec_s := String(data_copy.get("recipient"))
				if rec_s == recipient_id:
					data_copy["recipient"] = recip_name
		# Also inject recipient_settlement_name if available
		var recip_settlement := _resolve_settlement_name_for_vendor(recipient_id)
		if recip_settlement != "":
			data_copy["recipient_settlement_name"] = recip_settlement
	for k in data_copy.keys():
		if _should_hide_key(k):
			continue
		# Exclude fields now shown on the main row or otherwise undesirable here.
		if k in ["quantity", "weight", "volume", "creation_date", "pending_deletion", "name", "base_name"]:
			continue
		# Show weight/dry_weight only for resource items
		if (k == "weight" or k == "dry_weight" or k == "unit_dry_weight") and not is_resource:
			continue
		var v = data_copy[k]
		if v == null or str(v) == "":
			continue
		var t = typeof(v)
		if t == TYPE_ARRAY and (v as Array).size() <= 50: # allow larger arrays
			all_details_keys.append(k)
		elif t in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			all_details_keys.append(k)
	all_details_keys.sort()

	# Add all collected keys to a single grid inside the panel.
	_add_grid(inner, data_copy, all_details_keys)
	_diag("inspect_panel", "build_done", {"keys": all_details_keys.size()})

	frame.add_child(inner)
	container.add_child(frame)
	return container

func _on_title_label_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		print("ConvoyCargoMenu: Title clicked. Emitting 'return_to_convoy_overview_requested'.")
		emit_signal("return_to_convoy_overview_requested", convoy_data_received)
		get_viewport().set_input_as_handled()

func _inspect_item_on_load():
	if _item_to_inspect_on_load == null:
		return

	var target_cargo_id = str(_item_to_inspect_on_load.get("cargo_id", ""))
	if target_cargo_id.is_empty():
		printerr("ConvoyCargoMenu: Cannot inspect item on load, target item has no cargo_id.")
		_item_to_inspect_on_load = null
		return

	for child in cargo_items_vbox.get_children():
		if child.has_meta("agg_data"):
			var agg_data = child.get_meta("agg_data")
			var items = agg_data.get("items", [])
			for item in items:
				if str(item.get("cargo_id", "")) == target_cargo_id:
					var item_row_hbox = child
					var list_container = cargo_items_vbox
					var toggle_button = item_row_hbox.find_child("InspectButton", true, false)

					if is_instance_valid(toggle_button):
						_on_inspect_cargo_item_pressed(agg_data, list_container, item_row_hbox, toggle_button)

						var scroll_container = cargo_items_vbox.get_parent()
						if scroll_container is ScrollContainer:
							await get_tree().process_frame # Wait for inspect panel to be added
							scroll_container.ensure_control_visible(item_row_hbox)

						_item_to_inspect_on_load = null # Clear after use
						return

	_item_to_inspect_on_load = null # Clear even if not found
	printerr("ConvoyCargoMenu: Could not find item to inspect on load with cargo_id: ", target_cargo_id)


func _on_store_convoys_changed(all_convoy_data: Array) -> void:
	# Update convoy_data_received if this convoy is present in the update
	if not convoy_data_received or not convoy_data_received.has("convoy_id"):
		return

	# If we're within the suppress window, skip rebuilding to avoid closing inspect
	var now := Time.get_ticks_msec()
	_diag("store_update", "received", {"now": now, "suppress_until": _suppress_refresh_until_msec})
	if now < _suppress_refresh_until_msec:
		_diag("store_update", "suppressed")
		return
	var current_id = str(convoy_data_received.get("convoy_id"))
	for convoy in all_convoy_data:
		if convoy.has("convoy_id") and str(convoy.get("convoy_id")) == current_id:
			var prev_count := int((convoy_data_received.get("vehicle_details_list", []) as Array).size())
			convoy_data_received = convoy.duplicate(true)
			var new_count := int((convoy_data_received.get("vehicle_details_list", []) as Array).size())
			_diag("store_update", "convoy_match", {"prev_vehicle_count": prev_count, "new_vehicle_count": new_count})
			_diag("store_update", "repopulate_start")
			_populate_cargo_list()
			_diag("store_update", "repopulate_done")
			break
