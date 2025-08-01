# Scripts/UI/main_screen.gd
extends Control

# This script acts as a mediator between the MenuManager and the MapView/CameraController.
# It listens for signals from the MenuManager and adjusts the UI layout accordingly,
# then informs the camera about its new visible area.

var map_view: Control = null
var map_camera_controller: Node = null
var map_interaction_manager: Node = null
var _interactive_state_is_pending: bool = false
var _pending_interactive_state: bool = false

@onready var menu_container = $MainContainer/MainContent/MenuContainer
@onready var top_bar = $MainContainer/TopBar

func initialize(p_map_view: Control, p_camera_controller: Node, p_interaction_manager: Node):
	self.map_view = p_map_view
	map_camera_controller = p_camera_controller
	map_interaction_manager = p_interaction_manager

	# Connect to the MapView's specific input signal
	if is_instance_valid(map_view):
		if not map_view.is_connected("gui_input", Callable(self, "_on_map_view_gui_input")):
			map_view.gui_input.connect(Callable(self, "_on_map_view_gui_input"))
			print("[MainScreen] Connected to map_view's gui_input signal.")
	else:
		printerr("MainScreen: Could not find map_view node to connect its input.")

	# If set_map_interactive was called before we were ready, apply the state now.
	if _interactive_state_is_pending:
		set_map_interactive(_pending_interactive_state)
		_interactive_state_is_pending = false


# Camera input state
var _is_panning := false
var _map_ready_for_focus: bool = false
var _has_fitted_camera: bool = false

func _ready():
	# Defer the initial camera setup to ensure the UI layout is stable.
	call_deferred("_initial_camera_and_ui_setup")

	# Connect to the MenuManager's signal that indicates when a menu is opened or closed.
	var menu_manager = get_node_or_null("/root/MenuManager")
	if menu_manager:
		if not menu_manager.is_connected("menu_visibility_changed", Callable(self, "_on_menu_visibility_changed")):
			menu_manager.connect("menu_visibility_changed", Callable(self, "_on_menu_visibility_changed"))
			print("[MainScreen] Successfully connected to MenuManager's menu_visibility_changed signal.")
	else:
		printerr("MainScreen: CRITICAL - Could not find MenuManager at /root/MenuManager. Camera adjustments will not work.")

	# Connect the button in the top bar to a function that asks the MenuManager to open the menu.
	var convoy_button = top_bar.find_child("ConvoyMenuButton")
	if convoy_button:
		if not convoy_button.is_connected("pressed", Callable(self, "on_convoy_button_pressed")):
			convoy_button.pressed.connect(on_convoy_button_pressed)
	else:
		printerr("MainScreen: Could not find ConvoyMenuButton in TopBar.")



func _initial_camera_and_ui_setup():
	# This function is called deferred from _ready to ensure node sizes are correct.
	# Wait one frame to be absolutely sure all UI nodes have settled.
	await get_tree().process_frame
	
	# Now that the layout is stable, tell the camera controller the correct viewport.
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("update_map_viewport_rect"):
		var map_rect = map_view.get_global_rect()
		print("[MainScreen] Initial setup: Notifying camera of viewport rect: ", map_rect)
		map_camera_controller.update_map_viewport_rect(map_rect)
	
	# If the map data is already loaded, fit the camera now.
	if _map_ready_for_focus and not _has_fitted_camera:
		_fit_camera_to_map()


func _on_map_view_gui_input(event: InputEvent):
	if not is_instance_valid(map_camera_controller):
		return

	# 1. Let the interaction manager handle its specific inputs first (clicks, panel drags).
	if is_instance_valid(map_interaction_manager) and map_interaction_manager.has_method("handle_map_input"):
		map_interaction_manager.handle_map_input(event)
		if get_viewport().is_input_handled():
			# The interaction manager consumed the event (e.g., started a panel drag, clicked a convoy).
			# Reset panning state just in case and stop further processing.
			_is_panning = false
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			return

	# 2. If the event was not consumed by the interaction manager, handle camera movement.
	# This means the click was on the map background, not an interactive element.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_panning = true
				Input.set_default_cursor_shape(Input.CURSOR_DRAG)
				get_viewport().set_input_as_handled() # Consume the event
			else:
				_is_panning = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				get_viewport().set_input_as_handled() # Consume the event
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			map_camera_controller.zoom_at_screen_pos(map_camera_controller.camera_zoom_factor_increment, event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			map_camera_controller.zoom_at_screen_pos(1.0 / map_camera_controller.camera_zoom_factor_increment, event.position)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if _is_panning:
			# The camera's pan function expects a screen-space delta (invert for natural feel)
			map_camera_controller.pan(-event.relative)
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		map_camera_controller.zoom_at_screen_pos(event.factor, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		# The camera's pan function expects a screen-space delta
		map_camera_controller.pan(event.delta)
		get_viewport().set_input_as_handled()


# Called by the MenuManager's signal when a menu is opened or closed.

func _on_menu_visibility_changed(is_open: bool, menu_width_ratio: float):
	print("[MainScreen] Menu visibility changed. Is open: %s, Ratio: %s" % [is_open, menu_width_ratio])

	# Show/hide the placeholder container that makes space for the menu.
	menu_container.visible = is_open

	# Adjust the stretch ratio of the map and menu containers to resize them.
	if is_open:
		# The map takes up the remaining space.
		map_view.size_flags_stretch_ratio = 1.0 - menu_width_ratio
		menu_container.size_flags_stretch_ratio = menu_width_ratio
	else:
		# The map takes up the full width.
		map_view.size_flags_stretch_ratio = 1.0
		menu_container.size_flags_stretch_ratio = 0.0

	# Wait for the layout to update before notifying the camera controller.
	# This ensures the camera gets the correct, new dimensions of the map view.
	await get_tree().process_frame

	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("update_map_viewport_rect"):
		var map_rect = map_view.get_global_rect()
		print("[MainScreen] Notifying camera of new viewport rect: ", map_rect)
		map_camera_controller.update_map_viewport_rect(map_rect)
	else:
		printerr("MainScreen: Could not find MapCameraController or it lacks update_map_viewport_rect method.")

	# After the first layout, if the map is ready, fit the camera
	if _map_ready_for_focus and not _has_fitted_camera:
		_fit_camera_to_map()


# Called when the map_ready_for_focus signal is emitted from main.gd
func _on_map_ready_for_focus():
	print("[MainScreen] Received map_ready_for_focus signal.")
	_map_ready_for_focus = true
	# If the layout is already done, fit the camera now
	if is_instance_valid(map_camera_controller) and not _has_fitted_camera:
		_fit_camera_to_map()

# Helper to fit the camera to the map only once
func _fit_camera_to_map():
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("fit_camera_to_tilemap"):
		map_camera_controller.fit_camera_to_tilemap()
		_has_fitted_camera = true
		print("[MainScreen] fit_camera_to_tilemap called.")


# Called when the convoy button in the top bar is pressed.
func on_convoy_button_pressed():
	var menu_manager = get_node_or_null("/root/MenuManager")
	if menu_manager and menu_manager.has_method("open_convoy_menu"):
		# This call will trigger the MenuManager to show the menu and emit the
		# 'menu_visibility_changed' signal, which is handled by the function above.
		menu_manager.open_convoy_menu() # Assumes it opens for the currently selected convoy.
	else:
		printerr("MainScreen: Could not find MenuManager or its 'open_convoy_menu' method.")


func set_map_interactive(is_interactive: bool):
	if is_instance_valid(map_camera_controller):
		# If the controller is valid, apply the setting immediately.
		if map_camera_controller.has_method("set_interactive"):
			map_camera_controller.set_interactive(is_interactive)
			print("MainScreen: MapView interaction set to: %s" % is_interactive)
		else:
			printerr("MainScreen: MapCameraController is valid but is missing 'set_interactive' method.")
	else:
		# If the controller is NOT valid, it means we've been called before initialize().
		# We store the desired state to be applied later.
		_interactive_state_is_pending = true
		_pending_interactive_state = is_interactive
		print("MainScreen: MapCameraController not ready. Storing pending interactive state: %s" % is_interactive)
