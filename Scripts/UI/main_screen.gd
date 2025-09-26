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
			# print("[DFCAM-DEBUG] MainScreen: Connected to map_view's gui_input signal.")
	# else:
	# 	printerr("[DFCAM-DEBUG] MainScreen: Could not find map_view node to connect its input.")

	# If set_map_interactive was called before we were ready, apply the state now.
	if _interactive_state_is_pending:
		set_map_interactive(_pending_interactive_state)
		_interactive_state_is_pending = false


# Camera input state
var _is_panning := false
var _map_ready_for_focus: bool = false
var _has_fitted_camera: bool = false

# --- Options snapshot (from SettingsManager) ---
var _opt_invert_pan := false
var _opt_invert_zoom := false
var _opt_gestures_enabled := true
var _opt_click_closes_menus := true
var _opt_menu_ratio_open := 2.0


func _ready():
	# Defer the initial camera setup to ensure the UI layout is stable.
	# print("[DFCAM-DEBUG] MainScreen: _ready called, deferring initial camera/UI setup.")
	call_deferred("_initial_camera_and_ui_setup")

	# Connect to the MenuManager's signal that indicates when a menu is opened or closed.
	var menu_manager = get_node_or_null("/root/MenuManager")
	if menu_manager:
		# NEW: Register this screen's menu container with the manager.
		if menu_manager.has_method("register_menu_container"):
			menu_manager.register_menu_container(menu_container)
		else:
			printerr("MainScreen: CRITICAL - MenuManager is missing 'register_menu_container' method.")

		if not menu_manager.is_connected("menu_visibility_changed", Callable(self, "_on_menu_visibility_changed")):
			menu_manager.connect("menu_visibility_changed", Callable(self, "_on_menu_visibility_changed"))
			# print("[MainScreen] Successfully connected to MenuManager's menu_visibility_changed signal.")
		# Listen for convoy focus requests with data
		if not menu_manager.is_connected("convoy_menu_focus_requested", Callable(self, "_on_convoy_menu_focus_requested")):
			menu_manager.connect("convoy_menu_focus_requested", Callable(self, "_on_convoy_menu_focus_requested"))
	else:
		printerr("MainScreen: CRITICAL - Could not find MenuManager at /root/MenuManager. Camera adjustments will not work.")

	# Connect the button in the top bar to a function that asks the MenuManager to open the menu.
	var convoy_button = top_bar.find_child("ConvoyMenuButton")
	if convoy_button:
		if not convoy_button.is_connected("pressed", Callable(self, "on_convoy_button_pressed")):
			convoy_button.pressed.connect(on_convoy_button_pressed)
	else:
		printerr("MainScreen: Could not find ConvoyMenuButton in TopBar.")

	# --- Window/MapView Resize Handling ---
	# Use _notification for resize events instead of connecting to nonexistent signal
	# Also connect to map_view's size_changed if available
	if is_instance_valid(map_view):
		if not map_view.is_connected("size_changed", Callable(self, "_on_map_view_size_changed")):
			map_view.connect("size_changed", Callable(self, "_on_map_view_size_changed"))

	# --- Load Options from SettingsManager and subscribe ---
	var sm = get_node_or_null("/root/SettingsManager")
	if is_instance_valid(sm):
		_apply_settings_snapshot()
		if not sm.is_connected("setting_changed", Callable(self, "_on_setting_changed")):
			sm.setting_changed.connect(_on_setting_changed)
# Respond to Control resize events
func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_on_main_screen_size_changed()


func _on_main_screen_size_changed():
	# Called when MainScreen is resized (window resize or layout change)
	_update_camera_viewport_rect_on_resize()

func _on_map_view_size_changed():
	# Called when MapView is resized (e.g., due to menu open/close or container resize)
	_update_camera_viewport_rect_on_resize()

# Call this after the main screen is visible and unpaused to ensure camera is correct
func force_camera_update():
	await get_tree().process_frame  # Wait for layout to settle
	_update_camera_viewport_rect_on_resize()

func _update_camera_viewport_rect_on_resize():
	if is_instance_valid(map_view) and is_instance_valid(map_camera_controller) and map_camera_controller.has_method("update_map_viewport_rect"):
		var map_rect = map_view.get_global_rect()
		map_camera_controller.update_map_viewport_rect(map_rect)
		# Only fit to full map when no menu is open, to avoid overriding convoy focus
		var menu_manager = get_node_or_null("/root/MenuManager")
		var menu_open = false
		if is_instance_valid(menu_manager) and menu_manager.has_method("is_any_menu_active"):
			menu_open = menu_manager.is_any_menu_active()
		if not menu_open and map_camera_controller.has_method("fit_camera_to_tilemap"):
			map_camera_controller.fit_camera_to_tilemap()



func _initial_camera_and_ui_setup():
	# This function is called deferred from _ready to ensure node sizes are correct.
	# Wait one frame to be absolutely sure all UI nodes have settled.
	await get_tree().process_frame

	# NEW: Ensure the menu is hidden on startup by directly hiding the container.
	# This is safer than calling the full visibility function before the camera is ready.
	menu_container.hide()
	# print("[DFCAM-DEBUG] MainScreen: Menu container hidden on startup.")
	
	# Now that the layout is stable, tell the camera controller the correct viewport.
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("update_map_viewport_rect"):
		var map_rect = map_view.get_global_rect()
		# print("[DFCAM-DEBUG] MainScreen: Initial setup, notifying camera of viewport rect=", map_rect)
		map_camera_controller.update_map_viewport_rect(map_rect)
		if map_camera_controller.has_method("fit_camera_to_tilemap"):
			map_camera_controller.fit_camera_to_tilemap()
	# else:
	# 	printerr("[DFCAM-DEBUG] MainScreen: Camera controller not valid or missing update_map_viewport_rect.")


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

	# 2. If the event was not consumed by the interaction manager, handle camera movement and menu closing.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Close any open menu when clicking the map
				var menu_manager = get_node_or_null("/root/MenuManager")
				if menu_manager and menu_manager.has_method("is_any_menu_active") and menu_manager.is_any_menu_active():
					menu_manager.close_all_menus() # This will close all menus and update layout
					get_viewport().set_input_as_handled()
					return
				_is_panning = true
				Input.set_default_cursor_shape(Input.CURSOR_DRAG)
				get_viewport().set_input_as_handled() # Consume the event
			else:
				_is_panning = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				get_viewport().set_input_as_handled() # Consume the event
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			var inc: float = float(map_camera_controller.camera_zoom_factor_increment)
			var factor: float = (1.0 / inc) if _opt_invert_zoom else inc
			map_camera_controller.zoom_at_screen_pos(factor, event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			var inc2: float = float(map_camera_controller.camera_zoom_factor_increment)
			var factor2: float = inc2 if _opt_invert_zoom else (1.0 / inc2)
			map_camera_controller.zoom_at_screen_pos(factor2, event.position)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if _is_panning:
			# The camera's pan function expects a screen-space delta
			var delta: Vector2 = event.relative
			if not _opt_invert_pan:
				delta = -delta
			map_camera_controller.pan(delta)
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		if _opt_gestures_enabled:
			var f: float = float(event.factor)
			var z: float = f if not _opt_invert_zoom else (1.0 / max(0.0001, f))
			map_camera_controller.zoom_at_screen_pos(z, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		# The camera's pan function expects a screen-space delta
		if _opt_gestures_enabled:
			var d: Vector2 = event.delta
			if not _opt_invert_pan:
				d = -d
			map_camera_controller.pan(d)
		get_viewport().set_input_as_handled()


# Called by the MenuManager's signal when a menu is opened or closed.

func _on_menu_visibility_changed(is_open: bool, _menu_name: String):
	# print("[DFCAM-DEBUG] MainScreen: Menu visibility changed. Is open: %s" % is_open)


	# The stretch ratio determines how space is distributed in the HBoxContainer.
	# When the menu is open, we want a 2:1 ratio (menu:map).
	# When closed, we want a 0:1 ratio, giving the map all the space.

	# Always set stretch ratios and force layout update
	var main_content = menu_container.get_parent()
	var main_map = main_content.get_node_or_null("Main")
	if is_open:
		menu_container.size_flags_stretch_ratio = _opt_menu_ratio_open
		if is_instance_valid(main_map):
			main_map.size_flags_stretch_ratio = 1.0
		menu_container.show()
		# print("[DFCAM-DEBUG] MainScreen: Menu opened, set stretch ratios (menu=2, map=1)")
	else:
		menu_container.size_flags_stretch_ratio = 0.0
		if is_instance_valid(main_map):
			main_map.size_flags_stretch_ratio = 1.0
			main_map.show() # Ensure map view is visible
			# Force map view to fill the parent container
			if main_map.has_method("set_anchors_and_offsets_preset"):
				main_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		menu_container.hide()
		# print("[DFCAM-DEBUG] MainScreen: Menu closed, set stretch ratios (menu=0, map=1) and map to full size")
	if main_content:
		main_content.queue_sort()

	# Wait for the layout to update before notifying the camera controller.
	await get_tree().process_frame

	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("update_map_viewport_rect"):
		var map_rect = map_view.get_global_rect()
		# print("[DFCAM-DEBUG] MainScreen: Notifying camera of new viewport rect=", map_rect)
		map_camera_controller.update_map_viewport_rect(map_rect)

		if is_open:
			# Focus on the convoy associated with the active menu
			var menu_manager = get_node_or_null("/root/MenuManager")
			if is_instance_valid(menu_manager):
				var active_menu = menu_manager.get("current_active_menu") if menu_manager.has_method("get") else null
				if active_menu and active_menu.has_meta("menu_data"):
					var convoy_data = active_menu.get_meta("menu_data")
					if convoy_data and map_camera_controller.has_method("focus_on_convoy"):
						map_camera_controller.focus_on_convoy(convoy_data)
		else:
			# When closing menus, re-fit to the full tilemap
			if map_camera_controller.has_method("fit_camera_to_tilemap"):
				map_camera_controller.fit_camera_to_tilemap()
	# else:
	# 	printerr("[DFCAM-DEBUG] MainScreen: Could not find MapCameraController or it lacks update_map_viewport_rect method.")

	# After the first layout, if the map is ready, fit the camera
	# (Removed call to _fit_camera_to_map() to fix parser error)
	# if _map_ready_for_focus and not _has_fitted_camera:
	#     _fit_camera_to_map()


# --- Settings integration ---
func _apply_settings_snapshot():
	var sm = get_node_or_null("/root/SettingsManager")
	if not is_instance_valid(sm):
		return
	_opt_invert_pan = bool(sm.get_value("controls.invert_pan", _opt_invert_pan))
	_opt_invert_zoom = bool(sm.get_value("controls.invert_zoom", _opt_invert_zoom))
	_opt_gestures_enabled = bool(sm.get_value("controls.gestures_enabled", _opt_gestures_enabled))
	_opt_click_closes_menus = bool(sm.get_value("ui.click_closes_menus", _opt_click_closes_menus))
	_opt_menu_ratio_open = float(sm.get_value("ui.menu_open_ratio", _opt_menu_ratio_open))

func _on_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"controls.invert_pan", "controls.invert_zoom", "controls.gestures_enabled", "ui.click_closes_menus":
			_apply_settings_snapshot()
		"ui.menu_open_ratio":
			_apply_settings_snapshot()
			_apply_menu_ratio_if_open()

func _apply_menu_ratio_if_open():
	# If the menu container is visible, update its stretch ratio live
	if not is_instance_valid(menu_container):
		return
	if menu_container.visible:
		var main_content = menu_container.get_parent()
		var main_map = main_content.get_node_or_null("Main") if is_instance_valid(main_content) else null
		menu_container.size_flags_stretch_ratio = _opt_menu_ratio_open
		if is_instance_valid(main_map):
			main_map.size_flags_stretch_ratio = 1.0
		if is_instance_valid(main_content):
			main_content.queue_sort()


# Called when the menu asks specifically to focus on a convoy (with data)
func _on_convoy_menu_focus_requested(convoy_data: Dictionary):
	# Ensure layout has settled and camera sees final rect
	await get_tree().process_frame
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("focus_on_convoy"):
		map_camera_controller.focus_on_convoy(convoy_data)


# Called when the map_ready_for_focus signal is emitted from main.gd
func _on_map_ready_for_focus():
	# print("[DFCAM-DEBUG] MainScreen: Received map_ready_for_focus signal.")
	_map_ready_for_focus = true
	await get_tree().process_frame  # Wait for UI to settle
	if is_instance_valid(map_camera_controller) and not _has_fitted_camera:
		var map_rect = map_view.get_global_rect()
		# print("[DFCAM-DEBUG] MainScreen: map_ready_for_focus, updating camera viewport rect=", map_rect)
		map_camera_controller.update_map_viewport_rect(map_rect)
		if map_camera_controller.has_method("fit_camera_to_tilemap"):
			map_camera_controller.fit_camera_to_tilemap()
		_has_fitted_camera = true
		# print("[DFCAM-DEBUG] MainScreen: fit_camera_to_tilemap called.")


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
