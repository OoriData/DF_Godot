extends Control

# Preload your actual menu scene files here once you create them
var convoy_menu_scene = preload("res://Menus/ConvoyMenu.tscn") # Adjusted path if needed
# var settings_menu_scene = preload("res://menus/SettingsMenu.tscn") # Example for later

var current_active_menu = null
var menu_stack = [] # To keep track of the navigation path for "back" functionality

## Emitted when any menu is opened. Passes the menu node instance.
signal menu_opened(menu_node)
## Emitted when a menu is closed (either by navigating forward or back). Passes the menu node that was closed.
signal menu_closed(menu_node_was_active)
## Emitted when the last menu in the stack is closed via "back", meaning no menus are active.
signal menus_completely_closed

func _ready():
	# Initially, no menu is shown. You might want to open a main menu here.
	# Example: open_main_menu()
	pass

func _unhandled_input(event: InputEvent):
	# Global back button (e.g., Escape key)
	if event.is_action_pressed("ui_cancel") and is_instance_valid(current_active_menu):
		go_back()
		get_viewport().set_input_as_handled()

func is_any_menu_active() -> bool:
	return current_active_menu != null

# --- Function to open the Convoy Menu ---
func open_convoy_menu(convoy_data = null):
	print("MenuManager: Opening actual ConvoyMenu for data: ", convoy_data)
	_show_menu(convoy_menu_scene, convoy_data)

# --- Generic menu handling ---
func _show_menu(menu_scene_resource, data_to_pass = null, add_to_stack: bool = true):
	if current_active_menu:
		if add_to_stack:
			menu_stack.append({
				"scene_path": current_active_menu.scene_file_path, # Store path to reinstantiate
				"data": current_active_menu.get_meta("menu_data", null) # Optional: if menus store their context
			})
		emit_signal("menu_closed", current_active_menu)
		current_active_menu.queue_free() # Remove the old menu
		current_active_menu = null

	current_active_menu = menu_scene_resource.instantiate()
	
	if not is_instance_valid(current_active_menu):
		printerr("MenuManager: Failed to instantiate menu scene: ", menu_scene_resource.resource_path if menu_scene_resource else "null resource")
		# Attempt to recover by going back if possible, or closing all menus.
		if not menu_stack.is_empty():
			go_back() # This will pop from stack and try to show the previous.
		else:
			emit_signal("menus_completely_closed")
		return

	add_child(current_active_menu)
	# Ensure the new menu is sized to fill its parent (MenuManager, which should be a Control node filling the screen)
	if current_active_menu is Control:
		current_active_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
	emit_signal("menu_opened", current_active_menu)

	# Pass data to the new menu if it has an initializer function
	if current_active_menu.has_method("initialize_with_data"):
		current_active_menu.initialize_with_data(data_to_pass)
	if data_to_pass: # Optional: store context for "back"
		current_active_menu.set_meta("menu_data", data_to_pass)

	# Connect signals from the newly instantiated menu
	# Example: if your menus emit "back_requested" or "open_specific_menu_requested(data)"
	if current_active_menu.has_signal("back_requested"):
		# Using CONNECT_ONE_SHOT because the menu instance will be freed when closed.
		# If not using ONE_SHOT, ensure to disconnect when the menu is about to be freed.
		var err = current_active_menu.back_requested.connect(go_back, CONNECT_ONE_SHOT)
		if err == OK:
			print("MenuManager: Successfully connected 'back_requested' signal from new menu to go_back().")
		else:
			printerr("MenuManager: FAILED to connect 'back_requested' signal. Error code: ", err)
	else:
		print("MenuManager: New menu instance does NOT have 'back_requested' signal.")

func go_back():
	print("MenuManager: go_back() called. Current active menu: ", current_active_menu) # DEBUG
	if not is_instance_valid(current_active_menu):
		# This case might happen if ui_cancel is pressed rapidly or if a menu failed to open.
		# If no menu is active, but stack isn't empty, try to restore from stack.
		if not menu_stack.is_empty():
			var previous_menu_info = menu_stack.pop_back()
			var prev_scene_path = previous_menu_info.get("scene_path")
			var prev_data = previous_menu_info.get("data")
			if prev_scene_path:
				var scene_resource = load(prev_scene_path)
				if scene_resource:
					_show_menu(scene_resource, prev_data, false)
					return # Successfully restored a menu
		print("MenuManager: go_back() - No valid current menu and stack recovery failed or stack empty.") # DEBUG
		# If still no active menu or stack was empty, ensure menus are considered closed.
		emit_signal("menus_completely_closed")
		return

	# Current menu is valid, proceed to close it and go back.
	if menu_stack.is_empty(): # No previous menu in stack, closing the current (last) one
		emit_signal("menu_closed", current_active_menu)
		print("MenuManager: go_back() - Closing last menu. Emitting 'menus_completely_closed'.") # DEBUG
		current_active_menu.queue_free()
		current_active_menu = null
		emit_signal("menus_completely_closed") # All menus are now closed
		return

	# There's a previous menu in the stack. Close current and open previous.
	print("MenuManager: go_back() - Closing current menu and opening previous from stack.") # DEBUG
	emit_signal("menu_closed", current_active_menu)
	current_active_menu.queue_free()
	current_active_menu = null
	
	var previous_menu_info = menu_stack.pop_back()
	var prev_scene_path = previous_menu_info.get("scene_path")
	var prev_data = previous_menu_info.get("data")

	if prev_scene_path:
		var scene_resource = load(prev_scene_path)
		if scene_resource:
			_show_menu(scene_resource, prev_data, false) # false: don't add to stack again
		else:
			printerr("MenuManager: Failed to load previous menu scene: ", prev_scene_path, ". Attempting to go back further if possible.")
			go_back() # Try to go back again, as the loaded scene was invalid.
	else:
		printerr("MenuManager: Previous menu info in stack did not have a scene_path. Attempting to go back further.")
		go_back() # Stack entry was invalid, try to pop next.

func request_convoy_menu(convoy_data): # This is the public API called by main.gd
	open_convoy_menu(convoy_data)
