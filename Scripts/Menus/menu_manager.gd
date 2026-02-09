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
var _next_menu_extra_arg = null # Temp storage for passing a second arg to initialize_with_data

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

func register_menu_container(container: Control):
	_menu_container_host = container
	print("[MenuManager] Successfully registered menu container: ", container.name)

func _ready():
	# Initially, no menu is shown. Hide MenuManager so it does not block input.
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE
	_base_z_index = self.z_index # Store initial z_index

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
	
	print("MenuManager Initialized: visible=", visible, ", mouse_filter=", mouse_filter)


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
	var arg = _extract_convoy_id_or_passthrough(convoy_data)
	_show_menu(warehouse_menu_scene, arg)

func open_convoy_cargo_menu(convoy_data = null):
	if convoy_data == null:
		printerr("MenuManager: open_convoy_cargo_menu called with null data.")
		_show_menu(convoy_cargo_menu_scene, {"vehicle_details_list": [], "convoy_name": "Unknown Convoy"})
		return

	print("MenuManager: open_convoy_cargo_menu called. Original Convoy Data Keys: ", convoy_data.keys())
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


### --- Generic menu handling ---
# _emit_menu_area_changed is only called from menu_manager.gd, never from menu scripts.

func _show_menu(menu_scene_resource, data_to_pass = null, add_to_stack: bool = true):
	# When showing a menu, make MenuManager visible so it can receive input.
	var was_visible := visible
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
		if _next_menu_extra_arg != null:
			current_active_menu.call_deferred("initialize_with_data", data_to_pass, _next_menu_extra_arg)
			_next_menu_extra_arg = null # Consume the argument
		else:
			current_active_menu.call_deferred("initialize_with_data", data_to_pass)

	if data_to_pass:
		current_active_menu.set_meta("menu_data", data_to_pass)

	if current_active_menu is Control:
		var menu_node_control = current_active_menu
		var top_margin = 0.0
		if is_instance_valid(user_info_display) and user_info_display.is_visible_in_tree():
			top_margin = user_info_display.size.y
		if use_convoy_style_layout:
			# Only emit visibility change on initial open, not during submenu switches.
			if not was_visible:
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
	# (Removed) Diagnostic overrides that broke menu input handling.
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
		# Deep-link: open settlement menu and focus a specific vendor/item
		if current_active_menu.has_signal("open_settlement_menu_with_focus_requested"):
			current_active_menu.open_settlement_menu_with_focus_requested.connect(open_convoy_settlement_menu_with_focus, CONNECT_ONE_SHOT)
		if current_active_menu.has_signal("open_cargo_menu_requested"):
			current_active_menu.open_cargo_menu_requested.connect(open_convoy_cargo_menu, CONNECT_ONE_SHOT)
		# Deep-link: open cargo menu and inspect a specific item (expects {cargo_id})
		if current_active_menu.has_signal("open_cargo_menu_inspect_requested"):
			current_active_menu.open_cargo_menu_inspect_requested.connect(open_convoy_cargo_menu_for_item, CONNECT_ONE_SHOT)
	elif menu_type == "convoy_vehicle_submenu":
		if current_active_menu.has_signal("inspect_all_convoy_cargo_requested"):
			current_active_menu.inspect_all_convoy_cargo_requested.connect(open_convoy_cargo_menu, CONNECT_ONE_SHOT)
		if current_active_menu.has_signal("inspect_specific_convoy_cargo_requested"):
			current_active_menu.inspect_specific_convoy_cargo_requested.connect(open_convoy_cargo_menu_for_item, CONNECT_ONE_SHOT)
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
		_request_clear_selection()
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
	# go_back will eventually emit menus_completely_closed if the stack is now empty
	# and it closes the last menu.



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
