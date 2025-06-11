extends PanelContainer

# Emitted when a convoy is selected from this list.
# Passes the full convoy_data dictionary of the selected convoy.
signal convoy_selected_from_list(convoy_data)

@onready var toggle_button: Button = $MainVBox/ToggleButton
@onready var list_scroll_container: ScrollContainer = $MainVBox/ListScrollContainer
@onready var list_item_container: VBoxContainer = $MainVBox/ListScrollContainer/ConvoyItemsContainer

var _panel_style_open: StyleBox
var _panel_style_closed: StyleBox

func _ready():
	# Store the stylebox that is defined for this panel when it's 'open'.
	# This will get an override if set in inspector, or the theme's default.
	_panel_style_open = get_theme_stylebox("panel", "PanelContainer")
	
	_panel_style_closed = StyleBoxEmpty.new() # Completely transparent, no drawing

	# Hide the list initially
	list_scroll_container.visible = false
	toggle_button.pressed.connect(_on_toggle_button_pressed)
	_update_panel_appearance() # Set initial appearance (closed style, no background)
	toggle_button.text = "Convoys ▼" # Initial text for closed state

	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel (_ready): list_item_container node NOT FOUND or invalid. Expected path: $MainVBox/ListScrollContainer/ConvoyItemsContainer")
	else:
		# print("ConvoyListPanel (_ready): list_item_container successfully initialized.") # Less verbose
		pass

func _on_toggle_button_pressed() -> void:
	list_scroll_container.visible = not list_scroll_container.visible
	_update_panel_appearance()

	if list_scroll_container.visible:
		toggle_button.text = "Convoys ▲"
	else:
		toggle_button.text = "Convoys ▼"

func _update_panel_appearance() -> void:
	if list_scroll_container.visible: # Open state - show background
		if is_instance_valid(_panel_style_open):
			add_theme_stylebox_override("panel", _panel_style_open)
	else: # Closed state - hide background
		if is_instance_valid(_panel_style_closed):
			add_theme_stylebox_override("panel", _panel_style_closed)

## Populates the list with convoy data.
func populate_convoy_list(convoys_data: Array) -> void:
	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel: populate_convoy_list - list_item_container node not found or invalid. Check path in script and ConvoyListPanel.tscn. Path used: $ConvoyItemsContainer")
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
	emit_signal("convoy_selected_from_list", convoy_item_data)
	# If the list is currently open, close it.
	if list_scroll_container.visible:
		list_scroll_container.visible = false
		_update_panel_appearance() # Update panel style to closed (no background)
		toggle_button.text = "Convoys ▼" # Update button text
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
