extends PopupPanel
class_name DiscordPopup

signal closed

const DISCORD_LINK = "https://discord.gg/nS7NVC7PaK"

var _root: VBoxContainer
var _debug_lbl: Label

func _ready() -> void:
	_build_ui()
	wrap_controls = false # Prevent the window from expanding to fit miscalculated child sizes
	_apply_ui_scaling_recursive(self)

func _is_portrait() -> bool:
	# Use DisplayServer for more reliable screen orientation detection
	var screen_size = DisplayServer.window_get_size()
	return screen_size.y > screen_size.x

func _is_mobile() -> bool:
	var is_mobile_platform = OS.has_feature("mobile") or DisplayServer.get_name() in ["Android", "iOS"]
	# We only treat portrait as "mobile" if it's actually a mobile platform or if the user is on desktop with a very narrow window
	return is_mobile_platform or (is_inside_tree() and _is_portrait())

func _get_font_size(base: int) -> int:
	var is_mobile_platform = OS.has_feature("mobile") or DisplayServer.get_name() in ["Android", "iOS"]
	var win_size = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(0, 0)
	var is_port = win_size.y > win_size.x
	
	# Enlarged base from 14 to 17
	var effective_base = 17 if base == 14 else base
	
	# Less aggressive boost on desktop even if portrait
	var boost: float
	if is_mobile_platform:
		boost = 2.4 if is_port else 1.8 # Increased boost slightly
	else:
		boost = 1.6 if is_port else 1.2
	
	return int(effective_base * boost)

func open_centered() -> void:
	var v_size = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(0, 0)
	print("[DiscordPopup] open_centered. Viewport: %s, OS: %s, Display: %s | LOUD LOG" % [v_size, OS.get_name(), DisplayServer.get_name()])
	
	var is_port = _is_portrait()
	var is_mob = _is_mobile()

	# Force a fresh scaling pass to ensure minimum sizes are up to date
	_apply_ui_scaling_recursive(self) 
	
	var win_size = DisplayServer.window_get_size()
	var win_w: int
	var win_h: int
	
	if is_port:
		win_w = min(win_size.x - 40, 800) # Increased max width
		win_h = 600 # Increased from 520
	elif is_mob:
		win_w = 640 # Increased from 600
		win_h = 420 # Increased from 360
	else:
		win_w = 520 # Increased from 480
		win_h = 300 # Increased from 240
	
	# Safety clamp: Ensure popup never exceeds 90% of screen size to prevent clipping
	win_w = min(win_w, int(win_size.x * 0.9))
	win_h = min(win_h, int(win_size.y * 0.9))

	# Constrain the root content width to help the Label calculate its wrapped height correctly
	var pad = 32 if is_port else 20
	if is_instance_valid(_root):
		_root.custom_minimum_size.x = win_w - (pad * 2)

	print("[DiscordPopup] Calculated dimensions: %dx%d (is_port=%s, is_mob=%s) | LOUD LOG" % [win_w, win_h, is_port, is_mob])
	if is_instance_valid(_debug_lbl):
		_debug_lbl.text = "V:%s P:%dx%d Port:%s Mob:%s" % [v_size, win_w, win_h, is_port, is_mob]
	
	# Explicitly set the window size before popup to override any previous state
	self.size = Vector2i(win_w, win_h)
	popup_centered(Vector2i(win_w, win_h))
	
	# Diagnostic: Check if any child is forcing an expansion
	var min_sz = _root.get_combined_minimum_size() if is_instance_valid(_root) else Vector2(0,0)
	print("[DiscordPopup] Post-Popup Root MinSize: %s, Window Size: %s" % [min_sz, self.size])
	
	print("[DiscordPopup] Visible Rect after popup_centered: %s" % [get_visible_rect()])
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
	var pad = 32 if _is_portrait() else 20 # Increased padding
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	add_child(margin)
# ...
	# Root content
	var root := VBoxContainer.new()
	root.name = "Root"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 24 if _is_portrait() else 12) # Increased separation
	margin.add_child(root)
	_root = root

	# Content layout - consolidated
	var info_lbl := Label.new()
	info_lbl.text = "Join our community to share feedback, receive updates and join the community!"
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_lbl.add_theme_font_size_override("font_size", _get_font_size(14))
	info_lbl.add_theme_color_override("font_color", Color("#5865F2")) # Discord Blurple
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(info_lbl)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24 if _is_portrait() else 20)
	root.add_child(btn_row)

	var join_btn := Button.new()
	join_btn.text = "Join Discord"
	join_btn.custom_minimum_size = Vector2(280 if _is_portrait() else 140, 48)
	_apply_discord_button_style(join_btn)
	join_btn.pressed.connect(_on_join_pressed)
	btn_row.add_child(join_btn)
	
	var cancel_btn := Button.new()
	cancel_btn.text = "Later"
	cancel_btn.custom_minimum_size = Vector2(180 if _is_portrait() else 100, 48)
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.pressed.connect(_on_close_pressed)
	btn_row.add_child(cancel_btn)

	# Debug Label (tiny at bottom)
	_debug_lbl = Label.new()
	_debug_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_debug_lbl.modulate = Color(1, 1, 1, 0.4)
	_debug_lbl.add_theme_font_size_override("font_size", 10)
	root.add_child(_debug_lbl)

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
	var win_size = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(0, 0)
	var is_portrait = win_size.y > win_size.x
	var is_mob_platform = OS.has_feature("mobile") or DisplayServer.get_name() in ["Android", "iOS"]
	
	if node is Button:
		node.add_theme_font_size_override("font_size", _get_font_size(14))
		var btn_name: String = node.name.to_lower() if is_instance_valid(node) else ""
		var want_huge = btn_name.contains("later") or btn_name.contains("cancel") or btn_name.contains("join")
		var target_h: int
		if is_portrait:
			target_h = 180 if want_huge else 140 # Increased from 160/130
		else:
			target_h = (90 if want_huge else 72) if (is_mob_platform or is_portrait) else 48 # Increased from 80/64
		if node.custom_minimum_size.y < target_h:
			node.custom_minimum_size.y = target_h
		if is_portrait:
			node.custom_minimum_size.x = max(node.custom_minimum_size.x, 320 if want_huge else 220) # Increased from 280/180
	elif node is Label:
		# Use a fixed base (14) to ensure idempotency when called multiple times
		node.add_theme_font_size_override("font_size", _get_font_size(14))
	
	for child in node.get_children():
		_apply_ui_scaling_recursive(child)
