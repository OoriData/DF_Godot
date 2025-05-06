# main.gd
extends Node2D

# Preload the map rendering script
const MapRenderer = preload("res://map_render.gd")
# Reference the node that will display the map
@onready var map_display: TextureRect = $MapDisplay

func _ready():
	# Instantiate the map renderer
	var map_renderer = MapRenderer.new()

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

	var map_tiles: Array = json_data.get("tiles", [])
	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		printerr("Map tiles data is empty or invalid.")
		return

	# --- Render the map ---
	# You can add highlight/lowlight arrays here if needed, e.g.:
	# var highlights = [Vector2i(1, 0)]
	# var lowlights = []
	# var map_texture: ImageTexture = map_renderer.render_map(map_tiles, highlights, lowlights)
	var map_texture: ImageTexture = map_renderer.render_map(map_tiles) # Basic call

	# --- Display the map ---
	if map_texture:
		map_display.texture = map_texture
		print("Map rendered and displayed.")
	else:
		printerr("Failed to render map texture.")
