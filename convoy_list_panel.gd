extends ScrollContainer # Changed from PanelContainer to fulfill the role of a scroller

# Emitted when a convoy is selected from this list.
# Passes the full convoy_data dictionary of the selected convoy.
signal convoy_selected_from_list(convoy_data)

# Reference to the container node that will hold the individual convoy list items.
# IMPORTANT: Adjust this path to the actual VBoxContainer (or similar) in your convoy_list_panel.tscn
# The ConvoyItemsContainer is now expected to be a direct child of this ScrollContainer node.
@onready var list_item_container: VBoxContainer = $ConvoyItemsContainer

# Optional: If you use a separate scene for each list item
# var convoy_list_item_scene = preload("res://path/to_your/convoy_list_item.tscn")

func _ready():
	# --- TEMPORARY DEBUG: List children of the node this script is attached to ---
	print("ConvoyListPanel _ready: Script is attached to node: '", self.name, "' of type: '", self.get_class(), "'")
	print("  Children of this node are:")
	for child_node in get_children():
		print("    - Child name: '", child_node.name, "', type: '", child_node.get_class(), "'")
	# --- END TEMPORARY DEBUG ---
	# You can set the panel to be invisible initially if desired,
	# and control its visibility from main.gd or elsewhere.
	# self.visible = false # Example

	# --- Detailed Debug Check for list_item_container ---
	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel (_ready): list_item_container node (from @onready) NOT FOUND or invalid. Path used: $ConvoyItemsContainer")
		# Check if ConvoyItemsContainer exists as a direct child
		var direct_child_check = get_node_or_null("ConvoyItemsContainer")
		if not is_instance_valid(direct_child_check):
			printerr("  - ConvoyListPanel (_ready): Child 'ConvoyItemsContainer' NOT FOUND directly under this script's node (which should be a ScrollContainer).")
		elif not (direct_child_check is VBoxContainer):
			printerr("  - ConvoyListPanel (_ready): Child 'ConvoyItemsContainer' WAS FOUND, but it is of type '", direct_child_check.get_class(), "', NOT VBoxContainer as expected by the script.")
		else: # Found, but @onready failed.
			printerr("  - ConvoyListPanel (_ready): Path '$ConvoyItemsContainer' seems correct and node is VBoxContainer. The @onready var assignment failed for an unknown reason. Check for scene saving issues or editor glitches.")
	else:
		print("ConvoyListPanel (_ready): list_item_container successfully initialized via @onready.")

	# --- DEBUG: ConvoyListPanel final state check in its own _ready ---
	print("ConvoyListPanel _ready: Final state check:")
	print("  - IsValid: ", is_instance_valid(self))
	print("  - Visible: ", self.visible)
	print("  - Size: ", self.size)
	print("  - Custom Min Size: ", self.custom_minimum_size)
	print("  - Position: ", self.position)
	print("  - Modulate: ", self.modulate) # Check alpha
	print("  - Global Position: ", self.global_position)
	print("  - Z Index: ", self.z_index)
	# Parent checks are done in main.gd, but you could add them here too if needed.
	pass
## Populates the list with convoy data.
func populate_convoy_list(convoys_data: Array) -> void:
	if not is_instance_valid(list_item_container):
		printerr("ConvoyListPanel: populate_convoy_list - list_item_container node not found or invalid. Check path in script and ConvoyListPanel.tscn. Path used: $ConvoyItemsContainer")
		return

	# Clear existing items
	for child in list_item_container.get_children():
		child.queue_free()
	print("ConvoyListPanel: Cleared existing items from list_item_container.") # DEBUG

	if convoys_data.is_empty():
		var no_convoys_label = Label.new()
		no_convoys_label.text = "No convoys available."
		no_convoys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list_item_container.add_child(no_convoys_label)
		return
	print("ConvoyListPanel: Populating list with %s convoys." % convoys_data.size()) # DEBUG

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
		print("ConvoyListPanel: Added button for convoy '%s' (ID: %s). Button name: '%s'." % [convoy_name, convoy_id, item_button.name]) # DEBUG

	# --- DEBUG: Check state of list_item_container and children after population ---
	print("ConvoyListPanel: State check after population:")
	print("  - list_item_container IsValid: ", is_instance_valid(list_item_container))
	print("  - list_item_container Child Count: ", list_item_container.get_child_count())
	print("  - list_item_container Size: ", list_item_container.size) # Should reflect total size of children
	print("  - list_item_container Global Position: ", list_item_container.global_position)

func _on_convoy_item_pressed(convoy_item_data: Dictionary) -> void:
	print("ConvoyListPanel: Convoy item pressed, Data: ", convoy_item_data)
	emit_signal("convoy_selected_from_list", convoy_item_data)

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
