extends Control

# Signal that MenuManager will listen for to go back
signal back_requested
# Signal to open the full cargo manifest for the entire convoy
signal return_to_convoy_overview_requested(convoy_data)
signal inspect_all_convoy_cargo_requested(convoy_data)

# @onready variables for UI elements
@onready var title_label: Label = $MainVBox/TitleLabel
@onready var vehicle_option_button: OptionButton = $MainVBox/VehicleOptionButton
@onready var back_button: Button = $MainVBox/BackButton

@onready var overview_vbox: VBoxContainer = $MainVBox/VehicleTabContainer/Overview/OverviewVBox
@onready var parts_vbox: VBoxContainer = $MainVBox/VehicleTabContainer/Parts/PartsVBox
@onready var cargo_vbox: VBoxContainer = $MainVBox/VehicleTabContainer/Cargo/CargoVBox
@onready var back_to_mechanic_button: Button = $MainVBox/BackButton # repurpose later if needed
@onready var _menu_buttons_container: Node = null
@onready var mechanic_button_scene_node: Button = $MainVBox/ActionButtons/MechanicButton
@onready var mechanics_embed: Node = $MainVBox/VehicleTabContainer/Service/MechanicsEmbed

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
	
	# Make the title label clickable to return to the convoy overview
	if is_instance_valid(title_label):
		title_label.mouse_filter = Control.MOUSE_FILTER_STOP # Allow it to receive mouse events
		title_label.gui_input.connect(_on_title_label_gui_input)

	# Old mechanic buttons are deprecated in favor of the Service tab
	# If one exists in the scene or overview, hide/skip wiring it.
	var buttons_path_candidates = ["MainVBox/ScrollContainer/ContentVBox/MenuButtons", "MainVBox/VehicleTabContainer/Overview/OverviewVBox/MenuButtons"]
	for p in buttons_path_candidates:
		var node = get_node_or_null(p)
		if node != null:
			_menu_buttons_container = node
			break
	# Ensure scene Mechanic button is hidden
	if is_instance_valid(mechanic_button_scene_node):
		mechanic_button_scene_node.visible = false

	# Configure embedded mechanics menu to fit tab chrome
	if is_instance_valid(mechanics_embed) and mechanics_embed.has_method("set_embedded_mode"):
		mechanics_embed.set_embedded_mode(true)

	# Check new VBox validity
	if not is_instance_valid(overview_vbox) or not is_instance_valid(parts_vbox) or not is_instance_valid(cargo_vbox):
		printerr("ConvoyVehicleMenu: CRITICAL - One or more tab VBox nodes are not valid in _ready()!")
		return # Stop further initialization

	_clear_all_tabs() # Now safe to call
	_show_initial_detail_message("Initializing...") # Now safe to call

	# Add a reference to GameDataManager
	var gdm: Node = null
	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("convoy_data_updated", Callable(self, "_on_gdm_convoy_data_updated")):
			gdm.convoy_data_updated.connect(_on_gdm_convoy_data_updated)

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
	print("ConvoyVehicleMenu: vehicle_details_list: ", data.get("vehicle_details_list", []))
	if data.has("vehicle_details_list") and data["vehicle_details_list"].size() > 0:
		print("ConvoyVehicleMenu: First vehicle keys: ", data["vehicle_details_list"][0].keys())

	if is_instance_valid(title_label):
		_current_convoy_data = data.duplicate(true) # Store the full convoy data
		title_label.text = data.get("convoy_name", "Convoy")
		_update_mechanic_button_enabled()

	current_vehicle_list = data.get("vehicle_details_list", [])

	# Initialize the Service tab mechanics with the same convoy data
	if is_instance_valid(mechanics_embed) and mechanics_embed.has_method("initialize_with_data"):
		mechanics_embed.initialize_with_data(data)

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
		# Keep Service tab mechanics selection in sync
		if is_instance_valid(mechanics_embed) and mechanics_embed.has_method("set_selected_vehicle_index"):
			mechanics_embed.set_selected_vehicle_index(index)
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

	var name_label = Label.new()
	name_label.text = "  " + item_name_text # Indent for clarity
	# Remove expand flag to keep labels and button together
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER # Center vertically if row is taller
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER # Center text in label
	
	# Add a summary label for quick info
	var summary_label = Label.new()
	summary_label.text = " " + item_summary_text # Add a space for separation
	summary_label.add_theme_color_override("font_color", Color.LIGHT_GRAY) # Make summary less prominent
	summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER # Center text in label
	
	var inspect_button = Button.new()
	inspect_button.text = "Inspect"
	inspect_button.custom_minimum_size.y = 30 # Explicit minimum height for the button
	inspect_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER # Center vertically if row is taller
	
	# This function is only used for cargo, so connect to the cargo inspection handler.
	inspect_button.pressed.connect(_on_inspect_cargo_pressed.bind(item_data))
	hbox.add_child(name_label)
	hbox.add_child(summary_label)
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
	_add_stat_row_with_button(overview_vbox, "  Top Speed:", "%.0f" % vehicle_data.get("top_speed", 0.0), "top_speed", vehicle_data)
	_add_stat_row_with_button(overview_vbox, "  Offroad:", "%.0f" % vehicle_data.get("offroad_capability", 0.0), "offroad_capability", vehicle_data)
	_add_stat_row_with_button(overview_vbox, "  Efficiency:", "%.0f" % vehicle_data.get("efficiency", 0.0), "efficiency", vehicle_data)
	_add_stat_row_with_button(overview_vbox, "  Cargo Capacity:", "%.0f" % vehicle_data.get("cargo_capacity", 0.0), "cargo_capacity", vehicle_data)
	_add_stat_row_with_button(overview_vbox, "  Weight Capacity:", "%.0f" % vehicle_data.get("weight_capacity", 0.0), "weight_capacity", vehicle_data)
	_add_stat_row_with_button(overview_vbox, "  Passenger Seats:", "%d" % vehicle_data.get("passenger_seats", 0), "passenger_seats", vehicle_data)


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

	# --- Button to view full convoy manifest ---
	var full_manifest_button = Button.new()
	full_manifest_button.text = "View Full Convoy Cargo Manifest"
	full_manifest_button.custom_minimum_size.y = 40 # Make it a decent size
	full_manifest_button.pressed.connect(_on_inspect_all_cargo_pressed)
	cargo_vbox.add_child(full_manifest_button)

	var separator = HSeparator.new()
	separator.custom_minimum_size.y = 15
	cargo_vbox.add_child(separator)

	# --- Title for this vehicle's cargo ---
	var vehicle_cargo_title = Label.new()
	vehicle_cargo_title.text = "Cargo in this Vehicle:"
	vehicle_cargo_title.add_theme_font_size_override("font_size", 16)
	vehicle_cargo_title.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	cargo_vbox.add_child(vehicle_cargo_title)

	var all_cargo_from_vehicle: Array = vehicle_data.get("cargo", [])
	var general_cargo_list: Array = []

	# Filter out parts that are also cargo
	for item_data in all_cargo_from_vehicle:
		if item_data is Dictionary and item_data.get("intrinsic_part_id") == null:
			general_cargo_list.append(item_data)

	if general_cargo_list.is_empty():
		var no_cargo_label = Label.new()
		no_cargo_label.text = "  No cargo items in this vehicle."
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

func _add_stat_row_with_button(parent: Container, label_text: String, stat_value_display: String, stat_type: String, vehicle_data: Dictionary):
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label_node = Label.new()
	label_node.text = label_text
	label_node.size_flags_vertical = Control.SIZE_SHRINK_CENTER # Align with button vertically

	var inspect_button = Button.new()
	inspect_button.text = stat_value_display
	# Let the button take its natural width and sit next to the label
	inspect_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inspect_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Style the button to be lighter and more distinct
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.4, 0.4, 0.4, 0.8) # A lighter gray
	style_box.set_content_margin_all(4) # Give it some padding
	style_box.corner_radius_top_left = 3
	style_box.corner_radius_top_right = 3
	style_box.corner_radius_bottom_left = 3
	style_box.corner_radius_bottom_right = 3
	inspect_button.add_theme_stylebox_override("normal", style_box)

	inspect_button.pressed.connect(_on_inspect_stat_pressed.bind(stat_type, vehicle_data))

	hbox.add_child(label_node)
	hbox.add_child(inspect_button)
	parent.add_child(hbox)

func _on_inspect_stat_pressed(stat_type: String, vehicle_data: Dictionary):
	var dialog = AcceptDialog.new()
	dialog.title = "Inspect " + stat_type.capitalize().replace("_", " ")

	var dialog_vbox = VBoxContainer.new()
	dialog_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(dialog_vbox)

	var final_stat_value: float = vehicle_data.get(stat_type, 0.0)
	var total_modifier: float = 0.0
	var modifiers_list: Array = [] # [{"part_name": "Engine", "modifier": 10}]

	# Combine parts from 'parts' and 'cargo' (with intrinsic_part_id)
	var all_vehicle_parts: Array = []
	if vehicle_data.has("parts") and vehicle_data.get("parts") is Array:
		all_vehicle_parts.append_array(vehicle_data.get("parts"))
	if vehicle_data.has("cargo") and vehicle_data.get("cargo") is Array:
		for item_data in vehicle_data.get("cargo"):
			if item_data is Dictionary and item_data.has("intrinsic_part_id") and item_data.get("intrinsic_part_id") != null:
				all_vehicle_parts.append(item_data)

	var modifier_key: String = ""
	match stat_type:
		"top_speed": modifier_key = "top_speed_add"
		"offroad_capability": modifier_key = "offroad_capability_add"
		"efficiency": modifier_key = "efficiency_add"
		"cargo_capacity": modifier_key = "cargo_capacity_add"
		"weight_capacity": modifier_key = "weight_capacity_add"
		"passenger_seats": # Special case, usually not modified by parts
			var seats_label = Label.new()
			seats_label.text = "Passenger Seats: %d\n\nNote: Passenger seats are typically a base property of the vehicle and not modified by individual parts in an additive manner." % final_stat_value
			seats_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			seats_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
			dialog_vbox.add_child(seats_label)
			get_tree().root.add_child(dialog)
			dialog.popup_centered_ratio(0.75)
			dialog.connect("confirmed", Callable(dialog, "queue_free"))
			dialog.connect("popup_hide", Callable(dialog, "queue_free"))
			return
		_:
			_add_grid_row(dialog_vbox, "Value", str(final_stat_value))
			get_tree().root.add_child(dialog)
			dialog.popup_centered_ratio(0.75)
			dialog.connect("confirmed", Callable(dialog, "queue_free"))
			dialog.connect("popup_hide", Callable(dialog, "queue_free"))
			return

	for part_item_data in all_vehicle_parts:
		if part_item_data is Dictionary and part_item_data.has(modifier_key):
			var modifier_value = part_item_data.get(modifier_key)
			if modifier_value != null and modifier_value != 0:
				total_modifier += float(modifier_value)
				modifiers_list.append({"part_name": part_item_data.get("name", "Unknown Part"), "modifier": modifier_value})

	var base_stat_value: float = final_stat_value - total_modifier

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 5)
	dialog_vbox.add_child(grid)

	_add_grid_row(grid, "Base Value", "%.1f" % base_stat_value)
	_add_grid_row(grid, "Total Modifier", "%+.1f" % total_modifier)
	_add_grid_row(grid, "Final Value", "%.1f" % final_stat_value)

	if not modifiers_list.is_empty():
		var modifiers_label = Label.new()
		modifiers_label.text = "\nModifiers from Parts:"
		modifiers_label.add_theme_font_size_override("font_size", 16)
		modifiers_label.add_theme_color_override("font_color", Color.CYAN)
		dialog_vbox.add_child(modifiers_label)

		for mod_info in modifiers_list:
			var part_name_label = Label.new()
			part_name_label.text = "  %s: %+.1f" % [mod_info.part_name, mod_info.modifier]
			dialog_vbox.add_child(part_name_label)
	else:
		var no_mods_label = Label.new()
		no_mods_label.text = "\nNo part modifiers found for this stat."
		dialog_vbox.add_child(no_mods_label)

	get_tree().root.add_child(dialog)
	dialog.popup_centered_ratio(0.75)
	dialog.connect("confirmed", Callable(dialog, "queue_free"))
	dialog.connect("popup_hide", Callable(dialog, "queue_free"))

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

	_populate_part_details_dialog(dialog_vbox, part_data)
	get_tree().root.add_child(dialog)
	dialog.popup_centered_ratio(0.75)
	dialog.connect("confirmed", Callable(dialog, "queue_free"))
	dialog.connect("popup_hide", Callable(dialog, "queue_free"))

func _on_inspect_cargo_pressed(item_data: Dictionary):
	print("ConvoyVehicleMenu: Inspecting cargo item: ", item_data.get("name", "Unknown Item"))

	var dialog = AcceptDialog.new()
	dialog.title = "Inspect Cargo: " + item_data.get("name", "Item Details")
	
	var dialog_vbox = VBoxContainer.new()
	dialog_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(dialog_vbox)

	# Use a GridContainer for a cleaner look, similar to part inspection
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 5)
	dialog_vbox.add_child(grid)

	# Iterate through keys to display all relevant data
	for key in item_data:
		# Skip some less useful or complex keys for this simple display
		if key in ["parts", "log", "creation_date", "distributor_id", "origin_sett_id", "packed_vehicle", "pending_deletion", "recipient", "vehicle_id", "vendor_id", "warehouse_id", "class_id", "intrinsic_part_id"]:
			continue
		if item_data[key] != null: # Only show non-null values
			_add_grid_row(grid, key.capitalize().replace("_", " "), str(item_data[key]))
			
	get_tree().root.add_child(dialog)
	dialog.popup_centered_ratio(0.75)
	dialog.connect("confirmed", Callable(dialog, "queue_free"))
	dialog.connect("popup_hide", Callable(dialog, "queue_free"))

func _on_inspect_all_cargo_pressed():
	if _current_convoy_data:
		print("ConvoyVehicleMenu: Requesting to open full cargo menu.")
		emit_signal("inspect_all_convoy_cargo_requested", _current_convoy_data)
	else:
		printerr("ConvoyVehicleMenu: _current_convoy_data is not set. Cannot open full cargo manifest.")

func _populate_part_details_dialog(parent_vbox: VBoxContainer, part_data: Dictionary):

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

func _on_title_label_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _current_convoy_data:
			print("ConvoyVehicleMenu: Title clicked. Emitting 'return_to_convoy_overview_requested'.")
			emit_signal("return_to_convoy_overview_requested", _current_convoy_data)
			get_viewport().set_input_as_handled()

func _on_gdm_convoy_data_updated(all_convoy_data: Array) -> void:
	# Update _current_convoy_data if this convoy is present in the update
	if not _current_convoy_data or not _current_convoy_data.has("convoy_id"):
		return
	var current_id = str(_current_convoy_data.get("convoy_id"))
	for convoy in all_convoy_data:
		if convoy.has("convoy_id") and str(convoy.get("convoy_id")) == current_id:
			_current_convoy_data = convoy.duplicate(true)
			# Optionally, refresh the UI if needed
			initialize_with_data(_current_convoy_data)
			break

func _update_mechanic_button_enabled():
	var enabled := false
	if _current_convoy_data and _current_convoy_data is Dictionary:
		if _current_convoy_data.has("in_settlement"):
			enabled = bool(_current_convoy_data.get("in_settlement"))
		else:
			var gdm = get_node_or_null("/root/GameDataManager")
			if is_instance_valid(gdm) and gdm.has_method("get_settlement_name_from_coords"):
				var sx = int(roundf(float(_current_convoy_data.get("x", -9999.0))))
				var sy = int(roundf(float(_current_convoy_data.get("y", -9999.0))))
				var s_name = gdm.get_settlement_name_from_coords(sx, sy)
				enabled = s_name != null and String(s_name) != ""
	if is_instance_valid(mechanic_button_scene_node):
		mechanic_button_scene_node.disabled = not enabled
