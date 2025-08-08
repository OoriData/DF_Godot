extends Node
# Cached references from UIManager or main
var _convoy_label_container_ref: Node2D # Will be assigned programmatically
var _label_settings_ref: LabelSettings
var _base_convoy_title_font_size_ref: int = 15 # Default, will be overridden
var _ui_overall_scale_multiplier: float = 1.0
var _font_scaling_base_tile_size: float = 24.0
var _font_scaling_exponent: float = 0.6
var _max_node_panel_border_width: int = 3 # Default max border width
var _CONVOY_STAT_EMOJIS_ref: Dictionary # Expected to be initialized externally

# Add a local cache for convoy data by ID
var _convoy_data_by_id_cache: Dictionary = {}

# --- Newly Declared Member Variables ---
# Font size clamping
var _min_node_font_size: int = 8
var _max_node_font_size: int = 72

# Active panels tracking
var _active_convoy_panels: Dictionary = {}

# Cached map/view parameters (presumably updated externally)
var _cached_actual_tile_width_on_texture: float = 24.0
var _cached_actual_tile_height_on_texture: float = 24.0
var _current_map_zoom_cache: float = 1.0
var _cached_actual_scale: float = 1.0
var _cached_offset_x: float = 0.0
var _cached_offset_y: float = 0.0
var _ui_drawing_params_cached: bool = false # Flag indicating if cache params are valid

# Panel styling parameters
var _base_convoy_panel_corner_radius: float = 4.0
var _min_node_panel_corner_radius: float = 0.0
var _max_node_panel_corner_radius: float = 20.0

var _base_convoy_panel_padding_h: float = 4.0
var _base_convoy_panel_padding_v: float = 2.0
var _min_node_panel_padding: float = 0.0
var _max_node_panel_padding: float = 20.0

var _base_convoy_panel_border_width: float = 1.0 # Base value for scaling
var _min_node_panel_border_width: int = 0 # Min clamp for border width
# _max_node_panel_border_width is already declared above

var _convoy_panel_background_color: Color = Color(0.1, 0.1, 0.1, 0.75)

# Label positioning parameters
var _base_selected_convoy_horizontal_offset: float = 20.0
var _base_horizontal_label_offset_from_center: float = 10.0
var _label_map_edge_padding: float = 2.0
var _label_anti_collision_y_shift: float = 5.0


func set_convoy_label_container(p_container: Node2D):
	if not is_instance_valid(p_container):
		# Updated error message for clarity
		# printerr("ConvoyLabelManager (set_convoy_label_container): Attempted to assign an invalid Control node. Labels cannot be created.")
		_convoy_label_container_ref = null # Ensure it's null if an invalid one was passed
	else:
		_convoy_label_container_ref = p_container
		_convoy_label_container_ref.visible = true # Set visibility when a valid container is assigned

func _ready():
	# Connect to the UIScaleManager to react to global scale changes.
	if Engine.has_singleton("ui_scale_manager"):
		# The initial value will be set by UIManager via initialize_font_settings,
		# but we connect here to listen for any subsequent changes.
		ui_scale_manager.scale_changed.connect(_on_ui_scale_changed)
	else:
		printerr("ConvoyLabelManager: ui_scale_manager singleton not found. UI scaling will not be dynamic.")

func initialize_font_settings(p_theme_font: Font, p_label_settings: LabelSettings, 
							  p_base_convoy_title_fs: int,
							  p_ui_scale: float, p_font_base_tile_size: float, 
							  p_font_exponent: float, p_min_font: int, p_max_font: int,
							  p_all_convoy_data: Array, p_convoy_stat_emojis: Dictionary):
	_label_settings_ref = p_label_settings # UIManager still owns this, we just use it
	if is_instance_valid(_label_settings_ref):
		_label_settings_ref.font = p_theme_font
	_ui_overall_scale_multiplier = p_ui_scale
	_font_scaling_base_tile_size = p_font_base_tile_size
	_base_convoy_title_font_size_ref = p_base_convoy_title_fs
	_font_scaling_exponent = p_font_exponent
	_min_node_font_size = p_min_font
	_max_node_font_size = p_max_font

	_CONVOY_STAT_EMOJIS_ref = p_convoy_stat_emojis

	# Populate local convoy_data_by_id_cache
	_convoy_data_by_id_cache.clear()
	if p_all_convoy_data is Array:
		for convoy_data_item in p_all_convoy_data:
			if convoy_data_item is Dictionary and convoy_data_item.has("convoy_id"):
				_convoy_data_by_id_cache[str(convoy_data_item.get("convoy_id"))] = convoy_data_item

func initialize_style_settings(
	p_base_corner_radius: float, p_min_corner_radius: float, p_max_corner_radius: float,
	p_base_padding_h: float, p_base_padding_v: float,
	p_min_padding: float, p_max_padding: float,
	p_base_border_width: float, p_min_border_width: int, p_max_border_width: int,
	p_bg_color: Color,
	p_base_selected_offset: float, p_base_offset: float,
	p_edge_padding: float, p_collision_shift: float
):
	_base_convoy_panel_corner_radius = p_base_corner_radius
	_min_node_panel_corner_radius = p_min_corner_radius
	_max_node_panel_corner_radius = p_max_corner_radius
	_base_convoy_panel_padding_h = p_base_padding_h
	_base_convoy_panel_padding_v = p_base_padding_v
	_min_node_panel_padding = p_min_padding
	_max_node_panel_padding = p_max_padding
	_base_convoy_panel_border_width = p_base_border_width
	_min_node_panel_border_width = p_min_border_width
	_max_node_panel_border_width = p_max_border_width
	_convoy_panel_background_color = p_bg_color
	_base_selected_convoy_horizontal_offset = p_base_selected_offset
	_base_horizontal_label_offset_from_center = p_base_offset
	_label_map_edge_padding = p_edge_padding
	_label_anti_collision_y_shift = p_collision_shift

func update_drawing_parameters(
	p_actual_tile_width_on_texture: float,
	p_actual_tile_height_on_texture: float,
	p_current_map_zoom: float,
	p_actual_scale: float, # This is often map_display.scale.x/y if uniform
	p_map_offset_x: float, # This is often map_display.global_position.x
	p_map_offset_y: float  # This is often map_display.global_position.y
):
	_cached_actual_tile_width_on_texture = p_actual_tile_width_on_texture
	_cached_actual_tile_height_on_texture = p_actual_tile_height_on_texture
	_current_map_zoom_cache = p_current_map_zoom
	_cached_actual_scale = p_actual_scale # This should be the scale of the map_display texture itself
	_cached_offset_x = p_map_offset_x # Global X position of the map_display node
	_cached_offset_y = p_map_offset_y # Global Y position of the map_display node
	_ui_drawing_params_cached = (p_actual_tile_width_on_texture > 0.0 && p_actual_tile_height_on_texture > 0.0 && p_actual_scale > 0.0001)
	# print("ConvoyLabelManager: update_drawing_parameters called. _ui_drawing_params_cached set to: ", _ui_drawing_params_cached) # DEBUG


func get_active_convoy_panels_info() -> Array:
	var active_panels_info: Array = []
	for convoy_id_str in _active_convoy_panels:
		var panel_node = _active_convoy_panels[convoy_id_str]
		if is_instance_valid(panel_node) and panel_node.visible:
			var convoy_data = _convoy_data_by_id_cache.get(convoy_id_str) # Use the local cache
			if convoy_data: # Ensure data exists for the active panel
				active_panels_info.append({"panel": panel_node, "convoy_data": convoy_data})
	return active_panels_info

# --- Internal Helper Functions (moved from UIManager.gd) ---

func _create_convoy_panel(convoy_data: Dictionary) -> Panel:
	if not is_instance_valid(_convoy_label_container_ref):
		# printerr('ConvoyLabelManager: _convoy_label_container_ref is not valid. Cannot create convoy panel.')
		return null

	var current_convoy_id_orig = convoy_data.get('convoy_id')
	var current_convoy_id_str = str(current_convoy_id_orig)

	var panel := Panel.new()
	var style_box := StyleBoxFlat.new()
	panel.add_theme_stylebox_override('panel', style_box)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP # Panels are draggable
	panel.name = current_convoy_id_str
	panel.set_meta("convoy_id_str", current_convoy_id_str)
	panel.set_meta("style_box_ref", style_box)

	var label_node := Label.new()
	label_node.set('bbcode_enabled', true)
	label_node.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if is_instance_valid(_label_settings_ref): # Use the shared LabelSettings for base style
		label_node.label_settings = _label_settings_ref
	label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label_node)
	panel.set_meta("label_node_ref", label_node)

	return panel

func _update_convoy_panel_content(panel: Panel, convoy_data: Dictionary, p_convoy_id_to_color_map: Dictionary):
	if not is_instance_valid(panel):
		return

	var label_node: Label = panel.get_meta("label_node_ref")
	var style_box: StyleBoxFlat = panel.get_meta("style_box_ref")
	if not is_instance_valid(label_node) or not is_instance_valid(style_box):
		# printerr("ConvoyLabelManager: Panel is missing label_node_ref or style_box_ref metadata.")
		return

	# Font Size Calculation
	var effective_tile_size_on_texture: float = min(_cached_actual_tile_width_on_texture, _cached_actual_tile_height_on_texture)
	var base_linear_font_scale: float = 1.0
	if _font_scaling_base_tile_size > 0.001:
		base_linear_font_scale = effective_tile_size_on_texture / _font_scaling_base_tile_size
	var font_render_scale: float = pow(base_linear_font_scale, _font_scaling_exponent)

	# Use the specific base convoy title font size stored in this manager
	var adjusted_base_font_size = _base_convoy_title_font_size_ref * _ui_overall_scale_multiplier
	var scaled_target_screen_font_size = adjusted_base_font_size * font_render_scale
	var node_font_size_before_clamp = scaled_target_screen_font_size / _current_map_zoom_cache
	var current_convoy_title_font_size: int = clamp(roundi(node_font_size_before_clamp), _min_node_font_size, _max_node_font_size)

	var current_convoy_id_str = str(convoy_data.get('convoy_id'))

	# Panel appearance (using member variables for config)
	var adjusted_base_corner_radius = _base_convoy_panel_corner_radius * _ui_overall_scale_multiplier
	var scaled_target_screen_corner_radius = adjusted_base_corner_radius * font_render_scale
	var node_corner_radius_before_clamp = scaled_target_screen_corner_radius / _current_map_zoom_cache
	var current_panel_corner_radius: float = clamp(node_corner_radius_before_clamp, _min_node_panel_corner_radius, _max_node_panel_corner_radius)

	var adjusted_base_padding_h = _base_convoy_panel_padding_h * _ui_overall_scale_multiplier
	var scaled_target_screen_padding_h = adjusted_base_padding_h * font_render_scale
	var node_padding_h_before_clamp = scaled_target_screen_padding_h / _current_map_zoom_cache
	var current_panel_padding_h: float = clamp(node_padding_h_before_clamp, _min_node_panel_padding, _max_node_panel_padding)

	var adjusted_base_padding_v = _base_convoy_panel_padding_v * _ui_overall_scale_multiplier
	var scaled_target_screen_padding_v = adjusted_base_padding_v * font_render_scale
	var node_padding_v_before_clamp = scaled_target_screen_padding_v / _current_map_zoom_cache
	var current_panel_padding_v: float = clamp(node_padding_v_before_clamp, _min_node_panel_padding, _max_node_panel_padding)

	var adjusted_base_border_width = _base_convoy_panel_border_width * _ui_overall_scale_multiplier
	var scaled_target_screen_border_width = adjusted_base_border_width * font_render_scale
	var node_border_width_before_clamp = scaled_target_screen_border_width / _current_map_zoom_cache
	var current_panel_border_width: int = clamp(roundi(node_border_width_before_clamp), _min_node_panel_border_width, _max_node_panel_border_width)

	# Label Text Generation
	var efficiency: float = convoy_data.get('efficiency', 0.0)
	var top_speed: float = convoy_data.get('top_speed', 0.0)
	var offroad_capability: float = convoy_data.get('offroad_capability', 0.0)
	var convoy_name: String = convoy_data.get('convoy_name', 'N/A')
	var raw_journey = convoy_data.get('journey')
	var journey_data: Dictionary = {}
	if raw_journey is Dictionary:
		journey_data = raw_journey
	var progress: float = journey_data.get('progress', 0.0)

	var eta_raw_string: String = journey_data.get('eta', 'N/A')
	var _departure_raw_string_for_eta_format: String = journey_data.get('departure_time', 'N/A')
	var formatted_eta: String = "N/A" # Default
	# Avoid static-on-instance warning; fall back to raw string if needed
	if eta_raw_string != "N/A":
		formatted_eta = str(eta_raw_string)

	var progress_percentage_str: String = 'N/A'
	var length: float = journey_data.get('length', 0.0)
	if length > 0.001:
		var percentage: float = (progress / length) * 100.0
		progress_percentage_str = '%.1f%%' % percentage
	
	var label_text: String = '%s \n🏁 %s | ETA: %s\n%s %.1f | %s %.1f | %s %.1f' % [
			convoy_name, progress_percentage_str, formatted_eta,
			_CONVOY_STAT_EMOJIS_ref.get('efficiency', '?') if is_instance_valid(_CONVOY_STAT_EMOJIS_ref) else 'E', efficiency,
			_CONVOY_STAT_EMOJIS_ref.get('top_speed', '?') if is_instance_valid(_CONVOY_STAT_EMOJIS_ref) else 'S', top_speed,
			_CONVOY_STAT_EMOJIS_ref.get('offroad_capability', '?') if is_instance_valid(_CONVOY_STAT_EMOJIS_ref) else 'O', offroad_capability
		]

	# Update Label
	if not is_instance_valid(_label_settings_ref) or not is_instance_valid(_label_settings_ref.font):
		# printerr("ConvoyLabelManager: _label_settings_ref or its font is NOT VALID for convoy: ", convoy_name)
		# Fallback or return if critical settings are missing
		pass
	
	label_node.add_theme_font_size_override("font_size", current_convoy_title_font_size)
	label_node.text = label_text

	# Update Panel StyleBox
	var unique_convoy_color: Color = p_convoy_id_to_color_map.get(current_convoy_id_str, Color.GRAY)
	style_box.bg_color = _convoy_panel_background_color
	style_box.border_color = unique_convoy_color
	style_box.border_width_left = current_panel_border_width
	style_box.border_width_top = current_panel_border_width
	style_box.border_width_right = current_panel_border_width
	style_box.border_width_bottom = current_panel_border_width
	style_box.content_margin_left = current_panel_padding_h
	style_box.content_margin_right = current_panel_padding_h
	style_box.content_margin_top = current_panel_padding_v
	style_box.content_margin_bottom = current_panel_padding_v
	style_box.corner_radius_top_left = floori(current_panel_corner_radius)
	style_box.corner_radius_top_right = floori(current_panel_corner_radius)
	style_box.corner_radius_bottom_left = floori(current_panel_corner_radius)
	style_box.corner_radius_bottom_right = floori(current_panel_corner_radius)

	label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label_node.position = Vector2.ZERO 

	label_node.update_minimum_size() # Ensure label's min_size is current
	var label_actual_min_size = label_node.get_minimum_size()
	var stylebox_margins = style_box.get_minimum_size() # This is Vector2(left+right, top+bottom)

	panel.custom_minimum_size = Vector2(
		label_actual_min_size.x + stylebox_margins.x,
		label_actual_min_size.y + stylebox_margins.y
	)
	# print("ConvoyLabelManager (_update_convoy_panel_content) for %s: FontSz: %s, LabelMinSize: %s, PanelCustomMinSize: %s" % [panel.name, current_convoy_title_font_size, label_actual_min_size, panel.custom_minimum_size]) # DEBUG

	panel.update_minimum_size() # Notify panel to update its own minimum size based on custom_minimum_size


func _position_convoy_panel(panel: Panel, convoy_data: Dictionary, existing_label_rects: Array[Rect2], 
							p_selected_convoy_ids: Array, p_convoy_label_user_positions: Dictionary):
	if not is_instance_valid(panel):
		return

	var label_node: Label = panel.get_meta("label_node_ref")
	if not is_instance_valid(label_node): return

	var current_convoy_id_str = str(convoy_data.get('convoy_id'))
	var convoy_map_x: float = convoy_data.get('x', 0.0)
	var convoy_map_y: float = convoy_data.get('y', 0.0)

	# Diagnostic logging for convoy label placement
	print("[ConvoyLabelManager] Placing label for convoy_id:", current_convoy_id_str, "x:", convoy_map_x, "y:", convoy_map_y)

	# Horizontal Offset Calculation (in world units)
	var base_offset_value: float
	if p_selected_convoy_ids.has(current_convoy_id_str):
		base_offset_value = _base_selected_convoy_horizontal_offset
	else:
		base_offset_value = _base_horizontal_label_offset_from_center
	var current_horizontal_offset_world: float = base_offset_value * _ui_overall_scale_multiplier

	# Positioning Logic
	panel.update_minimum_size() # Ensure panel's minimum size is up-to-date
	var panel_actual_size = panel.size
	if panel_actual_size.x <= 0 or panel_actual_size.y <= 0:
		panel_actual_size = panel.get_minimum_size()
		print("[ConvoyLabelManager] Panel size is zero for convoy_id:", current_convoy_id_str)
	# Calculate convoy's center in local/world coordinates (relative to _convoy_label_container_ref's origin)
	# These are based on the unscaled map texture's tile dimensions.
	var convoy_center_local_x: float = (convoy_map_x + 0.5) * _cached_actual_tile_width_on_texture
	var convoy_center_local_y: float = (convoy_map_y + 0.5) * _cached_actual_tile_height_on_texture

	# Calculate panel's desired local/world position
	var panel_desired_local_x = convoy_center_local_x + current_horizontal_offset_world
	var panel_desired_local_y = convoy_center_local_y - (panel_actual_size.y / 2.0) # Vertically center panel against icon's y
	var panel_desired_local_pos = Vector2(panel_desired_local_x, panel_desired_local_y)
	print("[ConvoyLabelManager] Desired panel position for convoy_id:", current_convoy_id_str, panel_desired_local_pos)
	panel.position = panel_desired_local_pos

	# Apply user-defined position or anti-collision (all in local space of convoy_label_container)
	if p_selected_convoy_ids.has(current_convoy_id_str) and p_convoy_label_user_positions.has(current_convoy_id_str):
		panel.position = p_convoy_label_user_positions[current_convoy_id_str] # User positions are local
		print("[ConvoyLabelManager] Using user-defined position for convoy_id:", current_convoy_id_str, panel.position)
		var current_panel_rect = Rect2(panel.position, panel_actual_size)
		for _attempt in range(10): # Max attempts
			var collides_with_existing: bool = false
			var colliding_rect_for_shift_calc: Rect2 
			for existing_rect in existing_label_rects: # These are also local to container
				var buffered_existing_rect = existing_rect.grow_individual(2,2,2,2)
				if current_panel_rect.intersects(buffered_existing_rect, true):
					collides_with_existing = true
					colliding_rect_for_shift_calc = existing_rect
					break
			if collides_with_existing:
				var shift_based_on_collided_height = 0.0
				if colliding_rect_for_shift_calc.size.y > 0: # Check for valid Rect2
					shift_based_on_collided_height = colliding_rect_for_shift_calc.size.y * 0.25 + _label_map_edge_padding
				
				var label_min_size_for_shift = label_node.get_minimum_size()
				var y_shift_amount = _label_anti_collision_y_shift + max(label_min_size_for_shift.y * 0.1, shift_based_on_collided_height)
				
				panel.position.y += y_shift_amount
				current_panel_rect = Rect2(panel.position, panel_actual_size)
			else:
				break # No collision

	# print("ConvoyLabelManager (_position_convoy_panel) for %s: FinalLocalPos: %s" % [panel.name, panel.position]) # DEBUG


func _clamp_panel_position(panel: Panel, p_current_map_screen_rect_for_clamping: Rect2):
	if not is_instance_valid(panel) or not is_instance_valid(_convoy_label_container_ref):
		return

	var container_global_transform = _convoy_label_container_ref.get_global_transform_with_canvas()
	var clamp_rect_local_to_container = container_global_transform.affine_inverse() * p_current_map_screen_rect_for_clamping

	var panel_actual_size = panel.size
	if panel_actual_size.x <= 0 or panel_actual_size.y <= 0:
		panel_actual_size = panel.get_minimum_size()

	if panel_actual_size.x <= 0 or panel_actual_size.y <= 0:
		# printerr("ConvoyLabelManager: Cannot clamp panel %s due to invalid size: %s" % [panel.name, panel_actual_size])
		return

	var padded_min_x = clamp_rect_local_to_container.position.x + _label_map_edge_padding
	var padded_min_y = clamp_rect_local_to_container.position.y + _label_map_edge_padding
	var padded_max_x = clamp_rect_local_to_container.end.x - panel_actual_size.x - _label_map_edge_padding
	var padded_max_y = clamp_rect_local_to_container.end.y - panel_actual_size.y - _label_map_edge_padding
	
	padded_max_x = max(padded_min_x, padded_max_x)
	padded_max_y = max(padded_min_y, padded_max_y)

	panel.position.x = clamp(panel.position.x, padded_min_x, padded_max_x)
	panel.position.y = clamp(panel.position.y, padded_min_y, padded_max_y)


func update_convoy_labels(
	p_all_convoy_data: Array,
	p_convoy_id_to_color_map: Dictionary,
	p_current_hover_info: Dictionary,
	p_selected_convoy_ids: Array, # Expected array of strings
	p_convoy_label_user_positions: Dictionary,
	p_dragging_panel_node: Panel, # The actual panel node being dragged, if any
	p_dragged_convoy_id_actual_str: String, # The ID of the convoy whose panel is being dragged
	p_current_map_screen_rect_for_clamping: Rect2
	# Style parameters are now member variables, set by initialize_style_settings
):

	if not _ui_drawing_params_cached:
		# print("ConvoyLabelManager (update_convoy_labels): Drawing parameters NOT cached. Bailing out.") # DEBUG
		# Hide all active panels if drawing params are invalid, as positions would be wrong.
		for panel_node in _active_convoy_panels.values():
			if is_instance_valid(panel_node):
				# print("ConvoyLabelManager (update_convoy_labels): Hiding panel %s due to bad drawing params." % panel_node.name) # DEBUG
				panel_node.visible = false
		return

	# Update local convoy data cache
	_convoy_data_by_id_cache.clear()
	if p_all_convoy_data is Array:
		for convoy_data_item in p_all_convoy_data:
			if convoy_data_item is Dictionary and convoy_data_item.has("convoy_id"):
				_convoy_data_by_id_cache[str(convoy_data_item.get("convoy_id"))] = convoy_data_item
	# print("ConvoyLabelManager (update_convoy_labels): _convoy_data_by_id_cache populated. Size: ", _convoy_data_by_id_cache.size()) # DEBUG

	var drawn_convoy_ids_this_update: Array[String] = []
	var all_drawn_label_rects_this_update: Array[Rect2] = []

	var convoy_ids_to_display: Array[String] = []

	# Determine which convoy IDs to display based on selection
	if p_selected_convoy_ids is Array:
		for sel_id_str in p_selected_convoy_ids:
			if not convoy_ids_to_display.has(sel_id_str):
				convoy_ids_to_display.append(sel_id_str)

	# Add hovered convoy ID
	if p_current_hover_info.get('type') == 'convoy':
		var hovered_convoy_id_variant = p_current_hover_info.get('id')
		if hovered_convoy_id_variant != null:
			var hovered_convoy_id_as_string = str(hovered_convoy_id_variant)
			if not hovered_convoy_id_as_string.is_empty() and not convoy_ids_to_display.has(hovered_convoy_id_as_string):
				convoy_ids_to_display.append(hovered_convoy_id_as_string)
	# print("ConvoyLabelManager (update_convoy_labels): Received SelectedIDs: %s, HoverInfo: %s. Resulting convoy_ids_to_display: %s" % [p_selected_convoy_ids, p_current_hover_info, convoy_ids_to_display]) # DEBUG


	# Handle the currently dragged panel first (if any)
	if is_instance_valid(p_dragging_panel_node) and not p_dragged_convoy_id_actual_str.is_empty():
		var dragged_convoy_data = _convoy_data_by_id_cache.get(p_dragged_convoy_id_actual_str)
		if dragged_convoy_data:
			# Ensure the dragged panel is in our active list and its container
			if not _active_convoy_panels.has(p_dragged_convoy_id_actual_str) or _active_convoy_panels[p_dragged_convoy_id_actual_str] != p_dragging_panel_node:
				_active_convoy_panels[p_dragged_convoy_id_actual_str] = p_dragging_panel_node
				if p_dragging_panel_node.get_parent() != _convoy_label_container_ref:
					if p_dragging_panel_node.get_parent(): p_dragging_panel_node.get_parent().remove_child(p_dragging_panel_node)
					_convoy_label_container_ref.add_child(p_dragging_panel_node)
			
			p_dragging_panel_node.visible = true
			_update_convoy_panel_content(p_dragging_panel_node, dragged_convoy_data, p_convoy_id_to_color_map)
			# Dragging panel's position is handled by MapInteractionManager/main.gd, but we still need its rect for anti-collision
			# and clamping.
			_clamp_panel_position(p_dragging_panel_node, p_current_map_screen_rect_for_clamping)
			
			var dragged_panel_actual_size = p_dragging_panel_node.size
			if dragged_panel_actual_size.x <= 0 or dragged_panel_actual_size.y <= 0:
				dragged_panel_actual_size = p_dragging_panel_node.get_minimum_size()
			all_drawn_label_rects_this_update.append(Rect2(p_dragging_panel_node.position, dragged_panel_actual_size))
			
			if not drawn_convoy_ids_this_update.has(p_dragged_convoy_id_actual_str):
				drawn_convoy_ids_this_update.append(p_dragged_convoy_id_actual_str)

	# Process other convoy labels that need to be displayed
	for convoy_id_str_to_display in convoy_ids_to_display:
		if convoy_id_str_to_display == p_dragged_convoy_id_actual_str:
			continue # Already handled if being dragged

		var convoy_data = _convoy_data_by_id_cache.get(convoy_id_str_to_display)
		if not convoy_data: continue

		var panel_node: Panel
		if _active_convoy_panels.has(convoy_id_str_to_display):
			panel_node = _active_convoy_panels[convoy_id_str_to_display]
			if not is_instance_valid(panel_node): # Recreate if somehow invalid
				_active_convoy_panels.erase(convoy_id_str_to_display) # Remove bad ref
				panel_node = _create_convoy_panel(convoy_data)
				if not is_instance_valid(panel_node): continue
				_active_convoy_panels[convoy_id_str_to_display] = panel_node
				_convoy_label_container_ref.add_child(panel_node)
		else:
			panel_node = _create_convoy_panel(convoy_data)
			if not is_instance_valid(panel_node): continue
			_active_convoy_panels[convoy_id_str_to_display] = panel_node
			_convoy_label_container_ref.add_child(panel_node)

		panel_node.visible = true
		_update_convoy_panel_content(panel_node, convoy_data, p_convoy_id_to_color_map)
		_position_convoy_panel(panel_node, convoy_data, all_drawn_label_rects_this_update, p_selected_convoy_ids, p_convoy_label_user_positions)
		_clamp_panel_position(panel_node, p_current_map_screen_rect_for_clamping)

		var panel_actual_size = panel_node.size
		if panel_actual_size.x <= 0 or panel_actual_size.y <= 0: panel_actual_size = panel_node.get_minimum_size()
		all_drawn_label_rects_this_update.append(Rect2(panel_node.position, panel_actual_size))
		drawn_convoy_ids_this_update.append(convoy_id_str_to_display)

	# Hide panels that are no longer needed
	# var _ids_to_remove_from_active: Array[String] = [] # Keep for future cleanup logic if needed
	for existing_id_str in _active_convoy_panels.keys():
		if not drawn_convoy_ids_this_update.has(existing_id_str):
			var panel_to_hide = _active_convoy_panels[existing_id_str]
			if is_instance_valid(panel_to_hide):
				panel_to_hide.visible = false
			# Optionally, if you want to fully remove panels not used for a while:
			# panel_to_hide.queue_free()
			# _ids_to_remove_from_active.append(existing_id_str) 
	# for id_to_remove in _ids_to_remove_from_active:
		# _active_convoy_panels.erase(id_to_remove)

func _on_ui_scale_changed(new_scale: float):
	_ui_overall_scale_multiplier = new_scale
	# No redraw logic needed here. UIManager's signal handler will trigger a full update,
	# which will call update_convoy_labels, and this manager will use the new scale value.
