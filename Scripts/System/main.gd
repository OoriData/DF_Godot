# main.gd
@tool
extends Node2D

# Node references
## Reference to the node that has map_render.gd attached. This should be a child of the current node.
@onready var map_renderer_node: Node = $MapRendererLogic # MapRendererLogic is now a direct child
## Reference to the TextureRect that displays the map.
@onready var map_display: TextureRect = $MapContainer/MapDisplay

## Reference to the new MapContainer node. Ensure this path is correct.
@onready var map_container: Node2D = $MapContainer
@onready var map_camera: Camera2D = $MapCamera # Reference to the new MapCamera


@onready var ui_manager: Node = $ScreenSpaceUI/UIManagerNode # Corrected path
@onready var detailed_view_toggle: CheckBox = $ScreenSpaceUI/UIManagerNode/DetailedViewToggleCheckbox # Corrected path
@onready var map_interaction_manager: Node = $MapInteractionManager # Path to your MapInteractionManager node
# Reference to the new ConvoyVisualsManager node
@onready var convoy_visuals_manager: Node = $ConvoyVisualsManager # Adjust path if you place it elsewhere
# IMPORTANT: Adjust the path "$GameTimersNode" to the actual path of your GameTimers node in your scene tree.
@onready var game_timers_node: Node = $GameTimersNode # Adjust if necessary
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


func _ready():
	print("[DIAGNOSTIC_LOG | main.gd] _ready(): Main view is loaded and ready. WAITING to be made visible.")
	# print('Main: _ready() called.')  # DEBUG
	# print("!!!!!!!!!! MAIN.GD _ready() IS RUNNING !!!!!!!!!!") # DEBUG

	# Enable input processing for this Node2D to receive _input events,
	# including those propagated from its Control children (like MapDisplay).
	set_process_input(true)
	# self.visible = true # Visibility should be controlled by the parent scene/logic.

	# Explicitly disable the map camera on load. It will be enabled in _initialize_view()
	# when this scene is made visible, preventing it from hijacking the camera from other scenes (e.g., login screen).
	if is_instance_valid(map_camera):
		map_camera.enabled = false

	# --- Explicitly try to get map_renderer_node for detailed diagnostics ---
	var path_to_map_renderer = NodePath("MapRendererLogic") # Updated path
	if has_node(path_to_map_renderer):
		map_renderer_node = get_node(path_to_map_renderer) # Assign to the class variable
		if not is_instance_valid(map_renderer_node):
			printerr("Main (_ready): Found node at path 'MapRendererLogic' BUT IT'S NOT A VALID INSTANCE. Node: ", map_renderer_node)
			map_renderer_node = null # Ensure it's null if invalid
		else:
			# print("Main (_ready): Successfully got map_renderer_node. Path: MapRendererLogic. Instance: ", map_renderer_node)
			if map_renderer_node.get_script() == null:
				printerr("Main (_ready): map_renderer_node (at 'MapRendererLogic') HAS NO SCRIPT ATTACHED!")
			else:
				var script_path = map_renderer_node.get_script().resource_path
				# print("Main (_ready): map_renderer_node (at 'MapRendererLogic') script path: ", script_path)
				if not script_path.ends_with("map_render.gd"):
					printerr("Main (_ready): WARNING - map_renderer_node (at 'MapRendererLogic') has script '", script_path, "' but expected 'map_render.gd'.")
	else:
		printerr("Main (_ready): Node NOT FOUND at path 'MapRendererLogic' relative to %s." % self.get_path())
		# var parent_node = get_parent() # This part of the diagnostic is less relevant if it's a direct child
		# if not is_instance_valid(parent_node):
		# 	printerr("Main (_ready): This node (%s) does not have a valid parent. Path '../MapRendererLogic' cannot be resolved." % self.get_path())
		# else:
		# 	printerr("Main (_ready): Parent node is: %s (%s)." % [parent_node.name, parent_node.get_path()])
		# 	printerr("Main (_ready): Children of parent '%s':" % parent_node.name)
		# 	for child in parent_node.get_children():
		# 		printerr("  - Child: '%s' (Type: %s)" % [child.name, child.get_class()])
		# 	if not parent_node.has_node("MapRendererLogic"):
		# 		printerr("Main (_ready): Parent node '%s' does NOT have a child named 'MapRendererLogic'. Check spelling/hierarchy." % parent_node.name)
		map_renderer_node = null # Ensure it's null if not found

	# Get reference to MenuManager (adjust path if GameRoot node name is different)
	# Using an absolute path from the scene root for robustness.
	# Assumes your main scene root is named "GameRoot" and MenuManager is at "/root/GameRoot/MenuUILayer/MenuManager"
	var absolute_menu_manager_path = "/root/GameRoot/MenuUILayer/MenuManager" # Ensure this is the correct absolute path
	menu_manager_ref = get_node_or_null(absolute_menu_manager_path)
	
	if is_instance_valid(menu_manager_ref):
		if menu_manager_ref.has_signal("menu_opened"):
			menu_manager_ref.menu_opened.connect(_on_menu_opened_for_camera_focus)
		else:
			printerr("Main (MapView): MenuManager found but does not have 'menu_opened' signal.")
		if menu_manager_ref.has_signal("menus_completely_closed"): # Ensure this signal name matches MenuManager
			menu_manager_ref.menus_completely_closed.connect(_on_all_menus_closed)
		# print("Main (MapView): Successfully got reference to MenuManager.")
	else:
		printerr("Main (MapView): Could not find MenuManager. Path: GameRoot/MenuUILayer/MenuManager from this node's grandparent.")

	# Ensure nodes are valid
	if not is_instance_valid(map_camera): # No change here
		printerr("Main: MapCamera node not found or invalid. Path used: $MapCamera")
	if not is_instance_valid(map_renderer_node):
		# The detailed error is now printed by the explicit get_node block above.
		printerr("Main: map_renderer_node is STILL NOT VALID after explicit get_node. Check previous errors for details.")
	if not is_instance_valid(map_display):
		printerr("Main: MapDisplay node not found or invalid. Path used: $MapContainer/MapDisplay")
	if not is_instance_valid(map_container):
		printerr("Main: MapContainer node not found or invalid. Path used: $MapContainer")
	if not is_instance_valid(ui_manager):
		printerr("Main: UIManager node not found or invalid. Path used: $ScreenSpaceUI/UIManagerNode")
	if not is_instance_valid(map_interaction_manager):
		printerr("Main: MapInteractionManager node not found or invalid. Path used: $MapInteractionManager")
	if not is_instance_valid(convoy_visuals_manager):
		printerr("Main: ConvoyVisualsManager node not found or invalid. Path used: $ConvoyVisualsManager")

	# --- Connect to GameDataManager signals ---
	var gdm_node = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm_node):
		# print("Main: Found GameDataManager via get_node('/root/GameDataManager').")
		# Check against Engine.has_singleton for diagnostics
		if Engine.has_singleton("GameDataManager"):
			# print("Main: Engine.has_singleton('GameDataManager') is also TRUE.")
			if gdm_node != GameDataManager: # This should ideally not happen
				printerr("Main: CRITICAL - Node at /root/GameDataManager is NOT the same as global GameDataManager singleton!")
		else:
			# printerr("Main: WARNING - Engine.has_singleton('GameDataManager') is FALSE, but /root/GameDataManager exists.")
			pass

		# Connect signals using the gdm_node reference
		gdm_node.map_data_loaded.connect(_on_gdm_map_data_loaded) # Corrected signal name
		gdm_node.settlement_data_updated.connect(_on_gdm_settlement_data_updated)
		gdm_node.convoy_data_updated.connect(_on_gdm_convoy_data_updated)
		gdm_node.convoy_selection_changed.connect(_on_gdm_convoy_selection_changed)
	else:
		printerr("Main: GameDataManager Autoload NOT FOUND via get_node('/root/GameDataManager') AND Engine.has_singleton was likely false too. Core data will not be loaded.")




	# Instantiate the map renderer
	# Ensure the MapDisplay TextureRect scales its texture nicely
	if map_display:
		map_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# print('Main: map_display found and stretch_mode set.')  # DEBUG
		# Explicitly set texture filter for smoother scaling.
		map_display.mouse_filter = Control.MOUSE_FILTER_IGNORE # Allow mouse events to pass through for panning/interaction
		map_display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

		var theme_font_for_ui = map_display.get_theme_font("font", "Label") # Get font from a Control node

		# Label containers and settings are now managed by UIManager.gd
		if not is_instance_valid(ui_manager):
			printerr("Main: UIManager node not found or invalid. UI will not function correctly. Path used: $UIManagerNode")
		else:
			# print("Main: UIManager node found: ", ui_manager)
			if ui_manager.has_method("initialize_font_settings"):
				ui_manager.initialize_font_settings(theme_font_for_ui)
			else:
				printerr("Main: UIManager does not have initialize_font_settings method.")
			# If UIManager had signals for drag events that main.gd needed to react to,
			# you would connect them here. For now, main.gd calls UIManager methods directly
			if ui_manager is CanvasItem: # Node2D inherits from CanvasItem
				ui_manager.visible = true # Explicitly set UIManagerNode to visible
			# for drag state, so direct signal connections from UIManager back to main might not be needed
			# for the drag functionality itself.

	# --- Settlement data extraction is now handled by GameDataManager ---
	# Also get the initial convoy_id_to_color_map from the GameDataManager node
	# Re-check gdm_node validity here as well
	gdm_node = get_node_or_null("/root/GameDataManager") # Re-fetch or use the one from above if in same scope
	if is_instance_valid(gdm_node) and gdm_node.has_method("get_convoy_id_to_color_map"):
		_convoy_id_to_color_map = gdm_node.get_convoy_id_to_color_map()
		# print("Main: Successfully got convoy_id_to_color_map from GameDataManager (via get_node).")
	else:
		# This error message will now also cover the case where gdm_node itself is invalid.
		printerr("Main: GameDataManager Autoload invalid or missing 'get_convoy_id_to_color_map' method. Convoy colors may not be initialized.")

	# Initial setup of static map and camera will be triggered by GameDataManager.map_data_loaded
	if not is_instance_valid(map_interaction_manager):
		printerr("Main: MapInteractionManager node not found or invalid. Interaction will not work. Path used: $MapInteractionManager")
	else:
		# Defer initialization until map data is loaded. Connect signals now.
		if map_interaction_manager.has_method("initialize"): # Check for method existence before connecting
			map_interaction_manager.hover_changed.connect(_on_mim_hover_changed)
			map_interaction_manager.selection_changed.connect(_on_mim_selection_changed)
			map_interaction_manager.panel_drag_started.connect(_on_mim_panel_drag_started)
			map_interaction_manager.panel_drag_updated.connect(_on_mim_panel_drag_updated)
			map_interaction_manager.panel_drag_ended.connect(_on_mim_panel_drag_ended)
			map_interaction_manager.camera_zoom_changed.connect(_on_mim_camera_zoom_changed)
			map_interaction_manager.convoy_menu_requested.connect(_on_mim_convoy_menu_requested) # New connection
		else:
			printerr("Main: MapInteractionManager does not have initialize method.")

	# --- Initialize ConvoyVisualsManager ---
	if is_instance_valid(convoy_visuals_manager) and convoy_visuals_manager.has_method("initialize"):
		convoy_visuals_manager.initialize(map_container, map_renderer_node)
		# print("Main: ConvoyVisualsManager initialized.")
	else:
		printerr("Main: ConvoyVisualsManager node not found or invalid. Path used: $ConvoyVisualsManager")


	# map_display is now child of map_container, its position is (0,0) relative to map_container
	# its size is set above to _map_base_width_pixels, _map_base_height_pixels

	# Set Z-indices for global drawing order
	# Higher z_index is drawn on top.
	if is_instance_valid(map_display):
		map_display.z_index = MAP_DISPLAY_Z_INDEX # Base map layer
	if is_instance_valid(ui_manager) and ui_manager is CanvasItem: # Node2D inherits from CanvasItem
		ui_manager.z_index = 1 # UI Manager and its labels on top of the map
	if is_instance_valid(detailed_view_toggle):
		detailed_view_toggle.z_index = 2 # Toggle on top of UI Manager
	if is_instance_valid(_refresh_notification_label): # This was already high, which is good.
		_refresh_notification_label.z_index = 10 # Ensure notification is on top of everything

	# _update_map_display(true) is now handled by _setup_static_map_and_camera

	# Connect to the viewport's size_changed signal to re-render on window resize
	# This connection should happen regardless of GameTimersNode validity

	if not Engine.is_editor_hint(): # Don't run these in editor tool mode
		# Connection to APICallsInstance is now handled by GameDataManager
		# The _on_convoy_data_received method in main.gd will be replaced by _on_gdm_convoy_data_updated

		# Setup the refresh notification label (only for game, not editor preview)
		_refresh_notification_label = Label.new()
		_refresh_notification_label.text = 'Data Refreshed!'
		_refresh_notification_label.add_theme_font_size_override('font_size', 24)
		_refresh_notification_label.add_theme_color_override('font_color', Color.LIGHT_GREEN)
		_refresh_notification_label.add_theme_color_override('font_outline_color', Color.BLACK)
		_refresh_notification_label.add_theme_constant_override('outline_size', 2)
		_refresh_notification_label.modulate.a = 0.0  # Start invisible
		_refresh_notification_label.z_index = 10
		_refresh_notification_label.name = 'RefreshNotificationLabel'
		add_child(_refresh_notification_label)
		_update_refresh_notification_position()

		# Connect to GameTimers signals
		if is_instance_valid(game_timers_node):
			if game_timers_node.has_signal("data_refresh_tick"):
				game_timers_node.data_refresh_tick.connect(_on_data_refresh_tick) # Corrected signal name
				# print("Main: Connected to GameTimers.data_refresh_tick")
			else:
				printerr("Main: GameTimersNode does not have 'data_refresh_tick' signal.")
			if game_timers_node.has_signal("visual_update_tick"): # Corrected signal name
				game_timers_node.visual_update_tick.connect(_on_visual_update_tick)
				# print("Main: Connected to GameTimers.visual_update_tick")
			else:
				printerr("Main: GameTimersNode does not have 'visual_update_tick' signal.")
		else:
			printerr("Main: GameTimersNode not found or invalid. Timed updates will not work.")

	# Connect to the viewport's size_changed signal to re-render on window resize
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	# Ensure the MapViewportContainer (parent of this MapRender node) allows mouse events to pass through.
	# This is crucial for clicks to reach main.gd when a menu (on a higher CanvasLayer) is open
	# and has mouse_filter = PASS.
	var mvc = get_parent()
	if mvc is SubViewportContainer:
		# Connect to the UserInfoDisplay's signal for opening convoy menus.
		# Using find_child is more robust than a hardcoded path.
		var user_info_display_node = find_child("UserInfoDisplay", true, false)
		if is_instance_valid(user_info_display_node):
			# The container to measure is the parent of the HBox, which provides the visual "bar"
			top_nav_bar_container = user_info_display_node.get_parent()
			if not is_instance_valid(top_nav_bar_container):
				# Fallback in case UserInfoDisplay has no parent container, though it should.
				top_nav_bar_container = user_info_display_node

			if not user_info_display_node.is_connected("convoy_menu_requested", _on_user_info_display_convoy_menu_requested):
				user_info_display_node.convoy_menu_requested.connect(_on_user_info_display_convoy_menu_requested)
				print("[DIAGNOSTIC_LOG | main.gd] Successfully connected to UserInfoDisplay.convoy_menu_requested signal.")
		else:
			printerr("Main (_ready): Could not find UserInfoDisplay node to connect 'convoy_menu_requested' signal.")
			top_nav_bar_container = null # Ensure it's null if the contents aren't found

		mvc.mouse_filter = Control.MOUSE_FILTER_PASS
		# print("Main: Set MapViewportContainer mouse_filter to PASS.") # DEBUG
	# --- Setup Detailed View Toggle ---
	if is_instance_valid(detailed_view_toggle):
		detailed_view_toggle.button_pressed = show_detailed_view # Set initial state
		_update_detailed_view_toggle_position() # Set initial position
		detailed_view_toggle.toggled.connect(_on_detailed_view_toggled)
		# print('Main: Detailed View toggle initialized and connected.')
	else:
		printerr('Main: DetailedViewToggleCheckbox node not found or invalid. Check the path in main.gd.')

	# Defer initial layout until the node is visible to avoid interfering with other scenes (like a login screen).
	# _on_viewport_size_changed()
	_is_ready = true
	print("[DIAGNOSTIC_LOG | main.gd] _ready(): Finished. _is_ready is now true.")

func _focus_camera_on_convoy_or_route(convoy_world_position: Vector2, zoom_scalar: float):
	# Center the convoy in the visible map area (map viewport)
	var map_viewport_rect_global: Rect2 = get_map_viewport_container_global_rect()
	var map_viewport_center_world: Vector2 = map_viewport_rect_global.position + map_viewport_rect_global.size / 2.0
	print("[DIAGNOSTIC_LOG | main.gd] _focus_camera_on_convoy_or_route:")
	print("  - map_viewport_rect_global: position = %s, size = %s" % [map_viewport_rect_global.position, map_viewport_rect_global.size])
	print("  - map_viewport_center_world: %s" % map_viewport_center_world)
	print("  - convoy_world_position: %s" % convoy_world_position)
	print("  - zoom_scalar: %s" % zoom_scalar)

	var camera_target_world: Vector2 = convoy_world_position
	# If a convoy menu is open, offset the camera so the convoy appears in the center of the left 1/3rd
	if is_instance_valid(menu_manager_ref) and menu_manager_ref.has_method("is_any_menu_active") and menu_manager_ref.is_any_menu_active():
		var offset_x = map_viewport_rect_global.size.x * (1.0 / 3.0) * 0.5
		map_viewport_center_world = map_viewport_rect_global.position + Vector2(offset_x, map_viewport_rect_global.size.y * 0.5)
		var delta = convoy_world_position - map_viewport_center_world
		# Center the camera so the convoy appears at the center of the left 1/3rd
		camera_target_world = map_viewport_rect_global.position + Vector2(offset_x, map_viewport_rect_global.size.y * 0.5) + delta
		print("  - camera_target_world (offset for menu): %s" % camera_target_world)
	else:
		print("  - camera_target_world (direct): %s" % camera_target_world)

	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("focus_camera_and_set_zoom"):
		map_interaction_manager.focus_camera_and_set_zoom(camera_target_world, zoom_scalar)
	else:
		printerr("Main: MapInteractionManager invalid or missing focus_camera_and_set_zoom method.")

func _get_bounding_box_for_points(points: Array) -> Rect2:
	# Returns a Rect2 that bounds all Vector2 points in the array
	if points.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var min_x = points[0].x
	var max_x = points[0].x
	var min_y = points[0].y
	var max_y = points[0].y
	for pt in points:
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


# Focus the camera to fit a journey (array of Vector2 points) in view, with optional left-1/3 offset if menu is open

# Focus the camera to fit a journey (array of Vector2 points) in view, with optional left-1/3 offset if menu is open
func _focus_camera_on_journey(journey_points: Array, extra_padding: float = 32.0):
	print("[DEBUG] _focus_camera_on_journey called. journey_points.size = %s" % journey_points.size())
	print("[DEBUG] journey_points: %s" % journey_points)
	if journey_points.is_empty():
		print("[DEBUG] journey_points is empty, aborting.")
		return

	# Convert journey points from tile coordinates to world coordinates
	var world_points: Array = []
	if not map_tiles.is_empty() and is_instance_valid(map_display):
		var map_cols: int = map_tiles[0].size()
		var map_rows: int = map_tiles.size()
		var map_size: Vector2 = map_display.custom_minimum_size
		print("[DEBUG] map_cols: %s, map_rows: %s, map_size: %s" % [map_cols, map_rows, map_size])
		var tile_w: float = map_size.x / float(map_cols)
		var tile_h: float = map_size.y / float(map_rows)
		print("[DEBUG] tile_w: %s, tile_h: %s" % [tile_w, tile_h])
		for pt in journey_points:
			# Assume pt is in tile coordinates
			var world_pt = Vector2((pt.x + 0.5) * tile_w, (pt.y + 0.5) * tile_h)
			world_points.append(world_pt)
		print("[DEBUG] Converted journey_points to world_points: %s" % world_points)
	else:
		print("[DEBUG] map_tiles or map_display invalid, aborting.")
		return

	var bbox := _get_bounding_box_for_points(world_points)
	print("[DEBUG] world_points bbox: %s" % bbox)
	if bbox.size.x < 0.01 or bbox.size.y < 0.01:
		bbox = Rect2(bbox.position - Vector2(1,1), bbox.size + Vector2(2,2))
		print("[DEBUG] bbox was too small, expanded to: %s" % bbox)

	# Always use the left 1/3 of the map viewport as the visible map rect
	var visible_map_rect: Rect2 = get_left_third_map_viewport_rect()
	print("[DEBUG] Using left_third_map_viewport_rect for visible_map_rect: %s" % visible_map_rect)
	if visible_map_rect.size.x < 1 or visible_map_rect.size.y < 1:
		print("[DEBUG] visible_map_rect is too small, aborting.")
		return


	var bbox_with_padding = bbox.grow(extra_padding)
	print("[DEBUG] bbox_with_padding: %s" % bbox_with_padding)

	# --- Camera loose mode logic ---
	# Get the map bounds in world coordinates
	var map_bounds: Rect2 = Rect2(Vector2.ZERO, Vector2.ZERO)
	if is_instance_valid(map_display) and is_instance_valid(map_display.texture):
		map_bounds = Rect2(Vector2(0, 0), map_display.custom_minimum_size)

	# --- Camera loose mode logic and camera/zoom calculation ---
	var scale_x = visible_map_rect.size.x / bbox_with_padding.size.x
	var scale_y = visible_map_rect.size.y / bbox_with_padding.size.y
	var unclamped_zoom = min(scale_x, scale_y)
	print("[DEBUG] scale_x: %s, scale_y: %s, unclamped_zoom: %s" % [scale_x, scale_y, unclamped_zoom])

	var mcc = map_interaction_manager.get_node_or_null("MapCameraController") if is_instance_valid(map_interaction_manager) else null
	var min_zoom = 0.05
	var max_zoom = 5.0
	if mcc and "min_camera_zoom_level" in mcc and "max_camera_zoom_level" in mcc:
		min_zoom = mcc.min_camera_zoom_level
		max_zoom = mcc.max_camera_zoom_level
	var target_zoom = clamp(unclamped_zoom, min_zoom, max_zoom)
	print("[DEBUG] min_zoom: %s, max_zoom: %s, target_zoom (clamped): %s" % [min_zoom, max_zoom, target_zoom])

	var bbox_center = bbox_with_padding.position + bbox_with_padding.size * 0.5
	var viewport_size_world = visible_map_rect.size / target_zoom
	var min_x = map_bounds.position.x + viewport_size_world.x * 0.5
	var max_x = map_bounds.position.x + map_bounds.size.x - viewport_size_world.x * 0.5
	var min_y = map_bounds.position.y + viewport_size_world.y * 0.5
	var max_y = map_bounds.position.y + map_bounds.size.y - viewport_size_world.y * 0.5
	var clamped_x = clamp(bbox_center.x, min_x, max_x)
	var clamped_y = clamp(bbox_center.y, min_y, max_y)
	var clamped_camera_pos = Vector2(clamped_x, clamped_y)

	var left_third_rect = get_left_third_world_rect(clamped_camera_pos, visible_map_rect.size / target_zoom)
	print("[DEBUG] left_third_rect for clamped camera: %s" % left_third_rect)

	var journey_fits_in_left_third := left_third_rect.encloses(bbox_with_padding)
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("set_camera_loose_mode"):
		map_interaction_manager.set_camera_loose_mode(not journey_fits_in_left_third)

	# --- LOGGING: Camera and zoom logic ---
	var bbox_top_left = bbox_with_padding.position
	var bbox_size = bbox_with_padding.size
	var map_size: Vector2 = map_display.custom_minimum_size if is_instance_valid(map_display) else Vector2(0,0)
	var viewport_size = get_viewport().size
	print("[DEBUG] map_size: %s, viewport_size: %s" % [map_size, viewport_size])
	var camera_center : Vector2
	var camera_view_size : Vector2

	# Always use left third logic for zoom
	var zoom_x = viewport_size.x / (3.0 * bbox_size.x)
	var zoom_y = viewport_size.y / bbox_size.y
	var zoom = clamp(min(zoom_x, zoom_y), min_zoom, max_zoom)
	print("[DEBUG] left_third zoom_x: %s, zoom_y: %s, zoom: %s" % [zoom_x, zoom_y, zoom])
	camera_view_size = viewport_size / zoom
	print("[DEBUG] left_third camera_view_size: %s" % camera_view_size)
	# Center camera on journey bbox as usual
	var camera_center_x = bbox_top_left.x + bbox_size.x / 2.0
	var camera_center_y = bbox_top_left.y + bbox_size.y / 2.0
	# If menu is open, offset camera 33% of viewport width to the right (in world units)
	var menu_open = is_instance_valid(menu_manager_ref) and menu_manager_ref.has_method("is_any_menu_active") and menu_manager_ref.is_any_menu_active()
	if menu_open:
		var offset_world = camera_view_size.x * (1.0/3.0)
		camera_center_x += offset_world
		print("[DEBUG] menu_open: offsetting camera_center_x by %s (world units)" % offset_world)
	print("[DEBUG] camera_center_x: %s, camera_center_y: %s" % [camera_center_x, camera_center_y])
	camera_center = Vector2(camera_center_x, camera_center_y)
	print("[DEBUG] camera_center (after menu offset): %s, zoom = %s" % [camera_center, zoom])
	target_zoom = zoom

	print("[DEBUG] bbox_top_left: %s, bbox_size: %s, camera_view_size: %s" % [bbox_top_left, bbox_size, camera_view_size])
	print("[DEBUG] camera_center (before clamping): %s" % camera_center)

	# Clamp camera position to map bounds (using map_display size) ONLY if menu is closed
	var unclamped_camera_center = camera_center
	if not menu_open:
		var min_camera_pos = camera_view_size * 0.5
		var max_camera_pos = map_size - camera_view_size * 0.5
		print("[DEBUG] min_camera_pos: %s, max_camera_pos: %s" % [min_camera_pos, max_camera_pos])
		camera_center.x = clamp(camera_center.x, min_camera_pos.x, max_camera_pos.x)
		camera_center.y = clamp(camera_center.y, min_camera_pos.y, max_camera_pos.y)
		print("[DEBUG] camera_center (after clamping): %s (unclamped: %s)" % [camera_center, unclamped_camera_center])
		if camera_center != unclamped_camera_center:
			print("[DEBUG] Camera center was clamped to map bounds.")

	# --- FINAL: Actually move/zoom the camera ---
	print("[DEBUG] Setting camera position to: %s, zoom: %s" % [camera_center, target_zoom])
	if is_instance_valid(map_camera):
		map_camera.position = camera_center
		map_camera.zoom = Vector2(target_zoom, target_zoom)
		print("[DEBUG] map_camera.position now: %s, map_camera.zoom: %s" % [map_camera.position, map_camera.zoom])
	else:
		print("[DEBUG] map_camera is not valid!")

# Helper: Get the world rect of the left third of the camera's view for a given center and view size
func get_left_third_world_rect(center: Vector2, view_size: Vector2) -> Rect2:
	var cam_rect = Rect2(center - view_size * 0.5, view_size)
	return Rect2(cam_rect.position, Vector2(view_size.x / 3.0, view_size.y))

## Helper: Get the left 1/3rd of the map viewport in global coordinates
func get_left_third_map_viewport_rect() -> Rect2:
	if not is_instance_valid(map_display):
		return Rect2(0,0,0,0)
	var global_rect = map_display.get_global_rect()
	var left_third = Rect2(global_rect.position, Vector2(global_rect.size.x / 3.0, global_rect.size.y))
	return left_third

# Helper: Compute bounding box for an array of Vector2 points
## Duplicate removed: Only one _get_bounding_box_for_points should exist


func _on_ui_scale_changed(_new_scale: float):
	# Force camera bounds update when UI scale changes
	if is_instance_valid(map_camera) and map_camera.has_method("force_bounds_update"):
		map_camera.force_bounds_update()

func _notification(what: int) -> void:
	# This is a critical log to see if the scene is ever made visible.
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		print("[DIAGNOSTIC_LOG | main.gd] _notification(): VISIBILITY_CHANGED received. is_visible_in_tree() = %s, _view_is_initialized = %s, _is_ready = %s" % [is_visible_in_tree(), _view_is_initialized, _is_ready])
		if is_visible_in_tree() and not _view_is_initialized and _is_ready:
			# This block runs only the first time the node becomes visible.
			_view_is_initialized = true
			print("[DIAGNOSTIC_LOG | main.gd] _notification(): View is visible for the first time (after _ready). Calling _initialize_view().")
			_initialize_view()

func _initialize_view() -> void:
	"""
	Performs setup that should only happen once the view is visible.
	It now checks if map data has been preloaded.
	"""
	print("[DIAGNOSTIC_LOG | main.gd] _initialize_view(): Performing initial setup (activating camera, setting UI positions).")
	if is_instance_valid(map_camera):
		print("  - Making map_camera current.")
		map_camera.enabled = true # Explicitly re-enable the camera
		map_camera.make_current()
	_on_viewport_size_changed() # Set initial positions of UI elements.
	
	# --- Check for preloaded map data ---
	# The request is now initiated by GameDataManager on game start.
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.map_tiles.is_empty():
			print("[DIAGNOSTIC_LOG | main.gd] _initialize_view(): Map data was already preloaded. Setting up map immediately.")
			_on_gdm_map_data_loaded(gdm.map_tiles)
		else:
			print("[DIAGNOSTIC_LOG | main.gd] _initialize_view(): Map data not yet preloaded. Waiting for 'map_data_loaded' signal.")
	else:
		printerr("[DIAGNOSTIC_LOG | main.gd] _initialize_view(): GameDataManager not found. CANNOT check for map data.")

func _on_gdm_map_data_loaded(p_map_tiles: Array):
	map_tiles = p_map_tiles
	# print("Main: Received map_data_loaded from GameDataManager. Tile rows: %s" % map_tiles.size())
	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		printerr('[DIAGNOSTIC_LOG | main.gd] _on_gdm_map_data_loaded(): Map tiles data from GameDataManager is EMPTY or INVALID. Cannot proceed to setup static map.')
		return
	
	_setup_static_map_and_camera() # Now that map_tiles are available

	# Initialize MapInteractionManager now that we have the map data
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("initialize"):
		print("[DIAGNOSTIC_LOG | main.gd] Initializing MapInteractionManager with loaded map data.")
		map_interaction_manager.initialize(
			map_display,
			ui_manager,
			_all_convoy_data, # Pass current convoy data (might be empty, will be updated)
			_all_settlement_data, # Pass current settlement data
			map_tiles, # CRITICAL: Pass the now-loaded map_tiles
			map_camera,
			map_display,
			_selected_convoy_ids,
			_convoy_label_user_positions
		)
	# The old update_data_references call is now redundant as initialize handles it.


func _on_gdm_settlement_data_updated(p_settlement_data: Array):
	_all_settlement_data = p_settlement_data
	# print("Main: Received settlement_data_updated from GameDataManager. Count: %s" % _all_settlement_data.size())
	# Update MapInteractionManager
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("update_data_references"):
		map_interaction_manager.update_data_references(_all_convoy_data, _all_settlement_data, map_tiles)
	# Potentially trigger a UI update if settlements are displayed immediately
	# _update_map_display(false) # false = don't rerender map texture, only UI
	if not is_instance_valid(map_renderer_node) or not is_instance_valid(map_display) or not is_instance_valid(map_camera):
		printerr("[DIAGNOSTIC_LOG | main.gd] _setup_static_map_and_camera(): ABORTING - Essential nodes (map_renderer_node, map_display, or map_camera) not ready.")
		if not is_instance_valid(map_renderer_node): printerr("  - map_renderer_node is invalid.")
		if not is_instance_valid(map_display): printerr("  - map_display is invalid.")
		if not is_instance_valid(map_camera): printerr("  - map_camera is invalid.")
		return
	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		printerr("[DIAGNOSTIC_LOG | main.gd] _setup_static_map_and_camera(): ABORTING - map_tiles data is empty or invalid.")
		return

func _setup_static_map_and_camera():
	print("[DIAGNOSTIC_LOG | main.gd] _setup_static_map_and_camera(): Starting map texture generation.")

	# print("Main: _setup_static_map_and_camera - Starting map texture generation.") # DEBUG
	var map_rows_local = map_tiles.size()
	var map_cols_local = map_tiles[0].size()
	var tile_pixel_size: float = map_renderer_node.base_tile_size_for_proportions

	if tile_pixel_size <= 0.001: # Check for zero or very small value
		printerr("Main: CRITICAL - map_renderer_node.base_tile_size_for_proportions is %s (<= 0.001)." % tile_pixel_size)
		printerr("Main: This will lead to a zero-sized map and likely an 'affine_invert' error.")
		printerr("Main: Please ensure 'base_tile_size_for_proportions' is set to a positive value on the MapRendererLogic node in the editor.")
		tile_pixel_size = 24.0 # Fallback to a sensible default to prevent crash, but the root cause should be fixed in editor.
		printerr("Main: Fallback: Using default tile_pixel_size for calculations: %s" % tile_pixel_size)

	if tile_pixel_size <= 0:
		printerr("Main: base_tile_size_for_proportions is invalid (<=0). Cannot calculate map texture size.")
		return

	var full_map_width_px = map_cols_local * tile_pixel_size
	var full_map_height_px = map_rows_local * tile_pixel_size
	var render_viewport_for_full_map = Vector2(full_map_width_px, full_map_height_px)

	print("[DIAGNOSTIC_LOG | main.gd] _setup_static_map_and_camera(): Calling map_renderer_node.render_map() with target size: %s" % render_viewport_for_full_map)
	var static_render_result: Dictionary = map_renderer_node.render_map(
		map_tiles,
		[], # highlights (empty for base static map)
		[], # lowlights (empty for base static map)
		Color(0,0,0,0), # p_highlight_color_override (no longer passes convoy data)
		Color(0,0,0,0), # p_lowlight_color_override (no longer passes convoy data)
		render_viewport_for_full_map, # CRITICAL: Full map dimensions
		# Removed convoy related parameters:
		# p_convoys_data, p_throb_phase, p_convoy_id_to_color_map,
		# p_hover_info (UIManager handles labels), p_selected_convoy_ids (UIManager handles labels)
		show_detailed_view, # p_show_grid (use current setting for initial render)
		show_detailed_view, # p_show_political (use current setting for initial render)
		false, # p_render_highlights_lowlights - false for static base
		# p_render_convoys is removed from map_render.gd
	)

	if static_render_result and static_render_result.has("texture") and is_instance_valid(static_render_result.texture):
		var static_map_texture: ImageTexture = static_render_result.texture
		map_display.texture = static_map_texture
		map_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		map_display.custom_minimum_size = static_map_texture.get_size()
		print("[DIAGNOSTIC_LOG | main.gd] _setup_static_map_and_camera(): SUCCESS - Static map texture applied to MapDisplay. Size: %s" % map_display.custom_minimum_size)
	else: # Covers null or invalid static_map_texture
		printerr("[DIAGNOSTIC_LOG | main.gd] _setup_static_map_and_camera(): FAILED - map_renderer_node.render_map() did not return a valid texture.")
		return

	# Initialize Camera
	# map_camera.make_current() # This is now deferred to _initialize_view()
	# Set camera's position (center) to the center of the map_display content,
	# considering map_container's position within MapRender.
	if is_instance_valid(map_container) and is_instance_valid(map_display):
		# Original line to center camera on the map:
		# map_camera.position = map_container.position + map_display.custom_minimum_size / 2.0
		
		# New line to position camera view at the top-left of the map content:
		# The camera's position is its center. To see the map's top-left at the viewport's top-left:
		map_camera.position = map_container.position + (map_camera.get_viewport_rect().size / (2.0 * map_camera.zoom))
	map_camera.offset = Vector2.ZERO # Screen-space offset, keep at zero for primary positioning.
	map_camera.zoom = Vector2(1.0, 1.0) # Initial zoom
	_map_and_ui_setup_complete = true # Set flag after setup
	# Process any deferred convoy data now that setup is complete
	if not _deferred_convoy_data.is_empty():
		# print("Main: Processing deferred convoy data.")
		_on_gdm_convoy_data_updated(_deferred_convoy_data) # Call the handler with stored data
		_deferred_convoy_data.clear() # Clear after processing
	# Camera limits will be handled by MapInteractionManager's _constrain_camera_offset	
	_update_map_display(false) # Perform an initial UI update without re-rendering the map texture



func _on_viewport_size_changed():
	# print('Main: _on_viewport_size_changed triggered.') # DEBUG

	# MapView's camera should always be centered in its own viewport.
	# The ViewportContainer handles where this viewport is shown on the main screen.
	if is_instance_valid(map_camera):
		map_camera.offset = Vector2.ZERO # Camera offset is relative to its viewport center

	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("_handle_viewport_resize_constraints"):
		map_interaction_manager._handle_viewport_resize_constraints() # Tell MIM to re-apply camera and zoom constraints
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("set_current_map_screen_rect"):
		# MIM needs the screen rect *where the map is visible* for mouse coord conversion.
		# This should be the global rect of the MapViewportContainer.
		map_interaction_manager.set_current_map_screen_rect(get_map_viewport_container_global_rect())

	if not Engine.is_editor_hint() and is_instance_valid(_refresh_notification_label): # Only update in game
		_update_refresh_notification_position()
	if is_instance_valid(detailed_view_toggle):
		_update_detailed_view_toggle_position()

	# _apply_map_camera_and_ui_layout() is simplified as camera offset is now simpler.

func get_map_viewport_container_global_rect() -> Rect2:
	var mvc = get_parent() # Assuming MapView is direct child of MapViewportContainer
	if mvc is SubViewportContainer: # This check is correct for Godot 4
		return mvc.get_global_rect()
	return get_viewport().get_visible_rect() # Fallback if MapView isn't in a ViewportContainer


var _last_route_preview_data: Dictionary = {}

func _update_map_display(force_rerender_map_texture: bool = true, is_light_ui_update: bool = false):
	# --- FIX for Route Preview ---
	# If a call comes in to do a cheap update (force_rerender=false) while we are in a state
	# that has just requested an expensive update (_is_in_route_preview_mode=true), we must
	# ignore the cheap update. This prevents the visual tick's frequent call with `force_rerender=false`
	# from cancelling out the single, crucial `force_rerender=true` call needed to show the preview.
	if _is_in_route_preview_mode and not force_rerender_map_texture:
		return

	# If we are in route preview mode and have preview data, focus camera using the correct route logic
	if _is_in_route_preview_mode and typeof(_last_route_preview_data) == TYPE_DICTIONARY and not _last_route_preview_data.is_empty():
		_focus_camera_on_route(_last_route_preview_data)

	# print("Main: _update_map_display() CALLED - TOP") # DEBUG

	var render_result: Dictionary = {} # Declare at function scope to avoid 'locals()' which doesn't exist.

	# Get dragging state from MapInteractionManager if it's valid
	var is_currently_dragging: bool = false
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("is_dragging"):
		is_currently_dragging = map_interaction_manager.is_dragging()
	if is_currently_dragging:
		# If dragging a panel, we still need to update UI elements (like connector lines)
		# but we might skip re-rendering the main map texture.
		force_rerender_map_texture = false # Don't rerender map texture while dragging UI panel

	if map_tiles.is_empty():
		# printerr('Main: _update_map_display - Cannot update map display: map_tiles is empty. Returning.') # DEBUG - Can be noisy if data loads late
		return
	if not is_instance_valid(map_renderer_node):
		printerr('Main: _update_map_display - Cannot update map display: map_renderer_node is not valid. Returning.') # DEBUG
		return

	if not is_instance_valid(map_display): # Added safety check
		printerr('Main: _update_map_display - map_display is not valid. Cannot render. Returning.') # DEBUG
		return

	# print("Main: _update_map_display - Passed initial checks.") # DEBUG

	# --- Render the map ---
	# The size passed to render_map should be the MapDisplay's actual size (full map size)
	# This is now map_display.custom_minimum_size which holds the full texture dimensions
	var map_render_target_size = map_display.custom_minimum_size	
	if map_render_target_size.x == 0 or map_render_target_size.y == 0:
		# This might happen if _setup_static_map_and_camera hasn't run or failed
		# printerr("Main: _update_map_display - map_display.custom_minimum_size is zero. Cannot render. Returning.")
		return # Avoid rendering if the target size isn't set


	# Get current hover and selection from MapInteractionManager
	var hover_info_for_render = _current_hover_info # Use the one updated by signal
	var selected_ids_for_render = _selected_convoy_ids # Use the one updated by signal
	if is_instance_valid(map_interaction_manager): # Ensure MIM is valid before trying to get info
		if map_interaction_manager.has_method("get_current_hover_info"):
			hover_info_for_render = map_interaction_manager.get_current_hover_info()
		if map_interaction_manager.has_method("get_selected_convoy_ids"):
			selected_ids_for_render = map_interaction_manager.get_selected_convoy_ids()

	# print("Main: Calling map_renderer.render_map with show_detailed_view = %s" % show_detailed_view) # DEBUG
	# print('Main: Calling render_map with _current_hover_info: ', _current_hover_info)  # DEBUG
	# You can pass actual highlight/lowlight data here if you have it.
	if force_rerender_map_texture:
		# This part is for re-rendering dynamic elements INTO the main map texture.
		# For best performance with frequently changing elements, they should be separate nodes.
		var non_selected_highlights: Array = []
		var selected_highlights: Array = []
		# print("Main: force_rerender_map_texture is TRUE. Generating journey lines for ALL convoys. Selected IDs: ", _selected_convoy_ids) # DEBUG - Commented out

		for convoy_data_item in _all_convoy_data: # Iterate through ALL convoys
			if convoy_data_item is Dictionary and convoy_data_item.has("convoy_id") and convoy_data_item.has("journey"):
				var convoy_id_str = str(convoy_data_item.get("convoy_id"))
				var journey_data: Dictionary = {}
				var raw_journey = convoy_data_item.get("journey")
				if raw_journey is Dictionary:
					journey_data = raw_journey
				var is_selected: bool = _selected_convoy_ids.has(convoy_id_str)

				if journey_data is Dictionary: # Ensure journey_data is a dictionary
					var route_x: Array = journey_data.get("route_x", [])
					var route_y: Array = journey_data.get("route_y", [])
					# print("Main: Convoy ", convoy_id_str, " route_x size: ", route_x.size(), ", route_y size: ", route_y.size()) # DEBUG


					# Retrieve pre-calculated progress details from the augmented convoy_data_item
					var convoy_current_segment_start_index: int = convoy_data_item.get("_current_segment_start_idx", -1)
					var progress_within_current_segment: float = convoy_data_item.get("_progress_in_segment", 0.0)
					# The complex calculation block for these two variables is no longer needed here.

					var path_points: Array[Vector2] = []
					for i in range(route_x.size()):
						# Assuming route_x and route_y contain tile coordinates
						path_points.append(Vector2(float(route_x[i]), float(route_y[i])))
					# print("Main: Convoy ", convoy_id_str, " generated path_points count: ", path_points.size()) # DEBUG
					var base_convoy_color = _convoy_id_to_color_map.get(convoy_id_str, Color.GRAY) # Default to gray if not found

					if is_selected:
						# Create the selected line object
						var main_selected_line_obj = {
							"type": "journey_path",
							"convoy_id": convoy_id_str, # Ensure convoy_id is passed
							"points": path_points,
							"color": base_convoy_color.lightened(0.3), # Example: brighten selected lines
							"is_selected": true,
							# "width" property is removed; map_render.gd uses its own thickness settings
							"convoy_segment_start_idx": convoy_current_segment_start_index,
							"progress_in_current_segment": progress_within_current_segment
						}
						selected_highlights.append(main_selected_line_obj)
					else:
						# Create the non-selected line object
						var non_selected_line_obj = {
							"type": "journey_path",
							"convoy_id": convoy_id_str, # Ensure convoy_id is passed
							"points": path_points,
							"color": base_convoy_color.darkened(0.2), # Example: slightly darken non-selected
							"is_selected": false,
							# "width" property is removed; map_render.gd uses its own thickness settings
							"convoy_segment_start_idx": convoy_current_segment_start_index,
							"progress_in_current_segment": progress_within_current_segment
						}
						non_selected_highlights.append(non_selected_line_obj)
						# print("Main: Appended journey for convoy ", convoy_id_str, " (Selected: ", is_selected, ") to highlights_for_render.") # DEBUG
					# else:
						# print("Main: Convoy ", convoy_id_str, " journey data insufficient to form path.") #DEBUG
			# else:
				# print("Main: Skipping convoy item (no ID or journey): ", convoy_data_item) # DEBUG

		# Combine the lists, with selected highlights last to draw them on top
		var highlights_for_render: Array = []
		highlights_for_render.append_array(non_selected_highlights)
		highlights_for_render.append_array(selected_highlights)

		# NEW: Add route preview highlight if active. This is drawn on top of existing lines.
		if _is_in_route_preview_mode and not _route_preview_highlight_data.is_empty():
			var preview_line_obj = {
				"type": "journey_path", # Use the same type as other paths for consistent drawing
				"points": _route_preview_highlight_data,
				"color": Color.YELLOW.lightened(0.2), # A distinct, bright color for the preview
				"is_selected": true, # Use selected styling (e.g., thicker line)
				"is_preview": true # Custom flag in case map_render.gd wants to treat it differently
			}
			highlights_for_render.append(preview_line_obj)


		# print("Main: Final highlights_for_render before calling map_renderer_node.render_map: ", highlights_for_render) # DEBUG - Commented out, very verbose

		render_result = map_renderer_node.render_map(
			map_tiles,
			highlights_for_render,  # Pass the generated highlights for journey lines
			[],  # lowlights
			Color(0,0,0,0), # Let map_render use its own default highlight color
			Color(0,0,0,0), # Let map_render use its own default lowlight color
			map_render_target_size,    # Target size for the map texture (full map)
			show_detailed_view, # Pass detailed view flag for grid
			show_detailed_view, # Pass detailed view flag for political colors
			true # p_render_highlights_lowlights is true here
		)
		# print('Main: map_renderer.render_map call completed.')  # DEBUG

		# --- Display the map ---
		if render_result and render_result.has("texture") and is_instance_valid(render_result.texture):
			var map_texture: ImageTexture = render_result.texture
			# print('Main: map_texture is valid. Size: ', map_texture.get_size(), ' Format: ', map_texture.get_image().get_format() if map_texture.get_image() else 'N/A')  # DEBUG
			# Generate mipmaps for the texture if the TextureRect's filter uses them.
			# This improves quality when the texture is scaled down.
			if map_display and (map_display.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS or \
							   map_display.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS):
				# Ensure the texture actually has an image to work with
				if not is_instance_valid(map_texture.get_image()):
					printerr("Main: Map texture is valid, but its image data is not. Cannot generate mipmaps.")
					return # Or handle error appropriately
				var img := map_texture.get_image()
				if img:  # Ensure image is valid
					# print('Main: Generating mipmaps for map texture.')  # DEBUG
					img.generate_mipmaps()  # This modifies the image in-place; ImageTexture will update.
			map_display.texture = map_texture
			# No longer need to set map_display.set_size here, stretch_mode handles it.
			# print('Main: Map (re)rendered and displayed on map_display node.')  # DEBUG
		else:
			printerr('Failed to render map texture or result was invalid.')
			# If map texture failed, we probably shouldn't update convoy visuals based on it.
			# However, UI labels might still need an update.
			# For now, let's ensure icon_positions is empty if texture fails.
			# Removed unused/conflicting declaration of _icon_positions_from_render
			var icon_positions_from_render = {}
			if render_result and render_result.has("icon_positions"):
				icon_positions_from_render = render_result.get("icon_positions", {})

	# Call UIManager to update all UI elements (labels, connectors)
	# print("Main: _update_map_display - Preparing to call ui_manager.update_ui_elements.") # DEBUG
	# print("  - ui_manager valid: %s, map_display valid: %s, map_tiles empty: %s" % [is_instance_valid(ui_manager), is_instance_valid(map_display), map_tiles.is_empty()]) # DEBUG
	# print("  - Data counts: Convoys: %s, Settlements: %s" % [_all_convoy_data.size(), _all_settlement_data.size()]) # DEBUG
	# print("  - Hover: %s, Selected: %s" % [_current_hover_info, _selected_convoy_ids]) # DEBUG

	# Get necessary state from MapInteractionManager for UIManager
	# For drag state, use main.gd's own authoritative state variables.
	var dragging_panel_for_ui = self._dragging_panel_node
	var dragged_id_for_ui = self._dragged_convoy_id_actual_str
	var user_positions_for_ui = _convoy_label_user_positions # Default to main's copy

	if is_instance_valid(map_interaction_manager):
		if map_interaction_manager.has_method("get_convoy_label_user_positions"):
			# MIM is the authority for the latest user positions
			user_positions_for_ui = map_interaction_manager.get_convoy_label_user_positions()
			
	var current_camera_zoom_for_ui = 1.0
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("get_current_camera_zoom"):
		current_camera_zoom_for_ui = map_interaction_manager.get_current_camera_zoom()

	if is_instance_valid(ui_manager):
		# print("Main: _update_map_display - ui_manager IS VALID. CALLING update_ui_elements NOW.") # DEBUG
		ui_manager.update_ui_elements(
			map_display,
			map_tiles,
			_all_convoy_data,
			_all_settlement_data,
			_convoy_id_to_color_map,
			hover_info_for_render,
			selected_ids_for_render,
			user_positions_for_ui,      # Pass the up-to-date user positions
			dragging_panel_for_ui,      # Pass the currently dragged panel (or null)
			dragged_id_for_ui,          # Pass the ID of the currently dragged panel (or empty)
			get_map_viewport_container_global_rect(), # Pass the map's actual screen rect for UIManager clamping
			is_light_ui_update,         # Pass the light update flag
			current_camera_zoom_for_ui  # Pass the current zoom level
		) 
	# Now that UIManager has updated and cached its values, trigger the convoy visuals update.
	# This fixes the race condition where this was called before UIManager had valid tile dimensions.
	var icon_positions_from_render = {}
	if render_result and render_result.has("icon_positions"):
		icon_positions_from_render = render_result.get("icon_positions", {})
	_trigger_convoy_visuals_update(icon_positions_from_render)


func _on_gdm_convoy_data_updated(p_augmented_convoy_data: Array) -> void:
	if not _map_and_ui_setup_complete:
		# print("Main (_on_gdm_convoy_data_updated): Map and UI setup not yet complete. Deferring full convoy update.")
		# Optionally, store p_augmented_convoy_data and process it once _map_and_ui_setup_complete is true
		# For now, just return and wait for the next data update after setup.
		_deferred_convoy_data = p_augmented_convoy_data # Store it
		return
	# print('Main: Received convoy_data_updated from GameDataManager. Count: %s' % p_augmented_convoy_data.size())
	_all_convoy_data = p_augmented_convoy_data # Data is already augmented by GDM (colors, progress)
	
	# Update the local _convoy_id_to_color_map from GameDataManager
	var gdm_node_local = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm_node_local) and gdm_node_local.has_method("get_convoy_id_to_color_map"): # Check method existence too
		_convoy_id_to_color_map = gdm_node_local.get_convoy_id_to_color_map().duplicate(true)
	else:
		printerr("Main (_on_gdm_convoy_data_updated): GameDataManager not found or method missing for color map.")
		_convoy_id_to_color_map.clear() # Should not happen if GDM is set up

	# The _pixel_offset_for_icon calculation and shared_segments_data_for_icons
	# are now handled by ConvoyVisualsManager.augment_convoy_data_with_offsets
	
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("update_data_references"):
		map_interaction_manager.update_data_references(_all_convoy_data, _all_settlement_data, map_tiles)
	else:
		# Error messages for MIM update failure
		if not is_instance_valid(map_interaction_manager): printerr("Main (_on_gdm_convoy_data_updated): MIM instance NOT valid.")
		elif not map_interaction_manager.has_method("update_data_references"): printerr("Main (_on_gdm_convoy_data_updated): MIM missing 'update_data_references'.")

	# --- Augment convoy data with icon offsets using ConvoyVisualsManager ---
	if is_instance_valid(convoy_visuals_manager) and convoy_visuals_manager.has_method("augment_convoy_data_with_offsets"):
		# Pass map_tiles and map_display, as ConvoyVisualsManager will now need them for the full augmentation.
		_all_convoy_data = convoy_visuals_manager.augment_convoy_data_with_offsets(_all_convoy_data, map_tiles, map_display, map_renderer_node) # Assuming map_renderer_node is also needed by CVM
	else:
		printerr("Main: ConvoyVisualsManager not available or missing 'augment_convoy_data_with_offsets' method. Icon offsets will not be calculated.")

	# After map is rendered (if it was), get icon positions from the render result.
	# This part is tricky because _update_map_display can be called with force_rerender_map_texture = false.
	# For now, assume if _on_gdm_convoy_data_updated is called, we *want* to re-render map for new lines.
	# The _trigger_convoy_visuals_update will be called within _update_map_display if map is re-rendered.
	# If not re-rendered, _trigger_convoy_visuals_update will be called with empty positions.
	_update_map_display(true, false)


func _on_gdm_convoy_selection_changed(selected_convoy_data: Variant):
	# Update local selection cache from the single source of truth (GDM)
	if selected_convoy_data:
		_selected_convoy_ids = [str(selected_convoy_data.get("convoy_id"))]
		# Center camera on selected convoy in visible map area
		if selected_convoy_data.has("x") and selected_convoy_data.has("y") and is_instance_valid(map_container) and is_instance_valid(map_display) and not map_tiles.is_empty() and map_tiles[0] is Array and not map_tiles[0].is_empty():
			var map_initial_world_size = map_display.custom_minimum_size
			var map_cols: int = map_tiles[0].size()
			var map_rows: int = map_tiles.size()
			if map_cols > 0 and map_rows > 0 and map_initial_world_size.x > 0 and map_initial_world_size.y > 0:
				var tile_world_width: float = map_initial_world_size.x / float(map_cols)
				var tile_world_height: float = map_initial_world_size.y / float(map_rows)
				var convoy_center_local_to_map_container: Vector2 = Vector2((float(selected_convoy_data.get("x")) + 0.5) * tile_world_width, (float(selected_convoy_data.get("y")) + 0.5) * tile_world_height)
				var convoy_world_position: Vector2 = map_container.to_global(convoy_center_local_to_map_container)
				var default_zoom_scalar: float = 1.0
				_focus_camera_on_convoy_or_route(convoy_world_position, default_zoom_scalar)
	else:
		_selected_convoy_ids.clear()

	# A selection change requires re-rendering journey lines and UI
	_update_map_display(true)





func _on_data_refresh_tick() -> void:
	# print('Main: Refresh timer timeout. Requesting updated convoy data...')
	# GameDataManager will handle calling APICallsInstance if it's set up correctly.
	# This node (main.gd) no longer directly calls APICallsInstance.
	# If GameDataManager needs to be triggered, it should listen to this timer or have its own.    
	var gdm_node_refresh = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm_node_refresh) and gdm_node_refresh.has_method("request_convoy_data_refresh"):
		gdm_node_refresh.request_convoy_data_refresh()
	else:
		printerr("Main: GameDataManager Autoload invalid or missing 'request_convoy_data_refresh' method. Data refresh not triggered.")
	# If GameTimersNode is an Autoload, GameDataManager could connect to its data_refresh_tick.

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


func _on_visual_update_tick() -> void:
	# Throb animation is now handled by individual ConvoyNode instances in their _process.
	# The map texture itself doesn't need to be re-rendered for throb.
	# We only need to update UI elements (labels) if their state changed (hover, selection)
	# or if camera movement requires re-clamping (MIM signals UIManager for light updates).
	# A full UI update might be needed if other UI elements animate or depend on frequent updates.
	# and UI elements.
	# false = not a light UI update (do full UI update)    
	# Temporarily set force_rerender_map_texture to false to stop constant full map redraws.
	# This will stop throb if it's part of map_render. ConvoyNodes handle their own throb.
	call_deferred("_update_map_display", false, false) # false = don't rerender map texture, false = not a light ui update (full ui update)


# All label drawing and management is now handled by UIManager.gd
# The following functions are removed:
# _update_hover_labels()
# _update_convoy_labels()
# _update_settlement_labels()
# _draw_single_convoy_label()
# _draw_single_settlement_label()
# _find_settlement_at_tile()
# _on_connector_lines_container_draw()
# _get_convoy_label_combined_rect()

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
	pass # Deprecated

func _update_settlement_labels() -> void:
	# This function is now deprecated for hover labels.
	pass # Deprecated

func _input(event: InputEvent) -> void:  # Renamed from _gui_input
	# If a menu is active, MapView (main.gd) should not process input.
	if is_instance_valid(menu_manager_ref) and menu_manager_ref.has_method("is_any_menu_active"):
		if menu_manager_ref.is_any_menu_active():
			# Menus on CanvasLayer with MOUSE_FILTER_STOP should handle their own input.
			# NEW: Check for map click to close active menu
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				var map_view_rect: Rect2 = get_map_viewport_container_global_rect()
				var click_pos: Vector2 = event.global_position
				var is_on_map: bool = map_view_rect.has_point(click_pos)
				

				# Check if the click is within the map's visible area
				if is_on_map:
					# Click is on the map area while a menu is open
					if menu_manager_ref.has_method("close_all_menus"): # Ensure MenuManager has this method
						menu_manager_ref.close_all_menus()
						get_viewport().set_input_as_handled() # Consume the event
						return # Stop further processing of this input event
					else:
						printerr("Main: MenuManager does not have a 'close_all_menus' method.")
			return # Stop further input processing in main.gd

	# VERY IMPORTANT DEBUG: Log all events reaching main.gd's _input
	# print("Main _input RECEIVED EVENT --- Type: %s, Event: %s" % [event.get_class(), event]) # DEBUG: Performance intensive
	# if event is InputEventMouseButton:
		# print("    InputEventMouseButton --- button_index: %s, pressed: %s, shift_pressed: %s, global_pos: %s" % [event.button_index, event.pressed, event.is_shift_pressed(), event.global_position]) # DEBUG
	# elif event is InputEventMouseMotion:
		# print("    InputEventMouseMotion --- global_pos: %s, relative: %s, button_mask: %s" % [event.global_position, event.relative, event.button_mask]) # DEBUG
	# elif event is InputEventPanGesture: # DEBUG: Log PanGesture details
		# print("    InputEventPanGesture --- delta: %s, position: %s" % [event.delta, event.position]) # DEBUG
	# You can add more elif for other event types like InputEventScreenTouch, InputEventGesture if needed

	# Pan and Zoom logic is now entirely within MapInteractionManager.
	# MapInteractionManager's handle_input will consume events if it handles them.

	# MapInteractionManager now uses _unhandled_input, so we don't forward from here.
	# If main.gd had other global inputs to process that MIM shouldn't, they could go here.
	# Ensure MIM's _unhandled_input correctly consumes events it handles so they don't
	# trigger unexpected behavior here if main.gd also tries to process them.
	pass

	# Mouse wheel zoom logic has been removed from main.gd and is now handled by MapInteractionManager.gd
	
	# The old drag logic and hover detection that was in main.gd's _input
	# is now fully handled by MapInteractionManager or by main.gd reacting to
	# signals from MapInteractionManager.

func _process(_delta: float): # Keep _process for potential future needs or if UI updates need it
	# The _map_view_needs_light_ui_update flag is no longer needed here,
	# as MapInteractionManager handles camera updates and can trigger UI updates
	# via signals or direct calls if necessary.
	# For now, _update_map_display is called when data changes or on timers.
	# If UI elements need to react to continuous camera movement (e.g. for culling),
	# that logic would go into the UIManager or the elements themselves.
	
	# Reset the preview start flag at the end of every frame's processing.
	_preview_started_this_frame = false


func _update_refresh_notification_position():
	if not is_instance_valid(_refresh_notification_label):
		return

	# Position relative to MapView's own viewport (the ViewportContainer's area)
	var map_view_rect = get_viewport().get_visible_rect()
	# Ensure the label has its size calculated based on current text and font settings
	var label_size = _refresh_notification_label.get_minimum_size()
	var padding = label_map_edge_padding # Use the class member
	
	# Position relative to the bottom-right of map_view_rect
	# The position set is local to _refresh_notification_label's parent.
	_refresh_notification_label.position = Vector2(
		map_view_rect.position.x + map_view_rect.size.x - label_size.x - padding,
		map_view_rect.position.y + map_view_rect.size.y - label_size.y - padding
	)

# --- UI Toggle Handler ---
func _on_detailed_view_toggled(button_pressed: bool) -> void:
	show_detailed_view = button_pressed
	# print('Main: Detailed view toggled to: ', show_detailed_view)
	_update_map_display(true) # Re-render the map with new detail settings


func _update_detailed_view_toggle_position() -> void:
	if not is_instance_valid(detailed_view_toggle):
		return

	# Position relative to MapView's own viewport (the ViewportContainer's area)
	var map_view_rect = get_viewport().get_visible_rect()
	var toggle_size: Vector2 = detailed_view_toggle.get_minimum_size() # Get its actual size based on text and font
	var padding = label_map_edge_padding # Use the class member
	
	# Position relative to the bottom-right of map_view_rect
	# Position is local to detailed_view_toggle's parent (UIManagerNode)
	# UIManagerNode is a child of ScreenSpaceUI (CanvasLayer) within MapView.
	detailed_view_toggle.position = Vector2(
		map_view_rect.position.x + map_view_rect.size.x - toggle_size.x - padding,
		map_view_rect.position.y + map_view_rect.size.y - toggle_size.y - padding
	)

# _on_connector_lines_container_draw is now handled by UIManager.gd

# --- Signal Handlers for MapInteractionManager ---
func _on_mim_hover_changed(new_hover_info: Dictionary):
	_current_hover_info = new_hover_info
	# print("Main: _on_mim_hover_changed. New hover: ", _current_hover_info) # DEBUG
	# OLD: _update_map_display(true) was causing a full map re-render on hover.

	# NEW: Directly update UI elements without re-rendering the entire map.
	if is_instance_valid(ui_manager):
		# Gather necessary arguments for UIManager, similar to how _update_map_display does it,
		# but specifically for a UI-only update (which might be light or full depending on context).
		var user_positions_for_ui = _convoy_label_user_positions # Use main's current understanding
		# Use main.gd's own drag state as the source of truth for UI updates triggered by hover changes.
		# This state is set by _on_mim_panel_drag_started and cleared by _on_mim_panel_drag_ended.
		var dragging_panel_for_ui = self._dragging_panel_node 
		var dragged_id_for_ui = self._dragged_convoy_id_actual_str # Use main's current understanding

		if is_instance_valid(map_interaction_manager):
			if map_interaction_manager.has_method("get_convoy_label_user_positions"):
				# It's still good to get the latest user positions from MIM if it's the authority for that.
				user_positions_for_ui = map_interaction_manager.get_convoy_label_user_positions() 

		var current_camera_zoom_for_ui = 1.0
		if map_interaction_manager.has_method("get_current_camera_zoom"):
			current_camera_zoom_for_ui = map_interaction_manager.get_current_camera_zoom()
		# DEBUG: Log what drag state is being passed to UIManager during a hover change.
		# print("  _on_mim_hover_changed: Passing to UIManager - new_hover_info: %s, dragging_panel: %s, dragged_id: %s" % [new_hover_info, dragging_panel_for_ui, dragged_id_for_ui])
		
		ui_manager.update_ui_elements( # Call with is_light_ui_update = false (default) to trigger full label logic
			map_display,
			map_tiles,
			_all_convoy_data,
			_all_settlement_data,
			_convoy_id_to_color_map,
			new_hover_info, # Use the new_hover_info directly
			_selected_convoy_ids, # Use the current selection state
			user_positions_for_ui, 
			dragging_panel_for_ui,
			dragged_id_for_ui,                 # Pass the ID of the currently dragged panel (or empty)
			get_map_viewport_container_global_rect(), # Pass current map display rect for UIManager clamping
			false,                             # is_light_ui_update: false to trigger full label logic for hover
			current_camera_zoom_for_ui         # Pass the current zoom level
		)
	
func _on_mim_selection_changed(new_selected_ids: Array):
	# This signal comes from MapInteractionManager (e.g., user clicks on map)
	# Instead of setting state here, we tell the central manager.
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm) and gdm.has_method("select_convoy_by_id"):
		var id_to_select = ""
		if not new_selected_ids.is_empty():
			id_to_select = new_selected_ids[0] # Assuming single selection
		gdm.select_convoy_by_id(id_to_select)

func _on_mim_panel_drag_ended(convoy_id_str: String, final_local_position: Vector2):
	# print("Main: _on_mim_panel_drag_ended for convoy: %s. Panel node was: %s, IsValid: %s" % [convoy_id_str, _dragging_panel_node, is_instance_valid(_dragging_panel_node)]) # DEBUG
	_convoy_label_user_positions[convoy_id_str] = final_local_position # Update main's copy

	# Clear main.gd's internal drag state
	var _previously_dragged_panel = _dragging_panel_node
	_dragging_panel_node = null # Crucial to clear this
	_dragged_convoy_id_actual_str = ""
	_drag_offset = Vector2.ZERO # Reset drag offset
	
	# After clearing internal state, print status of the panel that WAS being dragged
	# if is_instance_valid(previously_dragged_panel):
		# print("  DragEnd: Panel %s is still valid. Visible: %s, Pos: %s, GlobalPos: %s, Parent: %s" % [convoy_id_str, previously_dragged_panel.visible, previously_dragged_panel.position, previously_dragged_panel.global_position, previously_dragged_panel.get_parent()])

	Input.set_default_cursor_shape(Input.CURSOR_ARROW) # Reset cursor

	if is_instance_valid(ui_manager) and ui_manager.has_method("set_dragging_state"):
		ui_manager.set_dragging_state(null, "", false) # Inform UIManager drag has ended

	# Panel drag ended, UI needs update, map texture itself doesn't.
	_update_map_display(false, false)

func _on_mim_camera_zoom_changed(_new_zoom_level: float):
	# print("Main: Camera zoom changed to: ", new_zoom_level) # DEBUG
	# A zoom change requires a full UI update to rescale elements, not just a light one.
	_update_map_display(false, false) # false = don't rerender map texture, false = not a light UI update


func _on_mim_panel_drag_started(convoy_id_str: String, panel_node: Panel): # Corrected signal name
	# print("Main: PanelDragStart: Convoy: %s, PanelNode: %s, IsValid: %s" % [convoy_id_str, panel_node, is_instance_valid(panel_node)])
	if not is_instance_valid(panel_node):
		printerr("Main: PanelDragStart: Attempted to start drag with an invalid panel_node for convoy %s. Aborting drag setup." % convoy_id_str)
		return

	_dragging_panel_node = panel_node
	_dragged_convoy_id_actual_str = convoy_id_str

	# Calculate drag offset based on the panel's current global position and the mouse position
	# This offset might be used by MapInteractionManager if it needs to calculate global positions.
	# Main.gd itself relies on local positions from MIM for updates.
	if is_instance_valid(_dragging_panel_node):
		_drag_offset = _dragging_panel_node.global_position - get_global_mouse_position()
		# print("  PanelDragStart: Panel %s initial state before UIM/move_child - Visible: %s, Pos: %s, GlobalPos: %s, Parent: %s" % [convoy_id_str, _dragging_panel_node.visible, _dragging_panel_node.position, _dragging_panel_node.global_position, _dragging_panel_node.get_parent()])
	else: # Should not happen due to check above, but as a safeguard
		printerr("Main: PanelDragStart: _dragging_panel_node became invalid unexpectedly for convoy %s." % convoy_id_str)
		_dragging_panel_node = null # Ensure it's null if invalid
		_dragged_convoy_id_actual_str = ""
		return

	Input.set_default_cursor_shape(Input.CURSOR_DRAG)

	if is_instance_valid(ui_manager) and ui_manager.has_method("set_dragging_state"):
		ui_manager.set_dragging_state(_dragging_panel_node, _dragged_convoy_id_actual_str, true)
		# print("  PanelDragStart: Called ui_manager.set_dragging_state for %s." % convoy_id_str)
	else:
		printerr("Main: PanelDragStart: UIManager or set_dragging_state method not available for %s." % convoy_id_str)

	# Bring panel to front
	if is_instance_valid(ui_manager) and ui_manager.has_method("get_convoy_label_container_node"):
		var label_container = ui_manager.get_convoy_label_container_node()
		if is_instance_valid(label_container):
			if is_instance_valid(_dragging_panel_node):
				if _dragging_panel_node.get_parent() == label_container:
					label_container.move_child(_dragging_panel_node, label_container.get_child_count() - 1)
					# print("  PanelDragStart: Moved panel %s to front of container '%s'." % [convoy_id_str, label_container.name])
				else:
					printerr("  PanelDragStart: Panel %s parent is NOT the expected label container. Parent: %s, ExpectedContainer: %s" % [convoy_id_str, _dragging_panel_node.get_parent(), label_container])
			else:
				printerr("   PanelDragStart: _dragging_panel_node became invalid before move_child for %s." % convoy_id_str)
		else:
			printerr("  PanelDragStart: UIManager's label container node is not valid for %s." % convoy_id_str)
	else:
		printerr("Main: PanelDragStart: UIManager or get_convoy_label_container_node method not available for move_child operation for %s." % convoy_id_str)
	
	# if is_instance_valid(_dragging_panel_node):
		# print("  PanelDragStart: Panel %s final state after UIM/move_child - Visible: %s, Pos: %s, GlobalPos: %s, Parent: %s" % [convoy_id_str, _dragging_panel_node.visible, _dragging_panel_node.position, _dragging_panel_node.global_position, _dragging_panel_node.get_parent()])

func _on_mim_panel_drag_updated(convoy_id_str: String, new_panel_local_position: Vector2):
	# print("Main: MIM panel_drag_updated for convoy: ", convoy_id_str, " to local_pos: ", new_panel_local_position) # DEBUG
	if not is_instance_valid(_dragging_panel_node):
		# This can be noisy if the panel was legitimately removed/hidden by UIManager after drag_ended
		# print("Main: PanelDragUpdate: _dragging_panel_node is invalid. Cannot update position for convoy %s." % convoy_id_str)
		return
	if _dragged_convoy_id_actual_str != convoy_id_str:
		# print("Main: PanelDragUpdate: Mismatched convoy ID. Expected '%s', got '%s'." % [_dragged_convoy_id_actual_str, convoy_id_str])
		return

	# At this point, _dragging_panel_node should be the correct, valid panel instance.
	# new_panel_local_position is local to its parent (the convoy_label_container in UIManager).
	# print("Main: PanelDragUpdate for %s. Panel IsValid: %s, Visible: %s. CurrentLocalPos: %s. Attempting NewLocalPos: %s. Parent: %s" % [convoy_id_str, is_instance_valid(_dragging_panel_node), _dragging_panel_node.visible, _dragging_panel_node.position, new_panel_local_position, _dragging_panel_node.get_parent()]) # DEBUG
	
	if is_instance_valid(_dragging_panel_node): # Double check before assigning position
		_dragging_panel_node.position = new_panel_local_position # Update the actual panel's local position

	if is_instance_valid(ui_manager) and ui_manager.has_method("get_convoy_connector_lines_container_node"):
		var connector_container = ui_manager.get_convoy_connector_lines_container_node()
		if is_instance_valid(connector_container):
			connector_container.queue_redraw() # Redraw connector lines after panel position update
		# else: print("Main: PanelDragUpdate: Connector container not valid for redraw.") # Can be noisy
	# else: print("Main: PanelDragUpdate: UIManager or connector container getter not available.") # Can be noisy

# --- Menu Interaction Functions ---

func _on_menu_opened_for_camera_focus(menu_node: Node, menu_type: String):
	# This function now ONLY handles camera focusing if a convoy menu opens.
	# The map resizing/repositioning is handled by GameScreenManager.
	
	# Instead of hiding the nav bar, push the menu manager down below it.
	if is_instance_valid(top_nav_bar_container) and is_instance_valid(menu_manager_ref):
		# Ensure the navbar is visible, in case it was hidden by other logic.
		top_nav_bar_container.show()
		# Set the top offset of the menu manager to be the height of the nav bar.
		menu_manager_ref.offset_top = top_nav_bar_container.size.y


	# MODIFIED: Added "convoy_settlement_submenu" and "convoy_overview"
	if menu_type == "convoy_detail" or \
	   menu_type == "convoy_settlement_submenu" or \
	   menu_type == "convoy_overview":
		# Defer the focusing logic to ensure GameScreenManager has resized the viewport.
		# NOTE: "convoy_journey_menu" is handled by its own route preview logic, so it's excluded here.
		call_deferred("_execute_convoy_focus_logic", menu_node)


	# NEW: Connect to route preview signals if it's the right menu
	# Print diagnostic info about menu type and node
	print("Main: _on_menu_opened_for_camera_focus called with menu_type:", menu_type, "node:", menu_node)
	var is_journey_menu = menu_type == "convoy_journey_menu" or menu_type == "convoy_journey_submenu" or menu_node.get_class() == "ConvoyJourneyMenu"
	if is_journey_menu:
		print("Main: Attempting to connect route preview signals for menu node:", menu_node)
		if menu_node.has_signal("route_preview_started"):
			if not menu_node.is_connected("route_preview_started", Callable(self, "_on_route_preview_started")):
				print("Main: Connecting route_preview_started signal.")
				menu_node.route_preview_started.connect(_on_route_preview_started)
		if menu_node.has_signal("route_preview_ended"):
			if not menu_node.is_connected("route_preview_ended", Callable(self, "_on_route_preview_ended")):
				print("Main: Connecting route_preview_ended signal.")
				menu_node.route_preview_ended.connect(_on_route_preview_ended)
	else:
		print("Main: Skipping route preview signal connection for menu_type:", menu_type, "node class:", menu_node.get_class())


func _execute_convoy_focus_logic(menu_node: Node):

	# This function contains the logic previously in _on_menu_opened_for_camera_focus
	# Ensure MapView is already visible and processing input if its ViewportContainer is visible.

	# Ensure MapInteractionManager uses the correct screen rect for the map (the ViewportContainer's rect)
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("set_current_map_screen_rect"):
		if get_map_viewport_container_global_rect().size.x > 0: # Ensure rect is valid
			map_interaction_manager.set_current_map_screen_rect(get_map_viewport_container_global_rect())
		else:
			printerr("Main: Cannot set MIM current map screen rect in _on_menu_opened_for_camera_focus.")


		var convoy_data = menu_node.get_meta("menu_data")
		if convoy_data is Dictionary and convoy_data.has("convoy_id"):
			var convoy_tile_x: float = convoy_data.get("x", -1.0) # Precise, possibly fractional, tile coord
			var convoy_tile_y: float = convoy_data.get("y", -1.0)

			if convoy_tile_x >= 0.0 and convoy_tile_y >= 0.0 and \
			   is_instance_valid(map_camera) and \
			   is_instance_valid(map_display) and is_instance_valid(map_display.texture) and \
			   not map_tiles.is_empty() and map_tiles[0] is Array and not map_tiles[0].is_empty() and \
			   is_instance_valid(map_container):

				# This is the rect of MapView's own viewport (e.g., the left 1/3 of the screen)
				var map_view_current_rect = get_viewport().get_visible_rect()
				var map_initial_world_size = map_display.custom_minimum_size
				var map_cols: int = map_tiles[0].size()
				var map_rows: int = map_tiles.size()

				if map_cols > 0 and map_rows > 0 and map_initial_world_size.x > 0 and map_initial_world_size.y > 0:
					var tile_world_width: float = map_initial_world_size.x / float(map_cols)
					var tile_world_height: float = map_initial_world_size.y / float(map_rows)

					# Calculate the convoy's center position local to MapContainer
					var convoy_center_local_to_map_container: Vector2 = Vector2(
						(convoy_tile_x + 0.5) * tile_world_width,
						(convoy_tile_y + 0.5) * tile_world_height
					)
					# Calculate convoy's position in MapView's local space (parent of MapCamera and MapContainer)
					var convoy_position_mapview_local: Vector2 = map_container.position + convoy_center_local_to_map_container

					var world_width_to_display: float = convoy_focus_zoom_target_tiles_wide * tile_world_width
					var world_height_to_display: float = convoy_focus_zoom_target_tiles_high * tile_world_height

					if world_width_to_display <= 0.001 or world_height_to_display <= 0.001 or map_view_current_rect.size.x <= 0.001 or map_view_current_rect.size.y <= 0.001:
						printerr("FocusDebug: Critical value for zoom calculation is too small. WidthToDisplay: %s, HeightToDisplay: %s, MapViewSize: %s. Aborting zoom." % [world_width_to_display, world_height_to_display, map_view_current_rect.size])
						return

					var target_zoom_x: float = map_view_current_rect.size.x / world_width_to_display
					var target_zoom_y: float = map_view_current_rect.size.y / world_height_to_display

					var final_target_zoom_scalar: float = min(target_zoom_x, target_zoom_y)

					# Calculate the world-space shift needed to position the convoy according to convoy_menu_map_view_offset_percentage.
					# This shift is applied to the camera's target.
					# If convoy_menu_map_view_offset_percentage is 0.0 (for centering), additional_camera_shift_world_x will be 0.0.
					var additional_camera_shift_world_x: float = 0.0
					if abs(final_target_zoom_scalar) > 0.0001: # Avoid division by zero						
						var partial_view_width_in_world_units = map_view_current_rect.size.x / final_target_zoom_scalar
						additional_camera_shift_world_x = convoy_menu_map_view_offset_percentage * partial_view_width_in_world_units
					else:
						printerr("Main: _on_menu_state_changed - final_target_zoom_scalar is too small (%s), cannot calculate additional_camera_shift_world_x." % final_target_zoom_scalar)
					# print("Main: _on_menu_state_changed (convoy_detail) - convoy_menu_map_view_offset_percentage: %s, final_target_zoom_scalar: %s, calculated additional_camera_shift_world_x: %s" % [convoy_menu_map_view_offset_percentage, final_target_zoom_scalar, additional_camera_shift_world_x]) # Original print

					# The camera should target the convoy's actual world position, plus this menu-induced shift.
					# The camera.offset (set in _apply_map_camera_and_ui_layout) then positions this target in the partial view.
					var camera_target_mapview_local: Vector2 = convoy_position_mapview_local + Vector2(additional_camera_shift_world_x, 0.0)

					
					# print("Main: Focusing on convoy %s. Base local pos: %s. Camera target local pos: %s" % [convoy_data.get("convoy_id", "N/A"), convoy_position_mapview_local, camera_target_mapview_local])

					# Calculate and set new zoom level
					if tile_world_width > 0.001 and tile_world_height > 0.001 and \
					   convoy_focus_zoom_target_tiles_wide > 0.001 and convoy_focus_zoom_target_tiles_high > 0.001 and \
					   map_view_current_rect.size.x > 0.001 and map_view_current_rect.size.y > 0.001:

						if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("focus_camera_and_set_zoom"):
							# Pass the adjusted camera target position
							map_interaction_manager.focus_camera_and_set_zoom(camera_target_mapview_local, final_target_zoom_scalar)
							var _cam_pos_str = "N/A"
							var _cam_offset_str = "N/A" # Offset will be set by _apply_map_camera_and_ui_layout shortly
							var _cam_zoom_str = "N/A"
							if is_instance_valid(map_camera):
								_cam_pos_str = "Local: %s, Global: %s" % [map_camera.position, map_camera.global_position]
								_cam_zoom_str = str(map_camera.zoom) # Get current zoom
						else:
							printerr("Main: MapInteractionManager invalid or missing set_and_clamp_camera_zoom method.")
					else:
						printerr("Main: Cannot calculate convoy focus zoom due to invalid parameters (tile_world_size, target_tiles, or map_view_current_rect.size).")
	# No need to call _apply_map_camera_and_ui_layout() as GameScreenManager handles map view,

	# and camera offset within its own viewport should be (0,0).
func _on_all_menus_closed(): # Renamed from _on_menus_completely_closed for clarity
	# print("Main (MapView): All menus are closed. Resuming map interactions.")
	# MapView visibility and input processing are now implicitly handled by its parent SubViewportContainer's state,
	# which is controlled by GameScreenManager.



	# Reset the menu manager's offset when all menus are closed.
	if is_instance_valid(menu_manager_ref):
		menu_manager_ref.offset_top = 0.0

	# When all menus close, ensure MapInteractionManager knows the map is full screen again for its internal calculations (e.g., zoom clamping).
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("set_current_map_screen_rect"):
		map_interaction_manager.set_current_map_screen_rect(get_map_viewport_container_global_rect())
	# No need to call _apply_map_camera_and_ui_layout().

func _apply_map_camera_and_ui_layout():
	if not is_instance_valid(map_camera):
		printerr("Main: MapCamera invalid in _apply_map_camera_and_ui_layout")
		return

	# DEBUG: Check _current_map_display_rect and viewport just before offset calculation
	# print("Main: _apply_map_camera_and_ui_layout - get_viewport().get_visible_rect(): ", get_viewport().get_visible_rect())

	map_camera.offset = Vector2.ZERO # Camera offset is relative to its viewport center

	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("set_current_map_screen_rect"):
		map_interaction_manager.set_current_map_screen_rect(get_map_viewport_container_global_rect())


# Example: Call this from MapInteractionManager when a convoy is clicked for its menu
func request_open_convoy_menu_via_manager(convoy_data):
	if is_instance_valid(menu_manager_ref):
		menu_manager_ref.request_convoy_menu(convoy_data) # Call a method on MenuManager

# --- Handler for Menu Requests from MapInteractionManager ---
func _on_mim_convoy_menu_requested(convoy_data: Dictionary):
	if not is_instance_valid(menu_manager_ref):
		printerr("Main: _on_mim_convoy_menu_requested - menu_manager_ref is NOT valid! Cannot request convoy menu.")
		return

	# print("Main: Map icon clicked, requesting convoy menu. Convoy Data: ", convoy_data) # DEBUG

	# --- NEW: Simplified selection logic ---
	# Tell the GameDataManager to select this convoy. The GDM will then emit
	# the 'convoy_selection_changed' signal, which will trigger the map update.
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm) and gdm.has_method("select_convoy_by_id"):
		gdm.select_convoy_by_id(str(convoy_data.get("convoy_id", "")))

	# This existing function already calls the menu manager correctly to open the menu
	request_open_convoy_menu_via_manager(convoy_data)

func _on_user_info_display_convoy_menu_requested(convoy_id_str: String):
	"""
	Handles the request from the top nav bar to open a convoy menu.
	"""
	# We have the ID, now we need the full data to open the menu.
	# We can find it in our local cache `_all_convoy_data`.
	var convoy_data_to_open = null
	for convoy_data in _all_convoy_data:
		if str(convoy_data.get("convoy_id", "")) == convoy_id_str:
			convoy_data_to_open = convoy_data
			break
	
	if convoy_data_to_open:
		# This reuses the same function called when clicking on the map icon.
		request_open_convoy_menu_via_manager(convoy_data_to_open)
	else:
		printerr("Main: Could not find convoy data for ID '%s' in local cache to open menu." % convoy_id_str)

func _trigger_convoy_visuals_update(icon_positions_map: Dictionary = {}):
	"""
	Calls the ConvoyVisualsManager to update the ConvoyNode instances on the map.
	Optionally takes a map of convoy_id to icon pixel positions.
	"""
	# print("Main: _trigger_convoy_visuals_update called. icon_positions_map size: ", icon_positions_map.size()) # DEBUG

	if not _map_and_ui_setup_complete:
		# print("Main (_trigger_convoy_visuals_update): Map and UI setup not yet complete. Skipping convoy node update.")
		return

	if not (is_instance_valid(convoy_visuals_manager) and convoy_visuals_manager.has_method("update_convoy_nodes_on_map")):
		printerr("Main: ConvoyVisualsManager not ready or 'update_convoy_nodes_on_map' method missing.")
		return


	var tile_w_on_texture = ui_manager._cached_actual_tile_width_on_texture
	var tile_h_on_texture = ui_manager._cached_actual_tile_height_on_texture


	# _all_convoy_data should already be augmented with _pixel_offset_for_icon by this point
	convoy_visuals_manager.update_convoy_nodes_on_map(
		_all_convoy_data,
		_convoy_id_to_color_map,
		tile_w_on_texture,
		tile_h_on_texture,
		icon_positions_map, # Pass the calculated icon positions
		_selected_convoy_ids # Pass the array of selected convoy IDs
	)

func update_map_render_bounds(_new_bounds_global_rect: Rect2) -> void:
	# This method is called by GameScreenManager when the map's display area changes.
	# We can simply trigger the existing _on_viewport_size_changed logic,
	# as it already handles updating MapInteractionManager and UI elements
	# based on the map's current global rectangle.
	# The _new_bounds_global_rect parameter isn't directly used here because
	# _on_viewport_size_changed recalculates it using get_map_viewport_container_global_rect().
	_on_viewport_size_changed()

# --- Route Preview Handlers ---


# Called when journey/route preview starts
func _on_route_preview_started(route_data: Dictionary):
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("set_camera_loose_mode"):
		map_interaction_manager.set_camera_loose_mode(true)
	# ...existing logic for starting route preview...
	"""Handles zooming and highlighting when a route preview is requested."""
	print("Main: _on_route_preview_started called. Route data:", route_data)
	# Set the single-frame guard flag to true. This prevents a simultaneous `_ended`
	# signal from clearing the preview state before it can be rendered.
	_preview_started_this_frame = true
	_is_in_route_preview_mode = true
	_last_route_preview_data = route_data.duplicate(true)
	var journey_details = route_data.get("journey", {})
	var route_x = journey_details.get("route_x", [])
	var route_y = journey_details.get("route_y", [])
	if route_x.is_empty() or route_y.is_empty():
		printerr("Main: Route preview started with no route points.")
		return
	# 1. Prepare highlight data
	_route_preview_highlight_data.clear()
	for i in range(route_x.size()):
		_route_preview_highlight_data.append(Vector2(float(route_x[i]), float(route_y[i])))
	# 2. Focus camera on the route
	# We defer this call to ensure the viewport has been resized by GameScreenManager first.
	call_deferred("_focus_camera_on_route", route_data)
	# 3. Trigger map re-render with the new highlight
	call_deferred("_update_map_display", true)


# Called when journey/route preview ends
func _on_route_preview_ended():
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("set_camera_loose_mode"):
		map_interaction_manager.set_camera_loose_mode(false)
	# ...existing logic for ending route preview...
	"""Handles cleaning up the preview when the menu is closed or a choice is made."""
	# RACE CONDITION GUARD: If a preview was just started in this same frame,
	# ignore this 'ended' signal. This handles cases where menu logic might
	# erroneously fire both signals at once.
	if _preview_started_this_frame:
		return
	if not _is_in_route_preview_mode:
		return # Avoid redundant updates if already ended

	_is_in_route_preview_mode = false
	_route_preview_highlight_data.clear()
	_last_route_preview_data.clear()

	# Re-render the map to remove the highlight
	_update_map_display(true)

	# Optional: Restore camera focus. For now, we'll let the camera stay.
	# When the menu stack closes, the view will be whatever it was.

func _focus_camera_on_route(route_data: Dictionary):
	"""Calculates the bounding box of a route and tells the camera to frame it using unified journey logic."""
	var journey_details = route_data.get("journey", {})
	var route_x = journey_details.get("route_x", [])
	var route_y = journey_details.get("route_y", [])
	if route_x.is_empty() or route_y.is_empty():
		printerr("Main: Cannot focus on route, route_x or route_y is empty.")
		return
	# Convert route_x and route_y arrays to an array of Vector2 points
	var journey_points: Array = []
	for i in range(min(route_x.size(), route_y.size())):
		journey_points.append(Vector2(float(route_x[i]), float(route_y[i])))
	# Use the robust journey focus logic
	_focus_camera_on_journey(journey_points)
