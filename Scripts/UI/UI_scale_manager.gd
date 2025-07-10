extends Node


## The base resolution the UI was designed for.
## Used with Project Stretch settings to ensure consistent scaling.
const BASE_RESOLUTION = Vector2(1920, 1080)

## Signal emitted when the global UI scale multiplier changes.
signal scale_changed(new_scale)


var _global_ui_scale: float = 1.0

## The global multiplier for all UI elements. 1.0 is default.
func get_global_ui_scale() -> float:
	return _global_ui_scale

## Sets the global multiplier for all UI elements.
## Clamps the value and emits the scale_changed signal if it changes.
func set_global_ui_scale(value: float):
	var new_value = clampf(value, 0.75, 2.0) # Clamp to reasonable values (e.g., 75% to 200%)
	if not is_equal_approx(_global_ui_scale, new_value):
		_global_ui_scale = new_value
		scale_changed.emit(_global_ui_scale)

# In the future, you can add methods here to save/load this value.
# func save_settings(): ...
# func load_settings(): ...
