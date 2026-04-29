extends Node


enum LayoutMode {
	DESKTOP,
	MOBILE_LANDSCAPE,
	MOBILE_PORTRAIT
}

signal layout_mode_changed(mode: LayoutMode, screen_size: Vector2, is_mobile: bool)

@export_group("Font Scaling Multipliers")
@export var font_multiplier_portrait: float = 1.6
@export var font_multiplier_landscape: float = 1.6
@export var font_multiplier_desktop: float = 1.2

var current_mode: LayoutMode = LayoutMode.DESKTOP
var is_mobile: bool = false
var screen_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Initial assignment
	_update_state()
	# Connect to window resize explicitly so we can track and emit changes dynamically
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	_update_state()

func _update_state() -> void:
	var old_mode = current_mode
	
	screen_size = DisplayServer.window_get_size()
	if screen_size == Vector2.ZERO:
		screen_size = get_viewport().get_visible_rect().size
		
	var is_portrait = screen_size.y > screen_size.x
	
	# Determine if running on mobile device based on feature tags and OS name
	is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.get_name() in ["Android", "iOS"]
	
	# Evaluate Layout Mode globally
	# Evaluate Layout Mode globally
	if is_portrait:
		current_mode = LayoutMode.MOBILE_PORTRAIT
	elif is_mobile:
		current_mode = LayoutMode.MOBILE_LANDSCAPE
	else:
		current_mode = LayoutMode.DESKTOP
			
	if old_mode != current_mode:
		layout_mode_changed.emit(current_mode, screen_size, is_mobile)
		print("[DeviceStateManager] Mode changed to ", _get_mode_name(current_mode), " Size: ", screen_size)

func get_font_multiplier() -> float:
	if current_mode == LayoutMode.MOBILE_PORTRAIT:
		return font_multiplier_portrait
	elif current_mode == LayoutMode.MOBILE_LANDSCAPE:
		return font_multiplier_landscape
	else:
		return font_multiplier_desktop

func get_scaled_base_font_size(base_size: int = 16) -> int:
	return int(base_size * get_font_multiplier())
	
func _get_mode_name(mode: LayoutMode) -> String:
	match mode:
		LayoutMode.DESKTOP: return "DESKTOP"
		LayoutMode.MOBILE_LANDSCAPE: return "MOBILE_LANDSCAPE"
		LayoutMode.MOBILE_PORTRAIT: return "MOBILE_PORTRAIT"
		_: return "UNKNOWN"

func get_layout_mode() -> LayoutMode:
	return current_mode

func get_is_portrait() -> bool:
	return current_mode == LayoutMode.MOBILE_PORTRAIT
