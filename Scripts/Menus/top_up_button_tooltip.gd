extends Button

const TOOLTIP_MIN_WIDTH := 260

func _make_custom_tooltip(for_text: String) -> Object:
	if not for_text.begins_with("Top Up Plan"):
		return null
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 1.0)
	style.border_color = Color(0.95, 0.95, 1.0, 1.0)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_color = Color(0,0,0,0.9)
	style.shadow_size = 10
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, 10)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var lines: Array = for_text.split('\n')
	var font := get_theme_font("font", "Label")
	var font_size := get_theme_font_size("font_size", "Label")
	var line_height := 16
	if font:
		line_height = int(font.get_height(font_size))
	var total_height := 0
	for i in range(lines.size()):
		var l := Label.new()
		l.text = lines[i]
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", Color(1,1,1,1))
		if i == 0:
			l.add_theme_color_override("font_color", Color(0.8,0.95,1.0,1))
			l.add_theme_font_size_override("font_size", font_size + 2)
		vbox.add_child(l)
		total_height += line_height

	if total_height < 20:
		total_height = 20 * max(1, lines.size())
	panel.custom_minimum_size = Vector2(TOOLTIP_MIN_WIDTH, total_height + 20)
	panel.reset_size()
	return panel
