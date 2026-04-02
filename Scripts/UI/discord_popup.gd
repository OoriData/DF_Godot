extends PopupPanel
class_name DiscordPopup

signal closed

const DISCORD_LINK = "https://discord.gg/nS7NVC7PaK"

var _root: VBoxContainer

func _ready() -> void:
	_build_ui()
	_apply_ui_scaling_recursive(self)

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or DisplayServer.get_name() in ["Android", "iOS"]

func _get_font_size(base: int) -> int:
	var boost = 1.7 if _is_mobile() else 1.2
	return int(base * boost)

func open_centered() -> void:
	var win_w = 480 if _is_mobile() else 360
	var win_h = 240 if _is_mobile() else 100
	popup_centered(Vector2i(win_w, win_h))
	call_deferred("_refresh_layout")

func _refresh_layout() -> void:
	if is_instance_valid(_root):
		_root.queue_sort()
		_root.queue_redraw()

func _on_close_pressed() -> void:
	hide()
	closed.emit()

func _on_join_pressed() -> void:
	OS.shell_open(DISCORD_LINK)
	hide()
	closed.emit()

func _build_ui() -> void:
	# Style the popup panel itself
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#1E1E1E")
	panel_style.border_color = Color("#2E2E2E")
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	# Root content
	var root := VBoxContainer.new()
	root.name = "Root"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)
	_root = root

	# Content layout - consolidated
	var info_lbl := Label.new()
	info_lbl.text = "Join our community to share feedback, receive updates and join the community!"
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 14)
	info_lbl.add_theme_color_override("font_color", Color("#5865F2")) # Discord Blurple
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(info_lbl)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	root.add_child(btn_row)

	var join_btn := Button.new()
	join_btn.text = "Join Discord"
	join_btn.custom_minimum_size = Vector2(120, 32)
	_apply_discord_button_style(join_btn)
	join_btn.pressed.connect(_on_join_pressed)
	btn_row.add_child(join_btn)
	
	var cancel_btn := Button.new()
	cancel_btn.text = "Later"
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.pressed.connect(_on_close_pressed)
	btn_row.add_child(cancel_btn)

func _apply_discord_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#5865F2") # Discord Blurple
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 15
	normal.content_margin_right = 15

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#4752C4") # Darker Blurple

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#3C45A5")

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color("#FFFFFF"))

func _apply_ui_scaling_recursive(node: Node) -> void:
	if node is Button:
		node.add_theme_font_size_override("font_size", _get_font_size(14))
		var btn_name: String = node.name.to_lower() if is_instance_valid(node) else ""
		var want_huge = btn_name.contains("later") or btn_name.contains("cancel") or btn_name.contains("join")
		var target_h = (72 if want_huge else 52) if _is_mobile() else 40
		if node.custom_minimum_size.y < target_h:
			node.custom_minimum_size.y = target_h
	elif node is Label:
		var current_fs = node.get_theme_font_size("font_size")
		if current_fs <= 1: current_fs = 14 # Fallback
		node.add_theme_font_size_override("font_size", _get_font_size(current_fs))
	
	for child in node.get_children():
		_apply_ui_scaling_recursive(child)
