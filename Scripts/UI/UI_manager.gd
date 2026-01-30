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
@export var base_convoy_title_font_size: int = 29 # 22 * 1.33
@export var base_settlement_font_size: int = 24 # 18 * 1.33
## Minimum font size to set on the Label node.
@export var min_node_font_size: int = 8
## Maximum font size to set on the Label node.
@export var max_node_font_size: int = 120 # Increased from 60
## The map tile size that font scaling is based on. Should ideally match map_render's base_tile_size_for_proportions.
@export var font_scaling_base_tile_size: float = 32.0 # 24 * 1.33
## Exponent for font scaling (1.0 = linear, <1.0 less aggressive shrink/grow).
@export var font_scaling_exponent: float = 0.6 

@export_group("Label Offsets")
## Base horizontal offset from the convoy's center for its label panel. Scaled.
@export var base_horizontal_label_offset_from_center: float = 20.0 # 15 * 1.33
## Base horizontal offset for selected convoy label panels. Scaled.
@export var base_selected_convoy_horizontal_offset: float = 80.0 # 60 * 1.33
## Base vertical offset above the settlement's tile center for its label panel. Scaled.
@export var base_settlement_offset_above_tile_center: float = 13.0 # 10 * 1.33

@export_group("Convoy Panel Appearance")
## Target screen corner radius for convoy label panels. Adjust for desired on-screen look. (Prev: 4.0)
@export var base_convoy_panel_corner_radius: float = 6.65 # 5.0 * 1.33
## Target screen horizontal padding inside convoy label panels. Adjust for desired on-screen look. (Prev: 4.0)
@export var base_convoy_panel_padding_h: float = 13.3 # 10.0 * 1.33
@export var base_convoy_panel_padding_v: float = 6.65 # 5.0 * 1.33
## Background color for convoy label panels.
@export var convoy_panel_background_color: Color = Color(0.12, 0.12, 0.15, 0.88) 
## Target screen border width for convoy label panels. Adjust for desired on-screen look. (Prev: 1.0)
@export var base_convoy_panel_border_width: float = 1.66 # 1.25 * 1.33
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
@export var base_settlement_panel_corner_radius: float = 4.99 # 3.75 * 1.33
## Target screen horizontal padding inside settlement label panels. Adjust for desired on-screen look. (Prev: 3.0)
@export var base_settlement_panel_padding_h: float = 4.99 # 3.75 * 1.33
## Target screen vertical padding inside settlement label panels. Adjust for desired on-screen look. (Prev: 2.0)
@export var base_settlement_panel_padding_v: float = 3.33 # 2.5 * 1.33
## Background color for settlement label panels.
@export var settlement_panel_background_color: Color = Color(0.15, 0.12, 0.12, 0.85) 

@export_group("Label Positioning")
## Amount to shift a label panel vertically to avoid collision with another.
@export var label_anti_collision_y_shift: float = 5.0 
## Radius around convoy icons to keep settlement labels out of.
@export var settlement_convoy_keepout_radius: float = 24.0
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
	'city': '🏢',
	'city-state': '🏛️',
	'dome': '🏙️',
	'military_base': '🪖',
	'tutorial': '📘',
}


# --- Connector Line constants ---
@export_group("Connector Lines")
## Color for lines connecting convoy icons to their label panels.
@export var connector_line_color: Color = Color(0.9, 0.9, 0.9, 0.6) 
## Width of the connector lines.
@export var connector_line_width: float = 3.0 # slightly thicker center line
## Extra width (in pixels) added to the white outline under journey / preview lines
@export var route_line_outline_extra_width: float = 5.0 # slightly thicker underlay for contrast

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

# Z-index for connector lines, to ensure they are drawn under labels.
const CONNECTOR_LINES_Z_INDEX = 1

# --- Preview Route Drawing State ---
var _is_preview_active: bool = false
var _preview_route_x: Array = []
var _preview_route_y: Array = []
# Default preview color (fallback) – actual will be per selected convoy color
var _preview_color: Color = Color(1.0, 0.6, 0.0, 0.85)
var _preview_line_width: float = 3.5
var _high_contrast_enabled: bool = false

var _convoy_label_manager_initialized: bool = false

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
		convoy_connector_lines_container.z_index = CONNECTOR_LINES_Z_INDEX # Draw lines under labels
		convoy_connector_lines_container.draw.connect(_on_connector_lines_container_draw)
	if is_instance_valid(convoy_label_container):
		convoy_label_container.z_index = LABEL_CONTAINER_Z_INDEX

	# Initialize label settings
	label_settings = LabelSettings.new()
	settlement_label_settings = LabelSettings.new()

	label_settings.font_color = Color.WHITE
	label_settings.outline_size = 6
	label_settings.outline_color = Color.BLACK
	settlement_label_settings.font_color = Color.WHITE
	settlement_label_settings.outline_size = 3
	settlement_label_settings.outline_color = Color.BLACK

	# Ensure a valid Font is assigned to both LabelSettings to avoid "font is NOT VALID" errors.
	var fallback_font: Font = load("res://Assets/Roboto-VariableFont_wdth,wght.ttf")
	if not is_instance_valid(fallback_font):
		fallback_font = ThemeDB.fallback_font
	if is_instance_valid(fallback_font):
		# Duplicate before modifying to avoid editor resource mutation/reload prompts.
		if fallback_font is FontFile:
			fallback_font = (fallback_font as FontFile).duplicate(true)
			(fallback_font as FontFile).oversampling = 2.0
		label_settings.font = fallback_font
		settlement_label_settings.font = fallback_font

	_current_map_screen_rect_for_clamping = get_viewport().get_visible_rect() # Initialize

	# Programmatically assign the convoy_label_container to the ConvoyLabelManager
	if is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("set_convoy_label_container"):
		if is_instance_valid(convoy_label_container):
			convoy_label_manager.set_convoy_label_container(convoy_label_container)

	# Phase B: UIManager no longer wires directly to GameDataManager.

	# --- Assign TerrainTileMap node if not set ---
	if not is_instance_valid(terrain_tilemap):
		var tilemap_path = "../SubViewport/TerrainTileMap"
		terrain_tilemap = get_node_or_null(tilemap_path)
		if is_instance_valid(terrain_tilemap):
			print("[UIManager DEBUG] TerrainTileMap node found:", terrain_tilemap.name)
		else:
			printerr("UIManager: TerrainTileMap node not found at path: ", tilemap_path)

	# Connect to the new UIScaleManager to react to global scale changes.
	# Autoloads are nodes under /root; don't use Engine.has_singleton for them.
	var sm = get_node_or_null("/root/ui_scale_manager")
	if is_instance_valid(sm):
		if sm.has_method("get_global_ui_scale"):
			ui_overall_scale_multiplier = sm.get_global_ui_scale()
		sm.scale_changed.connect(_on_ui_scale_changed)
	else:
		printerr("UIManager: ui_scale_manager singleton not found. UI scaling will not be dynamic.")

	# Connect to MenuManager to listen for journey menu openings so we can hook preview signals.
	var menu_manager = get_node_or_null("/root/MenuManager")
	if is_instance_valid(menu_manager):
		if not menu_manager.is_connected("menu_opened", Callable(self, "_on_menu_manager_menu_opened")):
			menu_manager.menu_opened.connect(_on_menu_manager_menu_opened)
	else:
		printerr("UIManager: MenuManager autoload not found; cannot attach journey preview listeners.")

	# Diagnostic: Print scene tree and mouse_filter values for all UI nodes
	print("[DIAG] UI_manager.gd: Printing scene tree and mouse_filter values for all UI nodes:")
	_print_ui_tree(self, 0)

	# --- Settings integration from SettingsManager ---
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if is_instance_valid(settings_mgr):
		_high_contrast_enabled = bool(settings_mgr.get_value("access.high_contrast", false))

		_apply_accessibility_visuals()
		if not settings_mgr.is_connected("setting_changed", Callable(self, "_on_setting_changed")):
			settings_mgr.setting_changed.connect(_on_setting_changed)

func _print_ui_tree(node: Node, indent: int):
	var prefix = "  ".repeat(indent)
	var mf = ""
	if node is Control:
		mf = " mouse_filter=" + str(node.mouse_filter)
	print("%s- %s (%s)%s" % [prefix, node.name, node.get_class(), mf])
	for child in node.get_children():
		_print_ui_tree(child, indent + 1)

func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"access.high_contrast":
			_high_contrast_enabled = bool(value)
			_apply_accessibility_visuals()
		_:
			pass


func initialize_font_settings(theme_font_to_use: Font):
	if theme_font_to_use:
		label_settings.font = theme_font_to_use # LabelSettings objects are shared
		settlement_label_settings.font = theme_font_to_use # LabelSettings objects are shared
		# print("UIManager: Using theme font for labels provided by main: ", theme_font_to_use.resource_path if theme_font_to_use.resource_path else "Built-in font")
	else:
		# If no font is passed, LabelSettings will not have a font set,
		# and Labels will use their default/themed font.
		print("UIManager: No theme font provided by main. Labels will use their default theme font if LabelSettings.font is not set.")

func _apply_accessibility_visuals():
	if not is_instance_valid(label_settings) or not is_instance_valid(settlement_label_settings):
		return
	if _high_contrast_enabled:
		label_settings.outline_size = 8
		settlement_label_settings.outline_size = 5
		convoy_panel_background_color.a = 0.95
		settlement_panel_background_color.a = 0.95
	else:
		label_settings.outline_size = 6
		settlement_label_settings.outline_size = 3
		convoy_panel_background_color.a = 0.88
		settlement_panel_background_color.a = 0.85

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

	# One-time init for ConvoyLabelManager so it can use the same font scaling constants.
	if not _convoy_label_manager_initialized and is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("initialize_font_settings"):
		convoy_label_manager.initialize_font_settings(
			label_settings.font,
			label_settings,
			base_convoy_title_font_size,
			1.0, # ui_overall_scale_multiplier is now handled by content_scale_factor
			font_scaling_base_tile_size,
			font_scaling_exponent,
			min_node_font_size,
			max_node_font_size,
			_all_convoy_data_cache,
			CONVOY_STAT_EMOJIS
		)
		_convoy_label_manager_initialized = true

	# Update UIManager's state from what main.gd passes
	_convoy_label_user_positions = convoy_label_user_positions_from_main
	_dragging_panel_node = dragging_panel_node_from_main
	_dragged_convoy_id_actual_str = dragged_convoy_id_str_from_main

	# print("[DIAG] UIManager update_ui_elements: settlement_data count:", _all_settlement_data_cache.size())
	# for s in _all_settlement_data_cache:
	# 	if s is Dictionary:
	# 		print("  Settlement:", s.get('name', 'N/A'), "coords:", s.get('x', 'N/A'), s.get('y', 'N/A'))
	
	# Always update settlement labels - they are not focus-sensitive and should respond
	# to hover and selection changes immediately, even when UI elements have focus.
	_draw_interactive_labels(current_hover_info)
	# Provide drawing parameters to ConvoyLabelManager before updating labels
	if is_instance_valid(convoy_label_manager) \
			and convoy_label_manager.has_method("update_drawing_parameters") \
			and is_instance_valid(terrain_tilemap) \
			and is_instance_valid(terrain_tilemap.tile_set):
		var ts = terrain_tilemap.tile_set.tile_size
		convoy_label_manager.update_drawing_parameters(ts.x, ts.y, current_map_zoom, 1.0, 0.0, 0.0)
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
	# Always include hovered convoy ID if present
	if current_hover_info.get('type') == 'convoy':
		var hovered_convoy_id_variant = current_hover_info.get('id')
		if hovered_convoy_id_variant != null:
			var hovered_convoy_id_as_string = str(hovered_convoy_id_variant)
			if not hovered_convoy_id_as_string.is_empty():
				if not convoy_ids_to_display.has(hovered_convoy_id_as_string):
					convoy_ids_to_display.append(hovered_convoy_id_as_string)

	# Also include selected convoys
	if not _selected_convoy_ids_cache.is_empty():
		for convoy_data in _all_convoy_data_cache:
			if convoy_data is Dictionary:
				var convoy_id = convoy_data.get('convoy_id')
				var convoy_id_str = str(convoy_id)
				if convoy_id != null and _selected_convoy_ids_cache.has(convoy_id_str):
					if not convoy_ids_to_display.has(convoy_id_str):
						convoy_ids_to_display.append(convoy_id_str)
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
	# Font size and panel sizing now rely on content_scale_factor
	var current_settlement_font_size: int = clamp(
		roundi(base_settlement_font_size / max(0.0001, _current_map_zoom_cache)),
		min_node_font_size,
		max_node_font_size
	)
	# Scale panel visuals inversely with zoom so the box scales along with the text
	var current_settlement_panel_corner_radius: float = clamp(
		base_settlement_panel_corner_radius / max(0.0001, _current_map_zoom_cache),
		min_node_panel_corner_radius,
		max_node_panel_corner_radius
	)
	var current_settlement_panel_padding_h: float = clamp(
		base_settlement_panel_padding_h / max(0.0001, _current_map_zoom_cache),
		min_node_panel_padding,
		max_node_panel_padding
	)
	var current_settlement_panel_padding_v: float = clamp(
		base_settlement_panel_padding_v / max(0.0001, _current_map_zoom_cache),
		min_node_panel_padding,
		max_node_panel_padding
	)
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
	label_node.update_minimum_size() # Ensure label's min_size is current before we use it.
	label_node.reset_size() # Match size to the new minimum_size.
	var label_actual_min_size = label_node.get_minimum_size()
	var stylebox_margins = style_box.get_minimum_size()
	panel.custom_minimum_size = Vector2(
		label_actual_min_size.x + stylebox_margins.x,
		label_actual_min_size.y + stylebox_margins.y
	)
	panel.update_minimum_size()
	panel.reset_size()

func _position_settlement_panel(panel: Panel, settlement_info: Dictionary, _existing_label_rects: Array[Rect2]):
	# For settlements, anti-collision is often less critical or handled differently (e.g., fewer labels shown at once).
	if not is_instance_valid(panel) or not is_instance_valid(terrain_tilemap): return

	var tile_x: int = settlement_info.get('x', -1)
	var tile_y: int = settlement_info.get('y', -1)
	if tile_x < 0 or tile_y < 0: return

	# Ensure panel size is current
	var panel_actual_size = panel.size
	if panel_actual_size.x <= 0 or panel_actual_size.y <= 0:
		panel_actual_size = panel.get_minimum_size()

	# Get the local position of the tile center using TerrainTileMap (SubViewport-local)
	var tile_center = terrain_tilemap.map_to_local(Vector2i(tile_x, tile_y))
	var current_settlement_offset_above_center: float = base_settlement_offset_above_tile_center
	
	# Position label above the tile center, centered horizontally
	var panel_desired_x = tile_center.x - (panel_actual_size.x / 2.0)
	var panel_desired_y = tile_center.y - panel_actual_size.y - current_settlement_offset_above_center
	panel.position = Vector2(panel_desired_x, panel_desired_y)

	# --- Anti-collision logic ---
	var attempt := 0
	while attempt < 20: # Max attempts to find a clear spot
		var panel_rect := Rect2(panel.position, panel_actual_size)
		
		# Check against other labels
		var overlaps_labels := false
		for r in _existing_label_rects:
			if panel_rect.intersects(r.grow(2), true):
				overlaps_labels = true
				break
		
		# Check against convoy icons
		var overlaps_convoys := _settlement_panel_overlaps_convoy(panel_rect)

		if not overlaps_labels and not overlaps_convoys:
			break # Found a clear spot

		# Adjust position if there's an overlap
		# Nudge vertically, alternating up and down from the original position
		var nudge_factor = ceil(float(attempt + 1) / 2.0)
		var sign_dir = 1 if attempt % 2 == 0 else -1
		# Nudge away from the settlement icon (upwards is negative y)
		panel.position.y = panel_desired_y - (nudge_factor * label_anti_collision_y_shift * sign_dir)
		attempt += 1

func _rect_overlaps_circle(r: Rect2, c: Vector2, radius: float) -> bool:
	var closest_x = clamp(c.x, r.position.x, r.position.x + r.size.x)
	var closest_y = clamp(c.y, r.position.y, r.position.y + r.size.y)
	var dx = c.x - closest_x
	var dy = c.y - closest_y
	return (dx * dx + dy * dy) <= (radius * radius)

func _settlement_panel_overlaps_convoy(panel_rect: Rect2) -> bool:
	if not is_instance_valid(terrain_tilemap) or not is_instance_valid(terrain_tilemap.tile_set): return false
	if not _all_convoy_data_cache: return false

	var tile_size = terrain_tilemap.tile_set.tile_size
	for convoy_data in _all_convoy_data_cache:
		if not (convoy_data is Dictionary): continue
		
		var convoy_tile_x: float = convoy_data.get('x', -1.0)
		var convoy_tile_y: float = convoy_data.get('y', -1.0)
		if convoy_tile_x < 0.0: continue

		var convoy_center_pos = Vector2(
			(convoy_tile_x + 0.5) * tile_size.x,
			(convoy_tile_y + 0.5) * tile_size.y
		)

		if _rect_overlaps_circle(panel_rect, convoy_center_pos, settlement_convoy_keepout_radius):
			return true
			
	return false

func _find_settlement_at_tile(tile_x: int, tile_y: int) -> Variant:
	if not _all_settlement_data_cache: return null # Guard against null cache
	for settlement_data_entry in _all_settlement_data_cache:
		if settlement_data_entry is Dictionary:
			var s_tile_x = settlement_data_entry.get('x', -1)
			var s_tile_y = settlement_data_entry.get('y', -1)
			if s_tile_x == tile_x and s_tile_y == tile_y:
				return settlement_data_entry
	return null


func _on_menu_manager_menu_opened(menu_node: Node, menu_type: String):
	# When a convoy journey submenu opens, attach to its preview signals.
	if menu_type == "convoy_journey_submenu" and is_instance_valid(menu_node):
		if menu_node.has_signal("route_preview_started") and not menu_node.is_connected("route_preview_started", Callable(self, "_on_preview_route_started")):
			menu_node.route_preview_started.connect(_on_preview_route_started)
		if menu_node.has_signal("route_preview_ended") and not menu_node.is_connected("route_preview_ended", Callable(self, "_on_preview_route_ended")):
			menu_node.route_preview_ended.connect(_on_preview_route_ended)

func _on_preview_route_started(route_data: Dictionary):
	# route_data expected to contain nested 'journey' with route_x / route_y arrays.
	var journey_dict = route_data.get("journey", {})
	var rx = journey_dict.get("route_x", [])
	var ry = journey_dict.get("route_y", [])
	if rx is Array and ry is Array and rx.size() >= 2 and rx.size() == ry.size():
		_preview_route_x = rx.duplicate()
		_preview_route_y = ry.duplicate()
		_is_preview_active = true
		# Determine convoy color (if convoy_id provided) to match node color
		var convoy_id_val = route_data.get("convoy_id")
		if convoy_id_val == null and route_data.has("journey"):
			# Attempt nested convoy_id in journey
			convoy_id_val = journey_dict.get("convoy_id")
		if convoy_id_val != null:
			var c_color = _convoy_id_to_color_map_cache.get(str(convoy_id_val), _preview_color)
			_preview_color = c_color
		if is_instance_valid(convoy_connector_lines_container):
			convoy_connector_lines_container.queue_redraw()
	else:
		printerr("UIManager: Preview route data invalid; cannot draw preview line.")

func _on_preview_route_ended():
	_is_preview_active = false
	_preview_route_x.clear()
	_preview_route_y.clear()
	if is_instance_valid(convoy_connector_lines_container):
		convoy_connector_lines_container.queue_redraw()

func _on_connector_lines_container_draw():
	# Ensure terrain_tilemap is valid before using it
	if not is_instance_valid(terrain_tilemap):
		printerr("UIManager (_on_connector_lines_container_draw): terrain_tilemap is not assigned or invalid. Cannot draw connector lines.")
		return
	# --- Build shared-segment membership to compute lateral offsets for overlapping routes ---
	var shared_segments_membership: Dictionary = {}
	var tile_size_vec: Vector2 = Vector2.ZERO
	if is_instance_valid(terrain_tilemap.tile_set):
		tile_size_vec = terrain_tilemap.tile_set.tile_size
	var base_sep_px: float = max(1.0, min(tile_size_vec.x, tile_size_vec.y) * 0.28) # slightly more separation between lanes

	if _all_convoy_data_cache is Array:
		# Pass 1: collect segment membership across all convoys
		for convoy_collect in _all_convoy_data_cache:
			if not (convoy_collect is Dictionary and convoy_collect.has("journey")):
				continue
			var j_collect = convoy_collect.get("journey")
			if not (j_collect is Dictionary and j_collect.has("route_x") and j_collect.has("route_y")):
				continue
			var rx_c: Array = j_collect["route_x"]
			var ry_c: Array = j_collect["route_y"]
			if rx_c.size() < 2 or ry_c.size() != rx_c.size():
				continue
			var cid_c: String = str(convoy_collect.get("convoy_id", ""))
			if cid_c == "":
				continue
			for si in range(rx_c.size() - 1):
				var a := Vector2i(int(rx_c[si]), int(ry_c[si]))
				var b := Vector2i(int(rx_c[si + 1]), int(ry_c[si + 1]))
				# Normalize order for key stability
				var p1 := Vector2(min(a.x, b.x), min(a.y, b.y))
				var p2 := Vector2(max(a.x, b.x), max(a.y, b.y))
				var seg_key := "%s,%s-%s,%s" % [int(p1.x), int(p1.y), int(p2.x), int(p2.y)]
				if not shared_segments_membership.has(seg_key):
					shared_segments_membership[seg_key] = []
				if not shared_segments_membership[seg_key].has(cid_c):
					shared_segments_membership[seg_key].append(cid_c)
		# Sort memberships for deterministic lane ordering
		for k in shared_segments_membership.keys():
			shared_segments_membership[k].sort()

		# Pass 2: draw each convoy's journey with lateral offsets
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
			var cid: String = str(convoy.get("convoy_id", ""))
			if cid == "":
				continue

			# Compute pixel-space points for the route
			var base_points: Array[Vector2] = []
			for i in range(route_x.size()):
				var tile_x := int(route_x[i])
				var tile_y := int(route_y[i])
				base_points.append(terrain_tilemap.map_to_local(Vector2i(tile_x, tile_y)))

			# Compute per-segment normals and lane index for this convoy
			var seg_normals: Array[Vector2] = []
			var seg_lane_offsets: Array[float] = []
			var seg_member_counts: Array[int] = []
			for si in range(route_x.size() - 1):
				var pA: Vector2 = base_points[si]
				var pB: Vector2 = base_points[si + 1]
				var dir: Vector2 = pB - pA
				var nrm: Vector2 = Vector2.ZERO
				if dir.length() > 0.0001:
					nrm = Vector2(-dir.y, dir.x).normalized()
				seg_normals.append(nrm)
				# Determine lane offset multiplier for this segment based on membership index
				var a := Vector2i(int(route_x[si]), int(route_y[si]))
				var b := Vector2i(int(route_x[si + 1]), int(route_y[si + 1]))
				var p1 := Vector2(min(a.x, b.x), min(a.y, b.y))
				var p2 := Vector2(max(a.x, b.x), max(a.y, b.y))
				var seg_key := "%s,%s-%s,%s" % [int(p1.x), int(p1.y), int(p2.x), int(p2.y)]
				var members: Array = shared_segments_membership.get(seg_key, [])
				var idx: int = members.find(cid)
				var count: int = members.size()
				var lane_centered: float = 0.0
				if not (idx == -1 or count <= 1):
					lane_centered = (float(idx) - float(count - 1) * 0.5)
				seg_lane_offsets.append(lane_centered)
				seg_member_counts.append(count)

			# Build offset points by averaging adjacent segment offsets for interior vertices
			var offset_points: PackedVector2Array = []
			var min_gap_px: float = 2.0 # ensure a few pixels of separation at junctions
			for vi in range(base_points.size()):
				var off_vec: Vector2 = Vector2.ZERO
				if vi == 0:
					if seg_normals.size() >= 1:
						off_vec = seg_normals[0] * seg_lane_offsets[0] * base_sep_px
						# entering first shared segment: enforce a minimal gap
						if seg_member_counts.size() >= 1 and seg_member_counts[0] > 1:
							var lane_sign := 1.0 if seg_lane_offsets[0] >= 0.0 else -1.0
							if off_vec.length() < min_gap_px and seg_normals[0].length() > 0.0:
								off_vec = seg_normals[0] * lane_sign * min_gap_px
				elif vi == base_points.size() - 1:
					if seg_normals.size() >= 1:
						off_vec = seg_normals[seg_normals.size() - 1] * seg_lane_offsets[seg_lane_offsets.size() - 1] * base_sep_px
						# exiting last shared segment: enforce a minimal gap
						if seg_member_counts.size() >= 1 and seg_member_counts[seg_member_counts.size() - 1] > 1:
							var lane_sign2 := 1.0 if seg_lane_offsets[seg_lane_offsets.size() - 1] >= 0.0 else -1.0
							if off_vec.length() < min_gap_px and seg_normals[seg_normals.size() - 1].length() > 0.0:
								off_vec = seg_normals[seg_normals.size() - 1] * lane_sign2 * min_gap_px
				else:
					var prev_off := seg_normals[vi - 1] * seg_lane_offsets[vi - 1] * base_sep_px
					var next_off := seg_normals[vi] * seg_lane_offsets[vi] * base_sep_px
					var prev_count := seg_member_counts[vi - 1]
					var next_count := seg_member_counts[vi]
					# If entering a shared segment, bias toward next_off; if exiting, bias toward prev_off
					if prev_count <= 1 and next_count > 1:
						off_vec = next_off
					elif prev_count > 1 and next_count <= 1:
						off_vec = prev_off
					else:
						off_vec = (prev_off + next_off) * 0.5
					# Enforce a small minimum gap at the junction if any segment is shared
					if (prev_count > 1 or next_count > 1):
						var use_next := next_count > 1
						var chosen_n := seg_normals[vi] if use_next else seg_normals[vi - 1]
						var lane_c := seg_lane_offsets[vi] if use_next else seg_lane_offsets[vi - 1]
						var lane_sign3 := 1.0 if lane_c >= 0.0 else -1.0
						if off_vec.length() < min_gap_px and chosen_n.length() > 0.0:
							off_vec = chosen_n * lane_sign3 * min_gap_px
				offset_points.append(base_points[vi] + off_vec)

			if offset_points.size() >= 2:
				var convoy_color = _convoy_id_to_color_map_cache.get(cid, connector_line_color)
				var outline_w = max(0.0, connector_line_width + route_line_outline_extra_width)
				# White underlay for better contrast (larger width)
				convoy_connector_lines_container.draw_polyline(offset_points, Color(1,1,1,0.95), outline_w)
				# Colored path matching convoy icon (top stroke)
				convoy_connector_lines_container.draw_polyline(offset_points, convoy_color, connector_line_width)
	# --- Preview Route Drawing (after existing routes so it appears on top) ---
	if _is_preview_active and _preview_route_x.size() >= 2 and _preview_route_x.size() == _preview_route_y.size():
		var preview_points: PackedVector2Array = []
		for j in range(_preview_route_x.size()):
			var px = int(_preview_route_x[j])
			var py = int(_preview_route_y[j])
			var ppos = terrain_tilemap.map_to_local(Vector2i(px, py))
			preview_points.append(ppos)
		if preview_points.size() >= 2:
			var preview_outline_w = max(0.0, _preview_line_width + route_line_outline_extra_width)
			# White underlay for preview path (larger outline)
			convoy_connector_lines_container.draw_polyline(preview_points, Color(1,1,1,0.95), preview_outline_w)
			# Colored overlay matching convoy color
			convoy_connector_lines_container.draw_polyline(preview_points, _preview_color, _preview_line_width)

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

func _on_store_convoys_changed(all_convoy_data: Array) -> void:
	_all_convoy_data_cache = all_convoy_data
	_draw_interactive_labels({})

func _on_store_settlements_changed(settlement_data_list: Array) -> void:
	_all_settlement_data_cache = settlement_data_list
	_draw_interactive_labels({})

func _on_ui_scale_changed(new_scale: float):
	ui_overall_scale_multiplier = new_scale
	# Update viewport rect to ensure proper clamping after scale changes
	var map_view = get_node_or_null("/root/Main/MainScreen/MainContainer/MainContent/MapView")
	if is_instance_valid(map_view):
		var map_display_node = map_view.get_node_or_null("MapDisplay")
		if is_instance_valid(map_display_node) and map_display_node.has_method("get_global_rect"):
			_current_map_screen_rect_for_clamping = map_display_node.get_global_rect()
	else:
		# Fallback to viewport rect if map_view not found
		_current_map_screen_rect_for_clamping = get_viewport().get_visible_rect()
	_draw_interactive_labels({})
