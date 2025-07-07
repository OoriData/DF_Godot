extends Node
class_name MapCameraController

signal camera_zoom_changed(new_zoom_level: float)

@export_group("Camera Controls") ## Minimum zoom level for the camera.
@export var min_camera_zoom_level: float = 0.05 # Decreased from 0.2 to allow more zoom-out
## Maximum zoom level for the camera.
@export var max_camera_zoom_level: float = 5.0
## Enable zooming with the mouse wheel when using Mouse & Keyboard control scheme.
@export var enable_mouse_wheel_zoom: bool = true
## Factor by which to multiply/divide current zoom on each scroll step.
@export var camera_zoom_factor_increment: float = 1.1
## Multiplier for camera pan speed when using mouse drag or touch pan. Higher values increase sensitivity.
@export var camera_pan_sensitivity: float = 7.5

var controls_enabled: bool = true

var camera_node: Camera2D = null
var map_container_for_bounds_ref: TextureRect = null # Will hold map_display (TextureRect)
var current_map_world_size_ref: Vector2 = Vector2.ZERO # The actual world size of the map content
var current_map_screen_rect_ref: Rect2 # The Rect2 on screen where the map is effectively displayed

var _is_panning_mmb: bool = false # Middle Mouse Button panning state
var _last_pan_mouse_screen_position: Vector2 # For MMB panning delta calculation


func _ready():
	set_physics_process(true) # Enable _physics_process for camera clamping


func initialize(p_camera: Camera2D, p_map_container: TextureRect, p_map_world_size: Vector2, p_map_screen_rect: Rect2):
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
	if not controls_enabled:
		return

	if not is_instance_valid(camera_node) or \
	   not is_instance_valid(map_container_for_bounds_ref) or \
	   current_map_world_size_ref.x <= 0 or \
	   current_map_world_size_ref.y <= 0:
		return

	var camera_viewport: Viewport = camera_node.get_viewport()
	if not is_instance_valid(camera_viewport):
		# Camera is not yet in the scene tree or has no viewport
		return

	# map_container_for_bounds_ref is now map_display (TextureRect).
	# Its parent is map_container (Node2D).
	# Both map_camera and map_container are children of "MapRender" (Node2D with main.gd).
	# The origin of the map texture in the camera's coordinate system is:
	# map_container.position + map_display.position
	var map_display_parent_node: Node2D = map_container_for_bounds_ref.get_parent() as Node2D
	if not is_instance_valid(map_display_parent_node): return # Should not happen
	
	var map_origin_in_camera_space: Vector2 = map_display_parent_node.position + map_container_for_bounds_ref.position
	# current_map_world_size_ref is the size of map_display.texture.
	var map_rect_world = Rect2(map_origin_in_camera_space, current_map_world_size_ref)
	var viewport_render_size_pixels = camera_viewport.size # Use the camera's actual viewport rendering size

	if camera_node.zoom.x <= 0 or camera_node.zoom.y <= 0:
		return

	var viewport_size_world = Vector2(viewport_render_size_pixels) / camera_node.zoom
	
	var target_camera_pos_x: float = camera_node.position.x
	var target_camera_pos_y: float = camera_node.position.y

	# Clamp X
	if viewport_size_world.x < map_rect_world.size.x:
		# Viewport is narrower than map content, normal clamping
		var clamp_min_x = map_rect_world.position.x + viewport_render_size_pixels.x / (2.0 * camera_node.zoom.x)
		var clamp_max_x = map_rect_world.position.x + map_rect_world.size.x - viewport_render_size_pixels.x / (2.0 * camera_node.zoom.x)
		target_camera_pos_x = clamp(camera_node.position.x, clamp_min_x, clamp_max_x)
	else:
		# Viewport is wider than or same width as map content, center camera on map horizontally
		target_camera_pos_x = map_rect_world.position.x + map_rect_world.size.x / 2.0
	
	# Clamp Y
	if viewport_size_world.y < map_rect_world.size.y:
		# Viewport is shorter than map content, normal clamping
		var clamp_min_y = map_rect_world.position.y + viewport_render_size_pixels.y / (2.0 * camera_node.zoom.y)
		var clamp_max_y = map_rect_world.position.y + map_rect_world.size.y - viewport_render_size_pixels.y / (2.0 * camera_node.zoom.y)
		target_camera_pos_y = clamp(camera_node.position.y, clamp_min_y, clamp_max_y)
	else:
		# Viewport is taller than or same height as map content, center camera on map vertically
		target_camera_pos_y = map_rect_world.position.y + map_rect_world.size.y / 2.0
	
	camera_node.position = Vector2(target_camera_pos_x, target_camera_pos_y)

func handle_input(event: InputEvent) -> bool:
	if not controls_enabled:
		return false

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

	var camera_viewport: Viewport = camera_node.get_viewport()
	if not is_instance_valid(camera_viewport):
		return

	var viewport_render_size_pixels = camera_viewport.size # Use the camera's actual viewport rendering size
	var map_world_size = current_map_world_size_ref

	var dynamic_min_zoom_val: float = min_camera_zoom_level # Start with the hardcoded minimum

	if map_world_size.x > 0.001 && map_world_size.y > 0.001 && \
	   viewport_render_size_pixels.x > 0.001 && viewport_render_size_pixels.y > 0.001:
		var zoom_to_make_width_fit_viewport = viewport_render_size_pixels.x / map_world_size.x
		var zoom_to_make_height_fit_viewport = viewport_render_size_pixels.y / map_world_size.y
		# This is the zoom level at which the entire map is contained within the viewport,
		# touching at least two edges. We don't want to zoom out (reduce zoom value) further than this.
		var zoom_level_to_contain_map = min(zoom_to_make_width_fit_viewport, zoom_to_make_height_fit_viewport)
		# The effective minimum zoom should be the greater of the hardcoded limit and the limit to contain the map.
		dynamic_min_zoom_val = max(min_camera_zoom_level, zoom_level_to_contain_map)

	# Ensure the dynamic minimum doesn't exceed the maximum possible zoom.
	# This can happen if the map is very small, making zoom_level_to_contain_map very large.
	# In such cases, min_camera_zoom_level should still be the floor if it's smaller than max_camera_zoom_level.
	# The actual floor for clamping will be `max(min_camera_zoom_level, zoom_level_to_contain_map)`
	# but this entire value must not make the lower bound of clamp exceed `max_camera_zoom_level`.
	var effective_min_clamp_val: float = clamp(dynamic_min_zoom_val, min_camera_zoom_level, max_camera_zoom_level)
	var effective_max_clamp_val: float = max_camera_zoom_level

	var new_potential_zoom: float = camera_node.zoom.x * zoom_adjust_factor
	var clamped_zoom: float = clamp(new_potential_zoom, effective_min_clamp_val, effective_max_clamp_val)
	var new_zoom_vec := Vector2(clamped_zoom, clamped_zoom)
	
	if camera_node.zoom.is_equal_approx(new_zoom_vec): return
	
	# screen_zoom_center is a global screen coordinate from the input event.
	# It needs to be relative to the camera's viewport (the SubViewportContainer).
	# current_map_screen_rect_ref.position is the global screen position of the SubViewportContainer's top-left corner.
	var zoom_center_in_viewport_coords: Vector2 = screen_zoom_center - current_map_screen_rect_ref.position
	
	var world_pos_before: Vector2 = camera_node.get_canvas_transform().affine_inverse() * zoom_center_in_viewport_coords
	var old_zoom_val = camera_node.zoom.x
	camera_node.zoom = new_zoom_vec
	var world_pos_after: Vector2 = camera_node.get_canvas_transform().affine_inverse() * zoom_center_in_viewport_coords
	camera_node.position += world_pos_before - world_pos_after

	if not is_equal_approx(old_zoom_val, camera_node.zoom.x):
		emit_signal("camera_zoom_changed", camera_node.zoom.x)


func set_and_clamp_zoom(target_zoom_scalar: float):
	if not is_instance_valid(camera_node):
		return
		
	# Simplified: zoom_at_screen_pos handles clamping. Call it with viewport center.
	var current_zoom = camera_node.zoom.x
	if current_zoom == 0:
		return # Avoid division by zero
		
	var adjust_factor = target_zoom_scalar / current_zoom
	
	zoom_at_screen_pos(adjust_factor, current_map_screen_rect_ref.get_center())


func focus_and_set_zoom(target_world_position: Vector2, target_zoom_scalar: float):
	if not is_instance_valid(camera_node):
		return
	set_and_clamp_zoom(target_zoom_scalar) # This will update camera_node.zoom
	camera_node.position = target_world_position
	# Clamping of position will be handled by _physics_process on the next frame.


func get_current_zoom() -> float:
	return camera_node.zoom.x if is_instance_valid(camera_node) else 1.0

func is_panning() -> bool:
	return _is_panning_mmb
