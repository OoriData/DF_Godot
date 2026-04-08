extends MarginContainer
class_name ResponsiveMarginContainer

@export var mobile_portrait_margins: int = 12
@export var desktop_margins: int = 24
@export var mobile_landscape_margins: int = 16

var _dsm: Node

func _ready() -> void:
	_dsm = get_node_or_null("/root/DeviceStateManager")
	if is_instance_valid(_dsm):
		_dsm.layout_mode_changed.connect(_on_layout_mode_changed)
	
	_apply_margins()

func _on_layout_mode_changed(mode: int, screen_size: Vector2, is_mobile: bool) -> void:
	_apply_margins()

func _apply_margins() -> void:
	if not is_instance_valid(_dsm):
		return
		
	var mode = _dsm.get_layout_mode()
	var pad = desktop_margins
	
	if mode == 2: # MOBILE_PORTRAIT
		pad = mobile_portrait_margins
	elif mode == 1: # MOBILE_LANDSCAPE
		pad = mobile_landscape_margins
		
	add_theme_constant_override("margin_left", pad)
	add_theme_constant_override("margin_right", pad)
	add_theme_constant_override("margin_top", pad)
	add_theme_constant_override("margin_bottom", pad)
