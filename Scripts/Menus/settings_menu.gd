extends Window

@onready var s_ui_scale: HSlider = $Margin/VBox/UISec/UIScaleRow/UIScaleSlider
@onready var c_dynamic_scale: CheckBox = $Margin/VBox/UISec/DynamicScaleCheck # New
@onready var c_fullscreen: CheckBox = $Margin/VBox/DisplaySection/FullscreenCheck
@onready var resolution_opt: OptionButton = $Margin/VBox/DisplaySection/ResolutionRow/ResolutionOption
@onready var c_invert_pan: CheckBox = $Margin/VBox/ControlsSec/InvertPanCheck
@onready var c_invert_zoom: CheckBox = $Margin/VBox/ControlsSec/InvertZoomCheck
@onready var c_gestures: CheckBox = $Margin/VBox/ControlsSec/GesturesCheck
@onready var s_menu_ratio: HSlider = $Margin/VBox/UISec/MenuWidthRow/MenuWidthRatioSlider
@onready var c_high_contrast: CheckBox = $Margin/VBox/GameplaySec/HighContrastCheck
@onready var btn_reset: Button = $Margin/VBox/ButtonsRow/ResetDefaultsButton
@onready var btn_close: Button = $Margin/VBox/ButtonsRow/CloseButton
@onready var btn_logout: Button = $Margin/VBox/ButtonsRow/LogoutButton

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

	# Make the window's titlebar close button work
	if not is_connected("close_requested", Callable(self, "_on_close_requested")):
		close_requested.connect(_on_close_requested)

	_init_values()
	_wire_events()

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
	_populate_resolution_options()
	_init_resolution_selection()
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
	resolution_opt.item_selected.connect(_on_resolution_selected)
	c_invert_pan.toggled.connect(func(b): SM.set_and_save("controls.invert_pan", b))
	c_invert_zoom.toggled.connect(func(b): SM.set_and_save("controls.invert_zoom", b))
	c_gestures.toggled.connect(func(b): SM.set_and_save("controls.gestures_enabled", b))
	s_menu_ratio.value_changed.connect(func(v): SM.set_and_save("ui.menu_open_ratio", v))
	c_high_contrast.toggled.connect(func(b): SM.set_and_save("access.high_contrast", b))
	# removed reduce motion and route preview

	if is_instance_valid(btn_close):
		btn_close.pressed.connect(func(): hide())
	if is_instance_valid(btn_reset):
		btn_reset.pressed.connect(_on_reset_defaults)
	if is_instance_valid(btn_logout):
		btn_logout.pressed.connect(_on_logout_pressed)

func _on_reset_defaults():
	var defaults := {
		"ui.scale": 1.4,
		"ui.auto_scale": false, # Default off
		"ui.menu_open_ratio": 0.5, # Match new default
		"ui.click_closes_menus": false,
		"access.high_contrast": false,
		"display.fullscreen": false,
		"display.resolution": Vector2i(1280, 720),
		"controls.invert_pan": false,
		"controls.invert_zoom": false,
		"controls.gestures_enabled": true,
	}
	for k in defaults.keys():
		SM.set_and_save(k, defaults[k])
	_init_values()

func _on_close_requested():
	hide()

func _populate_resolution_options():
	resolution_opt.clear()
	var list: Array[Vector2i] = [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
		Vector2i(3840, 2160),
	]
	for res in list:
		resolution_opt.add_item("%dx%d" % [res.x, res.y])
		resolution_opt.set_item_metadata(resolution_opt.item_count - 1, res)

func _init_resolution_selection():
	var current: Variant = SM.get_value("display.resolution", Vector2i(1280, 720))
	var cur: Vector2i = current if current is Vector2i else Vector2i(int(current.x), int(current.y))
	for i in range(resolution_opt.item_count):
		var meta: Variant = resolution_opt.get_item_metadata(i)
		if meta is Vector2i and meta == cur:
			resolution_opt.select(i)
			break

func _on_resolution_selected(index: int):
	var meta: Variant = resolution_opt.get_item_metadata(index)
	if meta is Vector2i:
		SM.set_and_save("display.resolution", meta)

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
