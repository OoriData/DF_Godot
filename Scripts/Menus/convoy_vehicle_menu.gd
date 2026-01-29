extends MenuBase

const VehicleModel = preload("res://Scripts/Data/Models/Vehicle.gd")

# Back signal provided by MenuBase
# Signal to open the full cargo manifest for the entire convoy
signal return_to_convoy_overview_requested(convoy_data)
signal inspect_all_convoy_cargo_requested(convoy_data)
signal inspect_specific_convoy_cargo_requested(convoy_data, item_data)

# @onready variables for UI elements
@onready var title_label: Label = $MainVBox/TitleLabel
@onready var vehicle_option_button: OptionButton = $MainVBox/VehicleOptionButton
@onready var back_button: Button = $MainVBox/BackButton

@onready var overview_vbox: VBoxContainer = $MainVBox/VehicleTabContainer/Overview/OverviewVBox
@onready var parts_vbox: VBoxContainer = $MainVBox/VehicleTabContainer/Parts/PartsScroll/PartsVBox
@onready var cargo_vbox: VBoxContainer = $MainVBox/VehicleTabContainer/Cargo/CargoVBox
@onready var back_to_mechanic_button: Button = $MainVBox/BackButton # repurpose later if needed
@onready var mechanics_embed: Node = $MainVBox/VehicleTabContainer/Service/ServiceVBox/MechanicsEmbed

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
@onready var _mechanics_service: Node = get_node_or_null("/root/MechanicsService")
@onready var _convoy_service: Node = get_node_or_null("/root/ConvoyService")

var current_vehicle_list: Array = []
var _current_convoy_data: Dictionary # To store the full convoy data
var _selected_vehicle_id: String = "" # Persist selection across refreshes
var _last_refresh_convoy_id: String = "" # Avoid spamming refresh requests

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
		title_label.add_theme_color_override("font_color", Color.YELLOW)
		title_label.mouse_filter = Control.MOUSE_FILTER_STOP # Allow it to receive mouse events
		title_label.gui_input.connect(_on_title_label_gui_input)

	# Configuration for Service tab
	if is_instance_valid(mechanics_embed) and mechanics_embed.has_method("set_embedded_mode"):
		mechanics_embed.set_embedded_mode(true)

	# Check new VBox validity
	if not is_instance_valid(overview_vbox) or not is_instance_valid(parts_vbox) or not is_instance_valid(cargo_vbox):
		printerr("ConvoyVehicleMenu: CRITICAL - One or more tab VBox nodes are not valid in _ready()!")
		return # Stop further initialization

	_clear_all_tabs() # Now safe to call
	_show_initial_detail_message("Initializing...") # Now safe to call

	# Subscribe to canonical events (store convoys_changed handled by MenuBase).
	if is_instance_valid(_hub) and _hub.has_signal("convoy_updated") and not _hub.convoy_updated.is_connected(_on_hub_convoy_updated):
		_hub.convoy_updated.connect(_on_hub_convoy_updated)

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

func initialize_with_data(data_or_id: Variant, extra_arg: Variant = null) -> void:
	# Ensure this function runs only after the node is fully ready and @onready vars are set.
	if not is_node_ready():
		printerr("ConvoyVehicleMenu: initialize_with_data called BEFORE node is ready! Deferring.")
		call_deferred("initialize_with_data", data_or_id, extra_arg)
		return

	if data_or_id is Dictionary:
		convoy_id = String((data_or_id as Dictionary).get("convoy_id", (data_or_id as Dictionary).get("id", "")))
	else:
		convoy_id = String(data_or_id)

	# Always initialize the embedded mechanics menu with the same context.
	# When this menu is opened with an id (common post-refactor), the service tab
	# still needs convoy_id so it can refresh from GameStore when shown.
	if is_instance_valid(mechanics_embed) and mechanics_embed.has_method("initialize_with_data"):
		mechanics_embed.initialize_with_data(data_or_id)

	if data_or_id is Dictionary:
		print("ConvoyVehicleMenu: initialize_with_data called. Data keys: ", (data_or_id as Dictionary).keys())
		print("ConvoyVehicleMenu: vehicle_details_list: ", (data_or_id as Dictionary).get("vehicle_details_list", []))
		if (data_or_id as Dictionary).has("vehicle_details_list") and (data_or_id as Dictionary)["vehicle_details_list"].size() > 0:
			print("ConvoyVehicleMenu: First vehicle keys: ", (data_or_id as Dictionary)["vehicle_details_list"][0].keys())

	if data_or_id is Dictionary and is_instance_valid(title_label):
		_current_convoy_data = (data_or_id as Dictionary).duplicate(true) # Store the full convoy data
		title_label.text = _current_convoy_data.get("convoy_name", _current_convoy_data.get("name", "Convoy"))

	# Deterministically sort vehicles for stable ordering
	# Fallback to the canonical 'vehicles' array when 'vehicle_details_list' is absent.
	if data_or_id is Dictionary:
		current_vehicle_list = _stable_sort_vehicles(
			(data_or_id as Dictionary).get("vehicle_details_list", (data_or_id as Dictionary).get("vehicles", []))
		)

	# If vehicle details are missing, request a single-convoy refresh to populate them
	var convoy_id_local = convoy_id
	if current_vehicle_list.is_empty() and convoy_id_local != "" and is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
		if _last_refresh_convoy_id != convoy_id_local:
			print("ConvoyVehicleMenu: Vehicles missing; requesting single-convoy refresh for id=", convoy_id_local)
			_last_refresh_convoy_id = convoy_id_local
			_convoy_service.refresh_single(convoy_id_local)

	# (embedded mechanics menu already initialized above)

	if data_or_id is Dictionary and is_instance_valid(vehicle_option_button):
		print("ConvoyVehicleMenu: Populating VehicleOptionButton. Number of vehicles from data: ", current_vehicle_list.size())
		vehicle_option_button.clear()
		if current_vehicle_list.is_empty():
			vehicle_option_button.add_item("No Vehicles Available")
			vehicle_option_button.disabled = true
			print("ConvoyVehicleMenu: No vehicles found in list.")
			var msg: String = "No vehicles in this convoy."
			# If we just requested a refresh, inform the user we're loading.
			if convoy_id != "" and is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
				msg = "Loading vehicles..."
			_show_initial_detail_message(msg)
		else:
			vehicle_option_button.disabled = false
			for i in range(current_vehicle_list.size()):
				var vehicle_data = current_vehicle_list[i]
				if vehicle_data is Dictionary:
					var vehicle_name = vehicle_data.get("name", "Unnamed Vehicle %s" % (i + 1))
					var make_model = vehicle_data.get("make_model", "N/A")
					vehicle_option_button.add_item("%s (%s)" % [vehicle_name, make_model], i)
					# Persist id as metadata for stability
					var vid: String = String(vehicle_data.get("vehicle_id", ""))
					vehicle_option_button.set_item_metadata(i, vid)
			print("ConvoyVehicleMenu: VehicleOptionButton populated. Item count: ", vehicle_option_button.get_item_count())
			# Select previously selected vehicle if present; otherwise first
			var target_index: int = 0
			if _selected_vehicle_id != "":
				for idx in range(vehicle_option_button.get_item_count()):
					var meta = vehicle_option_button.get_item_metadata(idx)
					if String(meta) == _selected_vehicle_id:
						target_index = idx
						break
			if vehicle_option_button.get_item_count() > 0:
				vehicle_option_button.select(target_index)
				_on_vehicle_selected(target_index)
				# Vehicles present; clear refresh guard for future convoys
				_last_refresh_convoy_id = ""
			else: # Should not happen if current_vehicle_list was not empty, but as a fallback
				print("ConvoyVehicleMenu: OptionButton is empty after trying to populate. Showing initial message.")
				_show_initial_detail_message("Select a vehicle from the dropdown to view details.")
	else:
		printerr("ConvoyVehicleMenu: CRITICAL - VehicleOptionButton node NOT found during initialize_with_data.")
		_show_initial_detail_message("Error: Vehicle selection UI not available.")

	# Ensure MenuBase subscriptions and store-driven updates are engaged for this menu
	super.initialize_with_data(data_or_id, extra_arg)

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
		# Persist selection by vehicle_id for stable reselect after refresh
		var vid := String(selected_vehicle_data.get("vehicle_id", ""))
		if vid != "":
			_selected_vehicle_id = vid
		# Keep Service tab mechanics selection in sync
		if is_instance_valid(mechanics_embed) and mechanics_embed.has_method("set_selected_vehicle_index"):
			mechanics_embed.set_selected_vehicle_index(index)

func _update_ui(convoy: Dictionary) -> void:
	_current_convoy_data = convoy.duplicate(true)
	if is_instance_valid(title_label):
		title_label.text = _current_convoy_data.get("convoy_name", title_label.text)
	# Rebuild vehicle list and selection
	current_vehicle_list = _stable_sort_vehicles(
		_current_convoy_data.get("vehicle_details_list", _current_convoy_data.get("vehicles", []))
	)
	if is_instance_valid(vehicle_option_button):
		vehicle_option_button.clear()
		if current_vehicle_list.is_empty():
			vehicle_option_button.add_item("No Vehicles Available")
			vehicle_option_button.disabled = true
			_show_initial_detail_message("No vehicles in this convoy.")
		else:
			vehicle_option_button.disabled = false
			for i in range(current_vehicle_list.size()):
				var vehicle_data = current_vehicle_list[i]
				if vehicle_data is Dictionary:
					var vehicle_name = vehicle_data.get("name", "Unnamed Vehicle %s" % (i + 1))
					var make_model = vehicle_data.get("make_model", "N/A")
					vehicle_option_button.add_item("%s (%s)" % [vehicle_name, make_model], i)
					var vid := String(vehicle_data.get("vehicle_id", ""))
					vehicle_option_button.set_item_metadata(i, vid)
			var target_index := 0
			if _selected_vehicle_id != "":
				for idx in range(vehicle_option_button.get_item_count()):
					var meta = vehicle_option_button.get_item_metadata(idx)
					if String(meta) == _selected_vehicle_id:
						target_index = idx
						break
			if vehicle_option_button.get_item_count() > 0:
				vehicle_option_button.select(target_index)
				_on_vehicle_selected(target_index)
	# Do not call super.initialize_with_data here; this is a UI refresh

func _add_styled_detail_row(parent: Container, label_text: String, value_text: String, item_index: int, value_autowrap: bool = false):
	var outer_row := HBoxContainer.new()
	outer_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bg_panel := PanelContainer.new()
	bg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	if item_index % 2 == 0:
		sb.bg_color = Color(0.13, 0.15, 0.19, 0.8)
	else:
		sb.bg_color = Color(0.10, 0.12, 0.16, 0.8)
	sb.set_content_margin_all(6)
	bg_panel.add_theme_stylebox_override("panel", sb)
	
	outer_row.add_child(bg_panel)

	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 10)
	bg_panel.add_child(content_row)

	var label_node = Label.new()
	label_node.text = label_text
	label_node.custom_minimum_size.x = 120
	label_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var value_node = Label.new()
	value_node.text = value_text
	value_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_node.clip_text = true
	value_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if value_autowrap:
		value_node.autowrap_mode = TextServer.AUTOWRAP_WORD
	
	content_row.add_child(label_node)
	content_row.add_child(value_node)
	parent.add_child(outer_row)

func _add_inspectable_item_row(parent: Container, item_name: String, agg_data: Dictionary, item_index: int):
	# agg_data contains: quantity, sample, total_weight, total_volume
	var item_data = agg_data.sample

	var outer_row := HBoxContainer.new()
	outer_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_row.mouse_filter = Control.MOUSE_FILTER_PASS # For hover effects

	var bg_panel := PanelContainer.new()
	bg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	if item_index % 2 == 0:
		sb.bg_color = Color(0.13, 0.15, 0.19, 0.8)
	else:
		sb.bg_color = Color(0.10, 0.12, 0.16, 0.8)
	sb.set_content_margin_all(6)
	bg_panel.add_theme_stylebox_override("panel", sb)
	
	outer_row.add_child(bg_panel)

	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 10)
	bg_panel.add_child(content_row)

	# Quantity Badge
	var qty_badge := Label.new()
	qty_badge.text = "x%d" % agg_data.quantity
	qty_badge.custom_minimum_size.x = 40
	qty_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qty_badge.modulate = Color(0.8, 0.85, 0.9, 1)
	content_row.add_child(qty_badge)

	# Item Name
	var name_label := Label.new()
	name_label.text = item_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content_row.add_child(name_label)

	# Weight
	var weight_label := Label.new()
	weight_label.text = "%.1f kg" % agg_data.total_weight
	weight_label.custom_minimum_size.x = 70
	weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weight_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weight_label.modulate = Color.LIGHT_GRAY
	content_row.add_child(weight_label)

	# Volume
	var volume_label := Label.new()
	volume_label.text = "%.2f m³" % agg_data.total_volume
	volume_label.custom_minimum_size.x = 70
	volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	volume_label.modulate = Color.LIGHT_GRAY
	content_row.add_child(volume_label)

	# Inspect Button
	var inspect_button = Button.new()
	inspect_button.text = "Inspect"
	inspect_button.custom_minimum_size.x = 80
	inspect_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inspect_button.pressed.connect(_on_inspect_cargo_pressed.bind(item_data))
	content_row.add_child(inspect_button)

	# Hover effect
	outer_row.mouse_entered.connect(func():
		sb.bg_color = sb.bg_color.lightened(0.1)
	)
	outer_row.mouse_exited.connect(func():
		if item_index % 2 == 0:
			sb.bg_color = Color(0.13, 0.15, 0.19, 0.8)
		else:
			sb.bg_color = Color(0.10, 0.12, 0.16, 0.8)
	)

	parent.add_child(outer_row)

func _add_inspectable_part_row(parent: Container, part_data: Dictionary, item_index: int):
	var outer_row := HBoxContainer.new()
	outer_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_row.mouse_filter = Control.MOUSE_FILTER_PASS # For hover effects

	var bg_panel := PanelContainer.new()
	bg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	if item_index % 2 == 0:
		sb.bg_color = Color(0.13, 0.15, 0.19, 0.8)
	else:
		sb.bg_color = Color(0.10, 0.12, 0.16, 0.8)
	sb.set_content_margin_all(6)
	bg_panel.add_theme_stylebox_override("panel", sb)
	
	outer_row.add_child(bg_panel)

	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 10)
	bg_panel.add_child(content_row)

	# Part Name
	var name_label := Label.new()
	name_label.text = part_data.get("name", "Unknown Part")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content_row.add_child(name_label)

	# Part Slot
	var slot_label := Label.new()
	slot_label.text = String(part_data.get("slot", "other")).capitalize().replace("_", " ")
	slot_label.custom_minimum_size.x = 150
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_label.modulate = Color.LIGHT_GRAY
	content_row.add_child(slot_label)

	# Inspect Button
	var inspect_button = Button.new()
	inspect_button.text = "Inspect"
	inspect_button.custom_minimum_size.x = 80
	inspect_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inspect_button.pressed.connect(_on_inspect_part_pressed.bind(part_data))
	content_row.add_child(inspect_button)

	# Hover effect
	outer_row.mouse_entered.connect(func():
		sb.bg_color = sb.bg_color.lightened(0.1)
	)
	outer_row.mouse_exited.connect(func():
		if item_index % 2 == 0:
			sb.bg_color = Color(0.13, 0.15, 0.19, 0.8)
		else:
			sb.bg_color = Color(0.10, 0.12, 0.16, 0.8)
	)

	parent.add_child(outer_row)

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

	# Basic Info Section
	var basic_info_title = Label.new()
	basic_info_title.text = "Basic Information:"
	basic_info_title.add_theme_font_size_override("font_size", 18)
	basic_info_title.add_theme_color_override("font_color", Color.YELLOW)
	overview_vbox.add_child(basic_info_title)

	var details = [
		{"label": "Name:", "value": String(vehicle_data.get("name", "N/A")), "wrap": false},
		{"label": "Make/Model:", "value": vehicle_data.get("make_model", "N/A"), "wrap": false},
		{"label": "Description:", "value": vehicle_data.get("description", "No description."), "wrap": true},
		{"label": "Color:", "value": vehicle_data.get("color", "N/A").capitalize(), "wrap": false},
		{"label": "Base Description:", "value": vehicle_data.get("base_desc", "No detailed description."), "wrap": true},
		{"label": "Shape:", "value": vehicle_data.get("shape", "N/A").capitalize().replace("_", " "), "wrap": false},
		{"label": "Base Value:", "value": "$%s" % int(vehicle_data.get("base_value", 0.0)), "wrap": false},
		{"label": "Current Value:", "value": "$%s" % int(vehicle_data.get("value", 0.0)), "wrap": false}
	]
	for i in range(details.size()):
		var detail = details[i]
		_add_styled_detail_row(overview_vbox, detail.label, detail.value, i, detail.wrap)

	# Stats Section
	var stats_title = Label.new()
	stats_title.text = "Statistics:"
	stats_title.add_theme_font_size_override("font_size", 18) # Make title slightly larger
	stats_title.add_theme_color_override("font_color", Color.YELLOW) # Highlight title
	overview_vbox.add_child(stats_title)

	var stats = [
		{"label": "Top Speed:", "value": "%.0f" % vehicle_data.get("top_speed", 0.0), "type": "top_speed"},
		{"label": "Offroad:", "value": "%.0f" % vehicle_data.get("offroad_capability", 0.0), "type": "offroad_capability"},
		{"label": "Efficiency:", "value": "%.0f" % vehicle_data.get("efficiency", 0.0), "type": "efficiency"},
		{"label": "Cargo Capacity:", "value": "%.0f" % vehicle_data.get("cargo_capacity", 0.0), "type": "cargo_capacity"},
		{"label": "Weight Capacity:", "value": "%.0f" % vehicle_data.get("weight_capacity", 0.0), "type": "weight_capacity"},
		{"label": "Passenger Seats:", "value": "%d" % vehicle_data.get("passenger_seats", 0), "type": "passenger_seats"}
	]
	for i in range(stats.size()):
		var stat = stats[i]
		_add_stat_row_with_button(overview_vbox, stat.label, stat.value, stat.type, vehicle_data, i)


func _populate_parts_tab(vehicle_data: Dictionary):
	if not is_instance_valid(parts_vbox): return
	var v = VehicleModel.new(vehicle_data)
	var all_cargo_from_vehicle: Array = v.cargo
	var all_parts_from_vehicle: Array = v.parts
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

	var has_parts_to_display = false
	var part_row_index = 0
	for category_name in PART_CATEGORY_ORDER:
		var parts_in_category = categorized_parts.get(category_name)
		if parts_in_category and not parts_in_category.is_empty():
			has_parts_to_display = true
			# Add category sub-header
			var sep = HSeparator.new()
			sep.custom_minimum_size.y = 8
			parts_vbox.add_child(sep)
			var category_label = Label.new()
			category_label.text = category_name + ":"
			# Make category headers more prominent and match menu accent color
			category_label.add_theme_font_size_override("font_size", 16)
			category_label.add_theme_color_override("font_color", Color.YELLOW)
			parts_vbox.add_child(category_label)

			# Sort parts within each category deterministically by name (lower), then slot, then id
			parts_in_category.sort_custom(func(a, b): return String(a.get("name", "")).to_lower() < String(b.get("name", "")).to_lower())

			for part_item_data in parts_in_category:
				_add_inspectable_part_row(parts_vbox, part_item_data, part_row_index)
				part_row_index += 1

	if not has_parts_to_display:
		var no_parts_label = Label.new()
		no_parts_label.text = "\nNo vehicle parts installed."
		no_parts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_parts_label.modulate = Color.GRAY
		parts_vbox.add_child(no_parts_label)

func _populate_cargo_tab(vehicle_data: Dictionary):
	if not is_instance_valid(cargo_vbox): return

	# Add a header row for the cargo list
	var header_hbox = HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_theme_constant_override("separation", 10)
	
	var qty_header = Label.new()
	qty_header.text = "Qty"
	qty_header.custom_minimum_size.x = 40
	qty_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_header.modulate = Color.LIGHT_GRAY
	header_hbox.add_child(qty_header)
	
	var name_header = Label.new()
	name_header.text = "Item Name"
	name_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_header.modulate = Color.LIGHT_GRAY
	header_hbox.add_child(name_header)
	
	var weight_header = Label.new()
	weight_header.text = "Weight"
	weight_header.custom_minimum_size.x = 70
	weight_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weight_header.modulate = Color.LIGHT_GRAY
	header_hbox.add_child(weight_header)
	
	var volume_header = Label.new()
	volume_header.text = "Volume"
	volume_header.custom_minimum_size.x = 70
	volume_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_header.modulate = Color.LIGHT_GRAY
	header_hbox.add_child(volume_header)
	
	var inspect_header_placeholder = Control.new() # Placeholder to align with button
	inspect_header_placeholder.custom_minimum_size.x = 80 # Approx width of "Inspect" button
	header_hbox.add_child(inspect_header_placeholder)
	
	cargo_vbox.add_child(header_hbox)
	var header_sep = HSeparator.new()
	header_sep.custom_minimum_size.y = 5
	cargo_vbox.add_child(header_sep)

	var v = VehicleModel.new(vehicle_data)
	var all_cargo_from_vehicle: Array = v.cargo
	var general_cargo_list: Array = []

	# Filter out parts that are also cargo
	for item_data in all_cargo_from_vehicle:
		if item_data is Dictionary and item_data.get("intrinsic_part_id") == null:
			general_cargo_list.append(item_data)

	if general_cargo_list.is_empty():
		var no_cargo_label = Label.new()
		no_cargo_label.text = "  No cargo items in this vehicle."
		no_cargo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_cargo_label.modulate = Color.GRAY
		cargo_vbox.add_child(no_cargo_label)
		return

	# Aggregate cargo items by name, now including weight and volume
	var aggregated_cargo: Dictionary = {}
	for cargo_item in general_cargo_list:
		var item_name = cargo_item.get("name", "Unknown Item")
		if not aggregated_cargo.has(item_name):
			aggregated_cargo[item_name] = {
				"quantity": 0, 
				"sample": cargo_item, 
				"total_weight": 0.0, 
				"total_volume": 0.0
			}
		
		var item_qty = int(cargo_item.get("quantity", 1))
		aggregated_cargo[item_name]["quantity"] += item_qty

		var unit_weight = 0.0
		if cargo_item.has("unit_weight") and cargo_item.get("unit_weight") != null:
			unit_weight = float(cargo_item.get("unit_weight", 0.0))
		elif cargo_item.has("weight") and cargo_item.get("weight") != null:
			if item_qty > 0:
				unit_weight = float(cargo_item.get("weight", 0.0)) / float(item_qty)
		
		var unit_volume = 0.0
		if cargo_item.has("unit_volume") and cargo_item.get("unit_volume") != null:
			unit_volume = float(cargo_item.get("unit_volume", 0.0))
		elif cargo_item.has("volume") and cargo_item.get("volume") != null:
			if item_qty > 0:
				unit_volume = float(cargo_item.get("volume", 0.0)) / float(item_qty)

		aggregated_cargo[item_name]["total_weight"] += unit_weight * item_qty
		aggregated_cargo[item_name]["total_volume"] += unit_volume * item_qty

	# Display aggregated cargo using the new styled row function
	var item_index = 0
	var sorted_item_names = aggregated_cargo.keys()
	sorted_item_names.sort() # Sort for deterministic order
	for item_name in sorted_item_names:
		var agg_data = aggregated_cargo[item_name]
		_add_inspectable_item_row(cargo_vbox, item_name, agg_data, item_index)
		item_index += 1

	# --- Button to view full convoy manifest at the bottom ---
	var bottom_separator = HSeparator.new()
	bottom_separator.custom_minimum_size.y = 15
	cargo_vbox.add_child(bottom_separator)

	var full_manifest_button = Button.new()
	full_manifest_button.text = "View Full Convoy Cargo Manifest"
	full_manifest_button.custom_minimum_size.y = 40 # Make it a decent size
	full_manifest_button.pressed.connect(_on_inspect_all_cargo_pressed)
	cargo_vbox.add_child(full_manifest_button)

func _add_stat_row_with_button(parent: Container, label_text: String, stat_value_display: String, stat_type: String, vehicle_data: Dictionary, item_index: int):
	var outer_row := HBoxContainer.new()
	outer_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_row.mouse_filter = Control.MOUSE_FILTER_PASS

	var bg_panel := PanelContainer.new()
	bg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	if item_index % 2 == 0:
		sb.bg_color = Color(0.13, 0.15, 0.19, 0.8)
	else:
		sb.bg_color = Color(0.10, 0.12, 0.16, 0.8)
	sb.set_content_margin_all(6)
	bg_panel.add_theme_stylebox_override("panel", sb)
	
	outer_row.add_child(bg_panel)

	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 10)
	bg_panel.add_child(content_row)

	var label_node = Label.new()
	label_node.text = label_text
	label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_node.clip_text = true
	label_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content_row.add_child(label_node)

	var inspect_button = Button.new()
	inspect_button.text = stat_value_display
	inspect_button.custom_minimum_size.x = 80
	inspect_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inspect_button.pressed.connect(_on_inspect_stat_pressed.bind(stat_type, vehicle_data))
	content_row.add_child(inspect_button)

	# Hover effect
	outer_row.mouse_entered.connect(func():
		sb.bg_color = sb.bg_color.lightened(0.1)
	)
	outer_row.mouse_exited.connect(func():
		if item_index % 2 == 0:
			sb.bg_color = Color(0.13, 0.15, 0.19, 0.8)
		else:
			sb.bg_color = Color(0.10, 0.12, 0.16, 0.8)
	)

	parent.add_child(outer_row)

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
	var v = VehicleModel.new(vehicle_data)
	all_vehicle_parts.append_array(v.parts)
	for item_data in v.cargo:
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

	# If part is removable and we can resolve vehicle_id and part_id, add a Remove button
	var removable := false
	var rv: Variant = part_data.get("removable", false)
	if rv is bool:
		removable = rv
	elif rv is int:
		removable = int(rv) != 0
	elif rv is String:
		var rvs := String(rv).to_lower()
		removable = (rvs == "true" or rvs == "1" or rvs == "yes")

	if removable:
		# Resolve context ids
		var convoy_id_local := ""
		if _current_convoy_data is Dictionary:
			convoy_id_local = String(_current_convoy_data.get("convoy_id", ""))
		var vehicle_id := String(part_data.get("vehicle_id", ""))
		if vehicle_id == "":
			# Fallback: try currently selected vehicle from dropdown
			var idx := 0
			if is_instance_valid(vehicle_option_button):
				idx = vehicle_option_button.get_selected_id() if vehicle_option_button.get_selected_id() != -1 else vehicle_option_button.get_selected()
			if idx >= 0 and idx < current_vehicle_list.size():
				var vdict: Dictionary = current_vehicle_list[idx]
				vehicle_id = String(vdict.get("vehicle_id", ""))
		var part_id := String(part_data.get("part_id", part_data.get("intrinsic_part_id", "")))
		if convoy_id_local != "" and vehicle_id != "" and part_id != "":
			var remove_btn := Button.new()
			remove_btn.text = "Remove"
			remove_btn.custom_minimum_size.y = 36
			remove_btn.add_theme_color_override("font_color", Color(1,0.4,0.4))
			remove_btn.pressed.connect(func():
				if is_instance_valid(_mechanics_service) and _mechanics_service.has_method("detach_part"):
					print("ConvoyVehicleMenu: Requesting detach part_id=", part_id, " from vehicle=", vehicle_id)
					_mechanics_service.detach_part(convoy_id_local, vehicle_id, part_id)
				else:
					printerr("ConvoyVehicleMenu: MechanicsService missing detach_part()")
				# Close dialog immediately; UI will refresh on convoy updates
				dialog.hide()
				dialog.queue_free()
			)
			# Spacer then button
			var spacer := HSeparator.new()
			spacer.custom_minimum_size.y = 8
			dialog_vbox.add_child(spacer)
			dialog_vbox.add_child(remove_btn)
	get_tree().root.add_child(dialog)
	dialog.popup_centered_ratio(0.75)
	dialog.connect("confirmed", Callable(dialog, "queue_free"))
	dialog.connect("popup_hide", Callable(dialog, "queue_free"))

func _on_inspect_cargo_pressed(item_data: Dictionary):
	if _current_convoy_data:
		print("ConvoyVehicleMenu: Requesting to inspect specific cargo item: ", item_data.get("name", "Unknown Item"))
		emit_signal("inspect_specific_convoy_cargo_requested", _current_convoy_data, item_data)
	else:
		printerr("ConvoyVehicleMenu: _current_convoy_data is not set. Cannot inspect specific cargo.")

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
	perf_mods_label.add_theme_color_override("font_color", Color.YELLOW)
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
	resource_label.add_theme_color_override("font_color", Color.YELLOW)
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

# Store-driven refresh handled by MenuBase


func _on_hub_convoy_updated(updated_convoy_data: Dictionary) -> void:
	# Some services (mechanics/routes) emit point updates; reflect them here.
	if not (_current_convoy_data is Dictionary) or not _current_convoy_data.has("convoy_id"):
		return
	if str(updated_convoy_data.get("convoy_id", "")) != str(_current_convoy_data.get("convoy_id")):
		return
	_current_convoy_data = updated_convoy_data.duplicate(true)
	initialize_with_data(_current_convoy_data)

# Helper: deterministically sort vehicles by name, make_model, then vehicle_id
func _stable_sort_vehicles(vehicles: Array) -> Array:
	if not (vehicles is Array):
		return []
	var copy := []
	for v in vehicles:
		if v is Dictionary:
			copy.append(v)
	copy.sort_custom(func(a, b):
		var an := String(a.get("name", ""))
		var bn := String(b.get("name", ""))
		an = an.to_lower()
		bn = bn.to_lower()
		if an == bn:
			var am := String(a.get("make_model", ""))
			var bm := String(b.get("make_model", ""))
			am = am.to_lower()
			bm = bm.to_lower()
			if am == bm:
				var aid := String(a.get("vehicle_id", ""))
				var bid := String(b.get("vehicle_id", ""))
				return aid < bid
			return am < bm
		return an < bn)
	return copy
