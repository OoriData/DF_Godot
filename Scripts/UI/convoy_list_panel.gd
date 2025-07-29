extends VBoxContainer


@onready var toggle_button: Button = $ToggleButton
@onready var convoy_popup: PopupPanel = %ConvoyPopup
@onready var list_item_container: VBoxContainer = %ConvoyItemsContainer

# Add a reference to GameDataManager
var gdm: Node = null

func _ready():
	# Diagnostic: Print ToggleButton's global position, size, and rect
	if has_node("ToggleButton"):
		var diag_toggle_button = $ToggleButton
		print("ConvoyListPanel: ToggleButton FOUND. global_position=", diag_toggle_button.global_position, ", size=", diag_toggle_button.size, ", rect_global=", diag_toggle_button.get_global_rect())
	else:
		print("ConvoyListPanel: ToggleButton NOT FOUND in ConvoyListPanel!")
	# Diagnostic: Print all direct children of ConvoyListPanel, their types, and mouse_filter
	print("ConvoyListPanel: Child diagnostic for self (", name, "):")
	for child in get_children():
		if child is Control:
			print("  Child '", child.name, "' (", child.get_class(), ") mouse_filter=", child.mouse_filter, " visible=", child.visible)
		else:
			print("  Child '", child.name, "' (", child.get_class(), ") [not Control]")
	# Set mouse_filter=IGNORE on non-interactive siblings in TopBar
	var topbar_parent = get_parent()
	if topbar_parent:
		for sibling in topbar_parent.get_children():
			if sibling != self and sibling is Control:
				if sibling.get_class() in ["VSeparator", "Control"]:
					sibling.mouse_filter = Control.MOUSE_FILTER_IGNORE
					print("ConvoyListPanel: Set mouse_filter=IGNORE on sibling '", sibling.name, "' (", sibling.get_class(), ")")
	# Diagnostic: Print all siblings in parent (TopBar), their types, and mouse_filter
	var parent = get_parent()
	if parent:
		print("ConvoyListPanel: Sibling diagnostic for parent node '", parent.name, "' (", parent.get_class(), "):")
		for sibling in parent.get_children():
			if sibling is Control:
				print("  Sibling '", sibling.name, "' (", sibling.get_class(), ") mouse_filter=", sibling.mouse_filter, " visible=", sibling.visible)
			else:
				print("  Sibling '", sibling.name, "' (", sibling.get_class(), ") [not Control]")

	# Set mouse_filter to STOP so this panel receives input
	mouse_filter = Control.MOUSE_FILTER_STOP
	print("ConvoyListPanel: Set mouse_filter=STOP on self (should now receive input)")

	# Diagnostic: Print mouse_filter for all parents up to root
	var node = self
	var depth = 0
	while node:
		if node is Control:
			print("ConvoyListPanel: Parent at depth ", depth, ": ", node.name, " (", node.get_class(), ") mouse_filter=", node.mouse_filter)
		node = node.get_parent()
		depth += 1
	set_process_input(true)
func _input(event):
	if event is InputEventMouseButton and event.pressed:
		print("ConvoyListPanel: _input() received mouse event: ", event)
	# Set mouse filter to STOP so this panel receives mouse input (for dropdowns/buttons)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# More robust node checks.
	if not is_instance_valid(toggle_button) or not is_instance_valid(convoy_popup) or not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel: One or more required child nodes are missing. Check scene setup.")
		return


	toggle_button.pressed.connect(_on_toggle_button_pressed)
	toggle_button.pressed.connect(func(): print("ConvoyListPanel: ToggleButton pressed!")) # DIAGNOSTIC
	# The popup hides itself when focus is lost. We connect to its signal to update our button.
	convoy_popup.popup_hide.connect(_on_popup_hide)

	# Attempt to connect to MenuManager's signal to auto-close this panel.
	# Since this panel is now nested, the path to MenuManager has changed.
	# Using an absolute path is more robust when nodes are in different branches of the main scene tree.
	var absolute_menu_manager_path = "/root/GameRoot/MenuUILayer/MenuManager"
	var menu_manager_node = get_node_or_null(absolute_menu_manager_path)
	if is_instance_valid(menu_manager_node):
		if menu_manager_node.has_signal("menu_opened"):
			menu_manager_node.menu_opened.connect(_on_main_menu_opened)
			# ...existing code...
		else:
			printerr("ConvoyListPanel: MenuManager found but does not have 'menu_opened' signal.")
	else:
		# The warning message is updated to reflect the new expected structure.
		printerr("ConvoyListPanel: MenuManager node not found. Cannot auto-close on menu open. Expected path: %s" % absolute_menu_manager_path)

	# Add this block to connect to GameDataManager's convoy_data_updated signal
	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("convoy_data_updated", Callable(self, "_on_convoy_data_updated")):
			gdm.convoy_data_updated.connect(Callable(self, "_on_convoy_data_updated"))
		# NEW: Connect to a signal that fires when the selected convoy changes.
		# This allows the dropdown to update itself from anywhere in the game.
		if gdm.has_signal("convoy_selection_changed"):
			if not gdm.is_connected("convoy_selection_changed", Callable(self, "_on_convoy_selection_changed")):
				gdm.convoy_selection_changed.connect(Callable(self, "_on_convoy_selection_changed"))
		else:
			printerr("ConvoyListPanel: GameDataManager is missing 'convoy_selection_changed' signal.")

		# Immediately populate with current data from GameDataManager if it's already loaded.
		if gdm.has_method("get_all_convoys"):
			var convoys = gdm.get_all_convoys()
			if not convoys.is_empty():
				populate_convoy_list(convoys)
		if gdm.has_method("get_selected_convoy"):
			var selected = gdm.get_selected_convoy()
			_on_convoy_selection_changed(selected)
	else:
		printerr("ConvoyListPanel: GameDataManager not found in scene tree.")

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

		var convoy_id = convoy_item_data.get("convoy_id", "N/A")
		var convoy_name = convoy_item_data.get("convoy_name", "Unknown Convoy")
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

	# Instead of emitting a local signal, tell the central state manager what was selected.
	if is_instance_valid(gdm) and gdm.has_method("select_convoy_by_id"):
		gdm.select_convoy_by_id(str(convoy_item_data.get("convoy_id", "")))

	# Close the list after an item is selected
	close_list()

# Add this handler to update the list when convoy data changes
func _on_convoy_data_updated(all_convoy_data: Array) -> void:
	populate_convoy_list(all_convoy_data)
	# After repopulating, ensure the selection highlight and button text are correct.
	if is_instance_valid(gdm) and gdm.has_method("get_selected_convoy"):
		var selected = gdm.get_selected_convoy()
		_on_convoy_selection_changed(selected)


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
