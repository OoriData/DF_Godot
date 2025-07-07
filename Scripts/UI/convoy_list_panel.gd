extends VBoxContainer

# Emitted when a convoy is selected from this list.
# Passes the full convoy_data dictionary of the selected convoy.
signal convoy_selected_from_list(convoy_data)

@onready var toggle_button: Button = $ToggleButton
@onready var list_scroll_container: ScrollContainer = %ListScrollContainer
@onready var list_item_container: VBoxContainer = %ConvoyItemsContainer

# Add a reference to GameDataManager
var gdm: Node = null

func _ready():
	# Critical node checks
	if not is_instance_valid(toggle_button):
		printerr("ConvoyListPanel (_ready): toggle_button node NOT FOUND.")
		return
	if not is_instance_valid(list_scroll_container):
		printerr("ConvoyListPanel (_ready): ListScrollContainer node NOT FOUND. Check unique name in scene.")
		return
	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel (_ready): ConvoyItemsContainer node NOT FOUND. Check unique name in scene.")
		return

	# Hide the list initially
	list_scroll_container.visible = false
	toggle_button.pressed.connect(_on_toggle_button_pressed)
	toggle_button.text = "Convoys ▼" # Initial text for closed state

	# Attempt to connect to MenuManager's signal to auto-close this panel
	var menu_manager_node = get_parent().get_node_or_null("MenuManager") # Assuming MenuManager is a sibling
	if is_instance_valid(menu_manager_node):
		if menu_manager_node.has_signal("menu_opened"):
			menu_manager_node.menu_opened.connect(_on_main_menu_opened)
			# print("ConvoyListPanel: Successfully connected to MenuManager.menu_opened signal.") # DEBUG
		else:
			printerr("ConvoyListPanel: MenuManager found but does not have 'menu_opened' signal.")
	else:
		printerr("ConvoyListPanel: MenuManager node not found as sibling. Cannot auto-close on menu open. Expected path: ../MenuManager")

	# Add this block to connect to GameDataManager's convoy_data_updated signal
	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("convoy_data_updated", _on_convoy_data_updated):
			gdm.convoy_data_updated.connect(_on_convoy_data_updated)
		# Optionally, request a refresh if you want the list to populate on startup:
		# gdm.request_convoy_data_refresh()

	# Initial size update after setup
	call_deferred("update_minimum_size")
	

func _on_toggle_button_pressed() -> void:
	if not is_instance_valid(list_scroll_container) or not is_instance_valid(toggle_button):
		printerr("ConvoyListPanel: Critical nodes missing in _on_toggle_button_pressed.")
		return

	if list_scroll_container.visible: # It's currently open, so we are closing it
		close_list()
	else: # It's currently closed, so we are opening it
		open_list()

func open_list():
	"""Opens the convoy list."""
	if list_scroll_container.visible:
		return # Already open

	list_scroll_container.visible = true
	toggle_button.text = "Convoys ▲"
	call_deferred("update_minimum_size")

func close_list():
	"""Closes the convoy list if it's open."""
	if not list_scroll_container.visible:
		return # Already closed
	# print("ConvoyListPanel: close_list() called.") # DEBUG

	list_scroll_container.visible = false
	toggle_button.text = "Convoys ▼"
	call_deferred("update_minimum_size")

func _on_main_menu_opened(_menu_node, _menu_type: String):
	# If a menu from MenuManager opens, and our panel is currently expanded, close it.
	# This ensures MenuManager's menus take precedence.
	# print("ConvoyListPanel: _on_main_menu_opened received. List visible: ", list_scroll_container.visible) # DEBUG
	if list_scroll_container.visible:
		close_list()

## Populates the list with convoy data.
func populate_convoy_list(convoys_data: Array) -> void:
	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel: populate_convoy_list - list_item_container node not found or invalid. Check unique name in scene.")
		return

	# Clear existing items
	for child in list_item_container.get_children():
		child.queue_free()
	# print("ConvoyListPanel: Cleared existing items.") # DEBUG

	if convoys_data.is_empty():
		var no_convoys_label = Label.new()
		no_convoys_label.text = "No convoys available."
		no_convoys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list_item_container.add_child(no_convoys_label)
		# print("ConvoyListPanel: No convoys available.") # DEBUG
		return
	# print("ConvoyListPanel: Populating list with %s convoys." % convoys_data.size()) # DEBUG

	for convoy_item_data in convoys_data:
		if not convoy_item_data is Dictionary:
			printerr("ConvoyListPanel: Invalid convoy data item: ", convoy_item_data)
			continue

		var convoy_id = convoy_item_data.get("convoy_id", "N/A")
		var convoy_name = convoy_item_data.get("convoy_name", "Unknown Convoy")
		# You can add more details from convoy_item_data to the display string

		# Example: Create a Button for each convoy
		var item_button = Button.new()
		item_button.text = "%s" % [convoy_name]
		item_button.name = "ConvoyButton_%s" % str(convoy_id) # Useful for identification
		# Connect the button's pressed signal to a local handler, binding the full convoy_item_data
		item_button.pressed.connect(_on_convoy_item_pressed.bind(convoy_item_data))
		list_item_container.add_child(item_button)
		# print("ConvoyListPanel: Added button for convoy '%s' (ID: %s)." % [convoy_name, convoy_id]) # DEBUG

func _on_convoy_item_pressed(convoy_item_data: Dictionary) -> void:
	if not is_instance_valid(list_scroll_container) or not is_instance_valid(toggle_button):
		printerr("ConvoyListPanel: Critical nodes missing in _on_convoy_item_pressed.")
		return

	emit_signal("convoy_selected_from_list", convoy_item_data)
	# Close the list after an item is selected
	close_list()

# Add this handler to update the list when convoy data changes
func _on_convoy_data_updated(all_convoy_data: Array) -> void:
	populate_convoy_list(all_convoy_data)

## Highlights a specific convoy in the list.
## Call this from main.gd when a convoy is selected on the map.
func highlight_convoy_in_list(selected_convoy_id_str: String) -> void:
	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel: highlight_convoy_in_list - list_item_container node not found or invalid. Check unique name in scene.")
		return

	for child in list_item_container.get_children():
		if child is Button: # Or your custom item type
			# A more robust way is to check the name or metadata set during creation
			if child.name == "ConvoyButton_%s" % selected_convoy_id_str:
				child.modulate = Color.LIGHT_SKY_BLUE # Highlight color
			else:
				child.modulate = Color.WHITE # Reset others
