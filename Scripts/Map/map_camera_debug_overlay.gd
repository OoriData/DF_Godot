extends Node2D
## map_camera_debug_overlay.gd
## Visual debug overlay to show:
## 1. Map world bounds (green)
## 2. Camera visible world rectangle (yellow)
## 3. Pan clamp region for camera center (cyan outline)
## Toggle visibility via exported flags. Attach under the same SubViewport as the TileMap.

@export var camera_controller: MapCameraController
@export var camera_node: Camera2D
@export var show_map_bounds: bool = true
@export var show_camera_visible_rect: bool = true
@export var show_pan_bounds: bool = true
@export var auto_hide_when_menu_open: bool = false
@export var debug_logging: bool = false

var _last_zoom: float = -1.0

func _ready():
	set_process(true)

func _process(_dt: float):
	if not is_instance_valid(camera_controller) or not is_instance_valid(camera_node):
		return
	# Redraw only if zoom or position changed significantly
	var z = camera_node.zoom.x
	if not is_equal_approx(z, _last_zoom):
		_last_zoom = z
		queue_redraw()
	# Invalidate occasionally anyway
	queue_redraw()

func _draw():
	if not is_instance_valid(camera_controller) or not is_instance_valid(camera_node):
		return
	if auto_hide_when_menu_open and camera_controller._menu_open: # accessing internal flag ok for debug
		return

	var cell_size = camera_controller._get_cell_size()
	var map_w = camera_controller.map_size.x * cell_size.x
	var map_h = camera_controller.map_size.y * cell_size.y
	var origin := Vector2.ZERO
	if is_instance_valid(camera_controller.tilemap_ref):
		origin = camera_controller.tilemap_ref.position

	# 1. Map bounds
	if show_map_bounds:
		var map_rect := Rect2(origin, Vector2(map_w, map_h))
		draw_rect(map_rect, Color(0,1,0,0.08), true)
		draw_rect(map_rect, Color(0,1,0,0.6), false, 2.0)

	# 2. Camera visible world rectangle
	if show_camera_visible_rect:
		var vp_size = camera_controller.map_viewport_rect.size
		var zoom = max(camera_node.zoom.x, 0.0001)
		var visible_world_size = vp_size / zoom
		var cam_center = camera_node.position
		var top_left = cam_center - visible_world_size * 0.5
		var cam_rect := Rect2(top_left, visible_world_size)
		draw_rect(cam_rect, Color(1,1,0,0.08), true)
		draw_rect(cam_rect, Color(1,1,0,0.6), false, 2.0)

	# 3. Pan bounds region (center clamp range)
	if show_pan_bounds:
		var pan_bounds: Rect2 = camera_controller.get_current_pan_bounds()
		# Represent center clamp region as rectangle filled lightly
		draw_rect(pan_bounds, Color(0,1,1,0.05), true)
		draw_rect(pan_bounds, Color(0,1,1,0.7), false, 1.5)

	if debug_logging:
		print("[CamDebug] map_origin=", origin, " map_px=(", map_w, ",", map_h, ") zoom=", camera_node.zoom.x,
			  " vp_px=", camera_controller.map_viewport_rect.size,
			  " cam_pos=", camera_node.position)
