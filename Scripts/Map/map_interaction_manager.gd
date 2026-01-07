extends Node

@export var debug_logging: bool = false

# --- Signals ---
# Emitted when the hovered map element or UI panel changes.
signal hover_changed(new_hover_info: Dictionary)

# Emitted when the set of selected convoy IDs changes.
signal selection_changed(selected_ids: Array) # Array of convoy_id_str

# Emitted when a convoy panel drag starts.
signal panel_drag_started(convoy_id_str: String, panel_node: Panel)

# Emitted when a convoy panel is being dragged.
# new_panel_local_position is the panel's position relative to its parent (convoy_label_container in UIManager)
signal panel_drag_updated(convoy_id_str: String, new_panel_local_position: Vector2)

# Emitted when a convoy panel drag ends.
# final_panel_local_position is the panel's final position relative to its parent.
signal panel_drag_ended(convoy_id_str: String, final_panel_local_position: Vector2)
# THIS SIGNAL IS NOW EMITTED BY MapCameraController
# It is kept here for compatibility if other scripts listen to MIM for it.
# Emitted when the camera zoom level has changed.
signal camera_zoom_changed(new_zoom_level: float)

# Emitted when a convoy icon is clicked/tapped, requesting its menu.
signal convoy_menu_requested(convoy_data: Dictionary)

# --- Node References (to be set by main.gd via initialize method) ---
var map_display: TileMapLayer = null
var ui_manager: Node = null # This will be the UIManagerNode instance
var _sub_viewport: SubViewport = null
var _map_texture_rect: TextureRect = null

# --- Data Snapshots ---
# Phase B: MapInteractionManager reads snapshots from GameStore.
# These are kept as local caches for convenience/perf.
var all_convoy_data: Array = []
var all_settlement_data: Array = []
var map_tiles: Array = []

var _store: Node = null
var camera: Camera2D = null
var map_container_for_bounds: TextureRect = null # Changed to TextureRect, will hold map_display
# Ensure MapCameraController node is a child of MapInteractionManager in the scene
@onready var map_camera_controller: MapCameraController = $MapCameraController



enum ControlScheme { MOUSE_AND_KEYBOARD, TOUCH }
@export_group("Control Scheme")
@export var active_control_scheme: ControlScheme = ControlScheme.MOUSE_AND_KEYBOARD

@export_group("Interaction Thresholds")
## The squared radius (in pixels on the map texture) for detecting hover over convoys. (e.g., 25*25 = 625).
@export var convoy_hover_radius_on_texture_sq: float = 1600.0 # 40*40, was 25*25
## The squared radius (in pixels on the map texture) for detecting hover over settlements. (e.g., 20*20 = 400).
@export var settlement_hover_radius_on_texture_sq: float = 900.0 # 30*30, was 20*20

@export_group("UI Interaction")
## Padding from the viewport edges (in pixels) used to clamp draggable UI panels.
@export var label_map_edge_padding: float = 5.0 

# Camera control exports (min_zoom, max_zoom, sensitivity, etc.) are now in MapCameraController.gd


var _pan_touch_index: int = -1 # For tracking which finger started a touch pan

var _hover_update_timer: float = 0.0
const HOVER_UPDATE_INTERVAL: float = 0.05 # Time in seconds (e.g., 0.05 for 20 FPS hover updates)
var _last_mouse_motion_event: InputEventMouseMotion = null # Store the latest mouse motion event

# --- Internal State Variables (will be moved from main.gd) ---
var _current_hover_info: Dictionary = {}
var _convoy_label_user_positions: Dictionary = {} # { 'convoy_id_str': Vector2(local_x, local_y) }
var _selected_convoy_ids: Array[String] = [] # Array of convoy_id_str
var _dragging_panel_node: Panel = null # The actual Panel node being dragged
var _drag_offset: Vector2 = Vector2.ZERO # Offset from panel origin to mouse click during drag
var _dragged_convoy_id_actual_str: String = "" # The ID of the convoy whose panel is being dragged
var _current_drag_clamp_rect: Rect2 # Global screen coordinates for clamping the dragged panel
var _current_map_screen_rect: Rect2 # The actual screen rect the map is displayed in



func _ready():
	# The MapInteractionManager might not need to process input itself if main.gd forwards it.
	set_process(true) # Enable _process for the hover timer
	if is_instance_valid(get_viewport()):
		_current_map_screen_rect = get_viewport().get_visible_rect() # Initialize
	else:
		_current_map_screen_rect = Rect2(0,0,1,1) # Fallback, should be updated by main.gd


func initialize(
		p_tilemap: TileMapLayer,
		p_ui_manager: Node,
		p_all_convoy_data: Array,
		p_all_settlement_data: Array,
		p_map_tiles: Array,
		p_camera: Camera2D,
		p_sub_viewport: SubViewport,
		p_initial_selected_ids: Array[String],
		p_initial_user_positions: Dictionary
	):
	# New: Pass TileMapLayer node for bounds
	map_display = p_tilemap
	ui_manager = p_ui_manager
	# Prefer snapshots from GameStore; fall back to passed arrays for legacy scenes.
	_refresh_snapshots_from_store_or_fallback(p_all_convoy_data, p_all_settlement_data, p_map_tiles)
	_connect_store_signals_if_available()
	_selected_convoy_ids = p_initial_selected_ids.duplicate(true)
	_convoy_label_user_positions = p_initial_user_positions.duplicate(true)
	camera = p_camera
	_sub_viewport = p_sub_viewport
	# Try to get the TextureRect that displays the SubViewport
	_map_texture_rect = get_node_or_null("../MapContainer/MapDisplay")

	if not is_instance_valid(map_display):
		printerr("MapInteractionManager: TileMap is invalid after init!")
	if not is_instance_valid(ui_manager):
		printerr("MapInteractionManager: ui_manager is invalid after init!")
	if not is_instance_valid(camera):
		printerr("MapInteractionManager: camera is invalid after init!")

	# TileMap is now used for bounds and sizing; remove texture-based sizing logic.
	if is_instance_valid(camera):
		if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("initialize"):
			map_camera_controller.initialize(camera, map_display, p_sub_viewport)
			if map_camera_controller.has_signal("camera_zoom_changed"):
				map_camera_controller.camera_zoom_changed.connect(_on_map_camera_controller_zoom_changed)
		else:
			printerr("MapInteractionManager: MapCameraController node or its initialize method is invalid.")
		camera.drag_horizontal_enabled = true
		camera.drag_left_margin = 0.0
		camera.drag_right_margin = 0.0
		camera.drag_top_margin = 0.0
		camera.drag_vertical_enabled = true
		camera.drag_left_margin = 0.0
		camera.drag_right_margin = 0.0
		camera.drag_top_margin = 0.0
		camera.drag_bottom_margin = 0.0
		camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		camera.set("smoothing_enabled", true)
		camera.set("smoothing_speed", 5.0)
	else:
		printerr("MapInteractionManager: Camera node is invalid in initialize.")

func _on_map_camera_controller_zoom_changed(new_zoom_level: float) -> void:
	# This function is called when the camera zoom changes. You can add logic here if needed.
	# For now, just emit the signal for compatibility.
	emit_signal("camera_zoom_changed", new_zoom_level)
	if not debug_logging:
		return
	# Diagnostics (gated)
	var map_display_vis: Variant = "N/A"
	if is_instance_valid(map_display) and map_display.has_method("is_visible_in_tree"):
		map_display_vis = map_display.is_visible_in_tree()
	print("[MIM][VIS] map_display visible:", map_display_vis)
		
# Call this to allow or disallow the camera to move outside map bounds (e.g. for journey preview)
func set_camera_loose_mode(is_loose: bool):
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("set_allow_camera_outside_bounds"):
		map_camera_controller.set_allow_camera_outside_bounds(is_loose)

func update_data_references(p_all_convoy_data: Array, p_all_settlement_data: Array, p_map_tiles: Array):
	"""Deprecated (Phase B): MapInteractionManager reads snapshots from GameStore.
	Kept for compatibility with legacy callers.
	"""
	_refresh_snapshots_from_store_or_fallback(p_all_convoy_data, p_all_settlement_data, p_map_tiles)

func _physics_process(_delta: float):
	pass # Camera clamping is now handled by MapCameraController's _physics_process


# -----------------------------------------------------------------------------
# NEW PUBLIC INPUT API
# This is the single entry point for all map-related input, called by MainScreen.gd
# -----------------------------------------------------------------------------
func handle_map_input(event: InputEvent):
	if not is_instance_valid(map_display) or not is_instance_valid(camera):
		return

	# 1. Always update _last_mouse_motion_event for hover detection in _process()
	if event is InputEventMouseMotion:
		_last_mouse_motion_event = event
		# Also handle panel dragging
		if _handle_panel_drag_motion_only(event):
			get_viewport().set_input_as_handled()
			return # Consumed by panel drag

	# 2. Handle Left Mouse Button interactions (clicks, panel drag start/end)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# We pass the camera reference because it's needed to convert screen to world coordinates
		if _handle_lmb_interactions(event, camera):
			get_viewport().set_input_as_handled()
			return # Consumed by LMB interaction

	# Note: Hover is handled separately in _process, not here.
	# Note: Camera movement (panning, zooming) is handled by MainScreen.gd before this function is called


# -----------------------------------------------------------------------------
# INTERNAL HELPERS
# These functions are now called by the public API above.
# -----------------------------------------------------------------------------

func get_current_camera_zoom() -> float:
	if is_instance_valid(camera):
		if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("get_current_zoom"):
			return map_camera_controller.get_current_zoom()
	return 1.0 # Fallback


func _process(delta: float):
	# Throttled hover detection
	_hover_update_timer += delta
	if _hover_update_timer >= HOVER_UPDATE_INTERVAL:
		_hover_update_timer = 0.0 # Reset timer
		if is_instance_valid(_last_mouse_motion_event) and \
		   active_control_scheme == ControlScheme.MOUSE_AND_KEYBOARD and \
		   not is_instance_valid(_dragging_panel_node): # Don't do hover if dragging panel
			_perform_hover_detection_only(_last_mouse_motion_event)
		_last_mouse_motion_event = null # Clear after processing or if conditions not met


func _handle_mouse_camera_controls(_event: InputEvent): # Was part of _handle_mouse_input
	# --- DEBUG: Log some events reaching _handle_mouse_input ---
	# ALL LOGIC MOVED TO MapCameraController.handle_input()
	pass


func _handle_touch_input(event: InputEvent):
	# Touch Panning (Single finger drag)
	if event is InputEventScreenTouch:
		if event.pressed:
			# Only track the touch index for potential tap, not for panning.
			# Panning is handled by InputEventPanGesture.
			if _pan_touch_index == -1:
				_pan_touch_index = event.index
				# _is_camera_panning = false # Ensure this is not set for single touch
				get_viewport().set_input_as_handled()
		else: # released
			if event.index == _pan_touch_index: # If the finger that started the pan is released
				_pan_touch_index = -1
				# _is_camera_panning = false # Ensure this is not set for single touch
				get_viewport().set_input_as_handled()
				# Check if it was a "tap" (short press, little movement)
				# For simplicity, we'll assume any touch release not part of a PanGesture could be a tap.
				_handle_tap_interaction(event.position) # Handle tap for selection
		return # Consumed

	if event is InputEventScreenDrag and event.index == _pan_touch_index:
		# Single finger drag is no longer used for camera panning.
		# It could be used for other interactions in the future (e.g., dragging map items if implemented).
		# For now, we can let it pass or consume it if no other single-drag interaction is planned.
		# get_viewport().set_input_as_handled() # Optionally consume if no other use
		return # Consumed

	# Touch Zooming (Pinch Gesture)
	# This is now handled globally at the start of _unhandled_input.
	# If it were to remain here, the logic would be:
	# _zoom_camera_at_screen_pos(1.0 / event.factor, event.position)

	# Touch Taps for UI interaction (panel drag start/end, map element click)
	# This is simplified. Robust touch UI needs careful state management.
	# For example, detecting a drag start on a panel with touch.
	# The _handle_tap_interaction above handles map element clicks.

func _handle_tap_interaction(_position: Vector2) -> void:
	# Stub for touch tap interaction. Add selection or menu logic here if needed.
	pass

# Add boolean return type
func _handle_panel_drag_motion_only(event: InputEventMouseMotion) -> bool:
	"""Handles ONLY the panel dragging motion part. Called directly from _unhandled_input."""
	if is_instance_valid(_dragging_panel_node) and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		# Calculate the new target global position for the panel's origin
		var new_global_panel_pos: Vector2 = event.global_position + _drag_offset

		var panel_actual_size_for_clamp = _dragging_panel_node.size
		if panel_actual_size_for_clamp.x <= 0 or panel_actual_size_for_clamp.y <= 0:
			panel_actual_size_for_clamp = _dragging_panel_node.get_minimum_size()

		# Clamp the new global position using the pre-calculated _current_drag_clamp_rect
		# Ensure panel_actual_size_for_clamp is also valid before using in subtraction
		if _current_drag_clamp_rect.size.x > 0 and _current_drag_clamp_rect.size.y > 0 and panel_actual_size_for_clamp.x > 0 and panel_actual_size_for_clamp.y > 0:
			new_global_panel_pos.x = clamp(
				new_global_panel_pos.x,
				_current_drag_clamp_rect.position.x,
				_current_drag_clamp_rect.position.x + _current_drag_clamp_rect.size.x - panel_actual_size_for_clamp.x
			)
			new_global_panel_pos.y = clamp(
				new_global_panel_pos.y,
				_current_drag_clamp_rect.position.y,
				_current_drag_clamp_rect.position.y + _current_drag_clamp_rect.size.y - panel_actual_size_for_clamp.y
			)

		_dragging_panel_node.global_position = new_global_panel_pos
		
		# Emit signal with the new *local* position of the panel
		if is_instance_valid(_dragging_panel_node.get_parent()):
			var new_local_pos = _dragging_panel_node.get_parent().to_local(new_global_panel_pos)
			emit_signal("panel_drag_updated", _dragged_convoy_id_actual_str, new_local_pos)
		get_viewport().set_input_as_handled()
		return true # Indicate event was handled
	# If not dragging a panel, this function does nothing further. Hover is separate.
	return false # Indicate event was not handled


func _perform_hover_detection_only(event: InputEventMouseMotion):
	"""Performs ONLY hover detection. Called from _process via throttle."""
	# Ensure we are not dragging a panel when performing hover detection
	if not (is_instance_valid(camera) and is_instance_valid(map_display)):
		return

	# Convert mouse position (main viewport) -> SubViewport screen -> SubViewport world
	var new_hover_info: Dictionary = {}
	var _found_hover_element_unused: bool = false

	if not is_instance_valid(_sub_viewport) or not is_instance_valid(_map_texture_rect):
		# Fallback to previous behavior (may be incorrect if SubViewport is used)
		var mouse_world_pos_fallback = camera.get_canvas_transform().affine_inverse() * event.position
		return _perform_hover_tests_at_world(mouse_world_pos_fallback)

	var display_rect: Rect2 = _map_texture_rect.get_global_rect()
	if not display_rect.has_point(event.global_position):
		# Outside the map area -> clear hover if needed
		if self._current_hover_info != new_hover_info:
			self._current_hover_info = new_hover_info
			emit_signal("hover_changed", self._current_hover_info)
		return

	# Position within the TextureRect (0..rect.size)
	var local_in_display: Vector2 = event.global_position - display_rect.position
	# Map to SubViewport pixel space
	var sub_size: Vector2i = _sub_viewport.size
	var sub_screen: Vector2 = Vector2(
		(local_in_display.x / max(1.0, display_rect.size.x)) * float(sub_size.x),
		(local_in_display.y / max(1.0, display_rect.size.y)) * float(sub_size.y)
	)
	# Convert SubViewport screen -> SubViewport world
	var mouse_world_pos: Vector2 = camera.get_canvas_transform().affine_inverse() * sub_screen

	_perform_hover_tests_at_world(mouse_world_pos)

func _perform_hover_tests_at_world(mouse_world_pos: Vector2):
	var new_hover_info: Dictionary = {}
	var _found_hover_element: bool = false

	# Get map bounds from TileMap
	if not (is_instance_valid(map_display) and is_instance_valid(map_display.tile_set)):
		return
	var tile_size = map_display.tile_set.tile_size
	var actual_tile_width_on_world: float = tile_size.x
	var actual_tile_height_on_world: float = tile_size.y

	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		if self._current_hover_info != new_hover_info: # If it changed to empty
			self._current_hover_info = new_hover_info
			emit_signal("hover_changed", self._current_hover_info)
		return

	# 1. Check for Convoy Hover
	if not all_convoy_data.is_empty():
		for convoy_data_item in all_convoy_data:
			if not convoy_data_item is Dictionary: continue
			var convoy_map_x: float = convoy_data_item.get('x', -1.0)
			var convoy_map_y: float = convoy_data_item.get('y', -1.0)
			var convoy_id_val = convoy_data_item.get('convoy_id')
			if convoy_map_x >= 0.0 and convoy_map_y >= 0.0 and convoy_id_val != null:
				var _convoy_id_str = str(convoy_id_val)
				var convoy_center_world_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_world
				var convoy_center_world_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_world
				var dx = mouse_world_pos.x - convoy_center_world_x
				var dy = mouse_world_pos.y - convoy_center_world_y
				if (dx * dx) + (dy * dy) < convoy_hover_radius_on_texture_sq:
					new_hover_info = {'type': 'convoy', 'id': _convoy_id_str}
					_found_hover_element = true
					break

	# 2. Settlement Hover if none found
	if not _found_hover_element and not all_settlement_data.is_empty():
		var closest_settlement_dist_sq: float = settlement_hover_radius_on_texture_sq + 1.0
		var best_hovered_settlement_coords: Vector2i = Vector2i(-1, -1)
		for settlement_info_item in all_settlement_data:
			if not settlement_info_item is Dictionary: continue
			var settlement_tile_x: int = settlement_info_item.get('x', -1)
			var settlement_tile_y: int = settlement_info_item.get('y', -1)
			if settlement_tile_x >= 0 and settlement_tile_y >= 0:
				var settlement_center_world_x: float = (float(settlement_tile_x) + 0.5) * actual_tile_width_on_world
				var settlement_center_world_y: float = (float(settlement_tile_y) + 0.5) * actual_tile_height_on_world
				var dx_settlement = mouse_world_pos.x - settlement_center_world_x
				var dy_settlement = mouse_world_pos.y - settlement_center_world_y
				var distance_sq_settlement = (dx_settlement * dx_settlement) + (dy_settlement * dy_settlement)
				if distance_sq_settlement < settlement_hover_radius_on_texture_sq and distance_sq_settlement < closest_settlement_dist_sq:
					closest_settlement_dist_sq = distance_sq_settlement
					best_hovered_settlement_coords = Vector2i(settlement_tile_x, settlement_tile_y)
					_found_hover_element = true
		if _found_hover_element and best_hovered_settlement_coords.x != -1:
			new_hover_info = {'type': 'settlement', 'coords': best_hovered_settlement_coords}

	if new_hover_info != self._current_hover_info:
		self._current_hover_info = new_hover_info
		emit_signal("hover_changed", self._current_hover_info)


func _handle_lmb_interactions(event: InputEventMouseButton, p_camera: Camera2D) -> bool: # Was _handle_mouse_button_interactions
	"""Handles MOUSE_BUTTON_LEFT press/release for panel dragging and map element selection. Assumes event.button_index == MOUSE_BUTTON_LEFT."""
	if not (is_instance_valid(p_camera) and \
			is_instance_valid(map_display)):
		return false

	if event.pressed:
		# --- Check for Panel Drag Start ---
		var convoy_label_container_node: Node = null
		if is_instance_valid(ui_manager):
			convoy_label_container_node = ui_manager.get("convoy_label_container")
		if is_instance_valid(convoy_label_container_node):
			for i in range(convoy_label_container_node.get_child_count() - 1, -1, -1):
				var node = convoy_label_container_node.get_child(i)
				if node is Panel:
					var panel_node_candidate: Panel = node
					if not is_instance_valid(panel_node_candidate):
						continue

					var panel_effective_size = panel_node_candidate.size
					if panel_effective_size.x <= 0 or panel_effective_size.y <= 0:
						panel_effective_size = panel_node_candidate.get_minimum_size()
					var panel_rect_global = Rect2(panel_node_candidate.global_position, panel_effective_size)
					var hit_test_rect = panel_rect_global.grow(2.0)

					if hit_test_rect.has_point(event.global_position):
						var id_from_meta = panel_node_candidate.get_meta("convoy_id_str", "")
						if id_from_meta.is_empty(): id_from_meta = panel_node_candidate.name

						# Always emit convoy_menu_requested when a convoy panel is clicked
						var convoy_data_clicked = null
						for convoy_data_item in all_convoy_data:
							if convoy_data_item is Dictionary and str(convoy_data_item.get("convoy_id", "")) == id_from_meta:
								convoy_data_clicked = convoy_data_item
								break
						if convoy_data_clicked:
							emit_signal("convoy_menu_requested", convoy_data_clicked)
							return true # Convoy menu opened

						if _selected_convoy_ids.has(id_from_meta):
							_dragging_panel_node = panel_node_candidate
							_dragged_convoy_id_actual_str = id_from_meta
							var panel_current_global_pos_for_offset = panel_rect_global.position
							_drag_offset = panel_current_global_pos_for_offset - event.global_position
							var map_view = get_node_or_null("/root/Main/MainScreen/MainContainer/MainContent/MapView")
							var viewport_rect = _current_map_screen_rect # Use map's effective screen rect for clamping
							if is_instance_valid(map_view):
								viewport_rect = map_view.get_global_rect()
							_current_drag_clamp_rect = Rect2(
								viewport_rect.position.x + label_map_edge_padding,
								viewport_rect.position.y + label_map_edge_padding,
								viewport_rect.size.x - (2 * label_map_edge_padding),
								viewport_rect.size.y - (2 * label_map_edge_padding)
							)
							emit_signal("panel_drag_started", _dragged_convoy_id_actual_str, _dragging_panel_node)
							return true # Drag started
	# ...existing code...
	elif not event.pressed:
		# --- Check for Panel Drag End ---
		if is_instance_valid(_dragging_panel_node):
			# Calculate the final position of the dragged panel
			var final_panel_global_pos = _dragging_panel_node.global_position

			# Emit the panel_drag_ended signal with the final position
			if is_instance_valid(_dragging_panel_node.get_parent()):
				var final_panel_local_pos = _dragging_panel_node.get_parent().to_local(final_panel_global_pos)
				emit_signal("panel_drag_ended", _dragged_convoy_id_actual_str, final_panel_local_pos)

			_dragging_panel_node = null # Reset dragging panel
			return true # Drag ended
		else:
			# --- Handle Click on Convoy (if not dragging) ---
			var clicked_convoy_data = null
			var mouse_world_pos = camera.get_canvas_transform().affine_inverse() * event.position
			# Get tile size for world coordinate conversion
			if not (is_instance_valid(map_display) and is_instance_valid(map_display.tile_set)):
				return false
			var tile_size = map_display.tile_set.tile_size
			var actual_tile_width_on_world: float = tile_size.x
			var actual_tile_height_on_world: float = tile_size.y
			for convoy_data_item in all_convoy_data:
				if convoy_data_item is Dictionary:
					var convoy_map_x: float = convoy_data_item.get('x', -1.0)
					var convoy_map_y: float = convoy_data_item.get('y', -1.0)
					var convoy_id_val = convoy_data_item.get('convoy_id')
					if convoy_map_x >= 0.0 and convoy_map_y >= 0.0 and convoy_id_val != null:
						var _convoy_id_str2 = str(convoy_id_val)
						var convoy_center_world_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_world
						var convoy_center_world_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_world
						var dx = mouse_world_pos.x - convoy_center_world_x
						var dy = mouse_world_pos.y - convoy_center_world_y
						if (dx * dx) + (dy * dy) < convoy_hover_radius_on_texture_sq:
							clicked_convoy_data = convoy_data_item
							break

			if clicked_convoy_data != null:
				emit_signal("convoy_menu_requested", clicked_convoy_data)
				return true # Click on convoy handled
			# ...existing code...
	return false # Ensure all code paths return a value


func get_dragging_panel_node() -> Panel:
	return _dragging_panel_node


func get_dragged_convoy_id_str() -> String:
	return _dragged_convoy_id_actual_str


func get_convoy_label_user_positions() -> Dictionary:
	return _convoy_label_user_positions


func _get_store() -> Node:
	if not is_instance_valid(_store):
		_store = get_node_or_null("/root/GameStore")
	return _store


func _refresh_snapshots_from_store_or_fallback(p_convoys: Array, p_settlements: Array, p_tiles: Array) -> void:
	var store := _get_store()
	if is_instance_valid(store) and store.has_method("get_convoys") and store.has_method("get_settlements") and store.has_method("get_tiles"):
		all_convoy_data = store.get_convoys()
		all_settlement_data = store.get_settlements()
		map_tiles = store.get_tiles()
		return
	# Legacy fallback
	all_convoy_data = p_convoys if p_convoys != null else []
	all_settlement_data = p_settlements if p_settlements != null else []
	map_tiles = p_tiles if p_tiles != null else []


func _connect_store_signals_if_available() -> void:
	var store := _get_store()
	if not is_instance_valid(store):
		return
	if store.has_signal("map_changed") and not store.map_changed.is_connected(_on_store_map_changed):
		store.map_changed.connect(_on_store_map_changed)
	if store.has_signal("convoys_changed") and not store.convoys_changed.is_connected(_on_store_convoys_changed):
		store.convoys_changed.connect(_on_store_convoys_changed)


func _on_store_map_changed(tiles: Array, settlements: Array) -> void:
	map_tiles = tiles if tiles != null else []
	all_settlement_data = settlements if settlements != null else []


func _on_store_convoys_changed(convoys: Array) -> void:
	all_convoy_data = convoys if convoys != null else []
