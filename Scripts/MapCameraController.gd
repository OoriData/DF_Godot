extends Node
class_name MapCameraController

signal camera_zoom_changed(new_zoom_level: float)

@export_group("Camera Controls")
## Minimum zoom level for the camera.
@export var min_camera_zoom_level: float = 0.2
## Maximum zoom level for the camera.
@export var max_camera_zoom_level: float = 5.0
## Enable zooming with the mouse wheel when using Mouse & Keyboard control scheme.
@export var enable_mouse_wheel_zoom: bool = true
## Factor by which to multiply/divide current zoom on each scroll step.
@export var camera_zoom_factor_increment: float = 1.1
## Multiplier for camera pan speed when using mouse drag or touch pan. Higher values increase sensitivity.
@export var camera_pan_sensitivity: float = 7.5

var camera_node: Camera2D = null
var map_container_for_bounds_ref: Node2D = null # Used to get map's global_position for clamping
var current_map_world_size_ref: Vector2 = Vector2.ZERO # The actual world size of the map content
var current_map_screen_rect_ref: Rect2 # The Rect2 on screen where the map is effectively displayed

var _is_panning_mmb: bool = false # Middle Mouse Button panning state
var _last_pan_mouse_screen_position: Vector2 # For MMB panning delta calculation


func _ready():
	set_physics_process(true) # Enable _physics_process for camera clamping


func initialize(p_camera: Camera2D, p_map_container: Node2D, p_map_world_size: Vector2, p_map_screen_rect: Rect2):
	camera_node = p_camera
	map_container_for_bounds_ref = p_map_container
	current_map_world_size_ref = p_map_world_size
	current_map_screen_rect_ref = p_map_screen_rect

	if not is_instance_valid(camera_node):
		printerr("MapCameraController: Camera node is invalid in initialize.")
	if not is_instance_valid(map_container_for_bounds_ref):
		printerr("MapCameraController: Map container for bounds is invalid in initialize.")


func update_map_dimensions(p_map_world_size: Vector2, p_map_screen_rect: Rect2):
	current_map_world_size_ref = p_map_world_size
	current_map_screen_rect_ref = p_map_screen_rect


func _physics_process(_delta: float):
	if not is_instance_valid(camera_node) or \
	   not is_instance_valid(map_container_for_bounds_ref) or \
	   current_map_world_size_ref.x <= 0 or \
	   current_map_world_size_ref.y <= 0:
		return

	var map_rect_world = Rect2(map_container_for_bounds_ref.global_position, current_map_world_size_ref)
	var viewport_size_pixels = current_map_screen_rect_ref.size

	if camera_node.zoom.x <= 0 or camera_node.zoom.y <= 0:
		return

	var viewport_size_world = viewport_size_pixels / camera_node.zoom

	var clamp_min_x = map_rect_world.position.x + viewport_size_world.x / 2.0
	var clamp_max_x = map_rect_world.position.x + map_rect_world.size.x - viewport_size_world.x / 2.0
	var clamp_min_y = map_rect_world.position.y + viewport_size_world.y / 2.0
	var clamp_max_y = map_rect_world.position.y + map_rect_world.size.y - viewport_size_world.y / 2.0

	clamp_min_x = min(clamp_min_x, clamp_max_x)
	clamp_min_y = min(clamp_min_y, clamp_max_y)

	camera_node.position.x = clamp(camera_node.position.x, clamp_min_x, clamp_max_x)
	camera_node.position.y = clamp(camera_node.position.y, clamp_min_y, clamp_max_y)


func handle_input(event: InputEvent) -> bool:
	if not is_instance_valid(camera_node):
		return false

	# Middle Mouse Button Panning
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			_is_panning_mmb = true
			_last_pan_mouse_screen_position = event.position
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			get_viewport().set_input_as_handled()
			return true
		elif _is_panning_mmb: # Released
			_is_panning_mmb = false
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			get_viewport().set_input_as_handled()
			return true

	if event is InputEventMouseMotion and _is_panning_mmb:
		var mouse_delta_screen: Vector2 = event.relative
		if camera_node.zoom.x != 0.0:
			camera_node.position += mouse_delta_screen * camera_pan_sensitivity / camera_node.zoom.x
		get_viewport().set_input_as_handled()
		return true

	# Mouse Wheel Zoom
	if enable_mouse_wheel_zoom and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.is_pressed():
			zoom_at_screen_pos(1.0 / camera_zoom_factor_increment, event.position)
			get_viewport().set_input_as_handled()
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.is_pressed():
			zoom_at_screen_pos(camera_zoom_factor_increment, event.position)
			get_viewport().set_input_as_handled()
			return true

	# Touch Gestures
	if event is InputEventMagnifyGesture:
		if event.factor != 0.0: # factor > 1 is zoom out, < 1 is zoom in for this event
			zoom_at_screen_pos(event.factor, event.position)
			get_viewport().set_input_as_handled()
			return true

	if event is InputEventPanGesture: # Touch pan
		if camera_node.zoom.x != 0.0:
			camera_node.position += event.delta * camera_pan_sensitivity / camera_node.zoom.x
			get_viewport().set_input_as_handled()
			return true
			
	return false # Event not handled by this controller


func zoom_at_screen_pos(zoom_adjust_factor: float, screen_zoom_center: Vector2):
	if not is_instance_valid(camera_node): return

	var effective_min_clamp_val: float = min_camera_zoom_level
	var effective_max_clamp_val: float = max_camera_zoom_level

	if current_map_world_size_ref.x > 0.001 and current_map_world_size_ref.y > 0.001 and \
	   current_map_screen_rect_ref.size.x > 0.001 and current_map_screen_rect_ref.size.y > 0.001:
		var viewport_pixel_size: Vector2 = current_map_screen_rect_ref.size
		var map_world_size: Vector2 = current_map_world_size_ref
		var req_zoom_x: float = viewport_pixel_size.x / map_world_size.x
		var req_zoom_y: float = viewport_pixel_size.y / map_world_size.y
		var dynamic_min_zoom: float = max(req_zoom_x, req_zoom_y)
		effective_min_clamp_val = max(min_camera_zoom_level, dynamic_min_zoom)
		effective_max_clamp_val = max(effective_min_clamp_val, max_camera_zoom_level)

	var new_potential_zoom: float = camera_node.zoom.x * zoom_adjust_factor
	var clamped_zoom: float = clamp(new_potential_zoom, effective_min_clamp_val, effective_max_clamp_val)
	var new_zoom_vec := Vector2(clamped_zoom, clamped_zoom)

	if camera_node.zoom.is_equal_approx(new_zoom_vec): return
	
	var world_pos_before: Vector2 = camera_node.get_canvas_transform().affine_inverse() * screen_zoom_center
	var old_zoom_val = camera_node.zoom.x
	camera_node.zoom = new_zoom_vec
	var world_pos_after: Vector2 = camera_node.get_canvas_transform().affine_inverse() * screen_zoom_center
	camera_node.position += world_pos_before - world_pos_after

	if not is_equal_approx(old_zoom_val, camera_node.zoom.x):
		emit_signal("camera_zoom_changed", camera_node.zoom.x)


func set_and_clamp_zoom(target_zoom_scalar: float):
	if not is_instance_valid(camera_node): return
	# Simplified: zoom_at_screen_pos handles clamping. Call it with viewport center.
	var current_zoom = camera_node.zoom.x
	if current_zoom == 0: return # Avoid division by zero
	var adjust_factor = target_zoom_scalar / current_zoom
	zoom_at_screen_pos(adjust_factor, get_viewport().get_visible_rect().size / 2.0)


func focus_and_set_zoom(target_world_position: Vector2, target_zoom_scalar: float):
	if not is_instance_valid(camera_node): return
	set_and_clamp_zoom(target_zoom_scalar) # This will update camera_node.zoom
	camera_node.position = target_world_position
	# Clamping of position will be handled by _physics_process on the next frame.


func get_current_zoom() -> float:
	return camera_node.zoom.x if is_instance_valid(camera_node) else 1.0

func is_panning() -> bool:
	return _is_panning_mmb
