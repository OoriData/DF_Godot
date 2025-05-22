# main.gd
@tool 
extends Node2D

# Reference to your APICalls node.
# IMPORTANT: Adjust the path "$APICallsInstance" to the actual path of your APICalls node
# in your scene tree relative to the node this script (main.gd) is attached to.
@onready var api_calls_node: Node = $APICallsInstance # Adjust if necessary
# IMPORTANT: Adjust this path to where you actually place your detailed view toggle in your scene tree!

# Node references
## Reference to the node that has map_render.gd attached. This should be a child of the current node.
@onready var map_renderer_node: Node = $MapRendererLogic 
## Reference to the TextureRect that displays the map.
@onready var map_display: TextureRect = $MapContainer/MapDisplay

## Reference to the new MapContainer node. Ensure this path is correct.
@onready var map_container: Node2D = $MapContainer

@onready var ui_manager: Node = $MapContainer/UIManagerNode
@onready var detailed_view_toggle: CheckBox = $DetailedViewToggleCheckbox # Example path
@onready var map_interaction_manager: Node = $MapInteractionManager # Path to your MapInteractionManager node
# IMPORTANT: Adjust the path "$GameTimersNode" to the actual path of your GameTimers node in your scene tree.
@onready var game_timers_node: Node = $GameTimersNode # Adjust if necessary

var map_tiles: Array = []  # Will hold the loaded tile data
var _all_settlement_data: Array = []  # To store settlement data for rendering
var _all_convoy_data: Array = []  # To store convoy data from APICalls
## The file path to the JSON file containing map data.
@export var map_data_file_path: String = "res://foo.json" 

# Configurable gameplay/UI parameters
## Pixels to keep UI elements (like the detailed view toggle) from the edge of the displayed map texture.
@export var label_map_edge_padding: float = 5.0 
## The squared radius (in pixels on the rendered map texture) for convoy hover detection. (e.g., 25*25 = 625).
@export var convoy_hover_radius_sq: float = 625.0 
## The squared radius (in pixels on the rendered map texture) for settlement hover detection. (e.g., 20*20 = 400).
@export var settlement_hover_radius_sq: float = 400.0 

# This PREDEFINED_CONVOY_COLORS is duplicated in map_render.gd.
# Consider moving to an Autoload (e.g., GlobalConstants.gd) for a single source of truth.
const PREDEFINED_CONVOY_COLORS: Array[Color] = [  # Copied from map_render.gd; could these be imported instead?
	Color.RED,        # Red
	Color.BLUE,       # Blue
	Color.GREEN,      # Green
	Color.YELLOW,     # Yellow
	Color.CYAN,       # Cyan
	Color.MAGENTA,    # Magenta
	Color('orange'),  # Orange
	Color('purple'),  # Purple
	Color('lime'),    # Lime Green
	Color('pink')     # Pink
]

var _throb_phase: float = 0.0  # Cycles 0.0 to 1.0 for a 1-second throb_
var _refresh_notification_label: Label  # For the "Data Refreshed" notification

var _convoy_id_to_color_map: Dictionary = {}
var _last_assigned_color_idx: int = -1  # To cycle through PREDEFINED_CONVOY_COLORS for new convoys

var _current_hover_info: Dictionary = {}  # Will be updated by MapInteractionManager signal
var _selected_convoy_ids: Array[String] = []  # Will be updated by MapInteractionManager signal

## Initial state for toggling detailed map features (grid & political colors) on or off.
@export var show_detailed_view: bool = true 

var _dragging_panel_node: Panel = null  # Will be updated by MapInteractionManager signal or getter
var _drag_offset: Vector2 = Vector2.ZERO  # This state will move to MapInteractionManager
var _convoy_label_user_positions: Dictionary = {}  # Will be updated by MapInteractionManager signal
var _dragged_convoy_id_actual_str: String = "" # Will be updated by MapInteractionManager signal or getter

# --- Panning and Zooming State ---
var _is_panning: bool = false
var _last_pan_mouse_pos: Vector2
var _current_zoom: float = 1.0 
## Minimum zoom level for the map.
@export var min_zoom: float = 0.2
## Maximum zoom level for the map. Set higher to allow magnification beyond 1:1. (e.g., 3.0 or 5.0)
@export var max_zoom: float = 3.0 
## Factor by which to multiply/divide current zoom on each scroll step.
@export var zoom_factor_increment: float = 1.1 

var _map_base_width_pixels: float = 0.0 # Calculated in _ready
var _map_base_height_pixels: float = 0.0 # Calculated in _ready

var _map_view_needs_light_ui_update: bool = false

func _ready():
	# print('Main: _ready() called.')  # DEBUG

	# Enable input processing for this Node2D to receive _input events,
	# including those propagated from its Control children (like MapDisplay).
	set_process_input(true)

	if not is_instance_valid(map_container):
		printerr("Main: MapContainer node not found or invalid. Panning and zooming will not work. Path used: $MapContainer")
		return

	# Instantiate the map renderer
	# Ensure the MapDisplay TextureRect scales its texture nicely
	if map_display:
		map_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# print('Main: map_display found and stretch_mode set.')  # DEBUG
		# Explicitly set texture filter for smoother scaling.
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

	# --- Initialize MapInteractionManager ---
	if not is_instance_valid(map_interaction_manager):
		printerr("Main: MapInteractionManager node not found or invalid. Interaction will not work. Path used: $MapInteractionManager")
	else:
		# print("Main: MapInteractionManager node found: ", map_interaction_manager)
		if map_interaction_manager.has_method("initialize"):
			map_interaction_manager.initialize(
				map_display,
				ui_manager,
				_all_convoy_data,
				_all_settlement_data,
				map_tiles,
				_selected_convoy_ids, # Pass current (likely empty) selected IDs
				_convoy_label_user_positions # Pass current (likely empty) user positions
			)
			# Connect to signals from MapInteractionManager
			map_interaction_manager.hover_changed.connect(_on_mim_hover_changed)
			map_interaction_manager.selection_changed.connect(_on_mim_selection_changed)
			map_interaction_manager.panel_drag_started.connect(_on_mim_panel_drag_started)
			map_interaction_manager.panel_drag_updated.connect(_on_mim_panel_drag_updated)
			map_interaction_manager.panel_drag_ended.connect(_on_mim_panel_drag_ended)
		else:
			printerr("Main: MapInteractionManager does not have initialize method.")

	# --- Load the JSON data ---
	var file = FileAccess.open(map_data_file_path, FileAccess.READ)

	var err_code = FileAccess.get_open_error()
	if err_code != OK:
		printerr('Error opening map json file: ', map_data_file_path)
		printerr('FileAccess error code: ', err_code)  # DEBUG
		return

	# print('Main: Successfully opened foo.json.')  # DEBUG
	var json_string = file.get_as_text()
	file.close()

	var json_data = JSON.parse_string(json_string)

	if json_data == null:
		printerr('Error parsing JSON map data from: ', map_data_file_path)
		printerr('JSON string was: ', json_string) # DEBUG
		return

	# print('Main: Successfully parsed foo.json.')  # DEBUG
	# --- Extract tile data ---
	# Ensure the JSON structure has a "tiles" key containing an array
	if not json_data is Dictionary or not json_data.has('tiles'):
		printerr('JSON data does not contain a "tiles" key.')
		printerr('Parsed JSON data: ', json_data)  # DEBUG
		return

	map_tiles = json_data.get('tiles', [])  # Assign to the class member
	if map_tiles.is_empty() or not map_tiles[0] is Array or map_tiles[0].is_empty():
		printerr('Map tiles data is empty or invalid.')
		printerr('Extracted map_tiles: ', map_tiles)  # DEBUG
		map_tiles = []  # Ensure it's empty if invalid
		return # Cannot proceed without map tiles for size calculation

	# Calculate base map dimensions
	if is_instance_valid(map_renderer_node) and map_renderer_node.has_method("get"): # map_render.gd is a Node
		var base_tile_prop_size = map_renderer_node.get("base_tile_size_for_proportions")
		if base_tile_prop_size > 0 and not map_tiles.is_empty() and map_tiles[0] is Array:
			_map_base_width_pixels = map_tiles[0].size() * base_tile_prop_size
			_map_base_height_pixels = map_tiles.size() * base_tile_prop_size
			map_display.size = Vector2(_map_base_width_pixels, _map_base_height_pixels)
			print("Main: MapDisplay base size set to: ", map_display.size)
		else:
			printerr("Main: Could not calculate map base dimensions. map_renderer_node.base_tile_size_for_proportions might be zero or map_tiles invalid.")

	_all_settlement_data.clear() # Populate _all_settlement_data from map_tiles
	for y_idx in range(map_tiles.size()):
		var row = map_tiles[y_idx]
		if not row is Array: continue
		for x_idx in range(row.size()):
			var tile_data = row[x_idx]
			if tile_data is Dictionary and tile_data.has('settlements'):
				var settlements_on_tile = tile_data.get('settlements', [])
				if settlements_on_tile is Array:
					for settlement_entry in settlements_on_tile:
						if settlement_entry is Dictionary and settlement_entry.has('name'):
							var settlement_info_for_render = settlement_entry.duplicate()
							settlement_info_for_render['x'] = x_idx  # Ensure we use tile's x for rendering
							settlement_info_for_render['y'] = y_idx  # Ensure we use tile's y for rendering
							_all_settlement_data.append(settlement_info_for_render)
							# print('Main: Loaded settlement for render: %s at tile (%s, %s)' % [settlement_info_for_render.get('name'), x_idx, y_idx])  # DEBUG

	# Initial map render and display
	if not is_instance_valid(map_renderer_node):
		printerr("Main: MapRendererNode is not valid in _ready(). Map rendering will fail.")
		# Optionally, you could try to create a fallback instance here if absolutely necessary, but it's better to ensure the scene is set up correctly.

	# map_display is now child of map_container, its position is (0,0) relative to map_container
	# its size is set above to _map_base_width_pixels, _map_base_height_pixels

	# Set Z-indices for global drawing order
	# Higher z_index is drawn on top.
	if is_instance_valid(map_display):
		map_display.z_index = 0 # Base map layer
	if is_instance_valid(ui_manager) and ui_manager is CanvasItem: # Node2D inherits from CanvasItem
		ui_manager.z_index = 1 # UI Manager and its labels on top of the map
	if is_instance_valid(detailed_view_toggle):
		detailed_view_toggle.z_index = 2 # Toggle on top of UI Manager
	if is_instance_valid(_refresh_notification_label): # This was already high, which is good.
		_refresh_notification_label.z_index = 10 # Ensure notification is on top of everything

	_center_map_on_load()
	_update_map_display(true) # Initial render

	# Connect to the viewport's size_changed signal to re-render on window resize
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	if not Engine.is_editor_hint(): # Don't run these in editor tool mode
		# print('Main: Attempting to connect to APICallsInstance signals.')  # DEBUG
		# Connect to the APICalls signal for convoy data
		if api_calls_node:
			# print('Main: api_calls_node found.')  # DEBUG
			if api_calls_node.has_signal('convoy_data_received'):
				api_calls_node.convoy_data_received.connect(_on_convoy_data_received)
				print('Main: Successfully connected to APICalls.convoy_data_received signal.')
			else:
				printerr('Main: APICalls node does not have "convoy_data_received" signal.')
				printerr('Main: api_calls_node is: ', api_calls_node)  # DEBUG
		else:
			printerr('Main: APICalls node not found at the specified path. Cannot connect signal.')

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
				game_timers_node.data_refresh_tick.connect(_on_data_refresh_tick)
				print("Main: Connected to GameTimers.data_refresh_tick")
			else:
				printerr("Main: GameTimersNode does not have 'data_refresh_tick' signal.")
			if game_timers_node.has_signal("visual_update_tick"):
				game_timers_node.visual_update_tick.connect(_on_visual_update_tick)
				print("Main: Connected to GameTimers.visual_update_tick")
			else:
				printerr("Main: GameTimersNode does not have 'visual_update_tick' signal.")
		else:
			printerr("Main: GameTimersNode not found. Timed updates will not work.")

	# --- Setup Detailed View Toggle ---
	if is_instance_valid(detailed_view_toggle):
		detailed_view_toggle.button_pressed = show_detailed_view # Set initial state
		_update_detailed_view_toggle_position() # Set initial position
		detailed_view_toggle.toggled.connect(_on_detailed_view_toggled)
		# print('Main: Detailed View toggle initialized and connected.')
	else:
		printerr('Main: DetailedViewToggleCheckbox node not found or invalid. Check the path in main.gd.')

	_on_viewport_size_changed() # Call once at the end of _ready to ensure all initial positions/constraints are correct


func _center_map_on_load():
	if not is_instance_valid(map_container) or not is_instance_valid(map_display):
		return
	if map_display.size.x == 0 or map_display.size.y == 0: # Not yet sized
		return

	var viewport_size = get_viewport_rect().size
	# Start with the map centered
	map_container.position = (viewport_size - (map_display.size * map_container.scale)) / 2.0
	_constrain_map_container_position()


func _on_viewport_size_changed():
	# print('Main: _on_viewport_size_changed triggered.') # DEBUG
	# map_display.size is fixed. map_container.position might need adjustment.
	if is_instance_valid(map_container):
		_constrain_map_container_position() # Re-apply constraints based on new viewport size

	# Update positions of UI elements that depend on viewport/map_display size
	if not Engine.is_editor_hint() and is_instance_valid(_refresh_notification_label): # Only update in game
		_update_refresh_notification_position()
	if is_instance_valid(detailed_view_toggle):
		_update_detailed_view_toggle_position()

	# Map texture doesn't need re-render, but UI elements might need updates
	# due to clamping changes from pan/zoom constraints.
	# UIManager's update_ui_elements will handle this.
	call_deferred("_update_map_display", false) # false = don't re-render map texture, just update UI

func _update_map_display(force_rerender_map_texture: bool = true, is_light_ui_update: bool = false):
	# print("Main: _update_map_display() CALLED - TOP") # DEBUG

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
	var map_render_target_size = map_display.size
	if map_render_target_size.x == 0 or map_render_target_size.y == 0:
		printerr("Main: _update_map_display - map_display.size is zero. Cannot render. Returning.")
		return

	var throb_phase_for_render = _throb_phase
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("is_dragging"):
		if map_interaction_manager.is_dragging():
			throb_phase_for_render = 0.0 # Freeze throb animation during drag

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
		var map_texture: ImageTexture = map_renderer_node.render_map(
			map_tiles,
			[],  # highlights
			[],  # lowlights
			Color(0,0,0,0), # Let map_render use its own default highlight color
			Color(0,0,0,0), # Let map_render use its own default lowlight color
			map_render_target_size,    # Target size for the map texture (full map)
			_all_convoy_data,         # Pass the convoy data
			throb_phase_for_render,   # Pass potentially frozen throb phase
			_convoy_id_to_color_map,  # Pass the color map
			hover_info_for_render,      # Pass hover info from MIM
			selected_ids_for_render,     # Pass selected convoy IDs from MIM
			show_detailed_view,       # Pass detailed view flag for grid
			show_detailed_view        # Pass detailed view flag for political colors
		)
		# print('Main: map_renderer.render_map call completed.')  # DEBUG

		# --- Display the map ---
		if map_texture:
			# print('Main: map_texture is valid. Size: ', map_texture.get_size(), ' Format: ', map_texture.get_image().get_format() if map_texture.get_image() else 'N/A')  # DEBUG
			# Generate mipmaps for the texture if the TextureRect's filter uses them.
			# This improves quality when the texture is scaled down.
			if map_display and (map_display.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS or \
							   map_display.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS):
				var img := map_texture.get_image()
				if img:  # Ensure image is valid
					# print('Main: Generating mipmaps for map texture.')  # DEBUG
					img.generate_mipmaps()  # This modifies the image in-place; ImageTexture will update.
			map_display.texture = map_texture
			# No longer need to set map_display.set_size here, stretch_mode handles it.
			# print('Main: Map (re)rendered and displayed on map_display node.')  # DEBUG
		else:
			printerr('Failed to render map texture.')

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
			
	if is_instance_valid(ui_manager):
		# print("Main: _update_map_display - ui_manager IS VALID. CALLING update_ui_elements NOW.") # DEBUG
		ui_manager.update_ui_elements(
			map_display,
			map_tiles,
			_all_convoy_data,
			_all_settlement_data,
			_convoy_id_to_color_map,
			hover_info_for_render,
			selected_ids_for_render, # This is _selected_convoy_ids from MIM
			user_positions_for_ui,      # Pass the up-to-date user positions
			dragging_panel_for_ui,      # Pass the currently dragged panel (or null)
			dragged_id_for_ui,          # Pass the ID of the currently dragged panel (or empty)
			is_light_ui_update,         # Pass the light update flag
			_current_zoom               # Pass the current zoom level
		)
		# print("Main: _update_map_display - ui_manager.update_ui_elements() CALL COMPLETED.") # DEBUG
	else:
		printerr("Main: _update_map_display - ui_manager IS NOT VALID. CANNOT CALL update_ui_elements.") # DEBUG


func _on_convoy_data_received(data: Variant) -> void:
	print('Main: Received convoy data from APICalls.gd!')

	if data is Array:
		_all_convoy_data = data
		print('Main: Stored %s convoy objects.' % data.size())
		if not data.is_empty() and data[0] is Dictionary:
			# print('Main: First convoy: ID %s, Name %s' % [data[0].get('convoy_id', 'N/A'), data[0].get('convoy_name', 'N/A')]) # DEBUG
			pass # Keep it quieter
		elif data.is_empty():
			print('Main: Received an empty list of convoys.')
	elif data is Dictionary and data.has('results') and data['results'] is Array:  # Common API pattern
		_all_convoy_data = data['results']
		print('Main: Stored %s convoy objects from "results" key.' % _all_convoy_data.size())
	else:
		_all_convoy_data = []  # Clear if data is not in expected array format
		printerr('Main: Received convoy data is not an array or recognized structure. Clearing stored convoy data. Data: ', data)

	# Update convoy ID to color mapping
	for convoy_item in _all_convoy_data:
		if convoy_item is Dictionary:
			var convoy_id_val = convoy_item.get('convoy_id')
			if convoy_id_val != null: # Check for null, as ID could be 0
				var convoy_id_str = str(convoy_id_val)
				if not convoy_id_str.is_empty() and not _convoy_id_to_color_map.has(convoy_id_str):
					# This convoy ID is new, assign it the next available color
					_last_assigned_color_idx = (_last_assigned_color_idx + 1) % PREDEFINED_CONVOY_COLORS.size()
					_convoy_id_to_color_map[convoy_id_str] = PREDEFINED_CONVOY_COLORS[_last_assigned_color_idx]

	# Re-render the map with the new convoy data
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("update_data_references"):
		map_interaction_manager.update_data_references(_all_convoy_data, _all_settlement_data, map_tiles)
	else:
		printerr("Main (_on_convoy_data_received): Cannot update MapInteractionManager data references.")

	_update_map_display()




func _on_data_refresh_tick() -> void:
	# print('Main: Refresh timer timeout. Requesting updated convoy data...')
	if api_calls_node:
		api_calls_node.get_all_in_transit_convoys()
	else:
		printerr('Main: Cannot refresh convoy data, api_calls_node is not valid.')

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
	# print("Main: _on_visual_update_timer_timeout() CALLED.") # DEBUG

	var do_visual_update = true
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("is_dragging"):
		if map_interaction_manager.is_dragging():
			do_visual_update = false # Don't update throb phase if dragging

	if do_visual_update:
		# Update throb phase for a 1-second cycle
		if is_instance_valid(game_timers_node) and game_timers_node.has_method("get_visual_update_interval"):
			_throb_phase += game_timers_node.get_visual_update_interval()
			_throb_phase = fmod(_throb_phase, 1.0)  # Wrap around 1.0
		else:
			# Fallback or error if GameTimersNode isn't available, though it should be.
			printerr("Main: GameTimersNode not found or 'get_visual_update_interval' missing for throb phase calculation.")
	
	# Re-render the map with the new throb phase (deferred if not dragging, direct if dragging to avoid lag)
	# and UI elements.
	call_deferred("_update_map_display", true) # true = force rerender for throb
	# Connector lines are redrawn by UIManager via its update_ui_elements call


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
	# VERY IMPORTANT DEBUG: Log all events reaching main.gd's _input
	# print("Main _input RECEIVED EVENT --- Type: %s, Event: %s" % [event.get_class(), event]) # DEBUG: Performance intensive
	# if event is InputEventMouseButton:
		# print("    InputEventMouseButton --- button_index: %s, pressed: %s, shift_pressed: %s, global_pos: %s" % [event.button_index, event.pressed, event.is_shift_pressed(), event.global_position]) # DEBUG
	# elif event is InputEventMouseMotion:
		# print("    InputEventMouseMotion --- global_pos: %s, relative: %s, button_mask: %s" % [event.global_position, event.relative, event.button_mask]) # DEBUG
	# elif event is InputEventPanGesture: # DEBUG: Log PanGesture details
		# print("    InputEventPanGesture --- delta: %s, position: %s" % [event.delta, event.position]) # DEBUG
	# You can add more elif for other event types like InputEventScreenTouch, InputEventGesture if needed

	if not is_instance_valid(map_container): return # Cannot pan/zoom without container

	# --- Panning Input ---
	# Middle Mouse Button OR Shift + Left Mouse Button for panning
	var is_pan_button_pressed = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE
	var is_alt_pan_button_pressed = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_shift_pressed()

	if is_pan_button_pressed or is_alt_pan_button_pressed:
		if event.pressed:
			_is_panning = true
			_last_pan_mouse_pos = event.global_position
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			get_viewport().set_input_as_handled()
			return # Consume event
		else:
			# Only stop panning if the button being released is one of the pan buttons
			# and we are currently in panning mode.
			if _is_panning:
				_is_panning = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				get_viewport().set_input_as_handled()
				return # Consume event

	if event is InputEventMouseMotion and _is_panning:
		var motion_delta = event.global_position - _last_pan_mouse_pos
		map_container.position += motion_delta
		_last_pan_mouse_pos = event.global_position
		_constrain_map_container_position() # Ensure map stays within bounds
		_map_view_needs_light_ui_update = true # Signal that UI needs update in _process
		get_viewport().set_input_as_handled() # Consume event
		return # Consume event

	# --- Zooming Input (Mouse Wheel) ---
	var zoom_in_detected: bool = false
	var zoom_out_detected: bool = false

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in_detected = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out_detected = true
	elif event is InputEventPanGesture:
		# For InputEventPanGesture, delta.y is typically negative for "scroll up" (zoom in)
		# and positive for "scroll down" (zoom out).
		# The magnitude of delta can vary, so we might only care about the sign.
		# You might need to adjust the threshold (0.01 here) or invert if behavior is opposite.
		if event.delta.y < -0.01: # Small negative delta for zoom in
			zoom_in_detected = true
		elif event.delta.y > 0.01: # Small positive delta for zoom out
			zoom_out_detected = true

	if zoom_in_detected or zoom_out_detected:
		if event is InputEventMouseButton:
			# print("Main: Zoom event (MouseWheel) detected, button_index: ", event.button_index) # DEBUG
			pass
		elif event is InputEventPanGesture:
			# print("Main: Zoom event (PanGesture) detected, delta.y: ", event.delta.y) # DEBUG
			pass
		else:
			# print("Main: Zoom event (Unknown Type) detected: ", event) # DEBUG
			pass

		var mouse_pos_global = get_global_mouse_position()
		# Point on the map (under the mouse) in map_container's local space, *before* new scale is applied
		var point_local_old = map_container.to_local(mouse_pos_global)
		# print("Main: Zoom - mouse_pos_global: ", mouse_pos_global, ", point_local_old: ", point_local_old) # DEBUG

		var old_zoom = _current_zoom
		if zoom_in_detected:
			# print("Main: Zooming IN. Old zoom: ", old_zoom) # DEBUG
			_current_zoom = min(_current_zoom * zoom_factor_increment, max_zoom)
		elif zoom_out_detected:
			# print("Main: Zooming OUT. Old zoom: ", old_zoom) # DEBUG_
			var attempted_new_zoom = _current_zoom / zoom_factor_increment

			var viewport_size = get_viewport_rect().size
			var dynamic_min_zoom_x = 0.0
			if _map_base_width_pixels > 0.001: # Prevent division by zero / very small numbers
				dynamic_min_zoom_x = viewport_size.x / _map_base_width_pixels
			
			var dynamic_min_zoom_y = 0.0
			if _map_base_height_pixels > 0.001: # Prevent division by zero / very small numbers
				dynamic_min_zoom_y = viewport_size.y / _map_base_height_pixels
				
			# This is the minimum zoom required for the map to cover the viewport
			var min_zoom_to_cover_viewport = max(dynamic_min_zoom_x, dynamic_min_zoom_y)

			# The effective minimum zoom is the greater of the dynamic cover limit and the user-defined absolute min_zoom
			var effective_min_zoom_limit = self.min_zoom # Start with the exported min_zoom
			if min_zoom_to_cover_viewport > 0.0001: # If calculated dynamic zoom is valid
				effective_min_zoom_limit = max(effective_min_zoom_limit, min_zoom_to_cover_viewport)

			_current_zoom = max(attempted_new_zoom, effective_min_zoom_limit)
		# print("Main: Zoom - New calculated zoom: ", _current_zoom) # DEBUG

		if abs(_current_zoom - old_zoom) > 0.0001: # If zoom actually changed
			# print("Main: Zoom - Zoom changed significantly. Applying scale.") # DEBUG
			map_container.scale = Vector2(_current_zoom, _current_zoom)

			# Adjust map_container's position to keep 'point_local_old' (the point on the map
			# that was under the mouse) under 'mouse_pos_global' (the mouse cursor) after scaling.
			map_container.position = mouse_pos_global - point_local_old * _current_zoom
			# print("Main: Zoom - map_container.position adjusted to: ", map_container.position) # DEBUG
			_constrain_map_container_position() # Constrain immediately
			_map_view_needs_light_ui_update = true # Signal that UI needs update in _process
			get_viewport().set_input_as_handled() # Consume event
			return # Consume event
		else: # DEBUG
			# print("Main: Zoom - Zoom did NOT change significantly enough (or hit min/max). old_zoom: ", old_zoom, " new_zoom: ", _current_zoom) # DEBUG
			pass

	# Forward input to MapInteractionManager
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("handle_input"):
		map_interaction_manager.handle_input(event)
		# Check if MIM consumed the event (important for when MIM fully handles drag)
		if get_viewport().is_input_handled():
			# If MIM handled the input (e.g., consumed it for a drag operation or a map click),
			# and it wasn't already handled by pan/zoom above.
			# then main.gd doesn't need to do anything further with this event.
			return

	# If MIM didn't handle the event, or if MIM doesn't exist,
	# any further general input processing for main.gd itself (not related to map/panel interaction)
	# could go here. For now, there isn't any.
	# Example:
	# if event.is_action_pressed("ui_cancel"):
	#     get_tree().quit()

	# The old drag logic and hover detection that was in main.gd's _input
	# is now fully handled by MapInteractionManager or by main.gd reacting to
	# signals from MapInteractionManager.

func _process(_delta: float) -> void:
	if _map_view_needs_light_ui_update:
		# print("Main _process: Performing light UI update due to map view change.") # DEBUG
		# Perform a light UI update because the map's position or zoom changed.
		# false = don't re-render map texture, true = light UI update (e.g., clamp labels)
		_update_map_display(false, true) 
		_map_view_needs_light_ui_update = false

func _constrain_map_container_position():
	if not is_instance_valid(map_container) or not is_instance_valid(map_display):
		return
	if map_display.size.x == 0 or map_display.size.y == 0: # map_display not sized yet
		return

	var viewport_size = get_viewport_rect().size
	var scaled_map_width = map_display.size.x * map_container.scale.x
	var scaled_map_height = map_display.size.y * map_container.scale.y

	var new_pos = map_container.position

	# If map is wider than viewport, constrain its horizontal position
	if scaled_map_width > viewport_size.x:
		new_pos.x = clamp(new_pos.x, viewport_size.x - scaled_map_width, 0.0)
	else: # Map is narrower than or equal to viewport width, center it
		new_pos.x = (viewport_size.x - scaled_map_width) / 2.0

	# If map is taller than viewport, constrain its vertical position
	if scaled_map_height > viewport_size.y:
		new_pos.y = clamp(new_pos.y, viewport_size.y - scaled_map_height, 0.0)
	else: # Map is shorter than or equal to viewport height, center it
		new_pos.y = (viewport_size.y - scaled_map_height) / 2.0
		
	map_container.position = new_pos


func _update_refresh_notification_position():
	if not is_instance_valid(_refresh_notification_label):
		return

	var viewport_size = get_viewport_rect().size
	# Ensure the label has its size calculated based on current text and font settings
	var label_size = _refresh_notification_label.get_minimum_size()

	var padding = label_map_edge_padding # Use the class member
	_refresh_notification_label.position = Vector2(viewport_size.x - label_size.x - padding, viewport_size.y - label_size.y - padding)

# --- UI Toggle Handler ---
func _on_detailed_view_toggled(button_pressed: bool) -> void:
	show_detailed_view = button_pressed
	# print('Main: Detailed view toggled to: ', show_detailed_view)
	_update_map_display(true) # Re-render the map with new detail settings


func _update_detailed_view_toggle_position() -> void:
	if not is_instance_valid(detailed_view_toggle):
		return

	var viewport_size = get_viewport_rect().size
	var toggle_size: Vector2 = detailed_view_toggle.get_minimum_size() # Get its actual size based on text and font
	var padding = label_map_edge_padding # Use the class member

	detailed_view_toggle.position = Vector2(
		viewport_size.x - toggle_size.x - padding,
		viewport_size.y - toggle_size.y - padding
	)

# _on_connector_lines_container_draw is now handled by UIManager.gd

# --- Signal Handlers for MapInteractionManager ---
func _on_mim_hover_changed(new_hover_info: Dictionary):
	_current_hover_info = new_hover_info
	print("Main: _on_mim_hover_changed. New hover: ", _current_hover_info) # DEBUG
	# OLD: _update_map_display() was causing a full map re-render on hover.

	# NEW: Directly update UI elements without re-rendering the entire map.
	if is_instance_valid(ui_manager):
		# Gather necessary arguments for UIManager, similar to how _update_map_display does it,
		# but specifically for a UI-only update.
		var user_positions_for_ui = _convoy_label_user_positions # Use main's current understanding
		# Use main.gd's own drag state as the source of truth for UI updates triggered by hover changes.
		# This state is set by _on_mim_panel_drag_started and cleared by _on_mim_panel_drag_ended.
		var dragging_panel_for_ui = self._dragging_panel_node 
		var dragged_id_for_ui = self._dragged_convoy_id_actual_str

		if is_instance_valid(map_interaction_manager):
			if map_interaction_manager.has_method("get_convoy_label_user_positions"):
				# It's still good to get the latest user positions from MIM if it's the authority for that.
				user_positions_for_ui = map_interaction_manager.get_convoy_label_user_positions() 
		
		# DEBUG: Log what drag state is being passed to UIManager during a hover change.
		print("  _on_mim_hover_changed: Passing to UIManager - new_hover_info: %s, dragging_panel: %s, dragged_id: %s" % [new_hover_info, dragging_panel_for_ui, dragged_id_for_ui])
		
		ui_manager.update_ui_elements(
			map_display,
			map_tiles,
			_all_convoy_data,
			_all_settlement_data,
			_convoy_id_to_color_map,
			new_hover_info, # Use the new_hover_info directly
			_selected_convoy_ids, # Use the current selection state
			user_positions_for_ui,
			dragging_panel_for_ui,
			dragged_id_for_ui,
			true,                 # is_light_ui_update: true for hover changes
			_current_zoom         # Pass the current zoom level (12th argument)
		)
	else:
		printerr("Main (_on_mim_hover_changed): ui_manager is not valid. Cannot update UI.")
func _on_mim_selection_changed(new_selected_ids: Array):
	_selected_convoy_ids = new_selected_ids
	# print("Main: MIM selection changed: ", _selected_convoy_ids) # DEBUG

	# User positions are no longer cleared from _convoy_label_user_positions here.
	# The UIManager will be responsible for showing/hiding labels based on selection,
	# and using the stored user position if available when a label is shown.
	# If ui_manager.clear_convoy_user_position was meant to tell UIManager to forget
	# its own cached position, that specific call might also need reconsideration based on UIManager's design.	
	_update_map_display(true) # Force rerender for selection changes (e.g., journey lines, highlights)

func _on_mim_panel_drag_ended(convoy_id_str: String, final_local_position: Vector2):
	print("Main: _on_mim_panel_drag_ended for convoy: %s. Panel node was: %s, IsValid: %s" % [convoy_id_str, _dragging_panel_node, is_instance_valid(_dragging_panel_node)]) # DEBUG
	_convoy_label_user_positions[convoy_id_str] = final_local_position # Update main's copy

	# Clear main.gd's internal drag state
	var previously_dragged_panel = _dragging_panel_node
	_dragging_panel_node = null # Crucial to clear this
	_dragged_convoy_id_actual_str = ""
	_drag_offset = Vector2.ZERO # Reset drag offset
	
	# After clearing internal state, print status of the panel that WAS being dragged
	if is_instance_valid(previously_dragged_panel):
		print("  DragEnd: Panel %s is still valid. Visible: %s, Pos: %s, GlobalPos: %s, Parent: %s" % [convoy_id_str, previously_dragged_panel.visible, previously_dragged_panel.position, previously_dragged_panel.global_position, previously_dragged_panel.get_parent()])

	Input.set_default_cursor_shape(Input.CURSOR_ARROW) # Reset cursor

	if is_instance_valid(ui_manager) and ui_manager.has_method("set_dragging_state"):
		ui_manager.set_dragging_state(null, "", false) # Inform UIManager drag has ended

	# Panel drag ended, UI needs update, map texture itself doesn't.
	_update_map_display(false)

func _on_mim_panel_drag_started(convoy_id_str: String, panel_node: Panel):
	print("Main: PanelDragStart: Convoy: %s, PanelNode: %s, IsValid: %s" % [convoy_id_str, panel_node, is_instance_valid(panel_node)])
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
		print("  PanelDragStart: Panel %s initial state before UIM/move_child - Visible: %s, Pos: %s, GlobalPos: %s, Parent: %s" % [convoy_id_str, _dragging_panel_node.visible, _dragging_panel_node.position, _dragging_panel_node.global_position, _dragging_panel_node.get_parent()])
	else: # Should not happen due to check above, but as a safeguard
		printerr("Main: PanelDragStart: _dragging_panel_node became invalid unexpectedly for convoy %s." % convoy_id_str)
		_dragging_panel_node = null # Ensure it's null if invalid
		_dragged_convoy_id_actual_str = ""
		return

	Input.set_default_cursor_shape(Input.CURSOR_DRAG)

	if is_instance_valid(ui_manager) and ui_manager.has_method("set_dragging_state"):
		ui_manager.set_dragging_state(_dragging_panel_node, _dragged_convoy_id_actual_str, true)
		print("  PanelDragStart: Called ui_manager.set_dragging_state for %s." % convoy_id_str)
	else:
		printerr("Main: PanelDragStart: UIManager or set_dragging_state method not available for %s." % convoy_id_str)

	# Bring panel to front
	if is_instance_valid(ui_manager) and ui_manager.has_method("get_convoy_label_container_node"):
		var label_container = ui_manager.get_convoy_label_container_node()
		if is_instance_valid(label_container):
			if is_instance_valid(_dragging_panel_node):
				if _dragging_panel_node.get_parent() == label_container:
					label_container.move_child(_dragging_panel_node, label_container.get_child_count() - 1)
					print("  PanelDragStart: Moved panel %s to front of container '%s'." % [convoy_id_str, label_container.name])
				else:
					printerr("  PanelDragStart: Panel %s parent is NOT the expected label container. Parent: %s, ExpectedContainer: %s" % [convoy_id_str, _dragging_panel_node.get_parent(), label_container])
			else:
				printerr("  PanelDragStart: _dragging_panel_node became invalid before move_child for %s." % convoy_id_str)
		else:
			printerr("  PanelDragStart: UIManager's label container node is not valid for %s." % convoy_id_str)
	else:
		printerr("Main: PanelDragStart: UIManager or get_convoy_label_container_node method not available for move_child operation for %s." % convoy_id_str)
	
	if is_instance_valid(_dragging_panel_node):
		print("  PanelDragStart: Panel %s final state after UIM/move_child - Visible: %s, Pos: %s, GlobalPos: %s, Parent: %s" % [convoy_id_str, _dragging_panel_node.visible, _dragging_panel_node.position, _dragging_panel_node.global_position, _dragging_panel_node.get_parent()])

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
	print("Main: PanelDragUpdate for %s. Panel IsValid: %s, Visible: %s. CurrentLocalPos: %s. Attempting NewLocalPos: %s. Parent: %s" % [convoy_id_str, is_instance_valid(_dragging_panel_node), _dragging_panel_node.visible, _dragging_panel_node.position, new_panel_local_position, _dragging_panel_node.get_parent()]) # DEBUG
	
	if is_instance_valid(_dragging_panel_node): # Double check before assigning position
		_dragging_panel_node.position = new_panel_local_position # Update the actual panel's local position

	if is_instance_valid(ui_manager) and ui_manager.has_method("get_convoy_connector_lines_container_node"):
		var connector_container = ui_manager.get_convoy_connector_lines_container_node()
		if is_instance_valid(connector_container):
			connector_container.queue_redraw() # Redraw connector lines
		# else: print("Main: PanelDragUpdate: Connector container not valid for redraw.") # Can be noisy
	# else: print("Main: PanelDragUpdate: UIManager or connector container getter not available.") # Can be noisy
