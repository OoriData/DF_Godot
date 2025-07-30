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
var tilemap_ref: TileMapLayer = null # Reference to the TileMapLayer node
var current_map_screen_rect_ref: Rect2 = Rect2()

# Store calculated map bounds to avoid recalculating every frame
var _cached_map_bounds: Rect2 = Rect2()
var _bounds_need_update: bool = true
var _is_menu_open: bool = false

var _is_panning_mmb: bool = false
var _last_pan_mouse_screen_position: Vector2 = Vector2.ZERO

func _ready():
	set_physics_process(true)
	get_viewport().connect("size_changed", Callable(self, "_on_viewport_resized"))

func _on_viewport_resized():
	# Wait a frame for UI layout to settle before updating bounds.
	await get_tree().process_frame
	_bounds_need_update = true
	update_map_dimensions(current_map_screen_rect_ref)

func initialize(p_camera: Camera2D, p_tilemap: TileMapLayer, p_map_screen_rect: Rect2):
	print("[MCC] initialize: camera_node=", p_camera, " tilemap_ref=", p_tilemap, " map_screen_rect=", p_map_screen_rect)
	camera_node = p_camera
	tilemap_ref = p_tilemap
	current_map_screen_rect_ref = p_map_screen_rect
	_bounds_need_update = true

	if not is_instance_valid(camera_node):
		printerr("[ERROR] Camera node is INVALID in initialize.")
	if not is_instance_valid(tilemap_ref):
		printerr("[ERROR] TileMapLayer node is INVALID in initialize.")

# Call this to set the visible map area to the left 1/3 of the viewport (for when a menu opens)
func set_map_view_to_left_third():
	var full_rect = get_viewport().get_visible_rect()
	var left_third = Rect2(full_rect.position, Vector2(full_rect.size.x / 3, full_rect.size.y))
	update_map_dimensions(left_third)

# Call this to set the visible map area to the full viewport (for when the menu closes)
func set_map_view_to_full():
	var full_rect = get_viewport().get_visible_rect()
	update_map_dimensions(full_rect)

func update_map_dimensions(p_map_screen_rect: Rect2):
	print("[MCC] update_map_dimensions: new rect=", p_map_screen_rect)
	current_map_screen_rect_ref = p_map_screen_rect
	_bounds_need_update = true

func _update_map_bounds():
	print("[MCC] _update_map_bounds: called. tilemap_ref=", tilemap_ref, " tile_set=", tilemap_ref.tile_set if is_instance_valid(tilemap_ref) else null)
	if not is_instance_valid(tilemap_ref) or not is_instance_valid(tilemap_ref.tile_set):
		_cached_map_bounds = Rect2()
		_bounds_need_update = false
		return
	var used_rect = tilemap_ref.get_used_rect()
	var cell_size = tilemap_ref.tile_set.tile_size
	var map_size = used_rect.size * cell_size
	var map_pos = used_rect.position * cell_size
	_cached_map_bounds = Rect2(map_pos, map_size)
	_bounds_need_update = false

func _physics_process(_delta: float):
	# Log camera and bounds state each frame (can be commented out if too verbose)
	#print("[MCC] _physics_process: camera_pos=", camera_node.position, " zoom=", camera_node.zoom, " bounds=", _cached_map_bounds, " visible_rect=", current_map_screen_rect_ref)
	if not controls_enabled or not is_instance_valid(camera_node):
		return

	if _bounds_need_update:
		_update_map_bounds()

	if _cached_map_bounds.size.x <= 0 or _cached_map_bounds.size.y <= 0:
		return

	if camera_node.zoom.x <= 0 or camera_node.zoom.y <= 0:
		return

	# Clamp camera position if not allowing it to go outside bounds.
	if not allow_camera_outside_bounds:
		var viewport_render_size_pixels: Vector2 = current_map_screen_rect_ref.size
		var viewport_size_world: Vector2 = viewport_render_size_pixels / camera_node.zoom

		var min_x = _cached_map_bounds.position.x + viewport_size_world.x * 0.5
		var max_x = _cached_map_bounds.position.x + _cached_map_bounds.size.x - viewport_size_world.x * 0.5
		var min_y = _cached_map_bounds.position.y + viewport_size_world.y * 0.5
		var max_y = _cached_map_bounds.position.y + _cached_map_bounds.size.y - viewport_size_world.y * 0.5

		var target_camera_pos = camera_node.position

		# If the menu is open and the visible area is larger than the map, center the map.
		if _is_menu_open and viewport_size_world.x >= _cached_map_bounds.size.x:
			target_camera_pos.x = _cached_map_bounds.get_center().x
		else:
			# Otherwise, clamp the camera's x-position to the map boundaries.
			target_camera_pos.x = clamp(camera_node.position.x, min_x, max_x)

		# Same logic for the y-axis.
		if _is_menu_open and viewport_size_world.y >= _cached_map_bounds.size.y:
			target_camera_pos.y = _cached_map_bounds.get_center().y
		else:
			# Otherwise, clamp the camera's y-position to the map boundaries.
			target_camera_pos.y = clamp(camera_node.position.y, min_y, max_y)

		camera_node.position = target_camera_pos

# Call this to allow or disallow camera going outside map bounds (e.g. when menu is open)
func set_allow_camera_outside_bounds(allow: bool):
	allow_camera_outside_bounds = allow

# Input handling functions (unchanged from your original)
func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if not is_instance_valid(camera_node):
		return

	# Trackpad-friendly: allow left mouse drag for panning
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			_is_panning_mmb = true
			_last_pan_mouse_screen_position = event.position
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			get_viewport().set_input_as_handled()
			return
		elif _is_panning_mmb:
			_is_panning_mmb = false
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_panning_mmb = true
			_last_pan_mouse_screen_position = event.position
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			get_viewport().set_input_as_handled()
			return
		elif _is_panning_mmb:
			_is_panning_mmb = false
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and _is_panning_mmb:
		var mouse_delta_screen: Vector2 = event.relative
		if camera_node.zoom.x != 0.0:
			# Apply panning sensitivity and scale by zoom level (invert sign for standard behavior)
			camera_node.position -= mouse_delta_screen * camera_pan_sensitivity / camera_node.zoom.x
		get_viewport().set_input_as_handled()
		return

	if enable_mouse_wheel_zoom and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.is_pressed():
			zoom_at_screen_pos(1.0 / camera_zoom_factor_increment, event.position)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.is_pressed():
			zoom_at_screen_pos(camera_zoom_factor_increment, event.position)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMagnifyGesture:
		if event.factor != 0.0:
			zoom_at_screen_pos(event.factor, event.position)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventPanGesture:
		if camera_node.zoom.x != 0.0:
			# Invert sign for standard panning behavior
			camera_node.position += event.delta * camera_pan_sensitivity / camera_node.zoom.x
			get_viewport().set_input_as_handled()
			return

func zoom_at_screen_pos(zoom_adjust_factor: float, screen_zoom_center: Vector2):
	if not is_instance_valid(camera_node):
		printerr("[ERROR] zoom_at_screen_pos: camera_node not valid, ignoring zoom.")
		return

	# Use the current map screen rect size for calculations
	var viewport_render_size_pixels = current_map_screen_rect_ref.size
	var map_world_size = _cached_map_bounds.size

	# Calculate the minimum zoom level required to see the whole map in the current viewport
	var dynamic_min_zoom_val = min_camera_zoom_level
	if map_world_size.x > 0.001 and viewport_render_size_pixels.x > 0.001:
		var zoom_to_fit_width = viewport_render_size_pixels.x / map_world_size.x
		var zoom_to_fit_height = viewport_render_size_pixels.y / map_world_size.y
		# The actual minimum zoom is the one that makes the map fit both width and height
		var zoom_level_to_contain_map = min(zoom_to_fit_width, zoom_to_fit_height)
		dynamic_min_zoom_val = max(min_camera_zoom_level, zoom_level_to_contain_map)

	var new_potential_zoom: float = camera_node.zoom.x * zoom_adjust_factor
	var clamped_zoom: float = clamp(new_potential_zoom, dynamic_min_zoom_val, max_camera_zoom_level)
	var new_zoom_vec := Vector2(clamped_zoom, clamped_zoom)

	if camera_node.zoom.is_equal_approx(new_zoom_vec):
		return

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
	# Center zoom on the center of the visible map area
	var center_pos = current_map_screen_rect_ref.get_center()
	zoom_at_screen_pos(adjust_factor, center_pos)

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

func get_visible_map_area() -> Rect2:
	if not is_instance_valid(camera_node):
		return Rect2()
	var viewport_size_pixels = current_map_screen_rect_ref.size
	var viewport_size_world = viewport_size_pixels / camera_node.zoom
	var camera_top_left = camera_node.position - viewport_size_world * 0.5
	return Rect2(camera_top_left, viewport_size_world)

func on_menu_opened():
	_is_menu_open = true
	# Wait a frame for the UI to settle, then update the dimensions.
	await get_tree().process_frame
	var map_view_node = get_node_or_null("/root/MainScreen/MainContainer/MainContent/MapView")
	if is_instance_valid(map_view_node):
		update_map_dimensions(map_view_node.get_global_rect())

func on_menu_closed():
	_is_menu_open = false
	# Wait a frame for the UI to settle, then update the dimensions.
	await get_tree().process_frame
	var map_view_node = get_node_or_null("/root/MainScreen/MainContainer/MainContent/MapView")
	if is_instance_valid(map_view_node):
		update_map_dimensions(map_view_node.get_global_rect())

func fit_camera_to_tilemap():
	print("[MCC] fit_camera_to_tilemap: called.")
	if not is_instance_valid(camera_node) or not is_instance_valid(tilemap_ref):
		printerr("[ERROR] Camera or TileMapLayer node is invalid in fit_camera_to_tilemap.")
		return

	# Always update the bounds when this function is called to get the latest map size.
	_update_map_bounds()

	var map_size = _cached_map_bounds.size
	var viewport_size = current_map_screen_rect_ref.size

	if map_size.x > 0 and viewport_size.x > 0:
		var zoom_x = viewport_size.x / map_size.x
		var zoom_y = viewport_size.y / map_size.y
		# Use min to ensure the entire map fits within the viewport
		var target_zoom = min(zoom_x, zoom_y)
		
		# Set zoom and center the camera on the map
		camera_node.zoom = Vector2(target_zoom, target_zoom)
		camera_node.position = _cached_map_bounds.get_center()
		emit_signal("camera_zoom_changed", target_zoom)
	else:
		printerr("[ERROR] Invalid map or viewport size in fit_camera_to_tilemap.")

func debug_print_bounds():
	print("TileMap bounds: ", _cached_map_bounds)
	if is_instance_valid(camera_node):
		print("Camera position: ", camera_node.position)
		print("Camera zoom: ", camera_node.zoom)
	else:
		print("Camera position: Invalid")
		print("Camera zoom: Invalid")
	print("Visible area: ", get_visible_map_area())
	print("Map screen rect: ", current_map_screen_rect_ref)
