extends Window

@onready var s_ui_scale: HSlider = $Margin/VBox/UISec/UIScaleRow/UIScaleSlider
@onready var c_fullscreen: CheckBox = $Margin/VBox/DisplaySection/FullscreenCheck
@onready var resolution_opt: OptionButton = $Margin/VBox/DisplaySection/ResolutionRow/ResolutionOption
@onready var c_invert_pan: CheckBox = $Margin/VBox/ControlsSec/InvertPanCheck
@onready var c_invert_zoom: CheckBox = $Margin/VBox/ControlsSec/InvertZoomCheck
@onready var c_gestures: CheckBox = $Margin/VBox/ControlsSec/GesturesCheck
@onready var s_menu_ratio: HSlider = $Margin/VBox/UISec/MenuWidthRow/MenuWidthRatioSlider
@onready var c_high_contrast: CheckBox = $Margin/VBox/GameplaySec/HighContrastCheck
@onready var btn_reset: Button = $Margin/VBox/ButtonsRow/ResetDefaultsButton
@onready var btn_close: Button = $Margin/VBox/ButtonsRow/CloseButton

var SM: Node

func _ready():
	SM = get_node_or_null("/root/SettingsManager")
	if not is_instance_valid(SM):
		push_error("SettingsMenu: SettingsManager not found")
		return

	# Make the window's titlebar close button work
	if not is_connected("close_requested", Callable(self, "_on_close_requested")):
		close_requested.connect(_on_close_requested)

	_init_values()
	_wire_events()

func _init_values():
	s_ui_scale.value = float(SM.get_value("ui.scale", 1.4))
	c_fullscreen.button_pressed = bool(SM.get_value("display.fullscreen", false))
	_populate_resolution_options()
	_init_resolution_selection()
	c_invert_pan.button_pressed = bool(SM.get_value("controls.invert_pan", false))
	c_invert_zoom.button_pressed = bool(SM.get_value("controls.invert_zoom", false))
	c_gestures.button_pressed = bool(SM.get_value("controls.gestures_enabled", true))
	s_menu_ratio.value = float(SM.get_value("ui.menu_open_ratio", 2.0))
	c_high_contrast.button_pressed = bool(SM.get_value("access.high_contrast", false))

func _wire_events():
	s_ui_scale.value_changed.connect(func(v): SM.set_and_save("ui.scale", v))
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

func _on_reset_defaults():
	var defaults := {
		"ui.scale": 1.4,
		"ui.menu_open_ratio": 2.0,
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
