extends Node


## The base resolution the UI was designed for.
## Used with Project Stretch settings to ensure consistent scaling.
const BASE_RESOLUTION = Vector2(1920, 1080)

## Minimum "effective" logical width we want present.
## If the effective width drops below this (due to high scale),
## the UI will likely break/overlap.
const MIN_LOGICAL_WIDTH = 1150.0

## Target logical width for mobile devices.
## This makes UI elements appear larger (touch friendly).
const TARGET_LOGICAL_WIDTH_MOBILE = 1600.0

## Target logical width for desktop.
const TARGET_LOGICAL_WIDTH_DESKTOP = 1920.0

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
	
	# Check for Dynamic Scaling preference
	var sm = get_node_or_null("/root/SettingsManager")
	if is_instance_valid(sm):
		if bool(sm.get_value("ui.auto_scale", false)):
			_auto_adjust_scale()
			return

	# Only re-calculate the auto heuristic if the user HAS NOT set a value.
	var has_setting = false
	if is_instance_valid(sm):
		has_setting = sm.data.has("ui.scale")
	
	if not has_setting:
		_auto_adjust_scale()

func _auto_adjust_scale():
	var screen_width = DisplayServer.window_get_size().x
	var is_mobile = DisplayServer.get_name() == "Android" or DisplayServer.get_name() == "iOS"

	var target_width = TARGET_LOGICAL_WIDTH_MOBILE if is_mobile else TARGET_LOGICAL_WIDTH_DESKTOP
	
	# Calculate the scale needed to achieve the target width
	# scale = physical_width / logical_width
	var target_scale = float(screen_width) / target_width
	
	# Clamp to safe limits
	var max_safe = get_max_safe_scale()
	target_scale = clampf(target_scale, 0.75, max_safe)
	
	# Check if we should apply this. If a SettingsManager exists and has a value, 
	# that should probably win, unless this is the first boot.
	# Check if we should apply this. 
	# If Dynamic Scaling is ON, we ALWAYS apply.
	# If OFF, we only apply if no manual setting exists (first boot).
	var sm = get_node_or_null("/root/SettingsManager")
	if is_instance_valid(sm):
		var auto_on = bool(sm.get_value("ui.auto_scale", false))
		if not auto_on:
			var has_setting = sm.data.has("ui.scale")
			if has_setting and _auto_adjust_done:
				# Manual mode: Let the manual scale win.
				return

	_auto_adjust_done = true
	set_global_ui_scale(target_scale)
	print("[UIScaleManager] Applied auto-scale: ", target_scale, " (Width:", screen_width, " Target:", target_width, ")")

## The global multiplier for all UI elements. 1.0 is default.
func get_global_ui_scale() -> float:
	return _global_ui_scale

func get_max_safe_scale() -> float:
	var screen_width = DisplayServer.window_get_size().x
	# Max scale = physical / min_logical 
	return float(screen_width) / MIN_LOGICAL_WIDTH

func set_global_ui_scale(value: float):
	var max_safe = get_max_safe_scale()
	# Ensure checking against min 0.75 and max safe
	var new_value = clampf(value, 0.75, max_safe) 
	
	if not is_equal_approx(_global_ui_scale, new_value) or not is_equal_approx(get_tree().root.content_scale_factor, new_value):
		_global_ui_scale = new_value
		# Target the root window viewport specifically to ensure global effect
		get_tree().root.content_scale_factor = _global_ui_scale
		scale_changed.emit(_global_ui_scale)
		print("[UIScaleManager] Global UI Scale set to: ", _global_ui_scale, " (Root Viewport Logical Size: ", get_tree().root.get_visible_rect().size, ")")

# In the future, you can add methods here to save/load this value.
# func save_settings(): ...
# func load_settings(): ...
