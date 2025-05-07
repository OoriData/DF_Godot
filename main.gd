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

func _ready():
	print("Main: _ready() called.") # DEBUG
	# Instantiate the map renderer
	# Ensure the MapDisplay TextureRect scales its texture nicely
	if map_display:
		map_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		print("Main: map_display found and stretch_mode set.") # DEBUG
		# Explicitly set texture filter for smoother scaling.
		map_display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

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
		current_viewport_size,
		_all_convoy_data # Pass the convoy data
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

	# Re-render the map with the new convoy data
	_update_map_display()
