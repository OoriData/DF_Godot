extends Node
class_name GameScreenManager

# Adjust these paths based on your actual scene tree structure
# These paths are relative to the node where GameScreenManager.gd is attached (e.g., GameRoot)
@onready var map_viewport_container: SubViewportContainer = get_node("MapViewportContainer")
@onready var menu_manager: Control = get_node("MenuUILayer/MenuManager")
# Path to the MapCameraController node, nested within MapRender (MapView.tscn instance)
@onready var map_camera_controller: MapCameraController = get_node_or_null("MapViewportContainer/MapRender/MapInteractionManager/MapCameraController") as MapCameraController
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
	# print("GameScreenManager _ready(): STARTING. Attempting to check GameDataManager singleton.") # Original check
	# if Engine.has_singleton("GameDataManager"):
		# print("GameScreenManager _ready(): Engine.has_singleton('GameDataManager') is TRUE at start of _ready.")
	# else:
		# print("GameScreenManager _ready(): Engine.has_singleton('GameDataManager') is FALSE at start of _ready.")
	
	# New check: Try direct access to the Autoload name
	if GameDataManager != null:
		print("GameScreenManager _ready(): Direct access to 'GameDataManager' (Autoload) is NOT NULL at start of _ready.")
	else:
		print("GameScreenManager _ready(): Direct access to 'GameDataManager' (Autoload) IS NULL at start of _ready.")


	if not is_instance_valid(map_camera_controller):
		printerr("GameScreenManager: MapCameraController node not found. Please check the path in GameScreenManager.gd. Camera controls cannot be managed.")

	# --- Login Screen Setup ---
	if not is_instance_valid(login_screen):
		printerr("GameScreenManager: LoginScreen node not found. Check path. Assuming direct game start.")
		_initialize_main_game_ui_and_signals()
		return # Skip further login setup
	
	login_screen.login_requested.connect(_on_login_requested)
	login_screen.visible = true
	login_screen.modulate = Color(1,1,1,1) # Ensure LoginScreen itself is opaque
	
	# Programmatically force the LoginScreen to fill the entire viewport.
	# This should override any settings in the .tscn file or editor inspector.
	login_screen.set_anchors_preset(Control.PRESET_FULL_RECT) 
	login_screen.position = Vector2.ZERO 
	login_screen.pivot_offset = Vector2.ZERO 
	# Explicitly set size to match the viewport
	if is_instance_valid(login_screen.get_parent()):
		login_screen.size = get_viewport().size # Use viewport size


	# print("--- GameScreenManager: Login Screen Setup Diagnostics ---")
	# print("LoginScreen node_path: ", login_screen.get_path())
	# print("LoginScreen visible: ", login_screen.visible)
	# print("LoginScreen modulate: ", login_screen.modulate) # Check modulate/alpha
	# print("LoginScreen global_position: ", login_screen.get_global_rect().position)
	# print("LoginScreen size: ", login_screen.get_global_rect().size)
	# var login_bg = login_screen.get_node_or_null("Background")
	# if is_instance_valid(login_bg) and login_bg is ColorRect:
		# print("LoginScreen/Background visible: ", login_bg.visible)
		# print("LoginScreen/Background global_position: ", login_bg.get_global_rect().position)
		# print("LoginScreen/Background size: ", login_bg.get_global_rect().size)
		# print("LoginScreen/Background color: ", login_bg.color)
	# else:
		# print("LoginScreen/Background node not found or not a ColorRect.")

	# Ensure main game UI is hidden initially
	if is_instance_valid(map_viewport_container):
		map_viewport_container.visible = false
		# print("MapViewportContainer visible: ", map_viewport_container.visible)
	if is_instance_valid(menu_ui_layer): # Hide the whole MenuUILayer
		menu_ui_layer.visible = false
		# print("MenuUILayer visible: ", menu_ui_layer.visible)
	
	# Disable camera controls if login screen is active
	if is_instance_valid(map_camera_controller):
		map_camera_controller.controls_enabled = false # Disable camera controls during login
	else:
		printerr("GameScreenManager: Cannot disable MapCameraController controls during login - controller not found (was checked earlier).")
	# if is_instance_valid(map_camera_controller) and is_instance_valid(map_camera_controller.camera_node):
		# print("MapCamera (from MapCameraController) global_position: ", map_camera_controller.camera_node.global_position)
		# print("MapCamera (from MapCameraController) zoom: ", map_camera_controller.camera_node.zoom)
	# print("----------------------------------------------------")

	# --- MenuManager and MapViewportContainer checks (deferred if login screen is present) ---
	# These will be fully utilized after login.

func _initialize_main_game_ui_and_signals():
	"""Initializes connections and states for the main game UI components."""
	if is_instance_valid(map_camera_controller):
		map_camera_controller.controls_enabled = true # Enable camera controls for main game

	if not is_instance_valid(menu_manager):
		printerr("GameScreenManager: MenuManager node not found. Check path.")
		# No return here, other parts might still work or game might be unplayable.
	if not is_instance_valid(map_viewport_container):
		printerr("GameScreenManager: MapViewportContainer node not found. Check path.")
		# No return here.

	# Connect to signals from MenuManager
	if is_instance_valid(menu_manager):
		if menu_manager.has_signal("menu_opened"):
			menu_manager.menu_opened.connect(_on_menu_opened)
		else:
			printerr("GameScreenManager: MenuManager does not have 'menu_opened' signal.")

		if menu_manager.has_signal("menus_completely_closed"):
			menu_manager.menus_completely_closed.connect(_on_menus_completely_closed)
		else:
			printerr("GameScreenManager: MenuManager does not have 'menus_completely_closed' signal.")

	# Initial state: map is full screen
	_set_map_view_layout(1.0)
	
	# Ensure main game UI is visible if we skipped login
	if is_instance_valid(map_viewport_container):
		map_viewport_container.visible = true
	if is_instance_valid(menu_ui_layer):
		menu_ui_layer.visible = true
	
	# After main UI is initialized and map_viewport_container is visible and sized,
	# update the MapRender's (MapView's) understanding of its display bounds.
	_update_map_render_bounds_after_layout_change()


func _on_login_requested(user_id: String) -> void:
	# print("GameScreenManager: Login attempt with User ID: ", user_id)
	current_user_id = user_id
	
	# Pass the user_id to GameDataManager, which should then inform APICalls
	# Use direct access check here as well.
	if GameDataManager != null:
		# print("GameScreenManager (_on_login_requested): GameDataManager is NOT NULL.") # Optional debug
		if GameDataManager.has_method("trigger_initial_convoy_data_fetch"):
			GameDataManager.trigger_initial_convoy_data_fetch(current_user_id)
		else:
			printerr("GameScreenManager: GameDataManager does not have 'trigger_initial_convoy_data_fetch' method.")
	else:
		# This block will execute if GameDataManager is null from this script's perspective
		# print("GameScreenManager (_on_login_requested): GameDataManager IS NULL.") # Optional debug
		printerr("GameScreenManager: GameDataManager singleton not found.")

	login_screen.visible = false
	_initialize_main_game_ui_and_signals() # Now setup the main game UI and its signals

func _on_menu_opened(_menu_node: Node, menu_type: String):
	# If a menu type that requires a split view (map on left 1/3) is opened
	if menu_type in PARTIAL_SCREEN_MENU_TYPES:
		_set_map_view_layout(1.0 / 3.0)
	# Else: You might have other logic, e.g., some menus hide the map,
	# or some menus overlay the full map. For now, only "convoy_detail" shrinks it.
	# If other menus open that don't require split screen, the map remains as is.

func _on_menus_completely_closed():
	# print("GameScreenManager: All menus closed, setting map to full screen.")
	_set_map_view_layout(1.0)

func _set_map_view_layout(right_anchor: float):
	"""Sets the map viewport container's layout based on a given right anchor."""
	if not is_instance_valid(map_viewport_container):
		printerr("GameScreenManager: map_viewport_container invalid in _set_map_view_layout")
		return
	map_viewport_container.anchor_right = right_anchor
	map_viewport_container.anchor_bottom = 1.0 # Stretch to full height
	map_viewport_container.offset_right = 0 # Clear any offset
	map_viewport_container.offset_bottom = 0 # Clear any offset
	map_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL # Ensure it fills
	map_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL   # Ensure it fills
	_update_map_render_bounds_after_layout_change()

func _update_map_render_bounds_after_layout_change():
	# Call this after the map_viewport_container's layout has been set by GameScreenManager
	if is_instance_valid(map_viewport_container) and map_viewport_container.visible:
		var map_render_node = map_viewport_container.get_node_or_null("MapRender")
		if is_instance_valid(map_render_node) and map_render_node.has_method("update_map_render_bounds"):
			map_render_node.update_map_render_bounds(map_viewport_container.get_global_rect())
		elif is_instance_valid(map_render_node):
			printerr("GameScreenManager: MapRender node does not have 'update_map_render_bounds' method.")
