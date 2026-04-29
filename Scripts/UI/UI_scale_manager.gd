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
	# Always run auto-adjust once to establish base scale for current window
	_auto_adjust_scale()
	
	# Try to pull manual override from settings
	var sm = get_node_or_null("/root/SettingsManager")
	if is_instance_valid(sm):
		var val = sm.get_value("ui.scale")
		if val != null:
			# If user has a manual scale, we might want to respect it, 
			# but for now we prioritize auto-scaling in portrait to fix the clipping.
			if not get_window().size.y > get_window().size.x:
				_global_ui_scale = float(val)
				set_global_ui_scale(_global_ui_scale)
	
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
	var win_sz = get_window().size
	var is_portrait = win_sz.y > win_sz.x
	var is_mobile = DisplayServer.get_name() in ["Android", "iOS"]
	
	# Target Logical Widths
	# Portrait: 800px (standard mobile portrait target)
	# Landscape: 1600px (standard mobile/tablet landscape)
	# Desktop: 1920px (base target)
	var target_w = 1920.0
	if is_portrait:
		target_w = 800.0
	elif is_mobile:
		target_w = 1600.0
	elif win_sz.x < 1200:
		target_w = 1200.0 # Small window on desktop
		
	var target_scale = float(win_sz.x) / target_w
	
	# Clamp to sane values
	target_scale = clampf(target_scale, 0.5, 4.0)
	
	_auto_adjust_done = true
	set_global_ui_scale(target_scale)

## The global multiplier for all UI elements. 1.0 is default.
func get_global_ui_scale() -> float:
	return _global_ui_scale

func get_max_safe_scale() -> float:
	var win_sz = DisplayServer.window_get_size()
	var screen_width = win_sz.x
	var screen_height = win_sz.y
	var is_portrait = screen_height > screen_width
	
	var min_logical = MIN_LOGICAL_WIDTH
	if is_portrait:
		# In portrait, we must allow a much smaller logical width to enable 
		# readable scaling factors on narrow screens.
		min_logical = MIN_LOGICAL_WIDTH * 0.5 # e.g. 1150 -> 575
	
	# Max scale = physical / min_logical 
	return float(screen_width) / min_logical

func set_global_ui_scale(value: float):
	# Calculate target logical width based on the desired scale
	# Scale = Physical / Logical  => Logical = Physical / Scale
	var win_sz = get_window().size
	var target_width = float(win_sz.x) / value
	
	# Godot 4.3+ content_scale_size is the most robust way to set logical resolution
	# We set the width and let 'expand' aspect handle the height
	get_window().content_scale_size = Vector2i(int(target_width), 0)
	
	_global_ui_scale = value
	scale_changed.emit(_global_ui_scale)

# In the future, you can add methods here to save/load this value.
# func save_settings(): ...
# func load_settings(): ...
