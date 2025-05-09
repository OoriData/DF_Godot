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
var _all_convoy_data: Array = [] # To store convoy data from APICalls

var _refresh_timer: Timer
const REFRESH_INTERVAL_SECONDS: float = 60.0 # 1 minute
var _visual_update_timer: Timer
const VISUAL_UPDATE_INTERVAL_SECONDS: float = 0.05 # e.g., 20 FPS for visual updates
var _throb_phase: float = 0.0 # Cycles 0.0 to 1.0 for a 1-second throb

var _convoy_label_container: Node2D
var _label_settings: LabelSettings


const HORIZONTAL_LABEL_OFFSET_FROM_CENTER: float = 20.0 # Pixels to offset label to the right of convoy center
const LABEL_ANTI_COLLISION_Y_SHIFT: float = 5.0 # Pixels to shift label down if collision detected
const COLOR_INDICATOR_SIZE: float = 14.0 # Size of the square color indicator (e.g., 80% of font_size 30)
const COLOR_INDICATOR_PADDING: float = 4.0 # Padding between color indicator and text

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

func _ready():
	print("Main: _ready() called.") # DEBUG
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
		print("Main: ConvoyLabelContainer added to MapDisplay.")

	# Setup LabelSettings for convoy labels
	_label_settings = LabelSettings.new()
	# _label_settings.font = load("res://path/to/your/font.ttf") # Optional: load a custom font
	_label_settings.font_size = 24 # Adjust as needed
	_label_settings.font_color = Color.WHITE
	_label_settings.outline_size = 6 # Increased from 4 for better readability
	_label_settings.outline_color = Color.BLACK

	map_renderer = MapRenderer.new() # Initialize the class member
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

	# Initial map render and display
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
	_visual_update_timer.timeout.connect(_on_visual_update_timer_timeout)
	add_child(_visual_update_timer)
	_visual_update_timer.start()
	print("Main: Visual update timer started for every %s seconds." % VISUAL_UPDATE_INTERVAL_SECONDS)
	print("Main: Convoy data refresh timer started for every %s seconds." % REFRESH_INTERVAL_SECONDS)

func _on_viewport_size_changed():
	# This function will be called whenever the window size changes
	# print("Viewport size changed, re-rendering map.") # Removed for cleaner log
	_update_map_display()

func _update_map_display():
	print("Main: _update_map_display() called.") # DEBUG
	if map_tiles.is_empty():
		printerr("Cannot update map display: map_tiles is empty.")
		return
	if not map_renderer:
		printerr("Cannot update map display: map_renderer is not initialized.")
		return

	print("Main: map_tiles count: ", map_tiles.size(), " (first row count: ", map_tiles[0].size() if not map_tiles.is_empty() and map_tiles[0] is Array else "N/A", ")") # DEBUG

	# --- Render the map ---
	# Get the current viewport size to pass to the renderer
	var current_viewport_size = get_viewport().get_visible_rect().size

	# Call render_map with all parameters, using defaults for highlights/lowlights for now
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
		_convoy_id_to_color_map # Pass the color map
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
	
	_update_convoy_labels() # Update labels after map is displayed


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

func _on_visual_update_timer_timeout() -> void:
	# Update throb phase for a 1-second cycle
	# VISUAL_UPDATE_INTERVAL_SECONDS is how much phase advances per timer tick.
	# To complete a full cycle (0 to 1) in 1 second, the increment should be VISUAL_UPDATE_INTERVAL_SECONDS / 1.0.
	_throb_phase += VISUAL_UPDATE_INTERVAL_SECONDS 
	_throb_phase = fmod(_throb_phase, 1.0) # Wrap around 1.0

	_update_map_display() # Re-render the map with the new throb phase
func _update_convoy_labels() -> void:
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
		label.position.x = (convoy_center_on_texture_x * actual_scale + offset_x) + HORIZONTAL_LABEL_OFFSET_FROM_CENTER
		label.position.y = convoy_center_on_texture_y * actual_scale + offset_y

		# Create and configure the color indicator
		var color_indicator := ColorRect.new()
		color_indicator.color = unique_convoy_color
		color_indicator.size = Vector2(COLOR_INDICATOR_SIZE, COLOR_INDICATOR_SIZE)
		# Position the color indicator to the right of the label
		# Note: label.position.x is its pivot (left edge), label_min_size.x is its width
		color_indicator.position.x = label.position.x + label_min_size.x + COLOR_INDICATOR_PADDING
		color_indicator.position.y = (convoy_center_on_texture_y * actual_scale + offset_y) - (COLOR_INDICATOR_SIZE / 2.0) # Vertically center indicator with convoy

		# Anti-collision: check against already placed labels and shift down if needed
		# For collision, consider the combined rect of indicator + label
		var combined_item_top_left_x: float = label.position.x - label.pivot_offset.x # Label's actual left edge
		var combined_item_top_left_y: float = min(color_indicator.position.y, label.position.y - label.pivot_offset.y)
		var combined_item_width: float = (color_indicator.position.x + COLOR_INDICATOR_SIZE) - combined_item_top_left_x
		var combined_item_height: float = max(color_indicator.position.y + COLOR_INDICATOR_SIZE, label.position.y - label.pivot_offset.y + label_min_size.y) - combined_item_top_left_y
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
