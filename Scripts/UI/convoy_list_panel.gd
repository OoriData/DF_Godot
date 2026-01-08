extends VBoxContainer


@onready var toggle_button: Button = $ToggleButton
@onready var convoy_popup: PopupPanel = %ConvoyPopup
@onready var list_item_container: VBoxContainer = %ConvoyItemsContainer

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")

func _ready():
	# More robust node checks.
	if not is_instance_valid(toggle_button) or not is_instance_valid(convoy_popup) or not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel: One or more required child nodes are missing. Check scene setup.")
		return

	# Set mouse filter to STOP so this panel receives mouse input (for dropdowns/buttons)
	mouse_filter = Control.MOUSE_FILTER_STOP

	toggle_button.pressed.connect(_on_toggle_button_pressed)
	# The popup hides itself when focus is lost. We connect to its signal to update our button.
	convoy_popup.popup_hide.connect(_on_popup_hide)

	# Attempt to connect to MenuManager's signal to auto-close this panel.
	# Since MenuManager is an Autoload, it's globally available.
	var menu_manager_node = get_node_or_null("/root/MenuManager")
	if is_instance_valid(menu_manager_node):
		if menu_manager_node.has_signal("menu_opened"):
			menu_manager_node.menu_opened.connect(_on_main_menu_opened)
		else:
			printerr("ConvoyListPanel: MenuManager found but does not have 'menu_opened' signal.")
	else:
		# The warning message is updated to reflect the new expected structure.
		printerr("ConvoyListPanel: MenuManager Autoload node not found. Cannot auto-close on menu open. Check Project Settings -> Autoload.")

	# Subscribe to canonical snapshots + selection bus
	if is_instance_valid(_store) and _store.has_signal("convoys_changed"):
		if not _store.convoys_changed.is_connected(_on_convoy_data_updated):
			_store.convoys_changed.connect(_on_convoy_data_updated)
		if _store.has_method("get_convoys"):
			var convoys_now: Array = _store.get_convoys()
			if not convoys_now.is_empty():
				populate_convoy_list(convoys_now)

	if is_instance_valid(_hub) and _hub.has_signal("convoy_selection_changed"):
		if not _hub.convoy_selection_changed.is_connected(_on_convoy_selection_changed):
			_hub.convoy_selection_changed.connect(_on_convoy_selection_changed)

func _on_toggle_button_pressed() -> void:
	# DIAGNOSTIC: Print a message to see if this function is ever called.

	if not is_instance_valid(convoy_popup) or not is_instance_valid(toggle_button):
		printerr("ConvoyListPanel: Critical nodes missing in _on_toggle_button_pressed.")
		return

	if convoy_popup.is_visible():
		convoy_popup.hide()
	else:
		var item_count = max(1, list_item_container.get_child_count()) # Avoid 0
		var popup_height = clamp(item_count * 30 + 10, 50, 300) # e.g., 30px per item + padding
		convoy_popup.size = Vector2(toggle_button.size.x, popup_height)


		# Use popup(Rect2i) for robust positioning in Godot 4.
		# This positions the popup relative to the viewport, using global coordinates.
		var button_rect = toggle_button.get_global_rect()
		# Position the popup to start at the bottom-left of the button.
		var popup_position = Vector2(button_rect.position.x, button_rect.end.y)
		convoy_popup.popup(Rect2i(popup_position, convoy_popup.size))

		# Update button text to show it's open
		if toggle_button.text.ends_with("▼"):
			toggle_button.text = toggle_button.text.replace("▼", "▲")

func _on_popup_hide() -> void:
	"""Called when the PopupPanel is hidden for any reason (selection, clicked away)."""

	# Update button text to show it's closed
	if toggle_button.text.ends_with("▲"):
		toggle_button.text = toggle_button.text.replace("▲", "▼")

func close_list():
	"""Closes the convoy list if it's open."""
	if convoy_popup.is_visible():
		convoy_popup.hide()

func _on_main_menu_opened(_menu_node, _menu_type: String):
	# If a menu from MenuManager opens, and our panel is currently expanded, close it.
	if convoy_popup.is_visible():
		close_list()

## Populates the list with convoy data.
func populate_convoy_list(convoys_data: Array) -> void:
	var logger := get_node_or_null("/root/Logger")
	if is_instance_valid(logger) and logger.has_method("info"):
		logger.info("ConvoyListPanel.populate count=%s visible=%s", convoys_data.size(), visible)
	else:
		print("ConvoyListPanel: populate_convoy_list() called. Visible:", visible, "Parent:", get_parent())

	# Diagnostic: Print node tree under ConvoyItemsContainer to help debug UI population issues
	if is_instance_valid(list_item_container):
		print("ConvoyListPanel: ConvoyItemsContainer children:")
		for child in list_item_container.get_children():
			print("  -", child.name, "type:", child.get_class())
	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel: populate_convoy_list - list_item_container node not found or invalid. Check unique name in scene.")
		return

	# Clear existing items
	for child in list_item_container.get_children():
		child.queue_free()

	if convoys_data.is_empty():
		var no_convoys_label = Label.new()
		no_convoys_label.text = "No convoys available."
		no_convoys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list_item_container.add_child(no_convoys_label)
		return

	for convoy_item_data in convoys_data:
		if not convoy_item_data is Dictionary:
			printerr("ConvoyListPanel: Invalid convoy data item: ", convoy_item_data)
			continue

		var convoy_id = convoy_item_data.get("convoy_id", convoy_item_data.get("id", "N/A"))
		var convoy_name = convoy_item_data.get("convoy_name", convoy_item_data.get("name", "Unknown Convoy"))
		var item_button = Button.new()
		item_button.text = "%s" % [convoy_name]
		item_button.name = "ConvoyButton_%s" % str(convoy_id) # Useful for identification
		# Connect the button's pressed signal to a local handler, binding the full convoy_item_data
		item_button.pressed.connect(_on_convoy_item_pressed.bind(convoy_item_data))
		list_item_container.add_child(item_button)

func _on_convoy_item_pressed(convoy_item_data: Dictionary) -> void:
	if not is_instance_valid(convoy_popup) or not is_instance_valid(toggle_button):
		printerr("ConvoyListPanel: Critical nodes missing in _on_convoy_item_pressed.")
		return

	# Tell the canonical selection bus about the intent.
	if is_instance_valid(_hub) and _hub.has_signal("convoy_selection_requested"):
		_hub.convoy_selection_requested.emit(str(convoy_item_data.get("convoy_id", "")), false)

	# Close the list after an item is selected
	close_list()

# Add this handler to update the list when convoy data changes
func _on_convoy_data_updated(all_convoy_data: Array) -> void:
	populate_convoy_list(all_convoy_data)
	# Selection highlight updates on convoy_selection_changed.


# NEW: Handles updates when the globally selected convoy changes.
func _on_convoy_selection_changed(selected_convoy_data: Variant) -> void:
	var convoy_id_str: String = ""
	if selected_convoy_data and selected_convoy_data.has("convoy_id"):
		var convoy_name = selected_convoy_data.get("convoy_name", "Unnamed Convoy")
		convoy_id_str = str(selected_convoy_data.get("convoy_id"))
		# Update the main button text to show the selected convoy
		toggle_button.text = "%s ▼" % convoy_name
	else:
		# No convoy is selected, or data is invalid
		toggle_button.text = "Select Convoy ▼"

	# Highlight the corresponding item in the list
	highlight_convoy_in_list(convoy_id_str)

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
