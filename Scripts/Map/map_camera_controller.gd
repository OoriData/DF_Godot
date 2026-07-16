class_name MapCameraController
extends Node

signal camera_zoom_changed(new_zoom_level: float)
signal focus_tween_finished

@export_group("Camera Controls")
@export var min_camera_zoom_level: float = 0.5 # Prevents excessive zoom out
@export var max_camera_zoom_level: float = 5.0
@export var enable_mouse_wheel_zoom: bool = true
@export var camera_zoom_factor_increment: float = 1.1
@export var camera_pan_sensitivity: float = 1.0 # Sensitivity for panning with mouse drag

@export var sub_viewport_node: SubViewport = null
@export var debug_logging: bool = true
@export var loose_pan_when_menu_open: bool = false # DEFAULT CHANGED: when menu opens, immediately use the shrunken viewport for clamping so edges stay locked to map
@export var freeze_zoom_for_menu_bounds: bool = true # If true, when menu opens capture zoom and use it for bounds until menu closes
@export var allow_map_edge_exposure: bool = false # If true, camera center can approach true map edge (viewport may show off-map)
@export var fit_margin: float = 1.0 # 1.0 means exact fit, < 1.0 adds margin (e.g. 0.95)
# Fraction of the map (on the axis that fully fills the viewport) that should remain pannable at the
# DEFAULT view. With FitMode.COVER the binding axis exactly fills the viewport at the fill zoom, leaving
# zero pan headroom on that axis until the user zooms in. By zooming the default view in by this fraction
# we guarantee the camera can pan to both edges of that axis without forcing the user to zoom first.
# 0.0 restores the old behavior (default zoom == fill zoom == pinned). 0.12 ≈ 12% of the map is pannable.
@export_range(0.0, 0.5, 0.01) var default_view_pan_headroom: float = 0.12

enum FitMode { CONTAIN, COVER }
@export var fit_mode: FitMode = FitMode.COVER
@export var auto_limit_zoom_out: bool = true # If true, min_camera_zoom_level is adjusted to prevent showing off-map
# Portrait zoom-OUT relaxation factor. Values > 1.0 let the user pull back PAST the COVER fill zoom,
# which necessarily exposes empty space beyond the map edges (a centered letterbox). Product decision
# (2026-06-26): the map must ALWAYS fully cover the screen — no empty space ever — so this is locked at
# 1.0 (floor stays at the COVER fill). Raising it re-introduces the letterbox; leave at 1.0 unless that
# requirement changes.
@export_range(1.0, 5.0, 0.1) var portrait_extra_zoom_out: float = 1.0

# Screen-space room (in viewport px, per side) reserved around a fitted convoy route so the
# world-space city labels at the route endpoints — which stay a roughly constant SCREEN size and
# overhang the route geometry — are not clipped at the viewport edges. Converted to world units at
# the estimated fit zoom in smooth_fit_route_preview. x = horizontal per side, y = vertical per side.
@export var route_fit_label_padding_px: Vector2 = Vector2(110.0, 80.0)
# Extra headroom (screen px) added ONLY to the TOP of the route-fit bounds, on top of
# route_fit_label_padding_px.y. Settlement labels anchor ABOVE their tile, and the route-line
# anti-collision nudge (UIManager._settlement_panel_overlaps_route) can push the topmost labels
# further up, so the top edge needs more clearance than the sides/bottom or those labels clip.
# Converted to world units at the estimated fit zoom, same as route_fit_label_padding_px.
@export var route_fit_label_top_extra_px: float = 60.0
# If true, smooth_fit_world_rect (used for journey route preview) is allowed to zoom out past the
# COVER floor so long routes show both endpoints. The map may briefly show empty space at the edges
# during the preview; the floor is re-enforced as soon as the user pans/zooms or closes the menu.
@export var route_fit_allow_zoom_past_cover: bool = true


var camera_node: Camera2D = null
var tilemap_ref: TileMapLayer = null
var map_viewport_rect: Rect2 = Rect2()
var _full_viewport_size: Vector2 = Vector2.ZERO # Remember the largest viewport so far (used for loose pan)
var _menu_open: bool = false
var _menu_open_reference_zoom: float = 1.0
# --- New: True map size (in tiles) ---
var map_size: Vector2i = Vector2i.ZERO

# --- Animation / Layout coordination state ---
var _viewport_updates_suppressed: bool = false # When true, viewport rect updates are deferred until unsuppressed
var _pending_viewport_rect: Rect2 = Rect2() # Stored most recent rect while suppressed
var _active_focus_tween: Tween = null # Active tween for smooth camera focusing
var _active_focus_tween_is_fit: bool = false
var _overlay_occlusion_px_x: float = 0.0 # Horizontal pixels on right side covered by overlay (menu) and thus not visible
var _overlay_occlusion_px_y: float = 0.0 # Vertical pixels on bottom side covered by overlay (menu) and thus not visible
var _debug_menu_focus: bool = false # Toggle detailed menu focus diagnostics (set to false to disable overlay)
var _debug_overlay_label: Label = null
var _last_tween_target: Vector2 = Vector2.ZERO

@export_group("Focus Tween")
@export var focus_tween_duration_default: float = 0.6
@export var focus_tween_trans: int = Tween.TRANS_SINE
@export var focus_tween_ease: int = Tween.EASE_IN_OUT

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
		_full_viewport_size = map_viewport_rect.size
		_dbg("initialize", {
 			"viewport_rect": map_viewport_rect,
 			"tilemap_valid": is_instance_valid(tilemap_ref),
 			"camera_valid": is_instance_valid(camera_node)
 		})

func _ready():
	if not debug_logging:
		print("[MCC] Debug logging disabled. Enable 'debug_logging' on MapCameraController to see diagnostics.")
	# Debug overlay is now disabled by default
	
	# Listen to viewport changes directly to ensure synchronization
	# NOTE: We do NOT connect to window viewport's size_changed here.
	# The authoritative viewport rect comes from update_map_viewport_rect(),
	# which is called by MainScreen with the actual map_display global rect.
	# Listening to the raw window size caused the camera to reset to the full
	# window height (ignoring the TopBar), which prevented reaching the map bottom.


func update_map_viewport_rect(new_rect: Rect2):
	if not is_instance_valid(camera_node) or not is_instance_valid(sub_viewport_node):
		printerr("[MCC] Cannot update, camera or sub_viewport is not valid.")
		return

	# Defer updates during animated layout transitions to avoid jitter/tearing
	if _viewport_updates_suppressed:
		_pending_viewport_rect = new_rect
		return

	# CRITICAL FIX: Synchronize the SubViewport's size with the actual UI control's size.
	# The size of the control showing the viewport (e.g., TextureRect) dictates the render size.
	if new_rect.size.x > 0 and new_rect.size.y > 0:
		sub_viewport_node.size = Vector2i(new_rect.size)
		map_viewport_rect = Rect2(Vector2.ZERO, new_rect.size)
		var is_new_portrait: bool = new_rect.size.y > new_rect.size.x
		var was_portrait: bool = _full_viewport_size.y > _full_viewport_size.x
		if _full_viewport_size != Vector2.ZERO and is_new_portrait != was_portrait:
			# Aspect ratio flipped. Invalidate the cache to prevent stale layout tracking.
			_full_viewport_size = new_rect.size
		
		# Now perform the normal maximums tracking
		if map_viewport_rect.size.x > _full_viewport_size.x or map_viewport_rect.size.y > _full_viewport_size.y:
			_full_viewport_size = map_viewport_rect.size
		# print("[DFCAM-DEBUG] update_map_viewport_rect: Synced SubViewport size to ", sub_viewport_node.size)
	else:
		# Fallback if the new_rect is invalid, use the existing SubViewport size.
		map_viewport_rect = Rect2(Vector2.ZERO, sub_viewport_node.size)
		# print("[DFCAM-DEBUG] update_map_viewport_rect: new_rect was invalid, using existing SubViewport size=", sub_viewport_node.size)

	_update_camera_limits()
	
	# CRITICAL: If auto_limit_zoom_out is active, ensure current zoom doesn't violate new bounds
	if is_instance_valid(camera_node):
		var cur_z = camera_node.zoom.x
		var new_z = clampf(cur_z, min_camera_zoom_level, max_camera_zoom_level)
		if not is_equal_approx(cur_z, new_z):
			camera_node.zoom = Vector2(new_z, new_z)
			emit_signal("camera_zoom_changed", new_z)
	
	# Preserve current zoom/position on layout changes; just clamp to new bounds
	_clamp_camera_position()
	
	# DIAGNOSTICS:
	if debug_logging:
		print("[MCC] update_map_viewport_rect: new_rect=%s, sub_size=%s, min_zoom=%.4f, current_zoom=%.4f, cam_pos=%s" % [
			str(new_rect), str(sub_viewport_node.size), min_camera_zoom_level, 
			(camera_node.zoom.x if is_instance_valid(camera_node) else -1.0),
			(camera_node.position if is_instance_valid(camera_node) else Vector2.ZERO)
		])
	
	_dbg("update_map_viewport_rect", {"sub_size": sub_viewport_node.size, "map_viewport_rect": map_viewport_rect, "zoom": (camera_node.zoom.x if is_instance_valid(camera_node) else -1.0), "cam_pos": (camera_node.position if is_instance_valid(camera_node) else Vector2.ZERO)})

func _clamp_camera_position():
	if not is_instance_valid(camera_node):
		return
	# Clamp camera so the entire viewport stays within map bounds
	var cell_size = _get_cell_size()
	var map_width = map_size.x * cell_size.x
	var map_height = map_size.y * cell_size.y
	var _dbg_sub_size = sub_viewport_node.size if is_instance_valid(sub_viewport_node) else Vector2i(-1,-1)
	var _dbg_zoom = camera_node.zoom.x
	var _dbg_half_h = Vector2(_dbg_sub_size).y / max(_dbg_zoom, 0.0001) / 2.0
	var _dbg_max_y = map_height - _dbg_half_h
	var _dbg_win := Vector2.ZERO
	if is_inside_tree() and get_viewport():
		_dbg_win = get_viewport().get_visible_rect().size
	print("[CLAMP] sub_vp=%s win=%s mvr=%s sub_aspect=%.3f win_aspect=%.3f zoom=%.4f half_full_h=%.1f map_h=%.1f min_y=%.1f max_y=%.1f cam_y=%.1f" % [
		str(_dbg_sub_size), str(_dbg_win), str(map_viewport_rect.size),
		(float(_dbg_sub_size.x) / max(1.0, float(_dbg_sub_size.y))),
		(_dbg_win.x / max(1.0, _dbg_win.y)),
		_dbg_zoom, _dbg_half_h, map_height,
		_dbg_half_h, _dbg_max_y, camera_node.position.y
	])
	# Account for possible tilemap positional offset (non-zero origin)
	var map_origin: Vector2 = Vector2.ZERO
	if is_instance_valid(tilemap_ref):
		map_origin = tilemap_ref.position
	# Optionally use the largest historical viewport when the menu is open (loose pan)
	# CRITICAL: Use the actual SubViewport render size as source of truth
	var current_viewport_px: Vector2 = map_viewport_rect.size
	if is_instance_valid(sub_viewport_node):
		current_viewport_px = Vector2(sub_viewport_node.size)
	var effective_viewport_size = current_viewport_px
	if _menu_open and loose_pan_when_menu_open and _full_viewport_size != Vector2.ZERO:
		effective_viewport_size = _full_viewport_size
	var viewport_size = effective_viewport_size
	var zoom = camera_node.zoom.x
	if _menu_open and freeze_zoom_for_menu_bounds:
		zoom = _menu_open_reference_zoom
	# Adjust visible width by subtracting overlay occlusion (menu covering map). Prevent negative values.
	var adjusted_viewport_w_px = max(0.0, viewport_size.x - _overlay_occlusion_px_x)
	var adjusted_world_w = adjusted_viewport_w_px / max(zoom, 0.0001) # width of visible (non-occluded) region
	var full_world_w = viewport_size.x / max(zoom, 0.0001) # width if no occlusion considered
	
	var adjusted_viewport_h_px = max(0.0, viewport_size.y - _overlay_occlusion_px_y)
	var adjusted_world_h = adjusted_viewport_h_px / max(zoom, 0.0001)
	var full_world_h = viewport_size.y / max(zoom, 0.0001)
	
	var half_full_w = full_world_w * 0.5
	var half_full_h = full_world_h * 0.5

	# World width covered by the overlay (menu) – we can extend the limit by this without exposing off-map in visible region.
	var occlusion_world_w: float = _overlay_occlusion_px_x / max(zoom, 0.1)
	var occlusion_world_h: float = _overlay_occlusion_px_y / max(zoom, 0.1)

	# Left bound: use half of FULL width so left edge never shows off-map.
	var min_x = map_origin.x + half_full_w
	# Right bound: allow overshoot up to occlusion width (area hidden under menu overlay).
	var max_x = map_origin.x + map_width - half_full_w + occlusion_world_w

	# Ensure max_x is at least min_x (for very small maps)
	if max_x < min_x:
		max_x = min_x
		
	var min_y = map_origin.y + half_full_h
	var max_y = map_origin.y + map_height - half_full_h + occlusion_world_h
	if max_y < min_y:
		max_y = min_y

	if allow_map_edge_exposure:
		# Allow camera center closer to edges; reduce margin by 75% (configurable strategy)
		var margin_factor := 0.25
		min_x = lerp(min_x, 0.0, margin_factor)
		max_x = lerp(max_x, map_width, margin_factor)
		min_y = lerp(min_y, 0.0, margin_factor)
		max_y = lerp(max_y, map_height, margin_factor)

	# If the map is smaller than the visible non-occluded world area, center the camera
	if map_width <= adjusted_world_w:
		min_x = map_origin.x + map_width * 0.5 + occlusion_world_w * 0.5
		max_x = min_x
	if map_height <= adjusted_world_h:
		min_y = map_origin.y + map_height * 0.5 + occlusion_world_h * 0.5
		max_y = min_y

	camera_node.position.x = clamp(camera_node.position.x, min_x, max_x)
	camera_node.position.y = clamp(camera_node.position.y, min_y, max_y)
	_dbg("clamp", {
		"map_w": map_width,
		"map_h": map_height,
		"map_origin": map_origin,
		"view_px": viewport_size,
		"overlay_px_x": _overlay_occlusion_px_x,
		"overlay_px_y": _overlay_occlusion_px_y,
		"raw_view_px": map_viewport_rect.size,
		"full_view_px": _full_viewport_size,
		"menu_open": _menu_open,
		"zoom": zoom,
		"world_w_full": full_world_w,
		"world_w_visible": adjusted_world_w,
		"world_h_full": full_world_h,
		"world_h_visible": adjusted_world_h,
		"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y,
		"occlusion_world_w": occlusion_world_w,
		"occlusion_world_h": occlusion_world_h,
		"cam_pos": camera_node.position
	})


func _update_camera_limits():
	if not is_instance_valid(camera_node) or camera_node.zoom.x <= 0:
		return

	# Use only the true map size for camera bounds
	var cell_size = _get_cell_size()
	var map_world_bounds: Rect2
	if map_size.x > 0 and map_size.y > 0:
		var map_size_vec2 = Vector2(map_size.x, map_size.y)
		var world_size = Vector2(map_size_vec2.x * cell_size.x, map_size_vec2.y * cell_size.y)
		map_world_bounds = Rect2(Vector2.ZERO, world_size)
	else:
		_dbg("limits_skip_no_map_size")
		return

	var viewport_px = map_viewport_rect.size
	if is_instance_valid(sub_viewport_node):
		viewport_px = Vector2(sub_viewport_node.size)
	var effective_viewport_px = viewport_px
	if _menu_open and loose_pan_when_menu_open and _full_viewport_size != Vector2.ZERO:
		effective_viewport_px = _full_viewport_size
	
	# --- Dynamic Zoom Limit Update ---
	if auto_limit_zoom_out:
		var map_w = map_size.x * cell_size.x
		var map_h = map_size.y * cell_size.y
		if map_w > 0 and map_h > 0:
			var zoom_min_x = effective_viewport_px.x / map_w
			var zoom_min_y = effective_viewport_px.y / map_h
			var requested_min = max(zoom_min_x, zoom_min_y) if fit_mode == FitMode.COVER else min(zoom_min_x, zoom_min_y)
			# Raise the zoom floor just above the exact COVER fill zoom so the binding axis (the one that
			# fully fills the viewport) keeps pan headroom at EVERY zoom level. Without this the user can
			# zoom out to the fill zoom where that axis is pinned (min_y == max_y) and cannot pan to the
			# map's far edge. This is the authoritative floor; fit_camera_to_tilemap mirrors it.
			if fit_mode == FitMode.COVER and default_view_pan_headroom > 0.0:
				requested_min = requested_min / (1.0 - clampf(default_view_pan_headroom, 0.0, 0.5))
			# Portrait only: relax the zoom-out floor so the map can be pulled back further than the COVER
			# fill. The default view is seated against the strict floor in fit_camera_to_tilemap before this
			# runs, so this affects how far OUT the user can zoom, not the opening framing.
			var is_portrait: bool = effective_viewport_px.y > effective_viewport_px.x
			if is_portrait and portrait_extra_zoom_out > 1.0:
				requested_min = requested_min / portrait_extra_zoom_out
			min_camera_zoom_level = requested_min
	
	var zoom = max(camera_node.zoom.x, 0.0001)
	if _menu_open and freeze_zoom_for_menu_bounds:
		zoom = max(_menu_open_reference_zoom, 0.0001)
	var adjusted_w_px = max(0.0, effective_viewport_px.x - _overlay_occlusion_px_x)
	var adjusted_h_px = max(0.0, effective_viewport_px.y - _overlay_occlusion_px_y)
	var visible_world = Vector2(adjusted_w_px / zoom, adjusted_h_px / zoom)

	# Nothing to set on Camera2D limits (we clamp manually), but log useful info
	var will_center_x = visible_world.x >= map_world_bounds.size.x
	var will_center_y = visible_world.y >= map_world_bounds.size.y

	_dbg("limits", {
		"map_bounds": map_world_bounds,
		"viewport_px": effective_viewport_px,
		"overlay_px_x": _overlay_occlusion_px_x,
		"overlay_px_y": _overlay_occlusion_px_y,
		"raw_viewport_px": viewport_px,
		"full_viewport_px": _full_viewport_size,
		"menu_open": _menu_open,
		"zoom": zoom,
		"visible_world": visible_world,
		"center_x": will_center_x,
		"center_y": will_center_y
	})

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

	# If menu is open with freeze bounds, keep reference zoom in sync to avoid stale limits
	if _menu_open and freeze_zoom_for_menu_bounds:
		_menu_open_reference_zoom = clamped_zoom

	var world_pos_after = camera_node.get_canvas_transform().affine_inverse() * screen_zoom_center
	camera_node.position += world_pos_before - world_pos_after
	
	_update_camera_limits()
	_clamp_camera_position()

	# print("[DFCAM-DEBUG] zoom_at_screen_pos: zoom_multiplier=", zoom_multiplier, ", clamped_zoom=", clamped_zoom, ", world_pos_before=", world_pos_before, ", world_pos_after=", world_pos_after, ", new_position=", camera_node.position)
	emit_signal("camera_zoom_changed", camera_node.zoom.x)



func fit_camera_to_tilemap():
	if not is_instance_valid(camera_node):
		return
	_trace_focus("fit_camera_to_tilemap")

	var cell_size = _get_cell_size()
	var map_world_bounds: Rect2
	if map_size.x > 0 and map_size.y > 0:
		var map_size_vec2 = Vector2(map_size.x, map_size.y)
		var world_size = Vector2(map_size_vec2.x * cell_size.x, map_size_vec2.y * cell_size.y)
		map_world_bounds = Rect2(Vector2.ZERO, world_size)
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
	
	var target_zoom: float = 1.0
	if fit_mode == FitMode.COVER:
		target_zoom = max(zoom_x, zoom_y)
	else: # FitMode.CONTAIN
		target_zoom = min(zoom_x, zoom_y)

	target_zoom *= fit_margin

	# If auto-limiting zoom out, update min_camera_zoom_level dynamically.
	# NOTE: this is the zoom at which the binding axis EXACTLY fills the viewport. At this zoom there is
	# zero pan headroom on that axis, so it is the floor for zooming OUT, not the default view.
	if auto_limit_zoom_out:
		var min_fill_zoom = max(zoom_x, zoom_y)
		var min_fit_zoom = min(zoom_x, zoom_y)
		# If we want to allow seeing the whole map even with bars, use min_fit_zoom.
		# If we want to ALWAYS fill the screen, use min_fill_zoom.
		# Let's default to min_fit_zoom if CONTAIN, or min_fill_zoom if COVER.
		var requested_min = min_fill_zoom if fit_mode == FitMode.COVER else min_fit_zoom
		# Mirror the headroom-adjusted floor from _update_camera_limits so the default view and the
		# zoom-out floor agree: the binding axis keeps pan headroom even when fully zoomed out.
		if fit_mode == FitMode.COVER and default_view_pan_headroom > 0.0:
			requested_min = requested_min / (1.0 - clampf(default_view_pan_headroom, 0.0, 0.5))
		min_camera_zoom_level = requested_min

	# Clamp the default view into the (headroom-adjusted) zoom range. For COVER this raises the default
	# up to the floor so the camera starts with pan headroom on both axes instead of being pinned.
	target_zoom = clamp(target_zoom, min_camera_zoom_level, max_camera_zoom_level)
	camera_node.zoom = Vector2(target_zoom, target_zoom)
	# camera_node.offset = Vector2.ZERO
	camera_node.position = map_world_bounds.get_center()
	_update_camera_limits()
	_clamp_camera_position()
	
	if debug_logging:
		print("[MCC] fit_camera_to_tilemap: viewport=%s, map_bounds=%s, target_zoom=%.4f, min_zoom=%.4f, final_pos=%s" % [
			str(viewport_size), str(map_world_bounds), target_zoom, min_camera_zoom_level, camera_node.position
		])

	emit_signal("camera_zoom_changed", target_zoom)
	_dbg("fit", {"map_bounds": map_world_bounds, "viewport": viewport_size, "target_zoom": target_zoom, "cam_pos": camera_node.position})

func get_current_zoom() -> float:
	return camera_node.zoom.x if is_instance_valid(camera_node) else 1.0

# --- NEW: Camera focusing helpers ---
func focus_on_world_pos(world_pos: Vector2):
	if not is_instance_valid(camera_node):
		return
	_trace_focus("focus_on_world_pos", world_pos)
	# If overlay occludes right or bottom edge, bias camera center so target appears in visible area.
	var zoom = max(camera_node.zoom.x, 0.0001)
	if _overlay_occlusion_px_x > 0.0:
		var occlusion_world_w: float = _overlay_occlusion_px_x / zoom
		# Shift right by half horizontal occlusion width.
		world_pos.x += occlusion_world_w * 0.5
	if _overlay_occlusion_px_y > 0.0:
		var occlusion_world_h: float = _overlay_occlusion_px_y / zoom
		# Shift down by half vertical occlusion width.
		world_pos.y += occlusion_world_h * 0.5
	camera_node.position = world_pos
	_clamp_camera_position()

func focus_on_tile(tile: Vector2i):
	var pos := Vector2.ZERO
	if is_instance_valid(tilemap_ref):
		pos = tilemap_ref.map_to_local(tile)
	else:
		var sz = _get_cell_size()
		pos = Vector2(tile.x * sz.x, tile.y * sz.y)
	focus_on_world_pos(pos)

func get_convoy_world_position(convoy_data: Dictionary) -> Vector2:
	if convoy_data.is_empty():
		return camera_node.position if is_instance_valid(camera_node) else Vector2.ZERO
	# Prefer journey interpolation if available
	var final_pixel_pos := Vector2.ZERO
	var raw_journey = convoy_data.get("journey")
	var journey_data: Dictionary = {}
	if raw_journey is Dictionary:
		journey_data = raw_journey
	var route_x: Array = journey_data.get("route_x", [])
	var route_y: Array = journey_data.get("route_y", [])
	var current_segment_idx: int = convoy_data.get("_current_segment_start_idx", -1)
	var progress_in_segment: float = convoy_data.get("_progress_in_segment", 0.0)

	if current_segment_idx != -1 and \
		route_x.size() > current_segment_idx and route_y.size() > current_segment_idx:
		var start_tile := Vector2i(int(route_x[current_segment_idx]), int(route_y[current_segment_idx]))
		var end_tile := start_tile
		if route_x.size() > current_segment_idx + 1 and route_y.size() > current_segment_idx + 1:
			end_tile = Vector2i(int(route_x[current_segment_idx + 1]), int(route_y[current_segment_idx + 1]))
		if is_instance_valid(tilemap_ref):
			var p_start_pixel = tilemap_ref.map_to_local(start_tile)
			var p_end_pixel = tilemap_ref.map_to_local(end_tile)
			final_pixel_pos = p_start_pixel.lerp(p_end_pixel, clamp(progress_in_segment, 0.0, 1.0))
		else:
			var cs = _get_cell_size()
			final_pixel_pos = Vector2(start_tile) * cs
	else:
		# Fallback to top-level x/y as tile coords
		var map_x: float = convoy_data.get("x", 0.0)
		var map_y: float = convoy_data.get("y", 0.0)
		var tile := Vector2i(int(map_x), int(map_y))
		if is_instance_valid(tilemap_ref):
			final_pixel_pos = tilemap_ref.map_to_local(tile)
		else:
			var cs2 = _get_cell_size()
			final_pixel_pos = Vector2(tile) * cs2
	return final_pixel_pos

func focus_on_convoy(convoy_data: Dictionary):
	var pos = get_convoy_world_position(convoy_data)
	focus_on_world_pos(pos)

func get_current_pan_bounds() -> Rect2:
	# Returns a Rect2 describing the min/max camera center positions allowed (world space)
	var cell_size = _get_cell_size()
	var map_width = map_size.x * cell_size.x
	var map_height = map_size.y * cell_size.y
	var map_origin: Vector2 = Vector2.ZERO
	if is_instance_valid(tilemap_ref):
		map_origin = tilemap_ref.position
	var effective_viewport_size = map_viewport_rect.size
	if _menu_open and loose_pan_when_menu_open and _full_viewport_size != Vector2.ZERO:
		effective_viewport_size = _full_viewport_size
	var zoom = max(camera_node.zoom.x, 0.0001)
	if _menu_open and freeze_zoom_for_menu_bounds:
		zoom = max(_menu_open_reference_zoom, 0.0001)
	var visible_world_w = effective_viewport_size.x / zoom
	var visible_world_h = effective_viewport_size.y / zoom
	var half_w = visible_world_w * 0.5
	var half_h = visible_world_h * 0.5
	var occlusion_world_w: float = _overlay_occlusion_px_x / zoom
	var occlusion_world_h: float = _overlay_occlusion_px_y / zoom
	var min_x = map_origin.x + half_w
	var max_x = map_origin.x + map_width - half_w + occlusion_world_w
	if max_x < min_x:
		max_x = min_x
	var min_y = map_origin.y + half_h
	var max_y = map_origin.y + map_height - half_h + occlusion_world_h
	if max_y < min_y:
		max_y = min_y
	if allow_map_edge_exposure:
		var margin_factor := 0.25
		min_x = lerp(min_x, 0.0, margin_factor)
		max_x = lerp(max_x, map_width, margin_factor)
		min_y = lerp(min_y, 0.0, margin_factor)
		max_y = lerp(max_y, map_height, margin_factor)
	var adjusted_world_w = max(0.0, effective_viewport_size.x - _overlay_occlusion_px_x) / zoom
	var adjusted_world_h = max(0.0, effective_viewport_size.y - _overlay_occlusion_px_y) / zoom
	if map_width <= adjusted_world_w:
		min_x = map_origin.x + map_width * 0.5 + occlusion_world_w * 0.5
		max_x = min_x
	if map_height <= adjusted_world_h:
		min_y = map_origin.y + map_height * 0.5 + occlusion_world_h * 0.5
		max_y = min_y
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func set_menu_open_state(is_open: bool, and_clamp_immediately: bool = true):
	_menu_open = is_open
	if _menu_open and freeze_zoom_for_menu_bounds:
		_menu_open_reference_zoom = camera_node.zoom.x if is_instance_valid(camera_node) else 1.0
	_update_camera_limits()
	if and_clamp_immediately:
		_clamp_camera_position()
	_dbg("menu_state", {"open": _menu_open, "pan_bounds": get_current_pan_bounds(), "cam_pos": (camera_node.position if is_instance_valid(camera_node) else Vector2.ZERO)})

# Resets any temporary "fit" state and returns camera to normal clamped map bounds.
func reset_camera_to_map_bounds() -> void:
	if not is_instance_valid(camera_node):
		return
	if _active_focus_tween and _active_focus_tween.is_valid():
		_active_focus_tween.kill()
	_active_focus_tween = null
	_active_focus_tween_is_fit = false

	_update_camera_limits()

	var current_zoom: float = maxf(camera_node.zoom.x, 0.0001)
	var clamped_zoom: float = clampf(current_zoom, min_camera_zoom_level, max_camera_zoom_level)
	if not is_equal_approx(current_zoom, clamped_zoom):
		camera_node.zoom = Vector2(clamped_zoom, clamped_zoom)
		emit_signal("camera_zoom_changed", clamped_zoom)
		if _menu_open and freeze_zoom_for_menu_bounds:
			_menu_open_reference_zoom = clamped_zoom

	_clamp_camera_position()

# Public setter to mirror MIM API and toggle edge exposure at runtime
func set_allow_camera_outside_bounds(allow: bool) -> void:
	allow_map_edge_exposure = allow
	_update_camera_limits()
	_clamp_camera_position()

# Public setter so scenes with saved export values can be overridden at runtime
func set_loose_pan_when_menu_open(enabled: bool) -> void:
	loose_pan_when_menu_open = enabled
	_update_camera_limits()
	_clamp_camera_position()

func set_freeze_zoom_for_menu_bounds(enabled: bool) -> void:
	freeze_zoom_for_menu_bounds = enabled
	if _menu_open and enabled:
		_menu_open_reference_zoom = camera_node.zoom.x if is_instance_valid(camera_node) else 1.0
	_update_camera_limits()
	_clamp_camera_position()

# --- New: Animation helpers ---
func suppress_viewport_updates(suppress: bool) -> void:
	_viewport_updates_suppressed = suppress
	if not suppress and _pending_viewport_rect.size != Vector2.ZERO:
		# Apply the last deferred rect now that suppression lifted
		var rect_to_apply := _pending_viewport_rect
		_pending_viewport_rect = Rect2()
		update_map_viewport_rect(rect_to_apply)

func smooth_focus_on_world_pos(world_pos: Vector2, duration: float = 0.5) -> void:
	if not is_instance_valid(camera_node):
		return
	_trace_focus("smooth_focus_on_world_pos", world_pos)
	if _active_focus_tween and _active_focus_tween.is_valid():
		_active_focus_tween.kill()
	_active_focus_tween_is_fit = false

	# Clamp the target position before tweening to respect map boundaries.
	var clamped_world_pos = _get_clamped_camera_pos(world_pos)

	if duration <= 0.0:
		duration = focus_tween_duration_default
	_active_focus_tween = create_tween()
	_active_focus_tween.set_trans(focus_tween_trans).set_ease(focus_tween_ease)
	_active_focus_tween.tween_property(camera_node, "position", clamped_world_pos, duration)
	_active_focus_tween.finished.connect(Callable(self, "_on_focus_tween_finished"))
	_last_tween_target = clamped_world_pos
	if _debug_menu_focus:
		_dbg("tween_start", {"from": camera_node.position, "to": clamped_world_pos, "duration": duration})

func smooth_focus_on_convoy(convoy_data: Dictionary, duration: float = 0.5) -> void:
	var target_world := get_convoy_world_position(convoy_data)
	if target_world == Vector2.ZERO:
		return
	
	# ACCOUNT FOR OCCLUSION: Just like immediate focus_on_convoy, smooth focus must
	# respect the current overlay occlusion to ensure the convoy is centered in the visible area.
	var zoom = max(camera_node.zoom.x, 0.0001)
	if _overlay_occlusion_px_x > 0.0:
		var occlusion_world_w: float = _overlay_occlusion_px_x / zoom
		target_world.x += occlusion_world_w * 0.5
	if _overlay_occlusion_px_y > 0.0:
		var occlusion_world_h: float = _overlay_occlusion_px_y / zoom
		target_world.y += occlusion_world_h * 0.5

	smooth_focus_on_world_pos(target_world, duration)

# Focus convoy expecting a final overlay occlusion width (in pixels). Bias computed from provided value, not current animated value.
func smooth_focus_on_convoy_with_final_occlusion(convoy_data: Dictionary, final_occlusion_px: float, duration: float = 0.5, is_vertical: bool = false) -> void:
	if not is_instance_valid(camera_node):
		return
	var target_world := get_convoy_world_position(convoy_data)
	if target_world == Vector2.ZERO:
		return
	var zoom = max(camera_node.zoom.x, 0.0001)
	var bias_world: float = (final_occlusion_px / zoom) * 0.5
	var biased_target := target_world
	if is_vertical:
		biased_target.y += bias_world
	else:
		biased_target.x += bias_world
	# Clamp against the FINAL overlay occlusion (the value the menu animates TO), not the current one.
	# On a close (final_occlusion_px == 0) this yields the tight, fully-in-map bounds, so the tween
	# already targets a legal resting position — no end-snap, and the per-frame close clamp has nothing
	# to fight. final bounds ⊆ current bounds, so smooth_focus_on_world_pos's own clamp leaves it intact.
	var occ_x_final: float = final_occlusion_px if not is_vertical else 0.0
	var occ_y_final: float = final_occlusion_px if is_vertical else 0.0
	biased_target = _get_clamped_camera_pos_for_zoom(biased_target, zoom, occ_x_final, occ_y_final)
	if _debug_menu_focus:
		_dbg("menu_focus_compute", {
			"raw_target": target_world,
			"final_occlusion_px": final_occlusion_px,
			"is_vertical": is_vertical,
			"zoom": zoom,
			"bias_world": bias_world,
			"biased_target": biased_target,
			"cam_start": (camera_node.position if is_instance_valid(camera_node) else Vector2.ZERO)
		})
	smooth_focus_on_world_pos(biased_target, duration)

# --- NEW: Fit helpers (zoom + pan to bounds) ---
# Smoothly zoom out/in so a world-space rect is fully visible in the *non-occluded* map area.
# If target_focus_point is provided, camera will prioritize keeping that point in view when zoom is restricted.
func smooth_fit_world_rect(world_rect: Rect2, duration: float = 0.6, margin: float = 0.92, target_focus_point: Vector2 = Vector2.INF) -> void:
	if not is_instance_valid(camera_node):
		return
	_trace_focus("smooth_fit_world_rect", world_rect)
	# Allow 0 width/height (perfectly straight routes) by treating as thin rects.
	if world_rect.size.x <= 0.0 and world_rect.size.y <= 0.0:
		return
	# Kill any active focus tween to avoid fighting.
	if _active_focus_tween and _active_focus_tween.is_valid():
		_active_focus_tween.kill()
	_active_focus_tween_is_fit = true

	# Use current render size as source of truth.
	var viewport_px: Vector2 = map_viewport_rect.size
	if is_instance_valid(sub_viewport_node):
		viewport_px = Vector2(sub_viewport_node.size)
	if viewport_px.x <= 0.0 or viewport_px.y <= 0.0:
		viewport_px = get_viewport().get_visible_rect().size
	if viewport_px.x <= 0.0 or viewport_px.y <= 0.0:
		return

	# Available width excludes overlay occlusion.
	var visible_w_px: float = max(1.0, viewport_px.x - _overlay_occlusion_px_x)
	var visible_h_px: float = max(1.0, viewport_px.y - _overlay_occlusion_px_y)
	var rect_w: float = max(1.0, world_rect.size.x)
	var rect_h: float = max(1.0, world_rect.size.y)

	# Camera2D.zoom < 1.0 zooms out. Choose CONTAIN behavior (fit inside view).
	var zoom_x: float = visible_w_px / rect_w
	var zoom_y: float = visible_h_px / rect_h
	var target_zoom: float = min(zoom_x, zoom_y) * clamp(margin, 0.5, 1.0)
	
	# Cap zoom-out at the cover floor so the map always fills the screen — unless
	# route_fit_allow_zoom_past_cover is set, which lets long routes zoom far enough to show both
	# endpoints even if that briefly exposes map edges. The floor is re-enforced on the next
	# pan/zoom or menu close.
	var absolute_min = min_camera_zoom_level
	if not route_fit_allow_zoom_past_cover and target_zoom < absolute_min:
		if debug_logging:
			print("[MCC] smooth_fit_world_rect: target_zoom %.4f capped to min_camera_zoom_level %.4f" % [target_zoom, absolute_min])
		target_zoom = absolute_min

	target_zoom = clamp(target_zoom, 0.05, max_camera_zoom_level)

	# If menu is open and we freeze zoom for bounds, keep the reference in sync.
	if _menu_open and freeze_zoom_for_menu_bounds:
		_menu_open_reference_zoom = target_zoom

	var start_zoom: float = maxf(camera_node.zoom.x, 0.0001)
	# Compute centers. If target_focus_point is INF, defaults to rect center.
	var start_center: Vector2 = _get_fit_center_for_world_rect_and_zoom(world_rect, start_zoom, target_focus_point)
	var final_center: Vector2 = _get_fit_center_for_world_rect_and_zoom(world_rect, target_zoom, target_focus_point)

	if duration <= 0.0:
		duration = focus_tween_duration_default
	# Split: quick pan to route center (at current zoom), then zoom while keeping that center anchored.
	var pan_time: float = minf(0.18, duration * 0.35)
	var zoom_time: float = maxf(0.05, duration - pan_time)

	_active_focus_tween = create_tween()
	_active_focus_tween.set_trans(focus_tween_trans).set_ease(focus_tween_ease)
	if camera_node.position.distance_to(start_center) > 1.0:
		_active_focus_tween.tween_property(camera_node, "position", start_center, pan_time)
	# During zoom, keep the rect fully visible (bias changes with zoom).
	_active_focus_tween.tween_method(
		Callable(self, "_apply_fit_zoom_step").bind(world_rect, target_focus_point),
		start_zoom,
		target_zoom,
		zoom_time
	)
	_active_focus_tween.finished.connect(Callable(self, "_on_focus_tween_finished"))
	_last_tween_target = final_center
	_dbg("fit_rect", {"rect": world_rect, "target_zoom": target_zoom, "start_zoom": start_zoom, "start_center": start_center, "final_center": final_center})

# Convenience: extract the journey route polyline and fit to its bounds.
func smooth_fit_route_preview(route_data: Dictionary, duration: float = 0.6, margin: float = 0.92) -> void:
	if not (route_data is Dictionary):
		return
	var journey: Variant = route_data.get("journey")
	if not (journey is Dictionary):
		return
	var rx: Variant = (journey as Dictionary).get("route_x", [])
	var ry: Variant = (journey as Dictionary).get("route_y", [])
	if not (rx is Array and ry is Array):
		return
	var route_x: Array = rx
	var route_y: Array = ry
	if route_x.size() < 2 or route_y.size() != route_x.size():
		return
	var bounds := _get_route_world_bounds(route_x, route_y)
	if bounds.size.x <= 0.0 and bounds.size.y <= 0.0:
		return
	# Pad so endpoints/line thickness aren't tight against edges.
	var pad := _get_cell_size() * 0.75
	bounds = bounds.grow_individual(pad.x, pad.y, pad.x, pad.y)

	# City labels at the route endpoints render in world space but hold a roughly constant SCREEN
	# size, so at the fitted zoom they overhang these bounds and clip at the viewport edges. Estimate
	# the fit zoom for the (padded) route, convert the desired label screen padding to world units, and
	# grow the bounds so the labels keep their room regardless of route length / final zoom.
	var est_zoom := _estimate_fit_zoom(bounds, margin)
	if est_zoom > 0.0001:
		var lpad := route_fit_label_padding_px / est_zoom
		# Labels anchor above their tile (and A4's route-nudge pushes the topmost ones further up), so
		# the TOP gets extra headroom. grow_individual args are (left, top, right, bottom); "top" grows
		# the -Y (visually upward) side, which is where labels overhang.
		var top_extra: float = route_fit_label_top_extra_px / est_zoom
		bounds = bounds.grow_individual(lpad.x, lpad.y + top_extra, lpad.x, lpad.y)

	# Determine destination world position to prioritize as focus point
	var dest_tile := Vector2i(int(route_x.back()), int(route_y.back()))
	var dest_world := Vector2.ZERO
	if is_instance_valid(tilemap_ref):
		dest_world = tilemap_ref.map_to_local(dest_tile)
	else:
		dest_world = Vector2(dest_tile) * _get_cell_size()

	# The destination's city label renders ABOVE its tile. For longer routes smooth_fit_world_rect blends
	# the camera toward this focus point — and if we point at the bare tile, the fit centers below the
	# label so only its lower half (down to its center) shows. Lift the focus up by the top headroom so
	# the fit targets where the LABEL sits and keeps the whole thing in view. Same knob as the bounds pad.
	if est_zoom > 0.0001:
		dest_world.y -= route_fit_label_top_extra_px / est_zoom

	smooth_fit_world_rect(bounds, duration, margin, dest_world)

func _get_route_world_bounds(route_x: Array, route_y: Array) -> Rect2:
	var minv := Vector2(INF, INF)
	var maxv := Vector2(-INF, -INF)
	for i in range(route_x.size()):
		var tx := int(route_x[i])
		var ty := int(route_y[i])
		var wp := Vector2.ZERO
		if is_instance_valid(tilemap_ref):
			wp = tilemap_ref.map_to_local(Vector2i(tx, ty))
		else:
			var cs := _get_cell_size()
			wp = Vector2(tx * cs.x, ty * cs.y)
		minv.x = min(minv.x, wp.x)
		minv.y = min(minv.y, wp.y)
		maxv.x = max(maxv.x, wp.x)
		maxv.y = max(maxv.y, wp.y)
	if minv.x == INF:
		return Rect2()
	return Rect2(minv, maxv - minv)

# Estimate the CONTAIN fit zoom a world_rect would resolve to in the non-occluded viewport.
# Mirrors the zoom math in smooth_fit_world_rect so route-label padding can be sized in world units
# before the real fit runs. Floored at min_camera_zoom_level to match that function's zoom-out cap.
func _estimate_fit_zoom(world_rect: Rect2, margin: float) -> float:
	var viewport_px: Vector2 = map_viewport_rect.size
	if is_instance_valid(sub_viewport_node):
		viewport_px = Vector2(sub_viewport_node.size)
	if viewport_px.x <= 0.0 or viewport_px.y <= 0.0:
		viewport_px = get_viewport().get_visible_rect().size
	if viewport_px.x <= 0.0 or viewport_px.y <= 0.0:
		return min_camera_zoom_level
	var visible_w_px: float = max(1.0, viewport_px.x - _overlay_occlusion_px_x)
	var visible_h_px: float = max(1.0, viewport_px.y - _overlay_occlusion_px_y)
	var rect_w: float = max(1.0, world_rect.size.x)
	var rect_h: float = max(1.0, world_rect.size.y)
	var z: float = min(visible_w_px / rect_w, visible_h_px / rect_h) * clamp(margin, 0.5, 1.0)
	return maxf(z, min_camera_zoom_level)

# occ_x_override / occ_y_override: pass >= 0 to clamp against a hypothetical overlay occlusion
# instead of the live one. Used so a menu *close* can clamp its focus target against the FINAL
# (occlusion == 0) bounds rather than the current extended bounds, which prevents the tween from
# aiming into the off-map strip and snapping back when the menu finishes retracting.
func _get_clamped_camera_pos_for_zoom(pos: Vector2, zoom_val: float, occ_x_override: float = -1.0, occ_y_override: float = -1.0) -> Vector2:
	if not is_instance_valid(camera_node):
		return pos
	var occ_px_x: float = occ_x_override if occ_x_override >= 0.0 else _overlay_occlusion_px_x
	var occ_px_y: float = occ_y_override if occ_y_override >= 0.0 else _overlay_occlusion_px_y
	var cell_size = _get_cell_size()
	var map_width = map_size.x * cell_size.x
	var map_height = map_size.y * cell_size.y
	var map_origin: Vector2 = Vector2.ZERO
	if is_instance_valid(tilemap_ref):
		map_origin = tilemap_ref.position

	var current_viewport_px: Vector2 = map_viewport_rect.size
	if is_instance_valid(sub_viewport_node):
		current_viewport_px = Vector2(sub_viewport_node.size)
	var viewport_size = current_viewport_px
	if _menu_open and loose_pan_when_menu_open and _full_viewport_size != Vector2.ZERO:
		viewport_size = _full_viewport_size

	var zoom: float = maxf(zoom_val, 0.0001)
	var full_world_w = viewport_size.x / zoom
	var full_world_h = viewport_size.y / zoom
	var half_full_w = full_world_w * 0.5
	var half_full_h = full_world_h * 0.5

	var occlusion_world_w: float = occ_px_x / zoom
	var occlusion_world_h: float = occ_px_y / zoom

	var min_x = map_origin.x + half_full_w
	var max_x = map_origin.x + map_width - half_full_w + occlusion_world_w
	if max_x < min_x:
		max_x = min_x
	var min_y = map_origin.y + half_full_h
	var max_y = map_origin.y + map_height - half_full_h + occlusion_world_h
	if max_y < min_y:
		max_y = min_y

	if allow_map_edge_exposure:
		var margin_factor := 0.25
		min_x = lerp(min_x, 0.0, margin_factor)
		max_x = lerp(max_x, map_width, margin_factor)
		min_y = lerp(min_y, 0.0, margin_factor)
		max_y = lerp(max_y, map_height, margin_factor)

	var adjusted_world_w = max(0.0, viewport_size.x - occ_px_x) / zoom
	var adjusted_world_h = max(0.0, viewport_size.y - occ_px_y) / zoom
	if map_width <= adjusted_world_w:
		min_x = map_origin.x + map_width * 0.5 + occlusion_world_w * 0.5; max_x = min_x
	if map_height <= adjusted_world_h:
		min_y = map_origin.y + map_height * 0.5 + occlusion_world_h * 0.5; max_y = min_y

	return Vector2(clamp(pos.x, min_x, max_x), clamp(pos.y, min_y, max_y))

func _get_fit_center_for_world_rect_and_zoom(world_rect: Rect2, zoom_val: float, target_focus_point: Vector2 = Vector2.INF) -> Vector2:
	# Chooses a camera center that keeps world_rect visible in the non-occluded area.
	# Priority logic:
	# - If the full route fits at this zoom: center on the route rect.
	# - If zoom is capped and route is clipped: lerp toward target_focus_point (destination).
	# - Final safety clamp always prevents background exposure.
	var current_viewport_px: Vector2 = map_viewport_rect.size
	if is_instance_valid(sub_viewport_node):
		current_viewport_px = Vector2(sub_viewport_node.size)
	var viewport_size: Vector2 = current_viewport_px
	if _menu_open and loose_pan_when_menu_open and _full_viewport_size != Vector2.ZERO:
		viewport_size = _full_viewport_size

	var zoom: float = maxf(zoom_val, 0.0001)
	var full_world_w: float = viewport_size.x / zoom
	var full_world_h: float = viewport_size.y / zoom
	var half_full_w: float = full_world_w * 0.5
	var half_full_h: float = full_world_h * 0.5
	var occlusion_world_w: float = _overlay_occlusion_px_x / zoom
	var occlusion_world_h: float = _overlay_occlusion_px_y / zoom
	# Non-occluded visible area in world units.
	var visible_world_w: float = max(0.0, viewport_size.x - _overlay_occlusion_px_x) / zoom
	var visible_world_h: float = max(0.0, viewport_size.y - _overlay_occlusion_px_y) / zoom

	var map_origin: Vector2 = Vector2.ZERO
	if is_instance_valid(tilemap_ref):
		map_origin = tilemap_ref.position
	var cell_size: Vector2 = _get_cell_size()
	var map_height: float = float(map_size.y) * cell_size.y

	var rect_left: float = world_rect.position.x
	var rect_top: float = world_rect.position.y
	var rect_right: float = world_rect.position.x + world_rect.size.x
	var rect_bottom: float = world_rect.position.y + world_rect.size.y
	var rect_w: float = world_rect.size.x
	var rect_h: float = world_rect.size.y

	# Start at the route rect center.
	var desired: Vector2 = world_rect.get_center()

	# When a focus point exists (e.g. journey destination), blend toward it based on overflow.
	# If the entire route fits on screen we keep the center; if heavily clipped we move to dest.
	# Use 90% of visible area as the threshold so there's a 10% buffer of breathing room,
	# keeping the convoy panel and route line comfortably inside view.
	if target_focus_point != Vector2.INF:
		var buffered_w: float = visible_world_w * 0.9
		var buffered_h: float = visible_world_h * 0.9
		var overflow_w: float = 0.0
		var overflow_h: float = 0.0
		if buffered_w > 0.0:
			overflow_w = clampf((rect_w - buffered_w) / buffered_w, 0.0, 1.0)
		if buffered_h > 0.0:
			overflow_h = clampf((rect_h - buffered_h) / buffered_h, 0.0, 1.0)
		var blend: float = maxf(overflow_w, overflow_h)
		desired = desired.lerp(target_focus_point, blend)

	# Occlusion bias: shift desired so the non-occluded visible area is centered on the route.
	if _overlay_occlusion_px_x > 0.0:
		desired.x += occlusion_world_w * 0.5
	if _overlay_occlusion_px_y > 0.0:
		desired.y += occlusion_world_h * 0.5

	# === Y-axis clamping ===
	# Only lock to map vertical center when there is NO destination focus active.
	# (When there IS a destination focus, the camera must NOT snap to map center —
	# that was the root cause of the "jumps to top of map" bug.)
	if target_focus_point == Vector2.INF and map_height > 0.0 and map_height <= full_world_h:
		# Map fits vertically; center it so off-map is split evenly above/below.
		desired.y = map_origin.y + map_height * 0.5
	else:
		# Clamp vertically so the route stays inside the non-occluded visible area.
		var min_center_y: float = rect_bottom - half_full_h + occlusion_world_h
		var max_center_y: float = rect_top + half_full_h
		if min_center_y <= max_center_y:
			desired.y = clampf(desired.y, min_center_y, max_center_y)
		# If min > max (route taller than screen), do NOT flip-clamp (that causes jumps).
		# The final safety clamp below keeps us inside the map.

	# === X-axis clamping ===
	var min_center_x: float = rect_right - half_full_w + occlusion_world_w
	var max_center_x: float = rect_left + half_full_w
	if min_center_x <= max_center_x:
		desired.x = clampf(desired.x, min_center_x, max_center_x)
	# Route wider than screen: do not flip-clamp; final safety clamp handles it.

	# FINAL SAFETY CLAMP: Ensures camera stays inside map (no background exposure).
	return _get_clamped_camera_pos_for_zoom(desired, zoom)


func _apply_fit_zoom_step(zoom_level: float, world_rect: Rect2, target_focus_point: Vector2 = Vector2.INF) -> void:
	if not is_instance_valid(camera_node):
		return
	var z: float = maxf(zoom_level, 0.0001)
	camera_node.zoom = Vector2(z, z)
	# If menu is open and we freeze zoom for bounds, keep the reference in sync.
	if _menu_open and freeze_zoom_for_menu_bounds:
		_menu_open_reference_zoom = z
	camera_node.position = _get_fit_center_for_world_rect_and_zoom(world_rect, z, target_focus_point)

func _on_focus_tween_finished() -> void:
	# For fit tweens, don't snap back to map clamp, since that can hide long routes
	# behind the menu occlusion near map edges.
	if not _active_focus_tween_is_fit:
		_clamp_camera_position()
	_active_focus_tween = null
	_active_focus_tween_is_fit = false
	emit_signal("focus_tween_finished")
	if _debug_menu_focus:
		_dbg("tween_finished", {"final_pos": (camera_node.position if is_instance_valid(camera_node) else Vector2.ZERO), "expected_target": _last_tween_target})

# --- New: Helper to get a clamped camera position without modifying state ---
func _get_clamped_camera_pos(pos: Vector2) -> Vector2:
	if not is_instance_valid(camera_node):
		return pos

	var cell_size = _get_cell_size()
	var map_width = map_size.x * cell_size.x
	var map_height = map_size.y * cell_size.y
	var map_origin: Vector2 = Vector2.ZERO
	if is_instance_valid(tilemap_ref):
		map_origin = tilemap_ref.position

	var current_viewport_px: Vector2 = map_viewport_rect.size
	if is_instance_valid(sub_viewport_node):
		current_viewport_px = Vector2(sub_viewport_node.size)
	
	var effective_viewport_size = current_viewport_px
	if _menu_open and loose_pan_when_menu_open and _full_viewport_size != Vector2.ZERO:
		effective_viewport_size = _full_viewport_size
	
	var viewport_size = effective_viewport_size
	var zoom = camera_node.zoom.x
	if _menu_open and freeze_zoom_for_menu_bounds:
		zoom = _menu_open_reference_zoom
	
	var full_world_w = viewport_size.x / max(zoom, 0.0001)
	var full_world_h = viewport_size.y / max(zoom, 0.0001)
	var half_full_w = full_world_w * 0.5
	var half_full_h = full_world_h * 0.5

	var occlusion_world_w: float = _overlay_occlusion_px_x / max(zoom, 0.0001)
	var occlusion_world_h: float = _overlay_occlusion_px_y / max(zoom, 0.0001)

	var min_x = map_origin.x + half_full_w
	var max_x = map_origin.x + map_width - half_full_w + occlusion_world_w
	if max_x < min_x:
		max_x = min_x
	var min_y = map_origin.y + half_full_h
	var max_y = map_origin.y + map_height - half_full_h + occlusion_world_h
	if max_y < min_y:
		max_y = min_y

	if allow_map_edge_exposure:
		var margin_factor := 0.25
		min_x = lerp(min_x, 0.0, margin_factor)
		max_x = lerp(max_x, map_width, margin_factor)
		min_y = lerp(min_y, 0.0, margin_factor)
		max_y = lerp(max_y, map_height, margin_factor)

	# If the map is smaller than the visible non-occluded world area, center the camera
	var adjusted_world_w = max(0.0, viewport_size.x - _overlay_occlusion_px_x) / max(zoom, 0.0001)
	var adjusted_world_h = max(0.0, viewport_size.y - _overlay_occlusion_px_y) / max(zoom, 0.0001)
	
	if map_width <= adjusted_world_w:
		min_x = map_origin.x + map_width * 0.5 + occlusion_world_w * 0.5
		max_x = min_x
	if map_height <= adjusted_world_h:
		min_y = map_origin.y + map_height * 0.5 + occlusion_world_h * 0.5
		max_y = min_y

	return Vector2(clamp(pos.x, min_x, max_x), clamp(pos.y, min_y, max_y))

# --- Overlay occlusion width setter (for sliding menu overlay) ---
func set_overlay_occlusion(px_x: float, px_y: float) -> void:
	var new_x: float = clamp(px_x, 0.0, map_viewport_rect.size.x)
	var new_y: float = clamp(px_y, 0.0, map_viewport_rect.size.y)
	# A SHRINKING overlay (menu closing) tightens the pan bounds: the off-map area that was hidden
	# under the menu becomes visible, so the camera can suddenly sit outside bounds. We must enforce
	# the clamp every frame through the close transition — even while the convoy-recenter focus tween
	# is running — otherwise the map renders off-edge until the tween's end-clamp snaps it back.
	# A GROWING/equal overlay (menu opening) loosens bounds, so we keep the old no-snap behavior and
	# let the focus tween animate the camera without a hard clamp fighting it at open.
	var occlusion_shrinking: bool = (new_x < _overlay_occlusion_px_x - 0.01) or (new_y < _overlay_occlusion_px_y - 0.01)
	_overlay_occlusion_px_x = new_x
	_overlay_occlusion_px_y = new_y
	_update_camera_limits()
	var tween_active: bool = _active_focus_tween != null and _active_focus_tween.is_valid()
	# Avoid immediate clamp reposition (snap) if a smooth focus tween is in progress, UNLESS the
	# overlay is shrinking (close) — then the clamp is a moving ceiling the camera follows in smoothly.
	if (not tween_active) or occlusion_shrinking:
		_clamp_camera_position()
	if _debug_menu_focus:
		_dbg("occlusion_set", {
			"occlusion_px_x": _overlay_occlusion_px_x,
			"occlusion_px_y": _overlay_occlusion_px_y,
			"viewport_px": map_viewport_rect.size,
			"active_tween": (_active_focus_tween and _active_focus_tween.is_valid()),
			"cam_pos": (camera_node.position if is_instance_valid(camera_node) else Vector2.ZERO)
		})
	_update_debug_overlay()

func set_overlay_occlusion_width(px: float) -> void:
	set_overlay_occlusion(px, _overlay_occlusion_px_y)

func set_overlay_occlusion_height(px: float) -> void:
	set_overlay_occlusion(_overlay_occlusion_px_x, px)

# --- Helpers ---
func _get_cell_size() -> Vector2:
	if is_instance_valid(tilemap_ref) and is_instance_valid(tilemap_ref.tile_set):
		return Vector2(tilemap_ref.tile_set.tile_size)
	# Sensible fallback
	return Vector2(16, 16)

# TEMP DIAGNOSTIC: logs which code path is driving the camera, with the caller chain.
# Remove once the "glued to top / y~676 pull" source is identified.
@export var trace_focus_calls: bool = true
func _trace_focus(tag: String, target: Variant = null):
	if not trace_focus_calls:
		return
	var chain := ""
	for frame in get_stack():
		chain += str(frame.get("source", "?")).get_file() + ":" + str(frame.get("function", "?")) + ":" + str(frame.get("line", -1)) + " <- "
	print("[FOCUS_TRACE] ", tag, " target=", target,
		" cam_y=", (camera_node.position.y if is_instance_valid(camera_node) else -1.0),
		" zoom=", (camera_node.zoom.x if is_instance_valid(camera_node) else -1.0),
		"\n    callers: ", chain)

func _dbg(tag: String, data: Dictionary = {}):
	if debug_logging:
		# Shallow stringify to avoid overwhelming logs
		var summary := ""
		for k in data.keys():
			summary += str(k) + ":" + str(data[k]) + " "
		print("[MCC] ", tag, " ", summary)
		_update_debug_overlay()

func _create_debug_overlay():
	if not is_instance_valid(get_viewport()):
		return
	if _debug_overlay_label:
		return
	_debug_overlay_label = Label.new()
	_debug_overlay_label.name = "CameraDebugOverlay"
	_debug_overlay_label.modulate = Color(0.9, 0.95, 1.0, 0.85)
	_debug_overlay_label.theme_type_variation = "Monospace"
	_debug_overlay_label.position = Vector2(12, 12)
	# Clamp z_index to a valid CanvasItem range and add deferred to avoid tree-lock errors
	_debug_overlay_label.z_index = 200
	get_viewport().call_deferred("add_child", _debug_overlay_label)
	_update_debug_overlay()

func _update_debug_overlay():
	if not _debug_menu_focus:
		return
	if not _debug_overlay_label:
		return
	if not is_instance_valid(camera_node):
		_debug_overlay_label.text = "<no camera>"
		return
	var zoom = camera_node.zoom.x
	var occlusion_x = _overlay_occlusion_px_x
	var occlusion_y = _overlay_occlusion_px_y
	var cam_pos = camera_node.position
	var target = _last_tween_target
	_debug_overlay_label.text = "Zoom:" + str(zoom) + "\nOccPxX:" + str(occlusion_x) + "\nOccPxY:" + str(occlusion_y) + "\nCam:" + str(cam_pos) + "\nTweenTarget:" + str(target)
