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


var current_active_menu = null
var menu_stack = [] # To keep track of the navigation path for "back" functionality

var _base_z_index: int
# Ensure this Z-index is higher than ConvoyListPanel's EXPANDED_OVERLAY_Z_INDEX (100)
const MENU_MANAGER_ACTIVE_Z_INDEX = 150 

## Emitted when any menu is opened. Passes the menu node instance.
signal menu_opened(menu_node, menu_type: String)
## Emitted when a menu is closed (either by navigating forward or back). Passes the menu node that was closed.
signal menu_closed(menu_node_was_active, menu_type: String)
## Emitted when the last menu in the stack is closed via "back", meaning no menus are active.
signal menus_completely_closed



func _ready():
	# Initially, no menu is shown. Hide MenuManager so it does not block input.
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE
	_base_z_index = self.z_index # Store initial z_index
	# Example: open_main_menu()
	pass

func _unhandled_input(event: InputEvent):
	# Global back button (e.g., Escape key)
	if event.is_action_pressed("ui_cancel") and is_instance_valid(current_active_menu):
		go_back()
		get_viewport().set_input_as_handled()

func is_any_menu_active() -> bool:
	return current_active_menu != null

# --- Functions to open specific Convoy Menus ---
func open_convoy_menu(convoy_data = null):
	# This opens the main Convoy Overview menu
	_show_menu(convoy_menu_scene, convoy_data)

func open_convoy_vehicle_menu(convoy_data = null):
	print("MenuManager: open_convoy_vehicle_menu called. Convoy Data Received: ")
	print(convoy_data) # This will print the full dictionary to the console
	_show_menu(convoy_vehicle_menu_scene, convoy_data)

func open_convoy_journey_menu(convoy_data = null):
	_show_menu(convoy_journey_menu_scene, convoy_data)

func open_convoy_settlement_menu(convoy_data = null):
	print("MenuManager: open_convoy_settlement_menu called. Data is valid: ", convoy_data != null)
	_show_menu(convoy_settlement_menu_scene, convoy_data)

func open_convoy_cargo_menu(convoy_data = null):
	if convoy_data == null:
		printerr("MenuManager: open_convoy_cargo_menu called with null data.")
		# Pass a structure that ConvoyCargoMenu can handle gracefully if data is missing
		_show_menu(convoy_cargo_menu_scene, {"vehicle_details_list": [], "convoy_name": "Unknown Convoy"})
		return

	print("MenuManager: open_convoy_cargo_menu called. Original Convoy Data Keys: ", convoy_data.keys())
	# Pass the convoy_data directly. ConvoyCargoMenu will now handle iterating through vehicles.
	_show_menu(convoy_cargo_menu_scene, convoy_data.duplicate(true)) # Pass a copy

# --- Generic menu handling ---

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
			emit_signal("menus_completely_closed")
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
	add_child(current_active_menu)
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

	# A menu is now active. Allow this manager to receive clicks on its background
	mouse_filter = MOUSE_FILTER_PASS
	self.z_index = MENU_MANAGER_ACTIVE_Z_INDEX
	emit_signal("menu_opened", current_active_menu, menu_type)

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
	elif menu_type == "convoy_journey_submenu":
		if current_active_menu.has_signal("return_to_convoy_overview_requested"):
			current_active_menu.return_to_convoy_overview_requested.connect(open_convoy_menu, CONNECT_ONE_SHOT)
	elif menu_type == "convoy_cargo_submenu":
		if current_active_menu.has_signal("return_to_convoy_overview_requested"):
			current_active_menu.return_to_convoy_overview_requested.connect(open_convoy_menu, CONNECT_ONE_SHOT)


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
		# If no menu was restored from stack and current_active_menu was already null
		emit_signal("menus_completely_closed")
		# Hide MenuManager when no menus are active
		visible = false
		return

	if menu_stack.is_empty():
		var _closed_menu_type = current_active_menu.get_meta("menu_type", "default")
		emit_signal("menu_closed", current_active_menu, _closed_menu_type)
		current_active_menu.queue_free()
		current_active_menu = null
		mouse_filter = MOUSE_FILTER_IGNORE
		self.z_index = _base_z_index
		emit_signal("menus_completely_closed")
		# Hide MenuManager when no menus are active
		visible = false
		return

	var _closed_menu_type2 = current_active_menu.get_meta("menu_type", "default")
	emit_signal("menu_closed", current_active_menu, _closed_menu_type2)
	current_active_menu.queue_free()
	current_active_menu = null
	var _previous_menu_info2 = menu_stack.pop_back()
	var _prev_scene_path2 = _previous_menu_info2.get("scene_path")
	var _prev_data2 = _previous_menu_info2.get("data")
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
			emit_signal("menus_completely_closed")
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
