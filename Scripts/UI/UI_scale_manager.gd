extends Node


## The base resolution the UI was designed for.
## Used with Project Stretch settings to ensure consistent scaling.
const BASE_RESOLUTION = Vector2(1920, 1080)

## Signal emitted when the global UI scale multiplier changes.
signal scale_changed(new_scale)


var _global_ui_scale: float = 1.4

func _ready():
	_auto_adjust_scale()
	get_viewport().size_changed.connect(_auto_adjust_scale)

func _auto_adjust_scale():
	# Simple heuristic for mobile/high-DPI scaling
	var screen_dpi = DisplayServer.screen_get_dpi()
	var screen_height = DisplayServer.screen_get_size().y
	
	# If DPI is high, we likely need larger UI
	var dpi_scale = 1.0
	if screen_dpi > 200:
		dpi_scale = 1.5
	if screen_dpi > 400:
		dpi_scale = 2.5
		
	# Adjust based on height (baseline 1080p)
	var height_scale = float(screen_height) / 1080.0
	
	# Combine and clamp
	var target_scale = clampf(dpi_scale * height_scale, 0.8, 2.5)
	
	# We don't want to override manual settings if we had them, 
	# but for now let's just apply it.
	# set_global_ui_scale(target_scale)
	# print("[UIScale] Auto-adjusted scale to: ", target_scale, " (DPI:", screen_dpi, " H:", screen_height, ")")

## The global multiplier for all UI elements. 1.0 is default.
func get_global_ui_scale() -> float:
	return _global_ui_scale

## Sets the global multiplier for all UI elements.
## Clamps the value and emits the scale_changed signal if it changes.
func set_global_ui_scale(value: float):
	var new_value = clampf(value, 0.75, 3.0) # Expanded range for mobile
	if not is_equal_approx(_global_ui_scale, new_value):
		_global_ui_scale = new_value
		scale_changed.emit(_global_ui_scale)

# In the future, you can add methods here to save/load this value.
# func save_settings(): ...
# func load_settings(): ...
