class_name MapCameraController
extends Node

signal camera_zoom_changed(new_zoom_level: float)

@export_group("Camera Controls")
@export var min_camera_zoom_level: float = 0.05
@export var max_camera_zoom_level: float = 5.0
@export var enable_mouse_wheel_zoom: bool = true
@export var camera_zoom_factor_increment: float = 1.1
@export var camera_pan_sensitivity: float = 1.0 # Sensitivity for panning with mouse drag

var camera_node: Camera2D = null
var tilemap_ref: TileMapLayer = null
var map_viewport_rect: Rect2 = Rect2()

func initialize(p_camera: Camera2D, p_tilemap: TileMapLayer):
	camera_node = p_camera
	tilemap_ref = p_tilemap
	if not is_instance_valid(camera_node):
		printerr("[MCC] Initialization failed: Camera2D is null.")
	if not is_instance_valid(tilemap_ref):
		printerr("[MCC] Initialization failed: TileMapLayer is null.")
	
	# Set the initial viewport to the full screen.
	# This will be adjusted by other scripts if the layout changes.
	if is_instance_valid(get_viewport()):
		map_viewport_rect = get_viewport().get_visible_rect()

func _ready():
	pass # Initialization is now handled by the initialize function.

func update_map_viewport_rect(new_rect: Rect2):
	if not is_instance_valid(camera_node):
		printerr("[MCC] Cannot update, camera is not valid.")
		return

	map_viewport_rect = new_rect
	
	# This function no longer changes the zoom level. It only adjusts the
	# camera's offset and limits to match the new viewport rectangle.
	# Zoom is controlled by the user or by fit_camera_to_tilemap().

	# 1. Set camera offset to center the view correctly within the new rect
	var screen_center = get_viewport().get_visible_rect().get_center()
	var map_viewport_center_screen = map_viewport_rect.get_center()
	camera_node.offset = map_viewport_center_screen - screen_center

	# 2. Calculate and set camera limits for the current zoom
	_update_camera_limits()
	
	# 3. Ensure camera position is still within new bounds.
	# This will clamp the position if the viewport change makes the old position invalid.
	camera_node.position = camera_node.position
	
	print("[MCC] Viewport rect updated. New offset: ", camera_node.offset)

func _update_camera_limits():
	if not is_instance_valid(camera_node) or not is_instance_valid(tilemap_ref) or camera_node.zoom.x <= 0:
		return

	var used_rect = tilemap_ref.get_used_rect()
	var cell_size = tilemap_ref.tile_set.tile_size
	var map_world_bounds = Rect2(used_rect.position * cell_size, used_rect.size * cell_size)
	
	var visible_world_size = map_viewport_rect.size / camera_node.zoom

	var limit_l = map_world_bounds.position.x + visible_world_size.x / 2.0
	var limit_r = map_world_bounds.end.x - visible_world_size.x / 2.0
	var limit_t = map_world_bounds.position.y + visible_world_size.y / 2.0
	var limit_b = map_world_bounds.end.y - visible_world_size.y / 2.0

	if limit_l > limit_r:
		var center_x = map_world_bounds.get_center().x
		limit_l = center_x
		limit_r = center_x
	if limit_t > limit_b:
		var center_y = map_world_bounds.get_center().y
		limit_t = center_y
		limit_b = center_y
		
	camera_node.limit_left = int(limit_l)
	camera_node.limit_right = int(limit_r)
	camera_node.limit_top = int(limit_t)
	camera_node.limit_bottom = int(limit_b)


func set_interactive(_is_interactive: bool):
	# No-op: input is now handled by MainScreen
	pass


## --- New public camera manipulation API ---

# Pan the camera by a delta in screen space (pixels)
func pan(delta: Vector2):
	if not is_instance_valid(camera_node):
		return
	if camera_node.zoom.x != 0.0:
		camera_node.position += delta * camera_pan_sensitivity / camera_node.zoom.x

# Zoom at a given screen position (in global/screen coordinates)
func zoom_at_screen_pos(zoom_multiplier: float, screen_zoom_center: Vector2):
	if not is_instance_valid(camera_node):
		return

	var new_potential_zoom = camera_node.zoom.x * zoom_multiplier
	var clamped_zoom = clamp(new_potential_zoom, min_camera_zoom_level, max_camera_zoom_level)
	if is_equal_approx(camera_node.zoom.x, clamped_zoom):
		return

	var world_pos_before = camera_node.get_canvas_transform().affine_inverse() * screen_zoom_center

	camera_node.zoom = Vector2(clamped_zoom, clamped_zoom)
	_update_camera_limits()

	var world_pos_after = camera_node.get_canvas_transform().affine_inverse() * screen_zoom_center
	camera_node.position += world_pos_before - world_pos_after

	emit_signal("camera_zoom_changed", camera_node.zoom.x)


func fit_camera_to_tilemap():
	if not is_instance_valid(camera_node) or not is_instance_valid(tilemap_ref):
		return
		
	var used_rect = tilemap_ref.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return
		
	var cell_size = tilemap_ref.tile_set.tile_size
	var map_world_bounds = Rect2(used_rect.position * cell_size, used_rect.size * cell_size)

	var viewport_size = map_viewport_rect.size
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return

	var zoom_x = viewport_size.x / map_world_bounds.size.x
	var zoom_y = viewport_size.y / map_world_bounds.size.y
	var target_zoom = min(zoom_x, zoom_y) * 0.95
	
	target_zoom = clamp(target_zoom, min_camera_zoom_level, max_camera_zoom_level)
	camera_node.zoom = Vector2(target_zoom, target_zoom)
	
	_update_camera_limits()
	camera_node.position = map_world_bounds.get_center()
	
	emit_signal("camera_zoom_changed", target_zoom)

func get_current_zoom() -> float:
	return camera_node.zoom.x if is_instance_valid(camera_node) else 1.0
