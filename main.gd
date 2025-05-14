# main.gd
extends Node2D

# Preload the map rendering script
const MapRenderer = preload('res://map_render.gd')
# Reference the node that will display the map
@onready var map_display: TextureRect = $MapDisplay

# Reference to your APICalls node.
# IMPORTANT: Adjust the path "$APICallsInstance" to the actual path of your APICalls node
# in your scene tree relative to the node this script (main.gd) is attached to.
@onready var api_calls_node: Node = $APICallsInstance # Adjust if necessary
# IMPORTANT: Adjust this path to where you actually place your detailed view toggle in your scene tree!
@onready var detailed_view_toggle: CheckBox = $DetailedViewToggleCheckbox # Example path

var map_renderer  # Will be initialized in _ready()
var map_tiles: Array = []  # Will hold the loaded tile data
var _all_settlement_data: Array = []  # To store settlement data for rendering
var _all_convoy_data: Array = []  # To store convoy data from APICalls

var _refresh_timer: Timer
const REFRESH_INTERVAL_SECONDS: float = 60.0  # Changed to 3 minutes
var _visual_update_timer: Timer
const VISUAL_UPDATE_INTERVAL_SECONDS: float = .5  # e.g., 20 FPS for visual updates
var _throb_phase: float = 0.0  # Cycles 0.0 to 1.0 for a 1-second throb
var _convoy_label_container: Node2D
var _settlement_label_container: Node2D  # New container for settlement labels
var _label_settings: LabelSettings
var _settlement_label_settings: LabelSettings
var _refresh_notification_label: Label  # For the "Data Refreshed" notification
var _default_theme_label_font: Font = null  # To store the font for labels

# --- Base sizes for UI elements (will be scaled) ---
const BASE_CONVOY_TITLE_FONT_SIZE: int = 64
# const BASE_CONVOY_DETAIL_FONT_SIZE: int = 52 # No longer used as convoy labels will have uniform font size
const BASE_SETTLEMENT_FONT_SIZE: int = 52  # Increased from 28
const MIN_FONT_SIZE: int = 8  # Minimum scaled font size
const FONT_SCALING_BASE_TILE_SIZE: float = 24.0  # Should match map_render.gd's BASE_TILE_SIZE_FOR_PROPORTIONS
const FONT_SCALING_EXPONENT: float = .6  # Adjust for more/less aggressive font scaling (1.0 = linear)

const BASE_HORIZONTAL_LABEL_OFFSET_FROM_CENTER: float = 15.0  # Base pixels to offset label to the right of convoy center (Reduced)
const BASE_SELECTED_CONVOY_HORIZONTAL_OFFSET: float = 60.0 # Larger offset for selected convoys
const BASE_SETTLEMENT_OFFSET_ABOVE_TILE_CENTER: float = 10.0  # Base pixels the TOP of the settlement label is above the tile center (after accounting for label height)
const BASE_COLOR_INDICATOR_SIZE: float = 14.0  # Base size of the square color indicator
const BASE_COLOR_INDICATOR_PADDING: float = 4.0  # Base padding between color indicator and text
const BASE_CONVOY_PANEL_CORNER_RADIUS: float = 8.0
const BASE_CONVOY_PANEL_PADDING_H: float = 8.0 # Horizontal padding inside the panel
const BASE_CONVOY_PANEL_PADDING_V: float = 5.0 # Vertical padding inside the panel
const CONVOY_PANEL_BACKGROUND_COLOR: Color = Color(0.12, 0.12, 0.15, 0.88) # Dark grey, slightly transparent
const BASE_SETTLEMENT_PANEL_CORNER_RADIUS: float = 6.0
const BASE_SETTLEMENT_PANEL_PADDING_H: float = 6.0
const BASE_SETTLEMENT_PANEL_PADDING_V: float = 4.0
const SETTLEMENT_PANEL_BACKGROUND_COLOR: Color = Color(0.15, 0.12, 0.12, 0.85) # Slightly different dark grey for settlements

# This constant is for the old anti-collision logic, may not be needed with single hover labels
const LABEL_ANTI_COLLISION_Y_SHIFT: float = 5.0
const LABEL_MAP_EDGE_PADDING: float = 5.0 # Pixels to keep labels from map edge
const PREDEFINED_CONVOY_COLORS: Array[Color] = [  # Copied from map_render.gd; could these be imported instead?
	Color.RED,        # Red
	Color.BLUE,       # Blue
	Color.GREEN,      # Green
	Color.YELLOW,     # Yellow
	Color.CYAN,       # Cyan
	Color.MAGENTA,    # Magenta
	Color('orange'),  # Orange
	Color('purple'),  # Purple
	Color('lime'),    # Lime Green
	Color('pink')     # Pink
]

var _convoy_id_to_color_map: Dictionary = {}
var _last_assigned_color_idx: int = -1  # To cycle through PREDEFINED_CONVOY_COLORS for new convoys
const CONVOY_HOVER_RADIUS_ON_TEXTURE_SQ: float = 625.0  # (25 pixels)^2, adjust as needed
const SETTLEMENT_HOVER_RADIUS_ON_TEXTURE_SQ: float = 400.0  # (20 pixels)^2, adjust as needed for settlements

var _current_hover_info: Dictionary = {}  # To store what the mouse is currently hovering over
var _selected_convoy_ids: Array[String] = []  # To store IDs of clicked/selected convoys

var show_detailed_view: bool = true  # Single flag for toggling detailed map features (grid & political)

var _dragging_panel_node: Panel = null  # Panel currently being dragged
var _drag_offset: Vector2 = Vector2.ZERO  # Mouse offset from panel's top-left during drag
var _convoy_label_user_positions: Dictionary = {}  # Stores user-set positions: { 'convoy_id': Vector2(x,y) }

# Emojis for labels
const CONVOY_STAT_EMOJIS: Dictionary = {
	'efficiency': '🌿',
	'top_speed': '🚀',
	'offroad_capability': '🥾',
}

# Emojis for settlement types

const ABBREVIATED_MONTH_NAMES: Array[String] = [
	'N/A',  # Index 0 (unused for months 1-12)
	'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
	'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
]


func _ready():
	print('Main: _ready() called.')  # DEBUG

	# Enable input processing for this Node2D to receive _input events,
	# including those propagated from its Control children (like MapDisplay).
	set_process_input(true)
	# Instantiate the map renderer
	# Ensure the MapDisplay TextureRect scales its texture nicely
	if map_display:
		map_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		print('Main: map_display found and stretch_mode set.')  # DEBUG
		# Explicitly set texture filter for smoother scaling.
		map_display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

		# Create settlement label container first, so it's drawn underneath convoy labels
		_settlement_label_container = Node2D.new()  # Create settlement label container
		_settlement_label_container.name = 'SettlementLabelContainer'
		map_display.add_child(_settlement_label_container)  # Add it as a child

		# Create a container for convoy labels as a child of MapDisplay, added after settlements
		_convoy_label_container = Node2D.new()
		_convoy_label_container.name = 'ConvoyLabelContainer'
		map_display.add_child(_convoy_label_container)
		print('Main: ConvoyLabelContainer added to MapDisplay.')

		# Attempt to get the default theme font for Label nodes
		_default_theme_label_font = map_display.get_theme_font('font', 'Label')
		if _default_theme_label_font:
			print('Main: Successfully retrieved theme font for Label: ', _default_theme_label_font.resource_path if _default_theme_label_font.resource_path else 'Built-in font')
		else:
			print('Main: No specific theme font found for "Label". Labels will use engine default or font set in LabelSettings.')

	# Setup LabelSettings for convoy labels
	_label_settings = LabelSettings.new()
	_label_settings.font = _default_theme_label_font  # Use the retrieved theme font, or null if none found
	# _label_settings.font_size = BASE_CONVOY_TITLE_FONT_SIZE  # Base size, will be overridden dynamically
	_label_settings.font_color = Color.WHITE
	_label_settings.outline_size = 6  # Increased from 4 for better readability
	_label_settings.outline_color = Color.BLACK

	# Setup LabelSettings for settlement labels (drawn on image)
	_settlement_label_settings = LabelSettings.new()  # Corrected variable name
	# _settlement_label_settings.font_size = BASE_SETTLEMENT_FONT_SIZE  # Base size, will be overridden dynamically
	_settlement_label_settings.font_color = Color.WHITE  # Ensure color is set
	_settlement_label_settings.outline_size = 3  # Adjust as needed
	_settlement_label_settings.outline_color = Color.BLACK

	# --- Load the JSON data ---
	var file_path = 'res://foo.json'
	var file = FileAccess.open(file_path, FileAccess.READ)

	var err_code = FileAccess.get_open_error()
	if err_code != OK:
		printerr('Error opening map json file: ', file_path)
		printerr('FileAccess error code: ', err_code)  # DEBUG
		return

	print('Main: Successfully opened foo.json.')  # DEBUG
	var json_string = file.get_as_text()
	file.close()

	var json_data = JSON.parse_string(json_string)

	if json_data == null:
		printerr('Error parsing JSON map data from: ', file_path)
		printerr('JSON string was: ', json_string) # DEBUG
		return

	print('Main: Successfully parsed foo.json.')  # DEBUG
	# --- Extract tile data ---
	# Ensure the JSON structure has a "tiles" key containing an array
	if not json_data is Dictionary or not json_data.has('tiles'):
		printerr('JSON data does not contain a "tiles" key.')
		printerr('Parsed JSON data: ', json_data)  # DEBUG
		return

	map_tiles = json_data.get('tiles', [])  # Assign to the class member
	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		printerr('Map tiles data is empty or invalid.')
		printerr('Extracted map_tiles: ', map_tiles)  # DEBUG
		map_tiles = []  # Ensure it's empty if invalid
		return

	# Populate _all_settlement_data from map_tiles
	_all_settlement_data.clear()
	for y_idx in range(map_tiles.size()):
		var row = map_tiles[y_idx]
		if not row is Array: continue
		for x_idx in range(row.size()):
			var tile_data = row[x_idx]
			if tile_data is Dictionary and tile_data.has('settlements'):
				var settlements_on_tile = tile_data.get('settlements', [])
				if settlements_on_tile is Array:
					for settlement_entry in settlements_on_tile:
						if settlement_entry is Dictionary and settlement_entry.has('name'):
							var settlement_info_for_render = settlement_entry.duplicate()
							settlement_info_for_render['x'] = x_idx  # Ensure we use tile's x for rendering
							settlement_info_for_render['y'] = y_idx  # Ensure we use tile's y for rendering
							_all_settlement_data.append(settlement_info_for_render)
							# print('Main: Loaded settlement for render: %s at tile (%s, %s)' % [settlement_info_for_render.get('name'), x_idx, y_idx])  # DEBUG

	# Initial map render and display
	map_renderer = MapRenderer.new() # Initialize the class member here

	# Ensure map_display is correctly sized and positioned before the first render
	# and before any UI elements dependent on its size/position are placed.
	if is_instance_valid(map_display):
		map_display.position = Vector2.ZERO
		map_display.size = get_viewport_rect().size

	_update_map_display() # Now render the map with map_display correctly sized

	# Connect to the viewport's size_changed signal to re-render on window resize
	get_viewport().connect('size_changed', Callable(self, '_on_viewport_size_changed'))
	_on_viewport_size_changed() # Call once at the end of _ready to ensure all initial positions are correct

	print('Main: Attempting to connect to APICallsInstance signals.')  # DEBUG
	# Connect to the APICalls signal for convoy data
	if api_calls_node:
		print('Main: api_calls_node found.')  # DEBUG
		if api_calls_node.has_signal('convoy_data_received'):
			api_calls_node.convoy_data_received.connect(_on_convoy_data_received)
			print('Main: Successfully connected to APICalls.convoy_data_received signal.')
		else:
			printerr('Main: APICalls node does not have "convoy_data_received" signal.')
			printerr('Main: api_calls_node is: ', api_calls_node)  # DEBUG
	else:
		printerr('Main: APICalls node not found at the specified path. Cannot connect signal.')

	# Setup and start the refresh timer
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_INTERVAL_SECONDS
	_refresh_timer.one_shot = false  # Make it repeat
	_refresh_timer.timeout.connect(_on_refresh_timer_timeout)
	add_child(_refresh_timer)  # Add the timer to the scene tree so it processes
	_refresh_timer.start()

	# Setup and start the visual update timer for animations like throbbing
	_visual_update_timer = Timer.new()
	_visual_update_timer.wait_time = VISUAL_UPDATE_INTERVAL_SECONDS
	_visual_update_timer.one_shot = false  # Make it repeat

	# Setup the refresh notification label
	_refresh_notification_label = Label.new()
	_refresh_notification_label.text = 'Data Refreshed!'
	# Basic styling - you can customize this further
	_refresh_notification_label.add_theme_font_size_override('font_size', 24)
	_refresh_notification_label.add_theme_color_override('font_color', Color.LIGHT_GREEN)
	_refresh_notification_label.add_theme_color_override('font_outline_color', Color.BLACK)
	_refresh_notification_label.add_theme_constant_override('outline_size', 2)
	_refresh_notification_label.modulate.a = 0.0  # Start invisible
	_refresh_notification_label.name = 'RefreshNotificationLabel'
	add_child(_refresh_notification_label)  # Add as a direct child of this Node2D
	_update_refresh_notification_position()  # Set initial position

	_visual_update_timer.timeout.connect(_on_visual_update_timer_timeout)
	add_child(_visual_update_timer)
	_visual_update_timer.start()

	# --- Setup Detailed View Toggle ---
	if is_instance_valid(detailed_view_toggle):
		detailed_view_toggle.button_pressed = show_detailed_view # Set initial state
		_update_detailed_view_toggle_position() # Set initial position
		detailed_view_toggle.toggled.connect(_on_detailed_view_toggled)
		print('Main: Detailed View toggle initialized and connected.')
	else:
		printerr('Main: DetailedViewToggleCheckbox node not found or invalid. Check the path in main.gd.')

	print('Main: Visual update timer started for every %s seconds.' % VISUAL_UPDATE_INTERVAL_SECONDS)
	print('Main: Convoy data refresh timer started for every %s seconds.' % REFRESH_INTERVAL_SECONDS)


func _on_viewport_size_changed():
	print('Main: _on_viewport_size_changed triggered.') # DEBUG
	# Ensure map_display is always at the origin of its parent and fills the viewport
	if is_instance_valid(map_display):
		map_display.position = Vector2.ZERO
		map_display.size = get_viewport_rect().size
		print('Main: map_display reset to position (0,0) and size: ', map_display.size) # DEBUG

	# Update positions of UI elements that depend on viewport/map_display size
	if is_instance_valid(_refresh_notification_label):
		_update_refresh_notification_position()
	if is_instance_valid(detailed_view_toggle):
		_update_detailed_view_toggle_position()
	_update_map_display()


func _update_map_display():
	# print('Main: _update_map_display() called.')  # DEBUG - Can be very noisy
	if map_tiles.is_empty():
		printerr('Cannot update map display: map_tiles is empty.')
		return
	if not map_renderer:
		printerr('Cannot update map display: map_renderer is not initialized.')
		return

	if not is_instance_valid(map_display): # Added safety check
		printerr('Main: map_display is not valid in _update_map_display. Cannot render.')
		return

	# print('Main: map_tiles count: ', map_tiles.size(), ' (first row count: ', str(map_tiles[0].size()) if not map_tiles.is_empty() and map_tiles[0] is Array else 'N/A', ')')  # DEBUG

	# --- Render the map ---
	# Get the current viewport size to pass to the renderer
	var current_viewport_size = get_viewport().get_visible_rect().size

	# Call render_map with all parameters, using defaults for highlights/lowlights for now
	print('Main: Calling render_map with _current_hover_info: ', _current_hover_info)  # DEBUG
	# You can pass actual highlight/lowlight data here if you have it.
	var map_texture: ImageTexture = map_renderer.render_map(
		map_tiles,
		[],  # highlights
		[],  # lowlights
		MapRenderer.DEFAULT_HIGHLIGHT_OUTLINE_COLOR,
		MapRenderer.DEFAULT_LOWLIGHT_INLINE_COLOR,
		current_viewport_size,    # Viewport size
		_all_convoy_data,         # Pass the convoy data
		_throb_phase,             # Pass the current throb phase
		_convoy_id_to_color_map,  # Pass the color map
		_current_hover_info,      # Pass hover info here
		_selected_convoy_ids,     # Pass selected convoy IDs
		show_detailed_view,       # Pass detailed view flag for grid
		show_detailed_view        # Pass detailed view flag for political colors
	)
	print('Main: map_renderer.render_map call completed.')  # DEBUG

	# --- Display the map ---
	if map_texture:
		print('Main: map_texture is valid. Size: ', map_texture.get_size(), ' Format: ', map_texture.get_image().get_format() if map_texture.get_image() else 'N/A')  # DEBUG
		# Generate mipmaps for the texture if the TextureRect's filter uses them.
		# This improves quality when the texture is scaled down.
		if map_display and (map_display.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS or \
						   map_display.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS):
			var img := map_texture.get_image()
			if img:  # Ensure image is valid
				print('Main: Generating mipmaps for map texture.')  # DEBUG
				img.generate_mipmaps()  # This modifies the image in-place; ImageTexture will update.
		map_display.texture = map_texture
		# No longer need to set map_display.set_size here, stretch_mode handles it.
		print('Main: Map (re)rendered and displayed on map_display node.')  # DEBUG
	else:
		printerr('Failed to render map texture.')

	# Update labels based on hover state
	_update_hover_labels()


func _on_convoy_data_received(data: Variant) -> void:
	print('Main: Received convoy data from APICalls.gd!')

	if data is Array:
		_all_convoy_data = data
		if not data.is_empty():
			print('Main: Stored %s convoy objects. First one: ' % data.size())
			print(data[0])  # Print only the first convoy object for brevity
		else:
			print('Main: Received an empty list of convoys.')
	elif data is Dictionary and data.has('results') and data['results'] is Array:  # Common API pattern
		_all_convoy_data = data['results']
		print('Main: Stored %s convoy objects from "results" key.' % _all_convoy_data.size())
	else:
		_all_convoy_data = []  # Clear if data is not in expected array format
		printerr('Main: Received convoy data is not an array or recognized structure. Clearing stored convoy data. Data: ', data)

	# Update convoy ID to color mapping
	for convoy_item in _all_convoy_data:
		if convoy_item is Dictionary:
			var convoy_id = convoy_item.get('convoy_id')
			if convoy_id and not convoy_id.is_empty():  # Ensure convoy_id is valid
				if not _convoy_id_to_color_map.has(convoy_id):
					# This convoy ID is new, assign it the next available color
					_last_assigned_color_idx = (_last_assigned_color_idx + 1) % PREDEFINED_CONVOY_COLORS.size()
					_convoy_id_to_color_map[convoy_id] = PREDEFINED_CONVOY_COLORS[_last_assigned_color_idx]

	# Re-render the map with the new convoy data
	_update_map_display()


func _on_refresh_timer_timeout() -> void:
	print('Main: Refresh timer timeout. Requesting updated convoy data...')
	if api_calls_node:
		api_calls_node.get_all_in_transit_convoys()
	else:
		printerr('Main: Cannot refresh convoy data, api_calls_node is not valid.')

	# Show and fade the notification label
	if is_instance_valid(_refresh_notification_label):
		_refresh_notification_label.text = 'Data Refreshed!'  # Or 'Refreshing data...'
		_refresh_notification_label.modulate.a = 1.0  # Make it fully visible
		_update_refresh_notification_position()  # Reposition in case text length changed

		# Kill any previous fade tween for this label
		if _refresh_notification_label.has_meta('fade_tween'):
			var old_tween = _refresh_notification_label.get_meta('fade_tween')
			if is_instance_valid(old_tween) and old_tween.is_valid():
				old_tween.kill()

		var new_fade_tween = create_tween()
		_refresh_notification_label.set_meta('fade_tween', new_fade_tween)
		new_fade_tween.tween_interval(2.0)  # Stay visible for 2 seconds
		new_fade_tween.tween_property(_refresh_notification_label, 'modulate:a', 0.0, 1.0)  # Fade out over 1 second
		printerr('Main: Cannot refresh convoy data, api_calls_node is not valid.')


func _on_visual_update_timer_timeout() -> void:
	# Update throb phase for a 1-second cycle
	# VISUAL_UPDATE_INTERVAL_SECONDS is how much phase advances per timer tick.
	# To complete a full cycle (0 to 1) in 1 second, the increment should be VISUAL_UPDATE_INTERVAL_SECONDS / 1.0.
	_throb_phase += VISUAL_UPDATE_INTERVAL_SECONDS
	_throb_phase = fmod(_throb_phase, 1.0)  # Wrap around 1.0

	_update_map_display()  # Re-render the map with the new throb phase


func _update_hover_labels():
	# Clear all existing hover labels
	if is_instance_valid(_convoy_label_container):
		# If a panel is being dragged, don't clear it.
		# All other panels (and their children) will be cleared and redrawn.
		for child_panel_node in _convoy_label_container.get_children():
			if child_panel_node != _dragging_panel_node: # Don't remove the panel being dragged
				child_panel_node.queue_free()
	if is_instance_valid(_settlement_label_container):
		for child in _settlement_label_container.get_children():
			child.queue_free()

	if not map_display or not is_instance_valid(map_display.texture):
		return  # Cannot position labels without a map texture

	var drawn_convoy_ids_this_update: Array[String] = [] # Keep track of what's drawn
	var drawn_settlement_tile_coords_this_update: Array[Vector2i] = [] # Store Vector2i of tile coords
	var all_drawn_label_rects_this_update: Array[Rect2] = [] # Store Rect2 of all labels drawn in this update

	# 1. Process selected convoys (draw convoy label + start/end settlement labels)
	if not _selected_convoy_ids.is_empty():
		for convoy_data in _all_convoy_data:
			var convoy_id = convoy_data.get('convoy_id')
			if convoy_id and _selected_convoy_ids.has(convoy_id):
				# If this convoy's panel is currently being dragged, skip redrawing it here.
				if is_instance_valid(_dragging_panel_node) and _dragging_panel_node.name == convoy_id:
					continue
				# STAGE 1a: Draw START/END settlement labels for this selected convoy
				var journey_data: Dictionary = convoy_data.get('journey')
				if journey_data is Dictionary:
					var route_x_coords: Array = journey_data.get('route_x')
					var route_y_coords: Array = journey_data.get('route_y')

					if route_x_coords is Array and route_y_coords is Array and \
					   route_x_coords.size() == route_y_coords.size() and not route_x_coords.is_empty():

						# Start settlement
						var start_tile_x: int = floori(float(route_x_coords[0]))
						var start_tile_y: int = floori(float(route_y_coords[0]))
						var start_tile_coords := Vector2i(start_tile_x, start_tile_y)

						if not drawn_settlement_tile_coords_this_update.has(start_tile_coords):
							var start_settlement_data = _find_settlement_at_tile(start_tile_x, start_tile_y)
							if start_settlement_data:
								var settlement_rect: Rect2 = _draw_single_settlement_label(start_settlement_data)
								if settlement_rect != Rect2():
									all_drawn_label_rects_this_update.append(settlement_rect)
								drawn_settlement_tile_coords_this_update.append(start_tile_coords) # Track to avoid re-drawing

						# End settlement
						if route_x_coords.size() > 0: # Check size, could be a 1-point journey
							var end_tile_x: int = floori(float(route_x_coords.back()))
							var end_tile_y: int = floori(float(route_y_coords.back()))
							var end_tile_coords := Vector2i(end_tile_x, end_tile_y)

							# Only draw if different from start AND not already drawn
							if end_tile_coords != start_tile_coords and \
							   not drawn_settlement_tile_coords_this_update.has(end_tile_coords):
								var end_settlement_data = _find_settlement_at_tile(end_tile_x, end_tile_y)
								if end_settlement_data:
									var settlement_rect: Rect2 = _draw_single_settlement_label(end_settlement_data)
									if settlement_rect != Rect2():
										all_drawn_label_rects_this_update.append(settlement_rect)
									drawn_settlement_tile_coords_this_update.append(end_tile_coords) # Track to avoid re-drawing

	# STAGE 1b: Process hovered settlement (if not already drawn as part of a selected convoy's journey)
	if _current_hover_info.get('type') == 'settlement':
		var hovered_tile_coords = _current_hover_info.get('coords')  # Expected Vector2i
		if hovered_tile_coords != null and hovered_tile_coords.x >= 0 and hovered_tile_coords.y >= 0: # Basic check
			if not drawn_settlement_tile_coords_this_update.has(hovered_tile_coords):
				var settlement_data_for_hover = _find_settlement_at_tile(hovered_tile_coords.x, hovered_tile_coords.y)
				if settlement_data_for_hover:
					var settlement_rect: Rect2 = _draw_single_settlement_label(settlement_data_for_hover)
					if settlement_rect != Rect2():
						all_drawn_label_rects_this_update.append(settlement_rect)
					# drawn_settlement_tile_coords_this_update.append(hovered_tile_coords) # Add if you want to prevent re-drawing if also an endpoint

	# --- STAGE 2: Draw Convoy Labels (Selected then Hovered) ---
	# These will try to avoid the settlement labels drawn in STAGE 1.

	# STAGE 2a: Draw labels for SELECTED convoys
	if not _selected_convoy_ids.is_empty():
		for convoy_data in _all_convoy_data:
			var convoy_id = convoy_data.get('convoy_id')
			if convoy_id and _selected_convoy_ids.has(convoy_id):
				# If this convoy's panel is currently being dragged, we've already skipped it above.
				if is_instance_valid(_dragging_panel_node) and _dragging_panel_node.name == convoy_id:
					continue
				if not drawn_convoy_ids_this_update.has(convoy_id): # Avoid drawing twice if somehow selected and hovered
					var convoy_panel_rect: Rect2 = _draw_single_convoy_label(convoy_data, all_drawn_label_rects_this_update)
					if convoy_panel_rect != Rect2(): # If a valid panel was drawn
						all_drawn_label_rects_this_update.append(convoy_panel_rect) # Add its rect to the list for others to avoid
					drawn_convoy_ids_this_update.append(convoy_id)

	# STAGE 2b: Process HOVERED convoy (if not already drawn as selected)
	if _current_hover_info.get('type') == 'convoy':
		var hovered_convoy_id = _current_hover_info.get('id')
		if hovered_convoy_id != null:
			if not drawn_convoy_ids_this_update.has(hovered_convoy_id): # Only draw if not already drawn as selected
				# Only proceed to draw the hovered convoy label if it's NOT currently being dragged.
				var should_draw_hovered_convoy = true
				if is_instance_valid(_dragging_panel_node) and _dragging_panel_node.name == hovered_convoy_id:
					should_draw_hovered_convoy = false # Skip, it's being handled by drag

				if should_draw_hovered_convoy:
					for convoy_data in _all_convoy_data:
						if convoy_data is Dictionary and convoy_data.get('convoy_id') == hovered_convoy_id:
							var convoy_panel_rect: Rect2 = _draw_single_convoy_label(convoy_data, all_drawn_label_rects_this_update)
							if convoy_panel_rect != Rect2(): # If a valid panel was drawn
								all_drawn_label_rects_this_update.append(convoy_panel_rect)
							break # Found the hovered convoy

# The following _update_..._labels functions are no longer used for hover labels
# but contain the logic for creating individual labels. We'll extract that logic.
func _update_convoy_labels() -> void:
	# If you want these Label nodes to be hover-dependent, you'd add similar logic here
	# to show/hide them based on _current_hover_info.
	# For example, you could set label.visible = false by default, and then
	# in an input handling function, if a convoy is hovered, find its corresponding label
	# and set label.visible = true.

	# For now, to avoid confusion with the image-drawn labels from map_render.gd,
	# you might want to keep these entirely commented out or ensure they are hidden
	# if you are focusing on the map_render.gd labels.
	# Example:
	# if not _current_hover_info.get('type') == 'convoy': #  Or some other logic
	#    # Clear existing labels if not hovering over a convoy, or manage visibility
	#    for child in _convoy_label_container.get_children():
	#        child.queue_free()  # or child.visible = false
	#    return
	# else:
	#    # Logic to show only the hovered convoy's label
	#    pass

	# This function is now deprecated for hover labels.
	# The logic has been moved to _draw_single_convoy_label and _update_hover_labels.
	if not is_instance_valid(_convoy_label_container):
		printerr('Main: ConvoyLabelContainer is not valid. Cannot update labels.')
		return

	# Clear existing labels
	for child in _convoy_label_container.get_children():
		child.queue_free()

	if not map_display or not is_instance_valid(map_display.texture):
		# print('Main: No map texture on MapDisplay, skipping label update.')  # Can be noisy
		return

	if _all_convoy_data.is_empty():
		# print('Main: No convoy data, skipping label update.')  # Can be noisy
		return

	var map_texture: ImageTexture = map_display.texture
	var map_texture_size: Vector2 = map_texture.get_size()
	var map_display_rect_size: Vector2 = map_display.size

	if map_texture_size.x == 0 or map_texture_size.y == 0:
		printerr('Main: Map texture size is zero, cannot calculate label positions.')
		return

	# Calculate scaling and offset of the texture within MapDisplay (due to STRETCH_KEEP_ASPECT_CENTERED)
	var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
	var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y
	var actual_scale: float = min(scale_x_ratio, scale_y_ratio)

	var displayed_texture_width: float = map_texture_size.x * actual_scale
	var displayed_texture_height: float = map_texture_size.y * actual_scale

	var offset_x: float = (map_display_rect_size.x - displayed_texture_width) / 2.0
	var offset_y: float = (map_display_rect_size.y - displayed_texture_height) / 2.0

	# Get tile dimensions on the unscaled map texture (needed to convert map coords to texture pixels)
	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		printerr('Main: map_tiles data is invalid, cannot calculate label positions accurately.')
		return
	var map_image_cols: int = map_tiles[0].size()
	var map_image_rows: int = map_tiles.size()
	var actual_tile_width_on_texture: float = map_texture_size.x / float(map_image_cols)
	var actual_tile_height_on_texture: float = map_texture_size.y / float(map_image_rows)

	var placed_label_rects: Array[Rect2] = [] # To store rects of already placed labels for collision avoidance

	for convoy_idx in range(_all_convoy_data.size()):
		var convoy_data = _all_convoy_data[convoy_idx]
		var convoy_name: String = convoy_data.get('convoy_name', 'N/A')
		var journey_data: Dictionary = convoy_data.get('journey', {})
		var progress: float = journey_data.get('progress', 0.0)
		var length: float = journey_data.get('length', 0.0)
		var convoy_map_x: float = convoy_data.get('x', 0.0)
		var convoy_map_y: float = convoy_data.get('y', 0.0)

		var progress_percentage_str: String = 'N/A'
		if length > 0.001:  # Avoid division by zero or tiny lengths
			var percentage: float = (progress / length) * 100.0
			progress_percentage_str = '%.1f%%' % percentage  # Format to one decimal place

		var label_text: String = '%s (%s)' % [convoy_name, progress_percentage_str]

		# Get the persistent color for this convoy
		var current_convoy_id = convoy_data.get('convoy_id')
		var unique_convoy_color: Color = _convoy_id_to_color_map.get(current_convoy_id, Color.GRAY)  # Fallback to gray if ID somehow not in map

		var label := Label.new()
		label.text = label_text
		label.label_settings = _label_settings

		# Wait for label to get its size after text and settings are applied
		# This is a bit of a workaround; ideally, we'd force an update or use call_deferred.
		# For now, we'll add it to the tree, get size, then set pivot.
		_convoy_label_container.add_child(label)  # Temporarily add to get size
		var label_min_size: Vector2 = label.get_minimum_size()
		label.pivot_offset = Vector2(0, label_min_size.y / 2.0)  # Pivot at left-middle
		_convoy_label_container.remove_child(label)  # Remove before final positioning

		# Calculate convoy's center pixel position on the unscaled map texture
		var convoy_center_on_texture_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_texture
		var convoy_center_on_texture_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_texture

		# Calculate initial desired label position within MapDisplay's coordinate system
		# Positioned to the right of the convoy center, vertically aligned with convoy center
		label.position.x = (convoy_center_on_texture_x * actual_scale + offset_x) + (BASE_HORIZONTAL_LABEL_OFFSET_FROM_CENTER * actual_scale)
		label.position.y = convoy_center_on_texture_y * actual_scale + offset_y

		# Create and configure the color indicator
		var color_indicator := ColorRect.new()
		color_indicator.color = unique_convoy_color
		color_indicator.size = Vector2(BASE_COLOR_INDICATOR_SIZE * actual_scale, BASE_COLOR_INDICATOR_SIZE * actual_scale)
		# Position the color indicator to the right of the label
		# Note: label.position.x is its pivot (left edge), label_min_size.x is its width
		color_indicator.position.x = label.position.x + label_min_size.x + (BASE_COLOR_INDICATOR_PADDING * actual_scale)
		color_indicator.position.y = (convoy_center_on_texture_y * actual_scale + offset_y) - ((BASE_COLOR_INDICATOR_SIZE * actual_scale) / 2.0)  # Vertically center indicator with convoy

		# Anti-collision: check against already placed labels and shift down if needed
		# For collision, consider the combined rect of indicator + label
		var combined_item_top_left_x: float = label.position.x - label.pivot_offset.x  # Label's actual left edge
		var combined_item_top_left_y: float = min(color_indicator.position.y, label.position.y - label.pivot_offset.y)
		var combined_item_width: float = (color_indicator.position.x + (BASE_COLOR_INDICATOR_SIZE * actual_scale)) - combined_item_top_left_x
		var combined_item_height: float = max(color_indicator.position.y + (BASE_COLOR_INDICATOR_SIZE * actual_scale), label.position.y - label.pivot_offset.y + label_min_size.y) - combined_item_top_left_y
		var current_item_rect := Rect2(combined_item_top_left_x, combined_item_top_left_y, combined_item_width, combined_item_height)

		for attempt in range(10):  # Max 10 attempts to avoid overlap
			var collides: bool = false
			for placed_rect in placed_label_rects:
				if current_item_rect.intersects(placed_rect, true):  # Use true for pixel-perfect intersection if needed, though Rect2 usually fine
					collides = true
					# Shift both indicator and label down
					color_indicator.position.y += LABEL_ANTI_COLLISION_Y_SHIFT + combined_item_height * 0.1
					label.position.y += LABEL_ANTI_COLLISION_Y_SHIFT + label_min_size.y * 0.1  # Shift down by a bit more than just the shift amount
					combined_item_top_left_y = min(color_indicator.position.y, label.position.y - label.pivot_offset.y)
					current_item_rect = Rect2(combined_item_top_left_x, combined_item_top_left_y, combined_item_width, combined_item_height)
					break  # Re-check against all placed rects with new position
			if not collides:
				break  # Found a non-colliding position

		placed_label_rects.append(current_item_rect)  # Add final rect for next item's collision check
		# Add label first, then indicator, so indicator is drawn 'on top' if they overlap (though they shouldn't much)
		_convoy_label_container.add_child(label)
		_convoy_label_container.add_child(color_indicator)


# The following _update_settlement_labels function is no longer used for hover labels.
func _update_settlement_labels() -> void:
	# Similar to _update_convoy_labels, if you want these Label nodes
	# to be hover-dependent, you'd add logic here.
	# For now, to focus on map_render.gd labels, you might keep this commented out
	# or ensure these labels are hidden.

	# This function is now deprecated for hover labels.
	# The logic has been moved to _draw_single_settlement_label and _update_hover_labels.
	if not is_instance_valid(_settlement_label_container):
		printerr('Main: SettlementLabelContainer is not valid. Cannot update labels.')
		return

	# Clear existing settlement labels
	for child in _settlement_label_container.get_children():
		child.queue_free()

	if not map_display or not is_instance_valid(map_display.texture):
		# print('Main: No map texture on MapDisplay, skipping settlement label update.')
		return

	if _all_settlement_data.is_empty():
		# print('Main: No settlement data, skipping settlement label update.')
		return

	var map_texture_size: Vector2 = map_display.texture.get_size()
	var map_display_rect_size: Vector2 = map_display.size

	if map_texture_size.x == 0 or map_texture_size.y == 0:
		printerr('Main: Map texture size is zero, cannot calculate settlement label positions.')
		return

	# Calculate scaling and offset of the texture within MapDisplay
	var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
	var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y
	var actual_scale: float = min(scale_x_ratio, scale_y_ratio)

	var displayed_texture_width: float = map_texture_size.x * actual_scale
	var displayed_texture_height: float = map_texture_size.y * actual_scale
	var offset_x: float = (map_display_rect_size.x - displayed_texture_width) / 2.0
	var offset_y: float = (map_display_rect_size.y - displayed_texture_height) / 2.0

	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		printerr('Main: map_tiles data is invalid for settlement labels.')
		return
	var map_image_cols: int = map_tiles[0].size()
	var map_image_rows: int = map_tiles.size()
	var actual_tile_width_on_texture: float = map_texture_size.x / float(map_image_cols)
	var actual_tile_height_on_texture: float = map_texture_size.y / float(map_image_rows)

	for settlement_info in _all_settlement_data:
		var settlement_name_local: String = settlement_info.get('name', 'N/A')
		var tile_x: int = settlement_info.get('x', -1)  # tile_x from main.gd's processing
		var tile_y: int = settlement_info.get('y', -1)  # tile_y from main.gd's processing
		if tile_x < 0 or tile_y < 0: continue  # Ensure valid tile coordinates
		if settlement_name_local == 'N/A': continue  # Skip if name is not available

		var label := Label.new()
		label.text = name
		label.label_settings = _settlement_label_settings  # Use pre-configured LabelSettings

		_settlement_label_container.add_child(label)  # Add to tree to get size
		var label_size: Vector2 = label.get_minimum_size()
		_settlement_label_container.remove_child(label)  # Remove for final positioning

		var tile_center_tex_x: float = (float(tile_x) + 0.5) * actual_tile_width_on_texture
		var tile_center_tex_y: float = (float(tile_y) + 0.5) * actual_tile_height_on_texture
		label.position = Vector2(tile_center_tex_x * actual_scale + offset_x - (label_size.x / 2.0), tile_center_tex_y * actual_scale + offset_y - (label_size.y / 2.0))
		_settlement_label_container.add_child(label)


# New helper function to draw a single convoy label
func _draw_single_convoy_label(convoy_data: Dictionary, existing_label_rects: Array[Rect2]) -> Rect2:
	if not is_instance_valid(_convoy_label_container):
		printerr('Main: ConvoyLabelContainer is not valid. Cannot draw single convoy label.')
		return Rect2()
	if not map_display or not is_instance_valid(map_display.texture):
		return Rect2()  # Cannot position labels without a map texture

	var map_texture: ImageTexture = map_display.texture
	var map_texture_size: Vector2 = map_texture.get_size()
	var map_display_rect_size: Vector2 = map_display.size

	if map_texture_size.x == 0 or map_texture_size.y == 0:
		printerr('Main: Map texture size is zero, cannot calculate single convoy label position.')
		return Rect2()

	# Calculate scaling and offset of the texture within MapDisplay
	var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
	var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y
	var actual_scale: float = min(scale_x_ratio, scale_y_ratio)

	var displayed_texture_width: float = map_texture_size.x * actual_scale
	var displayed_texture_height: float = map_texture_size.y * actual_scale

	var offset_x: float = (map_display_rect_size.x - displayed_texture_width) / 2.0
	var offset_y: float = (map_display_rect_size.y - displayed_texture_height) / 2.0

	# Get tile dimensions on the unscaled map texture (needed to convert map coords to texture pixels)
	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		printerr('Main: map_tiles data is invalid, cannot calculate single convoy label position accurately.')
		return Rect2()
	var map_image_cols: int = map_tiles[0].size()
	var map_image_rows: int = map_tiles.size()
	var actual_tile_width_on_texture: float = map_texture_size.x / float(map_image_cols)
	var actual_tile_height_on_texture: float = map_texture_size.y / float(map_image_rows)

	# Calculate font rendering scale based on how map tiles are scaled
	var effective_tile_size_on_texture: float = min(actual_tile_width_on_texture, actual_tile_height_on_texture)
	var base_linear_font_scale: float = 1.0
	if FONT_SCALING_BASE_TILE_SIZE > 0.001:  # Avoid division by zero
		base_linear_font_scale = effective_tile_size_on_texture / FONT_SCALING_BASE_TILE_SIZE

	var font_render_scale: float = pow(base_linear_font_scale, FONT_SCALING_EXPONENT)

	var current_convoy_title_font_size: int = max(MIN_FONT_SIZE, roundi(BASE_CONVOY_TITLE_FONT_SIZE * font_render_scale))
	# var current_convoy_detail_font_size: int = max(MIN_FONT_SIZE, roundi(BASE_CONVOY_DETAIL_FONT_SIZE * font_render_scale)) # No longer needed for label text

	var current_convoy_id_for_offset_check = convoy_data.get('convoy_id') # Get ID for checking selection status
	var current_horizontal_offset: float
	if _selected_convoy_ids.has(current_convoy_id_for_offset_check):
		current_horizontal_offset = BASE_SELECTED_CONVOY_HORIZONTAL_OFFSET * actual_scale
	else:
		current_horizontal_offset = BASE_HORIZONTAL_LABEL_OFFSET_FROM_CENTER * actual_scale

	var current_color_indicator_size: float = BASE_COLOR_INDICATOR_SIZE * actual_scale
	var current_color_indicator_padding: float = BASE_COLOR_INDICATOR_PADDING * actual_scale
	var current_panel_corner_radius: float = BASE_CONVOY_PANEL_CORNER_RADIUS * font_render_scale # Scale radius with font scale
	var current_panel_padding_h: float = BASE_CONVOY_PANEL_PADDING_H * font_render_scale
	var current_panel_padding_v: float = BASE_CONVOY_PANEL_PADDING_V * font_render_scale

	# Extract additional details
	var efficiency: float = convoy_data.get('efficiency', 0.0)
	var convoy_map_x: float = convoy_data.get('x', 0.0) # Moved here for clarity
	var current_convoy_id = convoy_data.get('convoy_id') # Declare once here
	var top_speed: float = convoy_data.get('top_speed', 0.0)
	var offroad_capability: float = convoy_data.get('offroad_capability', 0.0)
	var convoy_name: String = convoy_data.get('convoy_name', 'N/A')
	var journey_data: Dictionary = convoy_data.get('journey', {})
	# var current_convoy_id = convoy_data.get('convoy_id') # Get current convoy_id for selection check - Already declared above
	var convoy_map_y: float = convoy_data.get('y', 0.0) # Keep y for positioning calculations
	var progress: float = journey_data.get('progress', 0.0)
	# Format ETA
	var eta_raw_string: String = journey_data.get('eta', 'N/A')
	var departure_raw_string: String = journey_data.get('departure_time', 'N/A')
	var formatted_eta: String = 'N/A'
	if eta_raw_string != 'N/A' and not eta_raw_string.is_empty() and \
	   departure_raw_string != 'N/A' and not departure_raw_string.is_empty():

		var eta_datetime_local: Dictionary = {}
		var departure_datetime_local: Dictionary = {}

		# Helper function to manually parse ISO string to a UTC datetime dict
		var parse_iso_to_utc_dict = func(iso_string: String) -> Dictionary:
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
			return {}  # Return empty if parsing failed

		var eta_utc_dict: Dictionary = parse_iso_to_utc_dict.call(eta_raw_string)
		var departure_utc_dict: Dictionary = parse_iso_to_utc_dict.call(departure_raw_string)

		# Calculate local time offset from UTC using system time
		var local_offset_seconds: int = 0
		var current_local_components: Dictionary = Time.get_datetime_dict_from_system(false)  # false for local
		var current_utc_components: Dictionary = Time.get_datetime_dict_from_system(true)     # true for UTC
		var successfully_got_offset: bool = false

		if not current_local_components.is_empty() and not current_utc_components.is_empty():
			var current_system_unix_local: int = Time.get_unix_time_from_datetime_dict(current_local_components)
			var current_system_unix_utc: int = Time.get_unix_time_from_datetime_dict(current_utc_components)

			if current_system_unix_local > 0 and current_system_unix_utc > 0:
				local_offset_seconds = current_system_unix_local - current_system_unix_utc
				successfully_got_offset = true
		# timezone_offset_str is no longer needed

		if not eta_utc_dict.is_empty():
			# Convert UTC dict to UTC Unix timestamp
			var eta_unix_time_utc: int = Time.get_unix_time_from_datetime_dict(eta_utc_dict)  # Input dict is UTC, no second arg needed
			if eta_unix_time_utc > 0:
				var eta_unix_time_local: int = eta_unix_time_utc + local_offset_seconds
				eta_datetime_local = Time.get_datetime_dict_from_unix_time(eta_unix_time_local)  # Get dict from local unix time

		if not departure_utc_dict.is_empty():
			# Convert UTC dict to UTC Unix timestamp
			var departure_unix_time_utc: int = Time.get_unix_time_from_datetime_dict(departure_utc_dict)  # Input dict is UTC, no second arg needed
			if departure_unix_time_utc > 0:
				var departure_unix_time_local: int = departure_unix_time_utc + local_offset_seconds
				departure_datetime_local = Time.get_datetime_dict_from_unix_time(departure_unix_time_local)  # Get dict from local unix time

		if not eta_datetime_local.is_empty() and not departure_datetime_local.is_empty():
			var eta_hour_24: int = eta_datetime_local.hour
			var am_pm_str: String = 'AM'
			var eta_hour_12: int = eta_hour_24

			if eta_hour_24 >= 12:
				am_pm_str = 'PM'
				if eta_hour_24 > 12:
					eta_hour_12 = eta_hour_24 - 12
			if eta_hour_12 == 0:  # Midnight case
				eta_hour_12 = 12

			var eta_hour_str = '%d' % eta_hour_12  # No zero-padding for 12-hour format typically, unless desired
			var eta_minute_str = '%02d' % eta_datetime_local.minute

			# Compare based on local dates
			var years_match: bool = eta_datetime_local.has('year') \
									and departure_datetime_local.has('year') \
									and eta_datetime_local.year == departure_datetime_local.year
			var months_match: bool = eta_datetime_local.has('month') \
									 and departure_datetime_local.has('month') \
									 and eta_datetime_local.month == departure_datetime_local.month
			var days_match: bool = eta_datetime_local.has('day') \
								   and departure_datetime_local.has('day') \
								   and eta_datetime_local.day == departure_datetime_local.day

			if years_match and months_match and days_match:
				# formatted_eta = 'Today, %s:%s %s' % [eta_hour_str, eta_minute_str, am_pm_str]
				formatted_eta = '%s:%s %s' % [eta_hour_str, eta_minute_str, am_pm_str]
			else:
				var month_name_str: String = '???'  # Fallback month name
				if eta_datetime_local.has('month') and eta_datetime_local.month >= 1 and eta_datetime_local.month <= 12:
					month_name_str = ABBREVIATED_MONTH_NAMES[eta_datetime_local.month]
				var day_to_display = eta_datetime_local.get('day', '??')
				formatted_eta = '%s %s, %s:%s %s' % [month_name_str, day_to_display, eta_hour_str, eta_minute_str, am_pm_str]
		else:  # Fallback if parsing failed
			# Simpler fallback if proper parsing fails, this won't be timezone aware
			if eta_raw_string.length() >= 16:
				formatted_eta = eta_raw_string.substr(0, 16).replace('T', ' ')  # YYYY-MM-DD HH:MM
			else:
				formatted_eta = eta_raw_string  # Or just the raw string if too short or completely unparsable

	var progress_percentage_str: String = 'N/A'
	var length: float = journey_data.get('length', 0.0)
	if length > 0.001:  # Avoid division by zero or tiny lengths
		var percentage: float = (progress / length) * 100.0
		progress_percentage_str = '%.1f%%' % percentage  # Format to one decimal place

	var label_text: String
	if _selected_convoy_ids.has(current_convoy_id): # Check if this convoy is selected
		# --- Detailed View ---
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
		var vehicles: Array = convoy_data.get('vehicle_details_list', []) # Using the list from APICalls.gd
		if vehicles.is_empty():
			label_text += '  None\n'
		else:
			for v_detail in vehicles:
				label_text += '%s | 🌿: %.1f | 🚀: %.1f | 🥾: %.1f\n' % [
					v_detail.get('make_model', 'N/A'),
					v_detail.get('efficiency', 0.0), v_detail.get('top_speed', 0.0), v_detail.get('offroad_capability', 0.0)
				]
				# Vehicle description can be very long, so decide if you want to include it here.
				# var v_desc = v_detail.get('description', '')
				# if not v_desc.is_empty(): label_text += '    %s\n' % v_desc

				var v_cargo_items: Array = v_detail.get('cargo', [])
				if not v_cargo_items.is_empty():
					for cargo_item in v_cargo_items:  # Limiting to first few items for brevity on label
						label_text += '  - x%s %s\n' % [
							cargo_item.get('quantity', 0), cargo_item.get('name', 'N/A')
						]

		# label_text += 'Cargo Manifest:\n'
		# var all_cargo_items: Array = convoy_data.get('all_cargo', [])
		# if all_cargo_items.is_empty():
		# 	label_text += '  Empty\n'
		# else:
		# 	for cargo_item in all_cargo_items:  # Limiting to first few items for brevity on label
		# 		label_text += '  - x%s %s\n' % [
		# 			cargo_item.get('quantity', 0), cargo_item.get('name', 'N/A')
		# 		]
	else:
		# --- Summary View (Original) ---
		label_text = '%s \n🏁 %s | ETA: %s\n%s %.1f | %s %.1f | %s %.1f' % [
			convoy_name, progress_percentage_str, formatted_eta, CONVOY_STAT_EMOJIS.get('efficiency', ''), efficiency, CONVOY_STAT_EMOJIS.get('top_speed', ''), top_speed, CONVOY_STAT_EMOJIS.get('offroad_capability', ''), offroad_capability
		]
	# Dynamically set the font size on the LabelSettings resource itself
	_label_settings.font_size = current_convoy_title_font_size

	# Get the persistent color for this convoy
	# var current_convoy_id = convoy_data.get('convoy_id') # Already declared above - Redundant declaration
	var unique_convoy_color: Color = _convoy_id_to_color_map.get(current_convoy_id, Color.GRAY)  # Fallback to gray

	var label := Label.new()
	if not is_instance_valid(label):
		printerr('Main: Failed to create new Label instance in _draw_single_convoy_label.')
		return Rect2() # Cannot proceed without a valid label

	# label.bbcode_enabled = true  # This should enable BBCode parsing.
	label.set('bbcode_enabled', true)  # Using direct assignment above.
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP # Align text to the top of the label's box
	label.text = label_text
	label.label_settings = _label_settings  # Assign the LabelSettings with the updated font_size

	_convoy_label_container.add_child(label)  # Temporarily add to get size
	var label_min_size: Vector2 = label.get_minimum_size()
	label.pivot_offset = Vector2(0, 0)  # Pivot at top-left
	_convoy_label_container.remove_child(label)  # Remove before final positioning
	# The line label.add_theme_font_size_override is no longer needed as LabelSettings.font_size controls the base.

	# Calculate convoy's center pixel position on the unscaled map texture
	var convoy_center_on_texture_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_texture
	var convoy_center_on_texture_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_texture

	# Calculate convoy's center Y on the MapDisplay (scaled and offset)
	var convoy_center_display_y = convoy_center_on_texture_y * actual_scale + offset_y

	# Position the label's horizontal center to the right of the convoy icon.
	# Position the label's vertical center aligned with the convoy's vertical center.
	label.position.x = (convoy_center_on_texture_x * actual_scale + offset_x) + current_horizontal_offset # Initial X
	label.position.y = convoy_center_display_y - (label_min_size.y / 2.0) # Initial Y (top edge aligned to convoy center)

	# Create and configure the color indicator (relative to label for now)
	var color_indicator := ColorRect.new()
	color_indicator.color = unique_convoy_color
	color_indicator.size = Vector2(current_color_indicator_size, current_color_indicator_size)
	color_indicator.position.x = label.position.x + label_min_size.x + current_color_indicator_padding
	color_indicator.position.y = label.position.y + (label_min_size.y / 2.0) - (current_color_indicator_size / 2.0) # Center indicator with label's vertical middle

	# --- Create and configure the background Panel ---
	var panel := Panel.new()
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = CONVOY_PANEL_BACKGROUND_COLOR
	style_box.corner_radius_top_left = current_panel_corner_radius
	style_box.corner_radius_top_right = current_panel_corner_radius
	style_box.corner_radius_bottom_left = current_panel_corner_radius
	style_box.corner_radius_bottom_right = current_panel_corner_radius
	panel.add_theme_stylebox_override('panel', style_box)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP # Ensure panel can receive mouse events
	panel.name = str(current_convoy_id) # Use convoy_id as panel name

	# Determine panel size and position based on label and indicator
	# Label's actual top-left (considering pivot)
	var label_actual_top_left_x: float = label.position.x # Since pivot.x is 0
	# var label_actual_top_left_y = label.position.y - label.pivot_offset.y # Old calculation

	# Horizontal bounds
	var content_min_x: float = label_actual_top_left_x
	var content_max_x: float = color_indicator.position.x + color_indicator.size.x

	# Vertical bounds - based on current label/indicator positions
	var label_top_y: float = label.position.y # Since pivot.y is 0
	var label_bottom_y: float = label_top_y + label_min_size.y
	var indicator_top_y: float = color_indicator.position.y         # Top edge of the indicator
	var indicator_bottom_y: float = indicator_top_y + color_indicator.size.y # Bottom edge of the indicator
	var content_min_y: float = min(label_top_y, indicator_top_y)
	var content_max_y: float = max(label_bottom_y, indicator_bottom_y)

	panel.position.x = content_min_x - current_panel_padding_h
	panel.position.y = content_min_y - current_panel_padding_v
	panel.size.x = (content_max_x - content_min_x) + (2 * current_panel_padding_h)
	panel.size.y = (content_max_y - content_min_y) + (2 * current_panel_padding_v)

	# --- Position label and indicator *locally* within the panel ---
	# Label's pivot is (0,0) and vertical_alignment is TOP.
	# Position label's top-left at the panel's inner padding.
	label.position.x = current_panel_padding_h
	label.position.y = current_panel_padding_v

	# Position indicator relative to the label, also locally within the panel.
	color_indicator.position.x = label.position.x + label_min_size.x + current_color_indicator_padding
	color_indicator.position.y = label.position.y + (label_min_size.y / 2.0) - (color_indicator.size.y / 2.0)

	# Make children ignore mouse events so the parent panel handles them for dragging
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Add label and indicator as CHILDREN of the panel
	panel.add_child(label)

	panel.add_child(color_indicator)

	# If this convoy is selected AND has a user-defined position, use it and skip anti-collision.
	if _selected_convoy_ids.has(current_convoy_id) and _convoy_label_user_positions.has(current_convoy_id):
		panel.position = _convoy_label_user_positions[current_convoy_id] # Set panel's global position
		# print('Main: Using user position for convoy label: ', current_convoy_id, ' at ', panel.position) # DEBUG
	else:
		# Anti-collision logic (only if not using a user-defined position for the panel)
		# The panel's rectangle is now the one to check for collisions.
		var current_panel_rect = Rect2(panel.position, panel.size)

		for _attempt in range(10): # Max 10 attempts to avoid overlap
			var collides_with_existing: bool = false
			var colliding_rect_for_shift_calc: Rect2 # Store the rect we collided with
			for existing_rect in existing_label_rects:
				var buffered_existing_rect = existing_rect.grow_individual(2,2,2,2)
				if current_panel_rect.intersects(buffered_existing_rect, true):
					collides_with_existing = true
					colliding_rect_for_shift_calc = existing_rect # Store the specific rect that caused collision
					break

			if collides_with_existing:
				# Shift panel down.
				# Make the shift more aggressive, considering the height of the thing it collided with.
				var shift_based_on_collided_height = 0.0
				if is_instance_valid(colliding_rect_for_shift_calc) and colliding_rect_for_shift_calc.size.y > 0 : shift_based_on_collided_height = colliding_rect_for_shift_calc.size.y * 0.25 + LABEL_MAP_EDGE_PADDING
				var y_shift_amount = LABEL_ANTI_COLLISION_Y_SHIFT + max(label_min_size.y * 0.1, shift_based_on_collided_height)
				panel.position.y += y_shift_amount
				# Children (label, indicator) will move with the panel automatically
				# No need to update their positions here if they are children of the panel.
				current_panel_rect = Rect2(panel.position, panel.size) # Recalculate panel's rect
			else:
				break # No collision, position is good

	# --- Clamp panel position to map display bounds ---
	# Define the padded bounds within the map display
	var padded_map_bounds_rect = Rect2(offset_x + LABEL_MAP_EDGE_PADDING, offset_y + LABEL_MAP_EDGE_PADDING, displayed_texture_width - (2 * LABEL_MAP_EDGE_PADDING), displayed_texture_height - (2 * LABEL_MAP_EDGE_PADDING))
	var panel_pos_changed_by_clamping: bool = false
	var pre_clamp_panel_pos = panel.position # Store before clamping

	if panel.position.x < padded_map_bounds_rect.position.x:
		panel.position.x = padded_map_bounds_rect.position.x; panel_pos_changed_by_clamping = true
	if panel.position.x + panel.size.x > padded_map_bounds_rect.position.x + padded_map_bounds_rect.size.x:
		panel.position.x = (padded_map_bounds_rect.position.x + padded_map_bounds_rect.size.x) - panel.size.x; panel_pos_changed_by_clamping = true
	if panel.position.y < padded_map_bounds_rect.position.y:
		panel.position.y = padded_map_bounds_rect.position.y; panel_pos_changed_by_clamping = true
	if panel.position.y + panel.size.y > padded_map_bounds_rect.position.y + padded_map_bounds_rect.size.y:
		panel.position.y = (padded_map_bounds_rect.position.y + padded_map_bounds_rect.size.y) - panel.size.y; panel_pos_changed_by_clamping = true

	# If clamping changed the panel's position, its children (label, indicator) will move with it.

	# Add the fully assembled panel (with its children) to the main label container
	_convoy_label_container.add_child(panel)
	return Rect2(panel.position, panel.size) # Return the panel's final rect


# New helper function to draw a single settlement label
func _draw_single_settlement_label(settlement_info_for_render: Dictionary) -> Rect2:
	# This function uses the logic from the old _update_settlement_labels but for a single settlement
	if not is_instance_valid(_settlement_label_container):
		printerr('Main: SettlementLabelContainer is not valid. Cannot draw single settlement label.')
		return Rect2()
	if not map_display or not is_instance_valid(map_display.texture):
		return Rect2()  # Cannot position labels without a map texture

	var map_texture_size: Vector2 = map_display.texture.get_size() # map_display.texture should be valid here
	var map_display_rect_size: Vector2 = map_display.size

	if map_texture_size.x == 0 or map_texture_size.y == 0:
		printerr('Main: Map texture size is zero, cannot calculate single settlement label position.')
		return Rect2()

	# Calculate scaling and offset of the texture within MapDisplay (same logic as convoy label)
	var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
	var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y
	var actual_scale: float = min(scale_x_ratio, scale_y_ratio)

	var displayed_texture_width: float = map_texture_size.x * actual_scale
	var displayed_texture_height: float = map_texture_size.y * actual_scale
	var offset_x: float = (map_display_rect_size.x - displayed_texture_width) / 2.0
	var offset_y: float = (map_display_rect_size.y - displayed_texture_height) / 2.0

	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		printerr('Main: map_tiles data is invalid for single settlement label.')
		return Rect2()
	var map_image_cols: int = map_tiles[0].size()
	var map_image_rows: int = map_tiles.size()
	var actual_tile_width_on_texture: float = map_texture_size.x / float(map_image_cols)
	var actual_tile_height_on_texture: float = map_texture_size.y / float(map_image_rows)

	# Calculate font rendering scale based on how map tiles are scaled
	var effective_tile_size_on_texture: float = min(actual_tile_width_on_texture, actual_tile_height_on_texture)
	var base_linear_font_scale: float = 1.0
	if FONT_SCALING_BASE_TILE_SIZE > 0.001:  # Avoid division by zero
		base_linear_font_scale = effective_tile_size_on_texture / FONT_SCALING_BASE_TILE_SIZE

	var font_render_scale: float = pow(base_linear_font_scale, FONT_SCALING_EXPONENT)

	var current_settlement_font_size: int = max(MIN_FONT_SIZE, roundi(BASE_SETTLEMENT_FONT_SIZE * font_render_scale))
	var current_settlement_offset_above_center: float = BASE_SETTLEMENT_OFFSET_ABOVE_TILE_CENTER * actual_scale
	var current_settlement_panel_corner_radius: float = BASE_SETTLEMENT_PANEL_CORNER_RADIUS * font_render_scale
	var current_settlement_panel_padding_h: float = BASE_SETTLEMENT_PANEL_PADDING_H * font_render_scale
	var current_settlement_panel_padding_v: float = BASE_SETTLEMENT_PANEL_PADDING_V * font_render_scale


	# Emojis for settlement types
	const SETTLEMENT_EMOJIS: Dictionary = {
		'dome': '🏙️',
		'city': '🏢',
		'city-state': '🏢',
		'town': '🏘️',
		'village': '🏠',
		'military_base': '🪖',
	}

	# Dynamically set the font size on the LabelSettings resource itself
	_settlement_label_settings.font_size = current_settlement_font_size

	var settlement_name_local: String = settlement_info_for_render.get('name', 'N/A')
	var tile_x: int = settlement_info_for_render.get('x', -1)
	var tile_y: int = settlement_info_for_render.get('y', -1)
	if tile_x < 0 or tile_y < 0: return Rect2()
	if settlement_name_local == 'N/A': return Rect2()

	var settlement_type = settlement_info_for_render.get('sett_type', '')  # Assuming sett_type is available in settlement_info_for_render
	var settlement_emoji = SETTLEMENT_EMOJIS.get(settlement_type, '')  # Get emoji, fallback to empty string
	var label := Label.new()
	label.text = settlement_emoji + ' ' + settlement_name_local if not settlement_emoji.is_empty() else settlement_name_local  # Add emoji if found
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER # Center text vertically within the label's own bounds
	label.label_settings = _settlement_label_settings  # Assign the LabelSettings with the updated font_size

	_settlement_label_container.add_child(label)  # Add to tree to get size
	var label_size: Vector2 = label.get_minimum_size()
	# Label pivot is default (0,0) which is top-left. This is fine.
	_settlement_label_container.remove_child(label)  # Remove for final positioning

	# --- Create and configure the background Panel ---
	var panel := Panel.new()
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = SETTLEMENT_PANEL_BACKGROUND_COLOR
	style_box.corner_radius_top_left = current_settlement_panel_corner_radius
	style_box.corner_radius_top_right = current_settlement_panel_corner_radius
	style_box.corner_radius_bottom_left = current_settlement_panel_corner_radius
	style_box.corner_radius_bottom_right = current_settlement_panel_corner_radius
	panel.add_theme_stylebox_override('panel', style_box)

	# Determine panel size
	panel.size.x = label_size.x + (2 * current_settlement_panel_padding_h)
	panel.size.y = label_size.y + (2 * current_settlement_panel_padding_v)

	# Calculate initial panel position (centered above tile, accounting for panel height)
	var tile_center_tex_x: float = (float(tile_x) + 0.5) * actual_tile_width_on_texture
	var tile_center_tex_y: float = (float(tile_y) + 0.5) * actual_tile_height_on_texture
	var tile_center_display_y = tile_center_tex_y * actual_scale + offset_y

	panel.position.x = (tile_center_tex_x * actual_scale + offset_x) - (panel.size.x / 2.0)
	panel.position.y = tile_center_display_y - panel.size.y - current_settlement_offset_above_center

	# Position label inside the panel
	label.position.x = panel.position.x + current_settlement_panel_padding_h
	label.position.y = panel.position.y + current_settlement_panel_padding_v # Label's (0,0) pivot at padded top-left

	# --- Clamp panel position to map display bounds ---
	# Define the padded bounds within the map display
	var padded_map_bounds_rect = Rect2(offset_x + LABEL_MAP_EDGE_PADDING, offset_y + LABEL_MAP_EDGE_PADDING, displayed_texture_width - (2 * LABEL_MAP_EDGE_PADDING), displayed_texture_height - (2 * LABEL_MAP_EDGE_PADDING))
	var panel_pos_changed_by_clamping: bool = false
	var original_panel_pos_for_label_relative_calc = panel.position # Store before clamping for label relative pos

	if panel.position.x < padded_map_bounds_rect.position.x:
		panel.position.x = padded_map_bounds_rect.position.x; panel_pos_changed_by_clamping = true
	if panel.position.x + panel.size.x > padded_map_bounds_rect.position.x + padded_map_bounds_rect.size.x:
		panel.position.x = (padded_map_bounds_rect.position.x + padded_map_bounds_rect.size.x) - panel.size.x; panel_pos_changed_by_clamping = true
	if panel.position.y < padded_map_bounds_rect.position.y:
		panel.position.y = padded_map_bounds_rect.position.y; panel_pos_changed_by_clamping = true
	if panel.position.y + panel.size.y > padded_map_bounds_rect.position.y + padded_map_bounds_rect.size.y:
		panel.position.y = (padded_map_bounds_rect.position.y + padded_map_bounds_rect.size.y) - panel.size.y; panel_pos_changed_by_clamping = true

	if panel_pos_changed_by_clamping:
		# Recalculate label position relative to the *new* panel position
		var label_relative_to_original_panel = label.position - original_panel_pos_for_label_relative_calc
		label.position = panel.position + label_relative_to_original_panel

	_settlement_label_container.add_child(panel) # Add panel first
	_settlement_label_container.add_child(label) # Then add label
	return Rect2(panel.position, panel.size) # Return the panel's rect


# Helper function to find settlement data at specific tile coordinates
func _find_settlement_at_tile(tile_x: int, tile_y: int) -> Variant:
	for settlement_data_entry in _all_settlement_data:
		if settlement_data_entry is Dictionary:
			var s_tile_x = settlement_data_entry.get('x', -1) # 'x' is the tile_x stored during _ready
			var s_tile_y = settlement_data_entry.get('y', -1) # 'y' is the tile_y stored during _ready
			if s_tile_x == tile_x and s_tile_y == tile_y:
				return settlement_data_entry # Return the full data needed by _draw_single_settlement_label
	return null # No settlement found at these coordinates

# Helper function to get the combined screen rectangle of a convoy label and its indicator
func _get_convoy_label_combined_rect(label_node: Label, indicator_node: ColorRect) -> Rect2:
	if not is_instance_valid(label_node) or not is_instance_valid(indicator_node):
		return Rect2()

	# Label's rect (considering pivot for its actual top-left)
	var lbl_pos = label_node.position
	var lbl_pivot = label_node.pivot_offset # This is (0, label_min_size.y / 2.0)
	var lbl_size = label_node.get_minimum_size()

	var label_actual_top_left_x = lbl_pos.x - lbl_pivot.x
	var label_actual_top_left_y = lbl_pos.y - lbl_pivot.y
	var label_actual_rect = Rect2(label_actual_top_left_x, label_actual_top_left_y, lbl_size.x, lbl_size.y)

	var indicator_actual_rect = Rect2(indicator_node.position, indicator_node.size) # ColorRect pivot is top-left
	return label_actual_rect.merge(indicator_actual_rect)

func _input(event: InputEvent) -> void:  # Renamed from _gui_input
	# print('Main: _input event: ', event)  # DEBUG - Can be very noisy
	if not map_display or not is_instance_valid(map_display.texture):
		return

	if event is InputEventMouseMotion:
		# Only update drag position if a panel is being dragged AND the left mouse button is held down
		if _dragging_panel_node != null and is_instance_valid(_dragging_panel_node) and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			var new_panel_pos = get_global_mouse_position() - _drag_offset

			# --- Re-calculate map bounds for clamping during drag ---
			# This is a bit redundant but ensures clamping uses current map display state
			# Ensure map_display and its texture are valid before proceeding
			if is_instance_valid(map_display) and is_instance_valid(map_display.texture):
				var map_texture_size_drag: Vector2 = map_display.texture.get_size()
				var map_display_rect_size_drag: Vector2 = map_display.size
				if map_texture_size_drag.x > 0 and map_texture_size_drag.y > 0:
					var scale_x_ratio_drag: float = map_display_rect_size_drag.x / map_texture_size_drag.x
					var scale_y_ratio_drag: float = map_display_rect_size_drag.y / map_texture_size_drag.y
					var actual_scale_drag: float = min(scale_x_ratio_drag, scale_y_ratio_drag)
					var displayed_texture_width_drag: float = map_texture_size_drag.x * actual_scale_drag
					var displayed_texture_height_drag: float = map_texture_size_drag.y * actual_scale_drag
					var offset_x_drag: float = (map_display_rect_size_drag.x - displayed_texture_width_drag) / 2.0
					var offset_y_drag: float = (map_display_rect_size_drag.y - displayed_texture_height_drag) / 2.0
					var padded_map_bounds_drag = Rect2(
						map_display.position.x + offset_x_drag + LABEL_MAP_EDGE_PADDING,
						map_display.position.y + offset_y_drag + LABEL_MAP_EDGE_PADDING,
						displayed_texture_width_drag - (2 * LABEL_MAP_EDGE_PADDING),
						displayed_texture_height_drag - (2 * LABEL_MAP_EDGE_PADDING)
					)
					# Clamp new_panel_pos
					new_panel_pos.x = clamp(new_panel_pos.x, padded_map_bounds_drag.position.x, padded_map_bounds_drag.position.x + padded_map_bounds_drag.size.x - _dragging_panel_node.size.x)
					new_panel_pos.y = clamp(new_panel_pos.y, padded_map_bounds_drag.position.y, padded_map_bounds_drag.position.y + padded_map_bounds_drag.size.y - _dragging_panel_node.size.y)

			_dragging_panel_node.position = new_panel_pos
			_convoy_label_user_positions[_dragging_panel_node.name] = new_panel_pos # Store the ID from panel name
			# Children of _dragging_panel_node will move with it automatically. No _update_hover_labels() here.
		else: # Not dragging (or button not held), so process hover
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
				return  # Cannot determine tile dimensions

			var map_cols: int = map_tiles[0].size()
			var map_rows: int = map_tiles.size()
			var actual_tile_width_on_texture: float = map_texture_size.x / float(map_cols)
			var actual_tile_height_on_texture: float = map_texture_size.y / float(map_rows)

			# 1. Check for Convoy Hover
			if not _all_convoy_data.is_empty():
				for convoy_data in _all_convoy_data:
					if not convoy_data is Dictionary: continue
					var convoy_map_x: float = convoy_data.get('x', -1.0)
					var convoy_map_y: float = convoy_data.get('y', -1.0)
					var convoy_id = convoy_data.get('convoy_id')
					if convoy_map_x >= 0.0 and convoy_map_y >= 0.0 and convoy_id != null:
						var convoy_center_tex_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_texture
						var convoy_center_tex_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_texture
						var dx = mouse_on_texture_x - convoy_center_tex_x
						var dy = mouse_on_texture_y - convoy_center_tex_y
						if (dx * dx) + (dy * dy) < CONVOY_HOVER_RADIUS_ON_TEXTURE_SQ:
							new_hover_info = {'type': 'convoy', 'id': convoy_id}
							found_hover_element = true
							break

			# 2. Check for Settlement Hover (if no convoy was hovered)
			if not found_hover_element:
				var closest_settlement_dist_sq: float = SETTLEMENT_HOVER_RADIUS_ON_TEXTURE_SQ + 1.0
				var best_hovered_settlement_coords: Vector2i = Vector2i(-1, -1)
				for settlement_info in _all_settlement_data:
					if not settlement_info is Dictionary: continue
					var settlement_tile_x: int = settlement_info.get('x', -1)
					var settlement_tile_y: int = settlement_info.get('y', -1)
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

			# Update map if hover state changed
			if new_hover_info != _current_hover_info:
				_current_hover_info = new_hover_info
				_update_hover_labels()

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: # Mouse button DOWN
				# Check if clicking on an expanded (selected) convoy label panel to START a drag
				print('Checking for drag start click on convoy panels...') # DEBUG
				if is_instance_valid(_convoy_label_container):
					for node in _convoy_label_container.get_children():
						if node is Panel and node.get_global_rect().has_point(get_global_mouse_position()):
							var panel_node: Panel = node
							var panel_global_rect = panel_node.get_global_rect()
							var global_mouse_pos = get_global_mouse_position()
							print('  Checking Panel: %s, Global Rect: %s, Mouse Pos: %s' % [panel_node.name, panel_global_rect, global_mouse_pos]) # DEBUG
							# This inner if was already there, just ensuring the following lines are correctly indented under it.
							if panel_global_rect.has_point(global_mouse_pos):
								var convoy_id_of_panel = panel_node.name # Name should be convoy_id
								if _selected_convoy_ids.has(convoy_id_of_panel): # Only draggable if expanded/selected
									_dragging_panel_node = panel_node
									_drag_offset = get_global_mouse_position() - panel_node.position
									Input.set_default_cursor_shape(Input.CURSOR_DRAG)
									# Bring to front (optional, but good for visual feedback)
									if is_instance_valid(_convoy_label_container) and _dragging_panel_node.get_parent() == _convoy_label_container:
										_convoy_label_container.move_child(_dragging_panel_node, _convoy_label_container.get_child_count() - 1) # Move to last, draws on top
									# print('Main: Started dragging panel: ', convoy_id_of_panel) # DEBUG
									print('  Convoy %s is selected. Initiating drag.' % [convoy_id_of_panel]) # DEBUG - Changed from f-string

									get_viewport().set_input_as_handled() # Consume the event so map icon click doesn't fire
									return # Consume click, starting a drag
			elif not event.pressed: # Mouse button RELEASED
				if _dragging_panel_node != null: # If we were dragging, finalize drag
					# print('Main: Finished dragging panel: ', _dragging_panel_node.name) # DEBUG
					_dragging_panel_node = null
					Input.set_default_cursor_shape(Input.CURSOR_ARROW)
					_update_hover_labels() # Call once at the end of drag to ensure anti-collision with other labels is re-checked if needed
					get_viewport().set_input_as_handled() # Consume the event
					return # Consume this click release if it was ending a drag
				else: # This is a simple click release (not a drag release)
					# Proceed with map icon click logic for toggling selection
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

					var clicked_on_convoy_id: String = ''
					if not _all_convoy_data.is_empty():
						var actual_tile_width_on_texture: float = map_texture_size.x / float(map_tiles[0].size()) # Assuming map_tiles is not empty
						var actual_tile_height_on_texture: float = map_texture_size.y / float(map_tiles.size())
						for convoy_data in _all_convoy_data:
							if not convoy_data is Dictionary: continue
							var convoy_map_x: float = convoy_data.get('x', -1.0)
							var convoy_map_y: float = convoy_data.get('y', -1.0)
							var convoy_center_tex_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_texture
							var convoy_center_tex_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_texture
							var dx = mouse_on_texture_x - convoy_center_tex_x
							var dy = mouse_on_texture_y - convoy_center_tex_y
							if (dx * dx) + (dy * dy) < CONVOY_HOVER_RADIUS_ON_TEXTURE_SQ: # Using hover radius for click
								clicked_on_convoy_id = convoy_data.get('convoy_id', '')
								break

					if not clicked_on_convoy_id.is_empty(): # Clicked on a convoy map icon
						if _selected_convoy_ids.has(clicked_on_convoy_id):
							_selected_convoy_ids.erase(clicked_on_convoy_id) # Untoggle if already selected
							_convoy_label_user_positions.erase(clicked_on_convoy_id) # Clear user position on deselect
						else:
							_selected_convoy_ids.append(clicked_on_convoy_id) # Toggle on if not selected
						_update_hover_labels() # Update display based on new selection state
						get_viewport().set_input_as_handled() # Consume the click event
					# If clicked_on_convoy_id is empty, we just do nothing, which is the desired behavior.


func _update_refresh_notification_position():
	if not is_instance_valid(_refresh_notification_label):
		return

	var viewport_size = get_viewport_rect().size
	# Ensure the label has its size calculated based on current text and font settings
	var label_size = _refresh_notification_label.get_minimum_size()

	var padding: float = 10.0  # Pixels from the edge
	_refresh_notification_label.position = Vector2(viewport_size.x - label_size.x - padding, viewport_size.y - label_size.y - padding)

# --- UI Toggle Handler ---
func _on_detailed_view_toggled(button_pressed: bool) -> void:
	show_detailed_view = button_pressed
	print('Main: Detailed view toggled to: ', show_detailed_view)
	_update_map_display() # Re-render the map


func _update_detailed_view_toggle_position() -> void:
	if not is_instance_valid(detailed_view_toggle):
		return
	print('--- Debug: _update_detailed_view_toggle_position ---')

	if not map_display or not is_instance_valid(map_display.texture):
		printerr('Main: Cannot position detailed_view_toggle, map_display or its texture is invalid.')
		detailed_view_toggle.visible = false # Hide it if we can't position it
		return
	detailed_view_toggle.visible = true # Make sure it's visible if we can position it

	print('map_display.position: ', map_display.position)
	print('map_display.size: ', map_display.size)

	var map_texture_size: Vector2 = map_display.texture.get_size()
	var map_display_rect_size: Vector2 = map_display.size
	if map_texture_size.x <= 0 or map_texture_size.y <= 0: # More robust check
		printerr('Main: map_texture_size is zero. Aborting toggle position update.')
		return
	print('map_texture_size: ', map_texture_size)

	var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
	var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y
	var actual_scale: float = min(scale_x_ratio, scale_y_ratio)
	print('actual_scale: ', actual_scale)

	var displayed_texture_width: float = map_texture_size.x * actual_scale
	var displayed_texture_height: float = map_texture_size.y * actual_scale
	print('displayed_texture_width: ', displayed_texture_width, ', displayed_texture_height: ', displayed_texture_height)

	var offset_x: float = (map_display_rect_size.x - displayed_texture_width) / 2.0
	var offset_y: float = (map_display_rect_size.y - displayed_texture_height) / 2.0
	print('offset_x: ', offset_x, ', offset_y: ', offset_y)

	var toggle_size: Vector2 = detailed_view_toggle.get_minimum_size() # Get its actual size based on text and font
	print('toggle_size: ', toggle_size)
	print('LABEL_MAP_EDGE_PADDING: ', LABEL_MAP_EDGE_PADDING)

	# Position relative to the displayed map texture area, with LABEL_MAP_EDGE_PADDING
	# offset_x/y are relative to map_display. detailed_view_toggle.position is relative to its parent (this Node2D).
	var target_x = map_display.position.x + offset_x + displayed_texture_width - toggle_size.x - LABEL_MAP_EDGE_PADDING
	var target_y = map_display.position.y + offset_y + displayed_texture_height - toggle_size.y - LABEL_MAP_EDGE_PADDING
	print('Calculated target_x: ', target_x, ', target_y: ', target_y)
	detailed_view_toggle.position = Vector2(target_x, target_y)
