extends Control

func _ready() -> void:
	$Panel/VBoxContainer/CloseButton.pressed.connect(_on_close_pressed)
	
	# Create a beautiful dark backing scrim to completely block/obscure map clutter behind the modal
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(0.03, 0.04, 0.06, 0.82) # Premium dark slate scrim with high opacity
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP # Prevent interacting with elements behind the modal
	add_child(scrim)
	move_child(scrim, 0) # Render scrim behind the main modal Panel
	
	# Dynamically resize the root control to the full viewport size to keep scrim working during resize
	_update_full_screen_size()
	get_viewport().size_changed.connect(_update_full_screen_size)
	
	# Apply premium, solid/opaque Oori theme panel styling to make the modal card highly legible
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#12151c") # Solid deep charcoal/navy
	panel_style.border_color = Color("#293545") # Elegant subtle teal-blue border
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.shadow_size = 16
	panel_style.shadow_offset = Vector2(0, 8)
	$Panel.add_theme_stylebox_override("panel", panel_style)
	
	# Apply themed custom styling to the GOT IT close button
	_apply_premium_button_style($Panel/VBoxContainer/CloseButton)
	
	if _is_mobile():
		_apply_mobile_scaling()

func _update_full_screen_size() -> void:
	if is_inside_tree():
		custom_minimum_size = get_viewport().get_visible_rect().size

func _apply_premium_button_style(btn: Button) -> void:
	var base_color := Color(0.282353, 0.721569, 0.658824, 1) # Matches the subtitle accent teal
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = base_color
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = base_color.lightened(0.12)
	
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = base_color.darkened(0.18)
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color("#ffffff"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("#e0e0e0"))

func _is_portrait() -> bool:
	if is_inside_tree():
		var win_size = get_viewport().get_visible_rect().size
		return win_size.y > win_size.x
	return false

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or DisplayServer.get_name() in ["Android", "iOS"] or _is_portrait()

func _get_font_size(base: int) -> int:
	return base

func _apply_mobile_scaling() -> void:
	var is_port = _is_portrait()
	var win_size = get_viewport().get_visible_rect().size
	
	var panel = $Panel
	if is_port:
		var target_w = int(win_size.x * 0.88)
		var target_h = int(win_size.y * 0.72) # Capped to look like a modal
		panel.custom_minimum_size = Vector2(target_w, target_h)
		panel.offset_left = -target_w / 2
		panel.offset_right = target_w / 2
		panel.offset_top = -target_h / 2
		panel.offset_bottom = target_h / 2
	else:
		panel.custom_minimum_size = Vector2(min(800, win_size.x - 40), min(600, win_size.y - 40))
	
	var close_btn = $Panel/VBoxContainer/CloseButton
	close_btn.custom_minimum_size = Vector2(280 if is_port else 220, 100 if is_port else 80)
	close_btn.add_theme_font_size_override("font_size", _get_font_size(18))
	
	var title = $Panel/VBoxContainer/Title
	title.add_theme_font_size_override("font_size", _get_font_size(36))
	
	var content_vbox = $Panel/VBoxContainer/ScrollContainer/Content
	content_vbox.add_theme_constant_override("separation", 32 if is_port else 20)
	
	for child in content_vbox.get_children():
		if child is VBoxContainer:
			var subtitle = child.get_node_or_null("SubTitle")
			if subtitle:
				subtitle.add_theme_font_size_override("font_size", _get_font_size(24))
			var text_node = child.get_node_or_null("Text")
			if text_node:
				text_node.add_theme_font_size_override("font_size", _get_font_size(18))

func _on_close_pressed() -> void:
	queue_free()

func open() -> void:
	show()
