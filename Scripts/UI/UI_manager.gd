extends CanvasLayer

# References to label containers managed by UIManager
# These should be children of the Node this script is attached to.
# The global UI scale is now managed by the UIScaleManager singleton.
var ui_overall_scale_multiplier: float = 1.0

@export_group("Node Dependencies")
@export var settlement_label_container: Node2D
@export var convoy_connector_lines_container: Node2D
@export var convoy_label_container: Node2D
@export var convoy_label_manager: Node

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
var _convoy_label_user_positions: Dictionary = {} # Stores user-set positions: { 'convoy_id_str': Vector2(x,y) }
var _dragged_convoy_id_actual_str: String = ""

# Data passed from main.gd during updates
@export var terrain_tilemap: TileMapLayer # Reference to the TerrainTileMap node
var _all_convoy_data_cache: Array
var _all_settlement_data_cache: Array
var _convoy_id_to_color_map_cache: Dictionary
var _convoy_data_by_id_cache: Dictionary # New cache for quick lookup
var _selected_convoy_ids_cache: Array # Stored as strings
var _current_map_zoom_cache: float = 1.0 # Cache for current map zoom level
var _current_map_screen_rect_for_clamping: Rect2

var _active_settlement_panels: Dictionary = {} # { "tile_coord_str": PanelNode }

# Z-index for label containers within MapContainer, relative to MapDisplay and ConvoyNodes
const LABEL_CONTAINER_Z_INDEX = 2


func _ready():
	await get_tree().process_frame


	print("[DIAG] UIManager _ready: Checking node assignments...")
	print("  settlement_label_container valid:", is_instance_valid(settlement_label_container))
	print("  convoy_connector_lines_container valid:", is_instance_valid(convoy_connector_lines_container))
	print("  convoy_label_container valid:", is_instance_valid(convoy_label_container))
	print("  convoy_label_manager valid:", is_instance_valid(convoy_label_manager))
	print("  terrain_tilemap valid:", is_instance_valid(terrain_tilemap))
	
	# --- Critical Dependency Validation ---
	# Ensure all child Control nodes do not block input
	for child in get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			print("UIManagerNode: Set mouse_filter=IGNORE on child Control node:", child.name)
	# Check all exported NodePath dependencies at startup to fail early if not configured in the editor.
	var dependencies: Dictionary = {
		"settlement_label_container": settlement_label_container,
		"convoy_connector_lines_container": convoy_connector_lines_container,
		"convoy_label_container": convoy_label_container,
		"convoy_label_manager": convoy_label_manager
	}
	for dep_name in dependencies:
		if not is_instance_valid(dependencies[dep_name]):
			printerr('UIManager (_ready): The "%s" dependency is not assigned. Please select the UIManagerNode in the scene and assign the correct node to this property in the Inspector.' % dep_name)

	# --- Initialize Containers ---
	if is_instance_valid(settlement_label_container):
		settlement_label_container.visible = true
		settlement_label_container.z_index = LABEL_CONTAINER_Z_INDEX
	if is_instance_valid(convoy_connector_lines_container):
		convoy_connector_lines_container.visible = true
		convoy_connector_lines_container.z_index = LABEL_CONTAINER_Z_INDEX # Connectors at the same level as labels
		convoy_connector_lines_container.draw.connect(_on_connector_lines_container_draw)

	# Initialize label settings
	label_settings = LabelSettings.new()
	settlement_label_settings = LabelSettings.new()

	label_settings.font_color = Color.WHITE
	label_settings.outline_size = 6
	label_settings.outline_color = Color.BLACK
	settlement_label_settings.font_color = Color.WHITE
	settlement_label_settings.outline_size = 3
	settlement_label_settings.outline_color = Color.BLACK

	_current_map_screen_rect_for_clamping = get_viewport().get_visible_rect() # Initialize

	# Programmatically assign the convoy_label_container to the ConvoyLabelManager
	if is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("set_convoy_label_container"):
		if is_instance_valid(convoy_label_container):
			convoy_label_manager.set_convoy_label_container(convoy_label_container)
		# The generic dependency check at the top of _ready() already covers the case where convoy_label_container is invalid.

	# Add a reference to GameDataManager
	var gdm: Node = null

	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("convoy_data_updated", Callable(self, "_on_gdm_convoy_data_updated")):
			gdm.convoy_data_updated.connect(_on_gdm_convoy_data_updated)
		if not gdm.is_connected("settlement_data_updated", Callable(self, "_on_gdm_settlement_data_updated")):
			gdm.settlement_data_updated.connect(_on_gdm_settlement_data_updated)

	# --- Assign TerrainTileMap node if not set ---
	if not is_instance_valid(terrain_tilemap):
		var tilemap_path = "../SubViewport/TerrainTileMap"
		terrain_tilemap = get_node_or_null(tilemap_path)
		if is_instance_valid(terrain_tilemap):
			print("[UIManager DEBUG] TerrainTileMap node found:", terrain_tilemap.name)
		else:
			printerr("UIManager: TerrainTileMap node not found at path: ", tilemap_path)

	# Connect to the new UIScaleManager to react to global scale changes.
	# This manager will be the single source of truth for the UI scale setting.
	if Engine.has_singleton("ui_scale_manager"):
		ui_overall_scale_multiplier = ui_scale_manager.get_global_ui_scale()
		ui_scale_manager.scale_changed.connect(_on_ui_scale_changed)
	else:
		printerr("UIManager: ui_scale_manager singleton not found. UI scaling will not be dynamic.")

	# Diagnostic: Print scene tree and mouse_filter values for all UI nodes
	print("[DIAG] UI_manager.gd: Printing scene tree and mouse_filter values for all UI nodes:")
	_print_ui_tree(self, 0)

func _print_ui_tree(node: Node, indent: int):
	var prefix = "  ".repeat(indent)
	var mf = ""
	if node is Control:
		mf = " mouse_filter=" + str(node.mouse_filter)
	print("%s- %s (%s)%s" % [prefix, node.name, node.get_class(), mf])
	for child in node.get_children():
		_print_ui_tree(child, indent + 1)


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


func update_ui_elements(
	all_convoy_data: Array,
	all_settlement_data: Array,
	convoy_id_to_color_map: Dictionary,
	current_hover_info: Dictionary,
	selected_convoy_ids: Array, # Expecting array of strings
	convoy_label_user_positions_from_main: Dictionary, 
	dragging_panel_node_from_main: Panel, 
	dragged_convoy_id_str_from_main: String,
	p_current_map_screen_rect_for_clamping: Rect2, # Moved before optional params
	_is_light_ui_update: bool = false,
	current_map_zoom: float = 1.0 # Now 13th argument
	):
	# Store references to data needed by drawing functions
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

	# Update UIManager's state from what main.gd passes
	_convoy_label_user_positions = convoy_label_user_positions_from_main
	_dragging_panel_node = dragging_panel_node_from_main
	_dragged_convoy_id_actual_str = dragged_convoy_id_str_from_main

	print("[DIAG] UIManager update_ui_elements: settlement_data count:", _all_settlement_data_cache.size())
	for s in _all_settlement_data_cache:
		if s is Dictionary:
			print("  Settlement:", s.get('name', 'N/A'), "coords:", s.get('x', 'N/A'), s.get('y', 'N/A'))
	
	_draw_interactive_labels(current_hover_info)
	# Delegate convoy label updates to ConvoyLabelManager.
	if is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("update_convoy_labels"):
		convoy_label_manager.update_convoy_labels(
			_all_convoy_data_cache,
			_convoy_id_to_color_map_cache,
			current_hover_info,
			_selected_convoy_ids_cache,
			_convoy_label_user_positions,
			_dragging_panel_node,
			_dragged_convoy_id_actual_str,
			_current_map_screen_rect_for_clamping,
		)
	# Request redraw for connector lines
	if is_instance_valid(convoy_connector_lines_container):
		convoy_connector_lines_container.queue_redraw()
	# Called during pan/zoom. Avoids destroying/recreating labels. Focuses on re-clamping existing labels to viewport.
	if is_instance_valid(settlement_label_container) and settlement_label_container.get_child_count() > 0:
		var container_global_transform_settlement = settlement_label_container.get_global_transform_with_canvas()
		var clamp_rect_local_to_settlement_container = container_global_transform_settlement.affine_inverse() * _current_map_screen_rect_for_clamping
		for panel_node in settlement_label_container.get_children():
			if panel_node is Panel:
				_clamp_panel_position_optimized(panel_node, clamp_rect_local_to_settlement_container)

func _clamp_panel_position_optimized(panel: Panel, precalculated_clamp_rect_local_to_container: Rect2):
	# Helper to clamp a panel's position to the viewport boundaries using a precalculated clamping rectangle in the panel's parent container's local space.
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
	# Helper to clamp a panel's position to the viewport boundaries.
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
	if is_instance_valid(_dragging_panel_node):
		pass # Let's assume main.gd already checked this or UIManager will handle it.
	var drawn_settlement_tile_coords_this_update: Array[Vector2i] = []
	var all_drawn_label_rects_this_update: Array[Rect2] = [] # This will be used by SettlementLabelManager and ConvoyLabelManager internally or passed to them
	var convoy_ids_to_display: Array[String] = []
	var settlement_coords_to_display: Array[Vector2i] = []
	# Draw Settlement Labels (for selected convoys' start/end, then hovered settlement)
	if not _selected_convoy_ids_cache.is_empty():
		for convoy_data in _all_convoy_data_cache:
			if convoy_data is Dictionary:
				var convoy_id = convoy_data.get('convoy_id')
				var convoy_id_str = str(convoy_id)
				if convoy_id != null and _selected_convoy_ids_cache.has(convoy_id_str):
					var journey_data: Dictionary = convoy_data.get('journey')
					if journey_data is Dictionary:

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

	# Determine Convoy Labels to Display (Selected then Hovered)
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
				panel_node = _create_settlement_panel()
				if not is_instance_valid(panel_node): continue
				_active_settlement_panels[settlement_coord_str] = panel_node
				settlement_label_container.add_child(panel_node)
			elif panel_node.get_parent() != settlement_label_container:
				if panel_node.get_parent(): panel_node.get_parent().remove_child(panel_node)
				settlement_label_container.add_child(panel_node)
		else:
			panel_node = _create_settlement_panel()
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


func _create_settlement_panel() -> Panel:
	if not is_instance_valid(settlement_label_container): # This check is now crucial
		printerr('UIManager (_create_settlement_panel): The "settlement_label_container" dependency is not assigned. Please select the UIManagerNode in the scene and assign the correct node to this property in the Inspector.')
		return null # Abort creation if the container is missing
	# Removed legacy _ui_drawing_params_cached check

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
	if not is_instance_valid(panel): return
	var label_node: Label = panel.get_meta("label_node_ref")
	var style_box: StyleBoxFlat = panel.get_meta("style_box_ref")
	if not is_instance_valid(label_node) or not is_instance_valid(style_box): return
	# Font size and panel sizing use only exported variables and ui_overall_scale_multiplier
	var current_settlement_font_size: int = clamp(roundi(base_settlement_font_size * ui_overall_scale_multiplier), min_node_font_size, max_node_font_size)
	var current_settlement_panel_corner_radius: float = clamp(base_settlement_panel_corner_radius * ui_overall_scale_multiplier, min_node_panel_corner_radius, max_node_panel_corner_radius)
	var current_settlement_panel_padding_h: float = clamp(base_settlement_panel_padding_h * ui_overall_scale_multiplier, min_node_panel_padding, max_node_panel_padding)
	var current_settlement_panel_padding_v: float = clamp(base_settlement_panel_padding_v * ui_overall_scale_multiplier, min_node_panel_padding, max_node_panel_padding)
	var settlement_name_local: String = settlement_info.get('name', 'N/A')
	if settlement_name_local == 'N/A': return
	if not is_instance_valid(settlement_label_settings.font):
		printerr("UIManager (_update_settlement_panel_content): settlement_label_settings.font is NOT VALID for settlement: ", settlement_name_local)
	settlement_label_settings.font_size = current_settlement_font_size
	var settlement_type = settlement_info.get('sett_type', '')
	var settlement_emoji = SETTLEMENT_EMOJIS.get(settlement_type, '')
	label_node.text = settlement_emoji + ' ' + settlement_name_local if not settlement_emoji.is_empty() else settlement_name_local
	style_box.bg_color = settlement_panel_background_color
	style_box.corner_radius_top_left = floori(current_settlement_panel_corner_radius)
	style_box.corner_radius_top_right = floori(current_settlement_panel_corner_radius)
	style_box.corner_radius_bottom_left = floori(current_settlement_panel_corner_radius)
	style_box.corner_radius_bottom_right = floori(current_settlement_panel_corner_radius)
	style_box.content_margin_left = current_settlement_panel_padding_h
	style_box.content_margin_right = current_settlement_panel_padding_h
	style_box.content_margin_top = current_settlement_panel_padding_v
	style_box.content_margin_bottom = current_settlement_panel_padding_v
	label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label_node.position = Vector2.ZERO
	label_node.update_minimum_size()
	var label_actual_min_size = label_node.get_minimum_size()
	var stylebox_margins = style_box.get_minimum_size()
	panel.custom_minimum_size = Vector2(
		label_actual_min_size.x + stylebox_margins.x,
		label_actual_min_size.y + stylebox_margins.y
	)
	panel.update_minimum_size()

func _position_settlement_panel(panel: Panel, settlement_info: Dictionary, _existing_label_rects: Array[Rect2]):
	# For settlements, anti-collision is often less critical or handled differently (e.g., fewer labels shown at once).
	if not is_instance_valid(panel) or not is_instance_valid(terrain_tilemap): return

	var tile_x: int = settlement_info.get('x', -1)
	var tile_y: int = settlement_info.get('y', -1)
	if tile_x < 0 or tile_y < 0: return

	# Get the local position of the tile center using TerrainTileMap
	var tile_center = terrain_tilemap.map_to_local(Vector2i(tile_x, tile_y))
	# Convert tile_center from SubViewport local space to global canvas coordinates
	var global_tile_center = terrain_tilemap.to_global(tile_center)
	var current_settlement_offset_above_center: float = base_settlement_offset_above_tile_center
	# Position label above the tile center
	var panel_desired_x = global_tile_center.x - (panel.size.x / 2.0)
	var panel_desired_y = global_tile_center.y - panel.size.y - current_settlement_offset_above_center
	panel.position = Vector2(panel_desired_x, panel_desired_y)



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
	# Ensure terrain_tilemap is valid before using it
	if not is_instance_valid(terrain_tilemap):
		printerr("UIManager (_on_connector_lines_container_draw): terrain_tilemap is not assigned or invalid. Cannot draw connector lines.")
		return
	# Draw convoy journey lines and icons using TerrainTileMap coordinates
	if _all_convoy_data_cache is Array:
		for convoy in _all_convoy_data_cache:
			if not (convoy is Dictionary and convoy.has("journey")):
				continue
			var journey = convoy["journey"]
			if not (journey is Dictionary and journey.has("route_x") and journey.has("route_y")):
				continue
			var route_x: Array = journey["route_x"]
			var route_y: Array = journey["route_y"]
			if route_x.size() < 2 or route_y.size() != route_x.size():
				continue
			var points: PackedVector2Array = []
			for i in range(route_x.size()):
				var tile_x = int(route_x[i])
				var tile_y = int(route_y[i])
				var tile_pos = terrain_tilemap.map_to_local(Vector2i(tile_x, tile_y))
				points.append(tile_pos)
			if points.size() >= 2:
				convoy_connector_lines_container.draw_polyline(points, connector_line_color, connector_line_width)
		# Draw convoy icons
		for convoy in _all_convoy_data_cache:
			if not (convoy is Dictionary and convoy.has("x") and convoy.has("y")):
				continue
			var tile_x = int(convoy["x"])
			var tile_y = int(convoy["y"])
			var tile_pos = terrain_tilemap.map_to_local(Vector2i(tile_x, tile_y))
			var color = _convoy_id_to_color_map_cache.get(str(convoy.get("convoy_id", "")), Color(1,1,1,1))
			convoy_connector_lines_container.draw_circle(tile_pos, 6, color)

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

func _on_gdm_convoy_data_updated(all_convoy_data: Array) -> void:
	# Update your local cache or UI as needed
	_all_convoy_data_cache = all_convoy_data
	# Optionally, trigger a UI update here
	_draw_interactive_labels({})

func _on_gdm_settlement_data_updated(settlement_data_list: Array) -> void:
	# Update your local cache or UI as needed
	_all_settlement_data_cache = settlement_data_list
	# Optionally, trigger a UI update here
	_draw_interactive_labels({})

func _on_ui_scale_changed(new_scale: float):
	# Reacts to the global UI scale being changed in the UIScaleManager.
	ui_overall_scale_multiplier = new_scale
	# A full redraw of labels is needed because font sizes, padding, etc., will change.
	# We pass an empty dictionary for hover_info to avoid issues and force a clean update.
	# This will propagate the new scale down to the ConvoyLabelManager as well.
	_draw_interactive_labels({})
