# main.gd
@tool
extends Node2D

var terrain_int_to_name = {
	0: "impassable",
	1: "highway",
	2: "road",
	3: "trail",
	4: "desert",
	5: "plains",
	6: "forest",
	7: "swamp",
	8: "mountains",
	9: "near_impassible"
}

var settlement_type_to_name = {
	"town": "town",
	"village": "village",
	"city": "city",
	"city-state": "city-state",
	"dome": "dome",
	"military_base": "military_base",
	"tutorial": "tutorial"
	# Add more as needed
}



# Node references
@onready var sub_viewport = $MapContainer/SubViewport
@onready var game_data_manager = get_node_or_null("/root/GameDataManager")
@onready var map_camera_controller: Node = $MapInteractionManager/MapCameraController
@onready var map_display: TextureRect = $MapContainer/MapDisplay
@onready var map_container: Node2D = $MapContainer
@onready var map_camera: Camera2D = $MapContainer/SubViewport/MapCamera # Reference to the new MapCamera
@onready var ui_manager: Node = $ScreenSpaceUI/UIManagerNode # Corrected path
@onready var detailed_view_toggle: CheckBox = $ScreenSpaceUI/UIManagerNode/DetailedViewToggleCheckbox # Corrected path
@onready var map_interaction_manager: Node = $MapInteractionManager # Path to your MapInteractionManager node
@onready var convoy_visuals_manager: Node = $ConvoyVisualsManager # Adjust path if you place it elsewhere
@onready var game_timers_node: Node = $GameTimersNode # Adjust if necessary
# Reference to the TerrainTileMap (TileMapLayer) node
@onready var terrain_tilemap: TileMapLayer = $MapContainer/SubViewport/TerrainTileMap
# Reference to the MenuManager in GameRoot.tscn

var menu_manager_ref: Control = null

# Data will now be sourced from GameDataManager
var top_nav_bar_container: Control = null # This will hold the container of the nav bar
var map_tiles: Array = []
var _all_settlement_data: Array = []
var _all_convoy_data: Array = [] # This will store data received from GameDataManager
var _convoy_id_to_color_map: Dictionary = {} # This will also be populated from GameDataManager

# Configurable gameplay/UI parameters
## Pixels to keep UI elements (like the detailed view toggle) from the edge of the displayed map texture.
@export var label_map_edge_padding: float = 5.0 
## The squared radius (in pixels on the rendered map texture) for convoy hover detection. (e.g., 25*25 = 625).
@export var convoy_hover_radius_sq: float = 625.0 
## The squared radius (in pixels on the rendered map texture) for settlement hover detection. (e.g., 20*20 = 400).
@export var settlement_hover_radius_sq: float = 400.0 

var _refresh_notification_label: Label  # For the "Data Refreshed" notification


var _current_hover_info: Dictionary = {}  # Will be updated by MapInteractionManager signal
var _selected_convoy_ids: Array[String] = []  # Will be updated by MapInteractionManager signal

var _route_preview_highlight_data: Array = [] # Stores points for the preview highlight
var _is_in_route_preview_mode: bool = false # Flag to indicate preview is active
var _preview_started_this_frame: bool = false # Race condition guard for route preview

## Initial state for toggling detailed map features (grid & political colors) on or off.
@export_group("Camera Focusing")
@export var convoy_focus_zoom_target_tiles_wide: float = 100 # Example: Increased further to zoom out more
## When a convoy menu opens, this percentage of the map view's width is used to shift the convoy leftwards (camera rightwards) from the exact center.
@export var convoy_menu_map_view_offset_percentage: float = 0.0 # Set to 0.0 to center convoy in partial view
@export var convoy_focus_zoom_target_tiles_high: float = 70.0 # Example: Increased further to zoom out more

@export_group("Map Display") # Or an existing relevant group

@export var show_detailed_view: bool = true 



var _dragging_panel_node: Panel = null  # Will be updated by MapInteractionManager signal or getter
var _drag_offset: Vector2 = Vector2.ZERO  # This state will move to MapInteractionManager
var _convoy_label_user_positions: Dictionary = {}  # Will be updated by MapInteractionManager signal
var _dragged_convoy_id_actual_str: String = "" # Will be updated by MapInteractionManager signal or getter


# --- Panning and Zooming State ---
# These are now managed by MapInteractionManager and MapCamera
# var _is_panning: bool = false
# var _last_pan_mouse_pos: Vector2
# var _current_zoom: float = 1.0
# var min_zoom, max_zoom, zoom_factor_increment are now in MapInteractionManager

# Z-index constants for children of MapContainer

# MapView's display rect is now always its own viewport (managed by ViewportContainer).
# var _current_map_display_rect: Rect2 # Effectively get_viewport().get_visible_rect()
# var _is_map_in_partial_view: bool = false # This state is now managed by GameScreenManager
var _map_and_ui_setup_complete: bool = false # New flag
var _deferred_convoy_data: Array = [] # To store convoy data if it arrives before map setup
var _view_is_initialized: bool = false # To track if the view has been set up
var _is_ready: bool = false # To ensure _initialize_view is not called before _ready

const MAP_DISPLAY_Z_INDEX = 0
# UIManager's label containers will use a higher Z_INDEX (e.g., 2), set within UIManager.gd


## Populates the terrain_tilemap from a 2D array of tile type IDs
func populate_tilemap_from_data(tile_data_2d: Array) -> void:
	if not is_instance_valid(terrain_tilemap):
		printerr("[ERROR] terrain_tilemap is not valid!")
		return
	terrain_tilemap.clear()
	var set_count := 0
	var skipped_count := 0
	var missing_tile_names := {}
	# Build a mapping from tile name (texture file basename) to (source_id, atlas_coords)
	var tile_name_to_source_and_coords := {}
	var tile_set = terrain_tilemap.tile_set
	if is_instance_valid(tile_set):
		for i in range(tile_set.get_source_count()):
			var source_id = tile_set.get_source_id(i)
			var source = tile_set.get_source(source_id)
			if source == null:
				continue
			var texture_name = ""
			if source.has_method("get_texture"):
				var tex = source.get_texture()
				if tex and tex.resource_path:
					texture_name = tex.resource_path.get_file().get_basename() # e.g., "plains"
			for j in range(source.get_tiles_count()):
				var coords = source.get_tile_id(j)
				# Use texture_name as the tile name
				tile_name_to_source_and_coords[texture_name] = {"source_id": source_id, "coords": coords}
		print("[DEBUG] tile_name_to_source_and_coords mapping:", tile_name_to_source_and_coords)
	else:
		printerr("[ERROR] terrain_tilemap.tile_set is not valid!")
		return
	for y in tile_data_2d.size():
		var row = tile_data_2d[y]
		for x in row.size():
			var tile = row[x]
			var tname = "impassable"
			if tile is Dictionary:
				if tile.has("settlements") and tile["settlements"] is Array and tile["settlements"].size() > 0:
					var sett_type = tile["settlements"][0].get("sett_type", "town")
					tname = settlement_type_to_name.get(sett_type, "town")
				else:
					var terrain_int = tile.get("terrain_difficulty", 0)
					tname = terrain_int_to_name.get(terrain_int, "impassable")
			else:
				tname = terrain_int_to_name.get(tile, "impassable")
			if tile_name_to_source_and_coords.has(tname):
				var entry = tile_name_to_source_and_coords[tname]
				var coords = entry["coords"]
				if typeof(coords) == TYPE_DICTIONARY:
					coords = Vector2i(coords["x"], coords["y"])
				terrain_tilemap.set_cell(Vector2i(x, y), entry["source_id"], coords)
				set_count += 1
			else:
				skipped_count += 1
				missing_tile_names[tname] = true
				if set_count < 10:
					print("[DIAG] Skipped set_cell at (", x, ",", y, ") with tile name:", tname, " (not in tileset)")
	print("[INFO] TileMap population complete. set_count:", set_count, " skipped_count:", skipped_count)
	print("[INFO] Used cells after population:", terrain_tilemap.get_used_cells().size())
	if missing_tile_names.size() > 0:
		print("[DIAG] Missing tile names (not in tileset):", missing_tile_names.keys())
	# DEBUG: Try to manually set a test tile at (0,0) if possible
	for k in tile_name_to_source_and_coords.keys():
		var entry = tile_name_to_source_and_coords[k]
		var coords = entry["coords"]
		if typeof(coords) == TYPE_DICTIONARY:
			coords = Vector2i(coords["x"], coords["y"])
		print("[DEBUG] Attempting to set test tile '", k, "' at (0,0) with source_id:", entry["source_id"], " coords:", coords)
		terrain_tilemap.set_cell(Vector2i(0, 0), entry["source_id"], coords)
		break # Only set the first available tile as a test


func _ready():
	map_display.texture = sub_viewport.get_texture()
	print("[DIAGNOSTIC_LOG | main.gd] _ready(): Main view is loaded and ready. WAITING to be made visible.")
	# Connect to GameDataManager's map_data_loaded signal
	if is_instance_valid(game_data_manager):
		game_data_manager.map_data_loaded.connect(_on_map_data_loaded)
	else:
		printerr("[ERROR] Could not find GameDataManager autoload!")
	# Connect to window resize and update SubViewport size
	get_viewport().size_changed.connect(_on_window_resized)
	_update_subviewport_size()

func _on_window_resized():
	_update_subviewport_size()

func _update_subviewport_size():
	var subvp = null
	if map_container and map_container.has_node("SubViewport"):
		subvp = map_container.get_node("SubViewport")
	if is_instance_valid(subvp):
		subvp.size = get_viewport().size
		# print("[INFO] SubViewport size updated to:", subvp.size)
# Handler for map_data_loaded signal: extracts tile type IDs and populates tilemap
func _on_map_data_loaded(map_tiles_data: Array) -> void:
	if not is_instance_valid(terrain_tilemap):
		printerr("[ERROR] terrain_tilemap is not valid!")
		return
	if not map_tiles_data or map_tiles_data.size() == 0:
		printerr("[ERROR] map_tiles_data is empty or invalid!")
		return
	populate_tilemap_from_data(map_tiles_data)
	print("[SUMMARY] TileMap populated. Used cells:", terrain_tilemap.get_used_cells().size())
	# --- DIAGNOSTICS: TerrainTileMap state ---
	if is_instance_valid(terrain_tilemap):
		print("[DIAG] TerrainTileMap tile_set:", terrain_tilemap.tile_set)
		print("[DIAG] TerrainTileMap visible:", terrain_tilemap.visible)
		var parent_node = terrain_tilemap.get_parent()
		if is_instance_valid(parent_node) and parent_node is CanvasItem:
			print("[DIAG] TerrainTileMap parent SubViewport visible:", parent_node.visible)
		else:
			print("[DIAG] TerrainTileMap parent SubViewport visible: N/A or not a CanvasItem")
		# Print a sample of atlas coords used for first 5 tiles in first row
		if map_tiles_data.size() > 0 and map_tiles_data[0].size() > 0:
			var sample_row = map_tiles_data[0]
			for i in range(min(5, sample_row.size())):
				print("[DIAG] Sample tile[0][", i, "]: ", sample_row[i])
	else:
		print("[DIAG] TerrainTileMap is not valid!")
	set_process_input(true)


func _input(event):
	if is_instance_valid(map_camera_controller):
		var handled = map_camera_controller.handle_input(event)
		if handled:
			return
	# Optionally, handle other input here if needed
