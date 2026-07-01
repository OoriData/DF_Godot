extends PanelContainer

signal transfer_requested(item_data)

var item_data: Dictionary

var _name_label: Label
var _qty_label: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(160, 100)

	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.METAL_BASE
	sb.border_color = UITheme.METAL_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(UITheme.RADIUS_LG)
	add_theme_stylebox_override("panel", sb)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UITheme.SPACE_SM)
	margin.add_theme_constant_override("margin_right", UITheme.SPACE_SM)
	margin.add_theme_constant_override("margin_top", UITheme.SPACE_SM)
	margin.add_theme_constant_override("margin_bottom", UITheme.SPACE_SM)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SPACE_XS)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_name_label)

	_qty_label = Label.new()
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty_label.add_theme_font_size_override("font_size", 18)
	_qty_label.add_theme_color_override("font_color", UITheme.ACCENT_BRASS)
	_qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_qty_label)

func _ready() -> void:
	pivot_offset = size / 2.0
	resized.connect(func(): pivot_offset = size / 2.0)

func setup(data: Dictionary) -> void:
	item_data = data
	_name_label.text = String(data.get("name", "Unknown"))
	_qty_label.text = "x%d" % int(data.get("quantity", 0))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("transfer_requested", item_data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		var sb := get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			sb.border_color = UITheme.ACCENT_BRASS
	elif what == NOTIFICATION_MOUSE_EXIT:
		var sb := get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			sb.border_color = UITheme.METAL_EDGE
