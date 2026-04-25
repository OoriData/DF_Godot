extends CanvasLayer
class_name DiscordLinkPopup

signal closed

const _BG_COLOR         := Color("#161616")
const _BORDER_COLOR     := Color("#2e2e2e")
const _TEXT_LIGHT       := Color("#eaeaea")
const _TEXT_DIM         := Color("#9a9ab0")
const _DISCORD_BLURPLE  := Color("#5865F2")
const _GREEN_SUCCESS    := Color("#a4d007")

var _overlay: Control
var _root: VBoxContainer
var _api: Node

func _ready() -> void:
	layer = 101 # Above AccountLinksPopup
	visible = false
	_api = get_node_or_null("/root/APICalls")
	_build_ui()
	_apply_ui_scaling_recursive(self)

func _is_portrait() -> bool:
	if is_inside_tree():
		var win_size = get_viewport().get_visible_rect().size
		return win_size.y > win_size.x
	return false

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or DisplayServer.get_name() in ["Android", "iOS"] or _is_portrait()

func _get_font_size(base: int) -> int:
	var boost = 2.2 if _is_portrait() else (1.7 if _is_mobile() else 1.2)
	return int(base * boost)

func open_centered() -> void:
	print("[DiscordLinkPopup] open_centered called | LOUD LOG")
	show()

func _on_close_pressed() -> void:
	hide()
	closed.emit()
	queue_free()

func _on_continue_pressed() -> void:
	if is_instance_valid(_api):
		_api.get_discord_link_url()
	hide()
	closed.emit()
	queue_free()

func _build_ui() -> void:
	var is_port = _is_portrait()
	# Full-screen overlay
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _BG_COLOR
	panel_style.border_color = _BORDER_COLOR
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", panel_style)
	
	var win_size = DisplayServer.window_get_size()
	var win_w: int
	var win_h: int
	if is_port:
		win_w = min(win_size.x - 32, 600)
		win_h = min(win_size.y - 200, 500)
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		panel.offset_top += 80 # Shift down to clear nav bar
		panel.offset_bottom += 80
	elif _is_mobile():
		win_w = 480
		win_h = 320
	else:
		win_w = 380
		win_h = 200
		
	panel.custom_minimum_size = Vector2(win_w, win_h)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_overlay.add_child(panel)

	var margin := MarginContainer.new()
	var pad = 24 if is_port else 20
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18 if is_port else 12)
	margin.add_child(root)
	_root = root

	# Title
	var title := Label.new()
	title.text = "Link Discord Account"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _get_font_size(16))
	title.add_theme_color_override("font_color", _DISCORD_BLURPLE)
	root.add_child(title)

	# Description
	var desc := Label.new()
	desc.text = "Linking your Discord account will allow you to sync your progress across platforms and identify you in the community."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", _get_font_size(13))
	desc.add_theme_color_override("font_color", _TEXT_LIGHT)
	root.add_child(desc)

	# Info
	var info := Label.new()
	info.text = "This will open your web browser for authentication."
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", _get_font_size(11))
	info.add_theme_color_override("font_color", _TEXT_DIM)
	root.add_child(info)

	# Button row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24 if is_port else 16)
	root.add_child(btn_row)

	var continue_btn := Button.new()
	continue_btn.text = "Continue to Browser"
	continue_btn.custom_minimum_size = Vector2(220 if is_port else 160, 36)
	_apply_discord_button_style(continue_btn)
	continue_btn.pressed.connect(_on_continue_pressed)
	btn_row.add_child(continue_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100 if is_port else 80, 36)
	cancel_btn.pressed.connect(_on_close_pressed)
	btn_row.add_child(cancel_btn)

func _apply_discord_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = _DISCORD_BLURPLE
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = _DISCORD_BLURPLE.lightened(0.1)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = _DISCORD_BLURPLE.darkened(0.1)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color.WHITE)

func _apply_ui_scaling_recursive(node: Node) -> void:
	var is_port = _is_portrait()
	if node is Button:
		node.add_theme_font_size_override("font_size", _get_font_size(14))
		var btn_name: String = node.name.to_lower() if is_instance_valid(node) else ""
		var want_huge = btn_name.contains("cancel") or btn_name.contains("continue")
		var target_h: int
		if is_port:
			target_h = 100 if want_huge else 80
		else:
			target_h = (72 if want_huge else 52) if _is_mobile() else 40
		if node.custom_minimum_size.y < target_h:
			node.custom_minimum_size.y = target_h
	elif node is Label:
		var current_fs = node.get_theme_font_size("font_size")
		if current_fs <= 1: current_fs = 14
		node.add_theme_font_size_override("font_size", _get_font_size(current_fs))
	
	for child in node.get_children():
		_apply_ui_scaling_recursive(child)
