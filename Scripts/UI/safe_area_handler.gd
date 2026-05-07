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
	var win_sz = DisplayServer.window_get_size()
	if win_sz.x == 0 or win_sz.y == 0:
		return

	var sm = get_node_or_null("/root/ui_scale_manager")
	var margins = Rect2()
	if is_instance_valid(sm) and sm.has_method("get_logical_safe_margins"):
		margins = sm.get_logical_safe_margins()
	else:
		# Fallback to physical if scale manager not found
		var safe_area = DisplayServer.get_display_safe_area()
		var screen_size = DisplayServer.screen_get_size()
		margins.position.x = safe_area.position.x
		margins.position.y = safe_area.position.y
		margins.size.x = screen_size.x - safe_area.end.x
		margins.size.y = screen_size.y - safe_area.end.y

	var left = margins.position.x
	var top = margins.position.y
	var right = margins.size.x
	var bottom = margins.size.y

	# Add extra padding in portrait to avoid Dynamic Island / notch
	if win_sz.y > win_sz.x and top > 0:
		top += 14 # Push it down slightly further (logical pixels)

	# Ensure minimum padding to keep UI from sticking completely to edges even without safe area
	if win_sz.y > win_sz.x:
		left = max(left, 8.0)
		right = max(right, 8.0)

	# Set margins
	add_theme_constant_override("margin_left", int(left))
	add_theme_constant_override("margin_top", int(top))
	add_theme_constant_override("margin_right", int(right))
	add_theme_constant_override("margin_bottom", int(bottom))
