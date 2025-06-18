extends Node2D

# References to label containers managed by UIManager
# These should be children of the Node this script is attached to.
@export_group("Global UI Scaling")
## Multiplier to adjust the overall perceived size of UI labels and panels. 1.0 = default.
@export var ui_overall_scale_multiplier: float = 1.0

# Path corrected: From UIManagerNode, up two levels to MapRender, then down to MapContainer/SettlementLabelContainer.
@onready var settlement_label_container: Node2D = get_node("../../MapContainer/SettlementLabelContainer")
# Path corrected: From UIManagerNode (child of ScreenSpaceUI, child of MapRender)
# up to MapRender, then down to MapContainer, then to ConvoyConnectorLinesContainer.
# Adjust ../../ if UIManagerNode is nested differently under ScreenSpaceUI.
@onready var convoy_connector_lines_container: Node2D = get_node("../../MapContainer/ConvoyConnectorLinesContainer")
# @onready var convoy_label_container: Node2D = get_node("../../MapContainer/ConvoyLabelContainer") # Moved to ConvoyLabelManager
# Path corrected: ConvoyLabelContainer is also under MapContainer.
@onready var convoy_label_container: Node2D = get_node("../../MapContainer/ConvoyLabelContainer")

# Label settings and default font (will be initialized in _ready)
var label_settings: LabelSettings
var settlement_label_settings: LabelSettings

# --- UI Constants (copied and consolidated from main.gd) ---
@export_group("Font Scaling")
## Target screen font size for convoy titles (if font_render_scale and map_zoom are 1.0). Adjust for desired on-screen readability. (Prev: 12)
@export var base_convoy_title_font_size: int = 15 # 12 * 1.25
## Target screen font size for settlement labels (if font_render_scale and map_zoom are 1.0). Adjust for desired on-screen readability. (Prev: 10)
@export var base_settlement_font_size: int = 13 # 10 * 1.25 = 12.5, rounded to 13
## Minimum font size to set on the Label node.
@export var min_node_font_size: int = 8
## Maximum font size to set on the Label node.
@export var max_node_font_size: int = 120 # Increased from 60
## The map tile size that font scaling is based on. Should ideally match map_render's base_tile_size_for_proportions.
@export var font_scaling_base_tile_size: float = 24.0 
## Exponent for font scaling (1.0 = linear, <1.0 less aggressive shrink/grow).
@export var font_scaling_exponent: float = 0.6 

@export_group("Label Offsets")
## Base horizontal offset from the convoy's center for its label panel. Scaled.
@export var base_horizontal_label_offset_from_center: float = 15.0 
## Base horizontal offset for selected convoy label panels. Scaled.
@export var base_selected_convoy_horizontal_offset: float = 60.0 
## Base vertical offset above the settlement's tile center for its label panel. Scaled.
@export var base_settlement_offset_above_tile_center: float = 10.0 

@export_group("Convoy Panel Appearance")
## Target screen corner radius for convoy label panels. Adjust for desired on-screen look. (Prev: 4.0)
@export var base_convoy_panel_corner_radius: float = 5.0 # 4.0 * 1.25
## Target screen horizontal padding inside convoy label panels. Adjust for desired on-screen look. (Prev: 4.0)
@export var base_convoy_panel_padding_h: float = 5.0 # 4.0 * 1.25
## Target screen vertical padding inside convoy label panels. Adjust for desired on-screen look. (Prev: 2.0)
@export var base_convoy_panel_padding_v: float = 2.5 # 2.0 * 1.25
## Background color for convoy label panels.
@export var convoy_panel_background_color: Color = Color(0.12, 0.12, 0.15, 0.88) 
## Target screen border width for convoy label panels. Adjust for desired on-screen look. (Prev: 1.0)
@export var base_convoy_panel_border_width: float = 1.25 # 1.0 * 1.25
## Minimum corner radius to set on the panel node.
@export var min_node_panel_corner_radius: float = 1.0
## Maximum corner radius to set on the panel node.
@export var max_node_panel_corner_radius: float = 32.0 # Increased from 16.0
## Minimum padding to set on the panel node.
@export var min_node_panel_padding: float = 1.0
## Maximum padding to set on the panel node.
@export var max_node_panel_padding: float = 40.0 # Increased from 20.0
## Minimum border width to set on the panel node.
@export var min_node_panel_border_width: int = 1
## Maximum border width to set on the panel node.
@export var max_node_panel_border_width: int = 12 # Increased from 6

@export_group("Settlement Panel Appearance")
## Target screen corner radius for settlement label panels. Adjust for desired on-screen look. (Prev: 3.0)
@export var base_settlement_panel_corner_radius: float = 3.75 # 3.0 * 1.25
## Target screen horizontal padding inside settlement label panels. Adjust for desired on-screen look. (Prev: 3.0)
@export var base_settlement_panel_padding_h: float = 3.75 # 3.0 * 1.25
## Target screen vertical padding inside settlement label panels. Adjust for desired on-screen look. (Prev: 2.0)
@export var base_settlement_panel_padding_v: float = 2.5 # 2.0 * 1.25
## Background color for settlement label panels.
@export var settlement_panel_background_color: Color = Color(0.15, 0.12, 0.12, 0.85) 

@export_group("Label Positioning")
## Amount to shift a label panel vertically to avoid collision with another.
@export var label_anti_collision_y_shift: float = 5.0 
## Padding from the viewport edges (in pixels) used to clamp label panels.
@export var label_map_edge_padding: float = 5.0 

# Data constants, not typically exported for Inspector editing
const CONVOY_STAT_EMOJIS: Dictionary = {
	'efficiency': '🌿',
	'top_speed': '🚀',
	'offroad_capability': '🥾',
}

const SETTLEMENT_EMOJIS: Dictionary = {
	'dome': '🏙️',
	'city': '🏢',
	'city-state': '🏢',
	'town': '🏘️',
	'village': '🏠',
	'military_base': '🪖',
}

# --- Connector Line constants ---
@export_group("Connector Lines")
## Color for lines connecting convoy icons to their label panels.
@export var connector_line_color: Color = Color(0.9, 0.9, 0.9, 0.6) 
## Width of the connector lines.
@export var connector_line_width: float = 1.5 

# --- State managed by UIManager ---
var _dragging_panel_node: Panel = null
var _drag_offset: Vector2 = Vector2.ZERO
var _convoy_label_user_positions: Dictionary = {} # Stores user-set positions: { 'convoy_id_str': Vector2(x,y) }
var _dragged_convoy_id_actual_str: String = ""
var _current_drag_clamp_rect: Rect2

# Data passed from main.gd during updates
var _map_display_node: TextureRect # Reference to the MapDisplay node from main
var _map_tiles_data: Array
var _all_convoy_data_cache: Array
var _all_settlement_data_cache: Array
var _convoy_id_to_color_map_cache: Dictionary
var _convoy_data_by_id_cache: Dictionary # New cache for quick lookup
var _selected_convoy_ids_cache: Array # Stored as strings
var _current_map_zoom_cache: float = 1.0 # Cache for current map zoom level

var _current_map_screen_rect_for_clamping: Rect2
# Cached drawing parameters for connector lines
var _cached_actual_scale: float = 1.0
var _cached_offset_x: float = 0.0
var _cached_offset_y: float = 0.0
var _cached_actual_tile_width_on_texture: float = 0.0
var _cached_actual_tile_height_on_texture: float = 0.0
var _ui_drawing_params_cached: bool = false

# --- Active Panel Management for Optimization ---
# var _active_convoy_panels: Dictionary = {}  # { "convoy_id_str": PanelNode } # Moved to ConvoyLabelManager
@onready var convoy_label_manager: Node = $ConvoyLabelManagerNode # Assuming this path
var _active_settlement_panels: Dictionary = {} # { "tile_coord_str": PanelNode }

# Z-index for label containers within MapContainer, relative to MapDisplay and ConvoyNodes
const LABEL_CONTAINER_Z_INDEX = 2


func _ready():
	# Critical: Ensure child containers are valid and print their status
	# print("UIManager _ready: Checking child containers...")
	# print("  - settlement_label_container: %s (Valid: %s)" % [settlement_label_container, is_instance_valid(settlement_label_container)])
	# print("  - convoy_connector_lines_container: %s (Valid: %s)" % [convoy_connector_lines_container, is_instance_valid(convoy_connector_lines_container)])
	# print("  - convoy_label_container: %s (Valid: %s)" % [convoy_label_container, is_instance_valid(convoy_label_container)])

	# Ensure containers are visible
	if is_instance_valid(settlement_label_container):
		settlement_label_container.visible = true
		settlement_label_container.z_index = LABEL_CONTAINER_Z_INDEX
	if is_instance_valid(convoy_connector_lines_container):
		convoy_connector_lines_container.visible = true
		convoy_connector_lines_container.z_index = LABEL_CONTAINER_Z_INDEX # Connectors at the same level as labels
	# if is_instance_valid(convoy_label_container): # Managed by ConvoyLabelManager
	# 	convoy_label_container.visible = true
	# 	convoy_label_container.z_index = LABEL_CONTAINER_Z_INDEX
	_current_map_screen_rect_for_clamping = get_viewport().get_visible_rect() # Initialize
		

	# Initialize label settings
	label_settings = LabelSettings.new()
	settlement_label_settings = LabelSettings.new()

	label_settings.font_color = Color.WHITE
	label_settings.outline_size = 6
	label_settings.outline_color = Color.BLACK
	settlement_label_settings.font_color = Color.WHITE
	settlement_label_settings.outline_size = 3
	settlement_label_settings.outline_color = Color.BLACK

	if is_instance_valid(convoy_connector_lines_container):
		convoy_connector_lines_container.draw.connect(_on_connector_lines_container_draw)
		# print("UIManager: Connected to ConvoyConnectorLinesContainer draw signal.")
	else:
		printerr("UIManager: ConvoyConnectorLinesContainer not ready or invalid in _ready().")

	# Programmatically assign the convoy_label_container to the ConvoyLabelManager
	if is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("set_convoy_label_container"):
		if is_instance_valid(convoy_label_container):
			convoy_label_manager.set_convoy_label_container(convoy_label_container)
		else:
			printerr("UIManager: Cannot assign convoy_label_container to ConvoyLabelManager because UIManager's own reference to convoy_label_container is invalid.")


func initialize_font_settings(theme_font_to_use: Font):
	if theme_font_to_use:
		label_settings.font = theme_font_to_use # LabelSettings objects are shared
		settlement_label_settings.font = theme_font_to_use # LabelSettings objects are shared
		# print("UIManager: Using theme font for labels provided by main: ", theme_font_to_use.resource_path if theme_font_to_use.resource_path else "Built-in font")
	else:
		# If no font is passed, LabelSettings will not have a font set,
		# and Labels will use their default/themed font.
		print("UIManager: No theme font provided by main. Labels will use their default theme font if LabelSettings.font is not set.")
	
	if is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("initialize_font_settings"):
		convoy_label_manager.initialize_font_settings(theme_font_to_use, label_settings, 
													  base_convoy_title_font_size, # Pass the specific base font size for convoys
													  ui_overall_scale_multiplier, 
													  font_scaling_base_tile_size, font_scaling_exponent, 
													  min_node_font_size, max_node_font_size,
													  _all_convoy_data_cache if _all_convoy_data_cache else [], CONVOY_STAT_EMOJIS)

	if is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("initialize_style_settings"):
		convoy_label_manager.initialize_style_settings(
			base_convoy_panel_corner_radius, min_node_panel_corner_radius, max_node_panel_corner_radius,
			base_convoy_panel_padding_h, base_convoy_panel_padding_v,
			min_node_panel_padding, max_node_panel_padding,
			base_convoy_panel_border_width, min_node_panel_border_width, max_node_panel_border_width,
			convoy_panel_background_color,
			base_selected_convoy_horizontal_offset, base_horizontal_label_offset_from_center,
			label_map_edge_padding, label_anti_collision_y_shift
		)
	# else: # DEBUG
		# printerr("UIManager: ConvoyLabelManager is invalid or missing 'initialize_style_settings'. CLM valid: %s" % is_instance_valid(convoy_label_manager))


func update_ui_elements(
		map_display_node_ref: TextureRect,
		current_map_tiles: Array,
		all_convoy_data: Array,
		all_settlement_data: Array,
		convoy_id_to_color_map: Dictionary,
		current_hover_info: Dictionary,
		selected_convoy_ids: Array, # Expecting array of strings
		convoy_label_user_positions_from_main: Dictionary, 
		dragging_panel_node_from_main: Panel, 
		dragged_convoy_id_str_from_main: String,
		p_current_map_screen_rect_for_clamping: Rect2, # Moved before optional params
		is_light_ui_update: bool = false,
		current_map_zoom: float = 1.0 # Now 13th argument
	):
	# Store references to data needed by drawing functions
	_map_display_node = map_display_node_ref
	_map_tiles_data = current_map_tiles
	_all_convoy_data_cache = all_convoy_data
	_all_settlement_data_cache = all_settlement_data
	_convoy_id_to_color_map_cache = convoy_id_to_color_map
	_selected_convoy_ids_cache = selected_convoy_ids

	_current_map_screen_rect_for_clamping = p_current_map_screen_rect_for_clamping
	# Rebuild the convoy_data_by_id_cache for faster lookups
	_convoy_data_by_id_cache.clear()
	if _all_convoy_data_cache is Array:
		for convoy_data_item in _all_convoy_data_cache:
			if convoy_data_item is Dictionary and convoy_data_item.has("convoy_id"):
				_convoy_data_by_id_cache[str(convoy_data_item.get("convoy_id"))] = convoy_data_item

	_current_map_zoom_cache = current_map_zoom # Cache the zoom level

	# Cache drawing parameters for _on_connector_lines_container_draw
	if is_instance_valid(_map_display_node) and is_instance_valid(_map_display_node.texture) and \
	   _map_tiles_data and not _map_tiles_data.is_empty() and _map_tiles_data[0] is Array and not _map_tiles_data[0].is_empty():
		
		var map_texture_size: Vector2 = _map_display_node.texture.get_size()
		var map_display_rect_size: Vector2 = _map_display_node.size

		if map_texture_size.x > 0.001 and map_texture_size.y > 0.001:
			var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
			var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y
			_cached_actual_scale = min(scale_x_ratio, scale_y_ratio)

			var displayed_texture_width: float = map_texture_size.x * _cached_actual_scale
			var displayed_texture_height: float = map_texture_size.y * _cached_actual_scale
			_cached_offset_x = (_map_display_node.size.x - displayed_texture_width) / 2.0
			_cached_offset_y = (_map_display_node.size.y - displayed_texture_height) / 2.0

			var map_image_cols: int = _map_tiles_data[0].size()
			var map_image_rows: int = _map_tiles_data.size()
			if map_image_cols > 0 and map_image_rows > 0:
				_cached_actual_tile_width_on_texture = map_texture_size.x / float(map_image_cols)
				_cached_actual_tile_height_on_texture = map_texture_size.y / float(map_image_rows)
				_ui_drawing_params_cached = true
			else:
				_ui_drawing_params_cached = false # map_image_cols or rows is zero
		else:
			_ui_drawing_params_cached = false # map_texture_size is zero

		# print("UIManager: In update_ui_elements. UIManager._ui_drawing_params_cached: ", _ui_drawing_params_cached) # DEBUG
		# print("UIManager: convoy_label_manager valid: ", is_instance_valid(convoy_label_manager), ", has update_drawing_parameters: ", convoy_label_manager.has_method("update_drawing_parameters") if is_instance_valid(convoy_label_manager) else "N/A") # DEBUG

		# Pass the calculated drawing parameters to ConvoyLabelManager
		if is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("update_drawing_parameters"):
			# UIManager's _ui_drawing_params_cached ensures tile_width/height_on_texture are valid.
			# ConvoyLabelManager needs the map_display's global on-screen scale and offset.
			if _ui_drawing_params_cached and is_instance_valid(_map_display_node):
				var map_display_global_transform = _map_display_node.get_global_transform_with_canvas()
				# This is the visual scale of the map_display node on the screen (affected by camera)
				var clm_actual_scale = map_display_global_transform.get_scale().x # Assuming uniform scale
				# This is the global screen position of the map_display node's top-left corner
				var clm_offset = map_display_global_transform.get_origin()

				convoy_label_manager.update_drawing_parameters(
					_cached_actual_tile_width_on_texture,  # Tile width on original unscaled texture
					_cached_actual_tile_height_on_texture, # Tile height on original unscaled texture
					_current_map_zoom_cache,               # Camera zoom (used for inverse scaling of UI elements)
					clm_actual_scale,                      # Actual visual scale of map_display content on screen
					clm_offset.x,                          # Actual screen X position of map_display's origin
					clm_offset.y                           # Actual screen Y position of map_display's origin
				)
			else: # DEBUG
				# print("UIManager: Condition NOT MET to call convoy_label_manager.update_drawing_parameters. UIM_cached: %s, map_display_valid: %s" % [_ui_drawing_params_cached, is_instance_valid(_map_display_node)]) # DEBUG
				pass
	else:
		_ui_drawing_params_cached = false # map_display_node, texture, or map_tiles_data invalid
		# print("UIManager: In update_ui_elements. _map_display_node, texture, or _map_tiles_data invalid. UIManager._ui_drawing_params_cached: false") # DEBUG
		if is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("update_drawing_parameters"):
			# Explicitly tell CLM its params are not valid if UIM's are not.
			# This might involve setting a flag in CLM or passing invalid values.
			# For now, we just don't call its update_drawing_parameters if UIM's are bad.
			pass

	# Update UIManager's state from what main.gd passes
	_convoy_label_user_positions = convoy_label_user_positions_from_main
	_dragging_panel_node = dragging_panel_node_from_main
	_dragged_convoy_id_actual_str = dragged_convoy_id_str_from_main

	if is_light_ui_update:
		_perform_light_ui_update()
	else:
		_draw_interactive_labels(current_hover_info)
		
	# Delegate convoy label updates to ConvoyLabelManager.
	# NOTE: The 'update_convoy_labels' method needs to be implemented in ConvoyLabelManager.gd.
	# Its signature should be adjusted to not expect drawing parameters that are now set
	# via 'update_drawing_parameters'.
	if is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("update_convoy_labels"):
		convoy_label_manager.update_convoy_labels(
			_all_convoy_data_cache,
			_convoy_id_to_color_map_cache,
			current_hover_info,
			_selected_convoy_ids_cache,
			_convoy_label_user_positions, # This state might also move to ConvoyLabelManager
			_dragging_panel_node,         # Drag state might be passed or ConvoyLabelManager handles its own
			_dragged_convoy_id_actual_str,
			_current_map_screen_rect_for_clamping,
			# Style parameters are no longer passed here as they are set via initialize_style_settings.
			# CONVOY_STAT_EMOJIS is also set via initialize_font_settings.
		)

	# Request redraw for connector lines
	if is_instance_valid(convoy_connector_lines_container):
		convoy_connector_lines_container.queue_redraw()


func _perform_light_ui_update():
	"""
	Called during pan/zoom. Avoids destroying/recreating labels.
	Focuses on re-clamping existing labels to viewport.
	"""
	if not _map_display_node or not is_instance_valid(_map_display_node):
		printerr("UIManager (_perform_light_ui_update): _map_display_node is invalid.")
		return

	# Use the map's effective screen rect for clamping calculations
	var viewport_rect_global = _current_map_screen_rect_for_clamping

	# if is_instance_valid(convoy_label_container) and convoy_label_container.get_child_count() > 0: # Handled by ConvoyLabelManager
	# 	var container_global_transform_convoy = convoy_label_container.get_global_transform_with_canvas()
	# 	var clamp_rect_local_to_convoy_container = container_global_transform_convoy.affine_inverse() * viewport_rect_global

	# 	for panel_node in convoy_label_container.get_children():
	# 		if panel_node is Panel:
	# 			_clamp_panel_position_optimized(panel_node, clamp_rect_local_to_convoy_container)

	if is_instance_valid(settlement_label_container) and settlement_label_container.get_child_count() > 0:
		var container_global_transform_settlement = settlement_label_container.get_global_transform_with_canvas()
		var clamp_rect_local_to_settlement_container = container_global_transform_settlement.affine_inverse() * viewport_rect_global

		for panel_node in settlement_label_container.get_children():
			if panel_node is Panel:
				_clamp_panel_position_optimized(panel_node, clamp_rect_local_to_settlement_container)

func _clamp_panel_position_optimized(panel: Panel, precalculated_clamp_rect_local_to_container: Rect2):
	"""
	Helper to clamp a panel's position to the viewport boundaries,
	using a precalculated clamping rectangle in the panel's parent container's local space.
	"""
	if not is_instance_valid(panel):
		return

	var panel_actual_size = panel.size
	if panel_actual_size.x <= 0 or panel_actual_size.y <= 0:
		panel_actual_size = panel.get_minimum_size()

	var padded_min_x = precalculated_clamp_rect_local_to_container.position.x + label_map_edge_padding
	var padded_min_y = precalculated_clamp_rect_local_to_container.position.y + label_map_edge_padding
	var padded_max_x = precalculated_clamp_rect_local_to_container.position.x + precalculated_clamp_rect_local_to_container.size.x - panel_actual_size.x - label_map_edge_padding
	var padded_max_y = precalculated_clamp_rect_local_to_container.position.y + precalculated_clamp_rect_local_to_container.size.y - panel_actual_size.y - label_map_edge_padding

	panel.position.x = clamp(panel.position.x, padded_min_x, padded_max_x)
	panel.position.y = clamp(panel.position.y, padded_min_y, padded_max_y)

func _clamp_panel_position(panel: Panel): # Original function, now less used but kept for potential direct calls
	"""Helper to clamp a panel's position to the viewport boundaries."""
	if not is_instance_valid(panel) or not is_instance_valid(panel.get_parent()):
		return

	var container_node = panel.get_parent() # e.g., ConvoyLabelContainer
	# Use the map's effective screen rect for clamping calculations
	var viewport_rect_global = _current_map_screen_rect_for_clamping

	var container_global_transform = container_node.get_global_transform_with_canvas()
	var clamp_rect_local_to_container = container_global_transform.affine_inverse() * viewport_rect_global

	var panel_actual_size = panel.size
	if panel_actual_size.x <= 0 or panel_actual_size.y <= 0:
		panel_actual_size = panel.get_minimum_size()

	var padded_min_x = clamp_rect_local_to_container.position.x + label_map_edge_padding
	var padded_min_y = clamp_rect_local_to_container.position.y + label_map_edge_padding
	var padded_max_x = clamp_rect_local_to_container.position.x + clamp_rect_local_to_container.size.x - panel_actual_size.x - label_map_edge_padding
	var padded_max_y = clamp_rect_local_to_container.position.y + clamp_rect_local_to_container.size.y - panel_actual_size.y - label_map_edge_padding

	panel.position.x = clamp(panel.position.x, padded_min_x, padded_max_x)
	panel.position.y = clamp(panel.position.y, padded_min_y, padded_max_y)

func _draw_interactive_labels(current_hover_info: Dictionary):
	# print("UIManager: _draw_interactive_labels called. Hover: ", current_hover_info) # DEBUG
	# print("UIManager: Cached convoy data size: ", _all_convoy_data_cache.size() if _all_convoy_data_cache else "N/A") # DEBUG
	# print("UIManager: Cached settlement data size: ", _all_settlement_data_cache.size() if _all_settlement_data_cache else "N/A") # DEBUG
	# print("UIManager: Cached selected IDs: ", _selected_convoy_ids_cache) # DEBUG
	if is_instance_valid(_dragging_panel_node):
		# If a panel is being dragged, UIManager might still need to update settlement labels.
		# ConvoyLabelManager would internally handle not disturbing the dragged convoy panel.
		pass # Let's assume main.gd already checked this or UIManager will handle it.
	
	if not _ui_drawing_params_cached: # Use the cached flag
		printerr("UIManager: MapDisplay node or texture invalid. Cannot draw labels.")
		return
	var drawn_convoy_ids_this_update: Array[String] = []
	var drawn_settlement_tile_coords_this_update: Array[Vector2i] = []
	var all_drawn_label_rects_this_update: Array[Rect2] = [] # This will be used by SettlementLabelManager and ConvoyLabelManager internally or passed to them
	
	# Declare arrays to hold IDs/coords of elements that *should* be visible
	# print("UIManager:_draw_interactive_labels - current_hover_info: ", current_hover_info) # DEBUG
	var convoy_ids_to_display: Array[String] = []
	var settlement_coords_to_display: Array[Vector2i] = []

	# STAGE 1: Draw Settlement Labels (for selected convoys' start/end, then hovered settlement)
	if not _selected_convoy_ids_cache.is_empty():
		for convoy_data in _all_convoy_data_cache:
			if convoy_data is Dictionary:
				var convoy_id = convoy_data.get('convoy_id')
				var convoy_id_str = str(convoy_id)
				if convoy_id != null and _selected_convoy_ids_cache.has(convoy_id_str):
					# For selected convoys, identify their start and end settlement tiles
					var journey_data: Dictionary = convoy_data.get('journey')
					if journey_data is Dictionary:
						# var route_x_coords: Array = journey_data.get('route_x', []) # Old way
						# var route_y_coords: Array = journey_data.get('route_y', []) # Old way

						var raw_route_x = journey_data.get('route_x')
						var route_x_coords: Array = []
						if raw_route_x is Array:
							route_x_coords = raw_route_x

						var raw_route_y = journey_data.get('route_y')
						var route_y_coords: Array = []
						if raw_route_y is Array:
							route_y_coords = raw_route_y
							
						if route_x_coords is Array and route_y_coords is Array and \
						   route_x_coords.size() == route_y_coords.size() and not route_x_coords.is_empty():
							
							var start_tile_x: int = floori(float(route_x_coords[0]))
							var start_tile_y: int = floori(float(route_y_coords[0]))
							var start_tile_coords := Vector2i(start_tile_x, start_tile_y)
							if not settlement_coords_to_display.has(start_tile_coords):
								settlement_coords_to_display.append(start_tile_coords)

							if route_x_coords.size() > 0:
								var end_tile_x: int = floori(float(route_x_coords.back()))
								var end_tile_y: int = floori(float(route_y_coords.back()))
								var end_tile_coords := Vector2i(end_tile_x, end_tile_y)
								if end_tile_coords != start_tile_coords and \
								   not settlement_coords_to_display.has(end_tile_coords):
									settlement_coords_to_display.append(end_tile_coords)

	# Ensure hovered settlement coords are added
	if current_hover_info.get('type') == 'settlement':
		var hovered_tile_coords = current_hover_info.get('coords')
		if hovered_tile_coords is Vector2i and hovered_tile_coords.x >= 0 and hovered_tile_coords.y >= 0:
			if not settlement_coords_to_display.has(hovered_tile_coords):
				settlement_coords_to_display.append(hovered_tile_coords)


	# STAGE 2: Determine Convoy Labels to Display (Selected then Hovered)
	if not _selected_convoy_ids_cache.is_empty():
		for convoy_data in _all_convoy_data_cache:
			if convoy_data is Dictionary:
				var convoy_id = convoy_data.get('convoy_id')
				var convoy_id_str = str(convoy_id)
				if convoy_id != null and _selected_convoy_ids_cache.has(convoy_id_str):
					if not convoy_ids_to_display.has(convoy_id_str):
						convoy_ids_to_display.append(convoy_id_str)

	# Ensure hovered convoy ID is added as a string
	if current_hover_info.get('type') == 'convoy':
		var hovered_convoy_id_variant = current_hover_info.get('id')
		if hovered_convoy_id_variant != null:
			var hovered_convoy_id_as_string = str(hovered_convoy_id_variant)
			if not hovered_convoy_id_as_string.is_empty(): # Check after converting to string
				if not convoy_ids_to_display.has(hovered_convoy_id_as_string):
					convoy_ids_to_display.append(hovered_convoy_id_as_string)

	# print("UIManager:_draw_interactive_labels - convoy_ids_to_display: ", convoy_ids_to_display) # DEBUG
	# print("UIManager:_draw_interactive_labels - settlement_coords_to_display: ", settlement_coords_to_display) # DEBUG # This part remains for settlements

	# STAGE 3: Handle the dragged panel first (ensure its rect is considered and it remains visible)
	# This logic will move to ConvoyLabelManager if it handles its own drag state or receives it.
	# For now, UIManager might still pass _dragging_panel_node to ConvoyLabelManager.
	# if is_instance_valid(_dragging_panel_node) and _dragging_panel_node.get_parent() == convoy_label_container:
	# 	_dragging_panel_node.visible = true 
	# 	var dragged_convoy_data = _convoy_data_by_id_cache.get(_dragged_convoy_id_actual_str)
	# 	if dragged_convoy_data:
	# 		_update_convoy_panel_content(_dragging_panel_node, dragged_convoy_data) # This would be a call within ConvoyLabelManager
		
	# 	var dragged_panel_actual_size = _dragging_panel_node.size
	# 	if dragged_panel_actual_size.x <= 0 or dragged_panel_actual_size.y <= 0:
	# 		dragged_panel_actual_size = _dragging_panel_node.get_minimum_size()
	# 	all_drawn_label_rects_this_update.append(Rect2(_dragging_panel_node.position, dragged_panel_actual_size))

	# 	if not drawn_convoy_ids_this_update.has(_dragged_convoy_id_actual_str):
	# 		drawn_convoy_ids_this_update.append(_dragged_convoy_id_actual_str)

	# STAGE 4: Update/Create Convoy Labels
	# This entire loop and its helper functions (_create_convoy_panel, _update_convoy_panel_content, _position_convoy_panel)
	# will move to ConvoyLabelManager.gd.
	# UIManager will call something like:
	# convoy_label_manager.process_convoy_labels(convoy_ids_to_display, _convoy_data_by_id_cache, all_drawn_label_rects_this_update)
	# And ConvoyLabelManager will update `all_drawn_label_rects_this_update` internally.

	# Example of how it might look if delegated (conceptual):
	# if is_instance_valid(convoy_label_manager):
	# 	convoy_label_manager.update_active_labels(
	# 		convoy_ids_to_display, 
	# 		_convoy_data_by_id_cache, 
	# 		all_drawn_label_rects_this_update, # Pass for anti-collision
	# 		_selected_convoy_ids_cache,
	# 		_convoy_label_user_positions,
	# 		_dragging_panel_node, # Pass drag state
	# 		_dragged_convoy_id_actual_str
	# 	)

	# STAGE 5: Hide convoy panels that are no longer needed
	# This logic also moves to ConvoyLabelManager.gd.
	# for existing_id_str in _active_convoy_panels.keys():
	# 	if not drawn_convoy_ids_this_update.has(existing_id_str):
	# 		var panel_to_hide = _active_convoy_panels[existing_id_str]
	# 		if is_instance_valid(panel_to_hide):
	# 			panel_to_hide.visible = false

	# STAGE 6: Update/Create Settlement Labels
	# This part remains in UIManager or moves to a new SettlementLabelManager
	for settlement_coord_to_draw in settlement_coords_to_display:
		var settlement_coord_str = "%s_%s" % [settlement_coord_to_draw.x, settlement_coord_to_draw.y]
		var settlement_data_for_panel = _find_settlement_at_tile(settlement_coord_to_draw.x, settlement_coord_to_draw.y)
		if not settlement_data_for_panel: continue

		var panel_node: Panel
		if _active_settlement_panels.has(settlement_coord_str):
			panel_node = _active_settlement_panels[settlement_coord_str]
			if not is_instance_valid(panel_node):
				_active_settlement_panels.erase(settlement_coord_str)
				panel_node = _create_settlement_panel(settlement_data_for_panel)
				if not is_instance_valid(panel_node): continue
				_active_settlement_panels[settlement_coord_str] = panel_node
				settlement_label_container.add_child(panel_node)
			elif panel_node.get_parent() != settlement_label_container:
				if panel_node.get_parent(): panel_node.get_parent().remove_child(panel_node)
				settlement_label_container.add_child(panel_node)
		else:
			panel_node = _create_settlement_panel(settlement_data_for_panel)
			if not is_instance_valid(panel_node): continue
			_active_settlement_panels[settlement_coord_str] = panel_node
			settlement_label_container.add_child(panel_node)

		_update_settlement_panel_content(panel_node, settlement_data_for_panel)
		panel_node.visible = true
		# print("UIManager:_draw_interactive_labels - Positioning/Clamping settlement panel for coords: ", settlement_coord_to_draw, " at pos: ", panel_node.position) # DEBUG
		_position_settlement_panel(panel_node, settlement_data_for_panel, all_drawn_label_rects_this_update)
		_clamp_panel_position(panel_node)
		
		var current_settlement_panel_actual_size = panel_node.size
		if current_settlement_panel_actual_size.x <= 0 or current_settlement_panel_actual_size.y <= 0:
			current_settlement_panel_actual_size = panel_node.get_minimum_size()
		all_drawn_label_rects_this_update.append(Rect2(panel_node.position, current_settlement_panel_actual_size))
		if not drawn_settlement_tile_coords_this_update.has(settlement_coord_to_draw):
			drawn_settlement_tile_coords_this_update.append(settlement_coord_to_draw)

	# STAGE 7: Hide settlement panels that are no longer needed
	for existing_coord_str in _active_settlement_panels.keys():
		var coords_parts = existing_coord_str.split("_")
		if coords_parts.size() == 2:
			var existing_coord = Vector2i(coords_parts[0].to_int(), coords_parts[1].to_int())
			if not drawn_settlement_tile_coords_this_update.has(existing_coord):
				var panel_to_hide = _active_settlement_panels[existing_coord_str]
				if is_instance_valid(panel_to_hide):
					panel_to_hide.visible = false
		else: # Should not happen, but good to clean up malformed keys
			var panel_to_hide = _active_settlement_panels[existing_coord_str]
			if is_instance_valid(panel_to_hide): panel_to_hide.queue_free() # Or just hide
			_active_settlement_panels.erase(existing_coord_str)

	# Request redraw for connector lines (this part is fine)
	if is_instance_valid(convoy_connector_lines_container):
		convoy_connector_lines_container.queue_redraw()

# The following functions related to convoy panels will be moved to ConvoyLabelManager.gd:
# _create_convoy_panel
# _update_convoy_panel_content
# _position_convoy_panel


func _create_settlement_panel(settlement_info: Dictionary) -> Panel:
	if not is_instance_valid(settlement_label_container):
		printerr('UIManager (_create_settlement_panel): SettlementLabelContainer is not valid. Ensure a Node2D named "SettlementLabelContainer" is a direct child of the UIManagerNode in the scene tree.')
		return null
	if not _ui_drawing_params_cached:
		printerr('UIManager: Drawing params not cached in _create_settlement_panel.')
		return null

	var panel := Panel.new()
	var style_box := StyleBoxFlat.new()
	panel.add_theme_stylebox_override('panel', style_box)
	panel.set_meta("style_box_ref", style_box)
	# Settlement panels are not draggable by default, so no MOUSE_FILTER_STOP needed unless specified.

	var label_node := Label.new()
	label_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_node.label_settings = settlement_label_settings # Assign shared LabelSettings
	panel.add_child(label_node)
	panel.set_meta("label_node_ref", label_node)

	return panel

func _update_settlement_panel_content(panel: Panel, settlement_info: Dictionary):
	if not is_instance_valid(panel) or not _ui_drawing_params_cached: return

	var label_node: Label = panel.get_meta("label_node_ref")
	var style_box: StyleBoxFlat = panel.get_meta("style_box_ref")
	if not is_instance_valid(label_node) or not is_instance_valid(style_box): return

	# --- Font Size & Panel Style Calculations (from original _draw_single_settlement_label) ---
	var effective_tile_size_on_texture: float = min(_cached_actual_tile_width_on_texture, _cached_actual_tile_height_on_texture)
	var base_linear_font_scale: float = 1.0
	if font_scaling_base_tile_size > 0.001:
		base_linear_font_scale = effective_tile_size_on_texture / font_scaling_base_tile_size
	var font_render_scale: float = pow(base_linear_font_scale, font_scaling_exponent)

	var adjusted_base_settlement_font_size = base_settlement_font_size * ui_overall_scale_multiplier
	var scaled_target_screen_settlement_font_size = adjusted_base_settlement_font_size * font_render_scale
	var node_settlement_font_size_before_clamp = scaled_target_screen_settlement_font_size / _current_map_zoom_cache
	var current_settlement_font_size: int = clamp(roundi(node_settlement_font_size_before_clamp), min_node_font_size, max_node_font_size)

	var adjusted_base_settlement_corner_radius = base_settlement_panel_corner_radius * ui_overall_scale_multiplier
	var scaled_target_screen_settlement_corner_radius = adjusted_base_settlement_corner_radius * font_render_scale
	var node_settlement_corner_radius_before_clamp = scaled_target_screen_settlement_corner_radius / _current_map_zoom_cache
	var current_settlement_panel_corner_radius: float = clamp(node_settlement_corner_radius_before_clamp, min_node_panel_corner_radius, max_node_panel_corner_radius)

	var adjusted_base_settlement_padding_h = base_settlement_panel_padding_h * ui_overall_scale_multiplier
	var scaled_target_screen_settlement_padding_h = adjusted_base_settlement_padding_h * font_render_scale
	var node_settlement_padding_h_before_clamp = scaled_target_screen_settlement_padding_h / _current_map_zoom_cache
	var current_settlement_panel_padding_h: float = clamp(node_settlement_padding_h_before_clamp, min_node_panel_padding, max_node_panel_padding)

	var adjusted_base_settlement_padding_v = base_settlement_panel_padding_v * ui_overall_scale_multiplier
	var scaled_target_screen_settlement_padding_v = adjusted_base_settlement_padding_v * font_render_scale
	var node_settlement_padding_v_before_clamp = scaled_target_screen_settlement_padding_v / _current_map_zoom_cache
	var current_settlement_panel_padding_v: float = clamp(node_settlement_padding_v_before_clamp, min_node_panel_padding, max_node_panel_padding)

	# --- Label Text Generation ---
	var settlement_name_local: String = settlement_info.get('name', 'N/A')
	if settlement_name_local == 'N/A': return # Or handle error

	if not is_instance_valid(settlement_label_settings.font):
		printerr("UIManager (_update_settlement_panel_content): settlement_label_settings.font is NOT VALID for settlement: ", settlement_name_local)
	settlement_label_settings.font_size = current_settlement_font_size

	var settlement_type = settlement_info.get('sett_type', '')
	var settlement_emoji = SETTLEMENT_EMOJIS.get(settlement_type, '')
	label_node.text = settlement_emoji + ' ' + settlement_name_local if not settlement_emoji.is_empty() else settlement_name_local

	# --- Update Panel StyleBox ---
	style_box.bg_color = settlement_panel_background_color
	style_box.corner_radius_top_left = current_settlement_panel_corner_radius
	style_box.corner_radius_top_right = current_settlement_panel_corner_radius
	style_box.corner_radius_bottom_left = current_settlement_panel_corner_radius
	style_box.corner_radius_bottom_right = current_settlement_panel_corner_radius
	style_box.content_margin_left = current_settlement_panel_padding_h
	style_box.content_margin_right = current_settlement_panel_padding_h
	style_box.content_margin_top = current_settlement_panel_padding_v
	style_box.content_margin_bottom = current_settlement_panel_padding_v

	label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label_node.position = Vector2.ZERO

	# Explicitly set panel's custom_minimum_size
	label_node.update_minimum_size() # Nudge the label
	var label_actual_min_size = label_node.get_minimum_size()
	var stylebox_margins = style_box.get_minimum_size()

	panel.custom_minimum_size = Vector2(
		label_actual_min_size.x + stylebox_margins.x,
		label_actual_min_size.y + stylebox_margins.y
	)

	# This call might now be redundant.
	panel.update_minimum_size()

func _position_settlement_panel(panel: Panel, settlement_info: Dictionary, _existing_label_rects: Array[Rect2]):
	# For settlements, anti-collision is often less critical or handled differently (e.g., fewer labels shown at once).
	# This simplified version doesn't implement anti-collision for settlements yet.
	if not is_instance_valid(panel) or not _ui_drawing_params_cached: return

	var tile_x: int = settlement_info.get('x', -1)
	var tile_y: int = settlement_info.get('y', -1)
	if tile_x < 0 or tile_y < 0: return

	# --- Offset Calculation (from original _draw_single_settlement_label) ---
	var current_settlement_offset_above_center: float = base_settlement_offset_above_tile_center * _cached_actual_scale

	# --- Positioning Logic ---
	var tile_center_tex_x: float = (float(tile_x) + 0.5) * _cached_actual_tile_width_on_texture
	var tile_center_tex_y: float = (float(tile_y) + 0.5) * _cached_actual_tile_height_on_texture

	# Position in map_display's local coordinate space
	var panel_desired_x = (tile_center_tex_x * _cached_actual_scale + _cached_offset_x) - (panel.size.x / 2.0)
	var panel_desired_y = (tile_center_tex_y * _cached_actual_scale + _cached_offset_y) - panel.size.y - current_settlement_offset_above_center
	panel.position = Vector2(panel_desired_x, panel_desired_y)


# Original _draw_single_convoy_label and _draw_single_settlement_label are now replaced by:
# _create_convoy_panel, _update_convoy_panel_content, _position_convoy_panel
# _create_settlement_panel, _update_settlement_panel_content, _position_settlement_panel

func _find_settlement_at_tile(tile_x: int, tile_y: int) -> Variant:
	if not _all_settlement_data_cache: return null # Guard against null cache
	for settlement_data_entry in _all_settlement_data_cache:
		if settlement_data_entry is Dictionary:
			var s_tile_x = settlement_data_entry.get('x', -1)
			var s_tile_y = settlement_data_entry.get('y', -1)
			if s_tile_x == tile_x and s_tile_y == tile_y:
				return settlement_data_entry
	return null


func _on_connector_lines_container_draw():
	# Use cached drawing parameters
	if not _ui_drawing_params_cached:
		# printerr("UIManager: Drawing params not cached for connector lines. Skipping draw.")
		return
		
	if not is_instance_valid(convoy_label_container): return
	# This function will need to get visible convoy panels from ConvoyLabelManager
	# or ConvoyLabelManager could draw its own connector lines if this container is moved under it.
	# For now, assume UIManager asks ConvoyLabelManager for the visible panels.
	# Access cached values directly:
	# _cached_actual_scale
	# _cached_offset_x
	# _cached_offset_y
	# _cached_actual_tile_width_on_texture
	# _cached_actual_tile_height_on_texture
	
	var active_convoy_panels_info: Array = [] # Array of Dictionaries: [{panel: Panel, convoy_data: Dictionary}]
	if is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("get_active_convoy_panels_info"):
		active_convoy_panels_info = convoy_label_manager.get_active_convoy_panels_info()

	for panel_info in active_convoy_panels_info:
		var panel: Panel = panel_info.get("panel")
		var convoy_data_for_line: Dictionary = panel_info.get("convoy_data")

		if not is_instance_valid(panel) or not panel.visible or not convoy_data_for_line:
			continue

		var convoy_map_x: float = convoy_data_for_line.get('x', 0.0)
		var convoy_map_y: float = convoy_data_for_line.get('y', 0.0)
		var convoy_center_on_texture_x: float = (convoy_map_x + 0.5) * _cached_actual_tile_width_on_texture
		var convoy_center_on_texture_y: float = (convoy_map_y + 0.5) * _cached_actual_tile_height_on_texture
		
		var line_start_pos = Vector2(
			convoy_center_on_texture_x * _cached_actual_scale + _cached_offset_x,
			convoy_center_on_texture_y * _cached_actual_scale + _cached_offset_y
		)

		# Assuming convoy_label_container and convoy_connector_lines_container are siblings
		# and their parent (UIManagerNode) is at (0,0) relative to map_display.
		# Panel.position is local to its parent (ConvoyLabelContainer).
		# We need the panel's rect in the coordinate system of ConvoyConnectorLinesContainer.
		# If they are siblings under UIManagerNode, and UIManagerNode is at (0,0) in MapDisplay,
		# then panel.global_position can be transformed to local for the connector container.
		var panel_global_pos = panel.global_position
		var panel_pos_local_to_connector_container = convoy_connector_lines_container.to_local(panel_global_pos)
		
		var panel_rect_in_connector_space = Rect2(panel_pos_local_to_connector_container, panel.size)
		var actual_panel_size_for_draw = panel.size
		if actual_panel_size_for_draw.x <= 0 or actual_panel_size_for_draw.y <= 0:
			actual_panel_size_for_draw = panel.get_minimum_size()

		panel_rect_in_connector_space.size = actual_panel_size_for_draw
		
		var panel_center_in_connector_space = panel_rect_in_connector_space.get_center()
		var line_end_pos: Vector2

		if actual_panel_size_for_draw.x <= 0 or actual_panel_size_for_draw.y <= 0:
			# printerr("UIManager: Invalid panel size for connector line. Convoy ID: %s" % convoy_data_for_line.get("convoy_id"))
			continue

		if panel_rect_in_connector_space.has_point(line_start_pos):
			if panel_center_in_connector_space.is_equal_approx(line_start_pos):
				line_end_pos = Vector2(panel_center_in_connector_space.x, panel_rect_in_connector_space.position.y)
			else:
				var dir_to_icon = (line_start_pos - panel_center_in_connector_space).normalized()
				var far_point = panel_center_in_connector_space + dir_to_icon * (max(panel_rect_in_connector_space.size.x, panel_rect_in_connector_space.size.y) * 2.0)
				line_end_pos = Vector2(
					clamp(far_point.x, panel_rect_in_connector_space.position.x, panel_rect_in_connector_space.end.x),
					clamp(far_point.y, panel_rect_in_connector_space.position.y, panel_rect_in_connector_space.end.y)
				)
		else:
			line_end_pos = Vector2(
				clamp(line_start_pos.x, panel_rect_in_connector_space.position.x, panel_rect_in_connector_space.end.x),
				clamp(line_start_pos.y, panel_rect_in_connector_space.position.y, panel_rect_in_connector_space.end.y)
			)
			
		if not line_start_pos.is_equal_approx(line_end_pos):
			convoy_connector_lines_container.draw_line(line_start_pos, line_end_pos, connector_line_color, connector_line_width, true)

# --- Drag and Drop related methods (to be implemented/refined later) ---
# func start_panel_drag(panel_node: Panel, global_mouse_position: Vector2):
#     _dragging_panel_node = panel_node
#     _dragged_convoy_id_actual_str = panel_node.get_meta("convoy_id_str", "")
#     # Calculate drag offset, clamp rect, etc.
#     # ...

# func update_panel_drag(global_mouse_position: Vector2):
#     if not is_instance_valid(_dragging_panel_node): return
#     # Update panel position based on mouse, respecting clamp_rect
#     # ...

# func end_panel_drag():
#     if not is_instance_valid(_dragging_panel_node): return
#     # Store final user position in _convoy_label_user_positions
#     # _convoy_label_user_positions[_dragged_convoy_id_actual_str] = _dragging_panel_node.position
#     _dragging_panel_node = null
#     _dragged_convoy_id_actual_str = ""
#     # ...

# func _input(event: InputEvent):
	# UIManager could handle its own input for starting/updating/ending drags
	# if it's made responsible for that.
	# For now, main.gd handles input and calls UIManager methods.
	# pass


# Public method to update user positions if main.gd still handles drag input
func set_convoy_user_position(convoy_id_str: String, position: Vector2):
	_convoy_label_user_positions[convoy_id_str] = position

func clear_convoy_user_position(convoy_id_str: String):
	if _convoy_label_user_positions.has(convoy_id_str):
		_convoy_label_user_positions.erase(convoy_id_str)

func set_dragging_state(panel_node: Panel, convoy_id_str: String, is_dragging: bool):
	if is_dragging:
		_dragging_panel_node = panel_node
		_dragged_convoy_id_actual_str = convoy_id_str
	else:
		_dragging_panel_node = null
		_dragged_convoy_id_actual_str = ""
