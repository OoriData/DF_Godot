
class_name MapCameraController
extends Node

signal camera_zoom_changed(new_zoom_level: float)

@export_group("Camera Controls")
@export var min_camera_zoom_level: float = 0.5 # Prevents excessive zoom out
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


func update_map_viewport_rect(_new_rect: Rect2):
	if not is_instance_valid(camera_node):
		printerr("[MCC] Cannot update, camera is not valid.")
		return

	# Always use the SubViewport's size for camera calculations
	var viewport_node = camera_node.get_viewport()
	if viewport_node and viewport_node is SubViewport:
		var vp_size = viewport_node.size
		map_viewport_rect = Rect2(Vector2.ZERO, vp_size)
		print("[DFCAM-DEBUG] update_map_viewport_rect: using SubViewport size=", vp_size)
	else:
		# fallback to previous behavior if not in a SubViewport
		map_viewport_rect = _new_rect
		print("[DFCAM-DEBUG] update_map_viewport_rect: fallback to new_rect=", _new_rect.size)

	camera_node.offset = Vector2.ZERO
	_update_camera_limits()
	fit_camera_to_tilemap()
	print("[DFCAM-DEBUG] update_map_viewport_rect: camera_position=", camera_node.position, ", camera_zoom=", camera_node.zoom)

func _clamp_camera_position():
	if not is_instance_valid(camera_node):
		return
	camera_node.position.x = clamp(camera_node.position.x, camera_node.limit_left, camera_node.limit_right)
	camera_node.position.y = clamp(camera_node.position.y, camera_node.limit_top, camera_node.limit_bottom)


func _update_camera_limits():
	if not is_instance_valid(camera_node) or not is_instance_valid(tilemap_ref) or camera_node.zoom.x <= 0:
		return

	var used_rect = tilemap_ref.get_used_rect()
	var cell_size = tilemap_ref.tile_set.tile_size
	var map_world_bounds = Rect2(used_rect.position * cell_size, used_rect.size * cell_size)
	var visible_world_size = map_viewport_rect.size / camera_node.zoom


	# Calculate the min/max center positions so the viewport never shows outside the map
	var min_x = map_world_bounds.position.x + visible_world_size.x / 2.0
	var max_x = map_world_bounds.end.x - visible_world_size.x / 2.0
	var min_y = map_world_bounds.position.y + visible_world_size.y / 2.0
	var max_y = map_world_bounds.end.y - visible_world_size.y / 2.0

	# If the map is smaller than the viewport, lock to center
	if visible_world_size.x >= map_world_bounds.size.x:
		min_x = map_world_bounds.get_center().x
		max_x = map_world_bounds.get_center().x
	if visible_world_size.y >= map_world_bounds.size.y:
		min_y = map_world_bounds.get_center().y
		max_y = map_world_bounds.get_center().y

	camera_node.limit_left = int(round(min_x))
	camera_node.limit_right = int(round(max_x))
	camera_node.limit_top = int(round(min_y))
	camera_node.limit_bottom = int(round(max_y))


func set_interactive(_is_interactive: bool):
	# No-op: input is now handled by MainScreen
	pass


## --- New public camera manipulation API ---

# Pan the camera by a delta in screen space (pixels)
func pan(delta: Vector2):
	if not is_instance_valid(camera_node):
		return
	if camera_node.zoom.x != 0.0:
		var pan_delta = delta * camera_pan_sensitivity / camera_node.zoom.x
		camera_node.position += pan_delta
		_clamp_camera_position()
		print("[DFCAM-DEBUG] pan: delta=", delta, ", pan_delta=", pan_delta, ", new_position=", camera_node.position)

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
	_clamp_camera_position()

	print("[DFCAM-DEBUG] zoom_at_screen_pos: zoom_multiplier=", zoom_multiplier, ", clamped_zoom=", clamped_zoom, ", world_pos_before=", world_pos_before, ", world_pos_after=", world_pos_after, ", new_position=", camera_node.position)
	emit_signal("camera_zoom_changed", camera_node.zoom.x)



func fit_camera_to_tilemap():
	if not is_instance_valid(camera_node) or not is_instance_valid(tilemap_ref):
		return

	var used_rect = tilemap_ref.get_used_rect()
	var cell_size = tilemap_ref.tile_set.tile_size
	var map_world_bounds = Rect2(used_rect.position * cell_size, used_rect.size * cell_size)

	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return

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
	camera_node.offset = Vector2.ZERO
	_update_camera_limits()
	camera_node.position = map_world_bounds.get_center()
	_clamp_camera_position()
	emit_signal("camera_zoom_changed", target_zoom)

func get_current_zoom() -> float:
	return camera_node.zoom.x if is_instance_valid(camera_node) else 1.0
