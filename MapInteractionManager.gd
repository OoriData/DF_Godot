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
## Factor by which to multiply/divide current zoom on each scroll step.
@export var camera_zoom_factor_increment: float = 1.1

var _is_camera_panning: bool = false
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
	set_process_unhandled_input(true)
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
	
	if is_instance_valid(camera):
		if _initial_map_display_size.x > 0 and _initial_map_display_size.y > 0:
			camera.limit_left = 0
			camera.limit_top = 0
			camera.limit_right = int(round(_initial_map_display_size.x))
			camera.limit_bottom = int(round(_initial_map_display_size.y))
			camera.drag_horizontal_enabled = true # Enable built-in limit enforcement
			camera.drag_vertical_enabled = true   # Enable built-in limit enforcement
			# Set drag margins to 0 as we are directly manipulating offset or relying on limits.
			camera.drag_left_margin = 0.0; camera.drag_right_margin = 0.0
			camera.drag_top_margin = 0.0;  camera.drag_bottom_margin = 0.0
			# To enable smoothing in Godot 4, set the process_callback.
			# Camera2D.CAMERA2D_PROCESS_PHYSICS is common for smooth game movement.
			camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS 
			camera.set("smoothing_speed", 2.0) # Use set() for properties like this. Adjust speed as needed.
		else:
			printerr("MapInteractionManager: _initial_map_display_size is zero in initialize. Camera limits not set.")

func update_data_references(p_all_convoy_data: Array, p_all_settlement_data: Array, p_map_tiles: Array):
	"""Called by main.gd when core data (convoys, settlements, map_tiles) is updated."""
	all_convoy_data = p_all_convoy_data
	all_settlement_data = p_all_settlement_data
	map_tiles = p_map_tiles
	# print("MapInteractionManager: Data references updated.")


func _unhandled_input(event: InputEvent): # Changed from handle_input
	if not is_instance_valid(map_display) or \
	   (is_instance_valid(map_display) and not is_instance_valid(map_display.texture)) or \
	   not is_instance_valid(ui_manager) or \
	   not is_instance_valid(camera):
		# print("MapInteractionManager: handle_input - Essential nodes not ready. Skipping.")
		return

	match active_control_scheme:
		ControlScheme.MOUSE_AND_KEYBOARD:
			_handle_mouse_input(event)
		ControlScheme.TOUCH:
			_handle_touch_input(event)

	# If event was not handled by scheme-specific camera/pan/zoom,
	# let the general UI interaction logic try.
	# This needs careful separation: mouse hover is mouse-only.
	# Panel dragging and map element clicks need to be adapted for touch within _handle_touch_input.
	if not get_viewport().is_input_handled():
		if event is InputEventMouseMotion and active_control_scheme == ControlScheme.MOUSE_AND_KEYBOARD:
			# Store the event; actual processing will be throttled in _process
			_last_mouse_motion_event = event
			# Panel drag motion still needs to be responsive, so handle that part immediately
			_handle_panel_drag_motion_only(event)
		elif event is InputEventMouseButton and active_control_scheme == ControlScheme.MOUSE_AND_KEYBOARD:
			# Handles panel drag start/end and map element clicks for mouse
			_handle_mouse_button_interactions(event)


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


func _handle_mouse_input(event: InputEvent):
	# Camera Panning (Middle Mouse Button)
	var is_pan_button_pressed = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE
	var is_alt_pan_button_pressed = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_shift_pressed()

	if is_pan_button_pressed or is_alt_pan_button_pressed:
		if event.pressed:
			_is_camera_panning = true
			_last_camera_pan_mouse_screen_position = event.position
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			get_viewport().set_input_as_handled()
		else: # released
			# Stop panning if we were in panning mode AND
			# the button being released is either middle mouse OR left mouse (for the shift+left case)
			if _is_camera_panning and \
			   (event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_LEFT):
				_is_camera_panning = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				get_viewport().set_input_as_handled()
		return # Consumed

	if event is InputEventMouseMotion and _is_camera_panning:
		var mouse_delta_screen: Vector2 = event.position - _last_camera_pan_mouse_screen_position
		camera.offset -= mouse_delta_screen / camera.zoom.x # Assuming uniform zoom
		_last_camera_pan_mouse_screen_position = event.position
		# Camera's built-in limits will apply. No explicit _constrain_camera_offset call needed here for panning.
		get_viewport().set_input_as_handled()
		return # Consumed

	# Camera Zooming (Mouse Wheel)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera_at_screen_pos(1.0 / camera_zoom_factor_increment, event.position) # factor < 1 for zoom in
			get_viewport().set_input_as_handled()
			return # Consumed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera_at_screen_pos(camera_zoom_factor_increment, event.position)      # factor > 1 for zoom out
			get_viewport().set_input_as_handled()
			return # Consumed

	# Keyboard Zooming (+/- keys)
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD: # '=' is often '+' without shift, KEY_PLUS might also work
			_zoom_camera_at_screen_pos(1.0 / camera_zoom_factor_increment, get_viewport().get_mouse_position()) # Zoom in towards mouse
			get_viewport().set_input_as_handled()
			return # Consumed
		elif event.keycode == KEY_MINUS || event.keycode == KEY_KP_SUBTRACT:
			_zoom_camera_at_screen_pos(camera_zoom_factor_increment, get_viewport().get_mouse_position())      # Zoom out from mouse
			get_viewport().set_input_as_handled()
			return # Consumed
	# Mouse button interactions for UI (panel drag, map clicks) are handled by _handle_mouse_button_interactions
	# called from _unhandled_input if this function doesn't consume the event.

func _handle_touch_input(event: InputEvent):
	# Touch Panning (Single finger drag)
	if event is InputEventScreenTouch:
		if event.pressed:
			if _pan_touch_index == -1: # No pan active, start one
				_pan_touch_index = event.index
				_is_camera_panning = true # Use the same flag
				# For touch, relative motion is used, so last position isn't strictly needed for delta
				get_viewport().set_input_as_handled()
		else: # released
			if event.index == _pan_touch_index: # If the finger that started the pan is released
				_pan_touch_index = -1
				_is_camera_panning = false
				get_viewport().set_input_as_handled()
				# Here, you could check if it was a "tap" (short press, little movement)
				# and call a tap interaction handler.
				_handle_tap_interaction(event.position) # Example: handle tap for selection
		return # Consumed

	if event is InputEventScreenDrag and event.index == _pan_touch_index:
		if _is_camera_panning:
			camera.offset -= event.relative / camera.zoom.x # event.relative is the change in screen position
			# Camera's built-in limits will apply.
			get_viewport().set_input_as_handled()
		return # Consumed

	# Touch Zooming (Pinch Gesture)
	if event is InputEventMagnifyGesture:
		# event.factor is the magnification factor.
		# Our _zoom_camera_at_screen_pos expects a factor where >1 zooms out.
		_zoom_camera_at_screen_pos(event.factor, event.position)
		get_viewport().set_input_as_handled()
		return # Consumed

	# Touch Taps for UI interaction (panel drag start/end, map element click)
	# This is simplified. Robust touch UI needs careful state management.
	# For example, detecting a drag start on a panel with touch.
	# The _handle_tap_interaction above handles map element clicks.


func _handle_panel_drag_motion_only(event: InputEventMouseMotion):
	"""Handles ONLY the panel dragging motion part. Called directly from _unhandled_input."""
	if is_instance_valid(_dragging_panel_node) and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		# Calculate the new target global position for the panel's origin
		var new_global_panel_pos: Vector2 = event.global_position + _drag_offset

		# Clamp the new global position using the pre-calculated _current_drag_clamp_rect
		if _current_drag_clamp_rect.size.x > 0 and _current_drag_clamp_rect.size.y > 0: # Check if clamp rect is valid
			new_global_panel_pos.x = clamp(
				new_global_panel_pos.x,
				_current_drag_clamp_rect.position.x,
				_current_drag_clamp_rect.position.x + _current_drag_clamp_rect.size.x - _dragging_panel_node.size.x
			)
			new_global_panel_pos.y = clamp(
				new_global_panel_pos.y,
				_current_drag_clamp_rect.position.y,
				_current_drag_clamp_rect.position.y + _current_drag_clamp_rect.size.y - _dragging_panel_node.size.y
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


func _handle_mouse_button_interactions(event: InputEventMouseButton):
	"""Handles MOUSE_BUTTON_LEFT press/release for panel dragging and map element selection."""
	if not (is_instance_valid(camera) and \
			is_instance_valid(map_display) and \
			is_instance_valid(map_display.texture)):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# --- Check for Panel Drag Start ---
			# This needs access to UIManager's convoy_label_container
			if is_instance_valid(ui_manager) and ui_manager.has_method("get_node_or_null") and is_instance_valid(ui_manager.convoy_label_container):
				var convoy_label_container_node = ui_manager.convoy_label_container
				# Iterate from top-most to bottom-most child visually
				for i in range(convoy_label_container_node.get_child_count() - 1, -1, -1):
					var node = convoy_label_container_node.get_child(i)
					if node is Panel:
						var panel_node_candidate: Panel = node
						if not is_instance_valid(panel_node_candidate):
							continue

						# Always use get_global_rect() for accurate hit testing with scaled panels
						var panel_rect_global = panel_node_candidate.get_global_rect()
						var hit_test_rect = panel_rect_global.grow(2.0) # Small buffer for easier clicking

						if hit_test_rect.has_point(event.global_position):
							var id_from_meta = panel_node_candidate.get_meta("convoy_id_str", "")
							if id_from_meta.is_empty(): id_from_meta = panel_node_candidate.name

							if _selected_convoy_ids.has(id_from_meta): # Only draggable if selected
								_dragging_panel_node = panel_node_candidate
								_dragged_convoy_id_actual_str = id_from_meta

								var panel_current_global_pos_for_offset = panel_rect_global.position # Use the rect's position
								_drag_offset = panel_current_global_pos_for_offset - event.global_position

								# Calculate and store clamping bounds (in global coordinates)
								var viewport_rect = get_viewport().get_visible_rect()
								_current_drag_clamp_rect = Rect2(
									viewport_rect.position.x + label_map_edge_padding, # Use exported variable
									viewport_rect.position.y + label_map_edge_padding, # Use exported variable
									viewport_rect.size.x - (2 * label_map_edge_padding), # Use exported variable
									viewport_rect.size.y - (2 * label_map_edge_padding)  # Use exported variable
								)
								
								emit_signal("panel_drag_started", _dragged_convoy_id_actual_str, _dragging_panel_node)
								print("MIM: Panel drag started for convoy: ", _dragged_convoy_id_actual_str) # DEBUG
								get_viewport().set_input_as_handled() # Consume the event
								return # Drag started, no further processing for this click in MIM

			# If no panel drag started, the click might be on the map (handled on release)

		elif not event.pressed: # Mouse button RELEASED
			# If a drag was in progress (handled by MIM), this would be drag end.
			if is_instance_valid(_dragging_panel_node):
				var final_local_position = _dragging_panel_node.position # Position is local to its parent
				if _dragging_panel_node.get_parent() and is_instance_valid(_dragging_panel_node.get_parent()):
					final_local_position = _dragging_panel_node.get_parent().to_local(_dragging_panel_node.global_position)
				
				_convoy_label_user_positions[_dragged_convoy_id_actual_str] = final_local_position
				
				emit_signal("panel_drag_ended", _dragged_convoy_id_actual_str, final_local_position)
				print("MIM: Panel drag ended for convoy: ", _dragged_convoy_id_actual_str, " at local pos: ", final_local_position) # DEBUG

				_dragging_panel_node = null
				_dragged_convoy_id_actual_str = ""
				# _drag_offset and _current_drag_clamp_rect are reset on next drag start
				
				get_viewport().set_input_as_handled() # Consume the event
				return # Assuming drag release is handled elsewhere or will be handled here later

			# --- Handle click on map elements (convoys/settlements) ---
			# Convert screen mouse pos to camera's canvas space (world space)
			var mouse_world_pos = camera.get_canvas_transform().affine_inverse() * event.global_position
			# mouse_world_pos is now in the coordinate system of MapContainer.
			# MapDisplay is at (0,0) in MapContainer and has size _initial_map_display_size.
			# So mouse_world_pos is effectively mouse_on_texture_x/y if MapDisplay origin is top-left.

			var clicked_convoy_id_str_on_map: String = ""
			if not all_convoy_data.is_empty() and not map_tiles.is_empty() and map_tiles[0] is Array and not map_tiles[0].is_empty():
				var map_cols: int = map_tiles[0].size()
				# var map_rows: int = map_tiles.size() # Unused
				# Use _initial_map_display_size for tile dimensions in world space
				var actual_tile_width_on_world: float = _initial_map_display_size.x / float(map_cols)
				var actual_tile_height_on_world: float = _initial_map_display_size.y / float(map_tiles.size())

				for convoy_data_item in all_convoy_data:
					if not convoy_data_item is Dictionary: continue
					var convoy_map_x: float = convoy_data_item.get('x', -1.0)
					var convoy_map_y: float = convoy_data_item.get('y', -1.0)
					var convoy_id_val = convoy_data_item.get('convoy_id')
					if convoy_id_val != null:
						var convoy_center_world_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_world
						var convoy_center_world_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_world
						var dx = mouse_world_pos.x - convoy_center_world_x
						var dy = mouse_world_pos.y - convoy_center_world_y
						# Scale hover radius by camera zoom for comparison in world space
						var scaled_click_radius_sq = convoy_hover_radius_on_texture_sq / (camera.zoom.x * camera.zoom.x) # Assuming uniform zoom
						if (dx * dx) + (dy * dy) < scaled_click_radius_sq:
							clicked_convoy_id_str_on_map = str(convoy_id_val)
							break

			if not clicked_convoy_id_str_on_map.is_empty():
				var selection_changed_flag = false
				if _selected_convoy_ids.has(clicked_convoy_id_str_on_map):
					_selected_convoy_ids.erase(clicked_convoy_id_str_on_map)
					selection_changed_flag = true
					# User position is intentionally NOT erased here to remember it for re-selection.
					print("MIM: Deselected convoy: ", clicked_convoy_id_str_on_map) # DEBUG
				else:
					_selected_convoy_ids.append(clicked_convoy_id_str_on_map)
					selection_changed_flag = true
					print("MIM: Selected convoy: ", clicked_convoy_id_str_on_map) # DEBUG
				
				if selection_changed_flag:
					emit_signal("selection_changed", _selected_convoy_ids)
				
				# Potentially consume the event if a map icon was clicked
				get_viewport().set_input_as_handled()

			# TODO: Add settlement click logic if needed


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

	var world_pos = camera.get_canvas_transform().affine_inverse() * screen_pos
	# Simplified: Check only for convoy clicks on tap for now.
	# This logic is similar to the click part of _handle_mouse_button_interactions.
	var clicked_convoy_id_str_on_map: String = _get_convoy_id_at_world_pos(world_pos)

	if not clicked_convoy_id_str_on_map.is_empty():
		var selection_changed_flag = false
		if _selected_convoy_ids.has(clicked_convoy_id_str_on_map):
			_selected_convoy_ids.erase(clicked_convoy_id_str_on_map)
			selection_changed_flag = true
		else:
			_selected_convoy_ids.append(clicked_convoy_id_str_on_map)
			selection_changed_flag = true
		if selection_changed_flag:
			emit_signal("selection_changed", _selected_convoy_ids)
		get_viewport().set_input_as_handled()

func _zoom_camera_at_screen_pos(zoom_adjust_factor: float, screen_zoom_center: Vector2):
	if not is_instance_valid(camera):
		return

	var new_zoom_x = clamp(camera.zoom.x * zoom_adjust_factor, min_camera_zoom_level, max_camera_zoom_level)
	var new_zoom_y = clamp(camera.zoom.y * zoom_adjust_factor, min_camera_zoom_level, max_camera_zoom_level)
	var new_zoom_vector = Vector2(new_zoom_x, new_zoom_y)

	if camera.zoom.is_equal_approx(new_zoom_vector):
		return # No significant change in zoom

	# var mouse_screen_pos = get_viewport().get_mouse_position() # Use passed screen_zoom_center
	
	# Get the inverse transform before zoom changes
	var inv_transform_before_zoom: Transform2D = camera.get_canvas_transform().affine_inverse()
	var world_pos_before_zoom: Vector2 = inv_transform_before_zoom * screen_zoom_center

	camera.zoom = new_zoom_vector

	# Get the inverse transform after zoom has changed
	var inv_transform_after_zoom: Transform2D = camera.get_canvas_transform().affine_inverse()
	var world_pos_after_zoom: Vector2 = inv_transform_after_zoom * screen_zoom_center
	
	camera.offset += world_pos_before_zoom - world_pos_after_zoom
	# Camera's built-in limits will apply. No explicit _constrain_camera_offset call needed.



func _constrain_camera_offset():
	if not is_instance_valid(camera) or not is_instance_valid(map_container_for_bounds) or not is_instance_valid(map_display):
		return
	
	# _initial_map_display_size should be the full size of the map texture
	if _initial_map_display_size.x == 0 or _initial_map_display_size.y == 0:
		# This can happen if initialize was called before map_display had its size set
		# Try to get it again, assuming map_display.custom_minimum_size is the full map texture size
		if is_instance_valid(map_display) and map_display.custom_minimum_size != Vector2.ZERO:
			_initial_map_display_size = map_display.custom_minimum_size
		else:
			# printerr("MIM: _constrain_camera_offset - _initial_map_display_size is zero.")
			return
	# This function is now largely handled by the camera's built-in limits
	# which are set during initialize().
	# If the map is smaller than the viewport at current zoom, we might want to center it.
	var viewport_size_world = get_viewport().get_visible_rect().size / camera.zoom.x # Assuming uniform zoom

	if _initial_map_display_size.x < viewport_size_world.x:
		# Center horizontally if map is narrower than viewport
		camera.offset.x = _initial_map_display_size.x / 2.0
	# else: Camera limits will handle horizontal clamping

	if _initial_map_display_size.y < viewport_size_world.y:
		# Center vertically if map is shorter than viewport
		camera.offset.y = _initial_map_display_size.y / 2.0
	# else: Camera limits will handle vertical clamping

func _get_convoy_id_at_world_pos(world_pos: Vector2) -> String:
	"""Helper to find a convoy ID at a given world position."""
	if all_convoy_data.is_empty() or map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		return ""

	var map_cols: int = map_tiles[0].size()
	var actual_tile_width_on_world: float = _initial_map_display_size.x / float(map_cols)
	var actual_tile_height_on_world: float = _initial_map_display_size.y / float(map_tiles.size())

	for convoy_data_item in all_convoy_data:
		if not convoy_data_item is Dictionary: continue
		var convoy_map_x: float = convoy_data_item.get('x', -1.0)
		var convoy_map_y: float = convoy_data_item.get('y', -1.0)
		var convoy_id_val = convoy_data_item.get('convoy_id')
		if convoy_id_val != null:
			var convoy_center_world_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_world
			var convoy_center_world_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_world
			var dx = world_pos.x - convoy_center_world_x
			var dy = world_pos.y - convoy_center_world_y
			var scaled_hover_radius_sq = convoy_hover_radius_on_texture_sq / (camera.zoom.x * camera.zoom.x)
			if (dx * dx) + (dy * dy) < scaled_hover_radius_sq:
				return str(convoy_id_val)
	return ""
