extends Control

# Signal that MenuManager will listen for to go back
signal back_requested
signal find_route_requested(convoy_data, destination_data)
signal return_to_convoy_overview_requested(convoy_data)

var convoy_data_received: Dictionary
var _route_selection_menu_instance: Control = null

# @onready variables for UI elements
@onready var title_label: Label = $MainVBox/TitleLabel
@onready var scroll_container: ScrollContainer = $MainVBox/ScrollContainer
@onready var content_vbox: VBoxContainer = $MainVBox/ScrollContainer/ContentVBox
@onready var back_button: Button = $MainVBox/BackButton
@onready var main_vbox: VBoxContainer = $MainVBox

# Preload the scene for the route selection menu
const RouteSelectionMenuScene = preload("res://Scenes/RouteSelectionMenu.tscn")

func _ready():
	# Connect the back button signal
	if is_instance_valid(back_button):
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed)
	
	# Make the title label clickable to return to the convoy overview
	if is_instance_valid(title_label):
		title_label.mouse_filter = Control.MOUSE_FILTER_STOP # Allow it to receive mouse events
		title_label.gui_input.connect(_on_title_label_gui_input)
	else:
		printerr("ConvoyJourneyMenu: CRITICAL - TitleLabel node NOT found or is not a Label.")

	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("route_info_ready", Callable(self, "_on_route_info_ready")):
			gdm.route_info_ready.connect(_on_route_info_ready)
	else:
		printerr("ConvoyJourneyMenu: Could not connect to GameDataManager signals.")

	# Remove the placeholder label if it exists
	if content_vbox.has_node("PlaceholderLabel"):
		var placeholder = content_vbox.get_node("PlaceholderLabel")
		if is_instance_valid(placeholder):
			placeholder.queue_free()

func _on_back_button_pressed():
	print("ConvoyJourneyMenu: Back button pressed. Emitting 'back_requested' signal.")
	# If the route selection menu is open, this back button shouldn't be clickable,
	# but as a safeguard, we ensure it's closed if we go back.
	if is_instance_valid(_route_selection_menu_instance):
		_route_selection_menu_instance.queue_free()
	emit_signal("back_requested")

func _process(delta: float):
	pass

func _physics_process(delta: float):
	pass

func initialize_with_data(data: Dictionary):
	print("ConvoyJourneyMenu: Initialized with data.") # DEBUG

	# Store the received data for potential use by the title click
	# Duplicate to avoid modifying the original if needed elsewhere
	convoy_data_received = data.duplicate()

	for child in content_vbox.get_children():
		child.queue_free()

	var journey_data: Dictionary = data.get("journey", {})
	var gdm = get_node_or_null("/root/GameDataManager")

	if is_instance_valid(title_label):
		var convoy_name = data.get("convoy_name", "Convoy")
		title_label.text = convoy_name + " - " + ("Journey Details" if not journey_data.is_empty() else "Journey Planner")

	if journey_data.is_empty():
		_populate_destination_list()
		return

	# Current Location
	var current_loc_label = Label.new()
	current_loc_label.text = "Current Location: (%.2f, %.2f)" % [data.get("x", 0.0), data.get("y", 0.0)]
	content_vbox.add_child(current_loc_label)
	content_vbox.add_child(HSeparator.new())

	# Origin
	var origin_x = journey_data.get("origin_x")
	var origin_y = journey_data.get("origin_y")
	var origin_label = Label.new()
	var origin_text = "Origin: N/A"
	if origin_x != null and origin_y != null:
		var origin_name = _get_settlement_name(gdm, origin_x, origin_y)
		origin_text = "Origin: %s (at %.0f, %.0f)" % [origin_name, origin_x, origin_y]
	origin_label.text = origin_text
	content_vbox.add_child(origin_label)

	# Destination
	var dest_x = journey_data.get("dest_x")
	var dest_y = journey_data.get("dest_y")
	var destination_label = Label.new()
	var dest_text = "Destination: N/A"
	if dest_x != null and dest_y != null:
		var dest_name = _get_settlement_name(gdm, dest_x, dest_y)
		dest_text = "Destination: %s (at %.0f, %.0f)" % [dest_name, dest_x, dest_y]
	destination_label.text = dest_text
	content_vbox.add_child(destination_label)
	content_vbox.add_child(HSeparator.new())

	# Departure Time
	var departure_time_str = journey_data.get("departure_time")
	var departure_label = Label.new()
	departure_label.text = "Departed: " + DateTimeUtils.format_timestamp_display(departure_time_str, false)
	content_vbox.add_child(departure_label)

	# ETA and Time Remaining
	var eta_str = journey_data.get("eta")
	var eta_label = Label.new()
	eta_label.text = "ETA: " + DateTimeUtils.format_timestamp_display(eta_str, true)
	content_vbox.add_child(eta_label)
	content_vbox.add_child(HSeparator.new())

	# Progress
	var progress = journey_data.get("progress", 0.0)
	var length = journey_data.get("length", 0.0)
	var progress_percentage = 0.0
	if length > 0.001: # Avoid division by zero
		progress_percentage = (progress / length) * 100.0
	
	var progress_text_label = Label.new()
	progress_text_label.text = "Progress: %.1f / %.1f units (%.1f%%)" % [progress, length, progress_percentage]
	content_vbox.add_child(progress_text_label)

	var progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 20
	progress_bar.value = progress_percentage
	content_vbox.add_child(progress_bar)

func _populate_destination_list():
	var gdm = get_node_or_null("/root/GameDataManager")
	if not is_instance_valid(gdm) or not gdm.has_method("get_all_settlements_data"):
		printerr("ConvoyJourneyMenu: GameDataManager not found or method missing. Cannot populate destinations.")
		var error_label = Label.new()
		error_label.text = "Error: Could not load destination data."
		error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content_vbox.add_child(error_label)
		return

	var all_settlements = gdm.get_all_settlements_data()
	if all_settlements.is_empty():
		var no_settlements_label = Label.new()
		no_settlements_label.text = "No known destinations to travel to."
		no_settlements_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content_vbox.add_child(no_settlements_label)
		return

	var convoy_pos = Vector2(convoy_data_received.get("x", 0.0), convoy_data_received.get("y", 0.0))

	# Create a reverse map from vendor_id to settlement_name for quick lookups.
	var vendor_to_settlement_map: Dictionary = {}
	for settlement in all_settlements:
		if settlement.has("vendors") and settlement.vendors is Array:
			for vendor in settlement.vendors:
				if vendor.has("vendor_id"):
					vendor_to_settlement_map[str(vendor.vendor_id)] = settlement.get("name")

	# Find any mission-specific destinations by resolving recipient IDs to settlement names.
	var mission_destinations: Dictionary = {}
	if convoy_data_received.has("vehicle_details_list"):
		for vehicle in convoy_data_received.get("vehicle_details_list", []):
			if vehicle.has("cargo"):
				for cargo_item in vehicle.get("cargo", []):
					var recipient_id = cargo_item.get("recipient")
					if recipient_id != null:
						var recipient_id_str = str(recipient_id)
						if vendor_to_settlement_map.has(recipient_id_str):
							var settlement_name = vendor_to_settlement_map[recipient_id_str]
							# Store the name of the first mission cargo item found for this destination.
							if not mission_destinations.has(settlement_name):
								mission_destinations[settlement_name] = cargo_item.get("name", "Mission Cargo")

	var header_label = Label.new()
	header_label.text = "Choose a Destination:"
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_vbox.add_child(header_label)
	content_vbox.add_child(HSeparator.new())

	var potential_destinations = []
	for settlement_data in all_settlements:
		var settlement_pos = Vector2(settlement_data.get("x", 0.0), settlement_data.get("y", 0.0))
		
		# Don't list the current location as a destination. Use squared distance for efficiency.
		if convoy_pos.distance_squared_to(settlement_pos) < 0.01:
			continue
		
		# Exclude "Tutorial City" as it's not an accessible player destination
		if settlement_data.get("name", "") == "Tutorial City":
			continue
		
		var distance = convoy_pos.distance_to(settlement_pos)
		potential_destinations.append({"data": settlement_data, "distance": distance})

	# Sort destinations: mission destinations first, then by distance.
	potential_destinations.sort_custom(func(a, b):
		var a_name = a.data.get("name", "")
		var b_name = b.data.get("name", "")
		var a_is_mission = mission_destinations.has(a_name)
		var b_is_mission = mission_destinations.has(b_name)

		if a_is_mission and not b_is_mission:
			return true # a comes before b
		if not a_is_mission and b_is_mission:
			return false # b comes before a
		
		# If both are missions or both are not, sort by distance
		return a.distance < b.distance
	)

	for destination_entry in potential_destinations:
		var settlement_data = destination_entry.data
		var distance = destination_entry.distance
		var dest_button = Button.new()
		var settlement_name = settlement_data.get("name", "Unknown")
		var button_text = "%s (%.1f units)" % [settlement_name, distance]
		if mission_destinations.has(settlement_name):
			var cargo_name = mission_destinations[settlement_name]
			button_text = "[%s] %s" % [cargo_name, button_text]
		dest_button.text = button_text
		dest_button.pressed.connect(_on_destination_button_pressed.bind(settlement_data))
		content_vbox.add_child(dest_button)

	if potential_destinations.is_empty():
		var at_destination_label = Label.new()
		at_destination_label.text = "This convoy is already at the only known settlement."
		at_destination_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content_vbox.add_child(at_destination_label)

func _get_settlement_name(gdm_node, coord_x, coord_y) -> String:
	if not is_instance_valid(gdm_node) or not gdm_node.has_method("get_settlement_name_from_coords"):
		printerr("ConvoyJourneyMenu: GameDataManager not available or method missing for settlement name.")
		return "Unknown"
	
	var x_int = roundi(float(coord_x))
	var y_int = roundi(float(coord_y))
	var name = gdm_node.get_settlement_name_from_coords(x_int, y_int)
	if name.begins_with("N/A"):
		return "Uncharted Location"
	return name

func _on_title_label_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		print("ConvoyJourneyMenu: Title clicked. Emitting 'return_to_convoy_overview_requested'.")
		emit_signal("return_to_convoy_overview_requested", convoy_data_received)
		get_viewport().set_input_as_handled()

func _on_destination_button_pressed(destination_data: Dictionary):
	print("ConvoyJourneyMenu: Destination '%s' selected. Requesting route choices." % destination_data.get("name"))
	
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm) and gdm.has_method("request_route_choices"):
		var convoy_id = str(convoy_data_received.get("convoy_id"))
		var dest_x = int(destination_data.get("x"))
		var dest_y = int(destination_data.get("y"))
		gdm.request_route_choices(convoy_id, dest_x, dest_y)
	else:
		printerr("ConvoyJourneyMenu: Could not find GameDataManager or 'request_route_choices' method.")

	emit_signal("find_route_requested", convoy_data_received, destination_data)

func _on_route_info_ready(convoy_data: Dictionary, destination_data: Dictionary, route_choices: Array):
	# If a route selection menu already exists for some reason, remove it.
	if is_instance_valid(_route_selection_menu_instance):
		_route_selection_menu_instance.queue_free()

	# Hide the main content of this menu so it doesn't show behind the route selection.
	main_vbox.hide()

	_route_selection_menu_instance = RouteSelectionMenuScene.instantiate()
	add_child(_route_selection_menu_instance)

	# The `convoy_data` from the signal may be minimal. Use the locally stored
	# `convoy_data_received` which is guaranteed to have the full vehicle details list.
	_route_selection_menu_instance.initialize_with_data(convoy_data_received, destination_data, route_choices)

	_route_selection_menu_instance.back_requested.connect(_on_route_selection_back_requested)
	_route_selection_menu_instance.embark_requested.connect(_on_route_selection_embark_requested)

func _on_route_selection_back_requested():
	if is_instance_valid(_route_selection_menu_instance):
		_route_selection_menu_instance.queue_free()
		_route_selection_menu_instance = null
	
	# Re-show the main content of this menu.
	main_vbox.show()

func _on_route_selection_embark_requested(convoy_id: String, journey_id: String):
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		gdm.start_convoy_journey(convoy_id, journey_id)
	# The journey_started signal will be handled elsewhere to close menus/update UI
