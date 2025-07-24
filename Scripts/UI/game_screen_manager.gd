extends Node
class_name GameScreenManager

## Logging: GameScreenManager initialization
@onready var map_viewport_container: SubViewportContainer = get_node("MapViewportContainer")
@onready var menu_manager: Control = get_node("MenuUILayer/MenuManager")
# Path to the MapCameraController node, nested within MapRender (MapView.tscn instance)
@onready var map_camera_controller = get_node_or_null("MapViewportContainer/MapRender/MapInteractionManager/MapCameraController")
@onready var login_screen: Control = get_node("LoginScreen") # Path to your LoginScreen instance
@onready var menu_ui_layer: CanvasLayer = get_node("MenuUILayer") # Get the MenuUILayer itself

const PARTIAL_SCREEN_MENU_TYPES: Array[String] = [
	"convoy_overview",       # Main convoy detail/overview screen
	"convoy_vehicle_submenu",
	"convoy_journey_submenu",
	"convoy_settlement_submenu",
	"convoy_cargo_submenu"
]

var current_user_id: String = ""


func _ready():
	print("GameScreenManager _ready(): Checking GameDataManager singleton.")
	if GameDataManager != null:
		print("GameScreenManager _ready(): GameDataManager is NOT NULL at start of _ready.")
	else:
		print("GameScreenManager _ready(): GameDataManager IS NULL at start of _ready.")

	print("GameScreenManager _ready(): Checking MapCameraController node.")
	if not is_instance_valid(map_camera_controller):
		printerr("GameScreenManager: MapCameraController node not found. Please check the path in GameScreenManager.gd. Camera controls cannot be managed.")
	else:
		print("GameScreenManager: MapCameraController node found.")

	print("GameScreenManager _ready(): Checking LoginScreen node.")
	if not is_instance_valid(login_screen):
		printerr("GameScreenManager: LoginScreen node not found. Check path. Assuming direct game start.")
		_initialize_main_game_ui_and_signals()
		return # Skip further login setup
	else:
		print("GameScreenManager: LoginScreen node found.")

	login_screen.login_requested.connect(_on_login_requested)
	login_screen.visible = true
	login_screen.modulate = Color(1,1,1,1) # Ensure LoginScreen itself is opaque

	# Programmatically force the LoginScreen to fill the entire viewport.
	login_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	login_screen.position = Vector2.ZERO
	login_screen.pivot_offset = Vector2.ZERO
	if is_instance_valid(login_screen.get_parent()):
		login_screen.size = get_viewport().size
		print("GameScreenManager: LoginScreen size set to viewport size:", login_screen.size)

	if is_instance_valid(map_viewport_container):
		map_viewport_container.visible = false
		print("GameScreenManager: MapViewportContainer hidden at startup.")
	if is_instance_valid(menu_ui_layer):
		menu_ui_layer.visible = false
		print("GameScreenManager: MenuUILayer hidden at startup.")

	if is_instance_valid(map_camera_controller):
		map_camera_controller.controls_enabled = false
		print("GameScreenManager: Camera controls disabled during login.")
	else:
		printerr("GameScreenManager: Cannot disable MapCameraController controls during login - controller not found (was checked earlier).")

func _initialize_main_game_ui_and_signals():
	"""Initializes connections and states for the main game UI components."""
	print("GameScreenManager: Initializing main game UI and signals.")
	if is_instance_valid(map_camera_controller):
		# --- DIAGNOSTICS: Print visibility state of all relevant map nodes (no MapRender) ---
		if is_instance_valid(map_viewport_container):
			print("[VIS] MapViewportContainer visible:", map_viewport_container.visible)
			var map_container = map_viewport_container.get_node_or_null("MapContainer")
			if is_instance_valid(map_container):
				print("[VIS] MapContainer visible:", map_container.visible)
				var subviewport = map_container.get_node_or_null("SubViewport")
				if is_instance_valid(subviewport):
					print("[VIS] SubViewport visible:", subviewport.visible)
					var tilemap_node = subviewport.get_node_or_null("TerrainTileMap")
					if is_instance_valid(tilemap_node):
						print("[VIS] TerrainTileMap visible:", tilemap_node.visible)
						print("[DIAG] TerrainTileMap type:", typeof(tilemap_node), " class:", tilemap_node.get_class())
						print("[DIAG] TerrainTileMap resource_path:", tilemap_node.resource_path if tilemap_node.has_method("resource_path") else "N/A")
						print("[DIAG] TerrainTileMap.tile_set is_instance_valid:", is_instance_valid(tilemap_node.tile_set))
						if is_instance_valid(tilemap_node.tile_set):
							print("[DIAG] TerrainTileMap.tile_set resource_path:", tilemap_node.tile_set.resource_path if tilemap_node.tile_set.has_method("resource_path") else "N/A")
							print("[DIAG] TerrainTileMap.tile_set to_string:", str(tilemap_node.tile_set))
							var ids = []
							if tilemap_node.tile_set.has_method("get_tiles_ids"):
								ids = tilemap_node.tile_set.get_tiles_ids()
							else:
								for i in range(100):
									if tilemap_node.tile_set.has_method("has_tile") and tilemap_node.tile_set.has_tile(i):
										ids.append(i)
							print("[DIAG] TerrainTileMap.tile_set ids:", ids)
						else:
							print("[DIAG] TerrainTileMap.tile_set is not valid!")
					var map_camera = subviewport.get_node_or_null("MapCamera")
					if is_instance_valid(map_camera):
						print("[VIS] MapCamera visible:", map_camera.visible)
		# Diagnostics: print children of MapViewportContainer
		print("[DIAG] Children of MapViewportContainer:")
		for child in map_viewport_container.get_children():
			print("  - ", child.name, " (type: ", typeof(child), ")")

		var map_render = map_viewport_container.get_node_or_null("MapRender")
		if not is_instance_valid(map_render):
			printerr("GameScreenManager: MapRender node not found under MapViewportContainer.")
			print("[DIAG] Children of MapViewportContainer:")
			for child in map_viewport_container.get_children():
				print("  - ", child.name, " (type: ", typeof(child), ")")
		else:
			print("GameScreenManager: MapRender node found under MapViewportContainer.")
			print("[DIAG] Children of MapRender:")
			for child in map_render.get_children():
				print("  - ", child.name, " (type: ", typeof(child), ")")

			var map_container = map_render.get_node_or_null("MapContainer")
			if not is_instance_valid(map_container):
				printerr("GameScreenManager: MapContainer node not found under MapRender.")
				print("[DIAG] Children of MapRender:")
				for child in map_render.get_children():
					print("  - ", child.name, " (type: ", typeof(child), ")")
			else:
				print("GameScreenManager: MapContainer node found under MapRender.")
				print("[DIAG] Children of MapContainer:")
				for child in map_container.get_children():
					print("  - ", child.name, " (type: ", typeof(child), ")")

				var subviewport = map_container.get_node_or_null("SubViewport")
				if not is_instance_valid(subviewport):
					printerr("GameScreenManager: SubViewport node not found under MapContainer.")
					print("[DIAG] Children of MapContainer:")
					for child in map_container.get_children():
						print("  - ", child.name, " (type: ", typeof(child), ")")
				else:
					print("GameScreenManager: SubViewport node found under MapContainer.")
					print("[DIAG] Children of SubViewport:")
					for child in subviewport.get_children():
						print("  - ", child.name, " (type: ", typeof(child), ")")

					var camera_node = subviewport.get_node_or_null("MapCamera")
					var tilemap_node = subviewport.get_node_or_null("TerrainTileMap")
					if is_instance_valid(camera_node) and is_instance_valid(tilemap_node):
						var map_screen_rect = map_viewport_container.get_global_rect()
						map_camera_controller.initialize(camera_node, tilemap_node, map_screen_rect)
						print("GameScreenManager: Called initialize() on MapCameraController with valid nodes.")
					else:
						printerr("GameScreenManager: Could not find valid Camera2D or TileMapLayer under SubViewport.")
		map_camera_controller.controls_enabled = true
		print("GameScreenManager: Camera controls enabled for main game.")

	if not is_instance_valid(menu_manager):
		printerr("GameScreenManager: MenuManager node not found. Check path.")
	else:
		print("GameScreenManager: MenuManager node found.")
	if not is_instance_valid(map_viewport_container):
		printerr("GameScreenManager: MapViewportContainer node not found. Check path.")
	else:
		print("GameScreenManager: MapViewportContainer node found.")

	# Connect to signals from MenuManager
	if is_instance_valid(menu_manager):
		if menu_manager.has_signal("menu_opened"):
			menu_manager.menu_opened.connect(_on_menu_opened)
			print("GameScreenManager: Connected to menu_opened signal.")
		else:
			printerr("GameScreenManager: MenuManager does not have 'menu_opened' signal.")

		if menu_manager.has_signal("menus_completely_closed"):
			menu_manager.menus_completely_closed.connect(_on_menus_completely_closed)
			print("GameScreenManager: Connected to menus_completely_closed signal.")
		else:
			printerr("GameScreenManager: MenuManager does not have 'menus_completely_closed' signal.")

	# Initial state: map is full screen
	print("GameScreenManager: Setting map view layout to full screen.")
	_set_map_view_layout(1.0)
	if is_instance_valid(map_viewport_container):
		map_viewport_container.visible = true
		print("GameScreenManager: MapViewportContainer made visible.")
	if is_instance_valid(menu_ui_layer):
		menu_ui_layer.visible = true
		print("GameScreenManager: MenuUILayer made visible.")
	# MapRender bounds update removed; handled by TileMapLayer now.


func _on_login_requested(user_id: String) -> void:
	print("GameScreenManager: Login requested with User ID:", user_id)
	current_user_id = user_id
	if GameDataManager != null:
		if GameDataManager.has_method("trigger_initial_convoy_data_fetch"):
			print("GameScreenManager: Triggering initial convoy data fetch for user.")
			GameDataManager.trigger_initial_convoy_data_fetch(current_user_id)
		else:
			printerr("GameScreenManager: GameDataManager does not have 'trigger_initial_convoy_data_fetch' method.")
	else:
		printerr("GameScreenManager: GameDataManager singleton not found.")
	login_screen.visible = false
	print("GameScreenManager: LoginScreen hidden after login.")
	_initialize_main_game_ui_and_signals()

func _on_menu_opened(_menu_node: Node, menu_type: String):
	# If a menu type that requires a split view (map on left 1/3) is opened
	print("GameScreenManager: Menu opened with type:", menu_type)
	if menu_type in PARTIAL_SCREEN_MENU_TYPES:
		print("GameScreenManager: Setting map view layout to 1/3 for partial screen menu.")
		_set_map_view_layout(1.0 / 3.0)
	# Else: You might have other logic, e.g., some menus hide the map,
	# or some menus overlay the full map. For now, only "convoy_detail" shrinks it.
	# If other menus open that don't require split screen, the map remains as is.

func _on_menus_completely_closed():
	print("GameScreenManager: All menus closed, setting map to full screen.")
	_set_map_view_layout(1.0)

func _set_map_view_layout(right_anchor: float):
	"""Sets the map viewport container's layout based on a given right anchor."""
	print("GameScreenManager: Setting map view layout. Right anchor:", right_anchor)
	if not is_instance_valid(map_viewport_container):
		printerr("GameScreenManager: map_viewport_container invalid in _set_map_view_layout")
		return
	map_viewport_container.anchor_right = right_anchor
	map_viewport_container.anchor_bottom = 1.0
	map_viewport_container.offset_right = 0
	map_viewport_container.offset_bottom = 0
	map_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	print("GameScreenManager: MapViewportContainer anchors and size flags set.")
	# MapRender bounds update removed; handled by TileMapLayer now.
	_fit_camera_to_map()
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("fit_camera_to_tilemap"):
		print("GameScreenManager: Forcing camera fit to tilemap after layout change.")
		map_camera_controller.fit_camera_to_tilemap()

func _fit_camera_to_map():
	print("GameScreenManager: Fitting camera to map.")
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("fit_camera_to_tilemap"):
		map_camera_controller.fit_camera_to_tilemap()
