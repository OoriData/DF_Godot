class_name MapCameraController
extends Node

signal camera_zoom_changed(new_zoom_level: float)

@export_group("Camera Controls")
@export var min_camera_zoom_level: float = 0.05
@export var max_camera_zoom_level: float = 5.0
@export var enable_mouse_wheel_zoom: bool = true
@export var camera_zoom_factor_increment: float = 1.1
@export var camera_pan_sensitivity: float = 7.5


var controls_enabled: bool = true
# If true, disables camera clamping to map bounds (used when menu is open)
var allow_camera_outside_bounds: bool = false

var camera_node: Camera2D = null
var map_container_for_bounds_ref: TextureRect = null
var current_map_screen_rect_ref: Rect2 = Rect2()

# Store calculated map bounds to avoid recalculating every frame
var _cached_map_bounds: Rect2 = Rect2()
var _bounds_need_update: bool = true

var _is_panning_mmb: bool = false
var _last_pan_mouse_screen_position: Vector2 = Vector2.ZERO

func _ready():
	set_physics_process(true)
	get_viewport().connect("size_changed", Callable(self, "_on_viewport_resized"))

func _on_viewport_resized():
	await get_tree().process_frame
	_bounds_need_update = true
	update_map_dimensions(current_map_screen_rect_ref)

func initialize(p_camera: Camera2D, p_map_container: TextureRect, p_map_screen_rect: Rect2):
	camera_node = p_camera
	map_container_for_bounds_ref = p_map_container
	current_map_screen_rect_ref = p_map_screen_rect
	_bounds_need_update = true

	if not is_instance_valid(camera_node):
		printerr("MapCameraController: Camera node is invalid in initialize.")
	if not is_instance_valid(map_container_for_bounds_ref):
		printerr("MapCameraController: Map container for bounds is invalid in initialize.")

func update_map_dimensions(p_map_screen_rect: Rect2):
	current_map_screen_rect_ref = p_map_screen_rect
	_bounds_need_update = true

func _update_map_bounds():
	if not is_instance_valid(map_container_for_bounds_ref) or \
	   not is_instance_valid(map_container_for_bounds_ref.texture):
		return

	var texture_size: Vector2 = map_container_for_bounds_ref.texture.get_size()
	var container_size: Vector2 = map_container_for_bounds_ref.size

	# Compute displayed size preserving aspect ratio
	var texture_aspect_ratio: float = texture_size.x / texture_size.y
	var container_aspect_ratio: float = container_size.x / container_size.y

	var displayed_size: Vector2
	if texture_aspect_ratio > container_aspect_ratio:
		displayed_size.x = container_size.x
		displayed_size.y = container_size.x / texture_aspect_ratio
	else:
		displayed_size.y = container_size.y
		displayed_size.x = container_size.y * texture_aspect_ratio

	var offset: Vector2 = (container_size - displayed_size) * 0.5

	# Get the map container's global position and scale
	var container_global_pos: Vector2 = map_container_for_bounds_ref.global_position
	var container_scale: Vector2 = map_container_for_bounds_ref.get_global_transform().get_scale()
	
	# Calculate the actual displayed map area in world coordinates
	var map_top_left_world: Vector2 = container_global_pos + (offset * container_scale)
	var map_size_world: Vector2 = displayed_size * container_scale
	_cached_map_bounds = Rect2(map_top_left_world, map_size_world)
	_bounds_need_update = false

func _physics_process(_delta: float):
	if not controls_enabled:
		return

	if not is_instance_valid(camera_node):
		return

	# Update bounds if needed (screen resize, initialization, etc.)
	if _bounds_need_update:
		_update_map_bounds()

	# Skip if bounds are invalid
	if _cached_map_bounds.size.x <= 0 or _cached_map_bounds.size.y <= 0:
		return

	var camera_viewport: Viewport = camera_node.get_viewport()
	if not is_instance_valid(camera_viewport):
		return

	if camera_node.zoom.x <= 0 or camera_node.zoom.y <= 0:
		return

	# Always use the full viewport size for clamping
	var viewport_render_size_pixels: Vector2 = current_map_screen_rect_ref.size
	var viewport_size_world: Vector2 = viewport_render_size_pixels / camera_node.zoom

	# Only clamp camera position if not allowing camera outside bounds
	if not allow_camera_outside_bounds:
		var target_camera_pos_x: float = camera_node.position.x
		var target_camera_pos_y: float = camera_node.position.y

		# Only constrain if the viewport is smaller than the map
		if viewport_size_world.x < _cached_map_bounds.size.x:
			var min_x = _cached_map_bounds.position.x + viewport_size_world.x * 0.5
			var max_x = _cached_map_bounds.position.x + _cached_map_bounds.size.x - viewport_size_world.x * 0.5
			target_camera_pos_x = clamp(camera_node.position.x, min_x, max_x)
		else:
			# Center the camera if viewport is larger than map
			target_camera_pos_x = _cached_map_bounds.position.x + _cached_map_bounds.size.x * 0.5

		if viewport_size_world.y < _cached_map_bounds.size.y:
			var min_y = _cached_map_bounds.position.y + viewport_size_world.y * 0.5
			var max_y = _cached_map_bounds.position.y + _cached_map_bounds.size.y - viewport_size_world.y * 0.5
			target_camera_pos_y = clamp(camera_node.position.y, min_y, max_y)
		else:
			# Center the camera if viewport is larger than map
			target_camera_pos_y = _cached_map_bounds.position.y + _cached_map_bounds.size.y * 0.5

		camera_node.position = Vector2(target_camera_pos_x, target_camera_pos_y)
	# If allow_camera_outside_bounds is true, do not clamp or modify camera position at all

# Call this to allow or disallow camera going outside map bounds (e.g. when menu is open)
func set_allow_camera_outside_bounds(allow: bool):
	allow_camera_outside_bounds = allow

# Input handling functions (unchanged from your original)
func handle_input(event: InputEvent) -> bool:
	if not controls_enabled:
		return false
	if not is_instance_valid(camera_node):
		return false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			_is_panning_mmb = true
			_last_pan_mouse_screen_position = event.position
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			get_viewport().set_input_as_handled()
			return true
		elif _is_panning_mmb:
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

	if enable_mouse_wheel_zoom and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.is_pressed():
			zoom_at_screen_pos(1.0 / camera_zoom_factor_increment, event.position)
			get_viewport().set_input_as_handled()
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.is_pressed():
			zoom_at_screen_pos(camera_zoom_factor_increment, event.position)
			get_viewport().set_input_as_handled()
			return true

	if event is InputEventMagnifyGesture:
		if event.factor != 0.0:
			zoom_at_screen_pos(event.factor, event.position)
			get_viewport().set_input_as_handled()
			return true

	if event is InputEventPanGesture:
		if camera_node.zoom.x != 0.0:
			camera_node.position += event.delta * camera_pan_sensitivity / camera_node.zoom.x
			get_viewport().set_input_as_handled()
			return true

	return false

func zoom_at_screen_pos(zoom_adjust_factor: float, screen_zoom_center: Vector2):
	if not is_instance_valid(camera_node): return

	var camera_viewport: Viewport = camera_node.get_viewport()
	if not is_instance_valid(camera_viewport):
		return

	# Use the current map screen rect size for calculations
	var viewport_render_size_pixels = current_map_screen_rect_ref.size
	var map_world_size = Vector2.ZERO
	if is_instance_valid(map_container_for_bounds_ref) and is_instance_valid(map_container_for_bounds_ref.texture):
		map_world_size = map_container_for_bounds_ref.texture.get_size()

	var dynamic_min_zoom_val: float = min_camera_zoom_level

	if map_world_size.x > 0.001 and map_world_size.y > 0.001 and \
	   viewport_render_size_pixels.x > 0.001 and viewport_render_size_pixels.y > 0.001:
		var zoom_to_make_width_fit_viewport = viewport_render_size_pixels.x / map_world_size.x
		var zoom_to_make_height_fit_viewport = viewport_render_size_pixels.y / map_world_size.y
		var zoom_level_to_contain_map = min(zoom_to_make_width_fit_viewport, zoom_to_make_height_fit_viewport)
		dynamic_min_zoom_val = max(min_camera_zoom_level, zoom_level_to_contain_map)

	var effective_min_clamp_val: float = clamp(dynamic_min_zoom_val, min_camera_zoom_level, max_camera_zoom_level)
	var effective_max_clamp_val: float = max_camera_zoom_level

	var new_potential_zoom: float = camera_node.zoom.x * zoom_adjust_factor
	var clamped_zoom: float = clamp(new_potential_zoom, effective_min_clamp_val, effective_max_clamp_val)
	var new_zoom_vec := Vector2(clamped_zoom, clamped_zoom)

	if camera_node.zoom.is_equal_approx(new_zoom_vec): return

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

	var current_zoom = camera_node.zoom.x
	if current_zoom == 0:
		return

	var adjust_factor = target_zoom_scalar / current_zoom
	zoom_at_screen_pos(adjust_factor, current_map_screen_rect_ref.get_center())

func focus_and_set_zoom(target_world_position: Vector2, target_zoom_scalar: float):
	if not is_instance_valid(camera_node):
		return
	set_and_clamp_zoom(target_zoom_scalar)
	camera_node.position = target_world_position

func get_current_zoom() -> float:
	return camera_node.zoom.x if is_instance_valid(camera_node) else 1.0

func is_panning() -> bool:
	return _is_panning_mmb

# Force bounds recalculation (call this when map container changes)
func force_bounds_update():
	_bounds_need_update = true

# Helper function to get the actual visible map area in world coordinates
func get_visible_map_area() -> Rect2:
	if not is_instance_valid(camera_node):
		return Rect2()
	
	var viewport_size_pixels = current_map_screen_rect_ref.size
	var viewport_size_world = viewport_size_pixels / camera_node.zoom
	var camera_top_left = camera_node.position - viewport_size_world * 0.5
	
	return Rect2(camera_top_left, viewport_size_world)

# Debug function to print current bounds info
func debug_print_bounds():
	print("Map bounds: ", _cached_map_bounds)
	print("Camera position: ", camera_node.position if is_instance_valid(camera_node) else "Invalid")
	print("Camera zoom: ", camera_node.zoom if is_instance_valid(camera_node) else "Invalid")
	print("Visible area: ", get_visible_map_area())
	print("Map screen rect: ", current_map_screen_rect_ref)
