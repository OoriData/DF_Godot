extends PanelContainer # Or Control, VBoxContainer, etc., depending on your panel's root node

# Emitted when a convoy is selected from this list.
# Passes the full convoy_data dictionary of the selected convoy.
signal convoy_selected_from_list(convoy_data)

# Reference to the container node that will hold the individual convoy list items.
# IMPORTANT: Adjust this path to the actual VBoxContainer (or similar) in your convoy_list_panel.tscn
@onready var list_item_container: VBoxContainer = $ScrollContainer/ConvoyItemsContainer # Example path

# Optional: If you use a separate scene for each list item
# var convoy_list_item_scene = preload("res://path/to_your/convoy_list_item.tscn")

func _ready():
	# You can set the panel to be invisible initially if desired,
	# and control its visibility from main.gd or elsewhere.
	# self.visible = false
	pass

## Populates the list with convoy data.
func populate_convoy_list(convoys_data: Array) -> void:
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
		# You can add more details from convoy_item_data to the display string

		# Example: Create a Button for each convoy
		var item_button = Button.new()
		item_button.text = "%s" % [convoy_name]
		item_button.name = "ConvoyButton_%s" % str(convoy_id) # Useful for identification
		# Connect the button's pressed signal to a local handler, binding the full convoy_item_data
		item_button.pressed.connect(_on_convoy_item_pressed.bind(convoy_item_data))
		list_item_container.add_child(item_button)

func _on_convoy_item_pressed(convoy_item_data: Dictionary) -> void:
	print("ConvoyListPanel: Convoy item pressed, Data: ", convoy_item_data)
	emit_signal("convoy_selected_from_list", convoy_item_data)

## Highlights a specific convoy in the list.
## Call this from main.gd when a convoy is selected on the map.
func highlight_convoy_in_list(selected_convoy_id_str: String) -> void:
	for child in list_item_container.get_children():
		if child is Button: # Or your custom item type
			# A more robust way is to check the name or metadata set during creation
			if child.name == "ConvoyButton_%s" % selected_convoy_id_str:
				child.modulate = Color.LIGHT_SKY_BLUE # Highlight color
			else:
				child.modulate = Color.WHITE # Reset others
