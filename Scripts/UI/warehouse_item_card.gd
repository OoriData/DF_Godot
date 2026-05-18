extends PanelContainer

signal transfer_requested(item_data)

var item_data: Dictionary

var _icon_rect: TextureRect
var _name_label: Label
var _qty_label: Label
var _mini_bar: ProgressBar

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(160, 160)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	sb.border_color = Color(0.35, 0.45, 0.55, 0.7)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", sb)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)
	
	_icon_rect = TextureRect.new()
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.custom_minimum_size = Vector2(64, 64)
	_icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_icon_rect)
	
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1.0))
	vbox.add_child(_name_label)
	
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)
	
	_qty_label = Label.new()
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty_label.add_theme_font_size_override("font_size", 20)
	_qty_label.add_theme_color_override("font_color", Color(0.26, 1.0, 0.26, 1.0)) # Status Green
	vbox.add_child(_qty_label)
	
	_mini_bar = ProgressBar.new()
	_mini_bar.custom_minimum_size = Vector2(0, 6)
	_mini_bar.show_percentage = false
	_mini_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	bar_bg.corner_radius_top_left = 3
	bar_bg.corner_radius_top_right = 3
	bar_bg.corner_radius_bottom_left = 3
	bar_bg.corner_radius_bottom_right = 3
	var bar_fg = StyleBoxFlat.new()
	bar_fg.bg_color = Color(0.0, 0.66, 1.0, 1.0)
	bar_fg.corner_radius_top_left = 3
	bar_fg.corner_radius_top_right = 3
	bar_fg.corner_radius_bottom_left = 3
	bar_fg.corner_radius_bottom_right = 3
	_mini_bar.add_theme_stylebox_override("background", bar_bg)
	_mini_bar.add_theme_stylebox_override("fill", bar_fg)
	vbox.add_child(_mini_bar)

func _ready() -> void:
	# Set pivot offset for correct scale tweening from center
	pivot_offset = size / 2.0
	resized.connect(func(): pivot_offset = size / 2.0)

func setup(data: Dictionary) -> void:
	item_data = data
	var item_name = String(data.get("name", "Unknown"))
	var qty = int(data.get("quantity", 0))
	
	_name_label.text = item_name
	_qty_label.text = "x%d" % qty
	
	# Determine visual capacity (could be derived from stack size, default 1000)
	var max_cap = 1000.0
	if qty > max_cap: max_cap = float(qty) * 1.5
	_mini_bar.max_value = max_cap
	_mini_bar.value = min(float(qty), max_cap)
	
	var texture_path = _get_icon_for_category(item_name)
	if ResourceLoader.exists(texture_path):
		_icon_rect.texture = load(texture_path)
	else:
		# Simple fallback drawing if no specific icon
		_icon_rect.texture = null

func _get_icon_for_category(name: String) -> String:
	# Very basic heuristic for icons if they exist in standard paths
	var lower_name = name.to_lower()
	if "fuel" in lower_name:
		return "res://Assets/UI/Icons/fuel_barrel.png"
	if "iron" in lower_name or "ore" in lower_name:
		return "res://Assets/UI/Icons/iron_ore.png"
	if "ration" in lower_name or "food" in lower_name:
		return "res://Assets/UI/Icons/rations_crate.png"
	return "res://Assets/UI/Icons/generic_cargo.png"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("transfer_requested", item_data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2(1.03, 1.03), 0.1).set_trans(Tween.TRANS_SINE)
		var sb = get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			sb.border_color = Color(0.0, 0.66, 1.0, 1.0) # Neon blue glow
	elif what == NOTIFICATION_MOUSE_EXIT:
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE)
		var sb = get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			sb.border_color = Color(0.35, 0.45, 0.55, 0.7)
