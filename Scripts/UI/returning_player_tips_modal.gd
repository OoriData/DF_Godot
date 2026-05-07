extends Control

func _ready() -> void:
	$Panel/VBoxContainer/CloseButton.pressed.connect(_on_close_pressed)
	if _is_mobile():
		_apply_mobile_scaling()

func _is_portrait() -> bool:
	if is_inside_tree():
		var win_size = get_viewport().get_visible_rect().size
		return win_size.y > win_size.x
	return false

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or DisplayServer.get_name() in ["Android", "iOS"] or _is_portrait()

func _get_font_size(base: int) -> int:
	var boost = 2.4 if _is_portrait() else (1.7 if _is_mobile() else 1.2)
	return int(base * boost)

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
