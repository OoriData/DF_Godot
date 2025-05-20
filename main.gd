# main.gd
extends Node2D

# Preload the map rendering script
const MapRenderer = preload('res://map_render.gd')
# Reference the node that will display the map
@onready var map_display: TextureRect = $MapDisplay

# Reference to your APICalls node.
# IMPORTANT: Adjust the path "$APICallsInstance" to the actual path of your APICalls node
# in your scene tree relative to the node this script (main.gd) is attached to.
@onready var api_calls_node: Node = $APICallsInstance # Adjust if necessary
# IMPORTANT: Adjust this path to where you actually place your detailed view toggle in your scene tree!
@onready var ui_manager: Node = $UIManagerNode # Adjust path to your UIManager node
@onready var detailed_view_toggle: CheckBox = $DetailedViewToggleCheckbox # Example path
@onready var map_interaction_manager: Node = $MapInteractionManager # Path to your MapInteractionManager node
# IMPORTANT: Adjust the path "$GameTimersNode" to the actual path of your GameTimers node in your scene tree.
@onready var game_timers_node: Node = $GameTimersNode # Adjust if necessary

var map_renderer  # Will be initialized in _ready()
var map_tiles: Array = []  # Will hold the loaded tile data
var _all_settlement_data: Array = []  # To store settlement data for rendering
var _all_convoy_data: Array = []  # To store convoy data from APICalls
# Constants still needed in main.gd for hover detection or passed to map_renderer
const LABEL_MAP_EDGE_PADDING: float = 5.0 # Pixels to keep labels from map edge
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
const CONVOY_HOVER_RADIUS_ON_TEXTURE_SQ: float = 625.0  # (25 pixels)^2, adjust as needed
const SETTLEMENT_HOVER_RADIUS_ON_TEXTURE_SQ: float = 400.0  # (20 pixels)^2, adjust as needed for settlements

var _current_hover_info: Dictionary = {}  # Will be updated by MapInteractionManager signal
var _selected_convoy_ids: Array[String] = []  # Will be updated by MapInteractionManager signal

var show_detailed_view: bool = true  # Single flag for toggling detailed map features (grid & political)

var _dragging_panel_node: Panel = null  # Will be updated by MapInteractionManager signal or getter
var _drag_offset: Vector2 = Vector2.ZERO  # This state will move to MapInteractionManager
var _convoy_label_user_positions: Dictionary = {}  # Will be updated by MapInteractionManager signal
var _dragged_convoy_id_actual_str: String = "" # Will be updated by MapInteractionManager signal or getter
var _current_drag_clamp_rect: Rect2  # This state will move to MapInteractionManager


func _ready():
	# print('Main: _ready() called.')  # DEBUG

	# Enable input processing for this Node2D to receive _input events,
	# including those propagated from its Control children (like MapDisplay).
	set_process_input(true)
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
	var file_path = 'res://foo.json'
	var file = FileAccess.open(file_path, FileAccess.READ)

	var err_code = FileAccess.get_open_error()
	if err_code != OK:
		printerr('Error opening map json file: ', file_path)
		printerr('FileAccess error code: ', err_code)  # DEBUG
		return

	# print('Main: Successfully opened foo.json.')  # DEBUG
	var json_string = file.get_as_text()
	file.close()

	var json_data = JSON.parse_string(json_string)

	if json_data == null:
		printerr('Error parsing JSON map data from: ', file_path)
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
		return

	# Populate _all_settlement_data from map_tiles
	_all_settlement_data.clear()
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
	map_renderer = MapRenderer.new() # Initialize the class member here

	# Ensure map_display is correctly sized and positioned before the first render
	# and before any UI elements dependent on its size/position are placed.
	if is_instance_valid(map_display):
		map_display.position = Vector2.ZERO
		map_display.size = get_viewport_rect().size

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
	_update_map_display() # Now render the map with map_display correctly sized

	# Connect to the viewport's size_changed signal to re-render on window resize
	get_viewport().connect('size_changed', Callable(self, '_on_viewport_size_changed'))
	_on_viewport_size_changed() # Call once at the end of _ready to ensure all initial positions are correct

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

	# Setup the refresh notification label
	_refresh_notification_label = Label.new()
	_refresh_notification_label.text = 'Data Refreshed!'
	# Basic styling - you can customize this further
	_refresh_notification_label.add_theme_font_size_override('font_size', 24)
	_refresh_notification_label.add_theme_color_override('font_color', Color.LIGHT_GREEN)
	_refresh_notification_label.add_theme_color_override('font_outline_color', Color.BLACK)
	_refresh_notification_label.add_theme_constant_override('outline_size', 2)
	_refresh_notification_label.modulate.a = 0.0  # Start invisible
	_refresh_notification_label.z_index = 10 # Ensure notification is on top of everything
	_refresh_notification_label.name = 'RefreshNotificationLabel'
	add_child(_refresh_notification_label)  # Add as a direct child of this Node2D
	_update_refresh_notification_position()  # Set initial position

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

	# print('Main: Visual update timer started for every %s seconds.' % VISUAL_UPDATE_INTERVAL_SECONDS)
	# print('Main: Convoy data refresh timer started for every %s seconds.' % REFRESH_INTERVAL_SECONDS)


func _on_viewport_size_changed():
	# print('Main: _on_viewport_size_changed triggered.') # DEBUG
	# Ensure map_display is always at the origin of its parent and fills the viewport
	if is_instance_valid(map_display):
		map_display.position = Vector2.ZERO
		map_display.size = get_viewport_rect().size
		# print('Main: map_display reset to position (0,0) and size: ', map_display.size) # DEBUG

	# Update positions of UI elements that depend on viewport/map_display size
	if is_instance_valid(_refresh_notification_label):
		_update_refresh_notification_position()
	if is_instance_valid(detailed_view_toggle):
		_update_detailed_view_toggle_position()
	call_deferred("_update_map_display") # Defer to ensure layout is settled


func _update_map_display():
	# print("Main: _update_map_display() CALLED - TOP") # DEBUG

	# Get dragging state from MapInteractionManager if it's valid
	var is_currently_dragging: bool = false
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("is_dragging"):
		is_currently_dragging = map_interaction_manager.is_dragging()
	if is_currently_dragging:
		return

	if map_tiles.is_empty():
		# printerr('Main: _update_map_display - Cannot update map display: map_tiles is empty. Returning.') # DEBUG - Can be noisy if data loads late
		return
	if not map_renderer:
		printerr('Main: _update_map_display - Cannot update map display: map_renderer is not initialized. Returning.') # DEBUG
		return

	if not is_instance_valid(map_display): # Added safety check
		printerr('Main: _update_map_display - map_display is not valid. Cannot render. Returning.') # DEBUG
		return

	# print("Main: _update_map_display - Passed initial checks.") # DEBUG

	# --- Render the map ---
	# Get the current viewport size to pass to the renderer
	var current_viewport_size = get_viewport().get_visible_rect().size

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
	var map_texture: ImageTexture = map_renderer.render_map(
		map_tiles,
		[],  # highlights
		[],  # lowlights
		MapRenderer.DEFAULT_HIGHLIGHT_OUTLINE_COLOR,
		MapRenderer.DEFAULT_LOWLIGHT_INLINE_COLOR,
		current_viewport_size,    # Viewport size
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
	var user_positions_for_ui = _convoy_label_user_positions # Use the one updated by signal
	var dragging_panel_for_ui = null
	var dragged_id_for_ui = ""
	if is_instance_valid(map_interaction_manager):
		if map_interaction_manager.has_method("get_convoy_label_user_positions"):
			user_positions_for_ui = map_interaction_manager.get_convoy_label_user_positions()
		if map_interaction_manager.has_method("get_dragging_panel_node"):
			dragging_panel_for_ui = map_interaction_manager.get_dragging_panel_node()
		if map_interaction_manager.has_method("get_dragged_convoy_id_str"):
			dragged_id_for_ui = map_interaction_manager.get_dragged_convoy_id_str()

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
			dragged_id_for_ui           # Pass the ID of the currently dragged panel (or empty)
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
		printerr("Main: Cannot update MapInteractionManager data references.")

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
	call_deferred("_update_map_display")  # Re-render the map with the new throb phase (deferred)
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
	# Forward input to MapInteractionManager
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("handle_input"):
		map_interaction_manager.handle_input(event)
		# Check if MIM consumed the event (important for when MIM fully handles drag)
		if get_viewport().is_input_handled():
			# If MIM handled the input (e.g., consumed it for a drag operation or a map click),
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



func _update_refresh_notification_position():
	if not is_instance_valid(_refresh_notification_label):
		return

	var viewport_size = get_viewport_rect().size
	# Ensure the label has its size calculated based on current text and font settings
	var label_size = _refresh_notification_label.get_minimum_size()

	var padding: float = 10.0  # Pixels from the edge
	_refresh_notification_label.position = Vector2(viewport_size.x - label_size.x - padding, viewport_size.y - label_size.y - padding)

# --- UI Toggle Handler ---
func _on_detailed_view_toggled(button_pressed: bool) -> void:
	show_detailed_view = button_pressed
	# print('Main: Detailed view toggled to: ', show_detailed_view)
	_update_map_display() # Re-render the map


func _update_detailed_view_toggle_position() -> void:
	if not is_instance_valid(detailed_view_toggle):
		return
	# print('--- Debug: _update_detailed_view_toggle_position ---') # DEBUG

	if not map_display or not is_instance_valid(map_display.texture):
		printerr('Main: Cannot position detailed_view_toggle, map_display or its texture is invalid. Hiding toggle.')
		detailed_view_toggle.visible = false # Hide it if we can't position it
		return
	detailed_view_toggle.visible = true # Make sure it's visible if we CAN position it

	# print('map_display.position: ', map_display.position) # DEBUG
	# print('map_display.size: ', map_display.size) # DEBUG

	var map_texture_size: Vector2 = map_display.texture.get_size()
	var map_display_rect_size: Vector2 = map_display.size
	if map_texture_size.x <= 0 or map_texture_size.y <= 0: # More robust check
		printerr('Main: map_texture_size is zero. Aborting toggle position update.')
		return
	# print('map_texture_size: ', map_texture_size) # DEBUG

	var scale_x_ratio: float = map_display_rect_size.x / map_texture_size.x
	var scale_y_ratio: float = map_display_rect_size.y / map_texture_size.y
	var actual_scale: float = min(scale_x_ratio, scale_y_ratio)
	# print('actual_scale: ', actual_scale) # DEBUG

	var displayed_texture_width: float = map_texture_size.x * actual_scale
	var displayed_texture_height: float = map_texture_size.y * actual_scale
	# print('displayed_texture_width: ', displayed_texture_width, ', displayed_texture_height: ', displayed_texture_height) # DEBUG

	var offset_x: float = (map_display_rect_size.x - displayed_texture_width) / 2.0
	var offset_y: float = (map_display_rect_size.y - displayed_texture_height) / 2.0
	# print('offset_x: ', offset_x, ', offset_y: ', offset_y) # DEBUG

	var toggle_size: Vector2 = detailed_view_toggle.get_minimum_size() # Get its actual size based on text and font
	# print('toggle_size: ', toggle_size) # DEBUG
	# print('LABEL_MAP_EDGE_PADDING: ', LABEL_MAP_EDGE_PADDING) # DEBUG

	# Position relative to the displayed map texture area, with LABEL_MAP_EDGE_PADDING
	# offset_x/y are relative to map_display. detailed_view_toggle.position is relative to its parent (this Node2D).
	var target_x = map_display.position.x + offset_x + displayed_texture_width - toggle_size.x - LABEL_MAP_EDGE_PADDING
	var target_y = map_display.position.y + offset_y + displayed_texture_height - toggle_size.y - LABEL_MAP_EDGE_PADDING
	# print('Calculated target_x: ', target_x, ', target_y: ', target_y) # DEBUG
	detailed_view_toggle.position = Vector2(target_x, target_y)

# _on_connector_lines_container_draw is now handled by UIManager.gd

# --- Signal Handlers for MapInteractionManager ---
func _on_mim_hover_changed(new_hover_info: Dictionary):
	_current_hover_info = new_hover_info
	# print("Main: MIM hover changed: ", _current_hover_info) # DEBUG
	# _update_map_display() # OLD: This was causing a full map re-render on hover.

	# NEW: Directly update UI elements without re-rendering the entire map.
	if is_instance_valid(ui_manager):
		# Gather necessary arguments for UIManager, similar to how _update_map_display does it,
		# but specifically for a UI-only update.
		var user_positions_for_ui = _convoy_label_user_positions
		var dragging_panel_for_ui = null
		var dragged_id_for_ui = ""
		if is_instance_valid(map_interaction_manager):
			if map_interaction_manager.has_method("get_convoy_label_user_positions"):
				user_positions_for_ui = map_interaction_manager.get_convoy_label_user_positions()
			if map_interaction_manager.has_method("get_dragging_panel_node"):
				dragging_panel_for_ui = map_interaction_manager.get_dragging_panel_node()
			if map_interaction_manager.has_method("get_dragged_convoy_id_str"):
				dragged_id_for_ui = map_interaction_manager.get_dragged_convoy_id_str()

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
			dragged_id_for_ui
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
	_update_map_display() # Update visuals based on new selection

func _on_mim_panel_drag_ended(convoy_id_str: String, final_local_position: Vector2):
	_convoy_label_user_positions[convoy_id_str] = final_local_position # Update main's copy

	# Clear main.gd's internal drag state
	_dragging_panel_node = null
	_dragged_convoy_id_actual_str = ""
	_drag_offset = Vector2.ZERO # Reset drag offset

	Input.set_default_cursor_shape(Input.CURSOR_ARROW) # Reset cursor

	if is_instance_valid(ui_manager) and ui_manager.has_method("set_dragging_state"):
		ui_manager.set_dragging_state(null, "", false) # Inform UIManager drag has ended

	_update_map_display()

func _on_mim_panel_drag_started(convoy_id_str: String, panel_node: Panel):
	# print("Main: MIM panel_drag_started signal received for convoy: ", convoy_id_str) # DEBUG
	_dragging_panel_node = panel_node
	_dragged_convoy_id_actual_str = convoy_id_str

	# Calculate drag offset based on the panel's current global position and the mouse position
	if is_instance_valid(_dragging_panel_node):
		_drag_offset = _dragging_panel_node.global_position - get_global_mouse_position()

	Input.set_default_cursor_shape(Input.CURSOR_DRAG)

	if is_instance_valid(ui_manager) and ui_manager.has_method("set_dragging_state"):
		ui_manager.set_dragging_state(_dragging_panel_node, _dragged_convoy_id_actual_str, true)

	# Bring panel to front
	if is_instance_valid(ui_manager) and is_instance_valid(ui_manager.convoy_label_container) and \
	   is_instance_valid(_dragging_panel_node) and _dragging_panel_node.get_parent() == ui_manager.convoy_label_container:
		ui_manager.convoy_label_container.move_child(_dragging_panel_node, ui_manager.convoy_label_container.get_child_count() - 1)

func _on_mim_panel_drag_updated(convoy_id_str: String, new_panel_local_position: Vector2):
	# print("Main: MIM panel_drag_updated for convoy: ", convoy_id_str, " to local_pos: ", new_panel_local_position) # DEBUG
	if is_instance_valid(_dragging_panel_node) and _dragged_convoy_id_actual_str == convoy_id_str: # Ensure we're updating the correct panel
		# _dragging_panel_node is set by _on_mim_panel_drag_started
		_dragging_panel_node.position = new_panel_local_position # Update the actual panel's local position

	if is_instance_valid(ui_manager) and is_instance_valid(ui_manager.convoy_connector_lines_container):
		ui_manager.convoy_connector_lines_container.queue_redraw()
