# main.gd
extends Node2D

# Preload the map rendering script
const MapRenderer = preload("res://map_render.gd")
# Reference the node that will display the map
@onready var map_display: TextureRect = $MapDisplay

var map_renderer # Will be initialized in _ready()
var map_tiles: Array = [] # Will hold the loaded tile data

func _ready():
	# Instantiate the map renderer
	# Ensure the MapDisplay TextureRect scales its texture nicely
	if map_display:
		map_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Explicitly set texture filter for smoother scaling.
		map_display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	map_renderer = MapRenderer.new() # Initialize the class member
	# --- Load the JSON data ---
	var file_path = "res://foo.json"
	var file = FileAccess.open(file_path, FileAccess.READ)

	if FileAccess.get_open_error() != OK:
		printerr("Error opening map json file: ", file_path)
		return

	var json_string = file.get_as_text()
	file.close()

	var json_data = JSON.parse_string(json_string)

	if json_data == null:
		printerr("Error parsing JSON map data from: ", file_path)
		return

	# --- Extract tile data ---
	# Ensure the JSON structure has a "tiles" key containing an array
	if not json_data is Dictionary or not json_data.has("tiles"):
		printerr("JSON data does not contain a 'tiles' key.")
		return

	map_tiles = json_data.get("tiles", []) # Assign to the class member
	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		printerr("Map tiles data is empty or invalid.")
		map_tiles = [] # Ensure it's empty if invalid
		return

	# Initial map render and display
	_update_map_display()

	# Connect to the viewport's size_changed signal to re-render on window resize
	get_viewport().connect("size_changed", Callable(self, "_on_viewport_size_changed"))

func _on_viewport_size_changed():
	# This function will be called whenever the window size changes
	# print("Viewport size changed, re-rendering map.") # Removed for cleaner log
	_update_map_display()

func _update_map_display():
	if map_tiles.is_empty():
		printerr("Cannot update map display: map_tiles is empty.")
		return
	if not map_renderer:
		printerr("Cannot update map display: map_renderer is not initialized.")
		return

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
		current_viewport_size
	)

	# --- Display the map ---
	if map_texture:
		# Generate mipmaps for the texture if the TextureRect's filter uses them.
		# This improves quality when the texture is scaled down.
		if map_display and (map_display.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS or \
						   map_display.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS):
			var img := map_texture.get_image()
			if img: # Ensure image is valid
				img.generate_mipmaps() # This modifies the image in-place; ImageTexture will update.
		map_display.texture = map_texture
		# No longer need to set map_display.set_size here, stretch_mode handles it.
		print("Map (re)rendered and displayed.")
	else:
		printerr("Failed to render map texture.")
