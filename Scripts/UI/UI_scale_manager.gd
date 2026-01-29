extends Node


## The base resolution the UI was designed for.
## Used with Project Stretch settings to ensure consistent scaling.
const BASE_RESOLUTION = Vector2(1920, 1080)

## Signal emitted when the global UI scale multiplier changes.
signal scale_changed(new_scale)


var _global_ui_scale: float = 1.4

var _auto_adjust_done: bool = false

func _ready():
	# Try to pull from settings first
	var sm = get_node_or_null("/root/SettingsManager")
	var pulled_from_settings = false
	if is_instance_valid(sm):
		var val = sm.get_value("ui.scale")
		if val != null:
			_global_ui_scale = float(val)
			set_global_ui_scale(_global_ui_scale)
			pulled_from_settings = true
			_auto_adjust_done = true # Flag that we have a valid scale context
	
	if not pulled_from_settings:
		_auto_adjust_scale()
	
	get_viewport().size_changed.connect(_on_size_changed)

func _on_size_changed():
	# Always re-assert the scale in case Godot reset it during resize
	set_global_ui_scale(_global_ui_scale)
	
	# Only re-calculate the auto heuristic if the user HAS NOT set a value.
	var sm = get_node_or_null("/root/SettingsManager")
	var has_setting = false
	if is_instance_valid(sm):
		has_setting = sm.data.has("ui.scale")
	
	if not has_setting:
		_auto_adjust_scale()

func _auto_adjust_scale():
	# Simple heuristic for mobile/high-DPI scaling
	var screen_dpi = DisplayServer.screen_get_dpi()
	var screen_size = DisplayServer.screen_get_size()
	var screen_height = screen_size.y
	
	# If DPI is high, we likely need larger UI
	var dpi_scale = 1.0
	if screen_dpi > 150: 
		dpi_scale = 1.5
	if screen_dpi > 250:
		dpi_scale = 2.0
	if screen_dpi > 350:
		dpi_scale = 3.0
	if screen_dpi > 450:
		dpi_scale = 5.0
		
	# Adjust based on height (baseline 1080p)
	var height_scale = float(screen_height) / 1080.0
	
	# Combine and clamp
	var target_scale = clampf(dpi_scale * height_scale, 1.0, 6.0)
	
	# Check if we should apply this. If a SettingsManager exists and has a value, 
	# that should probably win, unless this is the first boot.
	var sm = get_node_or_null("/root/SettingsManager")
	if is_instance_valid(sm):
		var has_setting = sm.data.has("ui.scale")
		if has_setting and _auto_adjust_done:
			# Logic: We've already done our boot adjustment or pulled from settings.
			# Let the manual scale win.
			return

	_auto_adjust_done = true
	set_global_ui_scale(target_scale)
	print("[UIScaleManager] Applied auto-scale: ", target_scale, " (DPI:", screen_dpi, " H:", screen_height, ")")

## The global multiplier for all UI elements. 1.0 is default.
func get_global_ui_scale() -> float:
	return _global_ui_scale

func set_global_ui_scale(value: float):
	var new_value = clampf(value, 0.75, 6.0) 
	if not is_equal_approx(_global_ui_scale, new_value) or not is_equal_approx(get_tree().root.content_scale_factor, new_value):
		_global_ui_scale = new_value
		# Target the root window viewport specifically to ensure global effect
		get_tree().root.content_scale_factor = _global_ui_scale
		scale_changed.emit(_global_ui_scale)
		print("[UIScaleManager] Global UI Scale set to: ", _global_ui_scale, " (Root Viewport Logical Size: ", get_tree().root.get_visible_rect().size, ")")

# In the future, you can add methods here to save/load this value.
# func save_settings(): ...
# func load_settings(): ...
