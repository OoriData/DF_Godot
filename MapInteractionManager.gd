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

# --- Constants (can be moved from main.gd later if specific to interaction) ---
const CONVOY_HOVER_RADIUS_ON_TEXTURE_SQ: float = 625.0  # (25 pixels)^2
const SETTLEMENT_HOVER_RADIUS_ON_TEXTURE_SQ: float = 400.0  # (20 pixels)^2
const LABEL_MAP_EDGE_PADDING: float = 5.0 # For drag clamping

# --- Internal State Variables (will be moved from main.gd) ---
var _current_hover_info: Dictionary = {}
var _selected_convoy_ids: Array[String] = []

var _dragging_panel_node: Panel = null
var _drag_offset: Vector2 = Vector2.ZERO
var _convoy_label_user_positions: Dictionary = {} # { 'convoy_id_str': Vector2(local_x, local_y) }
var _dragged_convoy_id_actual_str: String = ""
var _current_drag_clamp_rect: Rect2 # Global coordinates for clamping


func _ready():
	# The MapInteractionManager might not need to process input itself if main.gd forwards it.
	# If it were to handle its own input (e.g., if it was a Control node covering the map),
	# you would set_process_input(true) or set_process_unhandled_input(true) here.
	# For now, we'll assume main.gd calls handle_input(event).
	pass


func initialize(
		p_map_display: TextureRect,
		p_ui_manager: Node,
		p_all_convoy_data: Array,
		p_all_settlement_data: Array,
		p_map_tiles: Array,
		p_initial_selected_ids: Array, # Pass initial state if needed
		p_initial_user_positions: Dictionary # Pass initial state if needed
	):
	map_display = p_map_display
	ui_manager = p_ui_manager
	all_convoy_data = p_all_convoy_data
	all_settlement_data = p_all_settlement_data
	map_tiles = p_map_tiles
	_selected_convoy_ids = p_initial_selected_ids.duplicate(true) # Make a copy
	_convoy_label_user_positions = p_initial_user_positions.duplicate(true) # Make a copy

	print("MapInteractionManager: Initialized with references.")
	if not is_instance_valid(map_display): printerr("MapInteractionManager: map_display is invalid after init!")
	if not is_instance_valid(ui_manager): printerr("MapInteractionManager: ui_manager is invalid after init!")


func update_data_references(p_all_convoy_data: Array, p_all_settlement_data: Array, p_map_tiles: Array):
	"""Called by main.gd when core data (convoys, settlements, map_tiles) is updated."""
	all_convoy_data = p_all_convoy_data
	all_settlement_data = p_all_settlement_data
	map_tiles = p_map_tiles
	# print("MapInteractionManager: Data references updated.")


func handle_input(event: InputEvent):
	# This is where the logic from main.gd's _input function will eventually go.
	# For now, it's a placeholder.

	if not is_instance_valid(map_display) or not is_instance_valid(map_display.texture) or not is_instance_valid(ui_manager):
		# print("MapInteractionManager: handle_input - Essential nodes not ready. Skipping.")
		return

	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)


func _handle_mouse_motion(event: InputEventMouseMotion):
	# If a panel is being dragged, MIM should handle updating its position
	# and emitting panel_drag_updated.

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

	if not is_instance_valid(map_display) or not is_instance_valid(map_display.texture):
		return

	var local_mouse_pos = map_display.get_local_mouse_position()

	# --- Convert local_mouse_pos to map texture coordinates ---
	var map_texture_size: Vector2 = map_display.texture.get_size()
	var map_display_rect_size: Vector2 = map_display.size
	if map_texture_size.x == 0 or map_texture_size.y == 0: return

	var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
	var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y
	var actual_scale: float = min(scale_x_ratio, scale_y_ratio)
	var displayed_texture_width: float = map_texture_size.x * actual_scale
	var displayed_texture_height: float = map_texture_size.y * actual_scale
	var offset_x: float = (map_display_rect_size.x - displayed_texture_width) / 2.0
	var offset_y: float = (map_display_rect_size.y - displayed_texture_height) / 2.0

	var mouse_on_texture_x = (local_mouse_pos.x - offset_x) / actual_scale
	var mouse_on_texture_y = (local_mouse_pos.y - offset_y) / actual_scale

	var new_hover_info: Dictionary = {}
	var found_hover_element: bool = false

	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		if self._current_hover_info != new_hover_info: # If it changed to empty
			self._current_hover_info = new_hover_info
			emit_signal("hover_changed", self._current_hover_info)
		return

	var map_cols: int = map_tiles[0].size()
	var map_rows: int = map_tiles.size()
	var actual_tile_width_on_texture: float = map_texture_size.x / float(map_cols)
	var actual_tile_height_on_texture: float = map_texture_size.y / float(map_rows)

	# 1. Check for Convoy Hover
	if not all_convoy_data.is_empty():
		for convoy_data_item in all_convoy_data:
			if not convoy_data_item is Dictionary: continue
			var convoy_map_x: float = convoy_data_item.get('x', -1.0)
			var convoy_map_y: float = convoy_data_item.get('y', -1.0)
			var convoy_id_val = convoy_data_item.get('convoy_id')
			if convoy_map_x >= 0.0 and convoy_map_y >= 0.0 and convoy_id_val != null:
				var convoy_id_str = str(convoy_id_val)
				var convoy_center_tex_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_texture
				var convoy_center_tex_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_texture
				var dx = mouse_on_texture_x - convoy_center_tex_x
				var dy = mouse_on_texture_y - convoy_center_tex_y
				if (dx * dx) + (dy * dy) < CONVOY_HOVER_RADIUS_ON_TEXTURE_SQ:
					new_hover_info = {'type': 'convoy', 'id': convoy_id_str}
					found_hover_element = true
					break

	# 2. Check for Settlement Hover (if no convoy was hovered)
	if not found_hover_element and not all_settlement_data.is_empty():
		var closest_settlement_dist_sq: float = SETTLEMENT_HOVER_RADIUS_ON_TEXTURE_SQ + 1.0
		var best_hovered_settlement_coords: Vector2i = Vector2i(-1, -1)
		for settlement_info_item in all_settlement_data:
			if not settlement_info_item is Dictionary: continue
			var settlement_tile_x: int = settlement_info_item.get('x', -1)
			var settlement_tile_y: int = settlement_info_item.get('y', -1)
			if settlement_tile_x >= 0 and settlement_tile_y >= 0:
				var settlement_center_tex_x: float = (float(settlement_tile_x) + 0.5) * actual_tile_width_on_texture
				var settlement_center_tex_y: float = (float(settlement_tile_y) + 0.5) * actual_tile_height_on_texture
				var dx_settlement = mouse_on_texture_x - settlement_center_tex_x
				var dy_settlement = mouse_on_texture_y - settlement_center_tex_y
				var distance_sq_settlement = (dx_settlement * dx_settlement) + (dy_settlement * dy_settlement)
				if distance_sq_settlement < SETTLEMENT_HOVER_RADIUS_ON_TEXTURE_SQ:
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


func _handle_mouse_button(event: InputEventMouseButton):
	if not is_instance_valid(map_display) or not is_instance_valid(map_display.texture):
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

						var panel_rect_global = panel_node_candidate.get_meta("intended_global_rect", null)
						if not (panel_rect_global is Rect2):
							panel_rect_global = panel_node_candidate.get_global_rect()

						var hit_test_rect = panel_rect_global.grow(2.0)

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
									viewport_rect.position.x + LABEL_MAP_EDGE_PADDING,
									viewport_rect.position.y + LABEL_MAP_EDGE_PADDING,
									viewport_rect.size.x - (2 * LABEL_MAP_EDGE_PADDING),
									viewport_rect.size.y - (2 * LABEL_MAP_EDGE_PADDING)
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
			var local_mouse_pos = map_display.get_local_mouse_position()

			var map_texture_size: Vector2 = map_display.texture.get_size()
			var map_display_rect_size: Vector2 = map_display.size
			if map_texture_size.x == 0 or map_texture_size.y == 0: return

			var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
			var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y
			var actual_scale: float = min(scale_x_ratio, scale_y_ratio)
			var displayed_texture_width: float = map_texture_size.x * actual_scale
			var displayed_texture_height: float = map_texture_size.y * actual_scale
			var offset_x: float = (map_display_rect_size.x - displayed_texture_width) / 2.0
			var offset_y: float = (map_display_rect_size.y - displayed_texture_height) / 2.0

			var mouse_on_texture_x = (local_mouse_pos.x - offset_x) / actual_scale
			var mouse_on_texture_y = (local_mouse_pos.y - offset_y) / actual_scale

			var clicked_convoy_id_str_on_map: String = ""
			if not all_convoy_data.is_empty() and not map_tiles.is_empty() and map_tiles[0] is Array and not map_tiles[0].is_empty():
				var map_cols: int = map_tiles[0].size()
				var map_rows: int = map_tiles.size()
				var actual_tile_width_on_texture: float = map_texture_size.x / float(map_cols)
				var actual_tile_height_on_texture: float = map_texture_size.y / float(map_rows)

				for convoy_data_item in all_convoy_data:
					if not convoy_data_item is Dictionary: continue
					var convoy_map_x: float = convoy_data_item.get('x', -1.0)
					var convoy_map_y: float = convoy_data_item.get('y', -1.0)
					var convoy_id_val = convoy_data_item.get('convoy_id')
					if convoy_id_val != null:
						var convoy_center_tex_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_texture
						var convoy_center_tex_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_texture
						var dx = mouse_on_texture_x - convoy_center_tex_x
						var dy = mouse_on_texture_y - convoy_center_tex_y
						if (dx * dx) + (dy * dy) < CONVOY_HOVER_RADIUS_ON_TEXTURE_SQ: # Using hover radius for click
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
				# get_viewport().set_input_as_handled() # main.gd will do this if it receives the signal

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