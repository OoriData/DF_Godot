extends Control

# Signal that MenuManager will listen for to go back
signal back_requested
signal find_route_requested(convoy_data, destination_data)
signal return_to_convoy_overview_requested(convoy_data)
signal route_preview_started(route_data)
signal route_preview_ended

var convoy_data_received: Dictionary
var _route_selection_menu_instance: Control = null

# --- Route Preview State ---
var _all_route_choices: Array = []
var _current_route_index: int = 0
var _destination_data: Dictionary = {}

# @onready variables for UI elements
@onready var title_label: Label = $MainVBox/TitleLabel
@onready var scroll_container: ScrollContainer = $MainVBox/ScrollContainer
@onready var content_vbox: VBoxContainer = $MainVBox/ScrollContainer/ContentVBox
@onready var back_button: Button = $MainVBox/BackButton
@onready var main_vbox: VBoxContainer = $MainVBox

# Preload the scene for the route selection menu
const RouteSelectionMenuScene = preload("res://Scenes/RouteSelectionMenu.tscn")

var _is_request_in_flight: bool = false
var _loading_label: Label = null
var _last_requested_destination: Dictionary = {}

# New confirmation panel references (created dynamically)
var _confirmation_panel: VBoxContainer = null
var _confirm_button: Button = null
var _change_destination_button: Button = null

# --- Route Cycling and Severity ---
var _current_route_choice_index: int = 0
var _route_choices_cache: Array = []
var _severity_state: String = "none" # none|safety|critical
var _next_route_button: Button = null
const ALLOW_HYBRID_ENERGY := true # Show battery usage even if vehicle also has internal combustion
const SHOW_ENERGY_DEBUG := true # Toggle to display raw data snapshot for kWh logic

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
		print("[ConvoyJourneyMenu] Connecting to GameDataManager signals.")
		# Listen for route choice lifecycle and journey cancel updates
		if not gdm.route_choices_request_started.is_connected(_on_route_choices_request_started):
			gdm.route_choices_request_started.connect(_on_route_choices_request_started)
		if not gdm.route_choices_error.is_connected(_on_route_choices_error):
			gdm.route_choices_error.connect(_on_route_choices_error)
		if not gdm.route_info_ready.is_connected(_on_route_info_ready):
			gdm.route_info_ready.connect(_on_route_info_ready)
		if not gdm.journey_canceled.is_connected(_on_journey_canceled):
			gdm.journey_canceled.connect(_on_journey_canceled)
	else:
		printerr("ConvoyJourneyMenu: Could not connect to GameDataManager signals.")

	# Remove the placeholder label if it exists
	if content_vbox.has_node("PlaceholderLabel"):
		var placeholder = content_vbox.get_node("PlaceholderLabel")
		if is_instance_valid(placeholder):
			placeholder.queue_free()

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		# Ensure preview is cleaned up if this menu is closed unexpectedly.
		emit_signal("route_preview_ended")

func _on_back_button_pressed():
	print("ConvoyJourneyMenu: Back button pressed. Emitting 'back_requested' signal.")
	# If the route selection menu is open, this back button shouldn't be clickable,
	# but as a safeguard, we ensure it's closed if we go back.
	if is_instance_valid(_route_selection_menu_instance):
		_route_selection_menu_instance.queue_free()
		emit_signal("route_preview_ended") # Clean up the preview
	emit_signal("back_requested")

func _process(_delta: float):
	pass

func _physics_process(_delta: float):
	pass

func initialize_with_data(data: Dictionary):
	print("ConvoyJourneyMenu: Initialized with data.") # DEBUG
	# Store the received data for potential use by the title click
	convoy_data_received = data.duplicate()
	for child in content_vbox.get_children():
		child.queue_free()
	# SAFELY extract journey data (API may send null)
	var journey_raw = data.get("journey")
	var journey_data: Dictionary = {}
	if journey_raw is Dictionary:
		journey_data = journey_raw
	# Access GameDataManager after journey coercion
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
	departure_label.text = "Departed: " + preload("res://Scripts/System/date_time_util.gd").format_timestamp_display(departure_time_str, false)
	content_vbox.add_child(departure_label)
	# ETA and Time Remaining
	var eta_str = journey_data.get("eta")
	var eta_label = Label.new()
	eta_label.text = "ETA: " + preload("res://Scripts/System/date_time_util.gd").format_timestamp_display(eta_str, true)
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

	# Cancel Journey button (in details mode)
	if journey_data.has("journey_id"):
		var cancel_btn := Button.new()
		cancel_btn.text = "Cancel Journey"
		cancel_btn.theme_type_variation = "DangerButton"
		cancel_btn.pressed.connect(func():
			# Show a blocking overlay while cancellation propagates
			_show_blocking_overlay("Canceling journey…")
			var convoy_id_local := str(convoy_data_received.get("convoy_id"))
			var journey_id_local := str(journey_data.get("journey_id", ""))
			if journey_id_local.is_empty():
				printerr("ConvoyJourneyMenu: Cannot cancel; missing journey_id")
				_hide_blocking_overlay()
				return
			var gdm_cancel := get_node_or_null("/root/GameDataManager")
			if is_instance_valid(gdm_cancel) and gdm_cancel.has_method("cancel_convoy_journey"):
				print("[ConvoyJourneyMenu] Cancel Journey pressed convoy="+convoy_id_local+" journey="+journey_id_local)
				gdm_cancel.cancel_convoy_journey(convoy_id_local, journey_id_local)
			else:
				printerr("ConvoyJourneyMenu: GameDataManager missing cancel_convoy_journey method.")
				_hide_blocking_overlay()
		)
		content_vbox.add_child(cancel_btn)

func _populate_destination_list():
	# Clear potential prior loading state
	_is_request_in_flight = false
	_loading_label = null
	_last_requested_destination = {}

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
	var settlement_name = gdm_node.get_settlement_name_from_coords(x_int, y_int)
	if settlement_name.begins_with("N/A"):
		return "Uncharted Location"
	return settlement_name

func _on_title_label_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		print("ConvoyJourneyMenu: Title clicked. Emitting 'return_to_convoy_overview_requested'.")
		emit_signal("return_to_convoy_overview_requested", convoy_data_received)
		get_viewport().set_input_as_handled()

func _on_destination_button_pressed(destination_data: Dictionary):
	if _is_request_in_flight:
		return # Ignore multiple clicks while loading
	print("ConvoyJourneyMenu: Destination '%s' selected. Requesting route choices." % destination_data.get("name"))
	_last_requested_destination = destination_data
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm) and gdm.has_method("request_route_choices"):
		var convoy_id = str(convoy_data_received.get("convoy_id"))
		var dest_x = int(destination_data.get("x"))
		var dest_y = int(destination_data.get("y"))
		gdm.request_route_choices(convoy_id, dest_x, dest_y)
		_disable_destination_buttons()
		_show_loading_indicator("Finding routes...")
	else:
		printerr("ConvoyJourneyMenu: Could not find GameDataManager or 'request_route_choices' method.")
	_emit_find_route(destination_data)

func _emit_find_route(destination_data: Dictionary):
	emit_signal("find_route_requested", convoy_data_received, destination_data)

func _on_route_choices_request_started(convoy_id: String, _destination_ctx: Dictionary):
	print("[ConvoyJourneyMenu] route_choices_request_started for convoy_id=", convoy_id)
	# Verify this is for our convoy
	if str(convoy_data_received.get("convoy_id")) != str(convoy_id):
		return
	_is_request_in_flight = true
	_show_loading_indicator("Calculating routes...")

func _on_route_choices_error(convoy_id: String, _destination_ctx: Dictionary, error_message: String):
	print("[ConvoyJourneyMenu] route_choices_error for convoy_id=", convoy_id, " error=", error_message)
	if str(convoy_data_received.get("convoy_id")) != str(convoy_id):
		return
	_is_request_in_flight = false
	_clear_loading_indicator()
	_show_error_message(error_message)
	_enable_destination_buttons()

func _on_route_info_ready(convoy_data: Dictionary, destination_data: Dictionary, route_choices: Array):
	print("[ConvoyJourneyMenu] route_info_ready for convoy_id=", convoy_data.get("convoy_id"), " routes=", route_choices.size())
	if str(convoy_data.get("convoy_id")) != str(convoy_data_received.get("convoy_id")):
		return
	_clear_loading_indicator()
	_is_request_in_flight = false

	if route_choices.is_empty():
		printerr("ConvoyJourneyMenu: Received no route choices. Cannot show preview.")
		return
	# Extra debug: list kWh expense keys per route
	for i in range(route_choices.size()):
		var rc = route_choices[i]
		if rc is Dictionary and rc.has('kwh_expenses'):
			var ke = rc.get('kwh_expenses')
			if ke is Dictionary:
				print('[ConvoyJourneyMenu][DEBUG] Route', i, 'kwh_expenses keys=', ke.keys())
			elif ke is Array:
				print('[ConvoyJourneyMenu][DEBUG] Route', i, 'kwh_expenses is Array size=', ke.size())
		else:
			print('[ConvoyJourneyMenu][DEBUG] Route', i, 'has no kwh_expenses key. Keys=', rc.keys())
	# For now just take the first route as selected; future enhancement could allow cycling.
	_all_route_choices = route_choices
	_current_route_index = 0
	_destination_data = destination_data
	var selected_route = route_choices[0]
	# Emit preview signal so map draws line
	emit_signal("route_preview_started", selected_route)
	_refresh_convoy_snapshot() # ensure latest vehicle data
	_show_confirmation_panel(selected_route)

# --- Formatting helper (re-added after merge overwrote original) ---
func _format_kwh(val: float) -> String:
	if val >= 10.0:
		return str(int(val)) # whole number
	return '%.1f' % val

# Duplicate replaced with alias
func _fmt_kwh(v: float) -> String:
	return _format_kwh(v)

# Format travel time from minutes into hours or days+hours.
# Rules:
# - Always display hours if under 24h: e.g. 18.5 h
# - If 24h or more: show D d H.h h (hours with one decimal) e.g. 2d 3.5h
func _format_travel_time(total_minutes: float) -> String:
	if total_minutes < 0.0:
		total_minutes = 0.0
	var hours: float = total_minutes / 60.0
	if hours < 24.0:
		return "%.1f h" % hours
	var days: int = int(floor(hours / 24.0))
	var rem_hours: float = hours - float(days) * 24.0
	return "%dd %.1fh" % [days, rem_hours]

# --- Helper for energy display ---
func _fuzz_kwh(v: float) -> float:
	if v <= 0.0:
		return 0.0
	if v < 20.0:
		return ceil(v)
	return ceil(v / 10.0) * 10.0

func _extract_battery_item(vehicle: Dictionary) -> Dictionary:
	# Extended battery detection: look for common key variations inside cargo items
	# 1) Direct vehicle-level fields
	var direct_kwh = 0.0
	var direct_cap = 0.0
	var direct_found = false
	for key in vehicle.keys():
		var k_lower = str(key).to_lower()
		if k_lower.find('kwh') != -1 or k_lower.find('battery') != -1 or k_lower.find('charge') != -1:
			var val = vehicle.get(key)
			if (val is int or val is float) and _coerce_number(val) > 0:
				direct_kwh = max(direct_kwh, _coerce_number(val))
				direct_found = true
		if k_lower.find('capacity') != -1 and (vehicle.get(key) is int or vehicle.get(key) is float):
			direct_cap = max(direct_cap, _coerce_number(vehicle.get(key)))
	if direct_found:
		if direct_cap <= 0: direct_cap = direct_kwh
		return {"kwh": direct_kwh, "capacity": direct_cap, "_source": "vehicle_fields"}
	for item in vehicle.get('cargo', []):
		if not (item is Dictionary):
			continue
		# Primary expected keys
		if item.has('kwh'):
			var cap_val = 0.0
			if item.has('capacity'):
				cap_val = _coerce_number(item.get('capacity'))
			elif item.has('capacity_kwh'):
				cap_val = _coerce_number(item.get('capacity_kwh'))
			elif item.has('max_kwh'):
				cap_val = _coerce_number(item.get('max_kwh'))
			elif item.has('max') and (item.get('max') is int or item.get('max') is float):
				cap_val = _coerce_number(item.get('max'))
			var kwh_val = _coerce_number(item.get('kwh'))
			if cap_val <= 0: cap_val = max(kwh_val, 0.0)
			return {"kwh": kwh_val, "capacity": cap_val, "_source": "cargo_kwh"}
		# Fallback variants
		if item.has('battery') and item.battery is Dictionary:
			var b = item.battery
			if b.has('kwh') and b.has('capacity'):
				return {"kwh": _coerce_number(b.get('kwh')), "capacity": _coerce_number(b.get('capacity')), "_source": "cargo_battery_obj"}
		if item.has('current_kwh') or item.has('energy_kwh'):
			var k_cur = 0.0
			if item.has('current_kwh'): k_cur = _coerce_number(item.get('current_kwh'))
			elif item.has('energy_kwh'): k_cur = _coerce_number(item.get('energy_kwh'))
			var cap = _coerce_number(item.get('capacity_kwh', item.get('capacity', 0.0)))
			if cap > 0.0 or k_cur > 0.0:
				return {"kwh": k_cur, "capacity": (cap if cap > 0 else k_cur), "_source": "cargo_alt_keys"}
		# Heuristic scan: any numeric field with kwh/charge in name
		for sub_key in item.keys():
			var sub_lower = str(sub_key).to_lower()
			if (sub_lower.find('kwh') != -1 or sub_lower.find('charge') != -1 or sub_lower.find('energy') != -1) and (item.get(sub_key) is int or item.get(sub_key) is float):
				var valn = _coerce_number(item.get(sub_key))
				if valn > 0:
					var cap_guess = valn
					if item.has('capacity'):
						cap_guess = max(cap_guess, _coerce_number(item.get('capacity')))
					elif item.has('capacity_kwh'):
						cap_guess = max(cap_guess, _coerce_number(item.get('capacity_kwh')))
					return {"kwh": valn, "capacity": cap_guess, "_source": "heuristic_scan"}
	return {}

func _refresh_convoy_snapshot():
	var gdm = get_node_or_null('/root/GameDataManager')
	if not is_instance_valid(gdm):
		return
	if not convoy_data_received.has('convoy_id'):
		return
	if gdm.has_method('get_convoy_by_id'):
		var latest = gdm.get_convoy_by_id(str(convoy_data_received.get('convoy_id')))
		if latest is Dictionary and not latest.is_empty():
			# Only update vehicle lists to avoid overwriting selection context
			if latest.has('vehicle_details_list'):
				convoy_data_received['vehicle_details_list'] = latest.get('vehicle_details_list')
			elif latest.has('vehicles'):
				convoy_data_received['vehicle_details_list'] = latest.get('vehicles')
			print('[ConvoyJourneyMenu][DEBUG] Refreshed convoy vehicle snapshot. Vehicles now =', (convoy_data_received.get('vehicle_details_list', []) as Array).size())

# Numeric coercion (re-added after revert)
func _coerce_number(v: Variant) -> float:
	if v is float:
		return v
	if v is int:
		return float(v)
	if v is String:
		var s: String = v.strip_edges()
		if s.is_valid_float():
			return s.to_float()
		if s.is_valid_int():
			return float(int(s))
	return 0.0

# Attempt multiple key forms for kWh expense
func _lookup_kwh_expense(expenses: Dictionary, vehicle_id: Variant) -> float:
	var keys_to_try: Array = []
	keys_to_try.append(vehicle_id)
	keys_to_try.append(str(vehicle_id))
	if vehicle_id is String and vehicle_id.is_valid_int():
		keys_to_try.append(int(vehicle_id))
	elif vehicle_id is int:
		keys_to_try.append(str(vehicle_id))
	for k in keys_to_try:
		if expenses.has(k):
			var val = _coerce_number(expenses.get(k))
			print('[ConvoyJourneyMenu][kWhLookup] match key=', k, ' val=', val)
			return val
	print('[ConvoyJourneyMenu][kWhLookup] no match for vehicle_id variants=', keys_to_try)
	return 0.0

# Diagnostic helper
func _debug_dump_energy_context(route_data: Dictionary):
	print('[ConvoyJourneyMenu][DEBUG] ---- Energy Context Dump ----')
	var kwh_expenses: Dictionary = route_data.get('kwh_expenses', {})
	print('[ConvoyJourneyMenu][DEBUG] kwh_expenses keys/types:')
	for k in kwh_expenses.keys():
		print('  key=', k, ' type=', typeof(k), ' value=', kwh_expenses[k])
	var vehicles: Array = _get_vehicle_list()
	print('[ConvoyJourneyMenu][DEBUG] vehicle count=', vehicles.size())
	for v in vehicles:
		if not (v is Dictionary):
			continue
		var vid = v.get('vehicle_id')
		var electric_flags = [v.get('electric'), v.get('is_electric'), v.get('electric_powered')]
		var ic_flag = v.get('internal_combustion')
		var battery = _extract_battery_item(v)
		print('  Vehicle id=', vid, ' name=', v.get('name'), ' electric_flags=', electric_flags, ' internal_combustion=', ic_flag, ' battery_found=', not battery.is_empty())
		if not battery.is_empty():
			print('    Battery keys=', battery.keys(), ' kwh=', battery.get('kwh'), ' capacity=', battery.get('capacity'))
	print('[ConvoyJourneyMenu][DEBUG] ---- End Dump ----')

# Attempt to resolve kWh expenses dict under variant key names
func _resolve_kwh_expenses(route_data: Dictionary) -> Dictionary:
	var direct = route_data.get('kwh_expenses')
	if direct is Dictionary:
		return direct
	if direct is Array:
		# Convert array of {vehicle_id, kwh?(cost)} into dictionary if possible
		var built: Dictionary = {}
		for entry in direct:
			if entry is Dictionary:
				var vid = entry.get('vehicle_id')
				var val = entry.get('kwh') if entry.has('kwh') else entry.get('cost')
				if vid != null and val != null:
					built[str(vid)] = _coerce_number(val)
		if built.size() > 0:
			print('[ConvoyJourneyMenu][DEBUG] Converted array-form kwh_expenses to dict keys=', built.keys())
			return built
	# case variations
	for key in ['kWh_expenses', 'kwhExpenses', 'kWhExpenses', 'electric_expenses', 'electricity_expenses']:
		var cand = route_data.get(key)
		if cand is Dictionary and cand.size() > 0:
			print('[ConvoyJourneyMenu][DEBUG] Using alt kWh expenses key=', key)
			return cand
	# deep search shallow
	for k in route_data.keys():
		var v = route_data[k]
		if v is Dictionary and v.has('kwh_expenses'):
			var inner = v.get('kwh_expenses')
			if inner is Dictionary and inner.size() > 0:
				print('[ConvoyJourneyMenu][DEBUG] Found nested kwh_expenses under key=', k)
				return inner
	print('[ConvoyJourneyMenu][DEBUG] No kWh expenses dictionary found; defaulting to empty.')
	return {}

# Unified vehicle list accessor with fallbacks
func _get_vehicle_list() -> Array:
	var primary = convoy_data_received.get('vehicle_details_list')
	if primary is Array and primary.size() > 0:
		return primary
	var alt = convoy_data_received.get('vehicles')
	if alt is Array and alt.size() > 0:
		print('[ConvoyJourneyMenu][DEBUG] Using fallback vehicles list (vehicles).')
		return alt
	var alt2 = convoy_data_received.get('convoy_vehicles')
	if alt2 is Array and alt2.size() > 0:
		print('[ConvoyJourneyMenu][DEBUG] Using fallback vehicles list (convoy_vehicles).')
		return alt2
	print('[ConvoyJourneyMenu][DEBUG] No vehicle arrays found (vehicle_details_list / vehicles / convoy_vehicles all empty).')
	return []

# --- Route Cycling and Severity ---
func _fuzz_amount(v: float) -> float:
	# Same fuzz rule as fuzz() in discord code
	return _fuzz_kwh(v)

func _show_confirmation_panel(route_data: Dictionary):
	# Cache routes for cycling if not done
	if _route_choices_cache.is_empty() and not _all_route_choices.is_empty():
		_route_choices_cache = _all_route_choices.duplicate(true)
		_current_route_choice_index = 0
	# Hide current destination list UI
	for child in content_vbox.get_children():
		child.visible = false
	# Build (create if needed)
	if not is_instance_valid(_confirmation_panel):
		_confirmation_panel = VBoxContainer.new()
		_confirmation_panel.name = "ConfirmationPanel"
		_confirmation_panel.add_theme_constant_override("separation", 10)
		content_vbox.add_child(_confirmation_panel)
	# Clear panel for rebuild
	for child in _confirmation_panel.get_children():
		child.queue_free()
	# Title with route index
	var title = Label.new()
	title.text = "Confirm Journey (%d / %d)" % [_current_route_choice_index + 1, max(1, _all_route_choices.size())]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirmation_panel.add_child(title)
	# ---------------- BODY START ----------------
	var summary = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	var journey = route_data.get("journey", {})
	var tiles = (journey.get("route_x", []) as Array).size()
	var distance_miles = tiles * 30.0
	var eta_minutes = route_data.get("delta_t", 0.0)
	var eta_fmt = _format_travel_time(eta_minutes)
	summary.text = "Destination: %s\nDistance: %.1f miles\nEstimated Travel Time: %s" % [ _destination_data.get("name", "Unknown"), distance_miles, eta_fmt]
	_confirmation_panel.add_child(summary)
	var resources_header = Label.new()
	resources_header.text = "Projected Resource Usage"
	_confirmation_panel.add_child(resources_header)
	# --- Resource Summary (Consumption vs Reserves) ---
	var resources_section = VBoxContainer.new()
	resources_section.name = "ResourcesSection"
	_confirmation_panel.add_child(resources_section)
	var res_title = Label.new()
	res_title.text = "Convoy Resources"
	res_title.add_theme_color_override("font_color", Color(0.9,0.9,1))
	resources_section.add_child(res_title)
	# Gather consumption from route
	var fuel_needed: float = 0.0
	for fk in route_data.get("fuel_expenses", {}):
		fuel_needed += _coerce_number(route_data.get("fuel_expenses", {})[fk])
	var water_needed: float = _coerce_number(route_data.get("water_expense", 0.0))
	var food_needed: float = _coerce_number(route_data.get("food_expense", 0.0))
	# Gather convoy reserves
	var fuel_have: float = _coerce_number(convoy_data_received.get("fuel", 0.0))
	var fuel_max: float = _coerce_number(convoy_data_received.get("max_fuel", 0.0))
	var water_have: float = _coerce_number(convoy_data_received.get("water", 0.0))
	var water_max: float = _coerce_number(convoy_data_received.get("max_water", 0.0))
	var food_have: float = _coerce_number(convoy_data_received.get("food", 0.0))
	var food_max: float = _coerce_number(convoy_data_received.get("max_food", 0.0))

	# Helper to classify status (assumption: warn if >50% of reserve, critical if need > reserve)
	var _classify = func(need: float, have: float) -> String:
		if need <= 0.0:
			return "ok"
		if have <= 0.0:
			return "critical" # any need when none available
		if need > have + 0.0001:
			return "critical"
		if need > 0.5 * have:
			return "warn"
		return "ok"

	var fuel_status = _classify.call(fuel_needed, fuel_have)
	var water_status = _classify.call(water_needed, water_have)
	var food_status = _classify.call(food_needed, food_have)

	var resource_warning: bool = (fuel_status == "warn" or water_status == "warn" or food_status == "warn")
	var resource_critical: bool = (fuel_status == "critical" or water_status == "critical" or food_status == "critical")

	# Container panel for contrast (now also housing energy subsection)
	var res_panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.12,0.14,0.18,0.95)
	if sb.has_method("set_border_width_all"):
		sb.set_border_width_all(1)
	else:
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
	sb.border_color = Color(0.25,0.3,0.38)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	res_panel.add_theme_stylebox_override("panel", sb)
	resources_section.add_child(res_panel)
	var panel_vbox = VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", 8)
	res_panel.add_child(panel_vbox)
	# Resource Grid: Resource | Need | Have | Remaining
	var res_grid = GridContainer.new()
	res_grid.columns = 4
	res_grid.add_theme_constant_override("h_separation", 32)
	panel_vbox.add_child(res_grid)
	var header_labels = ["Resource", "Need", "Have", "Remaining"]
	for h in header_labels:
		var hl = Label.new()
		hl.text = h
		hl.add_theme_color_override("font_color", Color(0.75,0.85,0.95))
		if h != "Resource":
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		res_grid.add_child(hl)
	var _add_res_row = func(label: String, unit: String, need: float, have: float, _max_v: float, status: String):
		var icon_lbl = Label.new()
		icon_lbl.text = label
		if status == "critical":
			icon_lbl.add_theme_color_override("font_color", Color(1,0.35,0.35))
		elif status == "warn":
			icon_lbl.add_theme_color_override("font_color", Color(1,0.75,0.35))
		res_grid.add_child(icon_lbl)
		var need_lbl = Label.new()
		need_lbl.text = "%.1f%s" % [need, unit]
		need_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		res_grid.add_child(need_lbl)
		var have_lbl = Label.new()
		have_lbl.text = "%.1f%s" % [have, unit]
		have_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		res_grid.add_child(have_lbl)
		var rem_lbl = Label.new()
		var remaining = have - need
		if remaining < 0:
			rem_lbl.text = "Short %.1f%s" % [abs(remaining), unit]
			rem_lbl.add_theme_color_override("font_color", Color(1,0.35,0.35))
		elif status == "warn":
			rem_lbl.text = "%.1f%s" % [remaining, unit]
			rem_lbl.add_theme_color_override("font_color", Color(1,0.75,0.35))
		else:
			rem_lbl.text = "%.1f%s" % [remaining, unit]
		rem_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		res_grid.add_child(rem_lbl)
	_add_res_row.call("⛽ Fuel", "L", fuel_needed, fuel_have, fuel_max, fuel_status)
	_add_res_row.call("💧 Water", "L", water_needed, water_have, water_max, water_status)
	_add_res_row.call("🍖 Food", "", food_needed, food_have, food_max, food_status)
	# Warning / Critical message (no legend explanation)
	if resource_critical or resource_warning:
		var warn_lbl = Label.new()
		warn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		if resource_critical:
			warn_lbl.text = "[CRITICAL] Insufficient reserves for journey." if not resource_warning else "[CRITICAL] Insufficient reserves; high usage on others."
			warn_lbl.add_theme_color_override("font_color", Color(1,0.4,0.4))
		elif resource_warning:
			warn_lbl.text = "[Warning] High consumption (>50%) on at least one reserve."
			warn_lbl.add_theme_color_override("font_color", Color(1,0.75,0.35))
		panel_vbox.add_child(warn_lbl)
	# (Vehicle Energy subsection will be appended later if entries exist)
	# Resolve kWh expenses and build energy entries (will attach inside panel_vbox)
	var kwh_expenses: Dictionary = _resolve_kwh_expenses(route_data)
	var vehicles: Array = _get_vehicle_list()
	var energy_entries: Array = []
	var any_critical := false
	for v in vehicles:
		if not (v is Dictionary):
			continue
		var cap_val: float = _coerce_number(v.get('kwh_capacity', 0.0))
		if cap_val <= 0.0:
			continue
		var vid = v.get('vehicle_id')
		var used: float = _coerce_number(kwh_expenses.get(str(vid), 0.0))
		if used <= 0.0:
			continue
		var is_ic := bool(v.get('internal_combustion', false))
		var veh_name := str(v.get('name', 'Vehicle'))
		var status := "normal"
		var display_used := used
		if used > cap_val:
			if is_ic:
				status = "discharged"
				display_used = cap_val
			else:
				status = "critical"
				any_critical = true
		energy_entries.append({"name": veh_name, "used": display_used, "capacity": cap_val, "raw_used": used, "status": status, "is_ic": is_ic})
	if not energy_entries.is_empty():
		panel_vbox.add_child(HSeparator.new())
		var energy_subtitle = Label.new()
		energy_subtitle.text = "Vehicle Energy"
		energy_subtitle.add_theme_color_override("font_color", Color(0.85,0.85,1))
		panel_vbox.add_child(energy_subtitle)
		var energy_grid = GridContainer.new()
		energy_grid.columns = 4
		energy_grid.add_theme_constant_override("h_separation", 24)
		panel_vbox.add_child(energy_grid)
		for e in energy_entries:
			var icon_lbl = Label.new()
			match e.status:
				"critical": icon_lbl.text = "❗"
				"discharged": icon_lbl.text = "🪫"
				_:
					icon_lbl.text = "🔋"
			energy_grid.add_child(icon_lbl)
			var name_lbl = Label.new()
			name_lbl.text = e.name
			if e.status == "critical":
				name_lbl.add_theme_color_override("font_color", Color(1,0.4,0.4))
			elif e.status == "discharged":
				name_lbl.add_theme_color_override("font_color", Color(1,0.75,0.4))
			energy_grid.add_child(name_lbl)
			var bar = ProgressBar.new()
			bar.min_value = 0
			bar.max_value = e.capacity
			bar.value = e.used
			bar.custom_minimum_size = Vector2(140, 14)
			if bar.has_method("set_show_percentage"):
				bar.set("show_percentage", false)
			var bar_tt = "%s Usage: %.1f / %.1f kWh" % [e.name, e.used, e.capacity]
			if e.status == "critical":
				bar_tt += " (Shortfall %.1f kWh)" % (e.raw_used - e.capacity)
			elif e.status == "discharged":
				bar_tt += " (Fully Discharged)"
			bar.tooltip_text = bar_tt
			energy_grid.add_child(bar)
			var nums_lbl = Label.new()
			if e.status == "critical":
				# Show true need and shortfall for pure electric shortfall
				nums_lbl.text = "Need: %.1f  Capacity: %.1f  Short: %.1f" % [e.raw_used, e.capacity, e.raw_used - e.capacity]
			else:
				# For normal & discharged (IC) cases, cap the displayed need at capacity
				nums_lbl.text = "Need: %.1f  Capacity: %.1f" % [e.used, e.capacity]
			energy_grid.add_child(nums_lbl)
	# Severity state from combined energy + resource evaluation
	if any_critical or resource_critical:
		_severity_state = "critical"
	elif resource_warning:
		_severity_state = "safety"
	else:
		_severity_state = "none"
	var buttons_hbox = HBoxContainer.new()
	buttons_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirmation_panel.add_child(buttons_hbox)
	_change_destination_button = Button.new()
	_change_destination_button.text = "Back"
	_change_destination_button.pressed.connect(_on_change_destination_pressed)
	buttons_hbox.add_child(_change_destination_button)
	if _route_choices_cache.size() > 1:
		_next_route_button = Button.new()
		_next_route_button.text = "Next Route"
		_next_route_button.pressed.connect(func(): _cycle_route(1))
		buttons_hbox.add_child(_next_route_button)
	_confirm_button = Button.new()
	_confirm_button.text = "Confirm Journey"
	_confirm_button.theme_type_variation = "SuccessButton"
	_confirm_button.pressed.connect(_on_confirm_journey_pressed.bind(route_data))
	buttons_hbox.add_child(_confirm_button)
	_apply_severity_styling()
	# ---------------- BODY END ----------------
	_confirmation_panel.visible = true

func _on_change_destination_pressed():
	# Hide confirmation, re-show destination list
	if is_instance_valid(_confirmation_panel):
		_confirmation_panel.visible = false
	# Stop preview line
	emit_signal("route_preview_ended")
	for child in content_vbox.get_children():
		if child != _confirmation_panel:
			child.visible = true

func _on_confirm_journey_pressed(route_data: Dictionary):
	var convoy_id = str(convoy_data_received.get("convoy_id"))
	var journey_id = str(route_data.get("journey", {}).get("journey_id", ""))
	if journey_id.is_empty():
		printerr("ConvoyJourneyMenu: Cannot confirm journey; missing journey_id")
		return
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		gdm.start_convoy_journey(convoy_id, journey_id)
	# End preview and go back to overview
	emit_signal("route_preview_ended")
	emit_signal("return_to_convoy_overview_requested", convoy_data_received)

func _on_journey_canceled(updated_convoy: Dictionary):
	# Ensure event is for our convoy
	if str(updated_convoy.get("convoy_id")) != str(convoy_data_received.get("convoy_id")):
		return
	# Update local snapshot
	convoy_data_received = updated_convoy.duplicate(true)
	var has_active_journey := convoy_data_received.has("journey") and (convoy_data_received.get("journey") is Dictionary) and not (convoy_data_received.get("journey") as Dictionary).is_empty()
	# Rebuild UI appropriately: planner only if no active journey remains
	for child in content_vbox.get_children():
		child.queue_free()
	if has_active_journey:
		initialize_with_data(convoy_data_received) # will show journey details
	else:
		initialize_with_data(convoy_data_received) # journey missing -> planner
	# Handle successful journey cancellation by refreshing UI and notifying the user.
	var canceled_id = String(updated_convoy.get("convoy_id", ""))
	var current_id = String(convoy_data_received.get("convoy_id", ""))
	if canceled_id == "" or current_id == "":
		return
	if canceled_id != current_id:
		return

	# Stop any route preview
	emit_signal("route_preview_ended")
	_is_request_in_flight = false
	_clear_loading_indicator()

	# Replace local convoy snapshot and rebuild the panel
	convoy_data_received = updated_convoy.duplicate(true)
	initialize_with_data(convoy_data_received)

	# Show user-facing message (non-blocking), then remove loading overlay
	_show_inline_toast("Journey canceled.", 2.5)
	_hide_blocking_overlay()

	# Also update the title line to reflect planner state if no active journey
	var j = updated_convoy.get("journey")
	if not (j is Dictionary) or j.is_empty():
		if is_instance_valid(title_label):
			var convoy_name = String(updated_convoy.get("name", "Convoy"))
			title_label.text = convoy_name + " - Journey Planner"

func _disable_destination_buttons():
	for child in content_vbox.get_children():
		if child is Button and child.text != "Back":
			child.disabled = true
	# Disable all destination buttons during a request
	for child in content_vbox.get_children():
		if child is Button:
			(child as Button).disabled = true
		elif child is HBoxContainer or child is VBoxContainer:
			for sub in child.get_children():
				if sub is Button:
					(sub as Button).disabled = true
	if is_instance_valid(_next_route_button):
		_next_route_button.disabled = true

func _enable_destination_buttons():
	for child in content_vbox.get_children():
		if child is Button:
			child.disabled = false
	# Re-enable destination buttons after request completes
	for child in content_vbox.get_children():
		if child is Button:
			(child as Button).disabled = false
		elif child is HBoxContainer or child is VBoxContainer:
			for sub in child.get_children():
				if sub is Button:
					(sub as Button).disabled = false
	if is_instance_valid(_next_route_button):
		_next_route_button.disabled = false

func _show_loading_indicator(text: String):
	if _loading_label == null:
		_loading_label = Label.new()
		_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loading_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		content_vbox.add_child(_loading_label)
	_loading_label.text = text

func _clear_loading_indicator():
	if _loading_label and is_instance_valid(_loading_label):
		_loading_label.queue_free()
	_loading_label = null

func _show_error_message(msg: String):
	var err_label = Label.new()
	err_label.text = "Route Error: %s" % msg
	err_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_vbox.add_child(err_label)

	# Lightweight inline toast helper to notify the user
func _show_inline_toast(text: String, duration_seconds: float = 2.0):
	# Minimal, non-intrusive toast (no green block background)
	var toast := Label.new()
	toast.name = "InlineToast"
	toast.text = text
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 16)
	toast.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	if is_instance_valid(main_vbox):
		main_vbox.add_child(toast)
		main_vbox.move_child(toast, 1) # just below Title

	# Auto-remove after duration
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = max(0.5, duration_seconds)
	add_child(t)
	t.timeout.connect(func():
		if is_instance_valid(toast) and is_instance_valid(main_vbox):
			toast.queue_free()
		t.queue_free()
	)

# --- Blocking overlay during backend updates ---
var _blocking_overlay: Control = null

func _show_blocking_overlay(text: String = "Working…"):
	if is_instance_valid(_blocking_overlay):
		_hide_blocking_overlay()
	var overlay := ColorRect.new()
	overlay.name = "BlockingOverlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_left = 0
	overlay.anchor_top = 0
	overlay.anchor_right = 1
	overlay.anchor_bottom = 1
	overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Message centered
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.anchor_left = 0.5
	vb.anchor_top = 0.5
	vb.offset_left = -150
	vb.offset_top = -40
	vb.custom_minimum_size = Vector2(300, 80)
	var msg := Label.new()
	msg.text = text
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 18)
	vb.add_child(msg)
	var sub := Label.new()
	sub.text = "Please wait…"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	overlay.add_child(vb)
	_blocking_overlay = overlay
	add_child(_blocking_overlay)

func _hide_blocking_overlay():
	if is_instance_valid(_blocking_overlay):
		_blocking_overlay.queue_free()
	_blocking_overlay = null

# Severity + route cycling helpers (added)
func _apply_severity_styling():
	if not is_instance_valid(_confirm_button):
		return
	match _severity_state:
		"critical":
			_confirm_button.theme_type_variation = "DangerButton"
			_confirm_button.text = "🛑 Confirm (Critical)"
		"safety":
			_confirm_button.theme_type_variation = "WarningButton"
			_confirm_button.text = "⚠️ Confirm (Low Reserve)"
		_:
			_confirm_button.theme_type_variation = "SuccessButton"
			_confirm_button.text = "Confirm Journey"

func _cycle_route(delta: int):
	if _route_choices_cache.is_empty():
		return
	_current_route_choice_index = wrapi(_current_route_choice_index + delta, 0, _route_choices_cache.size())
	emit_signal("route_preview_ended")
	var route_data: Dictionary = _route_choices_cache[_current_route_choice_index]
	emit_signal("route_preview_started", route_data)
	_show_confirmation_panel(route_data)

# --- Tutorial helpers: find UI targets for highlighting ---

# Returns the global rect of a destination button whose label contains the given text
func get_destination_button_rect_by_label_contains(substr: String) -> Rect2:
	var needle := substr.to_lower()
	for child in content_vbox.get_children():
		if child is Button:
			var txt := String((child as Button).text)
			if txt.to_lower().find(needle) != -1:
				var ctrl := child as Control
				return ctrl.get_global_rect()
	return Rect2()

# Expose confirm button node for highlight/gating during confirmation step
func get_confirm_button_node() -> Button:
	return _confirm_button
