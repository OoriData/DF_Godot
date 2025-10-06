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
@onready var _onboarding_layer: Control = Control.new()
@onready var _highlight_layer: Control = Control.new()
var _highlight_canvas: CanvasLayer = null

# Track the convoy dropdown popup for dynamic avoidance during tutorial coaching
var _convoy_dropdown_popup: Control = null

# Onboarding coach overlay for guiding next steps (e.g., buy first vehicle)
const ONBOARDING_COACH_SCRIPT_PATH := "res://Scripts/UI/onboarding_coach.gd"
const TUTORIAL_DIRECTOR_SCRIPT_PATH := "res://Scripts/UI/tutorial_director.gd"
var _buy_vehicle_coach: Control = null
var _buy_vehicle_coach_dismissed: bool = false
var _welcome_shown: bool = false
var _walkthrough_state: String = "" # "hint_convoy_button" -> "hint_settlement_button" -> "done"
var _walkthrough_messages := {
	"hint_convoy_button": "Use the convoy selector in the top bar to open the Convoy menu. This dropdown lets you switch between convoys and focuses the UI on the one you pick.",
	"hint_settlement_button": "This is the Convoy menu—where you can inspect vehicles, cargo, routes, and more. For now, click the [b]Settlement[/b] button to interact with the current settlement.",
	"hint_vendor_tab": "Welcome to the settlement vendors. You can buy and sell with different vendors here. Switch to the [b]Dealership[/b] tab to shop for vehicles.",
	"hint_vendor_vehicles": "Dealership: Browse available vehicles, compare stats, and buy one to add it to your convoy. Select the [b]Vehicles[/b] category, choose a model, then press [b]Buy[/b].",
	# Stage 2 (Resources: Market)
	"s2_hint_convoy_button": "Now that you have a vehicle, your crew needs [b]Water[/b] and [b]Food[/b]. Open the convoy menu from the top bar to visit the settlement vendors.",
	"s2_hint_settlement_button": "From the Convoy menu, press [b]Settlement[/b] to visit vendors at your current location.",
	"s2_hint_market_tab": "Go to the [b]Market[/b] tab.",
	"s2_hint_resources_category": "In the Market, expand/select the [b]Resources[/b] dropdown.",
	"s2_hint_select_water": "Select [b]Water Jerry Cans[/b] from Resources.",
	"s2_hint_buy_water": "Set quantity to [b]2[/b] and press [b]Buy[/b] to purchase Water Jerry Cans.",
	"s2_hint_select_food": "Now select [b]MRE Boxes[/b] from Resources.",
	"s2_hint_buy_food": "Set quantity to [b]2[/b] and press [b]Buy[/b] to purchase MREs."
}

# Tutorial director manages step order and back/forward navigation
var _tutorial_director: Node = null
var _current_tutorial_stage: int = 0 # 0=unknown, 1=buy-vehicle, 2=resources
var _s2_progress := {
	"bought_water": false,
	"bought_food": false
}

# Helper: read the user's tutorial stage safely from GameDataManager
func _get_user_tutorial_stage() -> int:
	var gdm = get_node_or_null("/root/GameDataManager")
	if not is_instance_valid(gdm):
		return 0
	if not gdm.has_method("get_current_user_data"):
		return 0
	var u: Dictionary = gdm.get_current_user_data()
	if typeof(u) != TYPE_DICTIONARY:
		return 0
	var md = u.get("metadata", {})
	if typeof(md) != TYPE_DICTIONARY or not md.has("tutorial"):
		return 0
	var t = md["tutorial"]
	if typeof(t) == TYPE_INT:
		return int(t)
	if typeof(t) == TYPE_FLOAT:
		return int(t)
	if typeof(t) == TYPE_STRING:
		return int(t)
	return 0

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

	# Ensure an overlay layer exists for onboarding modals (parented under the Map view so it cannot overlay menus)
	_ensure_onboarding_layer()
	# Ensure a global highlight layer (full screen, not clipped) so highlights can appear over menus/top bar
	_ensure_highlight_layer()


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

# Lazy binding for map-related nodes when initialize() isn't called externally
func _lazy_bind_map_nodes() -> void:
	if not is_instance_valid(map_view):
		var node = get_node_or_null("$MainContainer/MainContent/Main")
		if node and node is Control:
			map_view = node
	# Camera controller and interaction manager binding can be added here if needed

func refresh_tutorial_bounds() -> void:
	# Public method: can be called from GameScreenManager right after showing MainScreen
	_lazy_bind_map_nodes()
	_update_coach_bounds_and_avoid()

func _update_coach_bounds_and_avoid() -> void:
	# Centralized: set the coach bounds to the map area and avoid overlapping the menu container when visible.
	if not is_instance_valid(_buy_vehicle_coach):
		return
	if not is_instance_valid(map_view):
		return
	var rect: Rect2 = map_view.get_global_rect()
	if _buy_vehicle_coach.has_method("set_side_panel_bounds_by_global_rect"):
		_buy_vehicle_coach.call_deferred("set_side_panel_bounds_by_global_rect", rect)
	if _buy_vehicle_coach.has_method("set_side_panel_avoid_rects_global"):
		var avoids: Array = []
		if is_instance_valid(menu_container) and menu_container.visible:
			avoids.append(menu_container.get_global_rect())
		# Also avoid the convoy dropdown popup if it exists and is visible
		if is_instance_valid(_convoy_dropdown_popup) and _convoy_dropdown_popup.visible:
			avoids.append(_convoy_dropdown_popup.get_global_rect())
		_buy_vehicle_coach.call_deferred("set_side_panel_avoid_rects_global", avoids)


func _ready():
	_lazy_bind_map_nodes()
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

	# Bind signals from the convoy dropdown popup (if present) so we can avoid overlapping it
	_bind_convoy_dropdown_popup_signals()

	# --- Window/MapView Resize Handling ---
	# Use _notification for resize events instead of connecting to nonexistent signal
	# Also connect to map_view's size_changed if available
	if is_instance_valid(map_view):
		if not map_view.is_connected("size_changed", Callable(self, "_on_map_view_size_changed")):
			map_view.connect("size_changed", Callable(self, "_on_map_view_size_changed"))

	# Also react to menu container resize so tutorial box shrinks immediately when menu opens
	if is_instance_valid(menu_container):
		if not menu_container.is_connected("resized", Callable(self, "_on_menu_container_resized")):
			menu_container.resized.connect(_on_menu_container_resized)

	# --- Load Options from SettingsManager and subscribe ---
	var sm = get_node_or_null("/root/SettingsManager")
	if is_instance_valid(sm):
		_apply_settings_snapshot()
		if not sm.is_connected("setting_changed", Callable(self, "_on_setting_changed")):
			sm.setting_changed.connect(_on_setting_changed)

	# Subscribe to initial and convoy updates to detect empty state
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("initial_data_ready", Callable(self, "_on_initial_data_ready")):
			gdm.initial_data_ready.connect(_on_initial_data_ready)
		if not gdm.is_connected("convoy_data_updated", Callable(self, "_on_convoy_data_updated")):
			gdm.convoy_data_updated.connect(_on_convoy_data_updated)
		if not gdm.is_connected("user_data_updated", Callable(self, "_on_user_data_updated")):
			gdm.user_data_updated.connect(_on_user_data_updated)

	# Also listen for a successful vehicle purchase to dismiss the coach
	var api = get_node_or_null("/root/APICalls")
	if is_instance_valid(api) and api.has_signal("vehicle_bought"):
		if not api.is_connected("vehicle_bought", Callable(self, "_on_vehicle_bought")):
			api.vehicle_bought.connect(_on_vehicle_bought)
	# Stage 2: Also listen for resource/cargo buys to advance steps if user uses alternate flows
	if is_instance_valid(api):
		if api.has_signal("resource_bought") and not api.resource_bought.is_connected(Callable(self, "_on_any_resource_or_cargo_bought")):
			api.resource_bought.connect(_on_any_resource_or_cargo_bought)
		if api.has_signal("cargo_bought") and not api.cargo_bought.is_connected(Callable(self, "_on_any_resource_or_cargo_bought")):
			api.cargo_bought.connect(_on_any_resource_or_cargo_bought)

	# Listen to menu openings to advance hints
	var mm = get_node_or_null("/root/MenuManager")
	if is_instance_valid(mm) and mm.has_signal("menu_opened"):
		if not mm.is_connected("menu_opened", Callable(self, "_on_menu_opened_for_walkthrough")):
			mm.menu_opened.connect(_on_menu_opened_for_walkthrough)

	# Proactively check once after layout settles (in case no signals fire yet)
	call_deferred("_check_or_prompt_new_convoy")
	# Also initialize tutorial stage and attempt Stage 2 start if applicable
	_current_tutorial_stage = _get_user_tutorial_stage()
	call_deferred("_maybe_start_stage2_walkthrough")
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

func _on_menu_container_resized() -> void:
	# Called when the right menu width changes; recompute coach bounds/avoidance
	_update_coach_bounds_and_avoid()

func _on_convoy_popup_about_to_popup() -> void:
	# Wait one frame so the popup has a final size/position, then update avoidance
	await get_tree().process_frame
	_update_coach_bounds_and_avoid()

func _on_convoy_popup_hide() -> void:
	_update_coach_bounds_and_avoid()

func _on_convoy_popup_resized() -> void:
	if is_instance_valid(_convoy_dropdown_popup) and _convoy_dropdown_popup.visible:
		_update_coach_bounds_and_avoid()

func _bind_convoy_dropdown_popup_signals() -> void:
	if not is_instance_valid(top_bar):
		return
	# Find the ConvoyListPanel in the top bar
	var clp := top_bar.find_child("ConvoyListPanel", true, false)
	if clp and clp is Control:
		# Find its PopupPanel named ConvoyPopup
		var popup := (clp as Control).find_child("ConvoyPopup", true, false)
		if popup and popup is Control:
			_convoy_dropdown_popup = popup
			# Connect open/close signals
			if popup.has_signal("about_to_popup") and not popup.is_connected("about_to_popup", Callable(self, "_on_convoy_popup_about_to_popup")):
				popup.connect("about_to_popup", Callable(self, "_on_convoy_popup_about_to_popup"))
			if popup.has_signal("popup_hide") and not popup.is_connected("popup_hide", Callable(self, "_on_convoy_popup_hide")):
				popup.connect("popup_hide", Callable(self, "_on_convoy_popup_hide"))
			# Also track runtime size changes while open (Control.resized in Godot 4)
			if popup.has_signal("resized") and not popup.is_connected("resized", Callable(self, "_on_convoy_popup_resized")):
				popup.connect("resized", Callable(self, "_on_convoy_popup_resized"))

# Call this after the main screen is visible and unpaused to ensure camera is correct
func force_camera_update():
	await get_tree().process_frame  # Wait for layout to settle
	_update_camera_viewport_rect_on_resize()

func _update_camera_viewport_rect_on_resize():
	_lazy_bind_map_nodes()
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

	# Update coach side panel bounds and menu avoidance to keep it on the map area
	_update_coach_bounds_and_avoid()



func _initial_camera_and_ui_setup():
	_lazy_bind_map_nodes()
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

	# Initialize coach side panel bounds to map area as soon as layout is stable
	_update_coach_bounds_and_avoid()
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
				# Any click on the map (not handled elsewhere) should clear the current convoy selection
				var gdm = get_node_or_null("/root/GameDataManager")
				if is_instance_valid(gdm) and gdm.has_method("select_convoy_by_id"):
					# Pass empty string to deselect and disable toggle semantics
					gdm.select_convoy_by_id("", false)
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
		# When leaving any menu, ensure no convoy remains selected
		var gdm2 = get_node_or_null("/root/GameDataManager")
		if is_instance_valid(gdm2) and gdm2.has_method("select_convoy_by_id"):
			gdm2.select_convoy_by_id("", false)
		# print("[DFCAM-DEBUG] MainScreen: Menu closed, set stretch ratios (menu=0, map=1) and map to full size")
	if main_content:
		main_content.queue_sort()

	# Wait for the layout to update before notifying the camera controller.
	await get_tree().process_frame

	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("update_map_viewport_rect"):
		var map_rect = map_view.get_global_rect()
		# print("[DFCAM-DEBUG] MainScreen: Notifying camera of new viewport rect=", map_rect)
		map_camera_controller.update_map_viewport_rect(map_rect)

		# Also update the coach bounds and avoidance now that the map area changed
		_update_coach_bounds_and_avoid()

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

func _on_initial_data_ready():
	print("[Onboarding] initial_data_ready received; checking convoys…")
	_current_tutorial_stage = _get_user_tutorial_stage()
	_check_or_prompt_new_convoy()
	_maybe_start_stage2_walkthrough()

func _on_convoy_data_updated(all_convoys: Array):
	print("[Onboarding] convoy_data_updated received; convoys passed count=", (all_convoys.size() if all_convoys is Array else -1))
	_current_tutorial_stage = _get_user_tutorial_stage()
	_check_or_prompt_new_convoy(all_convoys)
	# After convoys update, consider showing the next coach (buy a vehicle)
	_maybe_show_buy_vehicle_coach()
	_maybe_run_vendor_walkthrough()
	_maybe_start_stage2_walkthrough()

func _on_user_data_updated(_user: Dictionary):
	print("[Onboarding] user_data_updated received; re-checking convoys…")
	# Print full user object so we can inspect tutorial flags/fields
	var user_dump := "<non-dict>"
	if typeof(_user) == TYPE_DICTIONARY:
		user_dump = JSON.stringify(_user)
		var md = _user.get("metadata", {})
		if typeof(md) == TYPE_DICTIONARY and md.has("tutorial"):
			var t = md["tutorial"]
			var stage = int(t) if typeof(t) in [TYPE_INT, TYPE_FLOAT] else -1
			print("[Onboarding] user.metadata.tutorial=", stage)
	print("[Onboarding] user object:", user_dump)
	_check_or_prompt_new_convoy()
	_maybe_show_buy_vehicle_coach()
	_maybe_run_vendor_walkthrough()
	# Refresh current stage and maybe start Stage 2
	_current_tutorial_stage = _get_user_tutorial_stage()
	_maybe_start_stage2_walkthrough()

func _check_or_prompt_new_convoy(all_convoys: Array = []):
	var gdm = get_node_or_null("/root/GameDataManager")
	var convoys := all_convoys
	if convoys.is_empty() and is_instance_valid(gdm) and gdm.has_method("get_all_convoy_data"):
		convoys = gdm.get_all_convoy_data()
	var has_any := convoys is Array and convoys.size() > 0

	# Determine tutorial stage from user metadata
	var tutorial_stage := -1
	if is_instance_valid(gdm) and gdm.has_method("get_current_user_data"):
		var u: Dictionary = gdm.get_current_user_data()
		if typeof(u) == TYPE_DICTIONARY:
			var md = u.get("metadata", {})
			if typeof(md) == TYPE_DICTIONARY and md.has("tutorial"):
				var t = md["tutorial"]
				if typeof(t) == TYPE_INT:
					tutorial_stage = t
				elif typeof(t) == TYPE_FLOAT:
					tutorial_stage = int(t)
				elif typeof(t) == TYPE_STRING:
					# Attempt to parse string to int
					var parsed := int(t)
					# If non-numeric strings become 0; guard with regex if needed later
					tutorial_stage = parsed

	print("[Onboarding] _check_or_prompt_new_convoy: gdm_valid=", is_instance_valid(gdm),
		" convoys_is_array=", (convoys is Array),
		" count=", (convoys.size() if convoys is Array else -1),
		" has_any=", has_any,
		" tutorial_stage=", tutorial_stage)

	# Gate the prompt strictly by tutorial stage: only when stage == 1 and user has no convoys
	if tutorial_stage != 1:
		print("[Onboarding] Tutorial stage is not 1; suppressing first-convoy prompt.")
		return

	if has_any:
		return

	# When there are no convoys and the tutorial stage applies, the inline coach naming
	# will be shown by _maybe_show_buy_vehicle_coach() which is already called by callers.
	# Nothing to do here.

func _ensure_onboarding_layer():
	# Ensure the overlay exists and is a child of the Map view, clipped to its bounds.
	_lazy_bind_map_nodes()
	if not is_instance_valid(map_view):
		# Fallback: parent to self to avoid crashes, but this should be temporary
		if not is_instance_valid(_onboarding_layer):
			_onboarding_layer = Control.new()
			_onboarding_layer.name = "OnboardingLayer"
		if _onboarding_layer.get_parent() != self:
			add_child(_onboarding_layer)
			move_child(_onboarding_layer, get_child_count()-1)
			_onboarding_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_onboarding_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return

	# Prefer a scene-based overlay if available (so it can be customized from the editor)
	var overlay_scene: PackedScene = load("res://Scenes/OnboardingLayer.tscn") if ResourceLoader.exists("res://Scenes/OnboardingLayer.tscn") else null
	if not is_instance_valid(_onboarding_layer):
		if overlay_scene != null:
			_onboarding_layer = overlay_scene.instantiate()
			_onboarding_layer.name = "OnboardingLayer"
		else:
			_onboarding_layer = Control.new()
			_onboarding_layer.name = "OnboardingLayer"
			# If programmatic, enable clipping so children never render outside the map area
			if _onboarding_layer.has_method("set"):
				_onboarding_layer.set("clip_contents", true)
	if _onboarding_layer.get_parent() != map_view:
		map_view.add_child(_onboarding_layer)
		# Ensure it's drawn above map content
		map_view.move_child(_onboarding_layer, map_view.get_child_count()-1)
	# Fit to map bounds and ignore mouse by default
	_onboarding_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_onboarding_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Ensure a director node exists under the overlay for step control
	_ensure_tutorial_director()

func _ensure_tutorial_director() -> void:
	if is_instance_valid(_tutorial_director):
		return
	var dir_script: Script = load(TUTORIAL_DIRECTOR_SCRIPT_PATH)
	if dir_script == null:
		printerr("[Onboarding] Failed to load tutorial director at ", TUTORIAL_DIRECTOR_SCRIPT_PATH)
		return
	_tutorial_director = Node.new()
	_tutorial_director.name = "TutorialDirector"
	_tutorial_director.set_script(dir_script)
	if is_instance_valid(_onboarding_layer):
		_onboarding_layer.add_child(_tutorial_director)
	# Define default ordered steps for the buy-vehicle walkthrough (Stage 1)
	var steps_s1 := [
		{"id": "hint_convoy_button"},
		{"id": "hint_settlement_button"},
		{"id": "hint_vendor_tab"},
		{"id": "hint_vendor_vehicles"},
	]
	if _tutorial_director.has_method("set_steps"):
		_tutorial_director.call("set_steps", steps_s1)
	# Wire step_changed -> render
	if _tutorial_director.has_signal("step_changed") and not _tutorial_director.is_connected("step_changed", Callable(self, "_on_tutorial_step_changed")):
		_tutorial_director.connect("step_changed", Callable(self, "_on_tutorial_step_changed"))

func _ensure_highlight_layer():
	# A full-screen, non-clipped overlay for drawing highlight borders over any UI (menus, top bar, map)
	# Ensure a CanvasLayer so highlights render above all other CanvasItems reliably
	if not is_instance_valid(_highlight_canvas):
		# Try find existing one by name
		var existing := get_node_or_null("HighlightCanvas")
		if existing and existing is CanvasLayer:
			_highlight_canvas = existing
		else:
			_highlight_canvas = CanvasLayer.new()
			_highlight_canvas.name = "HighlightCanvas"
			_highlight_canvas.layer = 100 # well above default layers
			add_child(_highlight_canvas)
	# Ensure the control host exists under the canvas layer
	if not is_instance_valid(_highlight_layer):
		_highlight_layer = Control.new()
		_highlight_layer.name = "HighlightLayer"
	if _highlight_layer.get_parent() != _highlight_canvas:
		if _highlight_layer.get_parent():
			_highlight_layer.get_parent().remove_child(_highlight_layer)
		_highlight_canvas.add_child(_highlight_layer)
	_highlight_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_highlight_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Legacy NewConvoyDialog helpers removed; inline naming is now handled by the coach panel.


# --- Onboarding coach: Buy first vehicle ---

func _ensure_coach() -> void:
	print("[Onboarding] _ensure_coach: start; dismissed=", _buy_vehicle_coach_dismissed, " coach_valid=", is_instance_valid(_buy_vehicle_coach))
	_ensure_onboarding_layer()
	if is_instance_valid(_buy_vehicle_coach):
		print("[Onboarding] _ensure_coach: exists; skipping create")
		return
	var coach_script: Script = load(ONBOARDING_COACH_SCRIPT_PATH)
	if coach_script == null:
		printerr("[Onboarding] Failed to load coach script at ", ONBOARDING_COACH_SCRIPT_PATH)
		return
	var coach := Control.new()
	coach.set_script(coach_script)
	_onboarding_layer.add_child(coach)
	_buy_vehicle_coach = coach
	print("[Onboarding] _ensure_coach: coach created and added under overlay")
	# Connect dismissed to suppress further prompts this session
	if _buy_vehicle_coach.has_signal("dismissed") and not _buy_vehicle_coach.is_connected("dismissed", Callable(self, "_on_buy_vehicle_coach_dismissed")):
		_buy_vehicle_coach.connect("dismissed", Callable(self, "_on_buy_vehicle_coach_dismissed"))
	# Immediately set bounds/avoidance so the panel is placed on the map area correctly
	_update_coach_bounds_and_avoid()
	# Route highlight overlays to global layer so they aren't clipped by the map overlay
	if _buy_vehicle_coach.has_method("set_highlight_host") and is_instance_valid(_highlight_layer):
		_buy_vehicle_coach.call_deferred("set_highlight_host", _highlight_layer)
		print("[Onboarding] _ensure_coach: highlight host set to global layer")

	# Also listen for returning to the map so we can reset tutorial to step 1
	var mm = get_node_or_null("/root/MenuManager")
	if is_instance_valid(mm):
		if mm.has_signal("menu_closed") and not mm.menu_closed.is_connected(Callable(self, "_on_menu_closed_for_walkthrough")):
			mm.menu_closed.connect(Callable(self, "_on_menu_closed_for_walkthrough"))
			print("[Onboarding] _ensure_coach: connected menu_closed for walkthrough reset")
		if mm.has_signal("menu_visibility_changed") and not mm.menu_visibility_changed.is_connected(Callable(self, "_on_menu_visibility_changed_for_walkthrough")):
			mm.menu_visibility_changed.connect(Callable(self, "_on_menu_visibility_changed_for_walkthrough"))
			print("[Onboarding] _ensure_coach: connected menu_visibility_changed for walkthrough reset")

func _on_tutorial_step_changed(step_id: String, index: int, total: int) -> void:
	# Mirror old state var for backward compatibility, then render that step
	_walkthrough_state = step_id
	_render_walkthrough_step(step_id, index, total)

func _hide_buy_vehicle_coach() -> void:
	if is_instance_valid(_buy_vehicle_coach):
		_buy_vehicle_coach.hide()

func _on_buy_vehicle_coach_dismissed() -> void:
	_buy_vehicle_coach_dismissed = true

func _on_vehicle_bought(_result: Dictionary) -> void:
	# Hide/dismiss when a vehicle is purchased
	_buy_vehicle_coach_dismissed = true
	_hide_buy_vehicle_coach()
	_clear_walkthrough()
	# Advance tutorial stage to 2 via API
	var gdm = get_node_or_null("/root/GameDataManager")
	var api = get_node_or_null("/root/APICalls")
	if is_instance_valid(gdm) and is_instance_valid(api) and api.has_method("update_user_metadata") and gdm.has_method("get_current_user_data"):
		var u: Dictionary = gdm.get_current_user_data()
		var user_id := String(u.get("user_id", "")) if typeof(u) == TYPE_DICTIONARY else ""
		if user_id != "":
			var merged_md: Dictionary = {}
			var existing_md2: Dictionary = (u.get("metadata", {}) if typeof(u) == TYPE_DICTIONARY else {})
			if typeof(existing_md2) == TYPE_DICTIONARY:
				merged_md = existing_md2.duplicate(true)
			var prev_tutorial: int = int(merged_md.get("tutorial", 1))
			merged_md["tutorial"] = prev_tutorial + 1
			api.call_deferred("update_user_metadata", user_id, merged_md)
	# Prepare Stage 2 state
	_current_tutorial_stage = 2
	_s2_progress["bought_water"] = false
	_s2_progress["bought_food"] = false
	# Optionally start Stage 2 immediately
	call_deferred("_maybe_start_stage2_walkthrough")

func _maybe_show_buy_vehicle_coach() -> void:
	if _buy_vehicle_coach_dismissed:
		return
	var gdm = get_node_or_null("/root/GameDataManager")
	if not is_instance_valid(gdm):
		return
	# Gate Level 1 hints entirely when tutorial stage >= 2
	var stage_now := _get_user_tutorial_stage()
	if stage_now >= 2:
		_hide_buy_vehicle_coach()
		return
	# Determine selected convoy or first convoy
	var convoy: Dictionary = {}
	if gdm.has_method("get_selected_convoy"):
		var sel = gdm.get_selected_convoy()
		if typeof(sel) == TYPE_DICTIONARY:
			convoy = sel
	if convoy.is_empty() and gdm.has_method("get_all_convoy_data"):
		var convoys: Array = gdm.get_all_convoy_data()
		if convoys is Array and convoys.size() > 0 and typeof(convoys[0]) == TYPE_DICTIONARY:
			convoy = convoys[0]
	if convoy.is_empty():
		# No convoy yet; inline create in the welcome coach
		_ensure_coach()
		if is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("show_convoy_naming"):
			# Guard to avoid reopening if already presenting
			if not has_meta("inline_convoy_naming_shown"):
				set_meta("inline_convoy_naming_shown", true)
			var prompt := "Welcome to Desolate Frontiers!\n\nLet's start by naming your first convoy."
			_buy_vehicle_coach.call_deferred("show_convoy_naming", prompt, Callable(self, "_on_inline_create_convoy"), "Create")
		return
	# Check if convoy has any vehicles
	var has_vehicles := false
	if convoy.has("vehicle_details_list") and convoy["vehicle_details_list"] is Array and (convoy["vehicle_details_list"] as Array).size() > 0:
		has_vehicles = true
	elif convoy.has("vehicles") and convoy["vehicles"] is Array and (convoy["vehicles"] as Array).size() > 0:
		has_vehicles = true
	if has_vehicles:
		_hide_buy_vehicle_coach()
		return

	# At this point we have a convoy with zero vehicles.
	# Show a short welcome modal once, then begin the 4-step walkthrough at step 1.
	_ensure_coach()
	if not _welcome_shown and is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("show_welcome"):
		var welcome_msg := "Welcome to Desolate Frontiers!\n\nFirst things first, let's get you started with a vehicle."
		_buy_vehicle_coach.call_deferred("show_welcome", welcome_msg, Callable(self, "_start_buy_vehicle_walkthrough"), "Start", "")
		return

	# If welcome already shown (or unsupported), ensure the walkthrough is running on step 1.
	_start_buy_vehicle_walkthrough()

func _start_buy_vehicle_walkthrough() -> void:
	_welcome_shown = true
	_ensure_tutorial_director()
	if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("start"):
		_tutorial_director.call("start", "hint_convoy_button")
	else:
		_walkthrough_state = "hint_convoy_button"
		_maybe_run_vendor_walkthrough()

func _on_inline_create_convoy(convoy_name: String) -> void:
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm) and gdm.has_method("create_new_convoy"):
		# Prevent duplicate creations by ensuring we only call once per show
		if not has_meta("inline_convoy_create_called"):
			set_meta("inline_convoy_create_called", true)
			gdm.create_new_convoy(convoy_name)
	# After creation, proceed to the buy-vehicle walkthrough
	_start_buy_vehicle_walkthrough()

func _open_settlement_menu_for_selected_convoy() -> void:
	var gdm = get_node_or_null("/root/GameDataManager")
	if not is_instance_valid(gdm):
		return
	var convoy: Dictionary = {}
	if gdm.has_method("get_selected_convoy"):
		var sel = gdm.get_selected_convoy()
		if typeof(sel) == TYPE_DICTIONARY:
			convoy = sel
	if convoy.is_empty() and gdm.has_method("get_all_convoy_data"):
		var convoys: Array = gdm.get_all_convoy_data()
		if convoys is Array and convoys.size() > 0 and typeof(convoys[0]) == TYPE_DICTIONARY:
			convoy = convoys[0]
	if convoy.is_empty():
		return
	var menu_manager = get_node_or_null("/root/MenuManager")
	if is_instance_valid(menu_manager) and menu_manager.has_method("open_convoy_settlement_menu"):
		menu_manager.open_convoy_settlement_menu(convoy)
	else:
		printerr("[Onboarding] Could not open settlement menu: MenuManager missing or method absent.")

func _maybe_run_vendor_walkthrough() -> void:
	if _buy_vehicle_coach_dismissed:
		print("[Onboarding] _maybe_run_vendor_walkthrough: dismissed; abort")
		return
	if _walkthrough_state == "":
		print("[Onboarding] _maybe_run_vendor_walkthrough: no state; abort")
		return
	_ensure_coach()
	if not is_instance_valid(_buy_vehicle_coach):
		print("[Onboarding] _maybe_run_vendor_walkthrough: coach invalid; abort")
		return
	print("[Onboarding] _maybe_run_vendor_walkthrough: state=", _walkthrough_state)
	# Always clear any previous highlight before applying the current step's highlight
	if _buy_vehicle_coach.has_method("clear_highlight"):
		_buy_vehicle_coach.call_deferred("clear_highlight")
	var total_steps := 4
	var idx := 1
	if is_instance_valid(_tutorial_director):
		if _tutorial_director.has_method("get_total_steps"):
			total_steps = int(_tutorial_director.call("get_total_steps"))
		if _tutorial_director.has_method("get_current_step_id") and _tutorial_director.call("get_current_step_id") == _walkthrough_state and _tutorial_director.has_method("get_step_index"):
			# Use 1-based index from director
			idx = int(_tutorial_director.call("get_step_index")) + 1
	match _walkthrough_state:
		# --- Stage 2 steps ---
		"s2_hint_convoy_button":
			if is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("show_step_message"):
				_buy_vehicle_coach.call_deferred("show_step_message", idx, total_steps, _walkthrough_messages.get(_walkthrough_state, ""))
			await get_tree().process_frame
			var rects_s2: Array = []
			if is_instance_valid(top_bar):
				var menu_btn2 := top_bar.find_child("ConvoyMenuButton", true, false)
				if menu_btn2 and menu_btn2 is Control:
					rects_s2.append((menu_btn2 as Control).get_global_rect())
				var clp2 := top_bar.find_child("ConvoyListPanel", true, false)
				if clp2 and clp2 is Control:
					var toggle2 := (clp2 as Control).find_child("ToggleButton", true, false)
					if toggle2 and toggle2 is Control:
						rects_s2.append((toggle2 as Control).get_global_rect())
			if not rects_s2.is_empty() and _buy_vehicle_coach.has_method("highlight_global_rect"):
				var ul2: Vector2 = rects_s2[0].position
				var br2: Vector2 = rects_s2[0].position + rects_s2[0].size
				for r2 in rects_s2:
					ul2.x = min(ul2.x, r2.position.x)
					ul2.y = min(ul2.y, r2.position.y)
					br2.x = max(br2.x, r2.position.x + r2.size.x)
					br2.y = max(br2.y, r2.position.y + r2.size.y)
				var union2 := Rect2(ul2, br2 - ul2)
				_buy_vehicle_coach.call_deferred("highlight_global_rect", union2)
		"s2_hint_settlement_button":
			var mm_s2 = get_node_or_null("/root/MenuManager")
			if is_instance_valid(mm_s2) and mm_s2.current_active_menu and mm_s2.current_active_menu.has_node("MainVBox/ScrollContainer/ContentVBox/MenuButtons/SettlementMenuButton"):
				var sbtn2: Control = mm_s2.current_active_menu.get_node("MainVBox/ScrollContainer/ContentVBox/MenuButtons/SettlementMenuButton")
				if is_instance_valid(sbtn2):
					if _buy_vehicle_coach.has_method("show_step_message"):
						_buy_vehicle_coach.call_deferred("show_step_message", idx, total_steps, _walkthrough_messages.get(_walkthrough_state, ""))
					if _buy_vehicle_coach.has_method("highlight_control"):
						_buy_vehicle_coach.call_deferred("highlight_control", sbtn2)
		"s2_hint_market_tab":
			var mm_m = get_node_or_null("/root/MenuManager")
			if is_instance_valid(mm_m) and mm_m.current_active_menu:
				# Wait until tabs are ready
				if mm_m.current_active_menu.has_signal("tabs_ready"):
					await mm_m.current_active_menu.tabs_ready
				var menu_m = mm_m.current_active_menu
				var tabs_m = menu_m.get_node_or_null("%VendorTabContainer")
				if tabs_m == null:
					tabs_m = menu_m.get_node_or_null("VendorTabContainer")
				if is_instance_valid(tabs_m):
					if _buy_vehicle_coach.has_method("show_step_message"):
						_buy_vehicle_coach.call_deferred("show_step_message", idx, total_steps, _walkthrough_messages.get(_walkthrough_state, ""))
					# Prefer the menu's Market helpers for index and rect
					var target_rect := Rect2()
					var market_idx := -1
					if menu_m.has_method("tutorial_get_market_tab_index"):
						market_idx = int(menu_m.call("tutorial_get_market_tab_index"))
					elif menu_m.has_method("tutorial_get_best_market_tab_index"):
						market_idx = int(menu_m.call("tutorial_get_best_market_tab_index"))
					if menu_m.has_method("tutorial_get_market_tab_rect_global"):
						target_rect = menu_m.call("tutorial_get_market_tab_rect_global")
					# If helpers didn't provide, fall back to header info priorities
					if (market_idx == -1 or target_rect.size == Vector2.ZERO) and menu_m.has_method("tutorial_get_vendor_tab_headers_info"):
						var info: Array = menu_m.call("tutorial_get_vendor_tab_headers_info")
						var exact_market := -1
						var exact_market_rect := Rect2()
						var prefer_both := -1
						var prefer_both_rect := Rect2()
						var prefer_some := -1
						var prefer_some_rect := Rect2()
						var any_resources := -1
						var any_resources_rect := Rect2()
						for e in info:
							if not (e is Dictionary):
								continue
							var idx_e := int(e.get("index", -1))
							if idx_e == -1:
								continue
							var title_ci := String(e.get("title", "")).strip_edges().to_lower()
							var has_water := bool(e.get("has_water", false))
							var has_food := bool(e.get("has_food", false))
							var has_fuel := bool(e.get("has_fuel", false))
							var rect_e: Rect2 = e.get("rect", Rect2())
							if title_ci == "market":
								exact_market = idx_e
								exact_market_rect = rect_e
								break
							if int(e.get("category_idx", -1)) == 4:
								if prefer_both == -1 and has_water and has_food:
									prefer_both = idx_e
									prefer_both_rect = rect_e
								elif prefer_some == -1 and (has_water or has_food) and not has_fuel:
									prefer_some = idx_e
									prefer_some_rect = rect_e
								elif any_resources == -1:
									any_resources = idx_e
									any_resources_rect = rect_e
						if exact_market != -1:
							market_idx = exact_market
							target_rect = exact_market_rect
						elif prefer_both != -1:
							market_idx = prefer_both
							target_rect = prefer_both_rect
						elif prefer_some != -1:
							market_idx = prefer_some
							target_rect = prefer_some_rect
						elif any_resources != -1:
							market_idx = any_resources
							target_rect = any_resources_rect
					# If nothing found from above, last resort best-index helper
					if market_idx == -1 and menu_m.has_method("tutorial_get_best_market_tab_index"):
						market_idx = int(menu_m.call("tutorial_get_best_market_tab_index"))
					# Auto-switch to the Market tab so the next step can highlight Resources immediately
					if market_idx != -1 and int(tabs_m.current_tab) != market_idx:
						tabs_m.current_tab = market_idx
					# If we still don't have a rect, compute from TabBar geometry as a fallback
					if target_rect.size == Vector2.ZERO and market_idx != -1:
						var tab_bar2: Control = null
						if tabs_m.has_method("get_tab_bar"):
							tab_bar2 = tabs_m.call("get_tab_bar")
						if tab_bar2 == null:
							tab_bar2 = tabs_m.find_child("TabBar", true, false)
						if tab_bar2 != null and tab_bar2.has_method("get_tab_rect"):
							var rect_local2: Rect2 = tab_bar2.call("get_tab_rect", market_idx)
							target_rect = Rect2(tab_bar2.get_global_transform() * rect_local2.position, rect_local2.size)
					# Also ensure the Resources dropdown is opened immediately on the selected tab
					if market_idx != -1:
						var market_panel: Node = tabs_m.get_tab_control(market_idx)
						if is_instance_valid(market_panel) and market_panel.has_method("tutorial_open_resources"):
							market_panel.call_deferred("tutorial_open_resources")
					if target_rect.size != Vector2.ZERO and _buy_vehicle_coach.has_method("highlight_global_rect"):
						_buy_vehicle_coach.call_deferred("highlight_global_rect", target_rect)
					# Wire tab change listener
					if tabs_m.has_signal("tab_changed") and not tabs_m.is_connected("tab_changed", Callable(self, "_on_vendor_tab_changed_for_walkthrough")):
						tabs_m.tab_changed.connect(_on_vendor_tab_changed_for_walkthrough)
		"s2_hint_resources_category":
			var mm_rc = get_node_or_null("/root/MenuManager")
			if is_instance_valid(mm_rc) and mm_rc.current_active_menu:
				var menu_rc = mm_rc.current_active_menu
				var tabs_rc = menu_rc.get_node_or_null("%VendorTabContainer")
				if tabs_rc == null:
					tabs_rc = menu_rc.get_node_or_null("VendorTabContainer")
				if is_instance_valid(tabs_rc):
					# Determine if on resources tab
					var res_idx := _get_resources_tab_index(menu_rc, tabs_rc)
					if res_idx != -1 and int(tabs_rc.current_tab) == res_idx:
						var vendor_panel_rc: Node = tabs_rc.get_tab_control(res_idx)
						if is_instance_valid(vendor_panel_rc):
							if _buy_vehicle_coach.has_method("show_step_message"):
								_buy_vehicle_coach.call_deferred("show_step_message", idx, total_steps, _walkthrough_messages.get(_walkthrough_state, ""))
							# Highlight the Resources category header (retry if the tree hasn't populated yet)
							_call_highlight_resources_category_with_retries(vendor_panel_rc)
					else:
						# Not on resources yet → revert to market tab step
						if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
							_tutorial_director.call("goto", "s2_hint_market_tab")
						else:
							_walkthrough_state = "s2_hint_market_tab"
							_maybe_run_vendor_walkthrough()
		"s2_hint_select_water":
			var mm_sw = get_node_or_null("/root/MenuManager")
			if is_instance_valid(mm_sw) and mm_sw.current_active_menu:
				var menu_sw = mm_sw.current_active_menu
				var tabs_sw = menu_sw.get_node_or_null("%VendorTabContainer")
				if tabs_sw == null:
					tabs_sw = menu_sw.get_node_or_null("VendorTabContainer")
				if is_instance_valid(tabs_sw):
					var res_idx2 := _get_resources_tab_index(menu_sw, tabs_sw)
					if res_idx2 != -1 and int(tabs_sw.current_tab) == res_idx2:
						var vendor_panel_sw: Node = tabs_sw.get_tab_control(res_idx2)
						if is_instance_valid(vendor_panel_sw):
							# Ensure Resources category is opened before selecting
							if vendor_panel_sw.has_method("tutorial_open_resources"):
								vendor_panel_sw.call_deferred("tutorial_open_resources")
							# Try to select and highlight Water Jerry Cans with retries for tree population
							if vendor_panel_sw.has_method("tutorial_select_item_by_prefix"):
								vendor_panel_sw.call_deferred("tutorial_select_item_by_prefix", "Water Jerry Cans")
							_call_highlight_item_row_with_retries(vendor_panel_sw, "Water Jerry Cans")
							if _buy_vehicle_coach.has_method("show_step_message"):
								_buy_vehicle_coach.call_deferred("show_step_message", idx, total_steps, _walkthrough_messages.get(_walkthrough_state, ""))
					else:
						# Not on resources
						if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
							_tutorial_director.call("goto", "s2_hint_market_tab")
						else:
							_walkthrough_state = "s2_hint_market_tab"
							_maybe_run_vendor_walkthrough()
		"s2_hint_buy_water":
			var mm_bw = get_node_or_null("/root/MenuManager")
			if is_instance_valid(mm_bw) and mm_bw.current_active_menu:
				var menu_bw = mm_bw.current_active_menu
				var tabs_bw = menu_bw.get_node_or_null("%VendorTabContainer")
				if tabs_bw == null:
					tabs_bw = menu_bw.get_node_or_null("VendorTabContainer")
				if is_instance_valid(tabs_bw):
					var res_idx3 := _get_resources_tab_index(menu_bw, tabs_bw)
					if res_idx3 != -1 and int(tabs_bw.current_tab) == res_idx3:
						var vendor_panel_bw: Node = tabs_bw.get_tab_control(res_idx3)
						if is_instance_valid(vendor_panel_bw):
							if vendor_panel_bw.has_method("tutorial_open_resources"):
								vendor_panel_bw.call_deferred("tutorial_open_resources")
							# Ensure quantity is set to 2; then highlight quantity + Buy union
							if vendor_panel_bw.has_method("tutorial_set_quantity"):
								vendor_panel_bw.call_deferred("tutorial_set_quantity", 2)
							var union := Rect2()
							var qrect := Rect2()
							if vendor_panel_bw.has_method("tutorial_get_quantity_spinbox_rect_global"):
								qrect = vendor_panel_bw.call("tutorial_get_quantity_spinbox_rect_global")
							var brect := Rect2()
							if vendor_panel_bw.has_method("tutorial_get_buy_button_global_rect"):
								brect = vendor_panel_bw.call("tutorial_get_buy_button_global_rect")
							if qrect.size != Vector2.ZERO and brect.size != Vector2.ZERO:
								var ul := Vector2(min(qrect.position.x, brect.position.x), min(qrect.position.y, brect.position.y))
								var br := Vector2(max(qrect.position.x+qrect.size.x, brect.position.x+brect.size.x), max(qrect.position.y+qrect.size.y, brect.position.y+brect.size.y))
								union = Rect2(ul, br-ul)
							elif brect.size != Vector2.ZERO:
								union = brect
							if union.size != Vector2.ZERO and _buy_vehicle_coach.has_method("highlight_global_rect"):
								_buy_vehicle_coach.call_deferred("highlight_global_rect", union)
							if _buy_vehicle_coach.has_method("show_step_message"):
								_buy_vehicle_coach.call_deferred("show_step_message", idx, total_steps, _walkthrough_messages.get(_walkthrough_state, ""))
							# Listen for local item_purchased to advance precisely
							if vendor_panel_bw.has_signal("item_purchased") and not vendor_panel_bw.is_connected("item_purchased", Callable(self, "_on_vendor_item_purchased_stage2")):
								vendor_panel_bw.connect("item_purchased", Callable(self, "_on_vendor_item_purchased_stage2"))
		"s2_hint_select_food":
			var mm_sf = get_node_or_null("/root/MenuManager")
			if is_instance_valid(mm_sf) and mm_sf.current_active_menu:
				var menu_sf = mm_sf.current_active_menu
				var tabs_sf = menu_sf.get_node_or_null("%VendorTabContainer")
				if tabs_sf == null:
					tabs_sf = menu_sf.get_node_or_null("VendorTabContainer")
				if is_instance_valid(tabs_sf):
					var res_idx4 := _get_resources_tab_index(menu_sf, tabs_sf)
					if res_idx4 != -1 and int(tabs_sf.current_tab) == res_idx4:
						var vendor_panel_sf: Node = tabs_sf.get_tab_control(res_idx4)
						if is_instance_valid(vendor_panel_sf):
							if vendor_panel_sf.has_method("tutorial_open_resources"):
								vendor_panel_sf.call_deferred("tutorial_open_resources")
							if vendor_panel_sf.has_method("tutorial_select_item_by_prefix"):
								vendor_panel_sf.call_deferred("tutorial_select_item_by_prefix", "MRE Boxes")
							_call_highlight_item_row_with_retries(vendor_panel_sf, "MRE Boxes")
							if _buy_vehicle_coach.has_method("show_step_message"):
								_buy_vehicle_coach.call_deferred("show_step_message", idx, total_steps, _walkthrough_messages.get(_walkthrough_state, ""))
					else:
						if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
							_tutorial_director.call("goto", "s2_hint_market_tab")
						else:
							_walkthrough_state = "s2_hint_market_tab"
							_maybe_run_vendor_walkthrough()
		"s2_hint_buy_food":
			var mm_bf = get_node_or_null("/root/MenuManager")
			if is_instance_valid(mm_bf) and mm_bf.current_active_menu:
				var menu_bf = mm_bf.current_active_menu
				var tabs_bf = menu_bf.get_node_or_null("%VendorTabContainer")
				if tabs_bf == null:
					tabs_bf = menu_bf.get_node_or_null("VendorTabContainer")
				if is_instance_valid(tabs_bf):
					var res_idx5 := _get_resources_tab_index(menu_bf, tabs_bf)
					if res_idx5 != -1 and int(tabs_bf.current_tab) == res_idx5:
						var vendor_panel_bf: Node = tabs_bf.get_tab_control(res_idx5)
						if is_instance_valid(vendor_panel_bf):
							# Ensure quantity is set to 2; then highlight
							if vendor_panel_bf.has_method("tutorial_set_quantity"):
								vendor_panel_bf.call_deferred("tutorial_set_quantity", 2)
							var union2 := Rect2()
							var qrect2 := Rect2()
							if vendor_panel_bf.has_method("tutorial_get_quantity_spinbox_rect_global"):
								qrect2 = vendor_panel_bf.call("tutorial_get_quantity_spinbox_rect_global")
							var brect2 := Rect2()
							if vendor_panel_bf.has_method("tutorial_get_buy_button_global_rect"):
								brect2 = vendor_panel_bf.call("tutorial_get_buy_button_global_rect")
							if qrect2.size != Vector2.ZERO and brect2.size != Vector2.ZERO:
								var ulb := Vector2(min(qrect2.position.x, brect2.position.x), min(qrect2.position.y, brect2.position.y))
								var brb := Vector2(max(qrect2.position.x+qrect2.size.x, brect2.position.x+brect2.size.x), max(qrect2.position.y+qrect2.size.y, brect2.position.y+brect2.size.y))
								union2 = Rect2(ulb, brb-ulb)
							elif brect2.size != Vector2.ZERO:
								union2 = brect2
							if union2.size != Vector2.ZERO and _buy_vehicle_coach.has_method("highlight_global_rect"):
								_buy_vehicle_coach.call_deferred("highlight_global_rect", union2)
							if _buy_vehicle_coach.has_method("show_step_message"):
								_buy_vehicle_coach.call_deferred("show_step_message", idx, total_steps, _walkthrough_messages.get(_walkthrough_state, ""))
							if vendor_panel_bf.has_signal("item_purchased") and not vendor_panel_bf.is_connected("item_purchased", Callable(self, "_on_vendor_item_purchased_stage2")):
								vendor_panel_bf.connect("item_purchased", Callable(self, "_on_vendor_item_purchased_stage2"))
		"hint_convoy_button":
			# Show step text unconditionally; highlight if targets are found
			if is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("show_step_message"):
				_buy_vehicle_coach.call_deferred("show_step_message", idx, total_steps, _walkthrough_messages.get(_walkthrough_state, ""))
				print("[Onboarding] step1: show_step_message dispatched")
			# Highlight the convoy dropdown and/or convoy button in the top bar (union rect)
			await get_tree().process_frame
			var rects: Array = []
			if is_instance_valid(top_bar):
				var menu_btn := top_bar.find_child("ConvoyMenuButton", true, false)
				if menu_btn and menu_btn is Control:
					rects.append((menu_btn as Control).get_global_rect())
				var clp := top_bar.find_child("ConvoyListPanel", true, false)
				if clp and clp is Control:
					var toggle := (clp as Control).find_child("ToggleButton", true, false)
					if toggle and toggle is Control:
						rects.append((toggle as Control).get_global_rect())
					# Also highlight the selected convoy inside the list for when it opens
					var gdm = get_node_or_null("/root/GameDataManager")
					if is_instance_valid(gdm) and (clp as Node).has_method("highlight_convoy_in_list") and gdm.has_method("get_selected_convoy"):
						var sel = gdm.get_selected_convoy()
						if sel is Dictionary and sel.has("convoy_id"):
							(clp as Node).call_deferred("highlight_convoy_in_list", str(sel.get("convoy_id")))
			if not rects.is_empty() and is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("highlight_global_rect"):
				var ul: Vector2 = rects[0].position
				var br: Vector2 = rects[0].position + rects[0].size
				for r in rects:
					ul.x = min(ul.x, r.position.x)
					ul.y = min(ul.y, r.position.y)
					br.x = max(br.x, r.position.x + r.size.x)
					br.y = max(br.y, r.position.y + r.size.y)
				var union_rect := Rect2(ul, br - ul)
				_buy_vehicle_coach.call_deferred("highlight_global_rect", union_rect)
				print("[Onboarding] step1: highlighting convoy UI union=", union_rect)
		"hint_settlement_button":
			# After convoy menu opens, hint the Settlement button within it
			var mm = get_node_or_null("/root/MenuManager")
			if is_instance_valid(mm) and mm.current_active_menu and mm.current_active_menu.has_node("MainVBox/ScrollContainer/ContentVBox/MenuButtons/SettlementMenuButton"):
				var sbtn: Control = mm.current_active_menu.get_node("MainVBox/ScrollContainer/ContentVBox/MenuButtons/SettlementMenuButton")
				if is_instance_valid(sbtn):
					var step_idx2: int = max(2, idx)
					if _buy_vehicle_coach.has_method("show_step_message"):
						_buy_vehicle_coach.call_deferred("show_step_message", step_idx2, total_steps, _walkthrough_messages.get(_walkthrough_state, ""))
						print("[Onboarding] step2: show_step_message dispatched")
					if _buy_vehicle_coach.has_method("highlight_control"):
						_buy_vehicle_coach.call_deferred("highlight_control", sbtn)
						print("[Onboarding] step2: highlighting Settlement button control")
					if _buy_vehicle_coach.has_method("highlight_control"):
						_buy_vehicle_coach.call_deferred("highlight_control", sbtn)
		"hint_vendor_tab":
			print("[Onboarding] step3: preparing dealership tab highlight…")
			var mm2 = get_node_or_null("/root/MenuManager")
			if is_instance_valid(mm2) and mm2.current_active_menu:
				# Ensure vendor tabs are built; if menu exposes tabs_ready, wait for it once
				if mm2.current_active_menu and mm2.current_active_menu.has_signal("tabs_ready"):
					# Avoid duplicate connections; await signal directly
					await mm2.current_active_menu.tabs_ready
				else:
					await get_tree().process_frame
				var menu = mm2.current_active_menu
				var tabs = menu.get_node_or_null("%VendorTabContainer")
				if tabs == null:
					tabs = menu.get_node_or_null("VendorTabContainer")
				if is_instance_valid(tabs):
					var step_idx3: int = max(3, idx)
					if _buy_vehicle_coach.has_method("show_step_message"):
						_buy_vehicle_coach.call_deferred("show_step_message", step_idx3, total_steps, _walkthrough_messages.get(_walkthrough_state, ""))
						print("[Onboarding] step3: show_step_message dispatched")
					# Highlight ONLY the dealership tab header; use top-level global rect so it renders above everything
					if tabs is TabContainer:
						var tc: TabContainer = tabs
						# Determine dealership tab index (for logging/fallback)
						var dealership_idx := -1
						if menu and menu.has_method("tutorial_get_dealership_tab_index"):
							dealership_idx = int(menu.call("tutorial_get_dealership_tab_index"))
						var current_idx := int(tc.current_tab)
						var on_dealership := (dealership_idx != -1 and current_idx == dealership_idx)
						print("[Onboarding] step3: tab context current=", current_idx, " dealer=", dealership_idx, " on_dealer=", on_dealership)
						# Clear any stale proxy (we don't use it anymore but clean up previous sessions)
						if menu and menu.has_method("tutorial_clear_tab_highlight_proxy"):
							menu.call_deferred("tutorial_clear_tab_highlight_proxy")

						# If user is already on the dealership tab during step 3, wire vehicle-selected to advance to step 4.
						if on_dealership and tc.get_tab_count() > current_idx:
							var dealer_panel: Node = tc.get_tab_control(current_idx)
							if is_instance_valid(dealer_panel) and dealer_panel.has_signal("tutorial_vehicle_selected"):
								if not dealer_panel.is_connected("tutorial_vehicle_selected", Callable(self, "_on_vendor_vehicle_selected_for_walkthrough")):
									dealer_panel.connect("tutorial_vehicle_selected", Callable(self, "_on_vendor_vehicle_selected_for_walkthrough"))
									print("[Onboarding] step3: connected vehicle_selected while already on dealership → will auto-advance to step 4")

						var did_highlight := false
						# Preferred: helper-provided global rect (works whether selected or not)
						if menu and menu.has_method("tutorial_get_dealership_tab_rect_global") and _buy_vehicle_coach.has_method("highlight_global_rect"):
							var target: Rect2 = menu.call("tutorial_get_dealership_tab_rect_global")
							if target.size == Vector2.ZERO:
								await get_tree().process_frame
								target = menu.call("tutorial_get_dealership_tab_rect_global")
							if target.size != Vector2.ZERO:
								_buy_vehicle_coach.call_deferred("highlight_global_rect", target)
								print("[Onboarding] Highlighting Dealership tab header (helper rect)", (" while on_dealership" if on_dealership else " while off_dealership"), "=", target)
								did_highlight = true

						# Fallback: compute from TabBar geometry directly
						if not did_highlight and _buy_vehicle_coach.has_method("highlight_global_rect"):
							var tab_bar_fallback: Control = null
							if tc.has_method("get_tab_bar"):
								tab_bar_fallback = tc.call("get_tab_bar")
							if tab_bar_fallback == null:
								tab_bar_fallback = tc.find_child("TabBar", true, false)
							if not is_instance_valid(tab_bar_fallback):
								await get_tree().process_frame
								if tc.has_method("get_tab_bar"):
									tab_bar_fallback = tc.call("get_tab_bar")
								if tab_bar_fallback == null:
									tab_bar_fallback = tc.find_child("TabBar", true, false)
							if is_instance_valid(tab_bar_fallback):
								# If we didn't resolve dealership index above, attempt light heuristic
								if dealership_idx == -1:
									var count2 := tc.get_tab_count()
									for i in count2:
										var t := String(tc.get_tab_title(i)).to_lower()
										if t.find("dealer") != -1:
											dealership_idx = i
											break
								if dealership_idx != -1 and tab_bar_fallback.has_method("get_tab_rect"):
									var rect_local: Rect2 = tab_bar_fallback.call("get_tab_rect", dealership_idx)
									if rect_local.size == Vector2.ZERO:
										await get_tree().process_frame
										rect_local = tab_bar_fallback.call("get_tab_rect", dealership_idx)
									if rect_local.size != Vector2.ZERO:
										var bar_global_pos: Vector2 = (tab_bar_fallback as Control).get_global_rect().position
										var rect_global := Rect2(bar_global_pos + rect_local.position, rect_local.size)
										_buy_vehicle_coach.call_deferred("highlight_global_rect", rect_global)
										print("[Onboarding] Highlighting Dealership tab via TabBar rect=", rect_global)
					# Ensure we listen for tab switches so we can re-guide immediately if user moves away
					var tc2: TabContainer = tabs
					if tc2 and tc2.has_signal("tab_changed") and not tc2.is_connected("tab_changed", Callable(self, "_on_vendor_tab_changed_for_walkthrough")):
						tc2.tab_changed.connect(_on_vendor_tab_changed_for_walkthrough)
						print("[Onboarding] step3: connected TabContainer tab_changed")
					# Also listen for a direct click on the dealership tab header (even if already selected)
					var tab_bar: Control = null
					if tc2 and tc2.has_method("get_tab_bar"):
						tab_bar = tc2.call("get_tab_bar")
					if tab_bar == null and tc2:
						tab_bar = tc2.find_child("TabBar", true, false)
					if tab_bar and not tab_bar.is_connected("gui_input", Callable(self, "_on_vendor_tab_bar_gui_input_for_walkthrough")):
						tab_bar.gui_input.connect(_on_vendor_tab_bar_gui_input_for_walkthrough)
						print("[Onboarding] step3: connected TabBar gui_input for single-click advance")
		"hint_vendor_vehicles":
			print("[Onboarding] step4: inside dealership; highlighting Vehicles header / waiting for buy")
			var mm3 = get_node_or_null("/root/MenuManager")
			if is_instance_valid(mm3) and mm3.current_active_menu:
				var menu2 = mm3.current_active_menu
				var tabs2 = menu2.get_node_or_null("%VendorTabContainer")
				if tabs2 == null:
					tabs2 = menu2.get_node_or_null("VendorTabContainer")
				if is_instance_valid(tabs2):
					# Clean up any prior proxy highlight under TabBar
					if menu2 and menu2.has_method("tutorial_clear_tab_highlight_proxy"):
						menu2.call_deferred("tutorial_clear_tab_highlight_proxy")
						print("[Onboarding] step4: cleared tab highlight proxy")
					# Ensure we are on the dealership tab; otherwise revert to step 3
					var dealership_idx2: int = -1
					if menu2 and menu2.has_method("tutorial_get_dealership_tab_index"):
						dealership_idx2 = int(menu2.call("tutorial_get_dealership_tab_index"))
					if int(tabs2.current_tab) != dealership_idx2 or dealership_idx2 == -1:
						print("[Onboarding] step4: wrong tab selected (idx=", int(tabs2.current_tab), "/ dealer=", dealership_idx2, ") → reverting to step3")
						_walkthrough_state = "hint_vendor_tab"
						_maybe_run_vendor_walkthrough()
						return
					# Find the active vendor panel and its tree
					var tab_idx: int = int(tabs2.current_tab)
					var vendor_panel: Node = tabs2.get_tab_control(tab_idx)
					if vendor_panel:
						# Prefer highlighting just the Vehicles header row if helper is available
						if vendor_panel.has_method("tutorial_get_category_header_rect_global") and _buy_vehicle_coach.has_method("highlight_global_rect"):
							var header_rect: Rect2 = vendor_panel.call("tutorial_get_category_header_rect_global", "Vehicles")
							if header_rect.size != Vector2.ZERO:
								_buy_vehicle_coach.call_deferred("highlight_global_rect", header_rect)
								print("[Onboarding] step4: highlighting Vehicles header=", header_rect)
							else:
								# If Vehicles header not present yet, do not highlight arbitrary panels
								print("[Onboarding] Vehicles category header not found; waiting for selection.")
						# Update step message for final step
						if _buy_vehicle_coach.has_method("show_step_message"):
							_buy_vehicle_coach.call_deferred("show_step_message", total_steps, total_steps, _walkthrough_messages.get(_walkthrough_state, ""))
						# When a vehicle is selected in the list, move highlight to the Buy button
						if vendor_panel.has_signal("tutorial_vehicle_selected"):
							if not vendor_panel.is_connected("tutorial_vehicle_selected", Callable(self, "_on_vendor_vehicle_selected_for_walkthrough")):
								vendor_panel.connect("tutorial_vehicle_selected", Callable(self, "_on_vendor_vehicle_selected_for_walkthrough"))
								print("[Onboarding] step4: connected vehicle_selected → will highlight Buy on selection")
	# Ensure panel respects current bounds and menu avoidance immediately after showing/updating a step
	_update_coach_bounds_and_avoid()

# Re-run step 3 once tabs are ready, to ensure highlight is placed after dynamic construction
func _on_settlement_tabs_ready_for_walkthrough() -> void:
	if _walkthrough_state == "hint_vendor_tab":
		_maybe_run_vendor_walkthrough()


func _on_menu_opened_for_walkthrough(_menu_node: Node, menu_type: String) -> void:
	print("[Onboarding] _on_menu_opened_for_walkthrough: type=", menu_type, " state=", _walkthrough_state)
	if menu_type == "convoy_overview":
		# Whenever convoy overview opens, set step based on stage
		if _current_tutorial_stage == 2:
			if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
				_tutorial_director.call("goto", "s2_hint_settlement_button")
			else:
				_walkthrough_state = "s2_hint_settlement_button"
				_maybe_run_vendor_walkthrough()
		else:
			if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
				_tutorial_director.call("goto", "hint_settlement_button")
			else:
				_walkthrough_state = "hint_settlement_button"
				_maybe_run_vendor_walkthrough()
	elif menu_type == "convoy_settlement_submenu":
		# When settlement submenu opens, guide to dealership or market tab depending on stage
		if _current_tutorial_stage == 2:
			if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
				_tutorial_director.call("goto", "s2_hint_market_tab")
			else:
				_walkthrough_state = "s2_hint_market_tab"
		else:
			if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
				_tutorial_director.call("goto", "hint_vendor_tab")
			else:
				_walkthrough_state = "hint_vendor_tab"
		var mm = get_node_or_null("/root/MenuManager")
		if is_instance_valid(mm) and mm.current_active_menu:
			var menu = mm.current_active_menu
			var vendor_tabs = menu.get_node_or_null("%VendorTabContainer")
			if vendor_tabs == null:
				vendor_tabs = menu.get_node_or_null("VendorTabContainer")
			if vendor_tabs and vendor_tabs.has_signal("tab_changed"):
				if not vendor_tabs.is_connected("tab_changed", Callable(self, "_on_vendor_tab_changed_for_walkthrough")):
					vendor_tabs.tab_changed.connect(_on_vendor_tab_changed_for_walkthrough)
		_maybe_run_vendor_walkthrough()

func _on_menu_closed_for_walkthrough(_menu_node: Node, _menu_type: String) -> void:
	# When all menus are closed, we're back on the map.
	var mm = get_node_or_null("/root/MenuManager")
	if not is_instance_valid(mm) or not mm.is_any_menu_active():
		print("[Onboarding] _on_menu_closed_for_walkthrough: no active menus → reset to step1")
		_reset_walkthrough_to_step1()

func _on_menu_visibility_changed_for_walkthrough(is_open: bool, _menu_name: String) -> void:
	print("[Onboarding] _on_menu_visibility_changed_for_walkthrough: is_open=", is_open, " state=", _walkthrough_state)
	if not is_open:
		_reset_walkthrough_to_step1()

func _reset_walkthrough_to_step1() -> void:
	# If user dismissed the coach, hide it to avoid a blank box; otherwise reset to step 1.
	print("[Onboarding] _reset_walkthrough_to_step1: dismissed=", _buy_vehicle_coach_dismissed)
	if _buy_vehicle_coach_dismissed:
		_hide_buy_vehicle_coach()
		_clear_walkthrough()
		return
	print("[Onboarding] _reset_walkthrough_to_step1: state set; running step1")
	# Hide central modal immediately to avoid a blank window during transition
	if is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("hide_main_panel"):
		_buy_vehicle_coach.hide_main_panel()
	# Proactively show step 1 side-panel text, but defer by one frame so layout settles after menu closes
	var total_steps := 4
	if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("get_total_steps"):
		total_steps = int(_tutorial_director.call("get_total_steps"))
	if is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("show_step_message"):
		var first_id := "s2_hint_convoy_button" if _current_tutorial_stage == 2 else "hint_convoy_button"
		var msg: String = String(_walkthrough_messages.get(first_id, ""))
		call_deferred("_render_step1_message_deferred", total_steps, msg)
	if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
		_tutorial_director.call("goto", ("s2_hint_convoy_button" if _current_tutorial_stage == 2 else "hint_convoy_button"))
	else:
		_walkthrough_state = "s2_hint_convoy_button" if _current_tutorial_stage == 2 else "hint_convoy_button"
		# Ensure the central coach panel is hidden so only the left panel shows text
		if is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("hide_main_panel"):
			_buy_vehicle_coach.call_deferred("hide_main_panel")
		_maybe_run_vendor_walkthrough()

func _render_step1_message_deferred(total_steps: int, msg: String) -> void:
	await get_tree().process_frame
	if is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("show_step_message"):
		_buy_vehicle_coach.call_deferred("show_step_message", 1, total_steps, msg)

func _clear_walkthrough() -> void:
	_walkthrough_state = ""
	if is_instance_valid(_buy_vehicle_coach):
		if _buy_vehicle_coach.has_method("hide_hint"):
			_buy_vehicle_coach.call_deferred("hide_hint")
		if _buy_vehicle_coach.has_method("hide_left_panel"):
			_buy_vehicle_coach.call_deferred("hide_left_panel")
		if _buy_vehicle_coach.has_method("clear_highlight"):
			_buy_vehicle_coach.call_deferred("clear_highlight")

func _on_vendor_tab_changed_for_walkthrough(tab_index: int) -> void:
	# Index 0 is usually the Settlement Info tab; vendor tabs start at 1
	var mm = get_node_or_null("/root/MenuManager")
	if not is_instance_valid(mm) or not mm.current_active_menu:
		return
	var menu = mm.current_active_menu
	var tabs = menu.get_node_or_null("%VendorTabContainer")
	if tabs == null:
		tabs = menu.get_node_or_null("VendorTabContainer")
	if not is_instance_valid(tabs):
		return
	# Determine path depending on current tutorial stage
	if _current_tutorial_stage == 2:
		# Resources tab selection logic via headers info helper
		var is_resources := false
		var res_idx := _get_resources_tab_index(menu, tabs)
		is_resources = (res_idx == tab_index and res_idx != -1)
		if tab_index >= 1 and is_resources:
			if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
				_tutorial_director.call("goto", "s2_hint_resources_category")
				_maybe_run_vendor_walkthrough()
			else:
				_walkthrough_state = "s2_hint_resources_category"
				_maybe_run_vendor_walkthrough()
		else:
			# Keep guiding to Market/Resources tab
			if is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("clear_highlight"):
				_buy_vehicle_coach.call_deferred("clear_highlight")
			if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
				_tutorial_director.call("goto", "s2_hint_market_tab")
				_maybe_run_vendor_walkthrough()
			else:
				_walkthrough_state = "s2_hint_market_tab"
				_maybe_run_vendor_walkthrough()
				# Also immediate re-highlight of Market tab header if possible
				if is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("highlight_global_rect"):
					var r := Rect2()
					if menu and menu.has_method("tutorial_get_market_tab_rect_global"):
						r = menu.call("tutorial_get_market_tab_rect_global")
					if r.size == Vector2.ZERO and menu and menu.has_method("tutorial_get_vendor_tab_headers_info"):
						var info2: Array = menu.call("tutorial_get_vendor_tab_headers_info")
						for e in info2:
							if e is Dictionary and int(e.get("category_idx", -1)) == 4:
								var r2: Rect2 = e.get("rect", Rect2())
								if r2.size != Vector2.ZERO:
									r = r2
									break
					if r.size != Vector2.ZERO:
						_buy_vehicle_coach.call_deferred("highlight_global_rect", r)
			# Ensure TabBar click handler remains wired
			if tabs is TabContainer:
				var tc_click: TabContainer = tabs
				var tb_click: Control = null
				if tc_click.has_method("get_tab_bar"):
					tb_click = tc_click.call("get_tab_bar")
				if tb_click == null:
					tb_click = tc_click.find_child("TabBar", true, false)
				if tb_click and not tb_click.is_connected("gui_input", Callable(self, "_on_vendor_tab_bar_gui_input_for_walkthrough")):
					tb_click.gui_input.connect(_on_vendor_tab_bar_gui_input_for_walkthrough)
					print("[Onboarding] s2: ensured TabBar gui_input connection on tab change")
		return
	# Stage 1 path: dealership logic
	# Determine if the selected tab is the dealership by asking the menu (classification-based)
	var is_dealership := false
	if menu and menu.has_method("tutorial_get_dealership_tab_index"):
		var di: int = int(menu.call("tutorial_get_dealership_tab_index"))
		is_dealership = (di == tab_index)
	else:
		var title: String = ""
		if tab_index >= 0 and tab_index < tabs.get_tab_count():
			title = String(tabs.get_tab_title(tab_index)).to_lower()
		is_dealership = title.find("dealership") != -1 or title.find("dealer") != -1 or title.find("vehicle") != -1
	if tab_index >= 1 and is_dealership:
		# Proceed to highlight the vehicles category inside dealership
		if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
			_tutorial_director.call("goto", "hint_vendor_vehicles")
			# Immediately render to ensure highlight updates this frame
			_maybe_run_vendor_walkthrough()
		else:
			_walkthrough_state = "hint_vendor_vehicles"
			_maybe_run_vendor_walkthrough()
	else:
		# Keep guiding the user to the dealership tab header
		# Clear any wares highlight lingering from dealership step
		if is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("clear_highlight"):
			_buy_vehicle_coach.call_deferred("clear_highlight")
		if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
			_tutorial_director.call("goto", "hint_vendor_tab")
			# Immediately render so the dealership tab header gets highlighted right away
			_maybe_run_vendor_walkthrough()
		else:
			_walkthrough_state = "hint_vendor_tab"
			_maybe_run_vendor_walkthrough()

		# Additionally, re-apply the highlight immediately to avoid any timing gaps
		# Prefer helper-provided global rect for the Dealership tab header
		if is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("highlight_global_rect"):
			var target_rect := Rect2()
			if menu and menu.has_method("tutorial_get_dealership_tab_rect_global"):
				target_rect = menu.call("tutorial_get_dealership_tab_rect_global")
			if target_rect.size != Vector2.ZERO:
				_buy_vehicle_coach.call_deferred("highlight_global_rect", target_rect)
				print("[Onboarding] step3: immediate re-highlight of Dealership tab=", target_rect)
			else:
				# Best-effort fallback via TabBar if helper didn't return a rect yet
				if tabs is TabContainer:
					var tc_local: TabContainer = tabs
					var tab_bar: Control = null
					if tc_local.has_method("get_tab_bar"):
						tab_bar = tc_local.call("get_tab_bar")
					if tab_bar == null:
						tab_bar = tc_local.find_child("TabBar", true, false)
					if is_instance_valid(tab_bar) and menu and menu.has_method("tutorial_get_dealership_tab_index") and tab_bar.has_method("get_tab_rect"):
						var di2: int = int(menu.call("tutorial_get_dealership_tab_index"))
						if di2 != -1:
							var rloc: Rect2 = tab_bar.call("get_tab_rect", di2)
							if rloc.size != Vector2.ZERO:
								var bar_pos: Vector2 = (tab_bar as Control).get_global_rect().position
								var rglob := Rect2(bar_pos + rloc.position, rloc.size)
								_buy_vehicle_coach.call_deferred("highlight_global_rect", rglob)
								print("[Onboarding] step3: immediate fallback highlight via TabBar=", rglob)

		# Ensure TabBar click handler is wired for single-click advance if user clicks the dealership header
		if tabs is TabContainer:
			var tc_click: TabContainer = tabs
			var tb_click: Control = null
			if tc_click.has_method("get_tab_bar"):
				tb_click = tc_click.call("get_tab_bar")
			if tb_click == null:
				tb_click = tc_click.find_child("TabBar", true, false)
			if tb_click and not tb_click.is_connected("gui_input", Callable(self, "_on_vendor_tab_bar_gui_input_for_walkthrough")):
				tb_click.gui_input.connect(_on_vendor_tab_bar_gui_input_for_walkthrough)
				print("[Onboarding] step3: ensured TabBar gui_input connection on tab change")

# When a vehicle is selected in vendor list, highlight the Buy button
func _on_vendor_vehicle_selected_for_walkthrough() -> void:
	# If a vehicle is selected while we're still on step 3, advance to step 4 immediately.
	if _walkthrough_state != "hint_vendor_vehicles":
		if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
			_tutorial_director.call("goto", "hint_vendor_vehicles")
			# Ensure the UI updates this frame
			_maybe_run_vendor_walkthrough()
		else:
			_walkthrough_state = "hint_vendor_vehicles"
			_maybe_run_vendor_walkthrough()

	var mm = get_node_or_null("/root/MenuManager")
	if not is_instance_valid(mm) or not mm.current_active_menu:
		return
	var menu = mm.current_active_menu
	var tabs = menu.get_node_or_null("%VendorTabContainer")
	if tabs == null:
		tabs = menu.get_node_or_null("VendorTabContainer")
	if not is_instance_valid(tabs):
		return
	var tab_idx: int = int(tabs.current_tab)
	var tab_ctrl: Control = tabs.get_tab_control(tab_idx)
	if tab_ctrl == null:
		return
	# In our UI, the tab control IS the vendor panel (VendorTradePanel). Use it directly.
	var vendor_panel: Node = tab_ctrl
	if vendor_panel and _buy_vehicle_coach:
		# Prefer highlighting the actual control for robustness; fallback to rect.
		if vendor_panel.has_method("tutorial_get_buy_button_control") and _buy_vehicle_coach.has_method("highlight_control"):
			var buy_btn: Control = vendor_panel.call("tutorial_get_buy_button_control")
			if is_instance_valid(buy_btn):
				_buy_vehicle_coach.call_deferred("highlight_control", buy_btn)
				return
		if _buy_vehicle_coach.has_method("highlight_global_rect") and vendor_panel.has_method("tutorial_get_buy_button_global_rect"):
			var buy_rect: Rect2 = vendor_panel.call("tutorial_get_buy_button_global_rect")
			if buy_rect.size != Vector2.ZERO:
				_buy_vehicle_coach.call_deferred("highlight_global_rect", buy_rect)


# Intercept clicks on vendor TabBar to detect when the dealership tab header is clicked, then advance
func _on_vendor_tab_bar_gui_input_for_walkthrough(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var mm = get_node_or_null("/root/MenuManager")
	if not is_instance_valid(mm) or not mm.current_active_menu:
		return
	var menu = mm.current_active_menu
	var tabs = menu.get_node_or_null("%VendorTabContainer")
	if tabs == null:
		tabs = menu.get_node_or_null("VendorTabContainer")
	if not (tabs is TabContainer):
		return
	var tc: TabContainer = tabs
	var dealership_idx := -1
	if menu and menu.has_method("tutorial_get_dealership_tab_index"):
		dealership_idx = int(menu.call("tutorial_get_dealership_tab_index"))
	# If we can access the TabBar and the dealership tab rect, and the click is inside it, advance immediately
	var tab_bar: Control = null
	if tc.has_method("get_tab_bar"):
		tab_bar = tc.call("get_tab_bar")
	if tab_bar == null:
		tab_bar = tc.find_child("TabBar", true, false)
	if is_instance_valid(tab_bar) and dealership_idx != -1 and tab_bar.has_method("get_tab_rect") and mb.pressed:
		var rect_local: Rect2 = tab_bar.call("get_tab_rect", dealership_idx)
		# event position is in TabBar local coordinates
		if rect_local.has_point(mb.position):
			# Ensure the dealership tab is selected, then proceed
			if int(tc.current_tab) != dealership_idx:
				tc.current_tab = dealership_idx
			if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
				_tutorial_director.call("goto", "hint_vendor_vehicles")
			else:
				_walkthrough_state = "hint_vendor_vehicles"
				_maybe_run_vendor_walkthrough()
			return
	# Otherwise, on mouse release, check if the selection ended up on the dealership and advance
	if not mb.pressed:
		await get_tree().process_frame
		if dealership_idx != -1 and int(tc.current_tab) == dealership_idx:
			if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
				_tutorial_director.call("goto", "hint_vendor_vehicles")
			else:
				_walkthrough_state = "hint_vendor_vehicles"
				_maybe_run_vendor_walkthrough()

# --- Stage 2 helpers and handlers ---
func _get_resources_tab_index(menu: Node, tabs: TabContainer) -> int:
	if not is_instance_valid(menu) or not is_instance_valid(tabs):
		return -1
	# Strongly prefer the menu's best Market tab index (uses robust heuristics)
	if menu.has_method("tutorial_get_best_market_tab_index"):
		var best_idx := int(menu.call("tutorial_get_best_market_tab_index"))
		if best_idx != -1:
			return best_idx
	# Otherwise, use vendor headers info but choose the most suitable Resources tab
	if menu.has_method("tutorial_get_vendor_tab_headers_info"):
		var info: Array = menu.call("tutorial_get_vendor_tab_headers_info")
		var exact_market := -1
		var prefer_both := -1
		var prefer_some := -1
		var any_resources := -1
		for e in info:
			if not (e is Dictionary):
				continue
			if int(e.get("category_idx", -1)) != 4:
				continue
			var idx_e := int(e.get("index", -1))
			if idx_e == -1:
				continue
			var title_ci := String(e.get("title", "")).strip_edges().to_lower()
			var has_water := bool(e.get("has_water", false))
			var has_food := bool(e.get("has_food", false))
			var has_fuel := bool(e.get("has_fuel", false))
			if exact_market == -1 and title_ci == "market":
				exact_market = idx_e
				# Break early on exact match
				break
			if prefer_both == -1 and has_water and has_food:
				prefer_both = idx_e
			elif prefer_some == -1 and (has_water or has_food) and not has_fuel:
				prefer_some = idx_e
			elif any_resources == -1:
				any_resources = idx_e
		if exact_market != -1:
			return exact_market
		if prefer_both != -1:
			return prefer_both
		if prefer_some != -1:
			return prefer_some
		if any_resources != -1:
			return any_resources
	return -1

func _maybe_start_stage2_walkthrough() -> void:
	# Determine stage and conditions
	var gdm = get_node_or_null("/root/GameDataManager")
	if not is_instance_valid(gdm):
		return
	var u: Dictionary = gdm.get_current_user_data() if gdm.has_method("get_current_user_data") else {}
	var stage := 0
	if typeof(u) == TYPE_DICTIONARY:
		var md = u.get("metadata", {})
		if typeof(md) == TYPE_DICTIONARY and md.has("tutorial"):
			var t = md["tutorial"]
			stage = int(t) if typeof(t) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING] else 0
	# Need at least one vehicle
	var has_vehicle := false
	if gdm.has_method("get_all_convoy_data"):
		var convoys: Array = gdm.get_all_convoy_data()
		for cv in convoys:
			if cv is Dictionary:
				var vlist = cv.get("vehicle_details_list", [])
				if vlist is Array and vlist.size() > 0:
					has_vehicle = true
					break
	if stage == 2 and has_vehicle:
		_current_tutorial_stage = 2
		_s2_progress["bought_water"] = false
		_s2_progress["bought_food"] = false
		# Ensure coach exists and is not considered dismissed for Stage 2 messaging
		_buy_vehicle_coach_dismissed = false
		_ensure_coach()
		_ensure_tutorial_director()
		# Define Stage 2 steps on the director and start
		if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("set_steps"):
			var steps2 := [
				{"id": "s2_hint_convoy_button"},
				{"id": "s2_hint_settlement_button"},
				{"id": "s2_hint_market_tab"},
				{"id": "s2_hint_resources_category"},
				{"id": "s2_hint_select_water"},
				{"id": "s2_hint_buy_water"},
				{"id": "s2_hint_select_food"},
				{"id": "s2_hint_buy_food"},
			]
			_tutorial_director.call("set_steps", steps2)
		if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("start"):
			_tutorial_director.call("start", "s2_hint_convoy_button")
		else:
			_walkthrough_state = "s2_hint_convoy_button"
			_maybe_run_vendor_walkthrough()

func _on_vendor_item_purchased_stage2(item: Dictionary, quantity: int, _total_cost: float) -> void:
	var name_s := String(item.get("name", ""))
	var name_l := name_s.to_lower()
	var is_water_jerry := name_l.find("water jerry") != -1 or name_l.find("jerry can") != -1
	var is_mre := name_l.find("mre") != -1
	if _current_tutorial_stage != 2:
		return
	# Require at least 2 of the specified items
	if not _s2_progress["bought_water"] and is_water_jerry and quantity >= 2:
		_s2_progress["bought_water"] = true
		if is_instance_valid(_tutorial_director) and _tutorial_director.has_method("goto"):
			_tutorial_director.call("goto", "s2_hint_select_food")
		else:
			_walkthrough_state = "s2_hint_select_food"
			_maybe_run_vendor_walkthrough()
		return
	if _s2_progress["bought_water"] and not _s2_progress["bought_food"] and is_mre and quantity >= 2:
		_s2_progress["bought_food"] = true
		_finish_stage2_tutorial()

func _on_any_resource_or_cargo_bought(_result: Dictionary) -> void:
	# Disable coarse advancement during Stage 2; we only advance on exact purchases captured via item_purchased.
	return

func _finish_stage2_tutorial() -> void:
	# Dismiss coach and advance user metadata to stage 3
	_hide_buy_vehicle_coach()
	_clear_walkthrough()
	var gdm = get_node_or_null("/root/GameDataManager")
	var api = get_node_or_null("/root/APICalls")
	if is_instance_valid(gdm) and is_instance_valid(api) and api.has_method("update_user_metadata") and gdm.has_method("get_current_user_data"):
		var u: Dictionary = gdm.get_current_user_data()
		var user_id := String(u.get("user_id", "")) if typeof(u) == TYPE_DICTIONARY else ""
		if user_id != "":
			var merged_md2: Dictionary = {}
			var existing_md3: Dictionary = (u.get("metadata", {}) if typeof(u) == TYPE_DICTIONARY else {})
			if typeof(existing_md3) == TYPE_DICTIONARY:
				merged_md2 = existing_md3.duplicate(true)
			var prev_tutorial2: int = int(merged_md2.get("tutorial", 2))
			merged_md2["tutorial"] = prev_tutorial2 + 1
			api.call_deferred("update_user_metadata", user_id, merged_md2)
	_current_tutorial_stage = 0

func _render_walkthrough_step(step_id: String, _index: int, _total: int) -> void:
	# Centralized render for the current step; keeps legacy behavior but uses provided index/total
	_walkthrough_state = step_id
	_ensure_coach()
	if not is_instance_valid(_buy_vehicle_coach):
		return
	# Hide main panel to prefer side panel during step-by-step
	if _buy_vehicle_coach.has_method("hide_main_panel"):
		_buy_vehicle_coach.call_deferred("hide_main_panel")
	# Delegate to existing runner which handles highlighting, but will use index/total via _maybe_run_vendor_walkthrough
	_maybe_run_vendor_walkthrough()

# --- Retry helpers for highlighting after vendor tree population ---
func _call_highlight_resources_category_with_retries(vendor_panel: Node, attempts: int = 6) -> void:
	if not is_instance_valid(vendor_panel) or attempts <= 0:
		return
	# Try immediately
	var rect := Rect2()
	# Force-open Resources to avoid flicker/retraction
	if vendor_panel.has_method("tutorial_open_resources"):
		vendor_panel.call_deferred("tutorial_open_resources")
	if vendor_panel.has_method("tutorial_get_category_header_rect_global"):
		rect = vendor_panel.call("tutorial_get_category_header_rect_global", "Resources")
	if rect.size != Vector2.ZERO and is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("highlight_global_rect"):
		_buy_vehicle_coach.call_deferred("highlight_global_rect", rect)
		return
	# Wait a frame, then retry
	await get_tree().process_frame
	_call_highlight_resources_category_with_retries(vendor_panel, attempts - 1)

func _call_highlight_item_row_with_retries(vendor_panel: Node, display_text: String, attempts: int = 6) -> void:
	if not is_instance_valid(vendor_panel) or attempts <= 0:
		return
	var rect := Rect2()
	# Keep Resources expanded while trying to select/highlight specific rows
	if vendor_panel.has_method("tutorial_open_resources"):
		vendor_panel.call_deferred("tutorial_open_resources")
	if vendor_panel.has_method("tutorial_get_item_row_rect_global"):
		rect = vendor_panel.call("tutorial_get_item_row_rect_global", display_text)
	if rect.size != Vector2.ZERO and is_instance_valid(_buy_vehicle_coach) and _buy_vehicle_coach.has_method("highlight_global_rect"):
		_buy_vehicle_coach.call_deferred("highlight_global_rect", rect)
		return
	await get_tree().process_frame
	_call_highlight_item_row_with_retries(vendor_panel, display_text, attempts - 1)


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
