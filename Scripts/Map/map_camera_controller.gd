
class_name MapCameraController
extends Node

signal camera_zoom_changed(new_zoom_level: float)

@export_group("Camera Controls")
@export var min_camera_zoom_level: float = 0.5 # Prevents excessive zoom out
@export var max_camera_zoom_level: float = 5.0
@export var enable_mouse_wheel_zoom: bool = true
@export var camera_zoom_factor_increment: float = 1.1
@export var camera_pan_sensitivity: float = 1.0 # Sensitivity for panning with mouse drag

@export var sub_viewport_node: SubViewport = null


var camera_node: Camera2D = null
var tilemap_ref: TileMapLayer = null
var map_viewport_rect: Rect2 = Rect2()
# --- New: True map size (in tiles) ---
var map_size: Vector2i = Vector2i.ZERO

# Set the true map size (in tiles)
func set_map_size(new_size: Vector2i):
	map_size = new_size
	_update_camera_limits()
	fit_camera_to_tilemap()

func initialize(p_camera: Camera2D, p_tilemap: TileMapLayer, p_sub_viewport: SubViewport):
	camera_node = p_camera
	tilemap_ref = p_tilemap
	sub_viewport_node = p_sub_viewport
	if not is_instance_valid(camera_node):
		printerr("[MCC] Initialization failed: Camera2D is null.")
	if not is_instance_valid(tilemap_ref):
		printerr("[MCC] Initialization failed: TileMapLayer is null.")
	if not is_instance_valid(sub_viewport_node):
		printerr("[MCC] Initialization failed: SubViewport is null.")
	
	# Set the initial viewport to the full screen.
	# This will be adjusted by other scripts if the layout changes.
	if is_instance_valid(get_viewport()):
		map_viewport_rect = get_viewport().get_visible_rect()

func _ready():
	pass # Initialization is now handled by the initialize function.


func update_map_viewport_rect(new_rect: Rect2):
	if not is_instance_valid(camera_node) or not is_instance_valid(sub_viewport_node):
		printerr("[MCC] Cannot update, camera or sub_viewport is not valid.")
		return

	# CRITICAL FIX: Synchronize the SubViewport's size with the actual UI control's size.
	# The size of the control showing the viewport (e.g., TextureRect) dictates the render size.
	if new_rect.size.x > 0 and new_rect.size.y > 0:
		sub_viewport_node.size = Vector2i(new_rect.size)
		map_viewport_rect = Rect2(Vector2.ZERO, new_rect.size)
		# print("[DFCAM-DEBUG] update_map_viewport_rect: Synced SubViewport size to ", sub_viewport_node.size)
	else:
		# Fallback if the new_rect is invalid, use the existing SubViewport size.
		map_viewport_rect = Rect2(Vector2.ZERO, sub_viewport_node.size)
		# print("[DFCAM-DEBUG] update_map_viewport_rect: new_rect was invalid, using existing SubViewport size=", sub_viewport_node.size)

	# camera_node.offset = Vector2.ZERO
	_update_camera_limits()
	fit_camera_to_tilemap()
	# print("[DFCAM-DEBUG] update_map_viewport_rect: camera_position=", camera_node.position, ", camera_zoom=", camera_node.zoom)

func _clamp_camera_position():
	if not is_instance_valid(camera_node):
		return
	# Clamp camera so the entire viewport stays within map bounds
	var cell_size = Vector2(16, 16)
	var map_width = map_size.x * cell_size.x
	var map_height = map_size.y * cell_size.y
	var viewport_size = map_viewport_rect.size
	var zoom = camera_node.zoom.x
	var half_viewport_w = viewport_size.x * 0.5 / zoom
	var half_viewport_h = viewport_size.y * 0.5 / zoom

	var min_x = 0 + half_viewport_w
	var max_x = map_width - half_viewport_w
	var min_y = 0 + half_viewport_h
	var max_y = map_height - half_viewport_h

	# If the map is smaller than the viewport, center the camera
	if map_width <= viewport_size.x * zoom:
		min_x = map_width * 0.5
		max_x = map_width * 0.5
	if map_height <= viewport_size.y * zoom:
		min_y = map_height * 0.5
		max_y = map_height * 0.5

	camera_node.position.x = clamp(camera_node.position.x, min_x, max_x)
	camera_node.position.y = clamp(camera_node.position.y, min_y, max_y)


func _update_camera_limits():
	print("[DEBUG] map_size:", map_size)
	if not is_instance_valid(camera_node) or camera_node.zoom.x <= 0:
		return

	# Use only the true map size for camera bounds
	var cell_size = Vector2(16, 16)
	print("[DEBUG] cell_size:", cell_size)
	var map_world_bounds: Rect2
	if map_size.x > 0 and map_size.y > 0:
		var map_size_vec2 = Vector2(map_size.x, map_size.y)
		var world_size = Vector2(map_size_vec2.x * cell_size.x, map_size_vec2.y * cell_size.y)
		map_world_bounds = Rect2(Vector2.ZERO, world_size)
		print("[DEBUG] map_world_bounds:", map_world_bounds)
	else:
		return

	var camera_view_rect = camera_node.get_viewport_rect()


	# Allow camera center to reach the edge of the map, but not beyond
	var min_x = map_world_bounds.position.x
	var max_x = map_world_bounds.end.x
	var min_y = map_world_bounds.position.y
	var max_y = map_world_bounds.end.y

	# If the map is smaller than the viewport, center the camera
	if camera_view_rect.size.x >= map_world_bounds.size.x:
		min_x = map_world_bounds.get_center().x
		max_x = map_world_bounds.get_center().x
	if camera_view_rect.size.y >= map_world_bounds.size.y:
		min_y = map_world_bounds.get_center().y
		max_y = map_world_bounds.get_center().y

	# camera_node.limit_left = int(round(min_x))
	# camera_node.limit_right = int(round(max_x))
	# camera_node.limit_top = int(round(min_y))
	# camera_node.limit_bottom = int(round(max_y))

	print("[DEBUG] camera limits: left=", camera_node.limit_left, 
		  ", right=", camera_node.limit_right, 
		  ", top=", camera_node.limit_top, 
		  ", bottom=", camera_node.limit_bottom)

# Pan the camera by a delta in screen space (pixels)
func pan(delta: Vector2):
	if not is_instance_valid(camera_node):
		return
	if camera_node.zoom.x != 0.0:
		var pan_delta = delta * camera_pan_sensitivity / camera_node.zoom.x
		camera_node.position += pan_delta
		_clamp_camera_position()
		# print("[DFCAM-DEBUG] pan: delta=", delta, ", pan_delta=", pan_delta, ", new_position=", camera_node.position)

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

	var world_pos_after = camera_node.get_canvas_transform().affine_inverse() * screen_zoom_center
	camera_node.position += world_pos_before - world_pos_after
	
	_update_camera_limits()
	_clamp_camera_position()

	# print("[DFCAM-DEBUG] zoom_at_screen_pos: zoom_multiplier=", zoom_multiplier, ", clamped_zoom=", clamped_zoom, ", world_pos_before=", world_pos_before, ", world_pos_after=", world_pos_after, ", new_position=", camera_node.position)
	emit_signal("camera_zoom_changed", camera_node.zoom.x)



func fit_camera_to_tilemap():
	if not is_instance_valid(camera_node):
		return

	var cell_size = Vector2(16, 16)
	var map_world_bounds: Rect2
	print("[DEBUG] map_size:", map_size)
	print("[DEBUG] cell_size:", cell_size)
	if map_size.x > 0 and map_size.y > 0:
		var map_size_vec2 = Vector2(map_size.x, map_size.y)
		var world_size = Vector2(map_size_vec2.x * cell_size.x, map_size_vec2.y * cell_size.y)
		map_world_bounds = Rect2(Vector2.ZERO, world_size)
		print("[DEBUG] map_world_bounds:", map_world_bounds)
	else:
		return

	if map_world_bounds.size.x <= 0 or map_world_bounds.size.y <= 0:
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
	# camera_node.offset = Vector2.ZERO
	camera_node.position = map_world_bounds.get_center()
	_update_camera_limits()
	_clamp_camera_position()
	emit_signal("camera_zoom_changed", target_zoom)

func get_current_zoom() -> float:
	return camera_node.zoom.x if is_instance_valid(camera_node) else 1.0
