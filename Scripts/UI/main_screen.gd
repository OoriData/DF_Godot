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
var _new_convoy_dialog: Control = null
const NEW_CONVOY_DIALOG_SCENE_PATH := "res://Scenes/NewConvoyDialog.tscn"
@export var new_convoy_dialog_scene: PackedScene = null

# Track the convoy dropdown popup for dynamic avoidance during tutorial coaching
var _convoy_dropdown_popup: Control = null

# Onboarding coach overlay for guiding next steps (e.g., buy first vehicle)
const ONBOARDING_COACH_SCRIPT_PATH := "res://Scripts/UI/onboarding_coach.gd"
var _buy_vehicle_coach: Control = null
var _buy_vehicle_coach_dismissed: bool = false
var _walkthrough_state: String = "" # "hint_convoy_button" -> "hint_settlement_button" -> "done"
var _walkthrough_messages := {
	"hint_convoy_button": "Select your convoy from the dropdown in the top bar to open the Convoy menu.",
	"hint_settlement_button": "Click the Settlement button to open settlement interactions.",
	"hint_vendor_tab": "Click the Dealership tab. Tabs switch between different vendors in this settlement.",
	"hint_vendor_vehicles": "Select the Vehicles category, choose a vehicle, and press Buy."
}

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

	# Listen to menu openings to advance hints
	var mm = get_node_or_null("/root/MenuManager")
	if is_instance_valid(mm) and mm.has_signal("menu_opened"):
		if not mm.is_connected("menu_opened", Callable(self, "_on_menu_opened_for_walkthrough")):
			mm.menu_opened.connect(_on_menu_opened_for_walkthrough)

	# Proactively check once after layout settles (in case no signals fire yet)
	call_deferred("_check_or_prompt_new_convoy")
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
	_check_or_prompt_new_convoy()

func _on_convoy_data_updated(all_convoys: Array):
	print("[Onboarding] convoy_data_updated received; convoys passed count=", (all_convoys.size() if all_convoys is Array else -1))
	_check_or_prompt_new_convoy(all_convoys)
	# After convoys update, consider showing the next coach (buy a vehicle)
	_maybe_show_buy_vehicle_coach()
	_maybe_run_vendor_walkthrough()

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
		_hide_new_convoy_dialog()
		return

	if has_any:
		_hide_new_convoy_dialog()
		return

	_show_new_convoy_dialog()

func _show_new_convoy_dialog():
	print("[Onboarding] _show_new_convoy_dialog invoked.")
	_ensure_onboarding_layer()
	if not is_instance_valid(_new_convoy_dialog):
		var scene_res: Resource = new_convoy_dialog_scene if new_convoy_dialog_scene != null else load(NEW_CONVOY_DIALOG_SCENE_PATH)
		if scene_res == null or not (scene_res is PackedScene):
			printerr("[Onboarding] WARN: Could not load PackedScene for NewConvoyDialog (export unset or load failed). Building inline fallback…")
			_new_convoy_dialog = _build_inline_new_convoy_dialog()
		else:
			var scene: PackedScene = scene_res
			print("[Onboarding] Instantiating NewConvoyDialog scene…")
			_new_convoy_dialog = scene.instantiate()
		_onboarding_layer.add_child(_new_convoy_dialog)
		print("[Onboarding] NewConvoyDialog added to overlay.")
		_new_convoy_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		# Center with a fixed size
		_new_convoy_dialog.custom_minimum_size = Vector2(420, 180)
		# Connect signals
		if _new_convoy_dialog.has_signal("create_requested"):
			_new_convoy_dialog.connect("create_requested", Callable(self, "_on_new_convoy_create"))
		if _new_convoy_dialog.has_signal("canceled"):
			_new_convoy_dialog.connect("canceled", Callable(self, "_on_new_convoy_canceled"))
	if _new_convoy_dialog.has_method("open"):
		print("[Onboarding] Opening NewConvoyDialog…")
		_new_convoy_dialog.call_deferred("open")
	else:
		printerr("[Onboarding] WARN: Dialog missing 'open' method; forcing visible true.")
		_new_convoy_dialog.visible = true

func _build_inline_new_convoy_dialog() -> Control:
	var dlg := PanelContainer.new()
	dlg.name = "NewConvoyDialog"
	dlg.custom_minimum_size = Vector2(420, 180)
	# Build structure before attaching script and adding to tree
	var v := VBoxContainer.new()
	v.name = "VBox"
	v.anchors_preset = Control.PRESET_FULL_RECT
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	dlg.add_child(v)

	var title := Label.new()
	title.name = "Title"
	title.text = "Welcome to Desolate Frontiers!  \nLets start by naming your first convoy."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var name_edit := LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.placeholder_text = "Convoy name"
	name_edit.max_length = 40
	v.add_child(name_edit)

	var error_label := Label.new()
	error_label.name = "ErrorLabel"
	error_label.visible = false
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.modulate = Color(1, 0.6, 0.6)
	v.add_child(error_label)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(buttons)

	var cancel_btn := Button.new()
	cancel_btn.name = "CancelButton"
	cancel_btn.text = "Cancel"
	buttons.add_child(cancel_btn)

	var create_btn := Button.new()
	create_btn.name = "CreateButton"
	create_btn.text = "Create"
	buttons.add_child(create_btn)

	# Attach behavior script
	var script_res := load("res://Scripts/UI/new_convoy_dialog.gd")
	if script_res:
		dlg.set_script(script_res)
	else:
		printerr("[Onboarding] ERROR: Failed to load dialog behavior script at res://Scripts/UI/new_convoy_dialog.gd")
		# Fallback barebones behavior: wire buttons directly
		create_btn.pressed.connect(func():
			var nm := name_edit.text.strip_edges()
			if nm.length() >= 3:
				_on_new_convoy_create(nm)
		)
		cancel_btn.pressed.connect(_on_new_convoy_canceled)
	return dlg

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

func _hide_new_convoy_dialog():
	if is_instance_valid(_new_convoy_dialog) and _new_convoy_dialog.has_method("close"):
		_new_convoy_dialog.call_deferred("close")

func _on_new_convoy_create(convoy_name: String):
	# Disable dialog while creating
	if is_instance_valid(_new_convoy_dialog) and _new_convoy_dialog.has_method("set_busy"):
		_new_convoy_dialog.call_deferred("set_busy", true)
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm) and gdm.has_method("create_new_convoy"):
		gdm.create_new_convoy(convoy_name)
		# Close the dialog immediately; backend will refresh data and the gating
		# logic will prevent reopening once a convoy exists.
		_hide_new_convoy_dialog()
	else:
		printerr("MainScreen: GameDataManager missing create_new_convoy; cannot create convoy.")

func _on_new_convoy_canceled():
	# Keep dialog open on cancel for onboarding; optional: hide
	pass
	#     _fit_camera_to_map()


# --- Onboarding coach: Buy first vehicle ---

func _ensure_coach() -> void:
	_ensure_onboarding_layer()
	if is_instance_valid(_buy_vehicle_coach):
		return
	var coach_script: Script = load(ONBOARDING_COACH_SCRIPT_PATH)
	if coach_script == null:
		printerr("[Onboarding] Failed to load coach script at ", ONBOARDING_COACH_SCRIPT_PATH)
		return
	var coach := Control.new()
	coach.set_script(coach_script)
	_onboarding_layer.add_child(coach)
	_buy_vehicle_coach = coach
	# Connect dismissed to suppress further prompts this session
	if _buy_vehicle_coach.has_signal("dismissed"):
		_buy_vehicle_coach.connect("dismissed", Callable(self, "_on_buy_vehicle_coach_dismissed"))
	# Immediately set bounds/avoidance so the panel is placed on the map area correctly
	_update_coach_bounds_and_avoid()
	# Route highlight overlays to global layer so they aren't clipped by the map overlay
	if _buy_vehicle_coach.has_method("set_highlight_host") and is_instance_valid(_highlight_layer):
		_buy_vehicle_coach.call_deferred("set_highlight_host", _highlight_layer)

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

func _maybe_show_buy_vehicle_coach() -> void:
	if _buy_vehicle_coach_dismissed:
		return
	var gdm = get_node_or_null("/root/GameDataManager")
	if not is_instance_valid(gdm):
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
		# No convoy yet; nothing to do
		_hide_buy_vehicle_coach()
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

	# At this point we have a convoy with zero vehicles; start guided walkthrough (don't auto-open vendors)
	_walkthrough_state = "hint_convoy_button"
	_maybe_run_vendor_walkthrough()

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
		return
	if _walkthrough_state == "":
		return
	_ensure_coach()
	if not is_instance_valid(_buy_vehicle_coach):
		return
	match _walkthrough_state:
		"hint_convoy_button":
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
			if not rects.is_empty() and is_instance_valid(_buy_vehicle_coach):
				var ul: Vector2 = rects[0].position
				var br: Vector2 = rects[0].position + rects[0].size
				for r in rects:
					ul.x = min(ul.x, r.position.x)
					ul.y = min(ul.y, r.position.y)
					br.x = max(br.x, r.position.x + r.size.x)
					br.y = max(br.y, r.position.y + r.size.y)
				var union_rect := Rect2(ul, br - ul)
				if _buy_vehicle_coach.has_method("show_step_message"):
					_buy_vehicle_coach.call_deferred("show_step_message", 1, 4, _walkthrough_messages.get(_walkthrough_state, ""))
				if _buy_vehicle_coach.has_method("highlight_global_rect"):
					_buy_vehicle_coach.call_deferred("highlight_global_rect", union_rect)
		"hint_settlement_button":
			# After convoy menu opens, hint the Settlement button within it
			var mm = get_node_or_null("/root/MenuManager")
			if is_instance_valid(mm) and mm.current_active_menu and mm.current_active_menu.has_node("MainVBox/ScrollContainer/ContentVBox/MenuButtons/SettlementMenuButton"):
				var sbtn: Control = mm.current_active_menu.get_node("MainVBox/ScrollContainer/ContentVBox/MenuButtons/SettlementMenuButton")
				if is_instance_valid(sbtn):
					var step_idx2 := 2
					if _buy_vehicle_coach.has_method("show_step_message"):
						_buy_vehicle_coach.call_deferred("show_step_message", step_idx2, 4, _walkthrough_messages.get(_walkthrough_state, ""))
					if _buy_vehicle_coach.has_method("highlight_control"):
						_buy_vehicle_coach.call_deferred("highlight_control", sbtn)
					if _buy_vehicle_coach.has_method("highlight_control"):
						_buy_vehicle_coach.call_deferred("highlight_control", sbtn)
		"hint_vendor_tab":
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
					var step_idx3 := 3
					if _buy_vehicle_coach.has_method("show_step_message"):
						_buy_vehicle_coach.call_deferred("show_step_message", step_idx3, 4, _walkthrough_messages.get(_walkthrough_state, ""))
					# Highlight ONLY the dealership tab header (even if it's already selected)
					if tabs is TabContainer:
						var tc: TabContainer = tabs
						var proxy: Control = null
						if menu and menu.has_method("tutorial_build_dealership_tab_highlight_proxy"):
							proxy = menu.call("tutorial_build_dealership_tab_highlight_proxy")
						if is_instance_valid(proxy) and _buy_vehicle_coach.has_method("highlight_control"):
							_buy_vehicle_coach.call_deferred("highlight_control", proxy)
							print("[Onboarding] Highlighting Dealership tab via proxy control")
						else:
							# Fallback: use global rect helper
							if menu and menu.has_method("tutorial_get_dealership_tab_rect_global") and _buy_vehicle_coach.has_method("highlight_global_rect"):
								var target: Rect2 = menu.call("tutorial_get_dealership_tab_rect_global")
								if target.size == Vector2.ZERO:
									await get_tree().process_frame
									target = menu.call("tutorial_get_dealership_tab_rect_global")
								if target.size != Vector2.ZERO:
									_buy_vehicle_coach.call_deferred("highlight_global_rect", target)
									print("[Onboarding] Highlighting Dealership tab header (fallback)=", target)
						# Also listen for a direct click on the dealership tab header (even if already selected)
						var tab_bar: Control = null
						if tc.has_method("get_tab_bar"):
							tab_bar = tc.call("get_tab_bar")
						if tab_bar == null:
							tab_bar = tc.find_child("TabBar", true, false)
						if tab_bar and not tab_bar.is_connected("gui_input", Callable(self, "_on_vendor_tab_bar_gui_input_for_walkthrough")):
							tab_bar.gui_input.connect(_on_vendor_tab_bar_gui_input_for_walkthrough)
		"hint_vendor_vehicles":
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
					# Ensure we are on the dealership tab; otherwise revert to step 3
					var dealership_idx2: int = -1
					if menu2 and menu2.has_method("tutorial_get_dealership_tab_index"):
						dealership_idx2 = int(menu2.call("tutorial_get_dealership_tab_index"))
					if int(tabs2.current_tab) != dealership_idx2 or dealership_idx2 == -1:
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
							else:
								# If Vehicles header not present yet, do not highlight arbitrary panels
								print("[Onboarding] Vehicles category header not found; waiting for selection.")
						# Update step message for final step
						if _buy_vehicle_coach.has_method("show_step_message"):
							_buy_vehicle_coach.call_deferred("show_step_message", 4, 4, _walkthrough_messages.get(_walkthrough_state, ""))
						# When a vehicle is selected in the list, move highlight to the Buy button
						if vendor_panel.has_signal("tutorial_vehicle_selected"):
							if not vendor_panel.is_connected("tutorial_vehicle_selected", Callable(self, "_on_vendor_vehicle_selected_for_walkthrough")):
								vendor_panel.connect("tutorial_vehicle_selected", Callable(self, "_on_vendor_vehicle_selected_for_walkthrough"))
	# Ensure panel respects current bounds and menu avoidance immediately after showing/updating a step
	_update_coach_bounds_and_avoid()

# Re-run step 3 once tabs are ready, to ensure highlight is placed after dynamic construction
func _on_settlement_tabs_ready_for_walkthrough() -> void:
	if _walkthrough_state == "hint_vendor_tab":
		_maybe_run_vendor_walkthrough()

func _on_menu_opened_for_walkthrough(_menu_node: Node, menu_type: String) -> void:
	if _walkthrough_state == "hint_convoy_button" and menu_type == "convoy_overview":
		# Advance to settlement hint
		_walkthrough_state = "hint_settlement_button"
		_maybe_run_vendor_walkthrough()
	elif _walkthrough_state == "hint_settlement_button" and menu_type == "convoy_settlement_submenu":
		# User reached settlement; hint selecting a vendor tab (any tab index > 0)
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
		_walkthrough_state = "hint_vendor_vehicles"
		_maybe_run_vendor_walkthrough()
	else:
		# Keep guiding the user to the dealership tab header
		_walkthrough_state = "hint_vendor_tab"
		_maybe_run_vendor_walkthrough()

# When a vehicle is selected in vendor list, highlight the Buy button
func _on_vendor_vehicle_selected_for_walkthrough() -> void:
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
			_walkthrough_state = "hint_vendor_vehicles"
			_maybe_run_vendor_walkthrough()
			return
	# Otherwise, on mouse release, check if the selection ended up on the dealership and advance
	if not mb.pressed:
		await get_tree().process_frame
		if dealership_idx != -1 and int(tc.current_tab) == dealership_idx:
			_walkthrough_state = "hint_vendor_vehicles"
			_maybe_run_vendor_walkthrough()


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
