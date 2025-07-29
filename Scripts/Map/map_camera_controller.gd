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
## Removed old TileMap reference, only using TileMapLayer now
var tilemap_ref: TileMapLayer = null # Reference to the TileMapLayer node
var current_map_screen_rect_ref: Rect2 = Rect2()

# Store calculated map bounds to avoid recalculating every frame
var _cached_map_bounds: Rect2 = Rect2()
var _bounds_need_update: bool = true

var _is_panning_mmb: bool = false
var _last_pan_mouse_screen_position: Vector2 = Vector2.ZERO

func _ready():
	set_physics_process(true)
	get_viewport().connect("size_changed", Callable(self, "_on_viewport_resized"))
	# Deep diagnostics for tilemap_ref and its tileset
	print("[DIAG] MapCameraController _ready: camera_node:", camera_node)
	print("[DIAG] MapCameraController _ready: tilemap_ref is_instance_valid:", is_instance_valid(tilemap_ref))
	if is_instance_valid(tilemap_ref):
		print("[DIAG] MapCameraController _ready: tilemap_ref type:", typeof(tilemap_ref), " class:", tilemap_ref.get_class())
		print("[DIAG] MapCameraController _ready: tilemap_ref resource_path:", tilemap_ref.resource_path if tilemap_ref.has_method("resource_path") else "N/A")
		print("[DIAG] MapCameraController _ready: tilemap_ref.tile_set is_instance_valid:", is_instance_valid(tilemap_ref.tile_set))
		if is_instance_valid(tilemap_ref.tile_set):
			print("[DIAG] MapCameraController _ready: tilemap_ref.tile_set resource_path:", tilemap_ref.tile_set.resource_path if tilemap_ref.tile_set.has_method("resource_path") else "N/A")
			print("[DIAG] MapCameraController _ready: tilemap_ref.tile_set to_string:", str(tilemap_ref.tile_set))
			var ids = []
			if tilemap_ref.tile_set.has_method("get_tiles_ids"):
				ids = tilemap_ref.tile_set.get_tiles_ids()
			else:
				for i in range(100):
					if tilemap_ref.tile_set.has_method("has_tile") and tilemap_ref.tile_set.has_tile(i):
						ids.append(i)
			print("[DIAG] MapCameraController _ready: tilemap_ref.tile_set ids:", ids)
		else:
			print("[DIAG] MapCameraController _ready: tilemap_ref.tile_set is not valid!")
	else:
		print("[DIAG] MapCameraController _ready: tilemap_ref is not valid!")

func _on_viewport_resized():
	await get_tree().process_frame
	_bounds_need_update = true
	update_map_dimensions(current_map_screen_rect_ref)

func initialize(p_camera: Camera2D, p_tilemap: TileMapLayer, p_map_screen_rect: Rect2):
	camera_node = p_camera
	tilemap_ref = p_tilemap # Now expects TileMapLayer
	current_map_screen_rect_ref = p_map_screen_rect
	_bounds_need_update = true

	if is_instance_valid(camera_node):
		pass
	else:
		printerr("[ERROR] Camera node is INVALID in initialize.")
	if is_instance_valid(tilemap_ref):
		pass
	else:
		printerr("[ERROR] TileMapLayer node is INVALID in initialize.")

func update_map_dimensions(p_map_screen_rect: Rect2):
	current_map_screen_rect_ref = p_map_screen_rect
	_bounds_need_update = true

func _update_map_bounds():
	if not is_instance_valid(tilemap_ref):
		return
	var used_rect = tilemap_ref.get_used_rect()
	var cell_size = tilemap_ref.tile_set.tile_size
	var cell_size_vec = Vector2(cell_size)
	var map_size = Vector2(used_rect.size.x * cell_size_vec.x, used_rect.size.y * cell_size_vec.y)
	var map_pos = Vector2(used_rect.position) * cell_size_vec
	_cached_map_bounds = Rect2(map_pos, map_size)
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
	# Prevent handling input if a UI element is focused or the mouse is over an interactive UI control.
	if get_viewport().gui_get_focus_owner() != null:
		return false
	if event is InputEventMouse:
		var hovered_control = get_viewport().gui_get_hovered_control()
		if is_instance_valid(hovered_control) and hovered_control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			# If the mouse is over a control that is meant to receive input (STOP or PASS),
			# then the camera should not handle the event.
			return false
	if not controls_enabled:
		return false
	if not is_instance_valid(camera_node):
		return false

	# Trackpad-friendly: allow left mouse drag for panning
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

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
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
	if not is_instance_valid(camera_node):
		printerr("[ERROR] zoom_at_screen_pos: camera_node not valid, ignoring zoom.")
		return

	var camera_viewport: Viewport = camera_node.get_viewport()
	if not is_instance_valid(camera_viewport):
		printerr("[ERROR] zoom_at_screen_pos: camera_viewport not valid, ignoring zoom.")
		return

	# Use the current map screen rect size for calculations
	var viewport_render_size_pixels = current_map_screen_rect_ref.size
	var map_world_size = Vector2.ZERO
	if is_instance_valid(tilemap_ref):
		var used_rect = tilemap_ref.get_used_rect()
		var cell_size = tilemap_ref.tile_set.tile_size
		map_world_size = Vector2(used_rect.size.x * cell_size.x, used_rect.size.y * cell_size.y)

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
	# Center on the map if possible
	var center_pos = Vector2.ZERO
	if is_instance_valid(tilemap_ref):
		var used_rect = tilemap_ref.get_used_rect()
		var cell_size = tilemap_ref.tile_set.tile_size
		var cell_size_vec = Vector2(cell_size)
		center_pos = (Vector2(used_rect.position) * cell_size_vec) + (Vector2(used_rect.size.x * cell_size_vec.x, used_rect.size.y * cell_size_vec.y) / 2)
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

func fit_camera_to_tilemap():
	if not is_instance_valid(camera_node):
		printerr("[ERROR] Camera node is invalid in fit_camera_to_tilemap.")
		return
	if not is_instance_valid(tilemap_ref):
		printerr("[ERROR] TileMapLayer node is invalid in fit_camera_to_tilemap.")
		return
	var used_rect = tilemap_ref.get_used_rect()
	var cell_size = tilemap_ref.tile_set.tile_size
	var cell_size_vec = Vector2(cell_size)
	var map_size = Vector2(used_rect.size.x * cell_size_vec.x, used_rect.size.y * cell_size_vec.y)
	var viewport_size = current_map_screen_rect_ref.size
	if map_size.x > 0 and map_size.y > 0 and viewport_size.x > 0 and viewport_size.y > 0:
		var zoom_x = viewport_size.x / map_size.x
		var zoom_y = viewport_size.y / map_size.y
		var target_zoom = min(zoom_x, zoom_y)
		# Clamp zoom so map never appears smaller than viewport (never < 1.0)
		var clamped_zoom = max(target_zoom, 1.0)
		var center_pos = (Vector2(used_rect.position) * cell_size_vec) + (map_size / 2)
		camera_node.zoom = Vector2(clamped_zoom, clamped_zoom)
		camera_node.position = center_pos
		emit_signal("camera_zoom_changed", clamped_zoom)
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
