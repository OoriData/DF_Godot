extends PanelContainer

# Emitted when a convoy is selected from this list.
# Passes the full convoy_data dictionary of the selected convoy.
signal convoy_selected_from_list(convoy_data)

@onready var toggle_button: Button = $MainVBox/ToggleButton
@onready var list_scroll_container: ScrollContainer = $MainVBox/ListScrollContainer
@onready var list_item_container: VBoxContainer = $MainVBox/ListScrollContainer/ConvoyItemsContainer
@onready var main_vbox: VBoxContainer = $MainVBox # Add @onready for MainVBox

# Z-index constants for managing draw order
# Default z-index is handled by _base_z_index when the panel is closed.
# Z-index when the list is open. This needs to be higher than MenuManager's MENU_MANAGER_ACTIVE_Z_INDEX (currently 150).
const EXPANDED_OVERLAY_Z_INDEX = 200

var _panel_style_open: StyleBox
var _panel_style_closed: StyleBox
# var _base_z_index: int # No longer needed as we'll maintain a high z-index

func _ready():
	# self.z_index is now consistently managed by _update_panel_appearance
	_panel_style_open = get_theme_stylebox("panel", "PanelContainer")
	_panel_style_closed = StyleBoxEmpty.new() # Completely transparent, no drawing

	# Critical node checks
	if not is_instance_valid(toggle_button):
		printerr("ConvoyListPanel (_ready): toggle_button node NOT FOUND.")
		return
	if not is_instance_valid(list_scroll_container):
		printerr("ConvoyListPanel (_ready): list_scroll_container node NOT FOUND.")
		return
	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel (_ready): list_item_container node NOT FOUND.")
		return
	if not is_instance_valid(main_vbox):
		printerr("ConvoyListPanel (_ready): main_vbox node NOT FOUND.")
		return

	# Hide the list initially
	list_scroll_container.visible = false
	toggle_button.pressed.connect(_on_toggle_button_pressed)
	_update_panel_appearance() # Set initial appearance (closed style, no background)
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

	# Initial size update after setup
	call_deferred("_update_layout_for_parents")
	

func _on_toggle_button_pressed() -> void:
	if not is_instance_valid(list_scroll_container) or \
	   not is_instance_valid(main_vbox) or \
	   not is_instance_valid(toggle_button):
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
	_update_panel_appearance()
	call_deferred("_update_layout_for_parents")

func close_list():
	"""Closes the convoy list if it's open."""
	if not list_scroll_container.visible:
		return # Already closed
	print("ConvoyListPanel: close_list() called.") # DEBUG

	list_scroll_container.visible = false
	toggle_button.text = "Convoys ▼"
	_update_panel_appearance()
	call_deferred("_update_layout_for_parents")

func _update_layout_for_parents():
	# Request layout update for parent containers
	if not is_instance_valid(main_vbox): return
	main_vbox.call_deferred("update_minimum_size")
	self.call_deferred("update_minimum_size")

func _on_main_menu_opened(_menu_node, _menu_type: String):
	# If a menu from MenuManager opens, and our panel is currently expanded, close it.
	# This ensures MenuManager's menus take precedence.
	print("ConvoyListPanel: _on_main_menu_opened received. List visible: ", list_scroll_container.visible) # DEBUG
	if list_scroll_container.visible:
		close_list()

func _update_panel_appearance() -> void:
	if not is_instance_valid(list_scroll_container) or not is_instance_valid(main_vbox): # Guard for both nodes
		printerr("ConvoyListPanel: _update_panel_appearance - Critical node (list_scroll_container or main_vbox) missing.")
		return

	if list_scroll_container.visible: # Open state - show background
		print("ConvoyListPanel: _update_panel_appearance() - Setting to OPEN state.") # DEBUG
		if is_instance_valid(_panel_style_open):
			z_index = EXPANDED_OVERLAY_Z_INDEX # Draw on top
			self.mouse_filter = MOUSE_FILTER_STOP # PanelContainer stops mouse events
			main_vbox.mouse_filter = MOUSE_FILTER_STOP # MainVBox also stops mouse events
			add_theme_stylebox_override("panel", _panel_style_open)
		else: # Fallback if style is somehow invalid
			print("ConvoyListPanel: _update_panel_appearance() - OPEN state, _panel_style_open INVALID.") # DEBUG
			z_index = EXPANDED_OVERLAY_Z_INDEX
			self.mouse_filter = MOUSE_FILTER_STOP
			main_vbox.mouse_filter = MOUSE_FILTER_STOP
			remove_theme_stylebox_override("panel") # Use default theme panel

	else: # Closed state - hide background, but keep Z-index high for the toggle button
		print("ConvoyListPanel: _update_panel_appearance() - Setting to CLOSED state.") # DEBUG
		if is_instance_valid(_panel_style_closed):
			z_index = EXPANDED_OVERLAY_Z_INDEX # Keep Z-index high to ensure toggle button is on top
			self.mouse_filter = MOUSE_FILTER_IGNORE # PanelContainer ignores mouse events
			main_vbox.mouse_filter = MOUSE_FILTER_IGNORE # MainVBox also ignores mouse events
			add_theme_stylebox_override("panel", _panel_style_closed)
		else: # Fallback if style is somehow invalid, still ensure proper Z and mouse filter
			z_index = EXPANDED_OVERLAY_Z_INDEX
			self.mouse_filter = MOUSE_FILTER_IGNORE
			main_vbox.mouse_filter = MOUSE_FILTER_IGNORE
			remove_theme_stylebox_override("panel")

## Populates the list with convoy data.
func populate_convoy_list(convoys_data: Array) -> void:
	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel: populate_convoy_list - list_item_container node not found or invalid. Check path in script and ConvoyListPanel.tscn. Path used: $MainVBox/ListScrollContainer/ConvoyItemsContainer")
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
	if not is_instance_valid(list_scroll_container) or \
	   not is_instance_valid(main_vbox) or \
	   not is_instance_valid(toggle_button):
		printerr("ConvoyListPanel: Critical nodes missing in _on_convoy_item_pressed.")
		return

	emit_signal("convoy_selected_from_list", convoy_item_data)
	# Close the list after an item is selected
	close_list()

## Highlights a specific convoy in the list.
## Call this from main.gd when a convoy is selected on the map.
func highlight_convoy_in_list(selected_convoy_id_str: String) -> void:
	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel: highlight_convoy_in_list - list_item_container node not found or invalid. Check path in script and ConvoyListPanel.tscn. Path used: $ConvoyItemsContainer")
		return

	for child in list_item_container.get_children():
		if child is Button: # Or your custom item type
			# A more robust way is to check the name or metadata set during creation
			if child.name == "ConvoyButton_%s" % selected_convoy_id_str:
				child.modulate = Color.LIGHT_SKY_BLUE # Highlight color
			else:
				child.modulate = Color.WHITE # Reset others
