extends Control

# Signal that MenuManager will listen for to go back
signal back_requested

# @onready variables for UI elements
@onready var title_label: Label = $MainVBox/TitleLabel
@onready var scroll_container: ScrollContainer = $MainVBox/ScrollContainer
@onready var content_vbox: VBoxContainer = $MainVBox/ScrollContainer/ContentVBox
@onready var back_button: Button = $MainVBox/BackButton

func _ready():
	# Connect the back button signal
	if is_instance_valid(back_button):
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed, CONNECT_ONE_SHOT)
	else:
		printerr("ConvoyVehicleMenu: CRITICAL - BackButton node NOT found or is not a Button.")

	# Remove the placeholder label if it exists
	if content_vbox.has_node("PlaceholderLabel"):
		var placeholder = content_vbox.get_node("PlaceholderLabel")
		if is_instance_valid(placeholder):
			placeholder.queue_free()

func _on_back_button_pressed():
	print("ConvoyVehicleMenu: Back button pressed. Emitting 'back_requested' signal.")
	emit_signal("back_requested")

# Function to receive and display convoy data
func initialize_with_data(data: Dictionary):
	print("ConvoyVehicleMenu: Initialized with data.") # DEBUG
	# print(data) # Uncomment this line if you want to print the full data structure again

	# Set the title
	if is_instance_valid(title_label):
		title_label.text = data.get("convoy_name", "Convoy") + " - Vehicles"

	# Clear previous vehicle entries
	for child in content_vbox.get_children():
		child.queue_free()

	# Populate with vehicle data
	var vehicle_list: Array = data.get("vehicle_details_list", [])

	if vehicle_list.is_empty():
		var no_vehicles_label = Label.new()
		no_vehicles_label.text = "No vehicles in this convoy."
		no_vehicles_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_vehicles_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		no_vehicles_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		no_vehicles_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content_vbox.add_child(no_vehicles_label)
	else:
		for vehicle_data in vehicle_list:
			if vehicle_data is Dictionary:
				var vehicle_container = VBoxContainer.new()
				vehicle_container.add_theme_constant_override("separation", 5)
				vehicle_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				
				var name_label = Label.new()
				name_label.text = "Name: %s (%s)" % [vehicle_data.get("name", "N/A"), vehicle_data.get("make_model", "N/A")]
				name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
				vehicle_container.add_child(name_label)

				var desc_label = Label.new()
				desc_label.text = "Description: %s" % vehicle_data.get("description", "No description.")
				desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
				vehicle_container.add_child(desc_label)

				var stats_label = Label.new()
				stats_label.text = "Speed: %.1f | Offroad: %.1f | Efficiency: %.1f" % [
					vehicle_data.get("top_speed", 0.0),
					vehicle_data.get("offroad_capability", 0.0),
					vehicle_data.get("efficiency", 0.0)
				]
				vehicle_container.add_child(stats_label)

				# Display Cargo for this specific vehicle
				var vehicle_cargo_list: Array = vehicle_data.get("cargo", [])
				if not vehicle_cargo_list.is_empty():
					var cargo_label = Label.new()
					var cargo_summary_strings = []
					var cargo_counts: Dictionary = {}
					for cargo_item in vehicle_cargo_list:
						if cargo_item is Dictionary:
							var item_name = cargo_item.get("name", "Unknown Item")
							var item_qty = cargo_item.get("quantity", 0)
							# Sum quantities for the same item name
							cargo_counts[item_name] = cargo_counts.get(item_name, 0) + item_qty
					
					for item_name in cargo_counts:
						cargo_summary_strings.append("%s x%s" % [item_name, cargo_counts[item_name]])
					
					cargo_label.text = "Cargo: " + ", ".join(cargo_summary_strings)
					cargo_label.autowrap_mode = TextServer.AUTOWRAP_WORD
					vehicle_container.add_child(cargo_label)
				else:
					var no_cargo_label = Label.new()
					no_cargo_label.text = "Cargo: Empty"
					vehicle_container.add_child(no_cargo_label)

				# Add a separator after each vehicle (except the last)
				if vehicle_data != vehicle_list.back():
					var separator = HSeparator.new()
					vehicle_container.add_child(separator)

				content_vbox.add_child(vehicle_container)

	# Ensure the layout updates after adding children
	call_deferred("update_minimum_size")
	if is_instance_valid(scroll_container):
		scroll_container.call_deferred("update_minimum_size")
