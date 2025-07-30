extends Node

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

# --- Data References (to be set by main.gd via initialize method) ---
var all_convoy_data: Array = []
var all_settlement_data: Array = []
var map_tiles: Array = []
var camera: Camera2D = null
var map_container_for_bounds: TextureRect = null # Changed to TextureRect, will hold map_display
# Ensure MapCameraController node is a child of MapInteractionManager in the scene
@onready var map_camera_controller: MapCameraController = $MapCameraController



enum ControlScheme { MOUSE_AND_KEYBOARD, TOUCH }
@export_group("Control Scheme")
@export var active_control_scheme: ControlScheme = ControlScheme.MOUSE_AND_KEYBOARD

@export_group("Interaction Thresholds")
## The squared radius (in pixels on the map texture) for detecting hover over convoys. (e.g., 25*25 = 625).
@export var convoy_hover_radius_on_texture_sq: float = 625.0 
## The squared radius (in pixels on the map texture) for detecting hover over settlements. (e.g., 20*20 = 400).
@export var settlement_hover_radius_on_texture_sq: float = 400.0 

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
	# If it were to handle its own input (e.g., if it was a Control node covering the map),
	# you would set_process_input(true) or set_process_unhandled_input(true) here.
	# For now, we'll assume main.gd calls handle_input(event).
	set_process_input(true) # Changed from _unhandled_input
	set_process(true) # Enable _process for the hover timer
	if is_instance_valid(get_viewport()):
		_current_map_screen_rect = get_viewport().get_visible_rect() # Initialize
	else:
		_current_map_screen_rect = Rect2(0,0,1,1) # Fallback, should be updated by main.gd
	# --- DIAGNOSTICS: Print visibility state of all relevant map nodes ---
	var map_display_vis = map_display.visible if is_instance_valid(map_display) else "N/A"
	var camera_vis = camera.visible if is_instance_valid(camera) else "N/A"
	print("[VIS] MapInteractionManager: map_display visible:", map_display_vis)
	print("[VIS] MapInteractionManager: camera visible:", camera_vis)
	var parent = map_display.get_parent() if is_instance_valid(map_display) else null
	print("[VIS] MapInteractionManager: map_display parent visible:", parent.visible if is_instance_valid(parent) else "N/A")
	# Deep diagnostics for map_display (should be TerrainTileMap) and its tileset
	print("[DIAG] MapInteractionManager _ready: map_display is_instance_valid:", is_instance_valid(map_display))
	if is_instance_valid(map_display):
		print("[DIAG] map_display type:", typeof(map_display), " class:", map_display.get_class())
		print("[DIAG] map_display resource_path:", map_display.resource_path if map_display.has_method("resource_path") else "N/A")
		print("[DIAG] map_display.tile_set is_instance_valid:", is_instance_valid(map_display.tile_set))
		if is_instance_valid(map_display.tile_set):
			print("[DIAG] map_display.tile_set resource_path:", map_display.tile_set.resource_path if map_display.tile_set.has_method("resource_path") else "N/A")
			print("[DIAG] map_display.tile_set to_string:", str(map_display.tile_set))
			var ids = []
			if map_display.tile_set.has_method("get_tiles_ids"):
				ids = map_display.tile_set.get_tiles_ids()
			else:
				for i in range(100):
					if map_display.tile_set.has_method("has_tile") and map_display.tile_set.has_tile(i):
						ids.append(i)
			print("[DIAG] map_display.tile_set ids:", ids)
		else:
			print("[DIAG] map_display.tile_set is not valid!")
	else:
		print("[DIAG] map_display is not valid!")


func initialize(
		p_tilemap: TileMapLayer,
		p_ui_manager: Node,
		p_all_convoy_data: Array,
		p_all_settlement_data: Array,
		p_map_tiles: Array,
		p_camera: Camera2D,
		p_initial_selected_ids: Array[String],
		p_initial_user_positions: Dictionary
	):
	# New: Pass TileMapLayer node for bounds
	map_display = p_tilemap
	ui_manager = p_ui_manager
	all_convoy_data = p_all_convoy_data
	all_settlement_data = p_all_settlement_data
	map_tiles = p_map_tiles
	_selected_convoy_ids = p_initial_selected_ids.duplicate(true)
	_convoy_label_user_positions = p_initial_user_positions.duplicate(true)
	camera = p_camera

	if not is_instance_valid(map_display):
		printerr("MapInteractionManager: TileMap is invalid after init!")
	if not is_instance_valid(ui_manager):
		printerr("MapInteractionManager: ui_manager is invalid after init!")
	if not is_instance_valid(camera):
		printerr("MapInteractionManager: camera is invalid after init!")

	# TileMap is now used for bounds and sizing; remove texture-based sizing logic.
	if is_instance_valid(camera):
		if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("initialize"):
			map_camera_controller.initialize(camera, map_display, _current_map_screen_rect)
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
		
# Call this to allow or disallow the camera to move outside map bounds (e.g. for journey preview)
func set_camera_loose_mode(is_loose: bool):
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("set_allow_camera_outside_bounds"):
		map_camera_controller.set_allow_camera_outside_bounds(is_loose)

func set_current_map_screen_rect(rect: Rect2):
	_current_map_screen_rect = rect
	print("[MIM] set_current_map_screen_rect: updating camera controller with rect:", _current_map_screen_rect)
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("update_map_dimensions"):
		map_camera_controller.update_map_dimensions(_current_map_screen_rect)
	# The camera controller's _physics_process will handle clamping.

func update_data_references(p_all_convoy_data: Array, p_all_settlement_data: Array, p_map_tiles: Array):
	"""Called by main.gd when core data (convoys, settlements, map_tiles) is updated."""
	all_convoy_data = p_all_convoy_data
	all_settlement_data = p_all_settlement_data
	map_tiles = p_map_tiles

	# TileMap is now the source of truth for map size and bounds. No texture-based sizing.
	if is_instance_valid(map_display):
		if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("update_map_dimensions"):
			map_camera_controller.update_map_dimensions(_current_map_screen_rect)

	# print("MapInteractionManager: Data references updated.")

func _physics_process(delta: float):
	pass # Camera clamping is now handled by MapCameraController's _physics_process

func _input(event: InputEvent): # Renamed from _unhandled_input
	# Prevent handling input if a UI element is focused
	if get_viewport().gui_get_focus_owner() != null:
		return
	# --- DEBUG: Log some events reaching _unhandled_input ---
	# This can be very verbose, enable only when actively debugging input issues.
	# print("MIM _input RECEIVED EVENT --- Type: %s, Event: %s" % [event.get_class(), event]) # DEBUG: Performance intensive
	# print("MIM _input RECEIVED EVENT --- Type: %s, Event: %s" % [event.get_class(), event]) # DEBUG: Performance intensive
	if event is InputEventMouseButton and false: # Disabled debug print
		# print("MIM _input: MouseButton - button_index: %s, pressed: %s, shift_pressed: %s, global_pos: %s" % [event.button_index, event.pressed, event.is_shift_pressed(), event.global_position]) # DEBUG
		pass
		# print("MIM _input: MouseButton - button_index: %s, pressed: %s, shift_pressed: %s, global_pos: %s" % [event.button_index, event.pressed, event.is_shift_pressed(), event.global_position]) # DEBUG
		pass
	elif event is InputEventMouseMotion:
		# print("MIM _input: MouseMotion - global_pos: %s, relative: %s, button_mask: %s" % [event.global_position, event.relative, event.button_mask]) # DEBUG # Too verbose
		# print("MIM _input: MouseMotion - global_pos: %s, relative: %s, button_mask: %s" % [event.global_position, event.relative, event.button_mask]) # DEBUG # Too verbose
		pass
	elif event is InputEventPanGesture: # DEBUG: Log PanGesture details
		# print("MIM _unhandled_input: PanGesture - delta: %s, position: %s" % [event.delta, event.position]) # DEBUG
		pass
		# print("MIM _unhandled_input: PanGesture - delta: %s, position: %s" % [event.delta, event.position]) # DEBUG
		pass
	# --- END DEBUG ---

	if not is_instance_valid(map_display) or not is_instance_valid(camera):
		# print("MapInteractionManager: handle_input - Essential nodes not ready. Skipping.")
		# Ensure event is not spuriously consumed if essential nodes aren't ready
		# If you want to see if events are reaching here even when nodes aren't ready,
		# comment out the return below temporarily.
		return

	# 1. Always update _last_mouse_motion_event for hover if it's a mouse motion.
	#    This ensures hover detection in _process() gets the latest position.
	#    Crucially, we do *not* consume the event here just for hover.
	if event is InputEventMouseMotion and active_control_scheme == ControlScheme.MOUSE_AND_KEYBOARD:
		_last_mouse_motion_event = event

	# 2. Handle panel drag motion (which might consume the InputEventMouseMotion).
	#    This needs to be called for InputEventMouseMotion.
	#    _handle_panel_drag_motion_only checks internally if dragging.
	if event is InputEventMouseMotion: # Check if it's a mouse motion event
		if _handle_panel_drag_motion_only(event): # Now returns true if handled
			return # Consumed by panel drag motion

	# 3. Handle gestures (Magnify, Pan). These are distinct event types.
	# Also handle M&K camera controls here by passing to MapCameraController
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("handle_input"):
		if map_camera_controller.handle_input(event):
			# Event was handled by camera controller (e.g., MMB pan, wheel zoom, gestures)
			return 

	# If a camera control or panel drag motion consumed the event, subsequent logic for that event is skipped.
	# This check is no longer needed as the returns above cover consumed events.
	# if get_viewport().is_input_as_handled(): 
	# 	return

	# 4. Handle scheme-specific interactions (camera controls, clicks, taps).
	match active_control_scheme:
		ControlScheme.MOUSE_AND_KEYBOARD:
			# This function now consolidates camera controls (MMB pan, wheel zoom)
			# and primary interactions (LMB clicks for panel drag start/end, map clicks).
			# Camera controls are now handled by map_camera_controller.handle_input above.
			_handle_mk_scheme_interactions_non_camera(event) # Renamed, only non-camera M&K
		ControlScheme.TOUCH:
			_handle_touch_input(event)


func _handle_mk_scheme_interactions(event: InputEvent):
	# This function combines logic previously in _handle_mouse_input() and _handle_mouse_button_interactions.
	# Order matters: camera controls might take precedence over map clicks for the same button.
	
	# Camera Panning (Middle Mouse Button or Shift + Left Mouse Button) & Camera Zoom (Wheel)
	# This logic is taken from the original _handle_mouse_input
	# MOVED to map_camera_controller.handle_input(event)
	pass


func _handle_mk_scheme_interactions_non_camera(event: InputEvent):
	# This function handles M&K interactions *not* related to direct camera control.
	# Left Mouse Button interactions (panel drag start/end, map element clicks)
	# This logic is taken from the original _handle_mouse_button_interactions
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_lmb_interactions(event) # New sub-function for clarity


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
		   (not is_instance_valid(map_camera_controller) or (is_instance_valid(map_camera_controller) and not map_camera_controller.is_panning())) and \
		   not is_instance_valid(_dragging_panel_node): # Don't do hover if panning or dragging panel
			_perform_hover_detection_only(_last_mouse_motion_event)
		_last_mouse_motion_event = null # Clear after processing or if conditions not met


func _handle_mouse_camera_controls(event: InputEvent): # Was part of _handle_mouse_input
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
				_handle_tap_interaction(event.position) # Example: handle tap for selection
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

	var mouse_world_pos = camera.get_canvas_transform().affine_inverse() * event.global_position

	# Get map bounds from TileMap
	var used_rect = map_display.get_used_rect()
	var tile_size = map_display.tile_set.tile_size
	# ...existing code...
	var actual_tile_width_on_world: float = tile_size.x
	var actual_tile_height_on_world: float = tile_size.y

	var new_hover_info: Dictionary = {}
	var found_hover_element: bool = false

	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		if self._current_hover_info != new_hover_info: # If it changed to empty
			self._current_hover_info = new_hover_info
			emit_signal("hover_changed", self._current_hover_info)
		return

	# ...existing code...

	# print("MIM:_perform_hover_detection_only - Tile world size: (%s, %s)" % [actual_tile_width_on_world, actual_tile_height_on_world]) # DEBUG
	# 1. Check for Convoy Hover
	if not all_convoy_data.is_empty():
		for convoy_data_item in all_convoy_data:
			if not convoy_data_item is Dictionary: continue
			var convoy_map_x: float = convoy_data_item.get('x', -1.0)
			var convoy_map_y: float = convoy_data_item.get('y', -1.0)
			var convoy_id_val = convoy_data_item.get('convoy_id')
			if convoy_map_x >= 0.0 and convoy_map_y >= 0.0 and convoy_id_val != null:
				var convoy_id_str = str(convoy_id_val)
				var convoy_center_world_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_world
				var convoy_center_world_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_world
				var dx = mouse_world_pos.x - convoy_center_world_x
				var dy = mouse_world_pos.y - convoy_center_world_y
				# If convoy_hover_radius_on_texture_sq is defined in texture pixels, and 1 texture pixel = 1 world unit,
				# then this value is already in world_units_squared and should not be scaled by camera zoom.
				# print("MIM:_perform_hover_detection_only - Convoy ID: %s, World Pos: (%s, %s), Dist Sq: %s, Radius Sq: %s" % [convoy_id_str, convoy_center_world_x, convoy_center_world_y, (dx*dx)+(dy*dy), convoy_hover_radius_on_texture_sq]) # DEBUG
				if (dx * dx) + (dy * dy) < convoy_hover_radius_on_texture_sq: # Use exported variable
					# print("MIM:_perform_hover_detection_only - HOVER DETECTED for Convoy ID: ", convoy_id_str) # DEBUG
					new_hover_info = {'type': 'convoy', 'id': convoy_id_str}
					found_hover_element = true
					break

	# 2. Check for Settlement Hover (if no convoy was hovered)
	if not found_hover_element and not all_settlement_data.is_empty():
		var closest_settlement_dist_sq: float = settlement_hover_radius_on_texture_sq + 1.0 # Use exported variable
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
				# If settlement_hover_radius_on_texture_sq is defined in texture pixels, and 1 texture pixel = 1 world unit,
				# then this value is already in world_units_squared and should not be scaled by camera zoom.
				# print("MIM:_perform_hover_detection_only - Settlement Coords: (%s, %s), World Pos: (%s, %s), Dist Sq: %s, Radius Sq: %s" % [settlement_tile_x, settlement_tile_y, settlement_center_world_x, settlement_center_world_y, distance_sq_settlement, settlement_hover_radius_on_texture_sq]) # DEBUG
				if distance_sq_settlement < settlement_hover_radius_on_texture_sq:
					if distance_sq_settlement < closest_settlement_dist_sq: # Use exported variable
						# print("MIM:_perform_hover_detection_only - HOVER DETECTED for Settlement Coords: ", Vector2i(settlement_tile_x, settlement_tile_y)) # DEBUG
						closest_settlement_dist_sq = distance_sq_settlement
						best_hovered_settlement_coords = Vector2i(settlement_tile_x, settlement_tile_y)
						found_hover_element = true
		if found_hover_element and best_hovered_settlement_coords.x != -1:
			new_hover_info = {'type': 'settlement', 'coords': best_hovered_settlement_coords}

	# Update internal state and emit signal if hover changed
	# print("MIM:_perform_hover_detection_only - New hover info before check: ", new_hover_info) # DEBUG
	if new_hover_info != self._current_hover_info:
		self._current_hover_info = new_hover_info
		emit_signal("hover_changed", self._current_hover_info)
		# print("MIM: Hover changed to: ", self._current_hover_info) # DEBUG


func _handle_lmb_interactions(event: InputEventMouseButton): # Was _handle_mouse_button_interactions
	"""Handles MOUSE_BUTTON_LEFT press/release for panel dragging and map element selection. Assumes event.button_index == MOUSE_BUTTON_LEFT."""
	if not (is_instance_valid(camera) and \
			is_instance_valid(map_display)):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
				# --- Check for Panel Drag Start ---
				if is_instance_valid(ui_manager) and ui_manager.has_method("get_node_or_null") and is_instance_valid(ui_manager.convoy_label_container):
					var convoy_label_container_node = ui_manager.convoy_label_container
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

								if _selected_convoy_ids.has(id_from_meta):
									_dragging_panel_node = panel_node_candidate
									_dragged_convoy_id_actual_str = id_from_meta
									var panel_current_global_pos_for_offset = panel_rect_global.position
									_drag_offset = panel_current_global_pos_for_offset - event.global_position
									
									var viewport_rect = _current_map_screen_rect # Use map's effective screen rect for clamping
									
									_current_drag_clamp_rect = Rect2(
										viewport_rect.position.x + label_map_edge_padding,
										viewport_rect.position.y + label_map_edge_padding,
										viewport_rect.size.x - (2 * label_map_edge_padding),
										viewport_rect.size.y - (2 * label_map_edge_padding)
									)
									
									emit_signal("panel_drag_started", _dragged_convoy_id_actual_str, _dragging_panel_node)
									# print("MIM: Panel drag started for convoy: ", _dragged_convoy_id_actual_str) # Keep this one
									get_viewport().set_input_as_handled()
									return # Drag started

			# If no panel drag started, the click might be on the map (handled on release)

		elif not event.pressed: # Mouse button RELEASED
			if is_instance_valid(_dragging_panel_node):
				var final_local_position: Vector2 = _dragging_panel_node.position
				if _dragging_panel_node.get_parent() and is_instance_valid(_dragging_panel_node.get_parent()):
					final_local_position = _dragging_panel_node.get_parent().to_local(_dragging_panel_node.global_position)
				
				_convoy_label_user_positions[_dragged_convoy_id_actual_str] = final_local_position
				
				emit_signal("panel_drag_ended", _dragged_convoy_id_actual_str, final_local_position)
				# print("MIM: Panel drag ended for convoy: ", _dragged_convoy_id_actual_str, " at local pos: ", final_local_position) # Keep this one

				_dragging_panel_node = null
				_dragged_convoy_id_actual_str = ""
				
				get_viewport().set_input_as_handled()
				return # Drag ended

			# --- Handle click on map elements (convoys/settlements) ---
			var mouse_world_pos: Vector2 = camera.get_canvas_transform().affine_inverse() * event.global_position
			var clicked_convoy_data = _get_convoy_data_at_world_pos(mouse_world_pos)

			if clicked_convoy_data != null:
				emit_signal("convoy_menu_requested", clicked_convoy_data)
				# print("MIM: Clicked convoy for menu: ", clicked_convoy_data.get("convoy_id", "N/A")) # Keep this one
				get_viewport().set_input_as_handled()
				return # Click on convoy handled

			# TODO: Add settlement click logic here if needed, similar to convoy click.


func get_current_hover_info() -> Dictionary:
	return _current_hover_info

func get_selected_convoy_ids() -> Array[String]:
	return _selected_convoy_ids

func get_convoy_label_user_positions() -> Dictionary:
	return _convoy_label_user_positions

func is_dragging() -> bool:
	return is_instance_valid(_dragging_panel_node)

func get_dragging_panel_node() -> Panel:
	return _dragging_panel_node

func get_dragged_convoy_id_str() -> String:
	return _dragged_convoy_id_actual_str


func _handle_tap_interaction(screen_pos: Vector2):
	"""Handles tap interactions for selecting map elements (for TOUCH scheme)."""
	if not (is_instance_valid(camera) and is_instance_valid(map_display)):
		return

	var world_pos: Vector2 = camera.get_canvas_transform().affine_inverse() * screen_pos # Keep type hint for world_pos
	var clicked_convoy_data = _get_convoy_data_at_world_pos(world_pos) # Remove Dictionary type hint

	if clicked_convoy_data != null:
		emit_signal("convoy_menu_requested", clicked_convoy_data)
		# print("MIM: Tapped convoy for menu: ", clicked_convoy_data.get("convoy_id", "N/A")) # Keep this one
		get_viewport().set_input_as_handled()

func _zoom_camera_at_screen_pos(zoom_adjust_factor: float, screen_zoom_center: Vector2):
	# MOVED to MapCameraController.zoom_at_screen_pos()
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("zoom_at_screen_pos"):
		map_camera_controller.zoom_at_screen_pos(zoom_adjust_factor, screen_zoom_center)
	else:
		printerr("MIM: _zoom_camera_at_screen_pos - MapCameraController or method invalid.")

func set_and_clamp_camera_zoom(target_zoom_scalar: float):
	# MOVED to MapCameraController.set_and_clamp_zoom()
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("set_and_clamp_zoom"):
		map_camera_controller.set_and_clamp_zoom(target_zoom_scalar)
	else:
		printerr("MIM: set_and_clamp_camera_zoom - MapCameraController or method invalid.")

func focus_camera_and_set_zoom(target_world_position: Vector2, target_zoom_scalar: float):
	# MOVED to MapCameraController.focus_and_set_zoom()
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("focus_and_set_zoom"):
			
		map_camera_controller.focus_and_set_zoom(target_world_position, target_zoom_scalar)
		
	else:
		printerr("MIM: focus_camera_and_set_zoom - MapCameraController or method invalid.")

func _on_map_camera_controller_zoom_changed(new_zoom_level: float):
	# Re-emit the signal if other scripts are listening to MIM
	emit_signal("camera_zoom_changed", new_zoom_level)

func _get_convoy_data_at_world_pos(world_pos: Vector2) -> Variant:
	"""Helper to find a convoy's data Dictionary at a given world position."""
	if all_convoy_data.is_empty() or map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		return null

	var used_rect = map_display.get_used_rect()
	var tile_size = map_display.tile_set.tile_size
	# ...existing code...
	var actual_tile_width_on_world: float = tile_size.x
	var actual_tile_height_on_world: float = tile_size.y

	for convoy_data_item in all_convoy_data:
		if not convoy_data_item is Dictionary: continue
		var convoy_map_x: float = convoy_data_item.get('x', -1.0)
		var convoy_map_y: float = convoy_data_item.get('y', -1.0)
		var convoy_id_val = convoy_data_item.get('convoy_id')
		if convoy_id_val != null: # Ensure convoy has an ID and valid coordinates

			var convoy_center_world_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_world
			var convoy_center_world_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_world
			var dx = world_pos.x - convoy_center_world_x
			var dy = world_pos.y - convoy_center_world_y
			# Use convoy_hover_radius_on_texture_sq directly, assuming it's a world-space squared radius.
			# The scaling by camera.zoom was inconsistent with hover detection.
			if (dx * dx) + (dy * dy) < convoy_hover_radius_on_texture_sq:
				return convoy_data_item
	return null
