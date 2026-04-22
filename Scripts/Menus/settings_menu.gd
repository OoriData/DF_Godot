extends CanvasLayer

@onready var s_ui_scale: HSlider = %UIScaleSlider
@onready var c_dynamic_scale: CheckButton = %DynamicScaleCheck
@onready var c_fullscreen: CheckButton = %FullscreenCheck
@onready var c_invert_pan: CheckButton = %InvertPanCheck
@onready var c_invert_zoom: CheckButton = %InvertZoomCheck
@onready var c_gestures: CheckButton = %GesturesCheck
@onready var s_menu_ratio: HSlider = %MenuWidthRatioSlider
@onready var c_high_contrast: CheckButton = %HighContrastCheck
@onready var btn_reset: Button = %ResetDefaultsButton
@onready var btn_close: Button = %CloseButton
@onready var btn_logout: Button = %LogoutButton

var SM: Node
var API: Node

func _ready():
	SM = get_node_or_null("/root/SettingsManager")
	if not is_instance_valid(SM):
		push_error("SettingsMenu: SettingsManager not found")
		return

	API = get_node_or_null("/root/APICalls")
	if not is_instance_valid(API):
		push_error("SettingsMenu: APICalls autoload not found")

	_init_values()
	_wire_events()
	_add_version_label()
	
	_update_layout()
	get_viewport().size_changed.connect(_update_layout)

func _is_portrait() -> bool:
	var win_size = get_viewport().get_visible_rect().size
	return win_size.y > win_size.x

func _is_mobile() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.get_name() in ["Android", "iOS"]:
		return true
	return false

func _get_font_size(base: int) -> int:
	var is_portrait = _is_portrait()
	var boost = 3.5 if is_portrait else (1.6 if _is_mobile() else 1.2)
	return int(base * boost)

func _update_layout() -> void:
	if not is_inside_tree(): return
	
	var win_size = get_viewport().get_visible_rect().size
	var is_portrait = _is_portrait()
	var is_mobile = _is_mobile()
	
	var target_w: int
	var target_h: int
	
	if is_portrait:
		# Portrait: Reduced size to look like a modal
		target_w = int(win_size.x * 0.92)
		target_h = int(win_size.y * 0.82)
	else:
		# Landscape: width capped but comfortable, height strictly respects borders
		target_w = int(min(1200, win_size.x * 0.85))
		target_h = int(win_size.y * 0.88) # Always stays 6% away from top/bottom
	
	var panel = %Panel
	if is_instance_valid(panel):
		panel.custom_minimum_size = Vector2(target_w, target_h)
		panel.size = Vector2(target_w, target_h)
		
		# Ensure it's centered if using center anchors
		if panel.layout_mode == 1: # Anchors mode
			panel.offset_left = -target_w / 2
			panel.offset_right = target_w / 2
			panel.offset_top = -target_h / 2
			panel.offset_bottom = target_h / 2
			
		# Always use borders and corners to maintain modal appearance
		var style = panel.get_theme_stylebox("panel").duplicate()
		if style is StyleBoxFlat:
			style.set_border_width_all(1)
			style.corner_radius_top_left = 12
			style.corner_radius_top_right = 12
			style.corner_radius_bottom_left = 12
			style.corner_radius_bottom_right = 12
			panel.add_theme_stylebox_override("panel", style)
			
	var scroll = %Scroll
	if is_instance_valid(scroll):
		scroll.scroll_deadzone = 12 # Higher deadzone helpful for mobile scrolling over buttons
		
	var content_vbox = %ContentVBox
	if is_instance_valid(content_vbox):
		content_vbox.add_theme_constant_override("separation", 12 if is_portrait else 8)
		
	# Scale margins
	var margin_node = %Margin
	if is_instance_valid(margin_node) and margin_node is MarginContainer:
		var pad = 8 if is_portrait else 32
		margin_node.add_theme_constant_override("margin_left", pad)
		margin_node.add_theme_constant_override("margin_right", pad)
		margin_node.add_theme_constant_override("margin_top", pad)
		margin_node.add_theme_constant_override("margin_bottom", pad)
		
	var vbox_node = %VBox
	if is_instance_valid(vbox_node) and vbox_node is VBoxContainer:
		vbox_node.add_theme_constant_override("separation", 36 if is_portrait else 24)
		_apply_ui_scaling_recursive(vbox_node)
	
	# Platform specific visibility adjustments
	var ui_scale_row = %UIScaleRow
	if is_instance_valid(ui_scale_row):
		ui_scale_row.visible = not is_mobile
	
	var menu_width_row = %MenuWidthRow
	if is_instance_valid(menu_width_row):
		menu_width_row.visible = not is_mobile
	
	if is_instance_valid(c_dynamic_scale):
		c_dynamic_scale.visible = not is_mobile
	
	var display_sec = %DisplaySection
	if is_instance_valid(display_sec):
		display_sec.visible = not is_mobile
		
	# Scale action buttons
	var buttons_row = %ButtonsRow
	if is_instance_valid(buttons_row) and buttons_row is HBoxContainer:
		var spacer = buttons_row.get_node_or_null("LeftSpacer")
		if is_instance_valid(spacer):
			spacer.visible = is_portrait # Keep centered in portrait, maybe aligned in landscape? 
			# Actually user wants them centered or always visible. 
			# Center is safest.
		buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
		buttons_row.add_theme_constant_override("separation", 20 if is_portrait else 16)

	for btn in [btn_close, btn_reset, btn_logout]:
		if is_instance_valid(btn):
			var want_huge = btn.name.to_lower().contains("close")
			var btn_height: int
			var btn_width: int
			if is_portrait:
				btn_height = 145 if want_huge else 120
				btn_width = 300
			else:
				btn_height = 100 if want_huge else 80
				btn_width = 260
			btn.custom_minimum_size = Vector2(btn_width, btn_height)
			btn.add_theme_font_size_override("font_size", _get_font_size(18))
			btn.mouse_filter = Control.MOUSE_FILTER_STOP

func _apply_ui_scaling_recursive(node: Node) -> void:
	var is_portrait = _is_portrait()
	if node is CheckButton:
		node.add_theme_font_size_override("font_size", _get_font_size(16))
		node.custom_minimum_size.y = 80 if is_portrait else (75 if _is_mobile() else 48)
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	elif node is Button:
		node.add_theme_font_size_override("font_size", _get_font_size(16))
		node.custom_minimum_size.y = 80 if is_portrait else (75 if _is_mobile() else 54) # Slightly taller for non-mobile desktop
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	elif node is Label:
		var base_sz = 22 if node.name == "Header" else (20 if node.name.contains("Title") else 18)
		node.add_theme_font_size_override("font_size", _get_font_size(base_sz))
		node.mouse_filter = Control.MOUSE_FILTER_PASS # Allow drag through labels too
		
		# Apply distinct colors to section headers
		if node.name.contains("Title") or node.name == "Header":
			var color = Color(1, 1, 1) # Default
			match node.name:
				"Header": color = Color(0.2, 0.8, 0.6) # Mint/Teal Header
				"DisplayTitle": color = Color(0.4, 0.7, 1.0) # Sky Blue
				"UITitle": color = Color(1.0, 0.8, 0.4) # Gold
				"ControlsTitle": color = Color(1.0, 0.6, 0.2) # Orange
				"GameplayTitle": color = Color(0.4, 1.0, 0.4) # Green
			node.add_theme_color_override("font_color", color)
	
	elif node is VBoxContainer:
		# Reduce separation in landscape to fit more elements
		var sep = 10
		if not is_portrait:
			sep = 4 if node.name == "VBox" else 2 # Even tighter for containers
		node.add_theme_constant_override("separation", sep)
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	
	elif node is HSeparator:
		# Hide or minimize separators in landscape
		if not is_portrait:
			node.add_theme_constant_override("separation", 4)
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	elif node is HSlider:
		node.custom_minimum_size.y = 80 if is_portrait else (70 if _is_mobile() else 48)
		node.mouse_filter = Control.MOUSE_FILTER_PASS
		var slider_style = StyleBoxFlat.new()
		slider_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
		var pad = 22 if is_portrait else (18 if _is_mobile() else 12)
		slider_style.content_margin_top = pad
		slider_style.content_margin_bottom = pad
		slider_style.corner_radius_top_left = 6
		slider_style.corner_radius_top_right = 6
		slider_style.corner_radius_bottom_left = 6
		slider_style.corner_radius_bottom_right = 6
		node.add_theme_stylebox_override("slider", slider_style)
		
	for child in node.get_children():
		_apply_ui_scaling_recursive(child)

func _add_version_label():
	var version = ProjectSettings.get_setting("application/config/version", "0.0.0")
	var label = Label.new()
	label.text = "Desolate Frontiers v" + str(version)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(1, 1, 1, 0.4)
	
	var settings = LabelSettings.new()
	settings.font_size = 14
	label.label_settings = settings
	
	%VBox.add_child(label)

func _init_values():
	s_menu_ratio.min_value = 0.0
	s_menu_ratio.max_value = 1.0
	s_menu_ratio.step = 0.01
	
	# Fetch safe max scale to prevent broken UI
	var sm_scale = get_node_or_null("/root/ui_scale_manager")
	if is_instance_valid(sm_scale) and sm_scale.has_method("get_max_safe_scale"):
		s_ui_scale.max_value = sm_scale.get_max_safe_scale()
	
	s_ui_scale.value = float(SM.get_value("ui.scale", 1.4))
	
	var dyn = bool(SM.get_value("ui.auto_scale", false))
	if is_instance_valid(c_dynamic_scale):
		c_dynamic_scale.button_pressed = dyn
	s_ui_scale.editable = not dyn # Disable slider if dynamic is on
	
	c_fullscreen.button_pressed = bool(SM.get_value("display.fullscreen", false))
	c_invert_pan.button_pressed = bool(SM.get_value("controls.invert_pan", false))
	c_invert_zoom.button_pressed = bool(SM.get_value("controls.invert_zoom", false))
	c_gestures.button_pressed = bool(SM.get_value("controls.gestures_enabled", true))
	s_menu_ratio.value = float(SM.get_value("ui.menu_open_ratio", 0.5))
	c_high_contrast.button_pressed = bool(SM.get_value("access.high_contrast", false))

func _wire_events():
	s_ui_scale.value_changed.connect(_on_ui_scale_value_changed)
	s_ui_scale.drag_ended.connect(_on_ui_scale_drag_ended)
	
	if is_instance_valid(c_dynamic_scale):
		c_dynamic_scale.toggled.connect(func(b):
			SM.set_and_save("ui.auto_scale", b)
			s_ui_scale.editable = not b
			if b:
				# Trigger auto-adjust immediately
				var sm_scale = get_node_or_null("/root/ui_scale_manager")
				if is_instance_valid(sm_scale) and sm_scale.has_method("_auto_adjust_scale"):
					sm_scale._auto_adjust_scale()
		)
	
	c_fullscreen.toggled.connect(func(b): SM.set_and_save("display.fullscreen", b))
	c_invert_pan.toggled.connect(func(b): SM.set_and_save("controls.invert_pan", b))
	c_invert_zoom.toggled.connect(func(b): SM.set_and_save("controls.invert_zoom", b))
	c_gestures.toggled.connect(func(b): SM.set_and_save("controls.gestures_enabled", b))
	s_menu_ratio.value_changed.connect(func(v): SM.set_and_save("ui.menu_open_ratio", v))
	c_high_contrast.toggled.connect(func(b): SM.set_and_save("access.high_contrast", b))
	# removed reduce motion and route preview

	if is_instance_valid(btn_close):
		btn_close.pressed.connect(func(): 
			print("[SettingsMenu] Close pressed")
			hide()
		)
	
	# Close on background click
	var dim_bg = %DimBackground
	if is_instance_valid(dim_bg):
		dim_bg.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				print("[SettingsMenu] Background clicked, closing")
				hide()
		)
	if is_instance_valid(btn_reset):
		btn_reset.pressed.connect(func():
			print("[SettingsMenu] Reset pressed")
			_on_reset_defaults()
		)
	if is_instance_valid(btn_logout):
		btn_logout.pressed.connect(func():
			print("[SettingsMenu] Logout pressed")
			_on_logout_pressed()
		)

func _on_reset_defaults():
	var defaults := {
		"ui.scale": 1.4,
		"ui.auto_scale": false, # Default off
		"ui.menu_open_ratio": 0.5, # Match new default
		"ui.click_closes_menus": false,
		"access.high_contrast": false,
		"display.fullscreen": false,
		"controls.invert_pan": false,
		"controls.invert_zoom": false,
		"controls.gestures_enabled": true,
	}
	for k in defaults.keys():
		SM.set_and_save(k, defaults[k])
	_init_values()


func _on_ui_scale_value_changed(_v: float):
	# Optional: We could apply a "preview" scale here without saving,
	# but content_scale_factor is quite heavy. Let's stick to debounced or drag_ended.
	pass

func _on_ui_scale_drag_ended(changed: bool):
	if changed:
		SM.set_and_save("ui.scale", s_ui_scale.value)

func _on_logout_pressed():
	if is_instance_valid(API) and API.has_method("logout"):
		API.logout()
	hide()

	# Ask the active GameRoot (GameScreenManager) to return to the login screen.
	var scene_root := get_tree().current_scene
	if is_instance_valid(scene_root) and scene_root.has_method("logout_to_login"):
		scene_root.logout_to_login()
	else:
		# Fallback: reload the main scene (autoloads persist, but this at least restores the login UI).
		get_tree().reload_current_scene()
