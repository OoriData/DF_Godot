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

# Emitted when the camera zoom level has changed.
signal camera_zoom_changed(new_zoom_level: float)

# Emitted when a convoy icon is clicked/tapped, requesting its menu.
signal convoy_menu_requested(convoy_data: Dictionary)

# --- Node References (to be set by main.gd via initialize method) ---
var map_display: TextureRect = null
var ui_manager: Node = null # This will be the UIManagerNode instance

# --- Data References (to be set by main.gd via initialize method) ---
var all_convoy_data: Array = []
var all_settlement_data: Array = []
var map_tiles: Array = []
var camera: Camera2D = null # Will be set by main.gd during initialization
var map_container_for_bounds: Node2D = null # To get map content dimensions for camera limits

var _initial_map_display_size: Vector2 = Vector2.ZERO # Store the original full map texture size

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

@export_group("Camera Controls")
## Minimum zoom level for the camera.
@export var min_camera_zoom_level: float = 0.2
## Maximum zoom level for the camera.
@export var max_camera_zoom_level: float = 5.0
## Enable zooming with the mouse wheel when using Mouse & Keyboard control scheme.
@export var enable_mouse_wheel_zoom: bool = true
## Factor by which to multiply/divide current zoom on each scroll step.
@export var camera_zoom_factor_increment: float = 1.1

var _is_camera_panning: bool = false
## Multiplier for camera pan speed when using mouse drag. Higher values increase sensitivity.
@export var camera_pan_sensitivity: float = 7.5

var _last_camera_pan_mouse_screen_position: Vector2

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


func _ready():
	# The MapInteractionManager might not need to process input itself if main.gd forwards it.
	# If it were to handle its own input (e.g., if it was a Control node covering the map),
	# you would set_process_input(true) or set_process_unhandled_input(true) here.
	# For now, we'll assume main.gd calls handle_input(event).
	set_process_input(true) # Changed from _unhandled_input
	set_process(true) # Enable _process for the hover timer


func initialize(
		p_map_display: TextureRect,
		p_ui_manager: Node,
		p_all_convoy_data: Array,
		p_all_settlement_data: Array,
		p_map_tiles: Array,
		p_camera: Camera2D, # Add camera reference
		p_map_container: Node2D, # Add map_container reference for bounds
		p_initial_selected_ids: Array, # Pass initial state if needed
		p_initial_user_positions: Dictionary # Pass initial state if needed
	):
	map_display = p_map_display
	if is_instance_valid(map_display):
		_initial_map_display_size = map_display.custom_minimum_size # Assuming this is set to full map texture size
		print("MapInteractionManager: Received map_display.custom_minimum_size in initialize: ", map_display.custom_minimum_size) # DEBUG
	ui_manager = p_ui_manager
	all_convoy_data = p_all_convoy_data
	all_settlement_data = p_all_settlement_data
	map_tiles = p_map_tiles
	_selected_convoy_ids = p_initial_selected_ids.duplicate(true) # Make a copy
	_convoy_label_user_positions = p_initial_user_positions.duplicate(true) # Make a copy

	camera = p_camera
	map_container_for_bounds = p_map_container

	print("MapInteractionManager: Initialized with references.")
	if not is_instance_valid(map_display): printerr("MapInteractionManager: map_display is invalid after init!")
	if not is_instance_valid(ui_manager): printerr("MapInteractionManager: ui_manager is invalid after init!")
	if not is_instance_valid(camera): printerr("MapInteractionManager: camera is invalid after init!")
	if not is_instance_valid(map_container_for_bounds): printerr("MapInteractionManager: map_container_for_bounds is invalid after init!")
	
	if is_instance_valid(camera): # Basic camera setup
		camera.drag_horizontal_enabled = true
		camera.drag_left_margin = 0.0
		camera.drag_right_margin = 0.0
		camera.drag_top_margin = 0.0
		camera.drag_vertical_enabled = true
		camera.drag_left_margin = 0.0; camera.drag_right_margin = 0.0
		camera.drag_top_margin = 0.0;  camera.drag_bottom_margin = 0.0
		camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		camera.set("smoothing_enabled", true)
		camera.set("smoothing_speed", 5.0) # Keep smoothing
		print("MapInteractionManager: Camera smoothing initialized.")
	else:
		printerr("MapInteractionManager: Camera node is invalid in initialize.")


func update_data_references(p_all_convoy_data: Array, p_all_settlement_data: Array, p_map_tiles: Array):
	"""Called by main.gd when core data (convoys, settlements, map_tiles) is updated."""
	all_convoy_data = p_all_convoy_data
	all_settlement_data = p_all_settlement_data
	map_tiles = p_map_tiles
	# print("MapInteractionManager: Data references updated.")

func _physics_process(delta: float):
	"""
	Performs manual camera clamping to keep the viewport edges within the map bounds.
	Called after camera position might be updated by physics or smoothing.
	"""
	if not is_instance_valid(camera) or not is_instance_valid(map_container_for_bounds) or _initial_map_display_size.x <= 0 or _initial_map_display_size.y <= 0:
		return # Cannot clamp if essential nodes or map size are invalid

	# Assuming map_container_for_bounds.position is the top-left of the map
	# and _initial_map_display_size is the map's size in world units.
	var map_rect_world = Rect2(map_container_for_bounds.position, _initial_map_display_size)
	var viewport_size_pixels = get_viewport().get_visible_rect().size

	if camera.zoom.x <= 0 or camera.zoom.y <= 0: # Avoid division by zero
		return

	var viewport_size_world = viewport_size_pixels / camera.zoom

	# Calculate the clamping bounds for the camera's center
	# The camera center must be offset from the map edge by half the viewport size (in world units)
	# to ensure the viewport edge aligns with the map edge.
	var clamp_min_x = map_rect_world.position.x + viewport_size_world.x / 2.0
	var clamp_max_x = map_rect_world.position.x + map_rect_world.size.x - viewport_size_world.x / 2.0
	var clamp_min_y = map_rect_world.position.y + viewport_size_world.y / 2.0
	var clamp_max_y = map_rect_world.position.y + map_rect_world.size.y - viewport_size_world.y / 2.0

	# Handle cases where map is smaller than viewport in a dimension (center the camera on the map)
	clamp_min_x = min(clamp_min_x, clamp_max_x) # Ensure min <= max, handles map smaller than viewport
	clamp_min_y = min(clamp_min_y, clamp_max_y) # Ensure min <= max, handles map smaller than viewport

	# Apply clamping to the camera's position
	camera.position.x = clamp(camera.position.x, clamp_min_x, clamp_max_x)
	camera.position.y = clamp(camera.position.y, clamp_min_y, clamp_max_y)

func _input(event: InputEvent): # Renamed from _unhandled_input
	# --- DEBUG: Log some events reaching _unhandled_input ---
	# This can be very verbose, enable only when actively debugging input issues.
	# print("MIM _unhandled_input RECEIVED EVENT --- Type: %s, Event: %s" % [event.get_class(), event]) # DEBUG: Performance intensive
	if event is InputEventMouseButton and false: # Disabled debug print
		print("MIM _unhandled_input: MouseButton - button_index: %s, pressed: %s, shift_pressed: %s, global_pos: %s" % [event.button_index, event.pressed, event.is_shift_pressed(), event.global_position]) # DEBUG
	elif event is InputEventMouseMotion:
		# print("MIM _unhandled_input: MouseMotion - global_pos: %s, relative: %s, button_mask: %s" % [event.global_position, event.relative, event.button_mask]) # DEBUG # Too verbose
		pass
	elif event is InputEventPanGesture: # DEBUG: Log PanGesture details
		print("MIM _unhandled_input: PanGesture - delta: %s, position: %s" % [event.delta, event.position]) # DEBUG
	# --- END DEBUG ---

	if not is_instance_valid(map_display) or \
	   (is_instance_valid(map_display) and not is_instance_valid(map_display.texture)) or \
	   not is_instance_valid(ui_manager) or \
	   not is_instance_valid(camera):
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
	if event is InputEventMouseMotion:
		_handle_panel_drag_motion_only(event)
		if get_viewport().is_input_handled():
			return # Consumed by panel drag motion

	# 3. Handle gestures (Magnify, Pan). These are distinct event types.
	if event is InputEventMagnifyGesture:
		if event.factor != 0.0: # Avoid division by zero, though unlikely for this event
			_zoom_camera_at_screen_pos(event.factor, event.position)
			get_viewport().set_input_as_handled()
		return # MagnifyGesture processed, then done.

	if event is InputEventPanGesture:
		if is_instance_valid(camera) and camera.zoom.x != 0.0:
			# Camera "flies" with the pan delta
			camera.position += event.delta * camera_pan_sensitivity / camera.zoom.x # Use position
			get_viewport().set_input_as_handled()
		return # PanGesture processed, then done.

	# If a gesture (or panel drag motion) consumed the event, subsequent logic for that event is skipped.
	if get_viewport().is_input_handled():
		return

	# 4. Handle scheme-specific interactions (camera controls, clicks, taps).
	match active_control_scheme:
		ControlScheme.MOUSE_AND_KEYBOARD:
			# This function now consolidates camera controls (MMB pan, wheel zoom)
			# and primary interactions (LMB clicks for panel drag start/end, map clicks).
			_handle_mk_scheme_interactions(event)
		ControlScheme.TOUCH:
			_handle_touch_input(event)


func _handle_mk_scheme_interactions(event: InputEvent):
	# This function combines logic previously in _handle_mouse_input() and _handle_mouse_button_interactions.
	# Order matters: camera controls might take precedence over map clicks for the same button.

	# Camera Panning (Middle Mouse Button or Shift + Left Mouse Button) & Camera Zoom (Wheel)
	# This logic is taken from the original _handle_mouse_input
	_handle_mouse_camera_controls(event)

	# If camera controls handled the event, don't process further for map/panel clicks.
	if get_viewport().is_input_handled():
		return

	# Left Mouse Button interactions (panel drag start/end, map element clicks)
	# This logic is taken from the original _handle_mouse_button_interactions
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_lmb_interactions(event) # New sub-function for clarity


func get_current_camera_zoom() -> float:
	if is_instance_valid(camera):
		return camera.zoom.x # Assuming uniform zoom
	return 1.0


func _process(delta: float):
	# Throttled hover detection
	_hover_update_timer += delta
	if _hover_update_timer >= HOVER_UPDATE_INTERVAL:
		_hover_update_timer = 0.0 # Reset timer
		if is_instance_valid(_last_mouse_motion_event) and \
		   active_control_scheme == ControlScheme.MOUSE_AND_KEYBOARD and \
		   not _is_camera_panning and \
		   not is_instance_valid(_dragging_panel_node): # Don't do hover if panning or dragging panel
			_perform_hover_detection_only(_last_mouse_motion_event)
		_last_mouse_motion_event = null # Clear after processing or if conditions not met


func _handle_mouse_camera_controls(event: InputEvent): # Was part of _handle_mouse_input
	# --- DEBUG: Log some events reaching _handle_mouse_input ---
	# print("MIM _handle_mouse_input RECEIVED EVENT --- Type: %s, Event: %s" % [event.get_class(), event]) # Verbose
	# if event is InputEventMouseButton:
	# print("MIM _handle_mouse_camera_controls: MouseButton - button_index: %s, pressed: %s, shift_pressed: %s, global_pos: %s" % [event.button_index, event.pressed, event.is_shift_pressed(), event.global_position]) # DEBUG
	# elif event is InputEventMouseMotion and _is_camera_panning:
	#     print("MIM _handle_mouse_input: MouseMotion - global_pos: %s, relative: %s, button_mask: %s" % [event.global_position, event.relative, event.button_mask]) # DEBUG
	# --- END DEBUG ---

	# Camera Panning (Middle Mouse Button Only)
	var is_middle_mouse_button_event = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE
	if is_middle_mouse_button_event:
		if event.pressed:
			_is_camera_panning = true
			# print("MIM _handle_mouse_camera_controls: Middle Mouse pan button event detected. Starting pan.") # DEBUG
			_last_camera_pan_mouse_screen_position = event.position
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			get_viewport().set_input_as_handled() # Consume the press event
		else: # released
			# Stop panning if we were in panning mode (initiated by middle mouse)
			if _is_camera_panning:
				_is_camera_panning = false
				# print("MIM _handle_mouse_camera_controls: Middle Mouse pan button released. Stopping pan.") # DEBUG
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				get_viewport().set_input_as_handled() # Consume the release event
		return # Consumed by middle mouse button press or release for panning

	if event is InputEventMouseMotion and _is_camera_panning:
		# --- DEBUG: Log pan motion ---
		# print("MIM _handle_mouse_input: Panning motion detected.") # DEBUG
		# print("  _is_camera_panning: %s" % _is_camera_panning) # DEBUG
		# print("  mouse_delta_screen (relative): %s" % event.relative) # DEBUG
		# --- END DEBUG --- #
		var mouse_delta_screen: Vector2 = event.relative # Use event.relative for direct screen delta
		if is_instance_valid(camera) and camera.zoom.x != 0.0:
			camera.position += mouse_delta_screen * camera_pan_sensitivity / camera.zoom.x # Use position, camera "flies" with mouse
		_last_camera_pan_mouse_screen_position = event.position # Update for next frame if using event.position for delta		
		get_viewport().set_input_as_handled() # Consume the event
		return # Consumed

	# Camera Zooming (Mouse Wheel)
	if enable_mouse_wheel_zoom and event is InputEventMouseButton: # Check the setting here
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.is_pressed():
			_zoom_camera_at_screen_pos(1.0 / camera_zoom_factor_increment, event.position) # factor < 1 for zoom in
			get_viewport().set_input_as_handled() # Consume the event
			return # Consumed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.is_pressed():
			_zoom_camera_at_screen_pos(camera_zoom_factor_increment, event.position) # factor > 1 for zoom out
			get_viewport().set_input_as_handled()
			return # Consumed

	# Keyboard Zooming (+/- keys) has been removed.


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


func _handle_panel_drag_motion_only(event: InputEventMouseMotion):
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
		get_viewport().set_input_as_handled() # Consume the event
		return
	# If not dragging a panel, this function does nothing further. Hover is separate.


func _perform_hover_detection_only(event: InputEventMouseMotion):
	"""Performs ONLY hover detection. Called from _process via throttle."""
	# Ensure we are not dragging a panel when performing hover detection
	if not (is_instance_valid(camera) and is_instance_valid(map_display) and is_instance_valid(map_display.texture)):
		return

	var mouse_world_pos = camera.get_canvas_transform().affine_inverse() * event.global_position

	# --- Convert local_mouse_pos to map texture coordinates ---
	var map_texture_size: Vector2 = map_display.texture.get_size()
	var map_display_rect_size: Vector2 = map_display.size
	if map_texture_size.x == 0 or map_texture_size.y == 0: return

	var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
	# var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y # Unused
	# var actual_scale: float = min(scale_x_ratio, scale_y_ratio) # Unused
	# var displayed_texture_width: float = map_texture_size.x * actual_scale # Unused
	# var displayed_texture_height: float = map_texture_size.y * actual_scale # Unused
	# var offset_x: float = (map_display_rect_size.x - displayed_texture_width) / 2.0 # Unused
	# var offset_y: float = (map_display_rect_size.y - displayed_texture_height) / 2.0 # Unused

	var new_hover_info: Dictionary = {}
	var found_hover_element: bool = false

	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		if self._current_hover_info != new_hover_info: # If it changed to empty
			self._current_hover_info = new_hover_info
			emit_signal("hover_changed", self._current_hover_info)
		return

	var map_cols: int = map_tiles[0].size()
	var map_rows: int = map_tiles.size()
	var actual_tile_width_on_world: float = _initial_map_display_size.x / float(map_cols)
	var actual_tile_height_on_world: float = _initial_map_display_size.y / float(map_rows)

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
				var scaled_hover_radius_sq = convoy_hover_radius_on_texture_sq / (camera.zoom.x * camera.zoom.x) # Assuming uniform zoom
				if (dx * dx) + (dy * dy) < scaled_hover_radius_sq:
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
				var scaled_settlement_hover_radius_sq = settlement_hover_radius_on_texture_sq / (camera.zoom.x * camera.zoom.x)
				if distance_sq_settlement < scaled_settlement_hover_radius_sq:
					if distance_sq_settlement < closest_settlement_dist_sq:
						closest_settlement_dist_sq = distance_sq_settlement
						best_hovered_settlement_coords = Vector2i(settlement_tile_x, settlement_tile_y)
						found_hover_element = true
		if found_hover_element and best_hovered_settlement_coords.x != -1:
			new_hover_info = {'type': 'settlement', 'coords': best_hovered_settlement_coords}

	# Update internal state and emit signal if hover changed
	if new_hover_info != self._current_hover_info:
		self._current_hover_info = new_hover_info
		emit_signal("hover_changed", self._current_hover_info)
		# print("MIM: Hover changed to: ", self._current_hover_info) # DEBUG


func _handle_lmb_interactions(event: InputEventMouseButton): # Was _handle_mouse_button_interactions
	"""Handles MOUSE_BUTTON_LEFT press/release for panel dragging and map element selection. Assumes event.button_index == MOUSE_BUTTON_LEFT."""
	if not (is_instance_valid(camera) and \
			is_instance_valid(map_display) and \
			is_instance_valid(map_display.texture)):
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

									var viewport_rect = get_viewport().get_visible_rect()
									_current_drag_clamp_rect = Rect2(
										viewport_rect.position.x + label_map_edge_padding,
										viewport_rect.position.y + label_map_edge_padding,
										viewport_rect.size.x - (2 * label_map_edge_padding),
										viewport_rect.size.y - (2 * label_map_edge_padding)
									)
									
									emit_signal("panel_drag_started", _dragged_convoy_id_actual_str, _dragging_panel_node)
									# print("MIM: Panel drag started for convoy: ", _dragged_convoy_id_actual_str) # DEBUG
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
				# print("MIM: Panel drag ended for convoy: ", _dragged_convoy_id_actual_str, " at local pos: ", final_local_position) # DEBUG

				_dragging_panel_node = null
				_dragged_convoy_id_actual_str = ""
				
				get_viewport().set_input_as_handled()
				return # Drag ended

			# --- Handle click on map elements (convoys/settlements) ---
			var mouse_world_pos: Vector2 = camera.get_canvas_transform().affine_inverse() * event.global_position
			var clicked_convoy_data = _get_convoy_data_at_world_pos(mouse_world_pos)

			if clicked_convoy_data != null:
				emit_signal("convoy_menu_requested", clicked_convoy_data)
				# print("MIM: Clicked convoy for menu: ", clicked_convoy_data.get("convoy_id", "N/A")) # DEBUG
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
	if not (is_instance_valid(camera) and is_instance_valid(map_display) and is_instance_valid(map_display.texture)):
		return

	var world_pos: Vector2 = camera.get_canvas_transform().affine_inverse() * screen_pos # Keep type hint for world_pos
	var clicked_convoy_data = _get_convoy_data_at_world_pos(world_pos) # Remove Dictionary type hint

	if clicked_convoy_data != null:
		emit_signal("convoy_menu_requested", clicked_convoy_data)
		print("MIM: Tapped convoy for menu: ", clicked_convoy_data.get("convoy_id", "N/A")) # DEBUG
		get_viewport().set_input_as_handled()

func _zoom_camera_at_screen_pos(zoom_adjust_factor: float, screen_zoom_center: Vector2):
	if not is_instance_valid(camera):
		return

	var min_zoom_from_export: float = min_camera_zoom_level
	var max_zoom_from_export: float = max_camera_zoom_level

	var effective_min_clamp_val: float = min_zoom_from_export
	var effective_max_clamp_val: float = max_zoom_from_export

	if _initial_map_display_size.x > 0.001 and _initial_map_display_size.y > 0.001:
		var viewport_pixel_size: Vector2 = get_viewport().get_visible_rect().size
		var map_world_size: Vector2 = _initial_map_display_size

		# Calculate the zoom level required for the map to fill the viewport width/height.
		# This is the smallest numerical zoom value (most zoomed-in) that prevents borders.
		var req_zoom_x_to_fill_viewport: float = viewport_pixel_size.x / map_world_size.x
		var req_zoom_y_to_fill_viewport: float = viewport_pixel_size.y / map_world_size.y
		var dynamic_min_zoom_to_prevent_borders: float = max(req_zoom_x_to_fill_viewport, req_zoom_y_to_fill_viewport)

		# The actual minimum zoom for clamping is the more restrictive of export setting and dynamic calculation.
		effective_min_clamp_val = max(min_zoom_from_export, dynamic_min_zoom_to_prevent_borders)
		
		# Ensure the max clamp value is not less than the (potentially increased) min clamp value.
		effective_max_clamp_val = max(effective_min_clamp_val, max_zoom_from_export)
	else:
		# Fallback if map size is invalid, use only exported limits
		pass # effective_min_clamp_val and effective_max_clamp_val already set to export limits

	var new_potential_zoom_scalar: float = camera.zoom.x * zoom_adjust_factor
	var clamped_new_zoom_scalar: float = clamp(new_potential_zoom_scalar, effective_min_clamp_val, effective_max_clamp_val)
	var new_zoom_vector: Vector2 = Vector2(clamped_new_zoom_scalar, clamped_new_zoom_scalar)

	if camera.zoom.is_equal_approx(new_zoom_vector):
		# This can happen if already at min/max zoom limit and trying to go further
		return # No significant change in zoom after clamping
	
	var inv_transform_before_zoom: Transform2D = camera.get_canvas_transform().affine_inverse()
	var world_pos_before_zoom: Vector2 = inv_transform_before_zoom * screen_zoom_center

	var old_zoom_for_signal = camera.zoom.x # Store before changing for the signal
	camera.zoom = new_zoom_vector

	var inv_transform_after_zoom: Transform2D = camera.get_canvas_transform().affine_inverse()
	var world_pos_after_zoom: Vector2 = inv_transform_after_zoom * screen_zoom_center
	
	camera.position += world_pos_before_zoom - world_pos_after_zoom # Use position
		
	# Camera's built-in limits will apply.
	if not is_equal_approx(old_zoom_for_signal, camera.zoom.x): # Check if zoom actually changed
		emit_signal("camera_zoom_changed", camera.zoom.x)

func _get_convoy_data_at_world_pos(world_pos: Vector2): # Removed -> Dictionary | null
	"""Helper to find a convoy's data Dictionary at a given world position."""
	if all_convoy_data.is_empty() or map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		return null

	var map_cols: int = map_tiles[0].size() # Should be safe due to checks above
	var actual_tile_width_on_world: float = _initial_map_display_size.x / float(map_cols)
	var actual_tile_height_on_world: float = _initial_map_display_size.y / float(map_tiles.size())

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
			var scaled_hover_radius_sq = convoy_hover_radius_on_texture_sq / (camera.zoom.x * camera.zoom.x)
			if (dx * dx) + (dy * dy) < scaled_hover_radius_sq:
				return convoy_data_item
	return null
