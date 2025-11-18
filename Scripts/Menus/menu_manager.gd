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


var current_active_menu = null
var menu_stack = [] # To keep track of the navigation path for "back" functionality

var _menu_container_host: Control = null

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

func register_menu_container(container: Control):
	_menu_container_host = container
	print("[MenuManager] Successfully registered menu container: ", container.name)

func _ready():
	# Initially, no menu is shown. Hide MenuManager so it does not block input.
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE
	_base_z_index = self.z_index # Store initial z_index
	
	# Get the GameDataManager and connect to its signal
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if gdm.has_signal("convoy_selection_changed"):
			gdm.convoy_selection_changed.connect(_on_gdm_convoy_selection_changed)
		else:
			printerr("MenuManager: GameDataManager is missing 'convoy_selection_changed' signal.")
		# Connect to convoy data updates so active menus refresh automatically
		if gdm.has_signal("convoy_data_updated") and not gdm.convoy_data_updated.is_connected(_on_gdm_convoy_data_updated):
			gdm.convoy_data_updated.connect(_on_gdm_convoy_data_updated)
	else:
		printerr("MenuManager: Could not find GameDataManager autoload.")
	
	# Example: open_main_menu()
	print("MenuManager Initialized: visible=", visible, ", mouse_filter=", mouse_filter)
	pass

func _on_gdm_convoy_selection_changed(selected_convoy_data: Variant):
	# This handler is called when a convoy is selected from the dropdown.
	# We only want to open the menu if a valid convoy is selected, not when it's deselected (null).
	if selected_convoy_data:
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
	_show_menu(convoy_menu_scene, convoy_data)

func open_convoy_vehicle_menu(convoy_data = null):
	print("MenuManager: open_convoy_vehicle_menu called. Convoy Data Received: ")
	print(convoy_data)
	_show_menu(convoy_vehicle_menu_scene, convoy_data)

func open_convoy_journey_menu(convoy_data = null):
	_show_menu(convoy_journey_menu_scene, convoy_data)

func open_convoy_settlement_menu(convoy_data = null):
	print("MenuManager: open_convoy_settlement_menu called. Data is valid: ", convoy_data != null)
	_show_menu(convoy_settlement_menu_scene, convoy_data)

func open_warehouse_menu(convoy_data = null):
	_show_menu(warehouse_menu_scene, convoy_data)

func open_convoy_cargo_menu(convoy_data = null):
	if convoy_data == null:
		printerr("MenuManager: open_convoy_cargo_menu called with null data.")
		_show_menu(convoy_cargo_menu_scene, {"vehicle_details_list": [], "convoy_name": "Unknown Convoy"})
		return

	print("MenuManager: open_convoy_cargo_menu called. Original Convoy Data Keys: ", convoy_data.keys())
	_show_menu(convoy_cargo_menu_scene, convoy_data.duplicate(true))

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
		# Fallback: if coords map to a settlement via GameDataManager
		var gdm = get_node_or_null("/root/GameDataManager")
		if is_instance_valid(gdm) and gdm.has_method("get_settlement_name_from_coords"):
			var sx = int(roundf(float(convoy_data.get("x", -9999.0))))
			var sy = int(roundf(float(convoy_data.get("y", -9999.0))))
			var sett_name = gdm.get_settlement_name_from_coords(sx, sy)
			in_settlement = sett_name != null and String(sett_name) != ""
	if not in_settlement:
		push_warning("Mechanic is only available in a settlement.")
		return
	_show_menu(mechanics_menu_scene, convoy_data)


### --- Generic menu handling ---
# _emit_menu_area_changed is only called from menu_manager.gd, never from menu scripts.

func _show_menu(menu_scene_resource, data_to_pass = null, add_to_stack: bool = true):
	# When showing a menu, make MenuManager visible so it can receive input.
	visible = true

	if current_active_menu:
		if add_to_stack:
			menu_stack.append({
				"scene_path": current_active_menu.scene_file_path,
				"data": current_active_menu.get_meta("menu_data", null),
				"type": current_active_menu.get_meta("menu_type", "default")
			})
		var closed_menu_type = current_active_menu.get_meta("menu_type", "default")
		emit_signal("menu_closed", current_active_menu, closed_menu_type)
		current_active_menu.queue_free()
		current_active_menu = null

	current_active_menu = menu_scene_resource.instantiate()
	if not is_instance_valid(current_active_menu):
		printerr("MenuManager: Failed to instantiate menu scene: ", menu_scene_resource.resource_path if menu_scene_resource else "null resource")
		if not menu_stack.is_empty():
			go_back()
		else:
			emit_signal("menu_visibility_changed", false, "")
		return

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

	current_active_menu.set_meta("menu_type", menu_type)

	if not is_instance_valid(_menu_container_host):
		printerr("MenuManager CRITICAL: No menu container host has been registered. Cannot display menu.")
		if not menu_stack.is_empty():
			go_back()
		else:
			emit_signal("menu_visibility_changed", false, "")
		return

	_menu_container_host.add_child(current_active_menu)
	# Only the menu panel itself should block input, not the entire MenuManager
	if current_active_menu is Control:
		current_active_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	self.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if current_active_menu.has_method("initialize_with_data"):
		current_active_menu.call_deferred("initialize_with_data", data_to_pass)
	if data_to_pass:
		current_active_menu.set_meta("menu_data", data_to_pass)

	if current_active_menu is Control:
		var menu_node_control = current_active_menu
		var top_margin = 0.0
		if is_instance_valid(user_info_display) and user_info_display.is_visible_in_tree():
			top_margin = user_info_display.size.y
		if use_convoy_style_layout:
			emit_signal("menu_visibility_changed", true, "convoy_menu")
			menu_node_control.anchor_left = 1.0 / 3.0
			menu_node_control.anchor_right = 1.0
			menu_node_control.anchor_top = 0.0
			menu_node_control.anchor_bottom = 1.0
			menu_node_control.offset_left = 0
			menu_node_control.offset_right = 0
			menu_node_control.offset_top = top_margin
			menu_node_control.offset_bottom = 0
		elif false:
			var menu_size = menu_node_control.custom_minimum_size
			if menu_size.x == 0 or menu_size.y == 0:
				menu_node_control.update_minimum_size()
				menu_size = menu_node_control.get_combined_minimum_size()
				if menu_size.x == 0 or menu_size.y == 0:
					printerr("MenuManager: ConvoyMenu's size could not be determined (custom_minimum_size and get_combined_minimum_size are zero). Using fallback size (300, 400). This may lead to incorrect layout. Please set custom_minimum_size in ConvoyMenu.tscn or ensure its content defines a size.")
					if menu_size.x == 0: menu_size.x = 300
					if menu_size.y == 0: menu_size.y = 400
			menu_node_control.anchor_left = 1.0
			menu_node_control.anchor_right = 1.0
			menu_node_control.anchor_top = 0.5
			menu_node_control.anchor_bottom = 0.5
			menu_node_control.offset_left = -menu_size.x
			menu_node_control.offset_right = 0
			menu_node_control.offset_top = -menu_size.y / 2.0 + top_margin / 2.0
			menu_node_control.offset_bottom = menu_size.y / 2.0 + top_margin / 2.0
		else:
			menu_node_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			menu_node_control.offset_top = top_margin

	# --- DIAGNOSTIC TEST: Force all menu layers to ignore input ---
	# A menu is now active. This manager will now intercept all clicks.
	# mouse_filter = MOUSE_FILTER_STOP
	self.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(current_active_menu):
		current_active_menu.mouse_filter = MOUSE_FILTER_IGNORE
	# --- END DIAGNOSTIC TEST ---

	self.z_index = MENU_MANAGER_ACTIVE_Z_INDEX
	emit_signal("menu_opened", current_active_menu, menu_type)

	# NEW: emit focus request with convoy data if present
	var menu_data_for_focus: Variant = current_active_menu.get_meta("menu_data", null)
	if menu_data_for_focus is Dictionary and not (menu_data_for_focus as Dictionary).is_empty():
		emit_signal("convoy_menu_focus_requested", menu_data_for_focus)

	if current_active_menu.has_signal("back_requested"):
		current_active_menu.back_requested.connect(go_back, CONNECT_ONE_SHOT)

	if menu_type == "convoy_overview":
		if current_active_menu.has_signal("open_vehicle_menu_requested"):
			current_active_menu.open_vehicle_menu_requested.connect(open_convoy_vehicle_menu, CONNECT_ONE_SHOT)
		if current_active_menu.has_signal("open_journey_menu_requested"):
			current_active_menu.open_journey_menu_requested.connect(open_convoy_journey_menu, CONNECT_ONE_SHOT)
		if current_active_menu.has_signal("open_settlement_menu_requested"):
			print("MenuManager: Attempting to connect 'open_settlement_menu_requested'...")
			current_active_menu.open_settlement_menu_requested.connect(open_convoy_settlement_menu, CONNECT_ONE_SHOT)
		else:
			printerr("MenuManager: FAILED to connect. ConvoyMenu is missing the 'open_settlement_menu_requested' signal declaration.")
		if current_active_menu.has_signal("open_cargo_menu_requested"):
			current_active_menu.open_cargo_menu_requested.connect(open_convoy_cargo_menu, CONNECT_ONE_SHOT)
	elif menu_type == "convoy_vehicle_submenu":
		if current_active_menu.has_signal("inspect_all_convoy_cargo_requested"):
			current_active_menu.inspect_all_convoy_cargo_requested.connect(open_convoy_cargo_menu, CONNECT_ONE_SHOT)
		if current_active_menu.has_signal("return_to_convoy_overview_requested"):
			current_active_menu.return_to_convoy_overview_requested.connect(open_convoy_menu, CONNECT_ONE_SHOT)
		# Optional: if vehicle menu exposes "open_mechanics_menu_requested", connect it
		if current_active_menu.has_signal("open_mechanics_menu_requested"):
			current_active_menu.open_mechanics_menu_requested.connect(open_mechanics_menu, CONNECT_ONE_SHOT)
	elif menu_type == "convoy_journey_submenu":
		if current_active_menu.has_signal("return_to_convoy_overview_requested"):
			current_active_menu.return_to_convoy_overview_requested.connect(open_convoy_menu, CONNECT_ONE_SHOT)
	elif menu_type == "convoy_cargo_submenu":
		if current_active_menu.has_signal("return_to_convoy_overview_requested"):
			current_active_menu.return_to_convoy_overview_requested.connect(open_convoy_menu, CONNECT_ONE_SHOT)
	elif menu_type == "convoy_settlement_submenu":
		# Hook from settlement menu mechanics tab
		if current_active_menu.has_signal("open_mechanics_menu_requested"):
			current_active_menu.open_mechanics_menu_requested.connect(open_mechanics_menu, CONNECT_ONE_SHOT)
		# Also forward Warehouse open requests
		if current_active_menu.has_signal("open_warehouse_menu_requested"):
			current_active_menu.open_warehouse_menu_requested.connect(open_warehouse_menu, CONNECT_ONE_SHOT)


func go_back():
	if not is_instance_valid(current_active_menu):
		if not menu_stack.is_empty():
			var _previous_menu_info = menu_stack.pop_back()
			var _prev_scene_path = _previous_menu_info.get("scene_path")
			var _prev_data = _previous_menu_info.get("data")
			if _prev_scene_path:
				var _scene_resource = load(_prev_scene_path)
				if _scene_resource:
					_show_menu(_scene_resource, _prev_data, false)
					return
		# No previous menu to go back to; fully closing menus.
		# Deselect any globally selected convoy so the user isn't forced to click again to clear it.
		var gdm_none = get_node_or_null("/root/GameDataManager")
		if is_instance_valid(gdm_none) and gdm_none.has_method("select_convoy_by_id"):
			gdm_none.select_convoy_by_id("", false)
		emit_signal("menu_visibility_changed", false, "")
		visible = false
		return


	if menu_stack.is_empty():
		var _closed_menu_type = current_active_menu.get_meta("menu_type", "default")
		emit_signal("menu_closed", current_active_menu, _closed_menu_type)
		current_active_menu.queue_free()
		current_active_menu = null
		mouse_filter = MOUSE_FILTER_IGNORE
		self.z_index = _base_z_index
		# We're closing the last open menu. Clear convoy selection to remove the highlight in the convoy list.
		var gdm = get_node_or_null("/root/GameDataManager")
		if is_instance_valid(gdm) and gdm.has_method("select_convoy_by_id"):
			gdm.select_convoy_by_id("", false)
		emit_signal("menu_visibility_changed", false, "")
		visible = false
		return

	var _closed_menu_type2 = current_active_menu.get_meta("menu_type", "default")
	emit_signal("menu_closed", current_active_menu, _closed_menu_type2)
	current_active_menu.queue_free()
	current_active_menu = null
	var _previous_menu_info2 = menu_stack.pop_back()
	var _prev_scene_path2 = _previous_menu_info2.get("scene_path")
	var _prev_data2 = _previous_menu_info2.get("data")
	# Replace with freshest convoy data if available
	if _prev_data2 is Dictionary and _prev_data2.has("convoy_id"):
		var gdm2 = get_node_or_null("/root/GameDataManager")
		if is_instance_valid(gdm2) and gdm2.has_method("get_convoy_by_id"):
			var latest = gdm2.get_convoy_by_id(str(_prev_data2.get("convoy_id")))
			if latest is Dictionary and not latest.is_empty():
				_prev_data2 = latest.duplicate(true)
	if _prev_scene_path2:
		var _scene_resource2 = load(_prev_scene_path2)
		if _scene_resource2:
			_show_menu(_scene_resource2, _prev_data2, false)
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
			var gdm = get_node_or_null("/root/GameDataManager")
			if is_instance_valid(gdm) and gdm.has_method("select_convoy_by_id"):
				gdm.select_convoy_by_id("", false)
			emit_signal("menu_visibility_changed", false, "")
		return

	menu_stack.clear() # Prevent go_back from reopening anything
	go_back() # Call go_back to handle closing the current_active_menu and emitting signals
	# go_back will eventually emit menus_completely_closed if the stack is now empty
	# and it closes the last menu.


# Handler to update the currently active menu if convoy data changes
func _on_gdm_convoy_data_updated(all_convoy_data: Array) -> void:
	if not is_instance_valid(current_active_menu):
		return
	if current_active_menu.has_method("initialize_with_data"):
		var menu_data = current_active_menu.get_meta("menu_data", null)
		if menu_data and menu_data.has("convoy_id"):
			var current_id = str(menu_data.get("convoy_id"))
			for convoy in all_convoy_data:
				if convoy.has("convoy_id") and str(convoy.get("convoy_id")) == current_id:
					current_active_menu.call_deferred("initialize_with_data", convoy.duplicate(true))
					current_active_menu.set_meta("menu_data", convoy.duplicate(true))
					break
	# Also update any stacked menu data snapshots so Back restores fresh data
	if not menu_stack.is_empty():
		for i in range(menu_stack.size()):
			var entry = menu_stack[i]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var data_snap = entry.get("data", null)
			if data_snap is Dictionary and data_snap.has("convoy_id"):
				var cid = str(data_snap.get("convoy_id"))
				for convoy2 in all_convoy_data:
					if convoy2.has("convoy_id") and str(convoy2.get("convoy_id")) == cid:
						entry["data"] = convoy2.duplicate(true)
						menu_stack[i] = entry
						break
