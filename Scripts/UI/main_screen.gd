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
var _onboarding_layer: Control = null
var _map_is_interactive: bool = true # New flag to control map input

@onready var menu_container = $MainContainer/MainContent/MapAndMenuContainer/MenuContainer
@onready var top_bar = $MainContainer/TopBar
var _new_convoy_dialog: Control = null
const NEW_CONVOY_DIALOG_SCENE_PATH := "res://Scenes/NewConvoyDialog.tscn"
@export var new_convoy_dialog_scene: PackedScene = null
const ERROR_DIALOG_SCENE_PATH := "res://Scenes/ErrorDialog.tscn"
var _error_dialog_scene: PackedScene

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

	# Ensure an overlay layer exists for onboarding modals
	if is_instance_valid(_onboarding_layer) == false:
		_onboarding_layer = Control.new()
		_onboarding_layer.name = "OnboardingLayer"
		_onboarding_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Parent the onboarding layer to the map_view so it only covers the map area
		var parent: Node = map_view if is_instance_valid(map_view) else self
		if _onboarding_layer.get_parent() != parent:
			if is_instance_valid(_onboarding_layer.get_parent()):
				_onboarding_layer.get_parent().remove_child(_onboarding_layer)
			parent.add_child(_onboarding_layer)
			parent.move_child(_onboarding_layer, parent.get_child_count() - 1)
		_onboarding_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Ensure overlay layer lives under the MapView even if it was created earlier
	_reparent_onboarding_layer_to_map()
	_update_onboarding_layer_rect_to_map()

# --- Tutorial / Onboarding helpers ---
# Provide a stable accessor for an overlay layer that tutorial can attach to.
func get_onboarding_layer() -> Control:
	_ensure_onboarding_layer()
	# Keep parenting correct in case this accessor is called before MapView is ready
	_reparent_onboarding_layer_to_map()
	return _onboarding_layer

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

# --- Animation state ---
const MENU_ANIM_DURATION := 0.45
const MENU_CAMERA_FOCUS_DURATION := 0.65 # Slightly longer for smoother convoy centering
const MENU_WIDTH_RATIO_DEFAULT := 0.35 # Fallback percent of screen width when open if settings ratio absent
var _menu_target_width: float = 0.0
var _menu_anim_tween: Tween = null
var _last_focused_convoy_data: Dictionary = {}
var _current_menu_occlusion_px: float = 0.0 # animated width used to inform camera occlusion
var DEBUG_MENU_CAMERA: bool = true # master toggle for menu-camera diagnostic logging
var _menu_anim_in_progress: bool = false # true while menu open/close tween is active to suppress duplicate focus requests

func _dbg_menu(tag: String, data: Dictionary = {}):
	if not DEBUG_MENU_CAMERA:
		return
	var summary := ""
	for k in data.keys():
		summary += str(k) + ":" + str(data[k]) + " "
	print("[MainScreen][MENU-CAM]", tag, summary)


func _ready():
	# Defer the initial camera setup to ensure the UI layout is stable.
	# print("[DFCAM-DEBUG] MainScreen: _ready called, deferring initial camera/UI setup.")
	call_deferred("_initial_camera_and_ui_setup")
	# Defer signal connections to ensure child scenes are also ready.
	call_deferred("_connect_deferred_signals")

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

	# Subscribe to initial and convoy updates to detect empty state
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("initial_data_ready", Callable(self, "_on_initial_data_ready")):
			gdm.initial_data_ready.connect(_on_initial_data_ready)
		if not gdm.is_connected("convoy_data_updated", Callable(self, "_on_convoy_data_updated")):
			gdm.convoy_data_updated.connect(_on_convoy_data_updated)
		if not gdm.is_connected("user_data_updated", Callable(self, "_on_user_data_updated")):
			gdm.user_data_updated.connect(_on_user_data_updated)

	# Proactively check once after layout settles (in case no signals fire yet)
	call_deferred("_check_or_prompt_new_convoy")

	# --- API Error Handling ---
	var api_calls = get_node_or_null("/root/APICalls")
	if is_instance_valid(api_calls):
		if not api_calls.is_connected("fetch_error", Callable(self, "_on_api_fetch_error")):
			api_calls.connect("fetch_error", Callable(self, "_on_api_fetch_error"))
	else:
		printerr("MainScreen: Could not find APICalls node to connect error handler.")
	_error_dialog_scene = load(ERROR_DIALOG_SCENE_PATH)
# Respond to Control resize events

func _connect_deferred_signals():
	# Connect the button in the top bar to a function that asks the MenuManager to open the menu.
	# This is deferred to ensure the TopBar and its instanced children (like ConvoyListPanel) are fully ready.
	var convoy_button = top_bar.find_child("ConvoyMenuButton", true, false)
	if convoy_button:
		if not convoy_button.is_connected("pressed", Callable(self, "on_convoy_button_pressed")):
			convoy_button.pressed.connect(on_convoy_button_pressed)
	else:
		printerr("MainScreen: Could not find ConvoyMenuButton in TopBar (deferred search).")

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_on_main_screen_size_changed()


func _on_main_screen_size_changed():
	# Called when MainScreen is resized (window resize or layout change)
	_update_camera_viewport_rect_on_resize()
	_update_onboarding_layer_rect_to_map()

func _on_map_view_size_changed():
	# Called when MapView is resized (e.g., due to menu open/close or container resize)
	_update_camera_viewport_rect_on_resize()
	_update_onboarding_layer_rect_to_map()

# Call this after the main screen is visible and unpaused to ensure camera is correct
func force_camera_update():
	await get_tree().process_frame  # Wait for layout to settle
	_update_camera_viewport_rect_on_resize()

func _update_camera_viewport_rect_on_resize():
	if is_instance_valid(map_view) and is_instance_valid(map_camera_controller) and map_camera_controller.has_method("update_map_viewport_rect"):
		# Use the actual MapDisplay (TextureRect) rect, not the root map_view rect.
		# The root control can include extra UI chrome; using it causes camera/map edge mismatch.
		var map_rect = _get_map_display_rect()
		map_camera_controller.update_map_viewport_rect(map_rect)
		# Preserve current camera state on resize; limits are updated by controller



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
		var map_rect = _get_map_display_rect()
		# print("[DFCAM-DEBUG] MainScreen: Initial setup, notifying camera of viewport display rect=", map_rect)
		map_camera_controller.update_map_viewport_rect(map_rect)
		# Force strict clamping to current viewport size at runtime
		if map_camera_controller.has_method("set_loose_pan_when_menu_open"):
			map_camera_controller.set_loose_pan_when_menu_open(false)
		if map_camera_controller.has_method("fit_camera_to_tilemap"):
			map_camera_controller.fit_camera_to_tilemap()
	# else:
	# 	printerr("[DFCAM-DEBUG] MainScreen: Camera controller not valid or missing update_map_viewport_rect.")


	# After initial layout, fit onboarding layer to the map display rect
	_update_onboarding_layer_rect_to_map()

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
			var center := _to_subviewport_screen(event.global_position)
			map_camera_controller.zoom_at_screen_pos(factor, center)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			var inc2: float = float(map_camera_controller.camera_zoom_factor_increment)
			var factor2: float = inc2 if _opt_invert_zoom else (1.0 / inc2)
			var center2 := _to_subviewport_screen(event.global_position)
			map_camera_controller.zoom_at_screen_pos(factor2, center2)
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
			# Magnify gesture provides local position relative to map_view, convert to global first
			var global_center3: Vector2 = map_view.get_global_transform() * event.position
			var center3 := _to_subviewport_screen(global_center3)
			map_camera_controller.zoom_at_screen_pos(z, center3)
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
	# Overlay behavior: map stays full size; slide menu over it.
	if not is_instance_valid(menu_container): return
	var viewport_rect = get_viewport().get_visible_rect()
	var full_w: float = viewport_rect.size.x
	var ratio := _opt_menu_ratio_open / (_opt_menu_ratio_open + 1.0)
	_menu_target_width = max(200.0, full_w * (ratio if ratio > 0 else MENU_WIDTH_RATIO_DEFAULT))
	_dbg_menu("menu_visibility_signal", {"is_open": is_open, "target_w": _menu_target_width, "viewport_w": full_w})
	if is_open:
		var menu_manager = get_node_or_null("/root/MenuManager")
		var convoy_data: Dictionary = {}
		if is_instance_valid(menu_manager):
			var active_menu = menu_manager.get("current_active_menu") if menu_manager.has_method("get") else null
			if active_menu and active_menu.has_meta("menu_data"):
				convoy_data = active_menu.get_meta("menu_data")
		_last_focused_convoy_data = convoy_data
		# Tell camera controller the menu is opening. This allows it to use the correct
		# clamping logic (e.g. frozen zoom) when calculating the tween target.
		# We pass 'false' to prevent an immediate camera snap.
		if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("set_menu_open_state"):
			map_camera_controller.set_menu_open_state(true, false)
		# IMPORTANT: apply final occlusion immediately for camera limit computation & centering.
		_current_menu_occlusion_px = _menu_target_width
		_update_camera_occlusion_from_menu()
		_dbg_menu("menu_open_occlusion_applied", {"occlusion_px": _current_menu_occlusion_px, "has_convoy": not convoy_data.is_empty()})
		_slide_menu_open(convoy_data)
	else:
		# Tell camera controller the menu is closing.
		if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("set_menu_open_state"):
			map_camera_controller.set_menu_open_state(false)
		_dbg_menu("menu_close_begin", {"last_convoy_empty": _last_focused_convoy_data.is_empty(), "prev_occlusion_px": _current_menu_occlusion_px})
		# Begin close: animate occlusion down alongside menu.
		_slide_menu_close(_last_focused_convoy_data)

func _kill_menu_anim_tween():
	if _menu_anim_tween and _menu_anim_tween.is_valid():
		_menu_anim_tween.kill()
	_menu_anim_tween = null

func _slide_menu_open(convoy_data: Dictionary):
	if not is_instance_valid(menu_container): return
	_kill_menu_anim_tween()
	_menu_anim_in_progress = true
	# Initial hidden state: width 0 at right edge.
	menu_container.visible = true
	menu_container.offset_right = 0
	menu_container.offset_left = 0 # zero width
	_dbg_menu("slide_open_start", {"menu_target_w": _menu_target_width, "convoy_empty": convoy_data.is_empty(), "cam_pos_pre": (map_camera_controller.camera_node.position if (is_instance_valid(map_camera_controller) and map_camera_controller.has_method("camera_node")) else "<none>")})

	# Acquire convoy data if missing (ensure deterministic centering on selected convoy).
	if convoy_data.is_empty():
		convoy_data = _get_primary_convoy_data()
	# Smoothly focus using FINAL occlusion width target so convoy ends centered in reduced visible map view.
	if is_instance_valid(map_camera_controller):
		if not convoy_data.is_empty() and map_camera_controller.has_method("smooth_focus_on_convoy_with_final_occlusion"):
			_dbg_menu("slide_open_focus_convoy", {})
			map_camera_controller.smooth_focus_on_convoy_with_final_occlusion(convoy_data, _menu_target_width, MENU_CAMERA_FOCUS_DURATION)
		elif map_camera_controller.has_method("smooth_focus_on_world_pos") and map_camera_controller.has_method("get_current_zoom"):
			_dbg_menu("slide_open_focus_fallback", {})
			# Fallback: shift camera center relative to current center (no convoy data available).
			var zoom: float = max(map_camera_controller.get_current_zoom(), 0.0001)
			var occlusion_world_w: float = _menu_target_width / zoom
			var current_center: Vector2 = map_camera_controller.camera_node.position
			map_camera_controller.smooth_focus_on_world_pos(current_center + Vector2(occlusion_world_w * 0.5, 0), MENU_CAMERA_FOCUS_DURATION)

	# Animate menu width (offset_left negative width).
	_menu_anim_tween = create_tween()
	_menu_anim_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_menu_anim_tween.tween_property(menu_container, "offset_left", -_menu_target_width, MENU_ANIM_DURATION)
	# Occlusion already set to final; no need to animate it for camera logic.
	_menu_anim_tween.finished.connect(func():
		_dbg_menu("slide_open_finished", {"final_offset_left": menu_container.offset_left})
		# Ensure final width exact
		menu_container.offset_left = -_menu_target_width
		# (Camera occlusion already correct)
		_menu_anim_in_progress = false
	)

func _slide_menu_close(convoy_data: Dictionary):
	if not is_instance_valid(menu_container): return
	_kill_menu_anim_tween()
	_menu_anim_in_progress = true
	if convoy_data.is_empty():
		convoy_data = _get_primary_convoy_data()
	_dbg_menu("slide_close_start", {"convoy_empty": convoy_data.is_empty(), "cam_pos_pre": (map_camera_controller.camera_node.position if (is_instance_valid(map_camera_controller) and map_camera_controller.has_method("camera_node")) else "<none>")})
	var start_w := _current_menu_occlusion_px
	if start_w <= 0.0:
		start_w = _menu_target_width
	_close_anim_convoy = convoy_data
	_close_anim_start_width = start_w
	_menu_anim_tween = create_tween()
	_menu_anim_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_menu_anim_tween.tween_method(Callable(self, "_close_anim_step"), 0.0, 1.0, MENU_ANIM_DURATION)
	_menu_anim_tween.finished.connect(func():
		_dbg_menu("slide_close_finished", {"final_offset_left": menu_container.offset_left})
		menu_container.visible = false
		menu_container.offset_left = 0.0
		_current_menu_occlusion_px = 0.0
		_update_camera_occlusion_from_menu()
		_menu_anim_in_progress = false
	)

var _close_anim_convoy: Dictionary = {}
var _close_anim_start_width: float = 0.0

func _close_anim_step(progress: float):
	var w = lerp(_close_anim_start_width, 0.0, progress)
	_current_menu_occlusion_px = w
	menu_container.offset_left = -w
	_update_camera_occlusion_from_menu()
	if is_instance_valid(map_camera_controller) and not _close_anim_convoy.is_empty():
		if map_camera_controller.has_method("focus_on_convoy"):
			map_camera_controller.focus_on_convoy(_close_anim_convoy)
	_dbg_menu("close_step", {"p": progress, "w": w})

# Update camera controller with current animated occlusion width
func _update_camera_occlusion_from_menu():
	if is_instance_valid(map_camera_controller) and map_camera_controller.has_method("set_overlay_occlusion_width"):
		map_camera_controller.set_overlay_occlusion_width(_current_menu_occlusion_px)
		_dbg_menu("occlusion_update", {"occlusion_px": _current_menu_occlusion_px})

# Helper: attempt to retrieve currently selected convoy data for focusing.
func _get_primary_convoy_data() -> Dictionary:
	# Try MenuManager active menu data first
	var menu_manager = get_node_or_null("/root/MenuManager")
	if is_instance_valid(menu_manager):
		var active_menu = menu_manager.get("current_active_menu") if menu_manager.has_method("get") else null
		if active_menu and active_menu.has_meta("menu_data"):
			var md = active_menu.get_meta("menu_data")
			if typeof(md) == TYPE_DICTIONARY and not md.is_empty():
				return md
	# Fall back to GameDataManager selected convoy ids
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		var selected_ids := []
		if gdm.has_method("get_selected_convoy_ids"):
			selected_ids = gdm.get_selected_convoy_ids()
		var all_convoys := []
		if gdm.has_method("get_all_convoy_data"):
			all_convoys = gdm.get_all_convoy_data()
		if selected_ids is Array and not selected_ids.is_empty() and all_convoys is Array:
			for c in all_convoys:
				if typeof(c) == TYPE_DICTIONARY:
					var cid = str(c.get("id", ""))
					if selected_ids.has(cid):
						return c
		# Fallback: return first convoy if any
		if all_convoys is Array and not all_convoys.is_empty():
			var first = all_convoys[0]
			if typeof(first) == TYPE_DICTIONARY:
				return first
	return {}

func _on_initial_data_ready():
	print("[Onboarding] initial_data_ready received; checking convoys…")
	_check_or_prompt_new_convoy()

func _on_convoy_data_updated(all_convoys: Array):
	print("[Onboarding] convoy_data_updated received; convoys passed count=", (all_convoys.size() if all_convoys is Array else -1))
	_check_or_prompt_new_convoy(all_convoys)

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

func _on_api_fetch_error(message: String):
	# Check if this is an error that should be handled by a specific UI component
	# and not by the global popup dialog.
	if ErrorTranslator.is_inline_error(message):
		print("MainScreen: Ignoring inline error, expected to be handled by component: ", message)
		return

	var display_message = ErrorTranslator.translate(message)
	if display_message.is_empty():
		return # This error is meant to be ignored by the popup

	_show_error_dialog(display_message)

func _show_error_dialog(message: String):
	if not is_instance_valid(_error_dialog_scene):
		printerr("Error dialog scene not loaded!")
		return

	var modal_layer: Control = get_node_or_null("ModalLayer")
	var dialog_host: CenterContainer = modal_layer.get_node_or_null("DialogHost") if is_instance_valid(modal_layer) else null

	if not is_instance_valid(dialog_host):
		printerr("MainScreen: DialogHost not found in ModalLayer!")
		return

	# Prevent stacking multiple error dialogs. If one is up, just print the new error.
	if dialog_host.find_child("ErrorDialog", false, false) != null:
		print("Ignoring new error as a dialog is already visible: ", message)
		return

	var error_dialog = _error_dialog_scene.instantiate()
	error_dialog.name = "ErrorDialog"
	dialog_host.add_child(error_dialog)
	modal_layer.show()

	error_dialog.show_message(message)

	# When the dialog is closed (freed), hide the modal layer if nothing else is in the host.
	error_dialog.tree_exited.connect(func():
		if is_instance_valid(dialog_host) and dialog_host.get_child_count() == 0:
			if is_instance_valid(modal_layer):
				modal_layer.hide()
	)

func _show_new_convoy_dialog():
	print("[Onboarding] _show_new_convoy_dialog invoked.")
	var modal_layer: Control = get_node_or_null("ModalLayer")
	if not is_instance_valid(_new_convoy_dialog):
		var scene_res: Resource = new_convoy_dialog_scene if new_convoy_dialog_scene != null else load(NEW_CONVOY_DIALOG_SCENE_PATH)
		if scene_res == null or not (scene_res is PackedScene):
			printerr("[Onboarding] WARN: Could not load PackedScene for NewConvoyDialog (export unset or load failed). Building inline fallback…")
			_new_convoy_dialog = _build_inline_new_convoy_dialog()
		else:
			var scene: PackedScene = scene_res
			print("[Onboarding] Instantiating NewConvoyDialog scene…")
			_new_convoy_dialog = scene.instantiate()
		# The host for the modal dialog is the full-screen CenterContainer from the scene file.
		modal_layer = get_node_or_null("ModalLayer")
		var host: Node = modal_layer.get_node_or_null("DialogHost") if is_instance_valid(modal_layer) else null
		if not is_instance_valid(host):
			printerr("[Onboarding] CRITICAL: ModalLayer or its DialogHost child not found in MainScreen.tscn!")
			return
		host.add_child(_new_convoy_dialog)
		print("[Onboarding] NewConvoyDialog added to ModalLayer.")
		# Connect signals
		if _new_convoy_dialog.has_signal("create_requested"):
			_new_convoy_dialog.connect("create_requested", Callable(self, "_on_new_convoy_create"))
		if _new_convoy_dialog.has_signal("canceled"):
			_new_convoy_dialog.connect("canceled", Callable(self, "_on_new_convoy_canceled"))
	modal_layer = get_node_or_null("ModalLayer")
	if _new_convoy_dialog.has_method("open"):
		print("[Onboarding] Opening NewConvoyDialog…")
		if is_instance_valid(modal_layer): modal_layer.show()
		_new_convoy_dialog.call_deferred("open")
	else:
		printerr("[Onboarding] WARN: Dialog missing 'open' method; forcing visible true.")
		if is_instance_valid(modal_layer): modal_layer.show()
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
	# Make sure the overlay exists and is in the scene tree before adding dialogs to it
	if not is_instance_valid(_onboarding_layer):
		_onboarding_layer = Control.new()
		_onboarding_layer.name = "OnboardingLayer"
		_onboarding_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Prefer to parent under the map_view (falls back to MainScreen if unavailable)
		var parent: Node = map_view if is_instance_valid(map_view) else self
		if _onboarding_layer.get_parent() != parent:
			if is_instance_valid(_onboarding_layer.get_parent()):
				_onboarding_layer.get_parent().remove_child(_onboarding_layer)
			parent.add_child(_onboarding_layer)
			parent.move_child(_onboarding_layer, parent.get_child_count() - 1)
		_onboarding_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Ensure a CenterContainer exists to center any onboarding dialogs/content
		var center := _onboarding_layer.get_node_or_null("Center")
		if not is_instance_valid(center):
			center = CenterContainer.new()
			center.name = "Center"
			_onboarding_layer.add_child(center)
			if center is Control:
				center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				center.mouse_filter = Control.MOUSE_FILTER_PASS

func _reparent_onboarding_layer_to_map() -> void:
	# Ensure onboarding layer is under map_view and sized later
	if not is_instance_valid(_onboarding_layer):
		return
	var parent: Node = map_view if is_instance_valid(map_view) else self
	if _onboarding_layer.get_parent() != parent:
		if is_instance_valid(_onboarding_layer.get_parent()):
			_onboarding_layer.get_parent().remove_child(_onboarding_layer)
		parent.add_child(_onboarding_layer)
	parent.move_child(_onboarding_layer, parent.get_child_count() - 1)

# Compute MapDisplay rect and size/position onboarding layer to match it (in map_view local coords)
func _update_onboarding_layer_rect_to_map() -> void:
	if not is_instance_valid(map_view):
		return
	# Find the MapDisplay TextureRect inside the MapView scene
	var map_display: Control = map_view.get_node_or_null("MapContainer/MapDisplay")
	if not is_instance_valid(map_display):
		# Fallback: use entire map_view bounds
		if is_instance_valid(_onboarding_layer):
			_onboarding_layer.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_onboarding_layer.position = Vector2.ZERO
			_onboarding_layer.custom_minimum_size = map_view.size
			_onboarding_layer.size = map_view.size
		return
	# Convert MapDisplay's global rect into map_view local space
	var rect: Rect2 = map_display.get_global_rect()
	var inv := map_view.get_global_transform().affine_inverse()
	var local_pos: Vector2 = inv * rect.position
	# Apply to onboarding layer (manual sizing, not full-rect anchors)
	if is_instance_valid(_onboarding_layer):
		_onboarding_layer.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_onboarding_layer.position = local_pos
		_onboarding_layer.custom_minimum_size = rect.size
		_onboarding_layer.size = rect.size
		# Keep overlay content clipped to this region
		_onboarding_layer.clip_contents = true

func _hide_new_convoy_dialog():
	var modal_layer: Control = get_node_or_null("ModalLayer")
	if is_instance_valid(modal_layer):
		modal_layer.hide()

	if is_instance_valid(_new_convoy_dialog):
		if _new_convoy_dialog.has_method("close"):
			_new_convoy_dialog.call_deferred("close")
		# In case the dialog is queued for deletion, we should remove our reference.
		_new_convoy_dialog = null

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
	var modal_layer: Control = get_node_or_null("ModalLayer")
	if is_instance_valid(modal_layer):
		modal_layer.hide()


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
	if not is_instance_valid(map_camera_controller):
		return
	# Suppress duplicate focus while menu visible or animating to preserve biased open tween.
	if is_instance_valid(menu_container) and (menu_container.visible or _menu_anim_in_progress):
		_dbg_menu("focus_request_suppressed", {"visible": menu_container.visible, "anim_in_progress": _menu_anim_in_progress})
		return
	if map_camera_controller.has_method("smooth_focus_on_convoy"):
		_dbg_menu("focus_request_applied", {})
		map_camera_controller.smooth_focus_on_convoy(convoy_data, MENU_CAMERA_FOCUS_DURATION)


# Called when the map_ready_for_focus signal is emitted from main.gd
func _on_map_ready_for_focus():
	# print("[DFCAM-DEBUG] MainScreen: Received map_ready_for_focus signal.")
	_map_ready_for_focus = true
	await get_tree().process_frame  # Wait for UI to settle
	if is_instance_valid(map_camera_controller) and not _has_fitted_camera:
		var map_rect = _get_map_display_rect()
		# print("[DFCAM-DEBUG] MainScreen: map_ready_for_focus, updating camera viewport display rect=", map_rect)
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
	# This function is called by other parts of the system (like menus) to enable/disable map panning and zooming.
	# It now controls a local flag which is checked in _on_map_view_gui_input.
	_map_is_interactive = is_interactive
	print("MainScreen: Map interaction set to: %s" % is_interactive)
	# If disabling interaction while panning, reset the state.
	if not is_interactive and _is_panning:
		_is_panning = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

# Convert a global mouse position (in main viewport) to SubViewport pixel space used by the map camera
func _to_subviewport_screen(global_pos: Vector2) -> Vector2:
	if not is_instance_valid(map_view):
		return global_pos
	var map_display: TextureRect = map_view.get_node_or_null("MapContainer/MapDisplay")
	var sub_viewport: SubViewport = map_view.get_node_or_null("MapContainer/SubViewport")
	if not is_instance_valid(map_display) or not is_instance_valid(sub_viewport):
		return global_pos
	var display_rect: Rect2 = map_display.get_global_rect()
	var local_in_display: Vector2 = global_pos - display_rect.position
	var sub_size: Vector2i = sub_viewport.size
	return Vector2(
		(local_in_display.x / max(1.0, display_rect.size.x)) * float(sub_size.x),
		(local_in_display.y / max(1.0, display_rect.size.y)) * float(sub_size.y)
	)

# Helper: get the rect we should use for camera viewport sizing (MapDisplay if present, else full map_view)
func _get_map_display_rect() -> Rect2:
	if not is_instance_valid(map_view):
		return Rect2()
	var map_display: TextureRect = map_view.get_node_or_null("MapContainer/MapDisplay")
	if is_instance_valid(map_display):
		return map_display.get_global_rect()
	return map_view.get_global_rect()
