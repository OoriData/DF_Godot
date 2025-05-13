# main.gd
extends Node2D

# Preload the map rendering script
const MapRenderer = preload("res://map_render.gd")
# Reference the node that will display the map
@onready var map_display: TextureRect = $MapDisplay

# Reference to your APICalls node.
# IMPORTANT: Adjust the path "$APICallsInstance" to the actual path of your APICalls node
# in your scene tree relative to the node this script (main.gd) is attached to.
@onready var api_calls_node: Node = $APICallsInstance # Adjust if necessary

var map_renderer # Will be initialized in _ready()
var map_tiles: Array = [] # Will hold the loaded tile data
var _all_settlement_data: Array = [] # To store settlement data for rendering
var _all_convoy_data: Array = [] # To store convoy data from APICalls

var _refresh_timer: Timer
const REFRESH_INTERVAL_SECONDS: float = 60.0 # Changed to 3 minutes
var _visual_update_timer: Timer
const VISUAL_UPDATE_INTERVAL_SECONDS: float = .5 # e.g., 20 FPS for visual updates
var _throb_phase: float = 0.0 # Cycles 0.0 to 1.0 for a 1-second throb
var _convoy_label_container: Node2D
var _settlement_label_container: Node2D # New container for settlement labels
var _label_settings: LabelSettings
var _settlement_label_settings: LabelSettings
var _refresh_notification_label: Label # For the "Data Refreshed" notification
var _default_theme_label_font: Font = null # To store the font for labels

# --- Base sizes for UI elements (will be scaled) ---
const BASE_CONVOY_TITLE_FONT_SIZE: int = 64
# const BASE_CONVOY_DETAIL_FONT_SIZE: int = 52 # No longer used as convoy labels will have uniform font size
const BASE_SETTLEMENT_FONT_SIZE: int = 52    # Increased from 28
const MIN_FONT_SIZE: int = 8 # Minimum scaled font size
const FONT_SCALING_BASE_TILE_SIZE: float = 24.0 # Should match map_render.gd's BASE_TILE_SIZE_FOR_PROPORTIONS
const FONT_SCALING_EXPONENT: float = .6 # Adjust for more/less aggressive font scaling (1.0 = linear)

const BASE_HORIZONTAL_LABEL_OFFSET_FROM_CENTER: float = 15.0 # Base pixels to offset label to the right of convoy center (Reduced)
const BASE_SETTLEMENT_OFFSET_ABOVE_TILE_CENTER: float = 10.0 # Base pixels the TOP of the settlement label is above the tile center (after accounting for label height)
const BASE_COLOR_INDICATOR_SIZE: float = 14.0 # Base size of the square color indicator
const BASE_COLOR_INDICATOR_PADDING: float = 4.0 # Base padding between color indicator and text

# This constant is for the old anti-collision logic, may not be needed with single hover labels
const LABEL_ANTI_COLLISION_Y_SHIFT: float = 5.0
const PREDEFINED_CONVOY_COLORS: Array[Color] = [ # Copied from map_render.gd
	Color.RED,          # Red
	Color.BLUE,         # Blue
	Color.GREEN,        # Green
	Color.YELLOW,       # Yellow
	Color.CYAN,         # Cyan
	Color.MAGENTA,      # Magenta
	Color("orange"),    # Orange
	Color("purple"),    # Purple
	Color("lime"),      # Lime Green
	Color("pink")       # Pink
]

var _convoy_id_to_color_map: Dictionary = {}
var _last_assigned_color_idx: int = -1 # To cycle through PREDEFINED_CONVOY_COLORS for new convoys
const CONVOY_HOVER_RADIUS_ON_TEXTURE_SQ: float = 625.0 # (25 pixels)^2, adjust as needed
const SETTLEMENT_HOVER_RADIUS_ON_TEXTURE_SQ: float = 400.0 # (20 pixels)^2, adjust as needed for settlements

var _current_hover_info: Dictionary = {} # To store what the mouse is currently hovering over

# Emojis for labels
const CONVOY_STAT_EMOJIS: Dictionary = {
	"efficiency": "🌿",
	"top_speed": "🚀",
	"offroad_capability": "🏔️",
}

# Emojis for settlement types

const ABBREVIATED_MONTH_NAMES: Array[String] = [
	"N/A", # Index 0 (unused for months 1-12)
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", 
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]

func _ready():
	print("Main: _ready() called.") # DEBUG

	# Enable input processing for this Node2D to receive _input events,
	# including those propagated from its Control children (like MapDisplay).
	set_process_input(true)
	# Instantiate the map renderer
	# Ensure the MapDisplay TextureRect scales its texture nicely
	if map_display:
		map_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		print("Main: map_display found and stretch_mode set.") # DEBUG
		# Explicitly set texture filter for smoother scaling.
		map_display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

		# Create a container for convoy labels as a child of MapDisplay
		_convoy_label_container = Node2D.new()
		_convoy_label_container.name = "ConvoyLabelContainer"
		map_display.add_child(_convoy_label_container)
		
		_settlement_label_container = Node2D.new() # Create settlement label container
		_settlement_label_container.name = "SettlementLabelContainer"
		map_display.add_child(_settlement_label_container) # Add it as a child
		
		print("Main: ConvoyLabelContainer added to MapDisplay.")
		
		# Attempt to get the default theme font for Label nodes
		_default_theme_label_font = map_display.get_theme_font("font", "Label")
		if _default_theme_label_font:
			print("Main: Successfully retrieved theme font for Label: ", _default_theme_label_font.resource_path if _default_theme_label_font.resource_path else "Built-in font")
		else:
			print("Main: No specific theme font found for 'Label'. Labels will use engine default or font set in LabelSettings.")

	# Setup LabelSettings for convoy labels
	_label_settings = LabelSettings.new()
	_label_settings.font = _default_theme_label_font # Use the retrieved theme font, or null if none found
	# _label_settings.font_size = BASE_CONVOY_TITLE_FONT_SIZE # Base size, will be overridden dynamically
	_label_settings.font_color = Color.WHITE
	_label_settings.outline_size = 6 # Increased from 4 for better readability
	_label_settings.outline_color = Color.BLACK
	
	# Setup LabelSettings for settlement labels (drawn on image)
	_settlement_label_settings = LabelSettings.new() # Corrected variable name
	# _settlement_label_settings.font_size = BASE_SETTLEMENT_FONT_SIZE # Base size, will be overridden dynamically
	_settlement_label_settings.font_color = Color.WHITE # Ensure color is set
	_settlement_label_settings.outline_size = 3 # Adjust as needed
	_settlement_label_settings.outline_color = Color.BLACK


	# --- Load the JSON data ---
	var file_path = "res://foo.json"
	var file = FileAccess.open(file_path, FileAccess.READ)

	var err_code = FileAccess.get_open_error()
	if err_code != OK:
		printerr("Error opening map json file: ", file_path)
		printerr("FileAccess error code: ", err_code) # DEBUG
		return

	print("Main: Successfully opened foo.json.") # DEBUG
	var json_string = file.get_as_text()
	file.close()

	var json_data = JSON.parse_string(json_string)

	if json_data == null:
		printerr("Error parsing JSON map data from: ", file_path)
		printerr("JSON string was: ", json_string) # DEBUG
		return

	print("Main: Successfully parsed foo.json.") # DEBUG
	# --- Extract tile data ---
	# Ensure the JSON structure has a "tiles" key containing an array
	if not json_data is Dictionary or not json_data.has("tiles"):
		printerr("JSON data does not contain a 'tiles' key.")
		printerr("Parsed JSON data: ", json_data) # DEBUG
		return

	map_tiles = json_data.get("tiles", []) # Assign to the class member
	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		printerr("Map tiles data is empty or invalid.")
		printerr("Extracted map_tiles: ", map_tiles) # DEBUG
		map_tiles = [] # Ensure it's empty if invalid
		return
	
	# Populate _all_settlement_data from map_tiles
	_all_settlement_data.clear() 
	for y_idx in range(map_tiles.size()):
		var row = map_tiles[y_idx]
		if not row is Array: continue
		for x_idx in range(row.size()):
			var tile_data = row[x_idx]
			if tile_data is Dictionary and tile_data.has("settlements"):
				var settlements_on_tile = tile_data.get("settlements", [])
				if settlements_on_tile is Array:
					for settlement_entry in settlements_on_tile:
						if settlement_entry is Dictionary and settlement_entry.has("name"):
							var settlement_info_for_render = settlement_entry.duplicate() 
							settlement_info_for_render["x"] = x_idx # Ensure we use tile's x for rendering
							settlement_info_for_render["y"] = y_idx # Ensure we use tile's y for rendering
							_all_settlement_data.append(settlement_info_for_render)
							# print("Main: Loaded settlement for render: %s at tile (%s, %s)" % [settlement_info_for_render.get("name"), x_idx, y_idx]) # DEBUG

	# Initial map render and display
	map_renderer = MapRenderer.new() # Initialize the class member here

	_update_map_display()

	# Connect to the viewport's size_changed signal to re-render on window resize
	get_viewport().connect("size_changed", Callable(self, "_on_viewport_size_changed"))
	
	print("Main: Attempting to connect to APICallsInstance signals.") # DEBUG
	# Connect to the APICalls signal for convoy data
	if api_calls_node:
		print("Main: api_calls_node found.") # DEBUG
		if api_calls_node.has_signal("convoy_data_received"):
			api_calls_node.convoy_data_received.connect(_on_convoy_data_received)
			print("Main: Successfully connected to APICalls.convoy_data_received signal.")
		else:
			printerr("Main: APICalls node does not have 'convoy_data_received' signal.")
			printerr("Main: api_calls_node is: ", api_calls_node) # DEBUG
	else:
		printerr("Main: APICalls node not found at the specified path. Cannot connect signal.")

	# Setup and start the refresh timer
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_INTERVAL_SECONDS
	_refresh_timer.one_shot = false # Make it repeat
	_refresh_timer.timeout.connect(_on_refresh_timer_timeout)
	add_child(_refresh_timer) # Add the timer to the scene tree so it processes
	_refresh_timer.start()

	# Setup and start the visual update timer for animations like throbbing
	_visual_update_timer = Timer.new()
	_visual_update_timer.wait_time = VISUAL_UPDATE_INTERVAL_SECONDS
	_visual_update_timer.one_shot = false # Make it repeat

	# Setup the refresh notification label
	_refresh_notification_label = Label.new()
	_refresh_notification_label.text = "Data Refreshed!"
	# Basic styling - you can customize this further
	_refresh_notification_label.add_theme_font_size_override("font_size", 24)
	_refresh_notification_label.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	_refresh_notification_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_refresh_notification_label.add_theme_constant_override("outline_size", 2)
	_refresh_notification_label.modulate.a = 0.0 # Start invisible
	_refresh_notification_label.name = "RefreshNotificationLabel"
	add_child(_refresh_notification_label) # Add as a direct child of this Node2D
	_update_refresh_notification_position() # Set initial position

	_visual_update_timer.timeout.connect(_on_visual_update_timer_timeout)
	add_child(_visual_update_timer)
	_visual_update_timer.start()
	print("Main: Visual update timer started for every %s seconds." % VISUAL_UPDATE_INTERVAL_SECONDS)
	print("Main: Convoy data refresh timer started for every %s seconds." % REFRESH_INTERVAL_SECONDS)

func _on_viewport_size_changed():
	# This function will be called whenever the window size changes
	# print("Viewport size changed, re-rendering map.") # Removed for cleaner log
	if is_instance_valid(_refresh_notification_label):
		_update_refresh_notification_position()
	_update_map_display()

func _update_map_display():
	print("Main: _update_map_display() called.") # DEBUG
	if map_tiles.is_empty():
		printerr("Cannot update map display: map_tiles is empty.")
		return
	if not map_renderer:
		printerr("Cannot update map display: map_renderer is not initialized.")
		return

	print("Main: map_tiles count: ", map_tiles.size(), " (first row count: ", str(map_tiles[0].size()) if not map_tiles.is_empty() and map_tiles[0] is Array else "N/A", ")") # DEBUG

	# --- Render the map ---
	# Get the current viewport size to pass to the renderer
	var current_viewport_size = get_viewport().get_visible_rect().size


	# Call render_map with all parameters, using defaults for highlights/lowlights for now
	print("Main: Calling render_map with _current_hover_info: ", _current_hover_info) # DEBUG
	# You can pass actual highlight/lowlight data here if you have it.
	var map_texture: ImageTexture = map_renderer.render_map(
		map_tiles,
		[], # highlights
		[], # lowlights
		MapRenderer.DEFAULT_HIGHLIGHT_OUTLINE_COLOR,
		MapRenderer.DEFAULT_LOWLIGHT_INLINE_COLOR,
		current_viewport_size, # Viewport size
		_all_convoy_data,      # Pass the convoy data
		_throb_phase,          # Pass the current throb phase
		_convoy_id_to_color_map, # Pass the color map <-- Added comma here
		_current_hover_info  # Pass hover info here
	)
	print("Main: map_renderer.render_map call completed.") # DEBUG

	# --- Display the map ---
	if map_texture:
		print("Main: map_texture is valid. Size: ", map_texture.get_size(), " Format: ", map_texture.get_image().get_format() if map_texture.get_image() else "N/A") # DEBUG
		# Generate mipmaps for the texture if the TextureRect's filter uses them.
		# This improves quality when the texture is scaled down.
		if map_display and (map_display.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS or \
						   map_display.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS):
			var img := map_texture.get_image()
			if img: # Ensure image is valid
				print("Main: Generating mipmaps for map texture.") # DEBUG
				img.generate_mipmaps() # This modifies the image in-place; ImageTexture will update.
		map_display.texture = map_texture
		# No longer need to set map_display.set_size here, stretch_mode handles it.
		print("Main: Map (re)rendered and displayed on map_display node.") # DEBUG
	else:
		printerr("Failed to render map texture.")
	
	# Update labels based on hover state
	_update_hover_labels()



func _on_convoy_data_received(data: Variant) -> void:
	print("Main: Received convoy data from APICalls.gd!")
	
	if data is Array:
		_all_convoy_data = data
		if not data.is_empty():
			print("Main: Stored %s convoy objects. First one: " % data.size())
			print(data[0]) # Print only the first convoy object for brevity
		else:
			print("Main: Received an empty list of convoys.")
	elif data is Dictionary and data.has("results") and data["results"] is Array: # Common API pattern
		_all_convoy_data = data["results"]
		print("Main: Stored %s convoy objects from 'results' key." % _all_convoy_data.size())
	else:
		_all_convoy_data = [] # Clear if data is not in expected array format
		printerr("Main: Received convoy data is not an array or recognized structure. Clearing stored convoy data. Data: ", data)

	# Update convoy ID to color mapping
	for convoy_item in _all_convoy_data:
		if convoy_item is Dictionary:
			var convoy_id = convoy_item.get("convoy_id")
			if convoy_id and not convoy_id.is_empty(): # Ensure convoy_id is valid
				if not _convoy_id_to_color_map.has(convoy_id):
					# This convoy ID is new, assign it the next available color
					_last_assigned_color_idx = (_last_assigned_color_idx + 1) % PREDEFINED_CONVOY_COLORS.size()
					_convoy_id_to_color_map[convoy_id] = PREDEFINED_CONVOY_COLORS[_last_assigned_color_idx]

	# Re-render the map with the new convoy data
	_update_map_display()

func _on_refresh_timer_timeout() -> void:
	print("Main: Refresh timer timeout. Requesting updated convoy data...")
	if api_calls_node:
		api_calls_node.get_all_in_transit_convoys()
	else:
		printerr("Main: Cannot refresh convoy data, api_calls_node is not valid.")
	
	# Show and fade the notification label
	if is_instance_valid(_refresh_notification_label):
		_refresh_notification_label.text = "Data Refreshed!" # Or "Refreshing data..."
		_refresh_notification_label.modulate.a = 1.0 # Make it fully visible
		_update_refresh_notification_position() # Reposition in case text length changed

		# Kill any previous fade tween for this label
		if _refresh_notification_label.has_meta("fade_tween"):
			var old_tween = _refresh_notification_label.get_meta("fade_tween")
			if is_instance_valid(old_tween) and old_tween.is_valid():
				old_tween.kill()

		var new_fade_tween = create_tween()
		_refresh_notification_label.set_meta("fade_tween", new_fade_tween)
		new_fade_tween.tween_interval(2.0) # Stay visible for 2 seconds
		new_fade_tween.tween_property(_refresh_notification_label, "modulate:a", 0.0, 1.0) # Fade out over 1 second
		printerr("Main: Cannot refresh convoy data, api_calls_node is not valid.")

func _on_visual_update_timer_timeout() -> void:
	# Update throb phase for a 1-second cycle
	# VISUAL_UPDATE_INTERVAL_SECONDS is how much phase advances per timer tick.
	# To complete a full cycle (0 to 1) in 1 second, the increment should be VISUAL_UPDATE_INTERVAL_SECONDS / 1.0.
	_throb_phase += VISUAL_UPDATE_INTERVAL_SECONDS 
	_throb_phase = fmod(_throb_phase, 1.0) # Wrap around 1.0

	_update_map_display() # Re-render the map with the new throb phase

func _update_hover_labels():
	# Clear all existing hover labels
	if is_instance_valid(_convoy_label_container):
		for child in _convoy_label_container.get_children():
			child.queue_free()
	if is_instance_valid(_settlement_label_container):
		for child in _settlement_label_container.get_children():
			child.queue_free()

	if not map_display or not is_instance_valid(map_display.texture):
		return # Cannot position labels without a map texture

	# Check if we are hovering over a settlement
	if _current_hover_info.get("type") == "settlement":
		var hovered_coords = _current_hover_info.get("coords") # Expected Vector2i
		if hovered_coords != null and hovered_coords.x >= 0 and hovered_coords.y >= 0 and \
		   hovered_coords.y < map_tiles.size() and hovered_coords.x < map_tiles[hovered_coords.y].size():
			
			var tile_data = map_tiles[hovered_coords.y][hovered_coords.x]
			if tile_data is Dictionary and tile_data.has("settlements"):
				var settlements_on_tile = tile_data.get("settlements", [])
				if settlements_on_tile is Array and not settlements_on_tile.is_empty():
					# Assuming the first settlement on the tile is the one to label
					var settlement_data = settlements_on_tile[0]
					# We need the settlement_info_for_render format which includes x, y tile coords
					var settlement_info_for_render = settlement_data.duplicate()
					settlement_info_for_render["x"] = hovered_coords.x
					settlement_info_for_render["y"] = hovered_coords.y
					_draw_single_settlement_label(settlement_info_for_render)

	# Check if we are hovering over a convoy
	elif _current_hover_info.get("type") == "convoy":
		var hovered_convoy_id = _current_hover_info.get("id")
		if hovered_convoy_id != null:
			for convoy_data in _all_convoy_data:
				if convoy_data is Dictionary and convoy_data.get("convoy_id") == hovered_convoy_id:
					_draw_single_convoy_label(convoy_data)
					break # Found the hovered convoy, no need to check others

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
	# if not _current_hover_info.get("type") == "convoy": # Or some other logic
	#    # Clear existing labels if not hovering over a convoy, or manage visibility
	#    for child in _convoy_label_container.get_children():
	#        child.queue_free() # or child.visible = false
	#    return
	# else:
	#    # Logic to show only the hovered convoy's label
	#    pass


	# This function is now deprecated for hover labels.
	# The logic has been moved to _draw_single_convoy_label and _update_hover_labels.

	if not is_instance_valid(_convoy_label_container):
		printerr("Main: ConvoyLabelContainer is not valid. Cannot update labels.")
		return

	# Clear existing labels
	for child in _convoy_label_container.get_children():
		child.queue_free()

	if not map_display or not is_instance_valid(map_display.texture):
		# print("Main: No map texture on MapDisplay, skipping label update.") # Can be noisy
		return

	if _all_convoy_data.is_empty():
		# print("Main: No convoy data, skipping label update.") # Can be noisy
		return

	var map_texture: ImageTexture = map_display.texture
	var map_texture_size: Vector2 = map_texture.get_size()
	var map_display_rect_size: Vector2 = map_display.size

	if map_texture_size.x == 0 or map_texture_size.y == 0:
		printerr("Main: Map texture size is zero, cannot calculate label positions.")
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
		printerr("Main: map_tiles data is invalid, cannot calculate label positions accurately.")
		return
	var map_image_cols: int = map_tiles[0].size()
	var map_image_rows: int = map_tiles.size()
	var actual_tile_width_on_texture: float = map_texture_size.x / float(map_image_cols)
	var actual_tile_height_on_texture: float = map_texture_size.y / float(map_image_rows)

	var placed_label_rects: Array[Rect2] = [] # To store rects of already placed labels for collision avoidance

	for convoy_idx in range(_all_convoy_data.size()):
		var convoy_data = _all_convoy_data[convoy_idx]
		var convoy_name: String = convoy_data.get("convoy_name", "N/A")
		var journey_data: Dictionary = convoy_data.get("journey", {})
		var progress: float = journey_data.get("progress", 0.0)
		var length: float = journey_data.get("length", 0.0)
		var convoy_map_x: float = convoy_data.get("x", 0.0)
		var convoy_map_y: float = convoy_data.get("y", 0.0)

		var progress_percentage_str: String = "N/A"
		if length > 0.001: # Avoid division by zero or tiny lengths
			var percentage: float = (progress / length) * 100.0
			progress_percentage_str = "%.1f%%" % percentage # Format to one decimal place
		
		var label_text: String = "%s (%s)" % [convoy_name, progress_percentage_str]
		
		# Get the persistent color for this convoy
		var current_convoy_id = convoy_data.get("convoy_id")
		var unique_convoy_color: Color = _convoy_id_to_color_map.get(current_convoy_id, Color.GRAY) # Fallback to gray if ID somehow not in map

		var label := Label.new()
		label.text = label_text
		label.label_settings = _label_settings
		
		# Wait for label to get its size after text and settings are applied
		# This is a bit of a workaround; ideally, we'd force an update or use call_deferred.
		# For now, we'll add it to the tree, get size, then set pivot.
		_convoy_label_container.add_child(label) # Temporarily add to get size
		var label_min_size: Vector2 = label.get_minimum_size()
		label.pivot_offset = Vector2(0, label_min_size.y / 2.0) # Pivot at left-middle
		_convoy_label_container.remove_child(label) # Remove before final positioning

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
		color_indicator.position.y = (convoy_center_on_texture_y * actual_scale + offset_y) - ((BASE_COLOR_INDICATOR_SIZE * actual_scale) / 2.0) # Vertically center indicator with convoy

		# Anti-collision: check against already placed labels and shift down if needed
		# For collision, consider the combined rect of indicator + label
		var combined_item_top_left_x: float = label.position.x - label.pivot_offset.x # Label's actual left edge
		var combined_item_top_left_y: float = min(color_indicator.position.y, label.position.y - label.pivot_offset.y)
		var combined_item_width: float = (color_indicator.position.x + (BASE_COLOR_INDICATOR_SIZE * actual_scale)) - combined_item_top_left_x
		var combined_item_height: float = max(color_indicator.position.y + (BASE_COLOR_INDICATOR_SIZE * actual_scale), label.position.y - label.pivot_offset.y + label_min_size.y) - combined_item_top_left_y
		var current_item_rect := Rect2(combined_item_top_left_x, combined_item_top_left_y, combined_item_width, combined_item_height)
		
		for attempt in range(10): # Max 10 attempts to avoid overlap
			var collides: bool = false
			for placed_rect in placed_label_rects:
				if current_item_rect.intersects(placed_rect, true): # Use true for pixel-perfect intersection if needed, though Rect2 usually fine
					collides = true
					# Shift both indicator and label down
					color_indicator.position.y += LABEL_ANTI_COLLISION_Y_SHIFT + combined_item_height * 0.1
					label.position.y += LABEL_ANTI_COLLISION_Y_SHIFT + label_min_size.y * 0.1 # Shift down by a bit more than just the shift amount
					combined_item_top_left_y = min(color_indicator.position.y, label.position.y - label.pivot_offset.y)
					current_item_rect = Rect2(combined_item_top_left_x, combined_item_top_left_y, combined_item_width, combined_item_height)
					break # Re-check against all placed rects with new position
			if not collides:
				break # Found a non-colliding position
		
		placed_label_rects.append(current_item_rect) # Add final rect for next item's collision check
		# Add label first, then indicator, so indicator is drawn "on top" if they overlap (though they shouldn't much)
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
		printerr("Main: SettlementLabelContainer is not valid. Cannot update labels.")
		return

	# Clear existing settlement labels
	for child in _settlement_label_container.get_children():
		child.queue_free()

	if not map_display or not is_instance_valid(map_display.texture):
		# print("Main: No map texture on MapDisplay, skipping settlement label update.")
		return

	if _all_settlement_data.is_empty():
		# print("Main: No settlement data, skipping settlement label update.")
		return

	var map_texture_size: Vector2 = map_display.texture.get_size()
	var map_display_rect_size: Vector2 = map_display.size

	if map_texture_size.x == 0 or map_texture_size.y == 0:
		printerr("Main: Map texture size is zero, cannot calculate settlement label positions.")
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
		printerr("Main: map_tiles data is invalid for settlement labels.")
		return
	var map_image_cols: int = map_tiles[0].size()
	var map_image_rows: int = map_tiles.size()
	var actual_tile_width_on_texture: float = map_texture_size.x / float(map_image_cols)
	var actual_tile_height_on_texture: float = map_texture_size.y / float(map_image_rows)

	for settlement_info in _all_settlement_data:
		var settlement_name_local: String = settlement_info.get("name", "N/A")
		var tile_x: int = settlement_info.get("x", -1) # tile_x from main.gd's processing
		var tile_y: int = settlement_info.get("y", -1) # tile_y from main.gd's processing
		if tile_x < 0 or tile_y < 0: continue # Ensure valid tile coordinates
		if settlement_name_local == "N/A": continue # Skip if name is not available

		var label := Label.new()
		label.text = name
		label.label_settings = _settlement_label_settings # Use pre-configured LabelSettings
		
		_settlement_label_container.add_child(label) # Add to tree to get size
		var label_size: Vector2 = label.get_minimum_size()
		_settlement_label_container.remove_child(label) # Remove for final positioning

		var tile_center_tex_x: float = (float(tile_x) + 0.5) * actual_tile_width_on_texture
		var tile_center_tex_y: float = (float(tile_y) + 0.5) * actual_tile_height_on_texture
		label.position = Vector2(tile_center_tex_x * actual_scale + offset_x - (label_size.x / 2.0), tile_center_tex_y * actual_scale + offset_y - (label_size.y / 2.0))
		_settlement_label_container.add_child(label)

# New helper function to draw a single convoy label
func _draw_single_convoy_label(convoy_data: Dictionary):
	if not is_instance_valid(_convoy_label_container):
		printerr("Main: ConvoyLabelContainer is not valid. Cannot draw single convoy label.")
		return
	if not map_display or not is_instance_valid(map_display.texture):
		return # Cannot position labels without a map texture

	var map_texture: ImageTexture = map_display.texture
	var map_texture_size: Vector2 = map_texture.get_size()
	var map_display_rect_size: Vector2 = map_display.size

	if map_texture_size.x == 0 or map_texture_size.y == 0:
		printerr("Main: Map texture size is zero, cannot calculate single convoy label position.")
		return

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
		printerr("Main: map_tiles data is invalid, cannot calculate single convoy label position accurately.")
		return
	var map_image_cols: int = map_tiles[0].size()
	var map_image_rows: int = map_tiles.size()
	var actual_tile_width_on_texture: float = map_texture_size.x / float(map_image_cols)
	var actual_tile_height_on_texture: float = map_texture_size.y / float(map_image_rows)

	# Calculate font rendering scale based on how map tiles are scaled
	var effective_tile_size_on_texture: float = min(actual_tile_width_on_texture, actual_tile_height_on_texture)
	var base_linear_font_scale: float = 1.0
	if FONT_SCALING_BASE_TILE_SIZE > 0.001: # Avoid division by zero
		base_linear_font_scale = effective_tile_size_on_texture / FONT_SCALING_BASE_TILE_SIZE
	
	var font_render_scale: float = pow(base_linear_font_scale, FONT_SCALING_EXPONENT)

	var current_convoy_title_font_size: int = max(MIN_FONT_SIZE, roundi(BASE_CONVOY_TITLE_FONT_SIZE * font_render_scale))
	# var current_convoy_detail_font_size: int = max(MIN_FONT_SIZE, roundi(BASE_CONVOY_DETAIL_FONT_SIZE * font_render_scale)) # No longer needed for label text
	
	var current_horizontal_offset: float = BASE_HORIZONTAL_LABEL_OFFSET_FROM_CENTER * actual_scale
	var current_color_indicator_size: float = BASE_COLOR_INDICATOR_SIZE * actual_scale
	var current_color_indicator_padding: float = BASE_COLOR_INDICATOR_PADDING * actual_scale

	var convoy_map_x: float = convoy_data.get("x", 0.0)
	var convoy_map_y: float = convoy_data.get("y", 0.0)

	# Extract additional details
	var efficiency: float = convoy_data.get("efficiency", 0.0)
	var top_speed: float = convoy_data.get("top_speed", 0.0)
	var offroad_capability: float = convoy_data.get("offroad_capability", 0.0)
	var convoy_name: String = convoy_data.get("convoy_name", "N/A") # Moved for clarity
	var journey_data: Dictionary = convoy_data.get("journey", {}) # Moved for clarity
	var progress: float = journey_data.get("progress", 0.0) # Moved for clarity
	
	# Format ETA
	var eta_raw_string: String = journey_data.get("eta", "N/A")
	var departure_raw_string: String = journey_data.get("departure_time", "N/A")
	var formatted_eta: String = "N/A"
	if eta_raw_string != "N/A" and not eta_raw_string.is_empty() and \
	   departure_raw_string != "N/A" and not departure_raw_string.is_empty():

		var eta_datetime_local: Dictionary = {}
		var departure_datetime_local: Dictionary = {}

		# Helper function to manually parse ISO string to a UTC datetime dict
		var parse_iso_to_utc_dict = func(iso_string: String) -> Dictionary:
			var components = {"year": 0, "month": 0, "day": 0, "hour": 0, "minute": 0, "second": 0}
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

		var eta_utc_dict: Dictionary = parse_iso_to_utc_dict.call(eta_raw_string)
		var departure_utc_dict: Dictionary = parse_iso_to_utc_dict.call(departure_raw_string)

		# Calculate local time offset from UTC using system time
		var local_offset_seconds: int = 0
		var current_local_components: Dictionary = Time.get_datetime_dict_from_system(false) # false for local
		var current_utc_components: Dictionary = Time.get_datetime_dict_from_system(true)   # true for UTC
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
			var eta_unix_time_utc: int = Time.get_unix_time_from_datetime_dict(eta_utc_dict) # Input dict is UTC, no second arg needed
			if eta_unix_time_utc > 0:
				var eta_unix_time_local: int = eta_unix_time_utc + local_offset_seconds
				eta_datetime_local = Time.get_datetime_dict_from_unix_time(eta_unix_time_local) # Get dict from local unix time
		
		if not departure_utc_dict.is_empty():
			# Convert UTC dict to UTC Unix timestamp
			var departure_unix_time_utc: int = Time.get_unix_time_from_datetime_dict(departure_utc_dict) # Input dict is UTC, no second arg needed
			if departure_unix_time_utc > 0:
				var departure_unix_time_local: int = departure_unix_time_utc + local_offset_seconds
				departure_datetime_local = Time.get_datetime_dict_from_unix_time(departure_unix_time_local) # Get dict from local unix time

		if not eta_datetime_local.is_empty() and not departure_datetime_local.is_empty():
			var eta_hour_24: int = eta_datetime_local.hour
			var am_pm_str: String = "AM"
			var eta_hour_12: int = eta_hour_24
			
			if eta_hour_24 >= 12:
				am_pm_str = "PM"
				if eta_hour_24 > 12:
					eta_hour_12 = eta_hour_24 - 12
			if eta_hour_12 == 0: # Midnight case
				eta_hour_12 = 12
				
			var eta_hour_str = "%d" % eta_hour_12 # No zero-padding for 12-hour format typically, unless desired
			var eta_minute_str = "%02d" % eta_datetime_local.minute

			# Compare based on local dates
			var years_match: bool = eta_datetime_local.has("year") and \
									departure_datetime_local.has("year") and \
									eta_datetime_local.year == departure_datetime_local.year
			var months_match: bool = eta_datetime_local.has("month") and \
									 departure_datetime_local.has("month") and \
									 eta_datetime_local.month == departure_datetime_local.month
			var days_match: bool = eta_datetime_local.has("day") and \
								   departure_datetime_local.has("day") and \
								   eta_datetime_local.day == departure_datetime_local.day
			
			if years_match and months_match and days_match:
				formatted_eta = "Today, %s:%s %s" % [eta_hour_str, eta_minute_str, am_pm_str]
			else:
				var month_name_str: String = "???" # Fallback month name
				if eta_datetime_local.has("month") and eta_datetime_local.month >= 1 and eta_datetime_local.month <= 12:
					month_name_str = ABBREVIATED_MONTH_NAMES[eta_datetime_local.month]
				var day_to_display = eta_datetime_local.get("day", "??")
				formatted_eta = "%s %s, %s:%s %s" % [month_name_str, day_to_display, eta_hour_str, eta_minute_str, am_pm_str]
		else: # Fallback if parsing failed
			# Simpler fallback if proper parsing fails, this won't be timezone aware
			if eta_raw_string.length() >= 16:
				formatted_eta = eta_raw_string.substr(0, 16).replace("T", " ") # YYYY-MM-DD HH:MM
			else:
				formatted_eta = eta_raw_string # Or just the raw string if too short or completely unparsable
			
	var progress_percentage_str: String = "N/A"
	var length: float = journey_data.get("length", 0.0) # Moved for clarity
	if length > 0.001: # Avoid division by zero or tiny lengths
		var percentage: float = (progress / length) * 100.0
		progress_percentage_str = "%.1f%%" % percentage # Format to one decimal place
	
	# Use BBCode for smaller detail font size
	var label_text: String = "%s (%s)\n%s %.1f | %s %.1f | %s %.1f\nETA: %s" % [
		convoy_name, progress_percentage_str, CONVOY_STAT_EMOJIS.get("efficiency", ""), efficiency, CONVOY_STAT_EMOJIS.get("top_speed", ""), top_speed, CONVOY_STAT_EMOJIS.get("offroad_capability", ""), offroad_capability, formatted_eta
	]
	
	# Dynamically set the font size on the LabelSettings resource itself
	_label_settings.font_size = current_convoy_title_font_size

	# Get the persistent color for this convoy
	var current_convoy_id = convoy_data.get("convoy_id")
	var unique_convoy_color: Color = _convoy_id_to_color_map.get(current_convoy_id, Color.GRAY) # Fallback to gray

	var label := Label.new()
	print("DEBUG: In _draw_single_convoy_label - label object is: ", label, ", class is: ", label.get_class()) # DEBUG
	# label.bbcode_enabled = true # Enable BBCode processing
	label.set("bbcode_enabled", true) # Alternative way to set the property
	label.text = label_text
	label.label_settings = _label_settings # Assign the LabelSettings with the updated font_size
	
	_convoy_label_container.add_child(label) # Temporarily add to get size
	var label_min_size: Vector2 = label.get_minimum_size()
	label.pivot_offset = Vector2(0, label_min_size.y / 2.0) # Pivot at left-middle
	_convoy_label_container.remove_child(label) # Remove before final positioning
	# The line label.add_theme_font_size_override is no longer needed as LabelSettings.font_size controls the base.

	# Calculate convoy's center pixel position on the unscaled map texture
	var convoy_center_on_texture_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_texture
	var convoy_center_on_texture_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_texture

	# Calculate convoy's center Y on the MapDisplay (scaled and offset)
	var convoy_center_display_y = convoy_center_on_texture_y * actual_scale + offset_y

	# Position the label's horizontal center to the right of the convoy icon.
	# Position the label's vertical center aligned with the convoy's vertical center.
	label.position.x = (convoy_center_on_texture_x * actual_scale + offset_x) + current_horizontal_offset
	label.position.y = convoy_center_display_y # Align vertical centers due to pivot_offset

	# Create and configure the color indicator
	var color_indicator := ColorRect.new() # Typo: Corrected := to :=
	color_indicator.color = unique_convoy_color
	color_indicator.size = Vector2(current_color_indicator_size, current_color_indicator_size)
	
	# Position the color indicator to the right of the label, and vertically centered with the label.
	color_indicator.position.x = label.position.x + label_min_size.x + current_color_indicator_padding
	color_indicator.position.y = label.position.y - (current_color_indicator_size / 2.0) # Vertically center indicator with the label

	# Add label first, then indicator, so indicator is drawn "on top" if they overlap
	_convoy_label_container.add_child(label)
	_convoy_label_container.add_child(color_indicator)

# New helper function to draw a single settlement label
func _draw_single_settlement_label(settlement_info_for_render: Dictionary):
	# This function uses the logic from the old _update_settlement_labels but for a single settlement
	if not is_instance_valid(_settlement_label_container):
		printerr("Main: SettlementLabelContainer is not valid. Cannot draw single settlement label.")
		return
	if not map_display or not is_instance_valid(map_display.texture):
		return # Cannot position labels without a map texture

	var map_texture_size: Vector2 = map_display.texture.get_size()
	var map_display_rect_size: Vector2 = map_display.size

	if map_texture_size.x == 0 or map_texture_size.y == 0:
		printerr("Main: Map texture size is zero, cannot calculate single settlement label position.")
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
		printerr("Main: map_tiles data is invalid for single settlement label.")
		return
	var map_image_cols: int = map_tiles[0].size()
	var map_image_rows: int = map_tiles.size()
	var actual_tile_width_on_texture: float = map_texture_size.x / float(map_image_cols)
	var actual_tile_height_on_texture: float = map_texture_size.y / float(map_image_rows)

	# Calculate font rendering scale based on how map tiles are scaled
	var effective_tile_size_on_texture: float = min(actual_tile_width_on_texture, actual_tile_height_on_texture)
	var base_linear_font_scale: float = 1.0
	if FONT_SCALING_BASE_TILE_SIZE > 0.001: # Avoid division by zero
		base_linear_font_scale = effective_tile_size_on_texture / FONT_SCALING_BASE_TILE_SIZE
		
	var font_render_scale: float = pow(base_linear_font_scale, FONT_SCALING_EXPONENT)
		
	var current_settlement_font_size: int = max(MIN_FONT_SIZE, roundi(BASE_SETTLEMENT_FONT_SIZE * font_render_scale))
	var current_settlement_offset_above_center: float = BASE_SETTLEMENT_OFFSET_ABOVE_TILE_CENTER * actual_scale

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

	var settlement_name_local: String = settlement_info_for_render.get("name", "N/A")
	var tile_x: int = settlement_info_for_render.get("x", -1)
	var tile_y: int = settlement_info_for_render.get("y", -1)
	if tile_x < 0 or tile_y < 0: return  # Should not happen if called correctly from _update_hover_labels
	if settlement_name_local == "N/A": return # Skip if name is not available

	var settlement_type = settlement_info_for_render.get("sett_type", "") # Assuming sett_type is available in settlement_info_for_render
	var settlement_emoji = SETTLEMENT_EMOJIS.get(settlement_type, "") # Get emoji, fallback to empty string
	var label := Label.new()
	label.text = settlement_emoji + " " + settlement_name_local if not settlement_emoji.is_empty() else settlement_name_local # Add emoji if found
	label.label_settings = _settlement_label_settings # Assign the LabelSettings with the updated font_size
	
	_settlement_label_container.add_child(label) # Add to tree to get size
	var label_size: Vector2 = label.get_minimum_size()
	_settlement_label_container.remove_child(label) # Remove for final positioning
	# The line label.add_theme_font_size_override is no longer needed.

	var tile_center_tex_x: float = (float(tile_x) + 0.5) * actual_tile_width_on_texture
	var tile_center_tex_y: float = (float(tile_y) + 0.5) * actual_tile_height_on_texture
	
	var tile_center_display_y = tile_center_tex_y * actual_scale + offset_y
	# Position the label's TOP edge 'current_settlement_offset_above_center' pixels ABOVE the tile's center, after accounting for label's own height.
	label.position = Vector2(tile_center_tex_x * actual_scale + offset_x - (label_size.x / 2.0), tile_center_display_y - label_size.y - current_settlement_offset_above_center)
	_settlement_label_container.add_child(label)



func _input(event: InputEvent) -> void: # Renamed from _gui_input
	print("Main: _gui_input event: ", event) # DEBUG - Can be very noisy
	if not map_display or not is_instance_valid(map_display.texture):
		return


	if event is InputEventMouseMotion:
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
		# print("Main: Mouse on texture: ", mouse_on_texture_x, ", ", mouse_on_texture_y) # DEBUG

		var new_hover_info: Dictionary = {}
		var found_hover_element: bool = false

		if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
			return # Cannot determine tile dimensions

		var map_cols: int = map_tiles[0].size()
		var map_rows: int = map_tiles.size()
		var actual_tile_width_on_texture: float = map_texture_size.x / float(map_cols)
		var actual_tile_height_on_texture: float = map_texture_size.y / float(map_rows)

		# 1. Check for Convoy Hover (prioritize so convoy label shows if on a settlement tile)
		if not _all_convoy_data.is_empty():
			for convoy_data in _all_convoy_data:
				if not convoy_data is Dictionary: continue

				var convoy_map_x: float = convoy_data.get("x", -1.0)
				var convoy_map_y: float = convoy_data.get("y", -1.0)
				var convoy_id = convoy_data.get("convoy_id")

				if convoy_map_x >= 0.0 and convoy_map_y >= 0.0 and convoy_id != null: # Ensure consistent spacing and float comparison
					# Calculate convoy's center pixel position on the unscaled map texture
					# For more precise hover, that offset calculation would need to be mirrored or results stored.
					var convoy_center_tex_x: float = (convoy_map_x + 0.5) * actual_tile_width_on_texture
					var convoy_center_tex_y: float = (convoy_map_y + 0.5) * actual_tile_height_on_texture

					var dx = mouse_on_texture_x - convoy_center_tex_x
					var dy = mouse_on_texture_y - convoy_center_tex_y
					var distance_sq = (dx * dx) + (dy * dy)
					# print("Main: Checking convoy hover for: ", convoy_id, " at map(", convoy_map_x, ",", convoy_map_y, ") tex(", convoy_center_tex_x, ",", convoy_center_tex_y, ") mouse_dist_sq: ", distance_sq) # DEBUG

					if distance_sq < CONVOY_HOVER_RADIUS_ON_TEXTURE_SQ:
						new_hover_info = {"type": "convoy", "id": convoy_id}
						found_hover_element = true
						print("Main: Convoy HOVERED: ", new_hover_info) # DEBUG
						break 
		
		# 2. Check for Settlement Hover (if no convoy was hovered)
		if not found_hover_element:
			var closest_settlement_dist_sq: float = SETTLEMENT_HOVER_RADIUS_ON_TEXTURE_SQ + 1.0 # Start greater than radius
			var best_hovered_settlement_coords: Vector2i = Vector2i(-1, -1)

			for settlement_info in _all_settlement_data:
				if not settlement_info is Dictionary: continue
				
				var settlement_tile_x: int = settlement_info.get("x", -1)
				var settlement_tile_y: int = settlement_info.get("y", -1)

				if settlement_tile_x >= 0 and settlement_tile_y >= 0:
					# Calculate settlement's center pixel position on the unscaled map texture
					var settlement_center_tex_x: float = (float(settlement_tile_x) + 0.5) * actual_tile_width_on_texture
					var settlement_center_tex_y: float = (float(settlement_tile_y) + 0.5) * actual_tile_height_on_texture

					var dx_settlement = mouse_on_texture_x - settlement_center_tex_x
					var dy_settlement = mouse_on_texture_y - settlement_center_tex_y
					var distance_sq_settlement = (dx_settlement * dx_settlement) + (dy_settlement * dy_settlement)

					if distance_sq_settlement < SETTLEMENT_HOVER_RADIUS_ON_TEXTURE_SQ:
						if distance_sq_settlement < closest_settlement_dist_sq: # Is this closer than a previously found settlement?
							closest_settlement_dist_sq = distance_sq_settlement
							best_hovered_settlement_coords = Vector2i(settlement_tile_x, settlement_tile_y)
							found_hover_element = true # Mark that we found at least one
			
			if found_hover_element and best_hovered_settlement_coords.x != -1: # Check if a valid settlement was found
				new_hover_info = {
					"type": "settlement",
					"coords": best_hovered_settlement_coords
				}
				print("Main: Settlement HOVERED (closest): ", new_hover_info) # DEBUG


		# Update map if hover state changed
		if new_hover_info != _current_hover_info:
			print("Main: Hover changed! new_hover_info: ", new_hover_info, " _current_hover_info was: ", _current_hover_info) # DEBUG
			_current_hover_info = new_hover_info
			# Update only the hover labels based on the new state
			_update_hover_labels()

func _update_refresh_notification_position():
	if not is_instance_valid(_refresh_notification_label):
		return
	
	var viewport_size = get_viewport_rect().size
	# Ensure the label has its size calculated based on current text and font settings
	var label_size = _refresh_notification_label.get_minimum_size() 
	
	var padding: float = 10.0 # Pixels from the edge
	_refresh_notification_label.position = Vector2(viewport_size.x - label_size.x - padding, viewport_size.y - label_size.y - padding)
