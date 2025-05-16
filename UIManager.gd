extends Node2D

# References to label containers managed by UIManager
# These should be children of the Node this script is attached to.
@onready var settlement_label_container: Node2D = $SettlementLabelContainer
@onready var convoy_connector_lines_container: Node2D = $ConvoyConnectorLinesContainer
@onready var convoy_label_container: Node2D = $ConvoyLabelContainer

# Label settings and default font (will be initialized in _ready)
var label_settings: LabelSettings
var settlement_label_settings: LabelSettings

# --- UI Constants (copied and consolidated from main.gd) ---
const BASE_CONVOY_TITLE_FONT_SIZE: int = 64
const BASE_SETTLEMENT_FONT_SIZE: int = 52
const MIN_FONT_SIZE: int = 8
const FONT_SCALING_BASE_TILE_SIZE: float = 24.0 # Should match map_render.gd's BASE_TILE_SIZE_FOR_PROPORTIONS
const FONT_SCALING_EXPONENT: float = 0.6

const BASE_HORIZONTAL_LABEL_OFFSET_FROM_CENTER: float = 15.0
const BASE_SELECTED_CONVOY_HORIZONTAL_OFFSET: float = 60.0
const BASE_SETTLEMENT_OFFSET_ABOVE_TILE_CENTER: float = 10.0
const BASE_COLOR_INDICATOR_SIZE: float = 14.0 # No longer used for convoy panels
const BASE_COLOR_INDICATOR_PADDING: float = 4.0 # No longer used for convoy panels
const BASE_CONVOY_PANEL_CORNER_RADIUS: float = 8.0
const BASE_CONVOY_PANEL_PADDING_H: float = 8.0
const BASE_CONVOY_PANEL_PADDING_V: float = 5.0
const CONVOY_PANEL_BACKGROUND_COLOR: Color = Color(0.12, 0.12, 0.15, 0.88)
const BASE_CONVOY_PANEL_BORDER_WIDTH: float = 3.0
const BASE_SETTLEMENT_PANEL_CORNER_RADIUS: float = 6.0
const BASE_SETTLEMENT_PANEL_PADDING_H: float = 6.0
const BASE_SETTLEMENT_PANEL_PADDING_V: float = 4.0
const SETTLEMENT_PANEL_BACKGROUND_COLOR: Color = Color(0.15, 0.12, 0.12, 0.85)

const LABEL_ANTI_COLLISION_Y_SHIFT: float = 5.0
const LABEL_MAP_EDGE_PADDING: float = 5.0

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

const ABBREVIATED_MONTH_NAMES: Array[String] = [
	'N/A',  # Index 0 (unused for months 1-12)
	'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
	'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
]

# --- Connector Line constants ---
const CONNECTOR_LINE_COLOR: Color = Color(0.9, 0.9, 0.9, 0.6)
const CONNECTOR_LINE_WIDTH: float = 1.5

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
var _selected_convoy_ids_cache: Array # Stored as strings


func _ready():
	# Critical: Ensure child containers are valid and print their status
	print("UIManager _ready: Checking child containers...")
	print("  - settlement_label_container: %s (Valid: %s)" % [settlement_label_container, is_instance_valid(settlement_label_container)])
	print("  - convoy_connector_lines_container: %s (Valid: %s)" % [convoy_connector_lines_container, is_instance_valid(convoy_connector_lines_container)])
	print("  - convoy_label_container: %s (Valid: %s)" % [convoy_label_container, is_instance_valid(convoy_label_container)])

	# Ensure containers are visible
	if is_instance_valid(settlement_label_container): settlement_label_container.visible = true
	if is_instance_valid(convoy_connector_lines_container): convoy_connector_lines_container.visible = true
	if is_instance_valid(convoy_label_container): convoy_label_container.visible = true


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
		print("UIManager: Connected to ConvoyConnectorLinesContainer draw signal.")
	else:
		printerr("UIManager: ConvoyConnectorLinesContainer not ready or invalid in _ready().")


func initialize_font_settings(theme_font_to_use: Font):
	if theme_font_to_use:
		label_settings.font = theme_font_to_use
		settlement_label_settings.font = theme_font_to_use
		print("UIManager: Using theme font for labels provided by main: ", theme_font_to_use.resource_path if theme_font_to_use.resource_path else "Built-in font")
	else:
		# If no font is passed, LabelSettings will not have a font set,
		# and Labels will use their default/themed font.
		print("UIManager: No theme font provided by main. Labels will use their default theme font if LabelSettings.font is not set.")


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
		dragged_convoy_id_str_from_main: String
	):
	# Store references to data needed by drawing functions
	_map_display_node = map_display_node_ref
	_map_tiles_data = current_map_tiles
	_all_convoy_data_cache = all_convoy_data
	_all_settlement_data_cache = all_settlement_data
	_convoy_id_to_color_map_cache = convoy_id_to_color_map
	_selected_convoy_ids_cache = selected_convoy_ids

	# Update UIManager's state from what main.gd passes
	_convoy_label_user_positions = convoy_label_user_positions_from_main
	_dragging_panel_node = dragging_panel_node_from_main
	_dragged_convoy_id_actual_str = dragged_convoy_id_str_from_main

	# Call the main label drawing logic
	_draw_interactive_labels(current_hover_info)

	# Request redraw for connector lines
	if is_instance_valid(convoy_connector_lines_container):
		convoy_connector_lines_container.queue_redraw()


func _draw_interactive_labels(current_hover_info: Dictionary):
	print("UIManager: _draw_interactive_labels called. Hover: ", current_hover_info) # DEBUG
	print("UIManager: Cached convoy data size: ", _all_convoy_data_cache.size() if _all_convoy_data_cache else "N/A") # DEBUG
	print("UIManager: Cached settlement data size: ", _all_settlement_data_cache.size() if _all_settlement_data_cache else "N/A") # DEBUG
	print("UIManager: Cached selected IDs: ", _selected_convoy_ids_cache) # DEBUG
	if is_instance_valid(_dragging_panel_node):
		# If a panel is being dragged by the UIManager (or externally, if main still handles drag input)
		# we might still want to update other labels, but not the one being dragged.
		# For now, the original logic is to skip all updates if a drag is in progress.
		# This might change if UIManager fully owns drag input.
		# For this iteration, we assume main.gd might still gate this call.
		# If UIManager handles drag, this check might be internal to its input handling.
		pass # Let's assume main.gd already checked this or UIManager will handle it.

	# Clear all existing hover labels
	if is_instance_valid(convoy_label_container):
		for child_panel_node in convoy_label_container.get_children():
			if child_panel_node != _dragging_panel_node: # Don't remove the panel being dragged
				child_panel_node.queue_free()
	if is_instance_valid(settlement_label_container):
		for child in settlement_label_container.get_children():
			child.queue_free()

	if not _map_display_node or not is_instance_valid(_map_display_node.texture):
		printerr("UIManager: MapDisplay node or texture invalid. Cannot draw labels.")
		return

	var drawn_convoy_ids_this_update: Array[String] = []
	var drawn_settlement_tile_coords_this_update: Array[Vector2i] = []
	var all_drawn_label_rects_this_update: Array[Rect2] = []

	# STAGE 1: Draw Settlement Labels (for selected convoys' start/end, then hovered settlement)
	if not _selected_convoy_ids_cache.is_empty():
		for convoy_data in _all_convoy_data_cache:
			var convoy_id = convoy_data.get('convoy_id')
			var convoy_id_str = str(convoy_id)
			if convoy_id != null and _selected_convoy_ids_cache.has(convoy_id_str):
				if is_instance_valid(_dragging_panel_node) and _dragged_convoy_id_actual_str == convoy_id_str:
					# If the selected convoy's panel is being dragged, its rect needs to be accounted for.
					# The panel itself is not redrawn here.
					if _dragging_panel_node.get_parent() == convoy_label_container:
						all_drawn_label_rects_this_update.append(Rect2(_dragging_panel_node.position, _dragging_panel_node.size))
					# Mark as "drawn" because its panel exists, even if not redrawn by this function.
					if not drawn_convoy_ids_this_update.has(convoy_id_str):
						drawn_convoy_ids_this_update.append(convoy_id_str)
					continue # Skip drawing settlements or the panel for this dragged convoy here

				var journey_data: Dictionary = convoy_data.get('journey')
				if journey_data is Dictionary:
					var route_x_coords: Array = journey_data.get('route_x')
					var route_y_coords: Array = journey_data.get('route_y')
					if route_x_coords is Array and route_y_coords is Array and \
					   route_x_coords.size() == route_y_coords.size() and not route_x_coords.is_empty():
						var start_tile_x: int = floori(float(route_x_coords[0]))
						var start_tile_y: int = floori(float(route_y_coords[0]))
						var start_tile_coords := Vector2i(start_tile_x, start_tile_y)
						if not drawn_settlement_tile_coords_this_update.has(start_tile_coords):
							var start_settlement_data = _find_settlement_at_tile(start_tile_x, start_tile_y)
							if start_settlement_data:
								var settlement_rect: Rect2 = _draw_single_settlement_label(start_settlement_data)
								if settlement_rect != Rect2():
									all_drawn_label_rects_this_update.append(settlement_rect)
								drawn_settlement_tile_coords_this_update.append(start_tile_coords)

						if route_x_coords.size() > 0:
							var end_tile_x: int = floori(float(route_x_coords.back()))
							var end_tile_y: int = floori(float(route_y_coords.back()))
							var end_tile_coords := Vector2i(end_tile_x, end_tile_y)
							if end_tile_coords != start_tile_coords and \
							   not drawn_settlement_tile_coords_this_update.has(end_tile_coords):
								var end_settlement_data = _find_settlement_at_tile(end_tile_x, end_tile_y)
								if end_settlement_data:
									var settlement_rect: Rect2 = _draw_single_settlement_label(end_settlement_data)
									if settlement_rect != Rect2():
										all_drawn_label_rects_this_update.append(settlement_rect)
									drawn_settlement_tile_coords_this_update.append(end_tile_coords)

	if current_hover_info.get('type') == 'settlement':
		var hovered_tile_coords = current_hover_info.get('coords')
		if hovered_tile_coords is Vector2i and hovered_tile_coords.x >= 0 and hovered_tile_coords.y >= 0:
			if not drawn_settlement_tile_coords_this_update.has(hovered_tile_coords):
				var settlement_data_for_hover = _find_settlement_at_tile(hovered_tile_coords.x, hovered_tile_coords.y)
				if settlement_data_for_hover:
					var settlement_rect: Rect2 = _draw_single_settlement_label(settlement_data_for_hover)
					if settlement_rect != Rect2():
						all_drawn_label_rects_this_update.append(settlement_rect)
					# drawn_settlement_tile_coords_this_update.append(hovered_tile_coords) # Optional: mark as drawn

	# STAGE 2: Draw Convoy Labels (Selected then Hovered)
	if not _selected_convoy_ids_cache.is_empty():
		for convoy_data in _all_convoy_data_cache:
			var convoy_id = convoy_data.get('convoy_id')
			var convoy_id_str = str(convoy_id)
			if convoy_id != null and _selected_convoy_ids_cache.has(convoy_id_str):
				if is_instance_valid(_dragging_panel_node) and _dragged_convoy_id_actual_str == convoy_id_str:
					# Already handled its rect and marked as drawn in Stage 1's loop for selected convoys
					continue
				if not drawn_convoy_ids_this_update.has(convoy_id_str):
					var convoy_panel_rect: Rect2 = _draw_single_convoy_label(convoy_data, all_drawn_label_rects_this_update)
					if convoy_panel_rect != Rect2():
						all_drawn_label_rects_this_update.append(convoy_panel_rect)
					drawn_convoy_ids_this_update.append(convoy_id_str)

	if current_hover_info.get('type') == 'convoy':
		var hovered_convoy_id_str = current_hover_info.get('id') # Assuming ID is already string
		if hovered_convoy_id_str != null and not hovered_convoy_id_str.is_empty():
			if not drawn_convoy_ids_this_update.has(hovered_convoy_id_str):
				var should_draw_hovered_convoy = true
				if is_instance_valid(_dragging_panel_node) and _dragged_convoy_id_actual_str == hovered_convoy_id_str:
					should_draw_hovered_convoy = false
					# Add its rect and mark as drawn, similar to selected convoys
					if _dragging_panel_node.get_parent() == convoy_label_container:
						all_drawn_label_rects_this_update.append(Rect2(_dragging_panel_node.position, _dragging_panel_node.size))
					drawn_convoy_ids_this_update.append(hovered_convoy_id_str)

				if should_draw_hovered_convoy:
					for convoy_data in _all_convoy_data_cache:
						if convoy_data is Dictionary and str(convoy_data.get('convoy_id')) == hovered_convoy_id_str:
							var convoy_panel_rect: Rect2 = _draw_single_convoy_label(convoy_data, all_drawn_label_rects_this_update)
							if convoy_panel_rect != Rect2():
								all_drawn_label_rects_this_update.append(convoy_panel_rect)
							# drawn_convoy_ids_this_update.append(hovered_convoy_id_str) # Mark as drawn
							break


func _draw_single_convoy_label(convoy_data: Dictionary, existing_label_rects: Array[Rect2]) -> Rect2:
	if not is_instance_valid(convoy_label_container):
		printerr('UIManager: ConvoyLabelContainer is not valid. Cannot draw single convoy label.')
		return Rect2()
	if not _map_display_node or not is_instance_valid(_map_display_node.texture):
		printerr('UIManager: MapDisplay node or texture invalid in _draw_single_convoy_label.')
		return Rect2()

	var map_texture: ImageTexture = _map_display_node.texture
	var map_texture_size: Vector2 = map_texture.get_size()
	var map_display_rect_size: Vector2 = _map_display_node.size

	if map_texture_size.x == 0 or map_texture_size.y == 0:
		printerr('UIManager: Map texture size is zero.')
		return Rect2()

	var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
	var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y
	var actual_scale: float = min(scale_x_ratio, scale_y_ratio)
	var displayed_texture_width: float = map_texture_size.x * actual_scale
	var displayed_texture_height: float = map_texture_size.y * actual_scale
	var offset_x: float = (_map_display_node.size.x - displayed_texture_width) / 2.0
	var offset_y: float = (_map_display_node.size.y - displayed_texture_height) / 2.0

	if _map_tiles_data.is_empty() or not _map_tiles_data[0] is Array or _map_tiles_data[0].is_empty():
		printerr('UIManager: map_tiles data is invalid.')
		return Rect2()
	var map_image_cols: int = _map_tiles_data[0].size()
	var map_image_rows: int = _map_tiles_data.size()
	var actual_tile_width_on_texture: float = map_texture_size.x / float(map_image_cols)
	var actual_tile_height_on_texture: float = map_texture_size.y / float(map_image_rows)

	var effective_tile_size_on_texture: float = min(actual_tile_width_on_texture, actual_tile_height_on_texture)
	var base_linear_font_scale: float = 1.0
	if FONT_SCALING_BASE_TILE_SIZE > 0.001:
		base_linear_font_scale = effective_tile_size_on_texture / FONT_SCALING_BASE_TILE_SIZE
	var font_render_scale: float = pow(base_linear_font_scale, FONT_SCALING_EXPONENT)

	var current_convoy_title_font_size: int = max(MIN_FONT_SIZE, roundi(BASE_CONVOY_TITLE_FONT_SIZE * font_render_scale))
	
	var current_convoy_id_orig = convoy_data.get('convoy_id')
	var current_convoy_id_str = str(current_convoy_id_orig)

	var current_horizontal_offset: float
	if _selected_convoy_ids_cache.has(current_convoy_id_str):
		current_horizontal_offset = BASE_SELECTED_CONVOY_HORIZONTAL_OFFSET * actual_scale
	else:
		current_horizontal_offset = BASE_HORIZONTAL_LABEL_OFFSET_FROM_CENTER * actual_scale

	var current_panel_corner_radius: float = BASE_CONVOY_PANEL_CORNER_RADIUS * font_render_scale
	var current_panel_padding_h: float = BASE_CONVOY_PANEL_PADDING_H * font_render_scale
	var current_panel_border_width: int = max(1, roundi(BASE_CONVOY_PANEL_BORDER_WIDTH * font_render_scale))
	var current_panel_padding_v: float = BASE_CONVOY_PANEL_PADDING_V * font_render_scale

	var efficiency: float = convoy_data.get('efficiency', 0.0)
	var convoy_map_x: float = convoy_data.get('x', 0.0)
	var top_speed: float = convoy_data.get('top_speed', 0.0)
	var offroad_capability: float = convoy_data.get('offroad_capability', 0.0)
	var convoy_name: String = convoy_data.get('convoy_name', 'N/A')
	var journey_data: Dictionary = convoy_data.get('journey', {})
	var convoy_map_y: float = convoy_data.get('y', 0.0)
	var progress: float = journey_data.get('progress', 0.0)

	var eta_raw_string: String = journey_data.get('eta', 'N/A')
	var departure_raw_string: String = journey_data.get('departure_time', 'N/A')
	var formatted_eta: String = _format_eta_string(eta_raw_string, departure_raw_string)

	var progress_percentage_str: String = 'N/A'
	var length: float = journey_data.get('length', 0.0)
	if length > 0.001:
		var percentage: float = (progress / length) * 100.0
		progress_percentage_str = '%.1f%%' % percentage

	var label_text: String
	if _selected_convoy_ids_cache.has(current_convoy_id_str):
		label_text = '%s\n' % convoy_name
		label_text += 'Progress 🏁: %s | ETA: %s\n' % [progress_percentage_str, formatted_eta]
		label_text += 'Convoy stats: %s %.1f | %s %.1f | %s %.1f\n' % [
			CONVOY_STAT_EMOJIS.get('efficiency', ''), efficiency,
			CONVOY_STAT_EMOJIS.get('top_speed', ''), top_speed,
			CONVOY_STAT_EMOJIS.get('offroad_capability', ''), offroad_capability
		]
		label_text += 'Fuel ⛽️: %.1fL / %.0fL | Water 💧: %.1fL / %.0fL | Food 🥪: %.1f / %.0f\n' % [
			convoy_data.get('fuel', 0.0), convoy_data.get('max_fuel', 0.0),
			convoy_data.get('water', 0.0), convoy_data.get('max_water', 0.0),
			convoy_data.get('food', 0.0), convoy_data.get('max_food', 0.0)
		]
		label_text += 'Cargo Volume: %.0fL / %.0fL | Cargo Weight: %.0fkg / %.0fkg\n' % [
			convoy_data.get('total_free_space', 0.0), convoy_data.get('total_cargo_capacity', 0.0),
			convoy_data.get('total_remaining_capacity', 0.0), convoy_data.get('total_weight_capacity', 0.0),
		]
		label_text += 'Vehicles:\n'
		var vehicles: Array = convoy_data.get('vehicle_details_list', [])
		if vehicles.is_empty():
			label_text += '  None\n'
		else:
			for v_detail in vehicles:
				label_text += '%s | 🌿: %.1f | 🚀: %.1f | 🥾: %.1f\n' % [
					v_detail.get('make_model', 'N/A'),
					v_detail.get('efficiency', 0.0), v_detail.get('top_speed', 0.0), v_detail.get('offroad_capability', 0.0)
				]
				var v_cargo_items: Array = v_detail.get('cargo', [])
				if not v_cargo_items.is_empty():
					for cargo_item in v_cargo_items:
						label_text += '  - x%s %s\n' % [
							cargo_item.get('quantity', 0), cargo_item.get('name', 'N/A')
						]
	else:
		label_text = '%s \n🏁 %s | ETA: %s\n%s %.1f | %s %.1f | %s %.1f' % [
			convoy_name, progress_percentage_str, formatted_eta,
			CONVOY_STAT_EMOJIS.get('efficiency', ''), efficiency,
			CONVOY_STAT_EMOJIS.get('top_speed', ''), top_speed,
			CONVOY_STAT_EMOJIS.get('offroad_capability', ''), offroad_capability
		]

	if not is_instance_valid(label_settings.font):
		printerr("UIManager (_draw_single_convoy_label): label_settings.font is NOT VALID for convoy: ", convoy_name)
	else:
		print("UIManager (_draw_single_convoy_label): label_settings.font is VALID. Size: ", label_settings.font_size, " for convoy: ", convoy_name)
	label_settings.font_size = current_convoy_title_font_size
	var unique_convoy_color: Color = _convoy_id_to_color_map_cache.get(current_convoy_id_str, Color.GRAY)

	var label_node := Label.new()
	if not is_instance_valid(label_node): return Rect2()

	label_node.set('bbcode_enabled', true)
	label_node.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label_node.text = label_text
	label_node.label_settings = label_settings

	convoy_label_container.add_child(label_node) # Add temporarily to get size
	var label_min_size: Vector2 = label_node.get_minimum_size()
	print("UIManager (_draw_single_convoy_label): Convoy '%s' label_min_size: %s, Text: '%s'" % [convoy_name, label_min_size, label_text.left(50)]) # DEBUG
	label_node.pivot_offset = Vector2.ZERO # Top-left pivot
	convoy_label_container.remove_child(label_node) # Remove before final positioning in panel

	var convoy_center_on_texture_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_texture
	var convoy_center_on_texture_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_texture
	var convoy_center_display_y = convoy_center_on_texture_y * actual_scale + offset_y

	# Initial desired global position for the label content's top-left
	var initial_label_global_pos_x = (convoy_center_on_texture_x * actual_scale + offset_x) + current_horizontal_offset
	var initial_label_global_pos_y = convoy_center_display_y - (label_min_size.y / 2.0)

	var panel := Panel.new()
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = CONVOY_PANEL_BACKGROUND_COLOR
	style_box.border_color = unique_convoy_color
	style_box.border_width_left = current_panel_border_width
	style_box.border_width_top = current_panel_border_width
	style_box.border_width_right = current_panel_border_width
	style_box.border_width_bottom = current_panel_border_width
	style_box.corner_radius_top_left = current_panel_corner_radius
	style_box.corner_radius_top_right = current_panel_corner_radius
	style_box.corner_radius_bottom_left = current_panel_corner_radius
	style_box.corner_radius_bottom_right = current_panel_corner_radius
	panel.add_theme_stylebox_override('panel', style_box)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP # For dragging
	panel.name = current_convoy_id_str # Use string convoy_id as panel name
	panel.set_meta("convoy_id_str", current_convoy_id_str)

	# Panel position and size based on label content
	panel.position.x = initial_label_global_pos_x - current_panel_padding_h
	panel.position.y = initial_label_global_pos_y - current_panel_padding_v
	panel.size.x = label_min_size.x + (2 * current_panel_padding_h)
	panel.size.y = label_min_size.y + (2 * current_panel_padding_v)
	print("UIManager (_draw_single_convoy_label): Convoy '%s' panel initial calculated pos: %s, size: %s" % [convoy_name, panel.position, panel.size]) # DEBUG

	# Position label locally within the panel
	label_node.position.x = current_panel_padding_h
	label_node.position.y = current_panel_padding_v
	label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label_node)

	# Apply user-defined position or anti-collision
	if _selected_convoy_ids_cache.has(current_convoy_id_str) and _convoy_label_user_positions.has(current_convoy_id_str):
		panel.position = _convoy_label_user_positions[current_convoy_id_str]
	else:
		var current_panel_rect = Rect2(panel.position, panel.size)
		for _attempt in range(10):
			var collides_with_existing: bool = false
			var colliding_rect_for_shift_calc: Rect2
			for existing_rect in existing_label_rects:
				var buffered_existing_rect = existing_rect.grow_individual(2,2,2,2)
				if current_panel_rect.intersects(buffered_existing_rect, true):
					collides_with_existing = true
					colliding_rect_for_shift_calc = existing_rect
					break
			if collides_with_existing:
				var shift_based_on_collided_height = 0.0
				if is_instance_valid(colliding_rect_for_shift_calc) and colliding_rect_for_shift_calc.size.y > 0:
					shift_based_on_collided_height = colliding_rect_for_shift_calc.size.y * 0.25 + LABEL_MAP_EDGE_PADDING
				var y_shift_amount = LABEL_ANTI_COLLISION_Y_SHIFT + max(label_min_size.y * 0.1, shift_based_on_collided_height)
				panel.position.y += y_shift_amount
				current_panel_rect = Rect2(panel.position, panel.size)
			else:
				break

	# Clamp panel position to viewport bounds (relative to convoy_label_container, which is child of map_display)
	# The panel.position is already in the coordinate system of convoy_label_container.
	# The clamping needs to happen against the viewport rect, transformed to local coords of convoy_label_container.
	# However, since convoy_label_container is at (0,0) of map_display, and map_display fills viewport,
	# the viewport rect can be used directly for clamping panel.position IF panel.position was global.
	# Since panel.position is local to convoy_label_container, and convoy_label_container is child of map_display,
	# and map_display is child of main scene root, we need to be careful.
	# Let's assume convoy_label_container is at (0,0) relative to map_display.
	# And map_display is at (0,0) relative to viewport for simplicity of clamping here.
	# A more robust solution would get global viewport rect and transform.

	var panel_target_position = panel.position # This is local to convoy_label_container
	var viewport_rect_global = get_viewport_rect() # Global viewport

	# Convert viewport_rect_global to the local coordinate system of convoy_label_container's parent (map_display)
	var map_display_global_transform = _map_display_node.get_global_transform_with_canvas()
	var clamp_rect_local_to_map_display = map_display_global_transform.affine_inverse() * viewport_rect_global

	# Since convoy_label_container is a direct child of map_display and assumed at (0,0) relative to it,
	# clamp_rect_local_to_map_display is also the clamp_rect_local_to_convoy_label_container.

	var padded_min_x = clamp_rect_local_to_map_display.position.x + LABEL_MAP_EDGE_PADDING
	var padded_min_y = clamp_rect_local_to_map_display.position.y + LABEL_MAP_EDGE_PADDING
	var padded_max_x = clamp_rect_local_to_map_display.position.x + clamp_rect_local_to_map_display.size.x - LABEL_MAP_EDGE_PADDING
	var padded_max_y = clamp_rect_local_to_map_display.position.y + clamp_rect_local_to_map_display.size.y - LABEL_MAP_EDGE_PADDING

	panel_target_position.x = clamp(panel.position.x, padded_min_x, padded_max_x - panel.size.x)
	panel_target_position.y = clamp(panel.position.y, padded_min_y, padded_max_y - panel.size.y)
	panel.position = panel_target_position

	convoy_label_container.add_child(panel)
	print("UIManager (_draw_single_convoy_label): Convoy '%s' panel ADDED. Final local pos: %s, global_pos: %s, visible: %s" % [convoy_name, panel.position, panel.global_position, panel.visible]) # DEBUG
	panel.set_meta("intended_global_rect", Rect2(panel.global_position, panel.size)) # Store for drag start

	# DO NOT RE-ASSIGN _convoy_label_user_positions here. It's read-only in this drawing function.
	return Rect2(panel.position, panel.size)


func _draw_single_settlement_label(settlement_info_for_render: Dictionary) -> Rect2:
	if not is_instance_valid(settlement_label_container):
		printerr('UIManager: SettlementLabelContainer is not valid.')
		return Rect2()
	if not _map_display_node or not is_instance_valid(_map_display_node.texture):
		printerr('UIManager: MapDisplay node or texture invalid in _draw_single_settlement_label.')
		return Rect2()

	var map_texture_size: Vector2 = _map_display_node.texture.get_size()
	var map_display_rect_size: Vector2 = _map_display_node.size

	if map_texture_size.x == 0 or map_texture_size.y == 0: return Rect2()

	var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
	var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y
	var actual_scale: float = min(scale_x_ratio, scale_y_ratio)
	var displayed_texture_width: float = map_texture_size.x * actual_scale
	var displayed_texture_height: float = map_texture_size.y * actual_scale
	var offset_x: float = (_map_display_node.size.x - displayed_texture_width) / 2.0
	var offset_y: float = (_map_display_node.size.y - displayed_texture_height) / 2.0

	if _map_tiles_data.is_empty() or not _map_tiles_data[0] is Array or _map_tiles_data[0].is_empty():
		return Rect2()
	var map_image_cols: int = _map_tiles_data[0].size()
	var map_image_rows: int = _map_tiles_data.size()
	var actual_tile_width_on_texture: float = map_texture_size.x / float(map_image_cols)
	var actual_tile_height_on_texture: float = map_texture_size.y / float(map_image_rows)

	var effective_tile_size_on_texture: float = min(actual_tile_width_on_texture, actual_tile_height_on_texture)
	var base_linear_font_scale: float = 1.0
	if FONT_SCALING_BASE_TILE_SIZE > 0.001:
		base_linear_font_scale = effective_tile_size_on_texture / FONT_SCALING_BASE_TILE_SIZE
	var font_render_scale: float = pow(base_linear_font_scale, FONT_SCALING_EXPONENT)

	var current_settlement_font_size: int = max(MIN_FONT_SIZE, roundi(BASE_SETTLEMENT_FONT_SIZE * font_render_scale))
	var current_settlement_offset_above_center: float = BASE_SETTLEMENT_OFFSET_ABOVE_TILE_CENTER * actual_scale
	var current_settlement_panel_corner_radius: float = BASE_SETTLEMENT_PANEL_CORNER_RADIUS * font_render_scale
	var current_settlement_panel_padding_h: float = BASE_SETTLEMENT_PANEL_PADDING_H * font_render_scale
	var current_settlement_panel_padding_v: float = BASE_SETTLEMENT_PANEL_PADDING_V * font_render_scale

	var settlement_name_local: String = settlement_info_for_render.get('name', 'N/A')
	var tile_x: int = settlement_info_for_render.get('x', -1)
	var tile_y: int = settlement_info_for_render.get('y', -1)
	if tile_x < 0 or tile_y < 0 or settlement_name_local == 'N/A': return Rect2()

	if not is_instance_valid(settlement_label_settings.font):
		printerr("UIManager (_draw_single_settlement_label): settlement_label_settings.font is NOT VALID for settlement: ", settlement_name_local)
	else:
		print("UIManager (_draw_single_settlement_label): settlement_label_settings.font is VALID. Size: ", current_settlement_font_size, " for settlement: ", settlement_name_local) # Use current_settlement_font_size here
	settlement_label_settings.font_size = current_settlement_font_size

	var settlement_type = settlement_info_for_render.get('sett_type', '')
	var settlement_emoji = SETTLEMENT_EMOJIS.get(settlement_type, '')
	
	var label_node := Label.new()
	label_node.text = settlement_emoji + ' ' + settlement_name_local if not settlement_emoji.is_empty() else settlement_name_local
	label_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_node.label_settings = settlement_label_settings

	settlement_label_container.add_child(label_node) # Add temporarily
	var label_size: Vector2 = label_node.get_minimum_size()
	print("UIManager (_draw_single_settlement_label): Settlement '%s' label_size: %s" % [settlement_name_local, label_size]) # DEBUG
	settlement_label_container.remove_child(label_node) # Remove

	var panel := Panel.new()
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = SETTLEMENT_PANEL_BACKGROUND_COLOR
	style_box.corner_radius_top_left = current_settlement_panel_corner_radius
	style_box.corner_radius_top_right = current_settlement_panel_corner_radius
	style_box.corner_radius_bottom_left = current_settlement_panel_corner_radius
	style_box.corner_radius_bottom_right = current_settlement_panel_corner_radius
	panel.add_theme_stylebox_override('panel', style_box)

	panel.size.x = label_size.x + (2 * current_settlement_panel_padding_h)
	panel.size.y = label_size.y + (2 * current_settlement_panel_padding_v)
	print("UIManager (_draw_single_settlement_label): Settlement '%s' panel initial calculated size: %s" % [settlement_name_local, panel.size]) # DEBUG

	var tile_center_tex_x: float = (float(tile_x) + 0.5) * actual_tile_width_on_texture
	var tile_center_tex_y: float = (float(tile_y) + 0.5) * actual_tile_height_on_texture
	var tile_center_display_y = tile_center_tex_y * actual_scale + offset_y

	# Panel position (local to settlement_label_container)
	panel.position.x = (tile_center_tex_x * actual_scale + offset_x) - (panel.size.x / 2.0)
	panel.position.y = tile_center_display_y - panel.size.y - current_settlement_offset_above_center
	print("UIManager (_draw_single_settlement_label): Settlement '%s' panel initial calculated pos: %s" % [settlement_name_local, panel.position]) # DEBUG

	# Label position (local to panel)
	label_node.position.x = current_settlement_panel_padding_h
	label_node.position.y = current_settlement_panel_padding_v
	panel.add_child(label_node) # Add label as child of panel

	# Clamp panel position (local to settlement_label_container)
	# Similar clamping logic as convoy panels, assuming settlement_label_container is also child of map_display at (0,0)
	var panel_target_position = panel.position
	var viewport_rect_global = get_viewport_rect()
	var map_display_global_transform = _map_display_node.get_global_transform_with_canvas()
	var clamp_rect_local_to_map_display = map_display_global_transform.affine_inverse() * viewport_rect_global

	var padded_min_x = clamp_rect_local_to_map_display.position.x + LABEL_MAP_EDGE_PADDING
	var padded_min_y = clamp_rect_local_to_map_display.position.y + LABEL_MAP_EDGE_PADDING
	var padded_max_x = clamp_rect_local_to_map_display.position.x + clamp_rect_local_to_map_display.size.x - LABEL_MAP_EDGE_PADDING
	var padded_max_y = clamp_rect_local_to_map_display.position.y + clamp_rect_local_to_map_display.size.y - LABEL_MAP_EDGE_PADDING

	panel_target_position.x = clamp(panel.position.x, padded_min_x, padded_max_x - panel.size.x)
	panel_target_position.y = clamp(panel.position.y, padded_min_y, padded_max_y - panel.size.y)
	panel.position = panel_target_position

	settlement_label_container.add_child(panel)
	print("UIManager (_draw_single_settlement_label): Settlement '%s' panel ADDED. Final local pos: %s, global_pos: %s, visible: %s" % [settlement_name_local, panel.position, panel.global_position, panel.visible]) # DEBUG
	return Rect2(panel.position, panel.size)


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
	if not is_instance_valid(_map_display_node) or not is_instance_valid(_map_display_node.texture): return
	if not _map_tiles_data or _map_tiles_data.is_empty() or not _map_tiles_data[0] is Array or _map_tiles_data[0].is_empty(): return
	if not is_instance_valid(convoy_label_container): return
	if not _all_convoy_data_cache: return

	var map_texture_size: Vector2 = _map_display_node.texture.get_size()
	var map_display_rect_size: Vector2 = _map_display_node.size

	if map_texture_size.x <= 0.001 or map_texture_size.y <= 0.001: return

	var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
	var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y
	var actual_scale: float = min(scale_x_ratio, scale_y_ratio)

	var displayed_texture_width: float = map_texture_size.x * actual_scale
	var displayed_texture_height: float = map_texture_size.y * actual_scale
	var offset_x: float = (_map_display_node.size.x - displayed_texture_width) / 2.0
	var offset_y: float = (_map_display_node.size.y - displayed_texture_height) / 2.0

	var map_image_cols: int = _map_tiles_data[0].size()
	var map_image_rows: int = _map_tiles_data.size()
	if map_image_cols == 0 or map_image_rows == 0: return

	var actual_tile_width_on_texture: float = map_texture_size.x / float(map_image_cols)
	var actual_tile_height_on_texture: float = map_texture_size.y / float(map_image_rows)

	for node in convoy_label_container.get_children():
		if node is Panel:
			var panel: Panel = node
			var convoy_id_str = panel.get_meta("convoy_id_str", "")
			if convoy_id_str.is_empty(): continue

			var convoy_data_for_line = null
			for cd in _all_convoy_data_cache:
				if cd is Dictionary and str(cd.get("convoy_id")) == convoy_id_str:
					convoy_data_for_line = cd
					break
			
			if convoy_data_for_line == null: continue

			var convoy_map_x: float = convoy_data_for_line.get('x', 0.0)
			var convoy_map_y: float = convoy_data_for_line.get('y', 0.0)
			var convoy_center_on_texture_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_texture
			var convoy_center_on_texture_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_texture
			
			# Line start is in map_display's local space (which is also convoy_connector_lines_container's local space)
			var line_start_pos = Vector2(
				convoy_center_on_texture_x * actual_scale + offset_x,
				convoy_center_on_texture_y * actual_scale + offset_y
			)

			# Panel.position is local to convoy_label_container.
			# convoy_label_container is sibling to convoy_connector_lines_container.
			# Both are children of UIManagerNode, and UIManagerNode is child of map_display.
			# For simplicity, assume UIManagerNode and its children (label containers) are at (0,0) relative to map_display.
			# So, panel.position can be treated as local to map_display for drawing in connector_lines_container.
			var panel_rect_local_to_container = Rect2(panel.position, panel.size)
			var panel_center = panel_rect_local_to_container.get_center()
			var line_end_pos: Vector2

			if not panel_rect_local_to_container is Rect2 or panel_rect_local_to_container.size.x <= 0 or panel_rect_local_to_container.size.y <= 0:
				printerr("UIManager: Invalid panel rect for connector line. Convoy ID: ", convoy_id_str)
				continue

			if panel_rect_local_to_container.has_point(line_start_pos):
				if panel_center.is_equal_approx(line_start_pos):
					line_end_pos = Vector2(panel_center.x, panel_rect_local_to_container.position.y)
				else:
					var dir_to_icon = (line_start_pos - panel_center).normalized()
					var far_point = panel_center + dir_to_icon * (max(panel_rect_local_to_container.size.x, panel_rect_local_to_container.size.y) * 2.0)
					line_end_pos = Vector2(
						clamp(far_point.x, panel_rect_local_to_container.position.x, panel_rect_local_to_container.end.x),
						clamp(far_point.y, panel_rect_local_to_container.position.y, panel_rect_local_to_container.end.y)
					)
			else:
				line_end_pos = Vector2(
					clamp(line_start_pos.x, panel_rect_local_to_container.position.x, panel_rect_local_to_container.end.x),
					clamp(line_start_pos.y, panel_rect_local_to_container.position.y, panel_rect_local_to_container.end.y)
				)
				
			if not line_start_pos.is_equal_approx(line_end_pos):
				convoy_connector_lines_container.draw_line(line_start_pos, line_end_pos, CONNECTOR_LINE_COLOR, CONNECTOR_LINE_WIDTH, true)


# --- Helper function for ETA formatting (moved from main.gd) ---
func _format_eta_string(eta_raw_string: String, departure_raw_string: String) -> String:
	var formatted_eta: String = 'N/A'
	if eta_raw_string != 'N/A' and not eta_raw_string.is_empty() and \
	   departure_raw_string != 'N/A' and not departure_raw_string.is_empty():

		var eta_datetime_local: Dictionary = {}
		var departure_datetime_local: Dictionary = {}

		var eta_utc_dict: Dictionary = _parse_iso_to_utc_dict(eta_raw_string)
		var departure_utc_dict: Dictionary = _parse_iso_to_utc_dict(departure_raw_string)

		var local_offset_seconds: int = 0
		var current_local_components: Dictionary = Time.get_datetime_dict_from_system(false)
		var current_utc_components: Dictionary = Time.get_datetime_dict_from_system(true)

		if not current_local_components.is_empty() and not current_utc_components.is_empty():
			var current_system_unix_local: int = Time.get_unix_time_from_datetime_dict(current_local_components)
			var current_system_unix_utc: int = Time.get_unix_time_from_datetime_dict(current_utc_components)
			if current_system_unix_local > 0 and current_system_unix_utc > 0:
				local_offset_seconds = current_system_unix_local - current_system_unix_utc

		if not eta_utc_dict.is_empty():
			var eta_unix_time_utc: int = Time.get_unix_time_from_datetime_dict(eta_utc_dict)
			if eta_unix_time_utc > 0:
				var eta_unix_time_local: int = eta_unix_time_utc + local_offset_seconds
				eta_datetime_local = Time.get_datetime_dict_from_unix_time(eta_unix_time_local)

		if not departure_utc_dict.is_empty():
			var departure_unix_time_utc: int = Time.get_unix_time_from_datetime_dict(departure_utc_dict)
			if departure_unix_time_utc > 0:
				var departure_unix_time_local: int = departure_unix_time_utc + local_offset_seconds
				departure_datetime_local = Time.get_datetime_dict_from_unix_time(departure_unix_time_local)

		if not eta_datetime_local.is_empty() and not departure_datetime_local.is_empty():
			var eta_hour_24: int = eta_datetime_local.hour
			var am_pm_str: String = 'AM'
			var eta_hour_12: int = eta_hour_24
			if eta_hour_24 >= 12:
				am_pm_str = 'PM'
				if eta_hour_24 > 12: eta_hour_12 = eta_hour_24 - 12
			if eta_hour_12 == 0: eta_hour_12 = 12

			var eta_hour_str = '%d' % eta_hour_12
			var eta_minute_str = '%02d' % eta_datetime_local.minute

			var years_match: bool = eta_datetime_local.year == departure_datetime_local.year
			var months_match: bool = eta_datetime_local.month == departure_datetime_local.month
			var days_match: bool = eta_datetime_local.day == departure_datetime_local.day

			if years_match and months_match and days_match:
				formatted_eta = '%s:%s %s' % [eta_hour_str, eta_minute_str, am_pm_str]
			else:
				var month_name_str: String = '???'
				if eta_datetime_local.month >= 1 and eta_datetime_local.month <= 12:
					month_name_str = ABBREVIATED_MONTH_NAMES[eta_datetime_local.month]
				var day_to_display = eta_datetime_local.get('day', '??')
				formatted_eta = '%s %s, %s:%s %s' % [month_name_str, day_to_display, eta_hour_str, eta_minute_str, am_pm_str]
		else: # Fallback if proper parsing failed
			if eta_raw_string.length() >= 16:
				formatted_eta = eta_raw_string.substr(0, 16).replace('T', ' ')
			else:
				formatted_eta = eta_raw_string
	return formatted_eta


func _parse_iso_to_utc_dict(iso_string: String) -> Dictionary:
	var components = {'year': 0, 'month': 0, 'day': 0, 'hour': 0, 'minute': 0, 'second': 0}
	if iso_string.length() >= 19: # Need YYYY-MM-DDTHH:MM:SS
		components.year = iso_string.substr(0, 4).to_int()
		components.month = iso_string.substr(5, 2).to_int()
		components.day = iso_string.substr(8, 2).to_int()
		components.hour = iso_string.substr(11, 2).to_int()
		components.minute = iso_string.substr(14, 2).to_int()
		components.second = iso_string.substr(17, 2).to_int()
		if components.year > 0 and components.month > 0 and components.day > 0:
			return components
	return {} # Return empty if parsing failed


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
