extends Control

signal back_requested

var convoy_data_received: Dictionary

@onready var title_label: Label = $MainVBox/TitleLabel
@onready var cargo_items_vbox: VBoxContainer = $MainVBox/ScrollContainer/CargoItemsVBox
@onready var back_button: Button = $MainVBox/BackButton

func _ready():
	if is_instance_valid(back_button):
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed, CONNECT_ONE_SHOT)
	else:
		printerr("ConvoyCargoMenu: BackButton node not found. Ensure it's named 'BackButton' in the scene.")

func initialize_with_data(data: Dictionary):
	convoy_data_received = data.duplicate() # Duplicate to avoid modifying the original
	# print("ConvoyCargoMenu: Initialized with data: ", convoy_data_received) # DEBUG

	if is_instance_valid(title_label) and convoy_data_received.has("convoy_name"):
		title_label.text = "%s - Cargo Hold" % convoy_data_received.get("convoy_name", "Unknown Convoy")
	elif is_instance_valid(title_label):
		title_label.text = "Cargo Hold"
	
	_populate_cargo_list()

func _populate_cargo_list():
	if not is_instance_valid(cargo_items_vbox):
		printerr("ConvoyCargoMenu: CargoItemsVBox node not found.")
		return

	# Clear any previous items from the list
	for child in cargo_items_vbox.get_children():
		child.queue_free()

	var all_cargo_list: Array = convoy_data_received.get("all_cargo", [])
	
	if all_cargo_list.is_empty():
		var no_cargo_label = Label.new()
		no_cargo_label.text = "This convoy is carrying no cargo."
		no_cargo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cargo_items_vbox.add_child(no_cargo_label)
		return

	# Aggregate cargo items by name to sum quantities (as seen in ConvoyMenu)
	var aggregated_cargo: Dictionary = {}
	for cargo_item_data in all_cargo_list:
		if cargo_item_data is Dictionary:
			var item_name: String = cargo_item_data.get("name", "Unknown Item")
			var item_quantity: int = cargo_item_data.get("quantity", 0)
			if item_quantity > 0: # Only add if quantity is positive
				aggregated_cargo[item_name] = aggregated_cargo.get(item_name, 0) + item_quantity
		else:
			printerr("ConvoyCargoMenu: Encountered non-dictionary item in all_cargo list: ", cargo_item_data)

	if aggregated_cargo.is_empty(): # Could happen if all quantities were 0 or items malformed
		var issue_label = Label.new()
		issue_label.text = "No displayable cargo items (check quantities)."
		issue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cargo_items_vbox.add_child(issue_label)
		return

	for item_name in aggregated_cargo:
		var quantity = aggregated_cargo[item_name]
		var item_label = Label.new()
		item_label.text = "%s x %s" % [item_name, quantity]
		item_label.set_h_size_flags(Control.SIZE_EXPAND_FILL) # Make label take full width
		cargo_items_vbox.add_child(item_label)

func _on_back_button_pressed():
	# print("ConvoyCargoMenu: Back button pressed. Emitting 'back_requested' signal.") # DEBUG
	emit_signal("back_requested")