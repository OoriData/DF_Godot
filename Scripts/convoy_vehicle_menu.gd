extends Control

# Signal that MenuManager will listen for to go back
signal back_requested
signal inspect_all_convoy_cargo_requested(convoy_data) # New signal

# @onready variables for UI elements
@onready var title_label: Label = $MainVBox/TitleLabel
@onready var vehicle_option_button: OptionButton = $MainVBox/VehicleOptionButton
@onready var details_scroll_container: ScrollContainer = $MainVBox/DetailsScrollContainer # This is correct
@onready var vehicle_details_vbox: VBoxContainer = $MainVBox/DetailsScrollContainer/VehicleDetailsVBox # Corrected path
@onready var back_button: Button = $MainVBox/BackButton

var current_vehicle_list: Array = []
var _current_convoy_data: Dictionary # To store the full convoy data

const CONSUMABLE_CLASS_IDS = [
	"4ccf7ae4-2297-420c-af71-97eda72dceca", # MRE Boxes
	"00422cf1-3ec5-4547-8ae3-ef7fa8029e18", # Fuel Drums
	"6cd91f47-5a72-4df6-8475-ca15c04af786"  # Water Jerry Cans
]

func _ready():
	# Connect the back button signal
	if is_instance_valid(back_button):
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed)
	else:
		printerr("ConvoyVehicleMenu: CRITICAL - BackButton node NOT found or is not a Button.")

	# Connect the vehicle selection signal
	if is_instance_valid(vehicle_option_button):
		if not vehicle_option_button.is_connected("item_selected", Callable(self, "_on_vehicle_selected")):
			vehicle_option_button.item_selected.connect(_on_vehicle_selected)
	else:
		printerr("ConvoyVehicleMenu: CRITICAL - VehicleOptionButton node NOT found.")

	# Check vehicle_details_vbox's validity (it should be valid now with the correct path)
	if not is_instance_valid(vehicle_details_vbox):
		printerr("ConvoyVehicleMenu: CRITICAL - vehicle_details_vbox is NOT valid in _ready()! Check scene path: $MainVBox/DetailsScrollContainer/VehicleDetailsVBox")
		return # Stop further initialization

	_clear_vehicle_details_display() # Now safe to call
	_show_initial_detail_message("Initializing...") # Now safe to call

func _on_back_button_pressed():
	print("ConvoyVehicleMenu: Back button pressed. Emitting 'back_requested' signal.")
	emit_signal("back_requested")

func _clear_vehicle_details_display():
	if not is_instance_valid(vehicle_details_vbox): return
	for child in vehicle_details_vbox.get_children():
		child.queue_free()
	vehicle_details_vbox.add_theme_constant_override("separation", 8)

func _show_initial_detail_message(message: String):
	_clear_vehicle_details_display() # This also sets VBox separation
	if not is_instance_valid(vehicle_details_vbox): return

	var prompt_label = Label.new()
	prompt_label.text = message
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vehicle_details_vbox.add_child(prompt_label)

func initialize_with_data(data: Dictionary):
	# Ensure this function runs only after the node is fully ready and @onready vars are set.
	if not is_node_ready():
		printerr("ConvoyVehicleMenu: initialize_with_data called BEFORE node is ready! Deferring.")
		call_deferred("initialize_with_data", data)
		return

	print("ConvoyVehicleMenu: initialize_with_data called. Data keys: ", data.keys())

	if is_instance_valid(title_label):
		_current_convoy_data = data.duplicate(true) # Store the full convoy data
		title_label.text = data.get("convoy_name", "Convoy")

	current_vehicle_list = data.get("vehicle_details_list", [])

	if is_instance_valid(vehicle_option_button):
		print("ConvoyVehicleMenu: Populating VehicleOptionButton. Number of vehicles from data: ", current_vehicle_list.size())
		vehicle_option_button.clear()
		if current_vehicle_list.is_empty():
			vehicle_option_button.add_item("No Vehicles Available")
			vehicle_option_button.disabled = true
			print("ConvoyVehicleMenu: No vehicles found in list.")
			_show_initial_detail_message("No vehicles in this convoy.")
		else:
			vehicle_option_button.disabled = false
			for i in range(current_vehicle_list.size()):
				var vehicle_data = current_vehicle_list[i]
				if vehicle_data is Dictionary:
					var vehicle_name = vehicle_data.get("name", "Unnamed Vehicle %s" % (i + 1))
					var make_model = vehicle_data.get("make_model", "N/A")
					vehicle_option_button.add_item("%s (%s)" % [vehicle_name, make_model], i)
			print("ConvoyVehicleMenu: VehicleOptionButton populated. Item count: ", vehicle_option_button.get_item_count())
			# Select the first vehicle by default if available
			if vehicle_option_button.get_item_count() > 0:
				print("ConvoyVehicleMenu: Attempting to select and display first vehicle.")
				vehicle_option_button.select(0)
				_on_vehicle_selected(0) # Manually trigger the display for the first item
			else: # Should not happen if current_vehicle_list was not empty, but as a fallback
				print("ConvoyVehicleMenu: OptionButton is empty after trying to populate. Showing initial message.")
				_show_initial_detail_message("Select a vehicle from the dropdown to view details.")
	else:
		printerr("ConvoyVehicleMenu: CRITICAL - VehicleOptionButton node NOT found during initialize_with_data.")
		_show_initial_detail_message("Error: Vehicle selection UI not available.")

func _on_vehicle_selected(index: int):
	print("ConvoyVehicleMenu: _on_vehicle_selected called with index: ", index)
	if index < 0 or index >= current_vehicle_list.size():
		printerr("ConvoyVehicleMenu: Invalid vehicle index: ", index, " (list size: ", current_vehicle_list.size(), ")")
		_show_initial_detail_message("Invalid vehicle selection.")
		return

	var selected_vehicle_data = current_vehicle_list[index]
	print("ConvoyVehicleMenu: Attempting to display data for vehicle at index ", index, ": ", selected_vehicle_data)
	if selected_vehicle_data is Dictionary:
		_display_vehicle_details(selected_vehicle_data)
	else:
		printerr("ConvoyVehicleMenu: Vehicle data at index ", index, " is not a Dictionary: ", typeof(selected_vehicle_data))
		_show_initial_detail_message("Error: Could not load vehicle data.")

func _add_detail_row(parent: Container, label_text: String, value_text: String, value_autowrap: bool = false):
	# print("ConvoyVehicleMenu: _add_detail_row called. Label: '", label_text, "', Value: '", value_text, "'") # Can be too verbose
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label_node = Label.new()
	label_node.text = label_text
	label_node.custom_minimum_size.x = 120 # Adjust for desired label width

	var value_node = Label.new()
	value_node.text = value_text
	value_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_node.clip_text = true
	if value_autowrap:
		value_node.autowrap_mode = TextServer.AUTOWRAP_WORD
	
	hbox.add_child(label_node)
	hbox.add_child(value_node)
	parent.add_child(hbox)

func _add_inspectable_part_row(parent: Container, part_name_text: String, part_data: Dictionary):
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Let children determine the row height, but button will have a minimum.

	var name_label = Label.new()
	name_label.text = "  " + part_name_text # Indent for clarity
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
	# name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL # Allow label to take natural height
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER # Center vertically if row is taller
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER # Center text in label
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE # Prevent label from stealing clicks
	
	var inspect_button = Button.new()
	inspect_button.text = "Inspect"
	inspect_button.custom_minimum_size.x = 100 # Ensure button is reasonably sized
	inspect_button.custom_minimum_size.y = 30 # Explicit minimum height for the button
	inspect_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inspect_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER # Center vertically if row is taller
	
	inspect_button.pressed.connect(_on_inspect_part_pressed.bind(part_data))
	
	hbox.add_child(name_label)
	hbox.add_child(inspect_button)
	parent.add_child(hbox)


func _display_vehicle_details(vehicle_data: Dictionary):
	print("ConvoyVehicleMenu: _display_vehicle_details called with data: ", vehicle_data.keys())

	# Using the @onready var, assuming it's correctly initialized and the node exists.
	# The check in _ready() should catch if it's not found initially.
	# If issues persist where it becomes invalid later, get_node_or_null here is a fallback.
	var active_details_vbox: VBoxContainer = vehicle_details_vbox 

	if not is_instance_valid(active_details_vbox):
		printerr("ConvoyVehicleMenu: CRITICAL - Cannot find VehicleDetailsVBox node at path 'MainVBox/DetailsScrollContainer/VehicleDetailsVBox' when trying to display details.")
		# For deeper debugging, you can compare with the @onready var:
		# if not is_instance_valid(vehicle_details_vbox):
		# 	printerr("ConvoyVehicleMenu: (Debug) The @onready var 'vehicle_details_vbox' is also invalid here.")
		# else:
		# 	printerr("ConvoyVehicleMenu: (Debug) The @onready var 'vehicle_details_vbox' IS valid, but get_node_or_null failed. This is highly unusual.")
		return

	# Clear previous content using the fresh reference
	for child in active_details_vbox.get_children():
		child.queue_free()
	active_details_vbox.add_theme_constant_override("separation", 8)

	print("ConvoyVehicleMenu: VehicleDetailsVBox (active reference) is valid. Children before add: ", active_details_vbox.get_child_count())
	_add_detail_row(active_details_vbox, "Name:", String(vehicle_data.get("name", "N/A")))
	_add_detail_row(active_details_vbox, "Make/Model:", vehicle_data.get("make_model", "N/A"))
	_add_detail_row(active_details_vbox, "Description:", vehicle_data.get("description", "No description."), true)

	# Stats Section
	var stats_title = Label.new()
	stats_title.text = "Statistics:"
	# You can add theme overrides for font style/size if desired
	# stats_title.add_theme_font_override("font", preload("res://path/to/bold_font.tres"))
	active_details_vbox.add_child(stats_title)
	_add_detail_row(active_details_vbox, "  Top Speed:", "%.0f " % vehicle_data.get("top_speed", 0.0))
	_add_detail_row(active_details_vbox, "  Offroad:", "%.0f" % vehicle_data.get("offroad_capability", 0.0))
	_add_detail_row(active_details_vbox, "  Efficiency:", "%.0f" % vehicle_data.get("efficiency", 0.0))

	var all_cargo_from_vehicle: Array = vehicle_data.get("cargo", [])
	var all_parts_from_vehicle: Array = vehicle_data.get("parts", [])
	var vehicle_parts_list: Array = []

	# 1. Add all items from the dedicated 'parts' array
	if all_parts_from_vehicle is Array:
		vehicle_parts_list.append_array(all_parts_from_vehicle)

	# 2. Add parts that are also listed in the 'cargo' array (e.g., fuel tanks with intrinsic_part_id)
	if all_cargo_from_vehicle is Array:
		for item_data in all_cargo_from_vehicle:
			if item_data is Dictionary and item_data.has("intrinsic_part_id") and item_data.get("intrinsic_part_id") != null:
				vehicle_parts_list.append(item_data)

	# Vehicle Parts Section (Intrinsic Components)
	var parts_title = Label.new()
	parts_title.text = "Vehicle Parts:"
	active_details_vbox.add_child(parts_title)

	if not vehicle_parts_list.is_empty():
		# Sort parts by name for a consistent order
		vehicle_parts_list.sort_custom(func(a, b): return a.get("name", "Z") < b.get("name", "Z"))
		for part_item_data in vehicle_parts_list: # Iterate the new list of parts
			var part_name = part_item_data.get("name", "Unknown Component")
			_add_inspectable_part_row(active_details_vbox, part_name, part_item_data)
	else:
		var no_parts_label = Label.new()
		no_parts_label.text = "  No vehicle parts installed."
		active_details_vbox.add_child(no_parts_label)

	# Add button to view full convoy cargo manifest
	var view_cargo_button = Button.new()
	view_cargo_button.text = "View Full Cargo Manifest"
	view_cargo_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER # Center the button
	view_cargo_button.pressed.connect(_on_view_convoy_cargo_pressed)
	active_details_vbox.add_child(view_cargo_button)

	# Removed cargo summary label, users will click the button to view cargo.

	print("ConvoyVehicleMenu: VehicleDetailsVBox (active reference) children after add: ", active_details_vbox.get_child_count())

	# Ensure layout updates
	active_details_vbox.call_deferred("update_minimum_size")
	if is_instance_valid(details_scroll_container):
		details_scroll_container.call_deferred("update_minimum_size")
	else:
		printerr("ConvoyVehicleMenu: details_scroll_container is NOT valid at end of _display_vehicle_details.")

func _on_view_convoy_cargo_pressed():
	if _current_convoy_data:
		emit_signal("inspect_all_convoy_cargo_requested", _current_convoy_data)
	else:
		printerr("ConvoyVehicleMenu: _current_convoy_data is null, cannot open cargo menu.")

func _on_inspect_part_pressed(part_data: Dictionary):
	print("ConvoyVehicleMenu: Inspecting part: ", part_data.get("name", "Unknown Part"))

	var dialog = AcceptDialog.new()
	dialog.title = "Inspect: " + part_data.get("name", "Component Details")
	
	var details_text = ""
	# Prioritize specific, known important fields for parts
	var important_keys = ["name", "base_desc", "class_id", "cargo_id", "quantity", "weight", "volume", "capacity", "fuel", "water", "food", "kwh", "intrinsic_part_id", "specific_name", "unit_capacity", "unit_price", "unit_volume", "unit_weight"]
	for key in important_keys:
		if part_data.has(key) and part_data[key] != null:
			details_text += "%s: %s\n" % [key.capitalize().replace("_", " "), str(part_data[key])]
	
	details_text += "\n--- All Data ---\n" # Separator for less critical data
	for key in part_data:
		if not key in important_keys: # Add remaining keys
			details_text += "%s: %s\n" % [key.capitalize().replace("_", " "), str(part_data[key])]
			
	dialog.dialog_text = details_text
	get_tree().root.add_child(dialog) # Add to the scene root to ensure visibility
	dialog.popup_centered_ratio(0.75) # Make dialog wider
	dialog.connect("confirmed", Callable(dialog, "queue_free"))
	dialog.connect("popup_hide", Callable(dialog, "queue_free")) # Also free if closed via 'X' or Esc
