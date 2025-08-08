@tool
extends Control

# --- Debug Overlay Flag ---


# --- Signals ---
signal map_ready_for_focus

# --- Node References ---
@onready var sub_viewport: SubViewport = $MapContainer/SubViewport
@onready var map_display: TextureRect = $MapContainer/MapDisplay
@onready var map_camera: Camera2D = $MapContainer/SubViewport/MapCamera
@onready var terrain_tilemap: TileMapLayer = $MapContainer/SubViewport/TerrainTileMap
@onready var map_interaction_manager: Node = $MapInteractionManager
@onready var map_camera_controller: Node = $MapInteractionManager/MapCameraController
@onready var convoy_visuals_manager: Node = $ConvoyVisualsManager
# The owner of an instanced scene is the root node of the scene that contains the instance.
# In this case, MainScreen.tscn instances MapView.tscn, so MainScreen is the owner.
@onready var main_screen: Control = get_owner()

# --- Autoloads / Singletons ---
@onready var game_data_manager = get_node_or_null("/root/GameDataManager")

# --- Data Variables ---
var map_tiles: Array = []
var _all_settlement_data: Array = []
var _all_convoy_data: Array = []
var _current_hover_info: Dictionary = {}
var _selected_convoy_ids: Array[String] = []
var _convoy_label_user_positions: Dictionary = {}

# --- State Flags ---
var _map_and_ui_setup_complete: bool = false

# --- Constants ---
var terrain_int_to_name = {
	0: "impassable", 1: "highway", 2: "road", 3: "trail", 4: "desert",
	5: "plains", 6: "forest", 7: "swamp", 8: "mountains", 9: "near_impassible"
}
var settlement_type_to_name = {
	"town": "town", "village": "village", "city": "city", "city-state": "city-state",
	"dome": "dome", "military_base": "military_base", "tutorial": "tutorial"
}

func _ready():
	self.name = "Main"
	call_deferred("initialize_all_components")

func initialize_all_components():
	print("--- Main Initialization Start ---")

	if not is_instance_valid(main_screen):
		printerr("[Main] FATAL: Could not determine the owner (MainScreen). The scene setup might be incorrect. Cannot proceed with initialization.")
		return

	# Reparent MapDisplay to be a child of this node (the MapView) for correct UI layouting.
	if is_instance_valid(map_display):
		if map_display.get_parent():
			map_display.get_parent().remove_child(map_display)
		self.add_child(map_display)
		# Ensure it's drawn behind other UI elements within this control
		move_child(map_display, 0)
		map_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		print("[Main] Reparented MapDisplay to self (MapView).")
	else:
		printerr("[Main] MapDisplay node is invalid.")

	# Connect to GameDataManager signals
	if is_instance_valid(game_data_manager):
		if not game_data_manager.is_connected("map_data_loaded", Callable(self, "_on_map_data_loaded")):
			game_data_manager.connect("map_data_loaded", Callable(self, "_on_map_data_loaded"))
		# FIX: use updated signal names
		if not game_data_manager.is_connected("convoy_data_updated", Callable(self, "_on_convoy_data_loaded")):
			game_data_manager.connect("convoy_data_updated", Callable(self, "_on_convoy_data_loaded"))
		if not game_data_manager.is_connected("settlement_data_updated", Callable(self, "_on_settlement_data_loaded")):
			game_data_manager.connect("settlement_data_updated", Callable(self, "_on_settlement_data_loaded"))
	else:
		printerr("Main: GameDataManager not found.")

	# Initialize MainScreen
	if is_instance_valid(main_screen):
		main_screen.initialize(self, map_camera_controller, map_interaction_manager)
		# Connect this node's signal to a method on the main_screen node.
		if not self.is_connected("map_ready_for_focus", Callable(main_screen, "_on_map_ready_for_focus")):
			self.connect("map_ready_for_focus", Callable(main_screen, "_on_map_ready_for_focus"))
			print("[Main] Connected self.map_ready_for_focus to main_screen._on_map_ready_for_focus")

	# Initialize MapInteractionManager with correct UIManager node path
	if is_instance_valid(map_interaction_manager):
		# --- Diagnostics: Print validity and type of terrain_tilemap and map_camera ---
		print("[DIAG] main.gd: terrain_tilemap valid:", is_instance_valid(terrain_tilemap))
		if is_instance_valid(terrain_tilemap):
			print("[DIAG] terrain_tilemap type:", typeof(terrain_tilemap), " class:", terrain_tilemap.get_class())
			print("[DIAG] terrain_tilemap resource_path:", terrain_tilemap.resource_path if terrain_tilemap.has_method("resource_path") else "N/A")
		else:
			printerr("[DIAG] main.gd: terrain_tilemap is NOT valid!")
		print("[DIAG] main.gd: map_camera valid:", is_instance_valid(map_camera))
		if is_instance_valid(map_camera):
			print("[DIAG] map_camera type:", typeof(map_camera), " class:", map_camera.get_class())
			print("[DIAG] map_camera position:", map_camera.position, " global_position:", map_camera.global_position)
		else:
			printerr("[DIAG] main.gd: map_camera is NOT valid!")
		var ui_manager_node = get_node("UIManager") # UIManager is a sibling of Main in MapView.tscn
		map_interaction_manager.initialize(
			terrain_tilemap,
			ui_manager_node,
			_all_convoy_data,
			_all_settlement_data,
			map_tiles,
			map_camera,
			sub_viewport,
			_selected_convoy_ids,
			_convoy_label_user_positions
		)
		if not map_interaction_manager.is_connected("selection_changed", Callable(self, "_on_selection_changed")):
			map_interaction_manager.connect("selection_changed", Callable(self, "_on_selection_changed"))
		if not map_interaction_manager.is_connected("hover_changed", Callable(self, "_on_hover_changed")):
			map_interaction_manager.connect("hover_changed", Callable(self, "_on_hover_changed"))
		if not map_interaction_manager.is_connected("convoy_menu_requested", Callable(self, "_on_convoy_menu_requested")):
			map_interaction_manager.connect("convoy_menu_requested", Callable(self, "_on_convoy_menu_requested"))

		# Ensure UIManager knows the terrain tilemap explicitly
		if is_instance_valid(ui_manager_node):
			ui_manager_node.terrain_tilemap = terrain_tilemap

	# Initialize ConvoyVisualsManager
	if is_instance_valid(convoy_visuals_manager):
		# Ensure convoy_visuals_manager is a child of SubViewport so icons move with the map
		if is_instance_valid(sub_viewport):
			if convoy_visuals_manager.get_parent() != sub_viewport:
				if convoy_visuals_manager.get_parent():
					convoy_visuals_manager.get_parent().remove_child(convoy_visuals_manager)
				sub_viewport.add_child(convoy_visuals_manager)
		convoy_visuals_manager.initialize(convoy_visuals_manager, terrain_tilemap)

	print("--- Main Initialization Complete ---")
	_map_and_ui_setup_complete = true

func _process(_delta: float):
	if not _map_and_ui_setup_complete:
		return

	# This node (self) is the MapView.
	var map_view = self
	if not is_instance_valid(map_view):
		return

	# Update the TextureRect with the SubViewport's texture.
	if is_instance_valid(map_display):
		map_display.texture = sub_viewport.get_texture()

func populate_tilemap_from_data(tile_data_2d: Array):
	if not is_instance_valid(terrain_tilemap):
		printerr("[ERROR] terrain_tilemap is not valid!")
		return
	terrain_tilemap.clear()
	var tile_set = terrain_tilemap.tile_set
	if not is_instance_valid(tile_set):
		printerr("[ERROR] terrain_tilemap.tile_set is not valid!")
		return

	var tile_name_to_source_and_coords := {}
	for i in range(tile_set.get_source_count()):
		var source_id = tile_set.get_source_id(i)
		var source = tile_set.get_source(source_id)
		if source and source.has_method("get_texture"):
			var tex = source.get_texture()
			if tex and tex.resource_path:
				var texture_name = tex.resource_path.get_file().get_basename()
				for j in range(source.get_tiles_count()):
					var coords = source.get_tile_id(j)
					tile_name_to_source_and_coords[texture_name] = {"source_id": source_id, "coords": coords}

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
				terrain_tilemap.set_cell(Vector2i(x, y), entry["source_id"], entry["coords"])

func _on_map_data_loaded(p_map_tiles: Array):
	print("[main.gd] _on_map_data_loaded: map_tiles_data size=", p_map_tiles.size())
	if not is_instance_valid(terrain_tilemap):
		printerr("[ERROR] terrain_tilemap is not valid!")
		return
	if not p_map_tiles or p_map_tiles.size() == 0:
		printerr("[ERROR] map_tiles_data is empty or invalid!")
		return


	self.map_tiles = p_map_tiles
	populate_tilemap_from_data(p_map_tiles)

	# Debug: Print node transforms and positions (Godot 4.4 valid properties)
	if is_instance_valid(terrain_tilemap):
		print("[DEBUG] terrain_tilemap position:", terrain_tilemap.position, 
			  " global_position:", terrain_tilemap.global_position, 
			  " scale:", terrain_tilemap.scale, 
			  " transform:", terrain_tilemap.transform)
	if is_instance_valid(sub_viewport):
		# SubViewport: print only valid property 'size'
		print("[DEBUG] sub_viewport size:", sub_viewport.size)
	if is_instance_valid(map_display):
		print("[DEBUG] map_display position:", map_display.position, " size:", map_display.size)

	# --- Calculate true map size and set it on the camera controller ---
	var map_height = p_map_tiles.size()
	var map_width = 0
	if map_height > 0:
		# Find the widest row (in case of ragged arrays)
		for row in p_map_tiles:
			if row is Array and row.size() > map_width:
				map_width = row.size()
	var map_size = Vector2i(map_width, map_height)
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("set_map_size"):
		map_camera_controller.set_map_size(map_size)
		print("[main.gd] Set map_camera_controller map_size to ", map_size)
	else:
		printerr("[main.gd] map_camera_controller is invalid or missing set_map_size method!")

	print("[main.gd] Emitting map_ready_for_focus signal...")
	emit_signal("map_ready_for_focus")
	# Push initial state to UI (no hover yet)
	_update_ui_manager(true)

func _on_convoy_data_loaded(p_convoy_data: Array):
	_all_convoy_data = p_convoy_data
	if is_instance_valid(map_interaction_manager):
		map_interaction_manager.update_data_references(_all_convoy_data, _all_settlement_data, map_tiles)
	_update_ui_manager(false)

func _on_settlement_data_loaded(p_settlement_data: Array):
	_all_settlement_data = p_settlement_data
	if is_instance_valid(map_interaction_manager):
		map_interaction_manager.update_data_references(_all_convoy_data, _all_settlement_data, map_tiles)
	_update_ui_manager(false)

func _on_selection_changed(selected_ids: Array):
	_selected_convoy_ids = selected_ids
	if is_instance_valid(convoy_visuals_manager):
		convoy_visuals_manager.update_selected_convoys(selected_ids)
	_update_ui_manager(false)

func _on_hover_changed(hover_info: Dictionary):
	_current_hover_info = hover_info
	_update_ui_manager(true)

func _on_convoy_menu_requested(convoy_data: Dictionary):
	var menu_manager = get_node_or_null("/root/MenuManager")
	if menu_manager:
		menu_manager.open_convoy_menu_with_data(convoy_data)
	else:
		printerr("Main: Could not find MenuManager to open convoy menu.")

# --- Helper to push state into UIManager ---
func _update_ui_manager(is_light_update: bool):
	var ui_manager_node: Node = get_node_or_null("UIManager")
	if not is_instance_valid(ui_manager_node):
		return
	if not ui_manager_node.has_method("update_ui_elements"):
		return
	var color_map: Dictionary = {}
	if is_instance_valid(game_data_manager) and game_data_manager.has_method("get_convoy_id_to_color_map"):
		color_map = game_data_manager.get_convoy_id_to_color_map()
	var dragging_panel_node: Panel = null
	var dragged_convoy_id_str: String = ""
	var user_positions: Dictionary = _convoy_label_user_positions
	var current_zoom: float = 1.0
	if is_instance_valid(map_interaction_manager):
		if map_interaction_manager.has_method("get_dragging_panel_node"):
			dragging_panel_node = map_interaction_manager.get_dragging_panel_node()
		if map_interaction_manager.has_method("get_dragged_convoy_id_str"):
			dragged_convoy_id_str = map_interaction_manager.get_dragged_convoy_id_str()
		if map_interaction_manager.has_method("get_convoy_label_user_positions"):
			user_positions = map_interaction_manager.get_convoy_label_user_positions()
		if map_interaction_manager.has_method("get_current_camera_zoom"):
			current_zoom = map_interaction_manager.get_current_camera_zoom()
	var clamp_rect: Rect2 = get_viewport().get_visible_rect()
	if is_instance_valid(map_display) and map_display.has_method("get_global_rect"):
		clamp_rect = map_display.get_global_rect()
	ui_manager_node.update_ui_elements(
		_all_convoy_data,
		_all_settlement_data,
		color_map,
		_current_hover_info,
		_selected_convoy_ids,
		user_positions,
		dragging_panel_node,
		dragged_convoy_id_str,
		clamp_rect,
		is_light_update,
		current_zoom
	)
