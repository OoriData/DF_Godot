extends MarginContainer
## safe_area_handler.gd
## Automatically adjusts margins to respect DisplayServer safe areas (notches/home indicators).
## Attach this to a MarginContainer that serves as a root for UI elements.

@export var auto_update: bool = true

func _ready():
	_update_safe_area()
	if auto_update:
		get_viewport().size_changed.connect(_update_safe_area)

func _update_safe_area():
	var safe_area = DisplayServer.get_display_safe_area()
	var window_size = DisplayServer.window_get_size()
	
	if window_size.x == 0 or window_size.y == 0:
		return

	# Convert safe_area (screen pixels) to margins
	# Godot's safe_area is in screen coordinates, we need to map it to our viewport
	var screen_size = DisplayServer.screen_get_size()
	
	# For most mobile platforms, safe_area is provided correctly.
	# We calculate the distance from each edge.
	var left = safe_area.position.x
	var top = safe_area.position.y
	var right = screen_size.x - safe_area.end.x
	var bottom = screen_size.y - safe_area.end.y

	# Set margins
	add_theme_constant_override("margin_left", left)
	add_theme_constant_override("margin_top", top)
	add_theme_constant_override("margin_right", right)
	add_theme_constant_override("margin_bottom", bottom)

	# print("[SafeRegion] Applied margins: L:%d T:%d R:%d B:%d" % [left, top, right, bottom])
