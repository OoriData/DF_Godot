extends Control

signal back_requested

signal return_to_convoy_overview_requested(convoy_data)
var convoy_data_received: Dictionary

@onready var title_label: Label = $MainVBox/TitleLabel
@onready var cargo_items_vbox: VBoxContainer = $MainVBox/ScrollContainer/CargoItemsVBox
@onready var back_button: Button = $MainVBox/BackButton

func _ready():
	if is_instance_valid(back_button):
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed, CONNECT_ONE_SHOT)
	
	# Make the title label clickable to return to the convoy overview
	if is_instance_valid(title_label):
		title_label.mouse_filter = Control.MOUSE_FILTER_STOP # Allow it to receive mouse events
		title_label.gui_input.connect(_on_title_label_gui_input)
	else:
		printerr("ConvoyCargoMenu: BackButton node not found. Ensure it's named 'BackButton' in the scene.")

func initialize_with_data(data: Dictionary):
	# Ensure this function runs only after the node is fully ready and @onready vars are set.
	if not is_node_ready():
		printerr("ConvoyCargoMenu: initialize_with_data called BEFORE node is ready! Deferring.")
		call_deferred("initialize_with_data", data)
		return

	convoy_data_received = data.duplicate() # Duplicate to avoid modifying the original
	# print("ConvoyCargoMenu: Initialized with data: ", convoy_data_received) # DEBUG

	if is_instance_valid(title_label) and convoy_data_received.has("convoy_name"):
		title_label.text = "%s" % convoy_data_received.get("convoy_name", "Unknown Convoy")
	elif is_instance_valid(title_label):
		title_label.text = "Cargo Hold"
	
	_populate_cargo_list()

func _populate_cargo_list():
	# Diagnostic: Try to get the node directly here
	var main_vbox_node: VBoxContainer = get_node_or_null("MainVBox")
	if not is_instance_valid(main_vbox_node):
		printerr("ConvoyCargoMenu: _populate_cargo_list - MainVBox node NOT FOUND via get_node_or_null. Path: MainVBox")
		printerr("ConvoyCargoMenu: _populate_cargo_list - State of @onready var cargo_items_vbox: %s" % [cargo_items_vbox]) # Log original target for context
		return

	var scroll_container_node: ScrollContainer = main_vbox_node.get_node_or_null("ScrollContainer")
	if not is_instance_valid(scroll_container_node):
		printerr("ConvoyCargoMenu: _populate_cargo_list - ScrollContainer node NOT FOUND as child of MainVBox. Path: MainVBox/ScrollContainer")
		printerr("ConvoyCargoMenu: _populate_cargo_list - State of @onready var cargo_items_vbox: %s" % [cargo_items_vbox])
		return

	var direct_vbox_ref: VBoxContainer = scroll_container_node.get_node_or_null("CargoItemsVBox")
	
	if not is_instance_valid(direct_vbox_ref):
		printerr("ConvoyCargoMenu: _populate_cargo_list - CargoItemsVBox node NOT FOUND as child of ScrollContainer. Full attempted path: MainVBox/ScrollContainer/CargoItemsVBox")
		# Also log the state of the @onready var for comparison
		printerr("ConvoyCargoMenu: _populate_cargo_list - State of @onready var cargo_items_vbox: %s" % [cargo_items_vbox])
		return

	# Clear any previous items from the list
	for child in direct_vbox_ref.get_children():
		child.queue_free()

	var vehicle_details_list: Array = convoy_data_received.get("vehicle_details_list", [])
	
	if vehicle_details_list.is_empty():
		var no_vehicles_label = Label.new()
		no_vehicles_label.text = "No vehicles in this convoy."
		no_vehicles_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		direct_vbox_ref.add_child(no_vehicles_label)
		return

	var any_cargo_found_in_convoy = false

	for vehicle_data in vehicle_details_list:
		if not vehicle_data is Dictionary:
			printerr("ConvoyCargoMenu: Invalid vehicle_data entry.")
			continue

		var vehicle_name_label = Label.new()
		vehicle_name_label.text = "Vehicle: %s" % vehicle_data.get("name", "Unnamed Vehicle")
		# vehicle_name_label.add_theme_font_size_override("font_size", 18) # Optional: make header larger
		# vehicle_name_label.add_theme_font_override("font", preload("res://path/to/your_bold_font.tres")) # Optional: bold
		direct_vbox_ref.add_child(vehicle_name_label)

		var vehicle_cargo_list: Array = vehicle_data.get("cargo", [])
		var actual_cargo_for_this_vehicle: Array = []
		for item in vehicle_cargo_list:
			if item is Dictionary and item.get("intrinsic_part_id") == null:
				actual_cargo_for_this_vehicle.append(item)
		
		if actual_cargo_for_this_vehicle.is_empty():
			var no_cargo_in_vehicle_label = Label.new()
			no_cargo_in_vehicle_label.text = "  No cargo items in this vehicle."
			direct_vbox_ref.add_child(no_cargo_in_vehicle_label)
		else:
			any_cargo_found_in_convoy = true
			# Aggregate cargo items by name for THIS VEHICLE
			var aggregated_cargo_for_vehicle: Dictionary = {}
			for cargo_item_data in actual_cargo_for_this_vehicle:
				var item_name: String = cargo_item_data.get("name", "Unknown Item")
				var item_quantity: int = cargo_item_data.get("quantity", 0)
				if item_quantity > 0:
					if not aggregated_cargo_for_vehicle.has(item_name):
						aggregated_cargo_for_vehicle[item_name] = {"quantity": 0, "item_data_sample": cargo_item_data.duplicate(true)}
					aggregated_cargo_for_vehicle[item_name]["quantity"] += item_quantity
			
			if aggregated_cargo_for_vehicle.is_empty(): # Should not happen if actual_cargo_for_this_vehicle was not empty
				var no_display_cargo_label = Label.new()
				no_display_cargo_label.text = "  No displayable cargo items in this vehicle."
				direct_vbox_ref.add_child(no_display_cargo_label)
			else:
				for item_name in aggregated_cargo_for_vehicle:
					var agg_data = aggregated_cargo_for_vehicle[item_name]
					var quantity = agg_data["quantity"]
					var item_data_sample_for_inspect = agg_data["item_data_sample"]

					var hbox = HBoxContainer.new()
					hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

					var item_label = Label.new()
					item_label.text = "  %s x %s" % [item_name, quantity] # Indent cargo items
					item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					item_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

					var inspect_button = Button.new()
					inspect_button.text = "Inspect"
					inspect_button.custom_minimum_size.x = 100
					inspect_button.custom_minimum_size.y = 30
					inspect_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
					inspect_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					inspect_button.pressed.connect(_on_inspect_cargo_item_pressed.bind(item_data_sample_for_inspect))

					hbox.add_child(item_label)
					hbox.add_child(inspect_button)
					direct_vbox_ref.add_child(hbox)
		# Add a small separator after each vehicle's section for clarity
		var separator = HSeparator.new()
		separator.custom_minimum_size.y = 10 # Make it a bit taller than default
		direct_vbox_ref.add_child(separator)

	if not any_cargo_found_in_convoy and not vehicle_details_list.is_empty():
		# This case means there were vehicles, but none of them had any non-part cargo.
		var no_cargo_overall_label = Label.new()
		no_cargo_overall_label.text = "This convoy is carrying no cargo items (only vehicle parts)."
		no_cargo_overall_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Insert it after the last vehicle's separator, or at the top if only one vehicle with no cargo.
		# For simplicity, just add it. If there were vehicle headers, it will appear at the end.
		# If you want it at the top if *all* vehicles have no cargo, more complex logic is needed.
		direct_vbox_ref.add_child(no_cargo_overall_label)

func _on_back_button_pressed():
	# print("ConvoyCargoMenu: Back button pressed. Emitting 'back_requested' signal.") # DEBUG
	emit_signal("back_requested")

func _on_inspect_cargo_item_pressed(item_data: Dictionary):
	print("ConvoyCargoMenu: Inspecting cargo item: ", item_data.get("name", "Unknown Item"))

	var dialog = AcceptDialog.new()
	dialog.title = "Inspect Cargo: " + item_data.get("name", "Item Details")
	
	var details_text = ""
	# You can define a list of important keys for cargo if needed, or just iterate all
	for key in item_data:
		if item_data[key] != null: # Only show non-null values
			details_text += "%s: %s\n" % [key.capitalize().replace("_", " "), str(item_data[key])]
			
	dialog.dialog_text = details_text

	# Add to tree BEFORE trying to access viewport or set size relative to it.
	get_tree().root.add_child(dialog)

	# Ensure the dialog doesn't exceed viewport dimensions and has a minimum size.
	var viewport_size = dialog.get_viewport().size
	dialog.max_size = viewport_size * 0.9 # Max 90% of viewport width and height
	dialog.min_size = Vector2(300, 200)  # Ensure a minimum sensible size for readability

	# popup_centered() will respect min_size and max_size.
	# It tries to fit content, then clamps to max_size, and ensures min_size.
	dialog.popup_centered()

	dialog.connect("confirmed", Callable(dialog, "queue_free"))
	dialog.connect("popup_hide", Callable(dialog, "queue_free"))

func _on_title_label_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		print("ConvoyCargoMenu: Title clicked. Emitting 'return_to_convoy_overview_requested'.")
		emit_signal("return_to_convoy_overview_requested", convoy_data_received)
		get_viewport().set_input_as_handled()
