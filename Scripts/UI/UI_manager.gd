extends CanvasLayer

@onready var _settings_service: Node = get_node_or_null("/root/MapSettingsService")
@onready var _user_service: Node = get_node_or_null("/root/UserService")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")

const _debug_map_menu: bool = true



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
@export var base_convoy_title_font_size: int = 36 # Was 29
@export var base_settlement_font_size: int = 32 # Was 24
## Minimum font size to set on the Label node.
@export var min_node_font_size: int = 8
## Maximum font size to set on the Label node.
@export var max_node_font_size: int = 120 # Increased from 60
## The map tile size that font scaling is based on. Should ideally match map_render's base_tile_size_for_proportions.
@export var font_scaling_base_tile_size: float = 32.0 # 24 * 1.33
## Exponent for font scaling (1.0 = linear, <1.0 less aggressive shrink/grow).
@export var font_scaling_exponent: float = 0.6 

@export_group("Zoom Smoothing")
## How fast label panels lerp to the new zoom scale. Higher = snappier. ~8 feels smooth, ~20 is near-instant.
@export var zoom_lerp_speed: float = 10.0

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
@export var convoy_panel_background_color: Color = Color("25282adc") # Oori Dark Grey with 0.86 alpha
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
@export var settlement_panel_background_color: Color = Color("25282ad9") # Oori Dark Grey with 0.85 alpha

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
@export var route_line_outline_extra_width: float = 2.0 # thinner border for more prominent colors

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
var _current_map_zoom_cache: float = 1.0 # Cache for current map zoom level (the real/target zoom)
var _display_zoom: float = 1.0            # Smoothed zoom used for panel scale — lerps toward _current_map_zoom_cache
var _current_hover_info_cache: Dictionary = {} # Cache for hover state
var _current_map_screen_rect_for_clamping: Rect2

var _active_settlement_panels: Dictionary = {} # { "tile_coord_str": PanelNode }
var _pinned_settlement_coords: Array[Vector2i] = []

# Set each draw pass — used by overlay and dimming logic.
var _coords_to_targeting_convoys: Dictionary = {}  # Vector2i → Array[String convoy_id]
var _focused_convoy_ids_last: Array[String] = []   # focused convoy IDs from last draw pass

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
var _preview_settlement_coords: Variant = null

var _convoy_label_manager_initialized: bool = false

# Settlement overlay: draws callout tails and tile icons (settlement_overlay_draw.gd)
var _settlement_overlay: Node = null  # tails + outlines (z_index -1, behind panels)
var _pin_overlay: Node = null          # focus pins only  (z_index 10, in front of panels)
var _grid_overlay: Node = null         # coordinate grid lines (child of terrain tilemap)

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
	var fallback_font: Font = load("res://Assets/main_font.tres")
	if not is_instance_valid(fallback_font):
		fallback_font = ThemeDB.fallback_font
	if is_instance_valid(fallback_font):
		label_settings.font = fallback_font
		settlement_label_settings.font = fallback_font

	_current_map_screen_rect_for_clamping = get_viewport().get_visible_rect() # Initialize

	# Create the settlement overlay draw node (tails + tile icons)
	_ensure_settlement_overlay()

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

	# --- Map Settings Overlay Signal Integration ---
	if is_instance_valid(_hub) and _hub.has_signal("map_overlay_settings_changed"):
		if not _hub.map_overlay_settings_changed.is_connected(_on_map_overlay_settings_changed):
			_hub.map_overlay_settings_changed.connect(_on_map_overlay_settings_changed)


func _process(delta: float) -> void:
	# Smoothly lerp the display zoom toward the real zoom each frame.
	# While it's still converging, redraw so panel scales animate continuously.
	if is_equal_approx(_display_zoom, _current_map_zoom_cache):
		return
	_display_zoom = lerp(_display_zoom, _current_map_zoom_cache, clampf(delta * zoom_lerp_speed, 0.0, 1.0))
	# Snap to target when close enough to avoid infinite micro-animation.
	if absf(_display_zoom - _current_map_zoom_cache) < 0.0005:
		_display_zoom = _current_map_zoom_cache
	# Redraw settlement labels with smoothed zoom.
	_draw_interactive_labels(_current_hover_info_cache)
	# Redraw convoy labels with smoothed zoom.
	if is_instance_valid(convoy_label_manager) \
			and convoy_label_manager.has_method("update_drawing_parameters") \
			and is_instance_valid(terrain_tilemap) \
			and is_instance_valid(terrain_tilemap.tile_set):
		var ts = terrain_tilemap.tile_set.tile_size
		convoy_label_manager.update_drawing_parameters(ts.x, ts.y, _display_zoom, 1.0, 0.0, 0.0)
	if is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("update_convoy_labels"):
		convoy_label_manager.update_convoy_labels(
			_all_convoy_data_cache,
			_convoy_id_to_color_map_cache,
			_current_hover_info_cache,
			_selected_convoy_ids_cache,
			_convoy_label_user_positions,
			_dragging_panel_node,
			_dragged_convoy_id_actual_str,
			_current_map_screen_rect_for_clamping,
		)


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
			if convoy_data_item is Dictionary and str(convoy_data_item.get("convoy_id")) != "":
				_convoy_data_by_id_cache[str(convoy_data_item.get("convoy_id"))] = convoy_data_item

	_current_map_zoom_cache = current_map_zoom # Cache the zoom level
	_current_hover_info_cache = current_hover_info # Cache hover info for redraw logic

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
		convoy_label_manager.update_drawing_parameters(ts.x, ts.y, _display_zoom, 1.0, 0.0, 0.0)
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
				pass # Intentionally disabled: let settlement panels pan off-screen naturally
				# _clamp_panel_position_optimized(panel_node, clamp_rect_local_to_settlement_container)

func _clamp_panel_position_optimized(panel: Panel, precalculated_clamp_rect_local_to_container: Rect2):
	# Helper to clamp a panel's position to the viewport boundaries using a precalculated clamping rectangle in the panel's parent container's local space.
	if not is_instance_valid(panel):
		return

	var panel_actual_size = panel.size
	if panel_actual_size.x <= 0 or panel_actual_size.y <= 0:
		panel_actual_size = panel.get_minimum_size()

	var scaled_size = panel_actual_size * panel.scale
	var padded_min_x = precalculated_clamp_rect_local_to_container.position.x + label_map_edge_padding
	var padded_min_y = precalculated_clamp_rect_local_to_container.position.y + label_map_edge_padding
	var padded_max_x = precalculated_clamp_rect_local_to_container.position.x + precalculated_clamp_rect_local_to_container.size.x - scaled_size.x - label_map_edge_padding
	var padded_max_y = precalculated_clamp_rect_local_to_container.position.y + precalculated_clamp_rect_local_to_container.size.y - scaled_size.y - label_map_edge_padding

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

	var scaled_size = panel_actual_size * panel.scale
	var padded_min_x = clamp_rect_local_to_container.position.x + label_map_edge_padding
	var padded_min_y = clamp_rect_local_to_container.position.y + label_map_edge_padding
	var padded_max_x = clamp_rect_local_to_container.position.x + clamp_rect_local_to_container.size.x - scaled_size.x - label_map_edge_padding
	var padded_max_y = clamp_rect_local_to_container.position.y + clamp_rect_local_to_container.size.y - scaled_size.y - label_map_edge_padding

	panel.position.x = clamp(panel.position.x, padded_min_x, padded_max_x)
	panel.position.y = clamp(panel.position.y, padded_min_y, padded_max_y)

func toggle_settlement_pin(coords: Vector2i):
	var settlement_name = "Unknown"
	var settlement_info = _find_settlement_at_tile(coords.x, coords.y)
	if settlement_info != null:
		settlement_name = settlement_info.get("name", "Unknown")

	print("[UIManager] Toggling settlement pin for: ", coords, " (", settlement_name, ")")
	if _pinned_settlement_coords.has(coords):
		print("[UIManager]   Removing pin")
		_pinned_settlement_coords.erase(coords)
	else:
		print("[UIManager]   Adding pin")
		_pinned_settlement_coords.append(coords)

func clear_all_settlement_pins():
	_pinned_settlement_coords.clear()
	_force_draw_interactive_labels_deferred()

func _draw_interactive_labels(current_hover_info: Dictionary):
	if is_instance_valid(_dragging_panel_node):
		pass # Let's assume UIManager will handle it.
	var drawn_settlement_tile_coords_this_update: Array[Vector2i] = []
	var all_drawn_label_rects_this_update: Array[Rect2] = []
	var convoy_ids_to_display: Array[String] = []
	var settlement_coords_to_display: Array[Vector2i] = []
	var coords_to_targeting_convoys: Dictionary = {}
	var coords_to_cargo_names: Dictionary = {}  # Vector2i -> Array[String] of cargo headed there
	var warehouse_ids_cache: Array[String] = _get_player_warehouse_settlement_ids()

	var add_settlement_target = func(coords: Vector2i, convoy_id_str: String = ""):
		if not settlement_coords_to_display.has(coords):
			settlement_coords_to_display.append(coords)
		if convoy_id_str != "":
			if not coords_to_targeting_convoys.has(coords):
				coords_to_targeting_convoys[coords] = []
			if not coords_to_targeting_convoys[coords].has(convoy_id_str):
				coords_to_targeting_convoys[coords].append(convoy_id_str)

	# Retrieve current overlay settings
	var show_all_settlements: bool = true
	var show_active_dests: bool = true
	var show_local_sett_dests: bool = true
	var show_all_convoy_dests: bool = false

	var show_warehouses: bool = true
	
	if is_instance_valid(_settings_service):
		show_all_settlements = _settings_service.settlement_labels
		show_active_dests = _settings_service.active_delivery_destinations
		show_local_sett_dests = _settings_service.settlement_delivery_destinations
		show_all_convoy_dests = _settings_service.all_convoy_destinations
		show_warehouses = _settings_service.warehouse_labels

	# --- Strategy 3: Progressive Zoom LOD ---
	var is_far_zoom: bool = _current_map_zoom_cache < 0.6
	
	# --- Strategy 1: Smart Focus (Selected + Hovered) ---
	var focused_convoy_ids: Array[String] = []
	if not _selected_convoy_ids_cache.is_empty():
		for fcid in _selected_convoy_ids_cache:
			focused_convoy_ids.append(str(fcid))

	if current_hover_info.get('type') == 'convoy':
		var hover_id = str(current_hover_info.get('id', ''))
		if hover_id != '' and not focused_convoy_ids.has(hover_id):
			focused_convoy_ids.append(hover_id)

	_focused_convoy_ids_last = focused_convoy_ids

	if is_far_zoom:
		# ONLY hide generic settlements on far zoom, but leave the active/local targets visible!
		show_all_settlements = false
		show_warehouses = false # Minimalist map

	# Include pinned settlements
	for pinned_coords in _pinned_settlement_coords:
		add_settlement_target.call(pinned_coords)

	# Include preview route destination
	if _is_preview_active and _preview_route_x.size() > 0:
		var end_tile_coords := Vector2i(int(_preview_route_x.back()), int(_preview_route_y.back()))
		var targeting_cid = ""
		if not focused_convoy_ids.is_empty():
			targeting_cid = focused_convoy_ids[0]
		add_settlement_target.call(end_tile_coords, targeting_cid)

	# Include destination preview settlement
	if _preview_settlement_coords is Vector2i:
		add_settlement_target.call(_preview_settlement_coords)

	# Show ALL Discovered Settlements (if setting is enabled)
	if show_all_settlements and _all_settlement_data_cache is Array:
		for s in _all_settlement_data_cache:
			if s is Dictionary:
				var coords = Vector2i(int(s.get("x", 0)), int(s.get("y", 0)))
				add_settlement_target.call(coords)

	# Show Warehouse Indicators (if setting is enabled)
	if show_warehouses:
		if _all_settlement_data_cache is Array:
			for s in _all_settlement_data_cache:
				if s is Dictionary:
					var sett_id = str(s.get("sett_id", s.get("id", "")))
					if sett_id != "" and warehouse_ids_cache.has(sett_id):
						var coords = Vector2i(int(s.get("x", 0)), int(s.get("y", 0)))
						add_settlement_target.call(coords)

	# Active Convoy Targets: cargo destinations in focused convoy(s)
	if show_active_dests and not focused_convoy_ids.is_empty():
		for convoy_data in _all_convoy_data_cache:
			if convoy_data is Dictionary:
				var convoy_id = convoy_data.get('convoy_id')
				var convoy_id_str = str(convoy_id)
				if convoy_id != null and focused_convoy_ids.has(convoy_id_str):
					var dests = _get_convoy_cargo_destination_coords(convoy_data, coords_to_cargo_names)
					for d in dests:
						add_settlement_target.call(d, convoy_id_str)

	# Local Settlement Targets: departing routes from focused convoy's current city, hovered settlement, or pinned settlements
	if show_local_sett_dests:
		# A. From focused convoys
		if not focused_convoy_ids.is_empty():
			for convoy_data in _all_convoy_data_cache:
				if convoy_data is Dictionary:
					var convoy_id = convoy_data.get('convoy_id')
					var convoy_id_str = str(convoy_id)
					if convoy_id != null and focused_convoy_ids.has(convoy_id_str):
						var cx = float(convoy_data.get("x", -999.0))
						var cy = float(convoy_data.get("y", -999.0))
						var local_sett = _find_closest_settlement(cx, cy, 2.5)
						if local_sett is Dictionary:
							var dests = _get_settlement_departing_destinations(local_sett, coords_to_cargo_names)
							for d in dests:
								add_settlement_target.call(d)

		# B. From currently hovered settlement
		if current_hover_info.get('type') == 'settlement':
			var hovered_coords = current_hover_info.get('coords')
			if hovered_coords is Vector2i:
				var local_sett = _find_settlement_at_tile(hovered_coords.x, hovered_coords.y)
				if local_sett is Dictionary:
					var dests = _get_settlement_departing_destinations(local_sett, coords_to_cargo_names)
					for d in dests:
						add_settlement_target.call(d)

		# C. From pinned settlements
		for pinned_coords in _pinned_settlement_coords:
			var local_sett = _find_settlement_at_tile(pinned_coords.x, pinned_coords.y)
			if local_sett is Dictionary:
				var dests = _get_settlement_departing_destinations(local_sett, coords_to_cargo_names)
				for d in dests:
					add_settlement_target.call(d)

	# All Convoy Targets: destinations of ALL active player convoy journeys and cargo
	if show_all_convoy_dests and _all_convoy_data_cache is Array:
		for convoy_data in _all_convoy_data_cache:
			if convoy_data is Dictionary:
				var convoy_id = convoy_data.get('convoy_id')
				var convoy_id_str = str(convoy_id)
				if convoy_id_str != "":
					# 1. Cargo destinations of this convoy
					var dests = _get_convoy_cargo_destination_coords(convoy_data, coords_to_cargo_names)
					for d in dests:
						add_settlement_target.call(d, convoy_id_str)
						
					# 2. Active journey destination
					var journey_data = convoy_data.get('journey')
					if journey_data is Dictionary:
						var rx = journey_data.get('route_x')
						var ry = journey_data.get('route_y')
						if rx is Array and ry is Array and rx.size() > 0 and rx.size() == ry.size():
							var end_coords = Vector2i(int(rx[rx.size() - 1]), int(ry[ry.size() - 1]))
							add_settlement_target.call(end_coords, convoy_id_str)

	# Active Convoy Route Targets: start/end coordinates of focused convoy routes
	if not focused_convoy_ids.is_empty():
		for convoy_data in _all_convoy_data_cache:
			if convoy_data is Dictionary:
				var convoy_id = convoy_data.get('convoy_id')
				var convoy_id_str = str(convoy_id)
				if convoy_id != null and focused_convoy_ids.has(convoy_id_str):
					var journey_data = convoy_data.get('journey')
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
							add_settlement_target.call(start_tile_coords, convoy_id_str)

							if route_x_coords.size() > 0:
								var end_tile_x: int = floori(float(route_x_coords.back()))
								var end_tile_y: int = floori(float(route_y_coords.back()))
								var end_tile_coords := Vector2i(end_tile_x, end_tile_y)
								if end_tile_coords != start_tile_coords:
									add_settlement_target.call(end_tile_coords, convoy_id_str)

	# Ensure hovered settlement coords are added
	if current_hover_info.get('type') == 'settlement':
		var hovered_tile_coords = current_hover_info.get('coords')
		if hovered_tile_coords is Vector2i and hovered_tile_coords.x >= 0 and hovered_tile_coords.y >= 0:
			add_settlement_target.call(hovered_tile_coords)


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
		if not settlement_data_for_panel: 
			print("[UIManager] WARNING: Could not find settlement data for resolved target coordinate: ", settlement_coord_to_draw)
			continue

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

		var targeting_convoys = coords_to_targeting_convoys.get(settlement_coord_to_draw, [])
		var cargo_names: Array = coords_to_cargo_names.get(settlement_coord_to_draw, [])
		# A delivery destination (has cargo headed to it) is never a "plain" label.
		var is_plain := cargo_names.is_empty() and _is_plain_settlement_label(
			settlement_coord_to_draw, settlement_data_for_panel, targeting_convoys,
			show_all_settlements, current_hover_info, warehouse_ids_cache
		)
		_update_settlement_panel_content(panel_node, settlement_data_for_panel, targeting_convoys, cargo_names, is_plain)
		panel_node.visible = true
		# print("UIManager:_draw_interactive_labels - Positioning/Clamping settlement panel for coords: ", settlement_coord_to_draw, " at pos: ", panel_node.position) # DEBUG
		_position_settlement_panel(panel_node, settlement_data_for_panel, all_drawn_label_rects_this_update)
		# Intentionally disabled: let settlement panels pan off-screen naturally
		# _clamp_panel_position(panel_node)
		
		var current_settlement_panel_actual_size = panel_node.size
		if current_settlement_panel_actual_size.x <= 0 or current_settlement_panel_actual_size.y <= 0:
			current_settlement_panel_actual_size = panel_node.get_minimum_size()
		var scaled_size = current_settlement_panel_actual_size * panel_node.scale
		all_drawn_label_rects_this_update.append(Rect2(panel_node.position, scaled_size))
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

	# Persist targeting map for overlay + dimming.
	_coords_to_targeting_convoys = coords_to_targeting_convoys

	# --- Dimming: determine which panels are "related" to the current focus ---
	_apply_settlement_panel_dimming(
		focused_convoy_ids,
		current_hover_info,
		coords_to_targeting_convoys,
		drawn_settlement_tile_coords_this_update
	)

	# Request redraw for connector lines (this part is fine)
	if is_instance_valid(convoy_connector_lines_container):
		convoy_connector_lines_container.queue_redraw()

	# Refresh settlement tails + tile outlines overlay
	_refresh_settlement_overlay(drawn_settlement_tile_coords_this_update)

	# Refresh coordinate grid overlay (independent of settlement labels)
	_refresh_grid_overlay()

## Dim settlement panels that are unrelated to the current focus (selected/hovered convoy or settlement).
## Related panels stay at full opacity; unrelated ones fade to DIM_ALPHA.
func _apply_settlement_panel_dimming(
		focused_ids: Array[String],
		hover_info: Dictionary,
		targeting_map: Dictionary,
		drawn_coords: Array
) -> void:
	const DIM_ALPHA: float = 0.25
	const FULL_ALPHA: float = 1.0

	var hover_type: String  = hover_info.get("type", "")
	var hover_coords: Variant = hover_info.get("coords", null)
	var is_settlement_hovered: bool = hover_type == "settlement" and hover_coords is Vector2i

	# No focus at all → restore everything to its base brightness (plain labels stay
	# translucent when "Settlement Labels" is on; everything else goes full opacity).
	if focused_ids.is_empty() and not is_settlement_hovered:
		for coord_str in _active_settlement_panels.keys():
			var p: Panel = _active_settlement_panels[coord_str]
			if is_instance_valid(p):
				var base_a: float = p.get_meta("plain_alpha", 1.0)
				p.modulate = Color(1.0, 1.0, 1.0, base_a)
		return

	# Build the set of "related" coords.
	var related: Dictionary = {}  # Vector2i → true (used as a set)

	# 1. Settlements targeted by any focused convoy.
	for coord in targeting_map.keys():
		var ids: Array = targeting_map[coord]
		for fid in focused_ids:
			if ids.has(fid):
				related[coord] = true
				break

	# 2. Settlement the focused convoy is currently sitting on.
	for convoy_data in _all_convoy_data_cache:
		if not convoy_data is Dictionary:
			continue
		var cid: String = str(convoy_data.get("convoy_id", ""))
		if not focused_ids.has(cid):
			continue
		var cx: float = float(convoy_data.get("x", -999.0))
		var cy: float = float(convoy_data.get("y", -999.0))
		var sett = _find_closest_settlement(cx, cy, 2.5)
		if sett is Dictionary:
			related[Vector2i(int(sett.get("x", 0)), int(sett.get("y", 0)))] = true

	# 3. Hovered settlement + its route-mates.
	if is_settlement_hovered:
		related[hover_coords] = true
		var hovered_ids: Array = targeting_map.get(hover_coords, [])
		for coord in targeting_map.keys():
			var ids: Array = targeting_map[coord]
			for tid in ids:
				if hovered_ids.has(tid):
					related[coord] = true
					break

	# Apply modulate to every visible panel.
	for coord_str in _active_settlement_panels.keys():
		var p: Panel = _active_settlement_panels[coord_str]
		if not is_instance_valid(p) or not p.visible:
			continue
		var parts: PackedStringArray = coord_str.split("_")
		if parts.size() != 2:
			continue
		var coord := Vector2i(parts[0].to_int(), parts[1].to_int())
		var base_a: float = p.get_meta("plain_alpha", FULL_ALPHA)
		p.modulate = Color(1.0, 1.0, 1.0, base_a if related.has(coord) else minf(base_a, DIM_ALPHA))


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

	# Settlement panels are visual overlays rendered in a Node2D inside a CanvasLayer.
	# Controls inside Node2D containers don't participate in Godot's GUI input
	# routing, so mouse_filter has no reliable effect here. Click handling is done
	# entirely via hit-rect tests in MapInteractionManager.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label_node := Label.new()
	label_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_node.label_settings = settlement_label_settings # Assign shared LabelSettings
	panel.add_child(label_node)
	panel.set_meta("label_node_ref", label_node)

	return panel

## Schedules a label redraw on the next frame so the pin state change is
## immediately reflected without needing a hover or selection change.
func _force_draw_interactive_labels_deferred() -> void:
	call_deferred("_draw_interactive_labels", {})

## A "plain" label is a generic discovered-city label shown only because the
## "Settlement Labels" overlay is on. Delivery targets, warehouses, pinned, and
## hovered settlements are NOT plain (they keep full size + opacity).
func _is_plain_settlement_label(
		coords: Vector2i,
		sett_info: Dictionary,
		targeting_convoys: Array,
		show_all_settlements: bool,
		hover_info: Dictionary,
		warehouse_ids: Array
) -> bool:
	if not show_all_settlements:
		return false
	if not targeting_convoys.is_empty():
		return false
	if _pinned_settlement_coords.has(coords):
		return false
	if hover_info.get('type') == 'settlement' and hover_info.get('coords') == coords:
		return false
	var sid := str(sett_info.get("sett_id", sett_info.get("id", "")))
	if sid != "" and warehouse_ids.has(sid):
		return false
	return true


# -------------------------------------------------------------------
# Coordinate grid overlay
# -------------------------------------------------------------------

func _ensure_grid_overlay() -> void:
	if is_instance_valid(_grid_overlay):
		return
	if not is_instance_valid(terrain_tilemap):
		return
	var script = load("res://Scripts/UI/map_grid_overlay.gd")
	if script == null:
		printerr("[UIManager] Could not load map_grid_overlay.gd")
		return
	_grid_overlay = Node2D.new()
	_grid_overlay.set_script(script)
	_grid_overlay.z_index = 0  # above terrain tiles, beneath labels/convoys
	# Child of the tilemap so local coords match TileMapLayer.map_to_local().
	terrain_tilemap.add_child(_grid_overlay)

## Pushes current grid parameters to the grid overlay. Safe to call every frame;
## the overlay only redraws when something visible actually changed.
func _refresh_grid_overlay() -> void:
	var enabled: bool = is_instance_valid(_settings_service) and _settings_service.grid_lines
	if not enabled:
		if is_instance_valid(_grid_overlay) and _grid_overlay.has_method("update_grid"):
			_grid_overlay.update_grid(false, Vector2.ZERO, 0, 0, Vector2.ONE, _display_zoom)
		return
	if not is_instance_valid(terrain_tilemap):
		return
	_ensure_grid_overlay()
	if not is_instance_valid(_grid_overlay):
		return
	var tile_size: Vector2 = Vector2(32.0, 32.0)
	if is_instance_valid(terrain_tilemap.tile_set):
		tile_size = Vector2(terrain_tilemap.tile_set.tile_size)
	var used: Rect2i = terrain_tilemap.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		_grid_overlay.update_grid(false, Vector2.ZERO, 0, 0, tile_size, _display_zoom)
		return
	# map_to_local returns the cell center; shift to the cell's top-left corner.
	var origin: Vector2 = terrain_tilemap.map_to_local(used.position) - tile_size * 0.5
	_grid_overlay.update_grid(true, origin, used.size.x, used.size.y, tile_size, _display_zoom)


# -------------------------------------------------------------------
# Settlement overlay helpers (callout tails + tile icons)
# -------------------------------------------------------------------

func _ensure_settlement_overlay() -> void:
	if is_instance_valid(_settlement_overlay):
		return
	if not is_instance_valid(settlement_label_container):
		return
	var script = load("res://Scripts/UI/settlement_overlay_draw.gd")
	if script == null:
		printerr("[UIManager] Could not load settlement_overlay_draw.gd")
		return
	_settlement_overlay = Node2D.new()
	_settlement_overlay.set_script(script)
	_settlement_overlay.z_index = -1  # behind panels — tails + outlines only
	settlement_label_container.add_child(_settlement_overlay)

	_pin_overlay = Node2D.new()
	_pin_overlay.set_script(script)
	_pin_overlay.z_index = 10  # in front of panels — pins only
	settlement_label_container.add_child(_pin_overlay)


## Collect tail + outline data from all visible panels and push to the overlay node.
## Called at the end of _draw_interactive_labels after all panels are positioned.
func _refresh_settlement_overlay(drawn_coords: Array) -> void:
	_ensure_settlement_overlay()
	if not is_instance_valid(_settlement_overlay):
		return
	if not is_instance_valid(terrain_tilemap):
		_settlement_overlay.clear_frame()
		if is_instance_valid(_pin_overlay):
			_pin_overlay.clear_frame()
		return

	var tile_size: Vector2 = Vector2(32.0, 32.0)
	if is_instance_valid(terrain_tilemap) and is_instance_valid(terrain_tilemap.tile_set):
		tile_size = Vector2(terrain_tilemap.tile_set.tile_size)

	var tail_list: Array    = []
	var outline_list: Array = []

	# --- Build panel-based tails and outlines ---
	for coords in drawn_coords:
		var coord_str := "%s_%s" % [coords.x, coords.y]
		var panel: Panel = _active_settlement_panels.get(coord_str)
		if not is_instance_valid(panel) or not panel.visible:
			continue

		var sett_info = _find_settlement_at_tile(coords.x, coords.y)
		if not sett_info is Dictionary:
			continue

		var tile_center: Vector2 = terrain_tilemap.map_to_local(coords)
		var panel_scale: float   = panel.scale.x  # uniform scale = 1/zoom

		# --- Tail ---
		var actual_size: Vector2 = panel.size
		if actual_size.x <= 0 or actual_size.y <= 0:
			actual_size = panel.get_minimum_size()
		var scaled_size: Vector2         = actual_size * panel.scale
		var panel_bottom_center: Vector2 = panel.position + Vector2(scaled_size.x * 0.5, scaled_size.y)
		var bg_color: Color              = panel.get_meta("bg_color", settlement_panel_background_color)
		bg_color.a *= panel.modulate.a

		tail_list.append({
			"panel_bottom_center": panel_bottom_center,
			"tile_center":         tile_center,
			"bg_color":            bg_color,
			"panel_scale":         panel_scale,
		})

		# --- Tile outline ---
		var outline_col: Color = panel.get_meta("outline_color", Color.TRANSPARENT)
		if outline_col == Color.TRANSPARENT:
			outline_col = Color(1.0, 1.0, 1.0, 0.55)
		outline_col.a *= panel.modulate.a
		outline_list.append({
			"tile_center": tile_center,
			"color":       outline_col,
		})

	# --- Focus pins — built from persistent state, not hover ---
	# Pins mark the origin of the current focus so the user always knows what's highlighted.
	# Sources (all persistent, not hover-dependent):
	#   1. Selected convoys  (_selected_convoy_ids_cache)
	#   2. Pinned convoys    (convoy_label_manager._pinned_convoy_ids via accessor)
	#   3. Pinned settlements (_pinned_settlement_coords)
	# Hover adds a temporary extra pin on top.
	var focus_pins: Array = []

	# Collect all persistent focused convoy IDs (selected + pinned).
	var persistent_convoy_ids: Dictionary = {}  # id → true (set)
	if _selected_convoy_ids_cache is Array:
		for cid in _selected_convoy_ids_cache:
			persistent_convoy_ids[str(cid)] = true
	if is_instance_valid(convoy_label_manager) and convoy_label_manager.has_method("get_pinned_convoy_ids"):
		for cid in convoy_label_manager.get_pinned_convoy_ids():
			persistent_convoy_ids[str(cid)] = true

	# Pin at each focused convoy's current tile.
	for convoy_data in _all_convoy_data_cache:
		if not convoy_data is Dictionary:
			continue
		var cid: String = str(convoy_data.get("convoy_id", ""))
		if not persistent_convoy_ids.has(cid):
			continue
		var cx: float = float(convoy_data.get("x", -999.0))
		var cy: float = float(convoy_data.get("y", -999.0))
		if cx < 0.0 or cy < 0.0:
			continue
		var convoy_col: Color = _convoy_id_to_color_map_cache.get(cid, Color.WHITE)
		focus_pins.append({
			"tile_center": terrain_tilemap.map_to_local(Vector2i(floori(cx), floori(cy))),
			"color":       convoy_col,
		})

	# Pin at each pinned settlement.
	for pinned_coords in _pinned_settlement_coords:
		focus_pins.append({
			"tile_center": terrain_tilemap.map_to_local(pinned_coords),
			"color":       Color(1.0, 1.0, 1.0, 0.95),
		})

	# Hover adds a temporary pin (hovered convoy or settlement) on top.
	var hover_type: String    = _current_hover_info_cache.get("type", "")
	var hover_coords: Variant = _current_hover_info_cache.get("coords", null)
	if hover_type == "settlement" and hover_coords is Vector2i:
		focus_pins.append({
			"tile_center": terrain_tilemap.map_to_local(hover_coords),
			"color":       Color(1.0, 1.0, 1.0, 0.95),
		})
	elif hover_type == "convoy":
		var hid: String = str(_current_hover_info_cache.get("id", ""))
		if not hid.is_empty() and not persistent_convoy_ids.has(hid):
			# Only add hover pin if not already shown as a persistent pin.
			for convoy_data in _all_convoy_data_cache:
				if not convoy_data is Dictionary: continue
				if str(convoy_data.get("convoy_id", "")) != hid: continue
				var cx: float = float(convoy_data.get("x", -999.0))
				var cy: float = float(convoy_data.get("y", -999.0))
				if cx >= 0.0 and cy >= 0.0:
					var hcol: Color = _convoy_id_to_color_map_cache.get(hid, Color.WHITE)
					focus_pins.append({
						"tile_center": terrain_tilemap.map_to_local(Vector2i(floori(cx), floori(cy))),
						"color":       hcol,
					})
				break

	# --- Route arcs: focused convoy → cargo destinations; pinned settlement → departing destinations ---
	var arc_list: Array = []

	# Arcs from each focused/selected convoy.
	for convoy_data in _all_convoy_data_cache:
		if not convoy_data is Dictionary:
			continue
		var cid: String = str(convoy_data.get("convoy_id", ""))
		if not persistent_convoy_ids.has(cid):
			continue
		var cx: float = float(convoy_data.get("x", -999.0))
		var cy: float = float(convoy_data.get("y", -999.0))
		if cx < 0.0 or cy < 0.0:
			continue
		var src: Vector2    = terrain_tilemap.map_to_local(Vector2i(floori(cx), floori(cy)))
		var convoy_col: Color = _convoy_id_to_color_map_cache.get(cid, Color.WHITE)
		var arc_col: Color    = Color(convoy_col.r, convoy_col.g, convoy_col.b, 0.55)
		for dest_coords in _get_convoy_cargo_destination_coords(convoy_data):
			arc_list.append({
				"from":  src,
				"to":    terrain_tilemap.map_to_local(dest_coords),
				"color": arc_col,
			})

	# Arcs from each pinned settlement.
	for pinned_coords in _pinned_settlement_coords:
		var sett = _find_settlement_at_tile(pinned_coords.x, pinned_coords.y)
		if not sett is Dictionary:
			continue
		var src: Vector2 = terrain_tilemap.map_to_local(pinned_coords)
		for dest_coords in _get_settlement_departing_destinations(sett):
			arc_list.append({
				"from":  src,
				"to":    terrain_tilemap.map_to_local(dest_coords),
				"color": Color(1.0, 1.0, 1.0, 0.45),
			})

	# Tails + outlines + arcs go behind panels; pins go in front.
	_settlement_overlay.update_frame(tail_list, outline_list, _current_map_zoom_cache, tile_size, [], arc_list)
	if is_instance_valid(_pin_overlay):
		_pin_overlay.update_frame([], [], _current_map_zoom_cache, tile_size, focus_pins)


func _on_map_overlay_settings_changed(_settings: Dictionary) -> void:
	if _debug_map_menu:
		print("[UIManager] Map overlay settings updated. Forcing redraw.")
	_force_draw_interactive_labels_deferred()

func _find_settlement_by_name(s_name: String) -> Variant:
	if s_name.is_empty() or not _all_settlement_data_cache: return null
	
	var target_name = s_name.strip_edges()
	if "(" in target_name:
		target_name = target_name.split("(")[0].strip_edges()
		
	# 1. Direct search by settlement name
	for s in _all_settlement_data_cache:
		if s is Dictionary:
			if str(s.get("name", "")).strip_edges().to_lower() == target_name.to_lower():
				return s
				
	# 2. Fallback search by checking vendor name
	for s in _all_settlement_data_cache:
		if s is Dictionary:
			var vendors = s.get("vendors", [])
			if vendors is Array:
				for v in vendors:
					if v is Dictionary:
						if str(v.get("name", "")).strip_edges().to_lower() == target_name.to_lower():
							return s
							
	# 3. Partial match as last resort
	for s in _all_settlement_data_cache:
		if s is Dictionary:
			var s_n := str(s.get("name", "")).strip_edges().to_lower()
			if s_n in target_name.to_lower() or target_name.to_lower() in s_n:
				return s
				
	return null

func _find_settlement_by_id(s_id: String) -> Variant:
	if s_id.is_empty() or not _all_settlement_data_cache: return null
	# 1. Direct search by settlement id or sett_id
	for s in _all_settlement_data_cache:
		if s is Dictionary:
			var sid = str(s.get("sett_id", s.get("id", "")))
			if sid == s_id:
				return s
	
	# 2. Fallback search by checking if s_id is a vendor ID belonging to any settlement
	for s in _all_settlement_data_cache:
		if s is Dictionary:
			var vendors = s.get("vendors", [])
			if vendors is Array:
				for v in vendors:
					if v is Dictionary:
						var vid = str(v.get("vendor_id", v.get("id", "")))
						if vid == s_id:
							return s
	return null

func _get_player_warehouse_settlement_ids() -> Array[String]:
	var ids: Array[String] = []
	if is_instance_valid(_user_service) and _user_service.has_method("get_user"):
		var user = _user_service.get_user()
		if user is Dictionary:
			var warehouses = user.get("warehouses", [])
			if warehouses is Array:
				for w in warehouses:
					if w is Dictionary:
						var sett_id = str(w.get("sett_id", ""))
						if sett_id != "":
							ids.append(sett_id)
	return ids

func _resolve_cargo_destination_coords(item: Dictionary) -> Variant:
	# 1. Gather all possible ID fields
	var id_fields := ["recipient", "recipient_settlement_id", "settlement_id", "sett_id", "mission_vendor_id", "recipient_vendor_id", "destination_vendor_id", "dest_vendor_id", "distributor"]
	for k in id_fields:
		var raw_val = item.get(k)
		if raw_val is Dictionary: # e.g. "recipient": { "settlement_id": "..." }
			var r_sid = raw_val.get("recipient_settlement_id", raw_val.get("sett_id", raw_val.get("settlement_id", "")))
			if str(r_sid) != "":
				var s = _find_settlement_by_id(str(r_sid))
				if s is Dictionary:
					return Vector2i(int(s.get("x", 0)), int(s.get("y", 0)))
			var r_name = raw_val.get("name", "")
			if str(r_name) != "":
				var s = _find_settlement_by_name(str(r_name))
				if s is Dictionary:
					return Vector2i(int(s.get("x", 0)), int(s.get("y", 0)))
		elif raw_val != null and str(raw_val).strip_edges() != "" and str(raw_val) != "00000000-0000-0000-0000-000000000000":
			var s = _find_settlement_by_id(str(raw_val).strip_edges())
			if s is Dictionary:
				return Vector2i(int(s.get("x", 0)), int(s.get("y", 0)))

	# 2. Gather all possible Name fields
	var name_fields := ["recipient_settlement_name", "destination_settlement_name", "destination", "destination_name", "dest_settlement"]
	for k in name_fields:
		var rsn = item.get(k, "")
		if str(rsn) != "":
			var s = _find_settlement_by_id(str(rsn)) # Some names might accidentally be UUIDs
			if s is Dictionary:
				return Vector2i(int(s.get("x", 0)), int(s.get("y", 0)))
			s = _find_settlement_by_name(str(rsn))
			if s is Dictionary:
				return Vector2i(int(s.get("x", 0)), int(s.get("y", 0)))

	return null

## Best display name for a cargo/delivery item dict.
func _cargo_item_display_name(item: Dictionary) -> String:
	for k in ["name", "base_name", "specific_name", "cargo_name"]:
		var v = item.get(k, "")
		if str(v).strip_edges() != "":
			return str(v).strip_edges()
	return ""

## Records a cargo name against a destination coord in `names_out` (deduplicated).
func _record_cargo_name(names_out: Dictionary, coords: Vector2i, item: Dictionary) -> void:
	var nm := _cargo_item_display_name(item)
	if nm == "":
		return
	if not names_out.has(coords):
		names_out[coords] = []
	if not names_out[coords].has(nm):
		names_out[coords].append(nm)

func _get_convoy_cargo_destination_coords(convoy: Dictionary, names_out: Dictionary = {}) -> Array[Vector2i]:
	var dest_coords: Array[Vector2i] = []
	var inspect_item = func(item: Dictionary, _source_name: String):
		var coords = _resolve_cargo_destination_coords(item)
		if coords != null:
			if not dest_coords.has(coords):
				dest_coords.append(coords)
			_record_cargo_name(names_out, coords, item)

	# Scan convoy-level cargo
	var inv = convoy.get("cargo_inventory", [])
	if inv is Array:
		for it in inv:
			if it is Dictionary:
				inspect_item.call(it, "convoy_root_cargo_inventory")
				
	# Scan vehicle cargo
	var vehicles = convoy.get("vehicle_details_list", convoy.get("vehicles", []))
	if vehicles is Array:
		for i in range(vehicles.size()):
			var v = vehicles[i]
			if v is Dictionary:
				var v_name = "Vehicle " + str(i)
				for it in v.get("cargo_items", []):
					if it is Dictionary: inspect_item.call(it, v_name + "_cargo_items")
				for it in v.get("cargo_inventory", []):
					if it is Dictionary: inspect_item.call(it, v_name + "_cargo_inventory")
				for it in v.get("cargo", []):
					if it is Dictionary: inspect_item.call(it, v_name + "_cargo")
				for it in v.get("cargo_items_typed", []):
					if it is Dictionary: inspect_item.call(it, v_name + "_typed")
	return dest_coords

func _get_settlement_departing_destinations(settlement: Dictionary, names_out: Dictionary = {}) -> Array[Vector2i]:
	var dest_coords: Array[Vector2i] = []
	var sett_id = str(settlement.get("sett_id", settlement.get("id", "")))
	var sett_name = str(settlement.get("name", sett_id))

	var inspect_cargo_array = func(cargo: Array, source_name: String):
		for item in cargo:
			if item is Dictionary:
				var is_delivery = CargoItem.DeliveryCargoItem._looks_like_delivery_dict(item)
				if is_delivery:
					# Available vendor contracts have no destination in the backend payload —
					# the destination is only known after pickup. So we mark the origin
					# settlement itself as the target ("missions available here").
					var coords = _resolve_cargo_destination_coords(item)
					if coords == null:
						coords = Vector2i(int(settlement.get("x", 0)), int(settlement.get("y", 0)))
					if not dest_coords.has(coords):
						dest_coords.append(coords)
					_record_cargo_name(names_out, coords, item)

	if _debug_map_menu:
		print("[UIManager] _get_settlement_departing_destinations: scanning '%s' (id=%s)" % [sett_name, sett_id])

	# 1. Direct cargo keys on the settlement dictionary itself
	for key in ["cargo_inventory", "cargo", "cargo_items", "cargo_items_typed", "contracts", "missions"]:
		var cargo = settlement.get(key)
		if cargo is Array and not cargo.is_empty():
			inspect_cargo_array.call(cargo, "settlement key: " + key)

	# 2. Inspect cargo stored in the vendors of this settlement
	var vendors = settlement.get("vendors", [])
	if vendors is Array:
		for v in vendors:
			if v is Dictionary:
				var v_name = str(v.get("name", "Unknown Vendor"))
				for key in ["cargo_inventory", "cargo", "cargo_items", "cargo_items_typed", "contracts", "missions"]:
					var cargo = v.get(key)
					if cargo is Array and not cargo.is_empty():
						inspect_cargo_array.call(cargo, "vendor (" + v_name + ") key: " + key)

	# 3. Inspect cargo stored in the player's warehouse at this settlement
	if sett_id != "" and is_instance_valid(_user_service) and _user_service.has_method("get_user"):
		var user = _user_service.get_user()
		if user is Dictionary:
			var warehouses = user.get("warehouses", [])
			if warehouses is Array:
				for w in warehouses:
					if w is Dictionary:
						var w_sett_id = str(w.get("sett_id", ""))
						if w_sett_id == sett_id:
							for key in ["cargo_inventory", "cargo", "cargo_items", "cargo_items_typed"]:
								var cargo = w.get(key)
								if cargo is Array and not cargo.is_empty():
									inspect_cargo_array.call(cargo, "warehouse key: " + key)

	if _debug_map_menu:
		print("[UIManager] _get_settlement_departing_destinations: '%s' → %d destinations found" % [sett_name, dest_coords.size()])
	return dest_coords


## When "Settlement Labels" (show all discovered cities) is on, most labels are generic
## "plain" labels. These are rendered smaller + translucent so the map stays readable; the
## relevant ones (delivery targets, warehouses, pinned, hovered) keep full size/opacity.
const PLAIN_LABEL_SCALE: float = 0.7
const PLAIN_LABEL_ALPHA: float = 0.55

func _update_settlement_panel_content(panel: Panel, settlement_info: Dictionary, targeting_convoys: Array = [], cargo_names: Array = [], is_plain: bool = false):
	if not is_instance_valid(panel): return
	var label_node: Label = panel.get_meta("label_node_ref")
	var style_box: StyleBoxFlat = panel.get_meta("style_box_ref")
	if not is_instance_valid(label_node) or not is_instance_valid(style_box): return
	# Font size and panel sizing now rely on content_scale_factor
	var current_settlement_font_size: int = base_settlement_font_size
	var current_settlement_panel_corner_radius: float = base_settlement_panel_corner_radius
	var current_settlement_panel_padding_h: float = base_settlement_panel_padding_h
	var current_settlement_panel_padding_v: float = base_settlement_panel_padding_v
	
	var zoom_factor: float = max(0.0001, _display_zoom)
	var label_scale: float = PLAIN_LABEL_SCALE if is_plain else 1.0
	panel.scale = Vector2(label_scale / zoom_factor, label_scale / zoom_factor)
	# Base opacity used by the dimming pass: plain labels start translucent.
	panel.set_meta("plain_alpha", PLAIN_LABEL_ALPHA if is_plain else 1.0)
	var settlement_name_local: String = settlement_info.get('name', 'N/A')
	if settlement_name_local == 'N/A': return
	if not is_instance_valid(settlement_label_settings.font):
		printerr("UIManager (_update_settlement_panel_content): settlement_label_settings.font is NOT VALID for settlement: ", settlement_name_local)
	settlement_label_settings.font_size = current_settlement_font_size
	var settlement_type = settlement_info.get('sett_type', '')
	var settlement_emoji = SETTLEMENT_EMOJIS.get(settlement_type, '')
	
	var final_text = settlement_emoji + ' ' + settlement_name_local if not settlement_emoji.is_empty() else settlement_name_local
	
	# Prepend warehouse indicator (🏭) if player owns a warehouse here
	var sett_id = str(settlement_info.get("sett_id", settlement_info.get("id", "")))
	var has_warehouse = false
	if sett_id != "" and _get_player_warehouse_settlement_ids().has(sett_id):
		final_text = "🏭 " + final_text
		has_warehouse = true

	# Append the cargo headed to this destination (first item + "(+N more)").
	if not cargo_names.is_empty():
		var cargo_line: String = "📦 " + str(cargo_names[0])
		var extra: int = cargo_names.size() - 1
		if extra > 0:
			cargo_line += " (+%d more)" % extra
		final_text += "\n" + cargo_line
		label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	label_node.text = final_text
	style_box.bg_color = settlement_panel_background_color
	panel.set_meta("sett_type", settlement_type) # used by overlay draw for tile icon
	
	# Apply border accent from the owning convoy's color.
	# Prioritise a focused/selected convoy; fall back to the first targeting convoy.
	var convoy_accent_color: Color = Color.TRANSPARENT
	if not targeting_convoys.is_empty():
		var chosen_id: String = targeting_convoys[0]
		for cid in targeting_convoys:
			if _focused_convoy_ids_last.has(cid):
				chosen_id = cid
				break
		convoy_accent_color = _convoy_id_to_color_map_cache.get(chosen_id, Color(0.9, 0.9, 0.9, 0.8))

	panel.set_meta("outline_color", convoy_accent_color)  # used by tile outline overlay

	if not targeting_convoys.is_empty():
		var bw: int = 3 if not _focused_convoy_ids_last.is_empty() else 2
		style_box.border_width_left   = bw
		style_box.border_width_right  = bw
		style_box.border_width_top    = bw
		style_box.border_width_bottom = bw
		style_box.border_color = convoy_accent_color
	elif has_warehouse:
		style_box.border_width_left = 2
		style_box.border_width_right = 2
		style_box.border_width_top = 2
		style_box.border_width_bottom = 2
		style_box.border_color = Color(0.25, 0.55, 0.95, 0.8) # Premium interactive blue glow
		style_box.bg_color = Color(0.12, 0.16, 0.24, 0.9)     # Deep glassmorphic tech-blue
	else:
		style_box.border_width_left = 0
		style_box.border_width_right = 0
		style_box.border_width_top = 0
		style_box.border_width_bottom = 0

	# Store final resolved bg color so the callout tail can match it.
	panel.set_meta("bg_color", style_box.bg_color)

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
	
	# Dynamically shift the label higher if any convoy is parked on this exact tile
	if _all_convoy_data_cache:
		for convoy_data in _all_convoy_data_cache:
			if convoy_data is Dictionary:
				var cx = convoy_data.get('x', -1)
				var cy = convoy_data.get('y', -1)
				if cx == tile_x and cy == tile_y:
					current_settlement_offset_above_center += 45.0 # Extra vertical clearance
					break
	
	var scaled_size = panel_actual_size * panel.scale
	
	# Position label above the tile center, centered horizontally
	var panel_desired_x = tile_center.x - (scaled_size.x / 2.0)
	var panel_desired_y = tile_center.y - scaled_size.y - current_settlement_offset_above_center
	panel.position = Vector2(panel_desired_x, panel_desired_y)

	# --- Anti-collision logic ---
	var attempt := 0
	while attempt < 20: # Max attempts to find a clear spot
		var panel_rect := Rect2(panel.position, scaled_size)
		
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
			var s_tile_x = int(round(float(settlement_data_entry.get('x', -1))))
			var s_tile_y = int(round(float(settlement_data_entry.get('y', -1))))
			if s_tile_x == tile_x and s_tile_y == tile_y:
				return settlement_data_entry
	return null

func _find_closest_settlement(cx: float, cy: float, max_dist: float = 1.5) -> Variant:
	if not _all_settlement_data_cache: return null
	var closest_sett = null
	var min_dist = max_dist
	for s in _all_settlement_data_cache:
		if s is Dictionary:
			var sx = float(s.get("x", -999.0))
			var sy = float(s.get("y", -999.0))
			var dist = sqrt((sx - cx)*(sx - cx) + (sy - cy)*(sy - cy))
			if dist < min_dist:
				min_dist = dist
				closest_sett = s
	return closest_sett


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
	var base_sep_px: float = max(1.0, min(tile_size_vec.x, tile_size_vec.y) * 0.32) # slightly more separation between lanes

	if _all_convoy_data_cache is Array:
		# --- Strategy 3: Progressive Zoom LOD ---
		var is_far_zoom: bool = _current_map_zoom_cache < 0.6
		
		# --- Strategy 1: Smart Focus Line Filter ---
		var show_all_lines: bool = false
		var show_active_lines: bool = true # Smart focus default
		if is_instance_valid(_settings_service):
			show_all_lines = _settings_service.all_convoy_destinations
			show_active_lines = _settings_service.active_delivery_destinations
			
		var focused_convoy_ids: Array[String] = []
		for cid in _selected_convoy_ids_cache:
			focused_convoy_ids.append(str(cid))
		if _current_hover_info_cache.get('type') == 'convoy':
			var hover_id = str(_current_hover_info_cache.get('id', ''))
			if hover_id != '' and not focused_convoy_ids.has(hover_id):
				focused_convoy_ids.append(hover_id)

		# Pass 1: collect segment membership across all convoys
		for convoy_collect in _all_convoy_data_cache:
			if not (convoy_collect is Dictionary and convoy_collect.has("journey")):
				continue
			
			var cid_c: String = str(convoy_collect.get("convoy_id", ""))
			if cid_c == "":
				continue
				
			# Apply Zoom LOD and Smart Focus filter
			if is_far_zoom:
				continue # Draw no lines when far out
			if not show_all_lines:
				if not show_active_lines or not focused_convoy_ids.has(cid_c):
					continue # Skip drawing this route if it's not focused!

			var j_collect = convoy_collect.get("journey")
			if not (j_collect is Dictionary and j_collect.has("route_x") and j_collect.has("route_y")):
				continue
			var rx_c: Array = j_collect["route_x"]
			var ry_c: Array = j_collect["route_y"]
			if rx_c.size() < 2 or ry_c.size() != rx_c.size():
				continue
			for si in range(rx_c.size() - 1):
				var a := Vector2i(int(rx_c[si]), int(ry_c[si]))
				var b := Vector2i(int(rx_c[si + 1]), int(ry_c[si + 1]))
				# Normalize order for key stability: subway-style pathing needs a canonical
				# key regardless of travel direction.
				var p_min := a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
				var p_max := b if (p_min == a) else a
				var seg_key := "%d,%d-%d,%d" % [p_min.x, p_min.y, p_max.x, p_max.y]
				if not shared_segments_membership.has(seg_key):
					shared_segments_membership[seg_key] = []
				if not shared_segments_membership[seg_key].has(cid_c):
					shared_segments_membership[seg_key].append(cid_c)
		
		# --- Add Preview Route to membership if active ---
		if _is_preview_active and _preview_route_x.size() >= 2:
			var preview_cid := "PREVIEW_ROUTE"
			for si in range(_preview_route_x.size() - 1):
				var a := Vector2i(int(_preview_route_x[si]), int(_preview_route_y[si]))
				var b := Vector2i(int(_preview_route_x[si + 1]), int(_preview_route_y[si + 1]))
				var p_min := a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
				var p_max := b if (p_min == a) else a
				var seg_key := "%d,%d-%d,%d" % [p_min.x, p_min.y, p_max.x, p_max.y]
				if not shared_segments_membership.has(seg_key):
					shared_segments_membership[seg_key] = []
				if not shared_segments_membership[seg_key].has(preview_cid):
					shared_segments_membership[seg_key].append(preview_cid)

		# Sort memberships for deterministic lane ordering
		for k in shared_segments_membership.keys():
			shared_segments_membership[k].sort()

		# Pass 2: draw each convoy's journey with lateral offsets
		for convoy in _all_convoy_data_cache:
			if not (convoy is Dictionary and convoy.has("journey")):
				continue
			var cid: String = str(convoy.get("convoy_id", ""))
			if cid == "":
				continue
				
			# Apply Zoom LOD and Smart Focus filter
			if is_far_zoom:
				continue 
			if not show_all_lines:
				if not show_active_lines or not focused_convoy_ids.has(cid):
					continue # Skip drawing

			var journey = convoy["journey"]
			if not (journey is Dictionary and journey.has("route_x") and journey.has("route_y")):
				continue
			var route_x: Array = journey["route_x"]
			var route_y: Array = journey["route_y"]
			if route_x.size() < 2 or route_y.size() != route_x.size():
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
				# Use a canonical direction for normal calculation (p_min to p_max)
				# so that lanes are consistent regardless of which way the convoy is moving.
				var a_tile := Vector2i(int(route_x[si]), int(route_y[si]))
				var b_tile := Vector2i(int(route_x[si + 1]), int(route_y[si + 1]))
				var p_min_tile := a_tile if (a_tile.x < b_tile.x or (a_tile.x == b_tile.x and a_tile.y < b_tile.y)) else b_tile
				var p_max_tile := b_tile if (p_min_tile == a_tile) else a_tile
				
				var pA_canonical := terrain_tilemap.map_to_local(p_min_tile)
				var pB_canonical := terrain_tilemap.map_to_local(p_max_tile)
				var dir_canonical := pB_canonical - pA_canonical
				
				var normal_canonical := Vector2.ZERO
				if dir_canonical.length() > 0.0001:
					normal_canonical = Vector2(-dir_canonical.y, dir_canonical.x).normalized()
				
				seg_normals.append(normal_canonical)
				
				# Determine lane offset multiplier for this segment based on membership index
				var seg_key := "%d,%d-%d,%d" % [p_min_tile.x, p_min_tile.y, p_max_tile.x, p_max_tile.y]
				var members: Array = shared_segments_membership.get(seg_key, [])
				var idx: int = members.find(cid)
				var count: int = members.size()
				var lane_centered: float = 0.0
				if not (idx == -1 or count <= 1):
					# Use direction-based alignment to ensure "Lane 0" stays on the same side
					# throughout the journey. travel_dir dot can_dir tells us if we are flipped.
					var travel_dir := pB - pA
					var alignment := 1.0 if (travel_dir.dot(dir_canonical) >= 0.0) else -1.0
					lane_centered = (float(idx) - float(count - 1) * 0.5) * alignment
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
					var n_prev := seg_normals[vi - 1]
					var n_next := seg_normals[vi]
					var lane_prev := seg_lane_offsets[vi - 1]
					var lane_next := seg_lane_offsets[vi]
					var count_prev := seg_member_counts[vi - 1]
					var count_next := seg_member_counts[vi]

					if count_prev <= 1 and count_next > 1:
						off_vec = n_next * lane_next * base_sep_px
					elif count_prev > 1 and count_next <= 1:
						off_vec = n_prev * lane_prev * base_sep_px
					else:
						# Use miter normal to keep lanes parallel through the turn
						var miter := (n_prev + n_next).normalized()
						if miter.length_squared() < 0.0001:
							# Parallel or opposing segments
							off_vec = n_prev * lane_prev * base_sep_px
						else:
							var miter_len: float = base_sep_px / max(0.1, n_prev.dot(miter))							# The lane offset should ideally be consistent, but we use the next segment's lane
							# as the authoritative one if they differ (though they shouldn't on a continuous path).
							off_vec = miter * lane_next * miter_len
					
					# Enforce a small minimum gap at the junction if any segment is shared
					if (count_prev > 1 or count_next > 1):
						var use_next := count_next > 1
						var chosen_n := n_next if use_next else n_prev
						var lane_c := lane_next if use_next else lane_prev
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
				
				# Destination Marker
				var dest_pt = offset_points[offset_points.size() - 1]
				var marker_radius = connector_line_width * 1.5
				var outline_radius = marker_radius + (route_line_outline_extra_width * 0.75)
				convoy_connector_lines_container.draw_circle(dest_pt, outline_radius, Color(1,1,1,0.95))
				convoy_connector_lines_container.draw_circle(dest_pt, marker_radius, convoy_color)

	# --- Preview Route Drawing (after existing routes so it appears on top) ---
	if _is_preview_active and _preview_route_x.size() >= 2 and _preview_route_x.size() == _preview_route_y.size():
		var preview_points_base: Array[Vector2] = []
		for j in range(_preview_route_x.size()):
			var px = int(_preview_route_x[j])
			var py = int(_preview_route_y[j])
			preview_points_base.append(terrain_tilemap.map_to_local(Vector2i(px, py)))
		
		var preview_offset_points: PackedVector2Array = []
		var preview_cid := "PREVIEW_ROUTE"
		var min_gap_px: float = 2.0
		
		# Compute per-segment normals and lane index for the preview
		var p_seg_normals: Array[Vector2] = []
		var p_seg_lane_offsets: Array[float] = []
		var p_seg_member_counts: Array[int] = []
		
		for si in range(_preview_route_x.size() - 1):
			var a_tile := Vector2i(int(_preview_route_x[si]), int(_preview_route_y[si]))
			var b_tile := Vector2i(int(_preview_route_x[si + 1]), int(_preview_route_y[si + 1]))
			var p_min_tile := a_tile if (a_tile.x < b_tile.x or (a_tile.x == b_tile.x and a_tile.y < b_tile.y)) else b_tile
			var p_max_tile := b_tile if (p_min_tile == a_tile) else a_tile
			
			var pA_canonical := terrain_tilemap.map_to_local(p_min_tile)
			var pB_canonical := terrain_tilemap.map_to_local(p_max_tile)
			var dir_canonical := pB_canonical - pA_canonical
			var normal_canonical := Vector2.ZERO
			if dir_canonical.length() > 0.0001:
				normal_canonical = Vector2(-dir_canonical.y, dir_canonical.x).normalized()
			
			p_seg_normals.append(normal_canonical)
			
			var seg_key := "%d,%d-%d,%d" % [p_min_tile.x, p_min_tile.y, p_max_tile.x, p_max_tile.y]
			var members: Array = shared_segments_membership.get(seg_key, [])
			var idx: int = members.find(preview_cid)
			var count: int = members.size()
			var lane_centered: float = 0.0
			if not (idx == -1 or count <= 1):
				var travel_dir := preview_points_base[si+1] - preview_points_base[si]
				var alignment := 1.0 if (travel_dir.dot(dir_canonical) >= 0.0) else -1.0
				lane_centered = (float(idx) - float(count - 1) * 0.5) * alignment
			p_seg_lane_offsets.append(lane_centered)
			p_seg_member_counts.append(count)

		# Build offset points for preview
		for vi in range(preview_points_base.size()):
			var off_vec: Vector2 = Vector2.ZERO
			if vi == 0:
				if p_seg_normals.size() >= 1:
					off_vec = p_seg_normals[0] * p_seg_lane_offsets[0] * base_sep_px
			elif vi == preview_points_base.size() - 1:
				if p_seg_normals.size() >= 1:
					off_vec = p_seg_normals[p_seg_normals.size() - 1] * p_seg_lane_offsets[p_seg_lane_offsets.size() - 1] * base_sep_px
			else:
				var n_prev := p_seg_normals[vi - 1]
				var n_next := p_seg_normals[vi]
				var lane_prev := p_seg_lane_offsets[vi - 1]
				var lane_next := p_seg_lane_offsets[vi]
				var cp_prev := p_seg_member_counts[vi - 1]
				var cp_next := p_seg_member_counts[vi]
				
				if cp_prev <= 1 and cp_next > 1:
					off_vec = n_next * lane_next * base_sep_px
				elif cp_prev > 1 and cp_next <= 1:
					off_vec = n_prev * lane_prev * base_sep_px
				else:
					# Miter normal for parallel lanes through corners
					var miter := (n_prev + n_next).normalized()
					if miter.length_squared() < 0.0001:
						off_vec = n_prev * lane_prev * base_sep_px
					else:
						var miter_len: float = base_sep_px / max(0.1, n_prev.dot(miter))
						off_vec = miter * lane_next * miter_len
				
				if cp_prev > 1 or cp_next > 1:
					var use_next := cp_next > 1
					var chosen_n := n_next if use_next else n_prev
					var lane_c := lane_next if use_next else lane_prev
					var lane_sign3 := 1.0 if lane_c >= 0.0 else -1.0
					if off_vec.length() < min_gap_px and chosen_n.length() > 0.0:
						off_vec = chosen_n * lane_sign3 * min_gap_px
			preview_offset_points.append(preview_points_base[vi] + off_vec)

		if preview_offset_points.size() >= 2:
			var preview_outline_w = max(0.0, _preview_line_width + route_line_outline_extra_width)
			# White underlay for preview path (larger outline)
			convoy_connector_lines_container.draw_polyline(preview_offset_points, Color(1,1,1,0.95), preview_outline_w)
			# Colored overlay matching convoy color
			convoy_connector_lines_container.draw_polyline(preview_offset_points, _preview_color, _preview_line_width)
			
			# Destination Marker
			var dest_pt = preview_offset_points[preview_offset_points.size() - 1]
			var marker_radius = _preview_line_width * 1.5
			var outline_radius = marker_radius + (route_line_outline_extra_width * 0.75)
			convoy_connector_lines_container.draw_circle(dest_pt, outline_radius, Color(1,1,1,0.95))
			convoy_connector_lines_container.draw_circle(dest_pt, marker_radius, _preview_color)

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
