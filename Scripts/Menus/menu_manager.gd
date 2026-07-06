extends Control

## The UI element at the top of the screen that menus should not overlap.
@export var user_info_display: Control

# Preload your actual menu scene files here once you create them
var convoy_menu_scene = preload("res://Scenes/ConvoyMenu.tscn")
# ADD PRELOADS FOR SUB-MENUS (ensure these paths match your new scenes)
var convoy_vehicle_menu_scene = preload("res://Scenes/ConvoyVehicleMenu.tscn") # Example path
var convoy_journey_menu_scene = preload("res://Scenes/ConvoyJourneyMenu.tscn") # Example path
var convoy_settlement_menu_scene = preload("res://Scenes/ConvoySettlementMenu.tscn") # Example path
var convoy_cargo_menu_scene = preload("res://Scenes/ConvoyCargoMenu.tscn") # Example path
var mechanics_menu_scene = preload("res://Scenes/MechanicsMenu.tscn")
var warehouse_menu_scene = load("res://Scenes/WarehouseMenu.tscn")
var settlement_overview_menu_scene = load("res://Scenes/SettlementOverviewMenu.tscn")
var premium_upgrade_modal_scene = preload("res://Scenes/UI/PremiumUpgradeModal.tscn")

const MENU_ORDER = {
	"convoy_overview": 0,
	"convoy_vehicle_submenu": 1,
	"convoy_journey_submenu": 2,    # Nav bar order: Vehicles | Journey | Settlement | Cargo
	"settlement_hub": 3,            # Settlement section landing — takes the old vendor-menu transition slot
	"convoy_settlement_submenu": 4, # single-vendor trade menu — one level deeper than the hub
	"warehouse_submenu": 5,
	"mechanics_submenu": 6,
	"convoy_cargo_submenu": 7
}
var _switch_tween: Tween = null
# True while a menu-switch slide/fade tween is animating. Rapid nav-button mashing during a
# transition previously duplicated menus or left one stuck mid-slide; we ignore new open/switch
# requests until the active tween completes (see the guard at the top of _show_menu).
var _is_switching: bool = false
# Outgoing menu whose disposal is deferred into the active switch tween's callback.
# Tracked so an interrupting switch (which kills that tween) can flush it instead of
# leaving it orphaned in the tree — the cause of the faint "ghost menu" behind a submenu.
var _pending_switch_old_menu: Control = null
var _pending_switch_old_persistent: bool = false

var current_active_menu = null
var menu_stack = [] # To keep track of the navigation path for "back" functionality
var _menu_states = {} # To persist UI states across menu switches
var _next_menu_extra_arg = null # Temp storage for passing a second arg to initialize_with_data

# Persistent menu cache: stores live menu nodes that should survive navigation.
# Key format: "<menu_type>_<convoy_id>"  Value: the MenuBase node instance
var _persistent_menu_cache: Dictionary = {}
# Tracks last-known convoy coords for cache invalidation when the convoy moves.
# Key: convoy_id  Value: {"x": int, "y": int}
var _convoy_coords_snapshot: Dictionary = {}

var _menu_container_host: Control = null

@onready var _hub: Node = get_node_or_null("/root/SignalHub")
@onready var _store: Node = get_node_or_null("/root/GameStore")

var _base_z_index: int
# Ensure this Z-index is higher than ConvoyListPanel's EXPANDED_OVERLAY_Z_INDEX (100)
const MENU_MANAGER_ACTIVE_Z_INDEX = 150 

## Emitted when any menu is opened. Passes the menu node instance.
signal menu_opened(menu_node, menu_type: String)
## Emitted when a menu is closed (either by navigating forward or back). Passes the menu node that was closed.
signal menu_closed(menu_node_was_active, menu_type: String)

## NEW SIGNAL as per new plan. Emitted when menu visibility changes.
signal menu_visibility_changed(is_open: bool, menu_name: String)
## NEW: Emitted with convoy_data when opening a convoy-related menu.
signal convoy_menu_focus_requested(convoy_data: Dictionary)

var _menu_wrapper: VBoxContainer = null
var _menu_content_area: Control = null
var _static_bottom_nav: PanelContainer = null
var _nav_hbox: HBoxContainer = null
var _nav_buttons: Dictionary = {} # menu_type -> Button

func register_menu_container(container: Control):
	_menu_container_host = container
	print("[MenuManager] Successfully registered menu container: ", container.name)
	
	# Setup the static hierarchy
	if is_instance_valid(_menu_wrapper):
		_menu_wrapper.queue_free()
	
	_menu_wrapper = VBoxContainer.new()
	_menu_wrapper.name = "MenuWrapperVBox"
	_menu_wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_wrapper.add_theme_constant_override("separation", 0)
	_menu_container_host.add_child(_menu_wrapper)
	
	_menu_content_area = Control.new()
	_menu_content_area.name = "MenuContentArea"
	_menu_content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_content_area.clip_contents = true
	_menu_wrapper.add_child(_menu_content_area)
	
	_setup_static_bottom_nav()

func _setup_static_bottom_nav():
	_static_bottom_nav = PanelContainer.new()
	_static_bottom_nav.name = "StaticBottomNav"
	_static_bottom_nav.visible = false
	_menu_wrapper.add_child(_static_bottom_nav)
	
	# Bar chrome — metal palette, seats the nav buttons (UITheme tokens).
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = UITheme.METAL_BASE
	bar_style.corner_radius_top_left = UITheme.RADIUS_MD
	bar_style.corner_radius_top_right = UITheme.RADIUS_MD
	bar_style.border_width_top = UITheme.BORDER_THIN
	bar_style.border_color = UITheme.METAL_EDGE
	_static_bottom_nav.add_theme_stylebox_override("panel", bar_style)

	# Fixed HBox so the four nav buttons never wrap and keep a stable rhythm.
	_nav_hbox = HBoxContainer.new()
	_nav_hbox.name = "NavButtonsHBox"
	_nav_hbox.add_theme_constant_override("separation", UITheme.SPACE_SM)
	_nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_static_bottom_nav.add_child(_nav_hbox)
	
	var btn_configs = [
		{"name": "VehicleMenuButton", "text": "Vehicles", "signal": "open_vehicle_menu_requested", "type": "convoy_vehicle_submenu"},
		{"name": "JourneyMenuButton", "text": "Journey", "signal": "open_journey_menu_requested", "type": "convoy_journey_submenu"},
		{"name": "SettlementMenuButton", "text": "Settlement", "signal": "open_settlement_menu_requested", "type": "convoy_settlement_submenu"},
		{"name": "CargoMenuButton", "text": "Cargo", "signal": "open_cargo_menu_requested", "type": "convoy_cargo_submenu"}
	]
	
	for config in btn_configs:
		var btn = Button.new()
		btn.name = config["name"]
		btn.text = config["text"]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func():
			var data = {}
			if is_instance_valid(current_active_menu) and current_active_menu.has_meta("menu_data"):
				data = current_active_menu.get_meta("menu_data")
			
			# If already in this nav section, go back to convoy overview (matches legacy behavior).
			# The Settlement section spans two screens (hub + single vendor menu), so compare slots.
			var active_slot := _nav_slot_for_type(str(current_active_menu.get_meta("menu_type", ""))) if current_active_menu else ""
			if active_slot == config["type"]:
				open_convoy_menu(data)
			else:
				# Call the respective open function
				match config["type"]:
					"convoy_vehicle_submenu": open_convoy_vehicle_menu(data)
					"convoy_journey_submenu": open_journey_journey_menu_if_available(data)
					"convoy_settlement_submenu": open_settlement_overview_menu(data)
					"convoy_cargo_submenu": open_convoy_cargo_menu(data)
		)
		_nav_hbox.add_child(btn)
		_nav_buttons[config["type"]] = btn

func open_journey_journey_menu_if_available(data):
	open_convoy_journey_menu(data)

## Public helper for tutorial/diagnostic tools to find nav buttons in the static bar.
func get_nav_button_by_name(btn_name: String) -> Button:
	if not is_instance_valid(_nav_hbox): return null
	return _nav_hbox.find_child(btn_name, true, false) as Button

func set_nav_button_visible(type: String, is_visible: bool):
	if _nav_buttons.has(type):
		_nav_buttons[type].visible = is_visible

## Maps a concrete menu_type to the bottom-nav slot it lights up. The Settlement section spans two
## screens — the overview hub (settlement_hub) and the single vendor menu (convoy_settlement_submenu) —
## that both belong to the "Settlement" slot.
func _nav_slot_for_type(t: String) -> String:
	if t == "settlement_hub":
		return "convoy_settlement_submenu"
	return t

func _get_logical_safe_margins() -> Rect2:
	# Rect2(position = (left, top), size = (right, bottom)) in logical pixels.
	var sm = get_node_or_null("/root/ui_scale_manager")
	if is_instance_valid(sm) and sm.has_method("get_logical_safe_margins"):
		return sm.get_logical_safe_margins()
	return Rect2()

func _update_static_nav_bar_ui(active_type: String):
	if not is_instance_valid(_static_bottom_nav): return
	
	var is_convoy_submenu = active_type in ["convoy_overview", "convoy_vehicle_submenu", "convoy_journey_submenu", "convoy_cargo_submenu", "convoy_settlement_submenu", "settlement_hub"]
	_static_bottom_nav.visible = is_convoy_submenu
	
	if not is_convoy_submenu: return
	
	# Update layout based on device
	var dsm = get_node_or_null("/root/DeviceStateManager")
	var is_portrait = dsm.get_is_portrait() if is_instance_valid(dsm) else false
	var use_mobile = dsm.is_mobile if is_instance_valid(dsm) else false
	
	var bar_margin := 14.0 if is_portrait else (6.0 if use_mobile else 0.0)
	# Inset the nav-button CONTENT to the safe area (rounded corners + home indicator) while
	# the bar background still bleeds to the physical edges (no black bars). Side margins get
	# a rounded-corner minimum; the bottom margin lifts buttons off the home indicator.
	var safe := _get_logical_safe_margins()
	var side_inset := maxf(bar_margin, maxf(safe.position.x, safe.size.x))
	if is_portrait:
		side_inset = maxf(side_inset, 16.0)
	var bottom_inset := bar_margin + safe.size.y
	var style = _static_bottom_nav.get_theme_stylebox("panel")
	style.content_margin_top = bar_margin
	style.content_margin_bottom = bottom_inset
	style.content_margin_left = side_inset
	style.content_margin_right = side_inset

	# Landscape mobile has a very short viewport, so an 85px nav bar swallowed the menu and
	# pushed action buttons off-screen. Keep it compact there. Portrait/desktop have the height.
	var is_landscape_mobile: bool = bool(use_mobile) and not bool(is_portrait)
	var btn_min_h := 140.0 if is_portrait else (52.0 if is_landscape_mobile else 90.0)
	var base_font_size: int = 28 if is_portrait else (18 if is_landscape_mobile else 28)
	var font_size: int = base_font_size if is_instance_valid(dsm) else base_font_size

	var active_slot := _nav_slot_for_type(active_type)
	for type in _nav_buttons:
		var btn = _nav_buttons[type]
		btn.custom_minimum_size = Vector2(72, btn_min_h)
		# Clip the label so long nav text ("Settlement") can't force the 4 buttons past the
		# logical width and push the bar off both screen edges.
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", font_size)
		
		var is_active = (active_slot == type)
		btn.theme_type_variation = &"NavButtonActive" if is_active else &"NavButton"

func _on_viewport_resized_navbar() -> void:
	# Re-apply nav-bar safe insets / button clipping when the device rotates with a menu open.
	# NOTE: raw size_changed can fire BEFORE DeviceStateManager updates its layout_mode, so this
	# pass may compute with a stale mode. We re-run on DSM.layout_mode_changed (authoritative) and
	# also defer one frame here so the height settles to the correct value instead of snapping
	# drastically on the next menu switch.
	if is_instance_valid(current_active_menu) and current_active_menu.has_meta("menu_type"):
		_update_static_nav_bar_ui(str(current_active_menu.get_meta("menu_type")))
		call_deferred("_reapply_nav_bar_for_active_menu")

func _reapply_nav_bar_for_active_menu() -> void:
	if is_instance_valid(current_active_menu) and current_active_menu.has_meta("menu_type"):
		_update_static_nav_bar_ui(str(current_active_menu.get_meta("menu_type")))

func _on_dsm_layout_mode_changed(_mode: int, _screen_size: Vector2, _is_mobile: bool) -> void:
	# Authoritative layout change — recompute the nav bar height now that DSM has settled, so the
	# bar doesn't keep a stale (e.g. portrait 140px) height after rotating into landscape.
	_reapply_nav_bar_for_active_menu()

func _ready():
	# Initially, no menu is shown. Hide MenuManager so it does not block input.
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE
	_base_z_index = self.z_index # Store initial z_index

	var vp := get_viewport()
	if is_instance_valid(vp) and not vp.size_changed.is_connected(_on_viewport_resized_navbar):
		vp.size_changed.connect(_on_viewport_resized_navbar)

	# Recompute the nav bar on the authoritative layout-mode change (DSM has settled by then),
	# not just on the raw viewport resize which can run with a stale mode.
	var dsm = get_node_or_null("/root/DeviceStateManager")
	if is_instance_valid(dsm) and dsm.has_signal("layout_mode_changed") and not dsm.layout_mode_changed.is_connected(_on_dsm_layout_mode_changed):
		dsm.layout_mode_changed.connect(_on_dsm_layout_mode_changed)

	if is_instance_valid(_hub):
		if _hub.has_signal("convoy_selection_changed") and not _hub.convoy_selection_changed.is_connected(_on_hub_convoy_selection_changed):
			_hub.convoy_selection_changed.connect(_on_hub_convoy_selection_changed)
	else:
		printerr("MenuManager: Could not find SignalHub autoload.")

	if is_instance_valid(_store):
		if _store.has_signal("convoys_changed") and not _store.convoys_changed.is_connected(_on_store_convoys_changed):
			_store.convoys_changed.connect(_on_store_convoys_changed)
	else:
		printerr("MenuManager: Could not find GameStore autoload.")
	
	var push_manager = get_node_or_null("/root/PushNotificationManager")
	if is_instance_valid(push_manager) and push_manager.has_signal("push_dialogue_requested"):
		push_manager.push_dialogue_requested.connect(_on_push_dialogue_requested)
	
	print("MenuManager Initialized: visible=", visible, ", mouse_filter=", mouse_filter)

func _on_push_dialogue_requested(dialogue_id: String) -> void:
	print("MenuManager: Interrupted for push notification dialogue deep-link: ", dialogue_id)
	close_all_menus()
	# TODO: Once the Conversation/Dialogue UI is built, instantiate and show it here using _show_menu
	# or dispatch to the Dialogue Manager.
	print("[MenuManager] Hook for Dialogue UI goes here (dialogue_id: %s)" % dialogue_id)


func _on_hub_convoy_selection_changed(selected_convoy_data: Variant) -> void:
	# This handler is called when a convoy is selected from the dropdown.
	# We only want to open the menu if a valid convoy is selected, not when it's deselected (null).
	if selected_convoy_data is Dictionary and not (selected_convoy_data as Dictionary).is_empty():
		open_convoy_menu(selected_convoy_data)

func _input(event: InputEvent):
	# Only process input if a menu is active and visible.
	if not visible or not is_instance_valid(current_active_menu):
		return
	# Global back button (e.g., Escape key)
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()

func is_any_menu_active() -> bool:
	return current_active_menu != null

### --- Functions to open specific Convoy Menus ---
# NOTE: _emit_menu_area_changed is called after every menu open/close/navigation event.
# This ensures the camera always clamps to the correct visible area.
func open_convoy_menu(convoy_data = null):
	var arg = _extract_convoy_id_or_passthrough(convoy_data)
	_show_menu(convoy_menu_scene, arg)

func open_convoy_vehicle_menu(convoy_data = null):
	print("MenuManager: open_convoy_vehicle_menu called. Convoy Data Received: ")
	print(convoy_data)
	var arg = _extract_convoy_id_or_passthrough(convoy_data)
	_show_menu(convoy_vehicle_menu_scene, arg)

func open_convoy_vehicle_menu_with_focus(convoy_data: Dictionary, vehicle_id: String) -> void:
	# Open the vehicle menu and pass the vehicle_id as extra_arg to pre-select the vehicle
	_next_menu_extra_arg = vehicle_id
	var arg = _extract_convoy_id_or_passthrough(convoy_data)
	_show_menu(convoy_vehicle_menu_scene, arg)

func open_convoy_journey_menu(convoy_data = null):
	var arg = _extract_convoy_id_or_passthrough(convoy_data)
	_show_menu(convoy_journey_menu_scene, arg)

func open_convoy_settlement_menu(convoy_data = null):
	print("MenuManager: open_convoy_settlement_menu called. Data is valid: ", convoy_data != null)
	var arg = _extract_convoy_id_or_passthrough(convoy_data)
	_show_menu(convoy_settlement_menu_scene, arg)

func open_convoy_settlement_menu_with_focus(convoy_data: Dictionary, focus_intent: Dictionary) -> void:
	# Open the settlement menu and pass the focus intent as extra_arg so it can deep-link.
	_next_menu_extra_arg = focus_intent
	var arg = _extract_convoy_id_or_passthrough(convoy_data)
	_show_menu(convoy_settlement_menu_scene, arg)

func open_warehouse_menu(convoy_data = null):
	# IMPORTANT: WarehouseMenu may require extra context like {settlement}.
	# Do not collapse the payload to convoy_id here.
	_show_menu(warehouse_menu_scene, convoy_data)

## Convoy-independent settlement view (Sprint 5). Opened from the map when tapping a settlement where
## the player owns a warehouse. `settlement_data` is the settlement snapshot dict (name, vendors, etc.).
func open_settlement_overview_menu(settlement_data = null):
	_show_menu(settlement_overview_menu_scene, settlement_data)

## Overview hub → open the single-vendor trade menu focused on the chosen vendor. Reuses the existing
## deep-link focus path so the settlement menu lands on this vendor.
func _on_overview_open_vendor(convoy_data: Dictionary, vendor_id: String) -> void:
	var intent := {"target": "settlement_vendor", "vendor_id": vendor_id}
	open_convoy_settlement_menu_with_focus(convoy_data, intent)

func open_convoy_cargo_menu(convoy_data = null):
	if convoy_data == null:
		printerr("MenuManager: open_convoy_cargo_menu called with null data.")
		_show_menu(convoy_cargo_menu_scene, {"vehicle_details_list": [], "convoy_name": "Unknown Convoy"})
		return

	print("MenuManager: open_convoy_cargo_menu called. Data: ", convoy_data.keys() if convoy_data is Dictionary else convoy_data)
	var arg = _extract_convoy_id_or_passthrough(convoy_data)
	_show_menu(convoy_cargo_menu_scene, arg)

func open_convoy_cargo_menu_for_item(convoy_data: Dictionary, item_data: Dictionary):
	# Special handler to open the cargo menu and jump to a specific item.
	_next_menu_extra_arg = item_data
	var arg = _extract_convoy_id_or_passthrough(convoy_data)
	_show_menu(convoy_cargo_menu_scene, arg)

func open_mechanics_menu(convoy_data = null):
	# Gate: require the convoy to be in a settlement
	if convoy_data == null:
		printerr("MenuManager: open_mechanics_menu called with null data.")
		return
	var in_settlement := false
	# Prefer an explicit flag if present
	if convoy_data.has("in_settlement"):
		in_settlement = bool(convoy_data.get("in_settlement"))
	else:
		# Fallback: if coords map to a settlement via GameStore snapshots
		var sx = int(roundf(float(convoy_data.get("x", -9999.0))))
		var sy = int(roundf(float(convoy_data.get("y", -9999.0))))
		in_settlement = _has_settlement_at_coords(sx, sy)
	if not in_settlement:
		push_warning("Mechanic is only available in a settlement.")
		return
	_show_menu(mechanics_menu_scene, convoy_data)



func open_premium_upgrade_menu():
	_show_menu(premium_upgrade_modal_scene, null)

### --- Generic menu handling ---
# _emit_menu_area_changed is only called from menu_manager.gd, never from menu scripts.

func _show_menu(menu_scene_resource, data_to_pass = null, add_to_stack: bool = true):
	# Transition guard: while a switch tween is animating, drop new open/switch requests so rapid
	# nav-button mashing can't duplicate menus or strand one mid-slide. Clear any focus arg queued
	# by an ignored open_*_with_focus() call so it doesn't leak into the next menu that does open.
	if _is_switching:
		_next_menu_extra_arg = null
		return

	# When showing a menu, make MenuManager visible so it can receive input.
	var was_visible := visible
	visible = true

	var old_menu = null
	var old_menu_type = "default"

	if current_active_menu:
		# Save state for non-persistent menus only (persistent ones keep it natively)
		var is_persistent_old = current_active_menu.get("persistence_enabled") == true
		if not is_persistent_old:
			if current_active_menu.has_method("get_menu_state_key") and current_active_menu.has_method("get_ui_state"):
				var state_key = current_active_menu.get_menu_state_key()
				if state_key != "":
					var ui_state = current_active_menu.get_ui_state()
					_menu_states[state_key] = ui_state
					print("[DIAGNOSTIC] MenuManager saved state for key: ", state_key, " state: ", ui_state)

		if add_to_stack:
			menu_stack.append({
				"scene_path": current_active_menu.scene_file_path,
				"data": current_active_menu.get_meta("menu_data", null),
				"type": current_active_menu.get_meta("menu_type", "default")
			})
		old_menu_type = current_active_menu.get_meta("menu_type", "default")
		emit_signal("menu_closed", current_active_menu, old_menu_type)
		old_menu = current_active_menu
		current_active_menu = null

	# --- Determine the menu_type label before resolving the new menu node ---
	var menu_type = "default"
	var use_convoy_style_layout = false
	if menu_scene_resource == convoy_menu_scene:
		menu_type = "convoy_overview"
		use_convoy_style_layout = true
	elif menu_scene_resource == convoy_vehicle_menu_scene:
		menu_type = "convoy_vehicle_submenu"
		use_convoy_style_layout = true
	elif menu_scene_resource == convoy_journey_menu_scene:
		menu_type = "convoy_journey_submenu"
		use_convoy_style_layout = true
	elif menu_scene_resource == convoy_settlement_menu_scene:
		menu_type = "convoy_settlement_submenu"
		use_convoy_style_layout = true
	elif menu_scene_resource == convoy_cargo_menu_scene:
		menu_type = "convoy_cargo_submenu"
		use_convoy_style_layout = true
	elif menu_scene_resource == warehouse_menu_scene:
		menu_type = "warehouse_submenu"
		use_convoy_style_layout = true
	elif menu_scene_resource == settlement_overview_menu_scene:
		# Hub (convoy present here → shows bottom nav under the Settlement slot) vs the standalone
		# map-preview view (no convoy, no bottom nav, Back returns to the map).
		# The nav may pass a convoy dict OR a bare convoy_id string; either means "hub". The map preview
		# passes a settlement dict (no convoy_id) → standalone overview.
		var _ov_has_convoy := false
		if data_to_pass is Dictionary:
			_ov_has_convoy = String((data_to_pass as Dictionary).get("convoy_id", "")) != ""
		elif data_to_pass is String:
			_ov_has_convoy = String(data_to_pass) != ""
		menu_type = "settlement_hub" if _ov_has_convoy else "settlement_overview"
		use_convoy_style_layout = true
	elif menu_scene_resource == mechanics_menu_scene:
		menu_type = "mechanics_submenu"
		use_convoy_style_layout = true
	elif menu_scene_resource == premium_upgrade_modal_scene:
		menu_type = "modal"
		use_convoy_style_layout = false

	# --- Resolve convoy_id for cache key ---
	var cache_convoy_id := ""
	if data_to_pass is Dictionary:
		cache_convoy_id = str((data_to_pass as Dictionary).get("convoy_id", (data_to_pass as Dictionary).get("id", "")))
	elif data_to_pass is String:
		cache_convoy_id = data_to_pass
	var cache_key = menu_type + "_" + cache_convoy_id

	# --- Try to pull from persistent cache ---
	var from_cache := false
	if cache_convoy_id != "" and _persistent_menu_cache.has(cache_key):
		var cached_node = _persistent_menu_cache[cache_key]
		if is_instance_valid(cached_node):
			print("[MenuManager] Restoring cached menu for key: ", cache_key)
			current_active_menu = cached_node
			from_cache = true
		else:
			_persistent_menu_cache.erase(cache_key)

	if not from_cache:
		current_active_menu = menu_scene_resource.instantiate()

	if not is_instance_valid(current_active_menu):
		printerr("MenuManager: Failed to instantiate menu scene: ", menu_scene_resource.resource_path if menu_scene_resource else "null resource")
		if not menu_stack.is_empty():
			go_back()
		else:
			emit_signal("menu_visibility_changed", false, "")
		return

	current_active_menu.set_meta("menu_type", menu_type)

	if not is_instance_valid(_menu_container_host):
		printerr("MenuManager CRITICAL: No menu container host has been registered. Cannot display menu.")
		if not menu_stack.is_empty():
			go_back()
		else:
			emit_signal("menu_visibility_changed", false, "")
		return

	# Add to tree (re-parent if coming from cache; regular add_child if new)
	var host = _menu_content_area if is_instance_valid(_menu_content_area) else _menu_container_host
	if not current_active_menu.is_inside_tree():
		host.add_child(current_active_menu)
	elif current_active_menu.get_parent() != host:
		current_active_menu.reparent(host)
	
	_update_static_nav_bar_ui(menu_type)

	# Only the menu panel itself should block input, not the entire MenuManager
	if current_active_menu is Control:
		current_active_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	self.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var is_returning_from_cache := from_cache
	if not is_returning_from_cache:
		# Fresh instance: call initialize_with_data as before
		if current_active_menu.has_method("initialize_with_data"):
			if _next_menu_extra_arg != null:
				current_active_menu.call_deferred("initialize_with_data", data_to_pass, _next_menu_extra_arg)
				_next_menu_extra_arg = null
			else:
				current_active_menu.call_deferred("initialize_with_data", data_to_pass)

		# Cache this node if it opts in
		if current_active_menu.get("persistence_enabled") == true and cache_convoy_id != "":
			_persistent_menu_cache[cache_key] = current_active_menu
			print("[MenuManager] Cached new persistent menu: ", cache_key)
	else:
		# Returning from cache: restore mouse input that was killed by _disable_mouse_recursive
		# during the outgoing animation.
		_restore_mouse_recursive(current_active_menu)
		# A focus intent (e.g. a specific vendor, or a vehicle) means the caller wants a DIFFERENT target
		# than whatever the cached instance last showed. The cache key is keyed only by convoy_id, so
		# without this the cached menu would keep its previous target. Re-apply the intent.
		if _next_menu_extra_arg != null and current_active_menu.has_method("initialize_with_data"):
			current_active_menu.call_deferred("initialize_with_data", data_to_pass, _next_menu_extra_arg)
		_next_menu_extra_arg = null
		print("[MenuManager] Menu restored from cache — mouse input re-enabled.")

	if data_to_pass:
		current_active_menu.set_meta("menu_data", data_to_pass)

	var has_key_method = current_active_menu.has_method("get_menu_state_key")
	var has_apply_method = current_active_menu.has_method("apply_ui_state")
	print("[DIAGNOSTIC] MenuManager check for ", current_active_menu.name, " has_key: ", has_key_method, " has_apply: ", has_apply_method)

	if has_key_method and has_apply_method:
		# Ensure the menu has its convoy_id set before we ask for the state key.
		# Since initialize_with_data is deferred, we set it manually here for the key lookup.
		var cid := ""
		if data_to_pass is Dictionary:
			cid = str(data_to_pass.get("convoy_id", data_to_pass.get("id", "")))
		elif data_to_pass is String:
			cid = data_to_pass
			
		if cid != "" and "convoy_id" in current_active_menu:
			current_active_menu.convoy_id = cid

		var state_key = current_active_menu.get_menu_state_key()
		if _menu_states.has(state_key):
			print("[DIAGNOSTIC] MenuManager restoring state for key: ", state_key, " state: ", _menu_states[state_key])
			print("[DIAGNOSTIC] MenuManager: INVOKING apply_ui_state() synchronously now.")
			current_active_menu.apply_ui_state(_menu_states[state_key])
		else:
			print("[DIAGNOSTIC] MenuManager no saved state found for key: ", state_key)

	if current_active_menu is Control:
		var menu_node_control = current_active_menu
		var top_margin = 0.0
		if is_instance_valid(user_info_display) and user_info_display.is_visible_in_tree():
			top_margin = user_info_display.size.y
		if use_convoy_style_layout:
			# Only emit visibility change on initial open, not during submenu switches.
			if not was_visible:
				emit_signal("menu_visibility_changed", true, "convoy_menu")
			
			menu_node_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			menu_node_control.offset_top = top_margin
		else:
			menu_node_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			menu_node_control.offset_top = top_margin

	if old_menu:
		var old_is_persistent = old_menu.get("persistence_enabled") == true
		print("[MenuManager] Old menu: ", old_menu.name, " type: ", old_menu_type, " is_persistent: ", old_is_persistent)
		if use_convoy_style_layout and old_menu.get_meta("menu_type", "default") in MENU_ORDER and menu_type in MENU_ORDER:
			_animate_menu_switch(old_menu, current_active_menu, old_menu_type, menu_type, old_is_persistent)
		else:
			if old_is_persistent and is_instance_valid(host):
				print("[MenuManager] Detaching persistent old menu: ", old_menu.name)
				host.remove_child(old_menu)
			else:
				print("[MenuManager] Freeing non-persistent old menu: ", old_menu.name)
				old_menu.queue_free()

	# --- DIAGNOSTIC TEST: Force all menu layers to ignore input ---
	# A menu is now active. This manager will now intercept all clicks.
	# mouse_filter = MOUSE_FILTER_STOP
	# (Removed) Diagnostic overrides that broke menu input handling.
	# --- END DIAGNOSTIC TEST ---

	self.z_index = MENU_MANAGER_ACTIVE_Z_INDEX
	emit_signal("menu_opened", current_active_menu, menu_type)

	# NEW: emit focus request with convoy data if present
	var menu_data_for_focus: Variant = current_active_menu.get_meta("menu_data", null)
	if menu_data_for_focus is Dictionary and not (menu_data_for_focus as Dictionary).is_empty():
		emit_signal("convoy_menu_focus_requested", menu_data_for_focus)

	if current_active_menu.has_signal("back_requested"):
		if not current_active_menu.back_requested.is_connected(go_back):
			current_active_menu.back_requested.connect(go_back, CONNECT_ONE_SHOT)

	var is_convoy_submenu = menu_type in ["convoy_overview", "convoy_vehicle_submenu", "convoy_journey_submenu", "convoy_cargo_submenu", "convoy_settlement_submenu"]

	if is_convoy_submenu:
		# Standard navigation bar signals — safe reconnect (ONE_SHOT was consumed on cache menus)
		var _s = current_active_menu
		if _s.has_signal("open_vehicle_menu_requested") and not _s.open_vehicle_menu_requested.is_connected(open_convoy_vehicle_menu):
			_s.open_vehicle_menu_requested.connect(open_convoy_vehicle_menu, CONNECT_ONE_SHOT)
		if _s.has_signal("open_journey_menu_requested") and not _s.open_journey_menu_requested.is_connected(open_convoy_journey_menu):
			_s.open_journey_menu_requested.connect(open_convoy_journey_menu, CONNECT_ONE_SHOT)
		# Settlement entry now lands on the overview hub (which then opens a single vendor menu).
		if _s.has_signal("open_settlement_menu_requested") and not _s.open_settlement_menu_requested.is_connected(open_settlement_overview_menu):
			_s.open_settlement_menu_requested.connect(open_settlement_overview_menu, CONNECT_ONE_SHOT)
		if _s.has_signal("open_cargo_menu_requested") and not _s.open_cargo_menu_requested.is_connected(open_convoy_cargo_menu):
			_s.open_cargo_menu_requested.connect(open_convoy_cargo_menu, CONNECT_ONE_SHOT)
		if _s.has_signal("return_to_convoy_overview_requested") and not _s.return_to_convoy_overview_requested.is_connected(open_convoy_menu):
			_s.return_to_convoy_overview_requested.connect(open_convoy_menu, CONNECT_ONE_SHOT)

		# Specific sub-menu signals and deep-links
		if menu_type == "convoy_overview":
			if _s.has_signal("open_settlement_menu_with_focus_requested") and not _s.open_settlement_menu_with_focus_requested.is_connected(open_convoy_settlement_menu_with_focus):
				_s.open_settlement_menu_with_focus_requested.connect(open_convoy_settlement_menu_with_focus, CONNECT_ONE_SHOT)
			if _s.has_signal("open_cargo_menu_inspect_requested") and not _s.open_cargo_menu_inspect_requested.is_connected(open_convoy_cargo_menu_for_item):
				_s.open_cargo_menu_inspect_requested.connect(open_convoy_cargo_menu_for_item, CONNECT_ONE_SHOT)
		elif menu_type == "convoy_vehicle_submenu":
			if _s.has_signal("inspect_all_convoy_cargo_requested") and not _s.inspect_all_convoy_cargo_requested.is_connected(open_convoy_cargo_menu):
				_s.inspect_all_convoy_cargo_requested.connect(open_convoy_cargo_menu, CONNECT_ONE_SHOT)
			if _s.has_signal("inspect_specific_convoy_cargo_requested") and not _s.inspect_specific_convoy_cargo_requested.is_connected(open_convoy_cargo_menu_for_item):
				_s.inspect_specific_convoy_cargo_requested.connect(open_convoy_cargo_menu_for_item, CONNECT_ONE_SHOT)
			if _s.has_signal("open_mechanics_menu_requested") and not _s.open_mechanics_menu_requested.is_connected(open_mechanics_menu):
				_s.open_mechanics_menu_requested.connect(open_mechanics_menu, CONNECT_ONE_SHOT)
		elif menu_type == "convoy_cargo_submenu":
			if _s.has_signal("open_vehicle_menu_with_focus_requested") and not _s.open_vehicle_menu_with_focus_requested.is_connected(open_convoy_vehicle_menu_with_focus):
				_s.open_vehicle_menu_with_focus_requested.connect(open_convoy_vehicle_menu_with_focus, CONNECT_ONE_SHOT)
		elif menu_type == "convoy_settlement_submenu":
			if _s.has_signal("open_mechanics_menu_requested") and not _s.open_mechanics_menu_requested.is_connected(open_mechanics_menu):
				_s.open_mechanics_menu_requested.connect(open_mechanics_menu, CONNECT_ONE_SHOT)
			if _s.has_signal("open_warehouse_menu_requested") and not _s.open_warehouse_menu_requested.is_connected(open_warehouse_menu):
				_s.open_warehouse_menu_requested.connect(open_warehouse_menu, CONNECT_ONE_SHOT)

	# Settlement overview / hub — forward its Warehouse entry, vendor selection, and Back.
	if menu_type == "settlement_overview" or menu_type == "settlement_hub":
		if current_active_menu.has_signal("open_warehouse_menu_requested") and not current_active_menu.open_warehouse_menu_requested.is_connected(open_warehouse_menu):
			current_active_menu.open_warehouse_menu_requested.connect(open_warehouse_menu, CONNECT_ONE_SHOT)
		if current_active_menu.has_signal("open_vendor_requested") and not current_active_menu.open_vendor_requested.is_connected(_on_overview_open_vendor):
			current_active_menu.open_vendor_requested.connect(_on_overview_open_vendor, CONNECT_ONE_SHOT)
		if current_active_menu.has_signal("back_requested") and not current_active_menu.back_requested.is_connected(go_back):
			current_active_menu.back_requested.connect(go_back, CONNECT_ONE_SHOT)

# Animation constants for menu switching
const SWITCH_DURATION := 0.42
const SWITCH_PARALLAX := 0.35 # Outgoing menu travels this fraction of the distance, creating depth

func _animate_menu_switch(old_menu: Control, new_menu: Control, old_type: String, new_type: String, old_is_persistent: bool = false) -> void:
	# Mark the transition as in-flight up front so the _show_menu guard covers the deferred gap
	# below (the tween isn't created until _start_menu_switch_animation runs next frame).
	_is_switching = true
	if _switch_tween and _switch_tween.is_valid():
		_switch_tween.kill()

	var old_idx = MENU_ORDER.get(old_type, 0)
	var new_idx = MENU_ORDER.get(new_type, 0)

	var direction = 1 if new_idx > old_idx else -1
	if new_idx == old_idx: direction = 1

	var slide_distance = _menu_content_area.size.x if is_instance_valid(_menu_content_area) else 400.0

	# Defer one frame so new menu layout settles before reading position.
	call_deferred("_start_menu_switch_animation", old_menu, new_menu, direction, slide_distance, old_type, new_type, old_is_persistent)

## Recursively sets MOUSE_FILTER_IGNORE on a node and all descendants.
## Used to prevent click-through on the outgoing menu during a transition.
func _disable_mouse_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_disable_mouse_recursive(child)

## Recursively restores MOUSE_FILTER_PASS on a node and all descendants.
## Called when a persistent menu is pulled from cache so it becomes interactive again.
func _restore_mouse_recursive(node: Node) -> void:
	if node is Control:
		# Root of the menu stays STOP (blocks click-through), children get PASS
		if node == current_active_menu:
			(node as Control).mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			(node as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	for child in node.get_children():
		_restore_mouse_recursive(child)

## Dispose of a switch's outgoing menu: detach if persistent (kept in cache), else free.
func _finalize_switch_old_menu(node: Control, is_persistent: bool) -> void:
	if not is_instance_valid(node):
		return
	var host = _menu_content_area if is_instance_valid(_menu_content_area) else _menu_container_host
	if is_persistent and is_instance_valid(host) and node.get_parent() == host:
		host.remove_child(node)
	else:
		node.queue_free()

func _start_menu_switch_animation(old_menu: Control, new_menu: Control, direction: int, slide_distance: float, old_type: String = "", new_type: String = "", old_is_persistent: bool = false) -> void:
	var host = _menu_content_area if is_instance_valid(_menu_content_area) else _menu_container_host

	# Flush an outgoing menu left over from a prior switch that was interrupted before its
	# tween callback could dispose of it (otherwise it lingers as a ghost behind the new menu).
	if is_instance_valid(_pending_switch_old_menu) and _pending_switch_old_menu != old_menu and _pending_switch_old_menu != new_menu:
		_finalize_switch_old_menu(_pending_switch_old_menu, _pending_switch_old_persistent)
	_pending_switch_old_menu = null

	if not is_instance_valid(new_menu) or not is_instance_valid(old_menu):
		if is_instance_valid(old_menu):
			_finalize_switch_old_menu(old_menu, old_is_persistent)
		_is_switching = false
		return

	# Track this switch's outgoing menu so an interrupting switch can flush it.
	_pending_switch_old_menu = old_menu
	_pending_switch_old_persistent = old_is_persistent

	# Kill input on the outgoing menu immediately
	_disable_mouse_recursive(old_menu)
	new_menu.move_to_front()

	# Hide per-menu tiled backgrounds (host container provides the same texture statically)
	var old_bg = old_menu.get_node_or_null("OoriBackground")
	var new_bg = new_menu.get_node_or_null("OoriBackground")
	if is_instance_valid(old_bg): old_bg.visible = false
	if is_instance_valid(new_bg): new_bg.visible = false

	# CRITICAL: Clip the host so only one panel is visible at a time.
	if is_instance_valid(host):
		host.clip_contents = true

	# --- OVERARCHING MENU LOGIC (Convoy Overview) ---
	# If we are entering or leaving the Convoy Overview, use a vertical swipe.
	# "convoy_overview" is treated as a layer "above" the others.
	var is_vertical := (old_type == "convoy_overview" or new_type == "convoy_overview")
	
	if is_vertical:
		var slide_height = host.size.y if is_instance_valid(host) else 800.0
		var base_y := old_menu.position.y
		
		# Ensure X is consistent
		new_menu.position.x = old_menu.position.x
		
		if new_type == "convoy_overview":
			# Entering Overview: swipes DOWN from the top (covering the submenu)
			new_menu.position.y = base_y - slide_height
			new_menu.modulate.a = 1.0
			new_menu.move_to_front() 
			
			_switch_tween = create_tween()
			_switch_tween.set_parallel(true)
			_switch_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_switch_tween.tween_property(new_menu, "position:y", base_y, SWITCH_DURATION)
			# Fade out the background menu slightly
			_switch_tween.tween_property(old_menu, "modulate:a", 0.0, SWITCH_DURATION * 0.5)
		else:
			# Leaving Overview: swipes UP to the top (revealing the submenu)
			new_menu.position.y = base_y
			new_menu.modulate.a = 0.0 # Submenu fades in behind
			old_menu.move_to_front() # Keep Overview on top
			
			_switch_tween = create_tween()
			_switch_tween.set_parallel(true)
			_switch_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			_switch_tween.tween_property(old_menu, "position:y", base_y - slide_height, SWITCH_DURATION)
			_switch_tween.tween_property(new_menu, "modulate:a", 1.0, SWITCH_DURATION)
			
		_switch_tween.chain().tween_callback(func():
			_finalize_switch_old_menu(old_menu, old_is_persistent)
			if _pending_switch_old_menu == old_menu:
				_pending_switch_old_menu = null
			if is_instance_valid(new_menu):
				new_menu.position.y = base_y
				new_menu.modulate.a = 1.0
				var restored_bg = new_menu.get_node_or_null("OoriBackground")
				if is_instance_valid(restored_bg): restored_bg.visible = true
			_is_switching = false
		)
		return

	# --- SLIDESHOW LAYOUT (Submenus) ---
	# Old menu: currently at its normal position (in frame).
	# New menu: starts exactly one panel-width to the entry side (out of frame).
	var base_x := old_menu.position.x
	var old_exit_x := base_x - (direction * slide_distance)
	var new_start_x := base_x + (direction * slide_distance)
	var new_target_x := base_x

	new_menu.position.x = new_start_x
	new_menu.modulate.a = 1.0 

	_switch_tween = create_tween()
	_switch_tween.set_parallel(true)
	_switch_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	_switch_tween.tween_property(old_menu, "position:x", old_exit_x, SWITCH_DURATION)
	_switch_tween.tween_property(new_menu, "position:x", new_target_x, SWITCH_DURATION)

	_switch_tween.chain().tween_callback(func():
		_finalize_switch_old_menu(old_menu, old_is_persistent)
		if _pending_switch_old_menu == old_menu:
			_pending_switch_old_menu = null
		if is_instance_valid(new_menu):
			new_menu.position.x = new_target_x
			var restored_bg = new_menu.get_node_or_null("OoriBackground")
			if is_instance_valid(restored_bg): restored_bg.visible = true
		_is_switching = false
	)

func _extract_convoy_id_or_passthrough(d: Variant) -> Variant:
	if d is Dictionary:
		var cid := String((d as Dictionary).get("convoy_id", (d as Dictionary).get("id", "")))
		if cid != "":
			return cid
	return d

func go_back():
	if not is_instance_valid(current_active_menu):
		if not menu_stack.is_empty():
			var _previous_menu_info = menu_stack.pop_back()
			var _prev_scene_path = _previous_menu_info.get("scene_path")
			var _prev_data = _previous_menu_info.get("data")
			# Replace with freshest convoy data if available (handles String convoy_id too)
			var _prev_arg = _prev_data
			if typeof(_prev_arg) == TYPE_DICTIONARY and (_prev_arg as Dictionary).has("convoy_id"):
				var latest := _get_latest_convoy_by_id(str((_prev_arg as Dictionary).get("convoy_id")))
				if not latest.is_empty():
					_prev_arg = latest.duplicate(true)
			elif typeof(_prev_arg) == TYPE_STRING:
				var latest_s := _get_latest_convoy_by_id(String(_prev_arg))
				if not latest_s.is_empty():
					_prev_arg = latest_s.duplicate(true)
			if _prev_scene_path:
				var _scene_resource = load(_prev_scene_path)
				if _scene_resource:
					_show_menu(_scene_resource, _prev_arg, false)
					return
		# No previous menu to go back to; fully closing menus.
		# Deselect any globally selected convoy so the user isn't forced to click again to clear it.
		_request_clear_selection()
		emit_signal("menu_visibility_changed", false, "")
		_update_static_nav_bar_ui("")
		visible = false
		return


	if menu_stack.is_empty():
		if current_active_menu.has_method("get_menu_state_key") and current_active_menu.has_method("get_ui_state"):
			var state_key = current_active_menu.get_menu_state_key()
			_menu_states[state_key] = current_active_menu.get_ui_state()
			
		var _closed_menu_type = current_active_menu.get_meta("menu_type", "default")
		emit_signal("menu_closed", current_active_menu, _closed_menu_type)
		current_active_menu.queue_free()
		current_active_menu = null
		mouse_filter = MOUSE_FILTER_IGNORE
		self.z_index = _base_z_index
		# We're closing the last open menu. Clear convoy selection to remove the highlight in the convoy list.
		_request_clear_selection()
		emit_signal("menu_visibility_changed", false, "")
		_update_static_nav_bar_ui("")
		visible = false
		return

	# Let _show_menu handle the 'menu_closed' emission and queue_free for the old menu so it can animate.
	# We just pop the previous info and let _show_menu take over.
	var _previous_menu_info2 = menu_stack.pop_back()
	var _prev_scene_path2 = _previous_menu_info2.get("scene_path")
	var _prev_data2 = _previous_menu_info2.get("data")
	# Replace with freshest convoy data if available
	var _prev_arg2 = _prev_data2
	if typeof(_prev_arg2) == TYPE_DICTIONARY and (_prev_arg2 as Dictionary).has("convoy_id"):
		var latest2 := _get_latest_convoy_by_id(str((_prev_arg2 as Dictionary).get("convoy_id")))
		if not latest2.is_empty():
			_prev_arg2 = latest2.duplicate(true)
	elif typeof(_prev_arg2) == TYPE_STRING:
		var latest2s := _get_latest_convoy_by_id(String(_prev_arg2))
		if not latest2s.is_empty():
			_prev_arg2 = latest2s.duplicate(true)
	if _prev_scene_path2:
		var _scene_resource2 = load(_prev_scene_path2)
		if _scene_resource2:
			_show_menu(_scene_resource2, _prev_arg2, false)
		else:
			printerr("MenuManager: Failed to load previous menu scene: ", _prev_scene_path2, ". Attempting to go back further if possible.")
			go_back()
	else:
		printerr("MenuManager: Previous menu info in stack did not have a scene_path. Attempting to go back further.")
		go_back()

func request_convoy_menu(convoy_data): # This is the public API called by main.gd
	open_convoy_menu(convoy_data)

func close_all_menus():
	"""
	Closes all currently open menus and clears the menu stack.
	Emits 'menus_completely_closed' when done.
	"""
	if not is_any_menu_active():
		# If no menu is considered active, ensure the signal is still emitted
		# in case the state is inconsistent or this is called to be certain.
		if menu_stack.is_empty() and not is_instance_valid(current_active_menu):
			mouse_filter = MOUSE_FILTER_IGNORE # Ensure mouse filter is reset.
			self.z_index = _base_z_index # Ensure z_index is reset
			# Also clear any selected convoy to keep UI consistent with a closed menu state.
			_request_clear_selection()
			emit_signal("menu_visibility_changed", false, "")
		return

	menu_stack.clear() # Prevent go_back from reopening anything
	go_back() # Call go_back to handle closing the current_active_menu and emitting signals

	# Free all persistent cached menus since we are fully closing
	for cached_node in _persistent_menu_cache.values():
		if is_instance_valid(cached_node):
			cached_node.queue_free()
	_persistent_menu_cache.clear()
	_convoy_coords_snapshot.clear()



func _on_store_convoys_changed(all_convoy_data: Array) -> void:
	if not is_instance_valid(current_active_menu):
		return
	# Rely on MenuBase to handle store-driven UI refresh. Keep meta snapshots fresh.
	var menu_data = current_active_menu.get_meta("menu_data", null)
	var current_id: String = ""
	if typeof(menu_data) == TYPE_DICTIONARY and (menu_data as Dictionary).has("convoy_id"):
		current_id = str((menu_data as Dictionary).get("convoy_id"))
	elif typeof(menu_data) == TYPE_STRING:
		current_id = String(menu_data)
	if not current_id.is_empty():
		for convoy in all_convoy_data:
			if convoy is Dictionary and (convoy as Dictionary).has("convoy_id") and str((convoy as Dictionary).get("convoy_id")) == current_id:
				current_active_menu.set_meta("menu_data", (convoy as Dictionary).duplicate(true))
				break
	# Also update any stacked menu data snapshots so Back restores fresh data
	if not menu_stack.is_empty():
		for i in range(menu_stack.size()):
			var entry = menu_stack[i]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var data_snap = entry.get("data", null)
			var cid: String = ""
			if typeof(data_snap) == TYPE_DICTIONARY and (data_snap as Dictionary).has("convoy_id"):
				cid = str((data_snap as Dictionary).get("convoy_id"))
			elif typeof(data_snap) == TYPE_STRING:
				cid = String(data_snap)
			if not cid.is_empty():
				for convoy2 in all_convoy_data:
					if convoy2 is Dictionary and (convoy2 as Dictionary).has("convoy_id") and str((convoy2 as Dictionary).get("convoy_id")) == cid:
						entry["data"] = (convoy2 as Dictionary).duplicate(true)
						menu_stack[i] = entry
						break

	# Invalidate persistent cache entries for convoys that have moved
	for convoy in all_convoy_data:
		if not (convoy is Dictionary):
			continue
		var cid2 := str((convoy as Dictionary).get("convoy_id", ""))
		if cid2.is_empty():
			continue
		var new_x := int((convoy as Dictionary).get("x", -9999))
		var new_y := int((convoy as Dictionary).get("y", -9999))
		if _convoy_coords_snapshot.has(cid2):
			var snap: Dictionary = _convoy_coords_snapshot[cid2]
			if snap.get("x", -9999) != new_x or snap.get("y", -9999) != new_y:
				# Convoy moved — evict all its cached menus
				var keys_to_erase: Array = []
				for ck in _persistent_menu_cache.keys():
					if str(ck).ends_with("_" + cid2):
						var old_node = _persistent_menu_cache[ck]
						if is_instance_valid(old_node) and not old_node.is_inside_tree():
							old_node.queue_free()
						keys_to_erase.append(ck)
				for ck in keys_to_erase:
					_persistent_menu_cache.erase(ck)
				print("[MenuManager] Cache invalidated for convoy ", cid2, " — convoy moved.")
		_convoy_coords_snapshot[cid2] = {"x": new_x, "y": new_y}


func _request_clear_selection() -> void:
	if not is_instance_valid(_hub):
		return
	if _hub.has_signal("convoy_selection_requested"):
		_hub.convoy_selection_requested.emit("", false)
	else:
		# Fallback: directly clear resolved selection if request signal isn't available.
		_hub.convoy_selection_changed.emit(null)
		_hub.selected_convoy_ids_changed.emit([])


func _get_latest_convoy_by_id(convoy_id: String) -> Dictionary:
	if convoy_id.is_empty() or not is_instance_valid(_store) or not _store.has_method("get_convoys"):
		return {}
	var convoys: Array = _store.get_convoys()
	for c in convoys:
		if c is Dictionary and (c as Dictionary).has("convoy_id") and str((c as Dictionary).get("convoy_id")) == convoy_id:
			return c as Dictionary
	return {}


func _has_settlement_at_coords(x: int, y: int) -> bool:
	if x == -9999 or y == -9999:
		return false
	if not is_instance_valid(_store) or not _store.has_method("get_settlements"):
		return false
	var settlements: Array = _store.get_settlements()
	for s in settlements:
		if s is Dictionary:
			var sx := int((s as Dictionary).get("x", -9999))
			var sy := int((s as Dictionary).get("y", -9999))
			if sx == x and sy == y:
				return true
	return false
