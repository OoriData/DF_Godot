extends Control

# Signal that MenuManager will listen for to go back
signal back_requested

# @onready variables for UI elements
@onready var title_label: Label = $MainVBox/TitleLabel
@onready var vehicle_option_button: OptionButton = $MainVBox/VehicleOptionButton
@onready var back_button: Button = $MainVBox/BackButton

@onready var overview_vbox: VBoxContainer = $MainVBox/VehicleTabContainer/Overview/OverviewVBox
@onready var parts_vbox: VBoxContainer = $MainVBox/VehicleTabContainer/Parts/PartsVBox
@onready var cargo_vbox: VBoxContainer = $MainVBox/VehicleTabContainer/Cargo/CargoVBox

var current_vehicle_list: Array = []
var _current_convoy_data: Dictionary # To store the full convoy data

const CONSUMABLE_CLASS_IDS = [
	"4ccf7ae4-2297-420c-af71-97eda72dceca", # MRE Boxes
	"00422cf1-3ec5-4547-8ae3-ef7fa8029e18", # Fuel Drums
	"6cd91f47-5a72-4df6-8475-ca15c04af786"  # Water Jerry Cans
]

# New: Define part categories and their display order
const PART_CATEGORIES = {
	"ice": "Engine",
	"electric_motor": "Engine",
	"transmission": "Drivetrain",
	"drivetrain": "Drivetrain",
	"transfer_case": "Drivetrain",
	"turbocharger": "Performance",
	"supercharger": "Performance",
	"tune": "Performance",
	"radiator": "Performance",
	"chassis": "Chassis",
	"suspension": "Chassis & Suspension",
	"springs_dampers": "Chassis & Suspension",
	"differentials": "Chassis & Suspension",
	"sway_bars": "Chassis & Suspension",
	"wheels": "Wheels & Tires",
	"tires": "Wheels & Tires",
	"underbody": "Protection",
	"body": "Body & Armor",
	"bumpers": "Body & Armor",
	"rooftop": "Utility",
	"receiver_hitch": "Utility",
	"spare_tire": "Utility",
	"compressor": "Utility",
	"fuel_tank": "Fuel System",
	"battery": "Power System",
	"other": "Other Parts" # Fallback category
}

const PART_CATEGORY_ORDER = [
	"Engine",
	"Drivetrain",
	"Performance",
	"Fuel System",
	"Power System",
	"Chassis",
	"Chassis & Suspension",
	"Wheels & Tires",
	"Body & Armor",
	"Protection",
	"Utility",
	"Other Parts"
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

	# Check new VBox validity
	if not is_instance_valid(overview_vbox) or not is_instance_valid(parts_vbox) or not is_instance_valid(cargo_vbox):
		printerr("ConvoyVehicleMenu: CRITICAL - One or more tab VBox nodes are not valid in _ready()!")
		return # Stop further initialization

	_clear_all_tabs() # Now safe to call
	_show_initial_detail_message("Initializing...") # Now safe to call

func _on_back_button_pressed():
	print("ConvoyVehicleMenu: Back button pressed. Emitting 'back_requested' signal.")
	emit_signal("back_requested")

func _clear_all_tabs():
	var all_vboxes = [overview_vbox, parts_vbox, cargo_vbox]
	for vbox in all_vboxes:
		if is_instance_valid(vbox):
			for child in vbox.get_children():
				child.queue_free()
			vbox.add_theme_constant_override("separation", 8)

func _show_initial_detail_message(message: String):
	_clear_all_tabs() # This also sets VBox separation
	if not is_instance_valid(overview_vbox): return

	var prompt_label = Label.new()
	prompt_label.text = message
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overview_vbox.add_child(prompt_label)

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

func _add_inspectable_item_row(parent: Container, item_name_text: String, item_summary_text: String, item_data: Dictionary):
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Let children determine the row height, but button will have a minimum.

	var name_label = Label.new()
	name_label.text = "  " + item_name_text # Indent for clarity
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
	# name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL # Allow label to take natural height
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER # Center vertically if row is taller
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER # Center text in label
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE # Prevent label from stealing clicks
	
	# Add a summary label for quick info
	var summary_label = Label.new()
	summary_label.text = item_summary_text
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER # Center text in label
	
	var inspect_button = Button.new()
	inspect_button.text = "Inspect"
	inspect_button.custom_minimum_size.x = 100 # Ensure button is reasonably sized
	inspect_button.custom_minimum_size.y = 30 # Explicit minimum height for the button
	inspect_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inspect_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER # Center vertically if row is taller
	
	inspect_button.pressed.connect(_on_inspect_part_pressed.bind(item_data))
	hbox.add_child(name_label) # Add the name label first
	
	hbox.add_child(name_label)
	hbox.add_child(inspect_button)
	parent.add_child(hbox)


func _display_vehicle_details(vehicle_data: Dictionary):
	print("ConvoyVehicleMenu: _display_vehicle_details called with data: ", vehicle_data.keys())
	_clear_all_tabs()

	_populate_overview_tab(vehicle_data)
	_populate_parts_tab(vehicle_data)
	_populate_cargo_tab(vehicle_data)

	# Ensure layout updates
	overview_vbox.call_deferred("update_minimum_size")
	parts_vbox.call_deferred("update_minimum_size")
	cargo_vbox.call_deferred("update_minimum_size")

func _populate_overview_tab(vehicle_data: Dictionary):
	if not is_instance_valid(overview_vbox): return

	# Basic Info
	_add_detail_row(overview_vbox, "Name:", String(vehicle_data.get("name", "N/A")))
	_add_detail_row(overview_vbox, "Make/Model:", vehicle_data.get("make_model", "N/A"))
	_add_detail_row(overview_vbox, "Description:", vehicle_data.get("description", "No description."), true)
	_add_detail_row(overview_vbox, "Color:", vehicle_data.get("color", "N/A").capitalize())
	_add_detail_row(overview_vbox, "Base Description:", vehicle_data.get("base_desc", "No detailed description."), true)
	_add_detail_row(overview_vbox, "Shape:", vehicle_data.get("shape", "N/A").capitalize().replace("_", " "))
	_add_detail_row(overview_vbox, "Base Value:", "$%s" % int(vehicle_data.get("base_value", 0.0)))
	_add_detail_row(overview_vbox, "Current Value:", "$%s" % int(vehicle_data.get("value", 0.0)))

	# Stats Section
	var stats_title = Label.new()
	stats_title.text = "Statistics:"
	stats_title.add_theme_font_size_override("font_size", 18) # Make title slightly larger
	stats_title.add_theme_color_override("font_color", Color.YELLOW) # Highlight title

	overview_vbox.add_child(stats_title)
	_add_detail_row(overview_vbox, "  Top Speed:", "%.0f " % vehicle_data.get("top_speed", 0.0))
	_add_detail_row(overview_vbox, "  Offroad:", "%.0f" % vehicle_data.get("offroad_capability", 0.0))
	_add_detail_row(overview_vbox, "  Efficiency:", "%.0f" % vehicle_data.get("efficiency", 0.0))
	_add_detail_row(overview_vbox, "  Cargo Capacity:", "%.0f" % vehicle_data.get("cargo_capacity", 0.0))
	_add_detail_row(overview_vbox, "  Weight Capacity:", "%.0f" % vehicle_data.get("weight_capacity", 0.0))
	_add_detail_row(overview_vbox, "  Passenger Seats:", "%d" % vehicle_data.get("passenger_seats", 0))

func _populate_parts_tab(vehicle_data: Dictionary):
	if not is_instance_valid(parts_vbox): return

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

	# New: Categorize parts
	var categorized_parts: Dictionary = {}
	for category_name in PART_CATEGORY_ORDER:
		categorized_parts[category_name] = []

	for part_item_data in vehicle_parts_list:
		var slot = part_item_data.get("slot", "other")
		var category = PART_CATEGORIES.get(slot, "Other Parts")
		if not categorized_parts.has(category):
			categorized_parts[category] = [] # Should not happen if PART_CATEGORY_ORDER is exhaustive
		categorized_parts[category].append(part_item_data)

	# Vehicle Parts Section (Intrinsic Components)
	var parts_main_title = Label.new()
	parts_main_title.text = "Installed Parts:"
	parts_main_title.add_theme_font_size_override("font_size", 18)
	parts_main_title.add_theme_color_override("font_color", Color.YELLOW)
	parts_vbox.add_child(parts_main_title)

	var has_parts_to_display = false
	for category_name in PART_CATEGORY_ORDER:
		var parts_in_category = categorized_parts.get(category_name)
		if parts_in_category and not parts_in_category.is_empty():
			has_parts_to_display = true
			# Add category sub-header
			var category_label = Label.new()
			category_label.text = category_name + ":"
			# Make category headers more prominent to act as the "bold title"
			category_label.add_theme_font_size_override("font_size", 18)
			category_label.add_theme_color_override("font_color", Color.YELLOW)
			parts_vbox.add_child(category_label)

			# Add a GridContainer for this category's parts
			var grid = GridContainer.new()
			grid.columns = 3 # A good starting point, adjust as needed
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			parts_vbox.add_child(grid)

			# Sort parts within each category by name for consistent display
			parts_in_category.sort_custom(func(a, b): return a.get("name", "Z") < b.get("name", "Z"))

			for part_item_data in parts_in_category:
				# Create a button for each part, with the part's name as text
				var part_button = Button.new()
				part_button.text = part_item_data.get("name", "Unknown Part")
				part_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				part_button.custom_minimum_size.y = 40 # Give buttons some height
				part_button.pressed.connect(_on_inspect_part_pressed.bind(part_item_data))
				grid.add_child(part_button)

	if not has_parts_to_display:
		var no_parts_label = Label.new()
		no_parts_label.text = "  No vehicle parts installed."
		parts_vbox.add_child(no_parts_label)

func _populate_cargo_tab(vehicle_data: Dictionary):
	if not is_instance_valid(cargo_vbox): return

	var all_cargo_from_vehicle: Array = vehicle_data.get("cargo", [])
	var general_cargo_list: Array = []

	# Filter out parts that are also cargo
	for item_data in all_cargo_from_vehicle:
		if item_data is Dictionary and item_data.get("intrinsic_part_id") == null:
			general_cargo_list.append(item_data)

	if general_cargo_list.is_empty():
		var no_cargo_label = Label.new()
		no_cargo_label.text = "This vehicle is not carrying any cargo."
		cargo_vbox.add_child(no_cargo_label)
		return

	# Aggregate cargo items by name
	var aggregated_cargo: Dictionary = {}
	for cargo_item in general_cargo_list:
		var item_name = cargo_item.get("name", "Unknown Item")
		if not aggregated_cargo.has(item_name):
			aggregated_cargo[item_name] = {"quantity": 0, "sample": cargo_item}
		aggregated_cargo[item_name]["quantity"] += cargo_item.get("quantity", 1)

	# Display aggregated cargo
	for item_name in aggregated_cargo:
		var agg_data = aggregated_cargo[item_name]
		var summary_text = "Quantity: %d" % agg_data.quantity
		_add_inspectable_item_row(cargo_vbox, item_name, summary_text, agg_data.sample)

func _get_part_summary_string(part_data: Dictionary) -> String:
	var summary_parts = []

	# Performance modifiers
	if part_data.has("top_speed_add") and part_data.top_speed_add != null and part_data.top_speed_add != 0:
		summary_parts.append("Speed: %+d" % part_data.top_speed_add)
	if part_data.has("efficiency_add") and part_data.efficiency_add != null and part_data.efficiency_add != 0:
		summary_parts.append("Eff: %+d" % part_data.efficiency_add)
	if part_data.has("offroad_capability_add") and part_data.offroad_capability_add != null and part_data.offroad_capability_add != 0:
		summary_parts.append("Offroad: %+d" % part_data.offroad_capability_add)

	# Capacity/Resource
	if part_data.has("fuel_capacity") and part_data.fuel_capacity != null and part_data.fuel_capacity > 0:
		summary_parts.append("Fuel Cap: %.0fL" % part_data.fuel_capacity)
	if part_data.has("kwh_capacity") and part_data.kwh_capacity != null and part_data.kwh_capacity > 0:
		summary_parts.append("kWh Cap: %.0f" % part_data.kwh_capacity)
	if part_data.has("cargo_capacity_add") and part_data.cargo_capacity_add != null and part_data.cargo_capacity_add != 0:
		summary_parts.append("Cargo: %+d" % part_data.cargo_capacity_add)
	if part_data.has("weight_capacity_add") and part_data.weight_capacity_add != null and part_data.weight_capacity_add != 0:
		summary_parts.append("Weight Cap: %+d" % part_data.weight_capacity_add)

	# Other notable stats
	if part_data.has("wp") and part_data.wp != null and part_data.wp > 0:
		summary_parts.append("WP: %.0f" % part_data.wp)
	if part_data.has("value") and part_data.value != null and part_data.value > 0:
		summary_parts.append("Value: $%s" % int(part_data.value))

	if summary_parts.is_empty():
		return "No notable stats"
	return "(" + ", ".join(summary_parts) + ")"

func _on_inspect_part_pressed(part_data: Dictionary):
	print("ConvoyVehicleMenu: Inspecting part: ", part_data.get("name", "Unknown Part"))

	var dialog = AcceptDialog.new()
	dialog.title = "Inspect: " + part_data.get("name", "Component Details")
	
	var dialog_vbox = VBoxContainer.new()
	dialog_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(dialog_vbox)

	_populate_part_details_dialog(dialog_vbox, part_data) # This function populates dialog_vbox directly
	# Remove the dialog.dialog_text line as it's no longer used and would cause an error
	# dialog.dialog_text = details_text 
	get_tree().root.add_child(dialog) # Add to the scene root to ensure visibility
	dialog.popup_centered_ratio(0.75) # Make dialog wider
	dialog.connect("confirmed", Callable(dialog, "queue_free"))
	dialog.connect("popup_hide", Callable(dialog, "queue_free")) # Also free if closed via 'X' or Esc



func _populate_part_details_dialog(parent_vbox: VBoxContainer, part_data: Dictionary):
	# Main details
	var main_details_grid = GridContainer.new()
	main_details_grid.columns = 2
	main_details_grid.add_theme_constant_override("h_separation", 10)
	main_details_grid.add_theme_constant_override("v_separation", 5)
	parent_vbox.add_child(main_details_grid)

	_add_grid_row(main_details_grid, "Name", part_data.get("name", "N/A"))
	_add_grid_row(main_details_grid, "Slot", part_data.get("slot", "N/A").capitalize().replace("_", " ")) # Corrected: Removed extra argument
	_add_grid_row(main_details_grid, "Description", part_data.get("description", part_data.get("base_desc", "No description available.")))
	_add_grid_row(main_details_grid, "Value", "$%s" % int(part_data.get("value", 0.0)))
	_add_grid_row(main_details_grid, "Critical Part", "Yes" if part_data.get("critical", false) else "No")
	_add_grid_row(main_details_grid, "Bolt-on", "Yes" if part_data.get("bolt_on", false) else "No")
	_add_grid_row(main_details_grid, "Removable", "Yes" if part_data.get("removable", false) else "No")
	_add_grid_row(main_details_grid, "OE Part", "Yes" if part_data.get("oe", false) else "No")
	_add_grid_row(main_details_grid, "Salvageable", "Yes" if part_data.get("salvagable", false) else "No")

	# Performance Modifiers
	var perf_mods_label = Label.new()
	perf_mods_label.text = "Performance Modifiers:"
	perf_mods_label.add_theme_font_size_override("font_size", 16)
	perf_mods_label.add_theme_color_override("font_color", Color.CYAN)
	parent_vbox.add_child(perf_mods_label)

	var perf_grid = GridContainer.new()
	perf_grid.columns = 2
	perf_grid.add_theme_constant_override("h_separation", 10)
	perf_grid.add_theme_constant_override("v_separation", 5)
	parent_vbox.add_child(perf_grid)

	if part_data.has("top_speed_add") and part_data.top_speed_add != null:
		_add_grid_row(perf_grid, "Top Speed Add", "%+d" % part_data.top_speed_add)
	if part_data.has("efficiency_add") and part_data.efficiency_add != null:
		_add_grid_row(perf_grid, "Efficiency Add", "%+d" % part_data.efficiency_add)
	if part_data.has("offroad_capability_add") and part_data.offroad_capability_add != null:
		_add_grid_row(perf_grid, "Offroad Add", "%+d" % part_data.offroad_capability_add)
	if part_data.has("kw") and part_data.kw != null:
		_add_grid_row(perf_grid, "Power (kW)", "%.1f" % part_data.kw)
	if part_data.has("nm") and part_data.nm != null:
		_add_grid_row(perf_grid, "Torque (Nm)", "%.1f" % part_data.nm)
	if part_data.has("wp") and part_data.wp != null:
		_add_grid_row(perf_grid, "Wear Points", "%.1f" % part_data.wp)
	if part_data.has("weight_class") and part_data.weight_class != null:
		_add_grid_row(perf_grid, "Weight Class", "%.0f" % part_data.weight_class)
	if part_data.has("diameter") and part_data.diameter != null:
		_add_grid_row(perf_grid, "Diameter", "%.3f" % part_data.diameter)

	# Resource/Capacity
	var resource_label = Label.new()
	resource_label.text = "Resource & Capacity:"
	resource_label.add_theme_font_size_override("font_size", 16)
	resource_label.add_theme_color_override("font_color", Color.CYAN)
	parent_vbox.add_child(resource_label)

	var resource_grid = GridContainer.new()
	resource_grid.columns = 2
	resource_grid.add_theme_constant_override("h_separation", 10)
	resource_grid.add_theme_constant_override("v_separation", 5)
	parent_vbox.add_child(resource_grid)

	if part_data.has("fuel_capacity") and part_data.fuel_capacity != null:
		_add_grid_row(resource_grid, "Fuel Capacity", "%.1f L" % part_data.fuel_capacity)
	if part_data.has("kwh_capacity") and part_data.kwh_capacity != null:
		_add_grid_row(resource_grid, "Battery Capacity", "%.1f kWh" % part_data.kwh_capacity)
	if part_data.has("cargo_capacity_add") and part_data.cargo_capacity_add != null:
		_add_grid_row(resource_grid, "Cargo Capacity Add", "%+d" % part_data.cargo_capacity_add)
	if part_data.has("weight_capacity_add") and part_data.weight_capacity_add != null:
		_add_grid_row(resource_grid, "Weight Capacity Add", "%+d" % part_data.weight_capacity_add)
	if part_data.has("weight_capacity_multi") and part_data.weight_capacity_multi != null:
		_add_grid_row(resource_grid, "Weight Capacity Multiplier", "x%.2f" % part_data.weight_capacity_multi)
	if part_data.has("fuel") and part_data.fuel != null:
		_add_grid_row(resource_grid, "Current Fuel", "%.1f L" % part_data.fuel)
	if part_data.has("water") and part_data.water != null:
		_add_grid_row(resource_grid, "Current Water", "%.1f L" % part_data.water)
	if part_data.has("food") and part_data.food != null:
		_add_grid_row(resource_grid, "Current Food", "%.1f units" % part_data.food)
	if part_data.has("volume") and part_data.volume != null:
		_add_grid_row(resource_grid, "Volume", "%.1f" % part_data.volume)
	if part_data.has("weight") and part_data.weight != null:
		_add_grid_row(resource_grid, "Weight", "%.1f" % part_data.weight)

	# Raw Data (for debugging/completeness)
	var raw_data_label = Label.new()
	raw_data_label.text = "Raw Data:"
	raw_data_label.add_theme_font_size_override("font_size", 16)
	raw_data_label.add_theme_color_override("font_color", Color.GRAY)
	parent_vbox.add_child(raw_data_label)

	var raw_data_grid = GridContainer.new()
	raw_data_grid.columns = 2
	raw_data_grid.add_theme_constant_override("h_separation", 10)
	raw_data_grid.add_theme_constant_override("v_separation", 5)
	parent_vbox.add_child(raw_data_grid)

	for key in part_data:
		# Skip keys already displayed in structured sections
		if key in ["name", "slot", "description", "base_desc", "value", "critical", "bolt_on", "removable", "oe", "salvagable",
					"top_speed_add", "efficiency_add", "offroad_capability_add", "kw", "nm", "wp", "weight_class", "diameter",
					"fuel_capacity", "kwh_capacity", "cargo_capacity_add", "weight_capacity_add", "weight_capacity_multi",
					"fuel", "water", "food", "volume", "weight", "parts", "cargo", "log", "creation_date", "distributor_id",
					"origin_sett_id", "packed_vehicle", "pending_deletion", "recipient", "resource_weight", "specific_name",
					"specific_unit_capacity", "unit_capacity", "unit_delivery_reward", "unit_dry_weight", "unit_price",
					"unit_volume", "unit_weight", "vehicle_id", "vendor_id", "warehouse_id", "class_id", "base_name",
					"base_unit_capacity", "base_unit_price", "energy_density", "dummy", "coupling", "driven_axles", "requirements"]:
			continue
		
		# Special handling for arrays/dictionaries in raw data
		var display_value = part_data[key]
		if display_value is Array or display_value is Dictionary:
			display_value = JSON.stringify(display_value) # Convert complex types to string
		
		_add_grid_row(raw_data_grid, key.capitalize().replace("_", " "), display_value)

	# Ensure dialog resizes to fit content
	parent_vbox.call_deferred("update_minimum_size")
	parent_vbox.get_parent().call_deferred("popup_centered_ratio", 0.75) # Re-center dialog after content added

func _add_grid_row(grid: GridContainer, key: String, value):
	"""Helper function to add a key-value row to a GridContainer."""
	var key_label = Label.new()
	key_label.text = key + ":"
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key_label.add_theme_color_override("font_color", Color.LIGHT_BLUE)
	grid.add_child(key_label)

	var value_label = Label.new()
	value_label.text = str(value)
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value_label)
