extends ScrollContainer
# Custom replacement for the vendor/convoy `Tree`. Renders category headers + selectable
# item rows as real Controls so each row can host an inline-expanding inspector (Concept A).
# Consumes the same `buckets` shape the TreeBuilder uses:
#   { "delivery": { key: agg_data, ... }, "vehicles": {...}, "parts": {...}, ... }
# where agg_data is a Dictionary with "display_name" and "item_data".
#
# Step 4 scope: category headers, selectable rows, selection highlight, and an
# item_selected(agg_data) signal that mirrors the old Tree's get_metadata(0) payload.
# Inline-expand body is stubbed via _build_row_body() for Step 6 to fill in.

signal item_selected(agg_data)

const _HEADER_COLOR := Color(0.952941, 0.835294, 0.305882, 1.0) # Oori gold
const _ROW_BORDER := Color(0.224, 0.239, 0.278, 1.0)            # #393d47
const _ROW_BG := Color(0.122, 0.133, 0.157, 1.0)               # #1f2228
const _ROW_SEL := Color(0.149, 0.157, 0.165, 1.0)              # selected fill
const _PRICE_COLOR := Color(0.952941, 0.835294, 0.305882, 1.0)

var _vbox: VBoxContainer
var _selected_panel: PanelContainer = null
var _selected_key: String = ""
var row_min_height: float = 48.0

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED # never scroll sideways
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 4)
	add_child(_vbox)

func clear_items() -> void:
	for c in _vbox.get_children():
		c.queue_free()
	_selected_panel = null

func set_buckets(buckets: Dictionary, category_order: Array) -> void:
	clear_items()
	for entry in category_order:
		var cat_key: String = String(entry[0])
		var cat_title: String = String(entry[1])
		var cat: Variant = buckets.get(cat_key, {})
		if cat is Dictionary and not (cat as Dictionary).is_empty():
			_add_category(cat_title, cat)

func _add_category(title: String, agg_dict: Dictionary) -> void:
	var header := Label.new()
	header.text = title
	header.add_theme_color_override("font_color", _HEADER_COLOR)
	header.add_theme_font_size_override("font_size", 18)
	_vbox.add_child(header)

	# Stable alphabetical order by display name (matches TreeBuilder default).
	var keys: Array = agg_dict.keys()
	keys.sort_custom(func(a, b): return _display_name(agg_dict[a]).to_lower() < _display_name(agg_dict[b]).to_lower())
	for k in keys:
		_add_row(String(k), agg_dict[k])

func _add_row(key: String, agg_data: Variant) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = row_min_height
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _row_style(false))

	var body := VBoxContainer.new()
	panel.add_child(body)

	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(header_row)

	var name_lbl := Label.new()
	name_lbl.text = _display_name(agg_data)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_lbl.add_theme_font_size_override("font_size", 18)
	header_row.add_child(name_lbl)

	var secondary := _row_secondary_text(agg_data)
	if secondary != "":
		var val_lbl := Label.new()
		val_lbl.text = secondary
		val_lbl.add_theme_color_override("font_color", _PRICE_COLOR)
		val_lbl.add_theme_font_size_override("font_size", 16)
		header_row.add_child(val_lbl)

	# Inline-expand body lives here (Step 6 fills it); hidden until selected.
	var detail := _build_row_body(agg_data)
	if detail != null:
		detail.visible = false
		body.add_child(detail)

	panel.set_meta("agg_key", key)
	panel.set_meta("agg_data", agg_data)
	if detail != null:
		panel.set_meta("detail", detail)
	panel.gui_input.connect(_on_row_input.bind(panel))
	_vbox.add_child(panel)

	if key == _selected_key:
		_apply_selection(panel)

func _on_row_input(event: InputEvent, panel: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_panel(panel)
	elif event is InputEventScreenTouch and event.pressed:
		_select_panel(panel)

func _select_panel(panel: PanelContainer) -> void:
	_apply_selection(panel)
	var agg_data: Variant = panel.get_meta("agg_data")
	emit_signal("item_selected", agg_data)

func _apply_selection(panel: PanelContainer) -> void:
	if _selected_panel != null and is_instance_valid(_selected_panel):
		_selected_panel.add_theme_stylebox_override("panel", _row_style(false))
		if _selected_panel.has_meta("detail"):
			var prev_detail: Variant = _selected_panel.get_meta("detail")
			if is_instance_valid(prev_detail):
				prev_detail.visible = false
	_selected_panel = panel
	_selected_key = String(panel.get_meta("agg_key"))
	panel.add_theme_stylebox_override("panel", _row_style(true))
	if panel.has_meta("detail"):
		var detail: Variant = panel.get_meta("detail")
		if is_instance_valid(detail):
			detail.visible = true

# Select by stable key after a rebuild (mirrors the Tree's selection-restore).
func select_key(key: String) -> bool:
	for child in _vbox.get_children():
		if child is PanelContainer and child.has_meta("agg_key") and String(child.get_meta("agg_key")) == key:
			_select_panel(child)
			return true
	return false

func get_selected_data() -> Variant:
	if _selected_panel != null and is_instance_valid(_selected_panel):
		return _selected_panel.get_meta("agg_data")
	return null

# --- Overridable detail body (Step 6) ---
func _build_row_body(_agg_data: Variant) -> Control:
	return null

# --- helpers ---
func _row_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _ROW_SEL if selected else _ROW_BG
	s.set_border_width_all(1)
	s.border_color = _PRICE_COLOR if selected else _ROW_BORDER
	s.set_corner_radius_all(6)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _display_name(agg_data: Variant) -> String:
	if agg_data is Dictionary:
		var d: Dictionary = agg_data
		if d.has("display_name"):
			return String(d.get("display_name"))
		if d.has("item_data") and d["item_data"] is Dictionary and (d["item_data"] as Dictionary).has("name"):
			return String((d["item_data"] as Dictionary).get("name"))
	return str(agg_data)

func _row_secondary_text(agg_data: Variant) -> String:
	# Best-effort price/quantity hint for the row; tolerant of missing fields.
	if agg_data is Dictionary:
		var d: Dictionary = agg_data
		var item: Variant = d.get("item_data", d)
		if item is Dictionary:
			for f in ["price", "base_price", "value"]:
				if (item as Dictionary).has(f):
					return "$%s" % str((item as Dictionary).get(f))
		if d.has("quantity"):
			return "x%s" % str(d.get("quantity"))
	return ""
