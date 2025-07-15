extends Control

signal embark_requested(convoy_id, journey_id)
signal back_requested

# --- Node References ---
@onready var destination_value: Label = $MainVBox/ColumnsHBox/RightColumn/DetailsGrid/DestinationValue
@onready var distance_value: Label = $MainVBox/ColumnsHBox/RightColumn/DetailsGrid/DistanceValue
@onready var eta_value: Label = $MainVBox/ColumnsHBox/RightColumn/DetailsGrid/ETAValue
@onready var fuel_value: Label = $MainVBox/ColumnsHBox/LeftColumn/ExpensesGrid/FuelValue
@onready var water_value: Label = $MainVBox/ColumnsHBox/LeftColumn/ExpensesGrid/WaterValue
@onready var food_value: Label = $MainVBox/ColumnsHBox/LeftColumn/ExpensesGrid/FoodValue
@onready var vehicle_expenses_vbox: VBoxContainer = $MainVBox/ColumnsHBox/LeftColumn/ScrollContainer/VehicleExpensesVBox
@onready var back_button: Button = $MainVBox/ButtonsHBox/BackButton
@onready var embark_button: Button = $MainVBox/ButtonsHBox/EmbarkButton

# --- Internal State ---
var _convoy_data: Dictionary
var _route_data: Dictionary

func _ready():
	back_button.pressed.connect(_on_back_button_pressed)
	embark_button.pressed.connect(_on_embark_button_pressed)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		# The parent menu is now responsible for cleaning up the preview.
		pass

func display_route_details(p_convoy_data: Dictionary, p_destination_data: Dictionary, p_route_data: Dictionary):
	"""Displays the details for a single, specific route."""
	if p_route_data.is_empty():
		printerr("RouteSelectionMenu: display_route_details called with no route data. Cannot display.")
		# In a real scenario, you might show an error message here.
		queue_free() # Or hide and emit back signal
		return

	_convoy_data = p_convoy_data
	# This menu now only knows about the one route it was given.
	_route_data = p_route_data

	var journey_details = _route_data.get("journey", {})

	# --- Populate UI ---
	destination_value.text = p_destination_data.get("name", "Unknown")
	# The 'length' and 'eta' values are inside the nested 'journey' dictionary.
	# Distance is calculated from the number of tiles in the route (30 miles/tile).
	var route_x_array = journey_details.get("route_x", [])
	var distance_in_miles = route_x_array.size() * 30.0
	distance_value.text = "%.1f miles" % distance_in_miles
	# ETA for a prospective journey is calculated from delta_t (in minutes).
	var delta_t_minutes = _route_data.get("delta_t", 0.0)
	var eta_timestamp = Time.get_unix_time_from_system() + int(delta_t_minutes * 60.0)
	eta_value.text = DateTimeUtils.format_timestamp_display(eta_timestamp, true)

	# Fuel is a dictionary of expenses per vehicle; we need to sum them.
	var total_fuel_cost = 0.0
	var fuel_expenses_dict = _route_data.get("fuel_expenses", {})
	for vehicle_id in fuel_expenses_dict:
		total_fuel_cost += fuel_expenses_dict[vehicle_id]
	fuel_value.text = "%s L" % _format_resource_value(total_fuel_cost)
	water_value.text = "%s L" % _format_resource_value(_route_data.get("water_expense", 0.0))
	food_value.text = "%s meals" % _format_resource_value(_route_data.get("food_expense", 0.0))

	_populate_vehicle_expenses()

func _populate_vehicle_expenses():
	for child in vehicle_expenses_vbox.get_children():
		child.queue_free()

	var kwh_expenses_dict: Dictionary = _route_data.get("kwh_expenses", {})
	var any_vehicle_shown = false

	for vehicle_id in kwh_expenses_dict:
		var energy_cost = kwh_expenses_dict[vehicle_id]

		# Find the corresponding vehicle in the convoy data
		var vehicle_details = null
		for v in _convoy_data.get("vehicle_details_list", []):
			if v.get("vehicle_id") == vehicle_id:
				vehicle_details = v
				break

		if vehicle_details == null:
			continue

		var vehicle_name = vehicle_details.get("name", "Unknown Vehicle")

		# Find the battery in the vehicle's cargo to get energy details.
		var current_energy = 0.0
		var max_energy = 1.0 # Default to 1 to avoid division by zero
		var cargo_list = vehicle_details.get("cargo", [])
		for cargo_item in cargo_list:
			# A battery is identified by having a "kwh" key with a non-null value.
			if cargo_item.has("kwh") and cargo_item["kwh"] != null:
				current_energy = float(cargo_item["kwh"])
				var capacity = cargo_item.get("capacity")
				if capacity != null:
					max_energy = max(1.0, float(capacity))
				break # Found the battery, no need to check other cargo.

		# The actual expense for the journey cannot exceed the energy currently available.
		var capped_energy_cost = min(energy_cost, current_energy)

		# If the actual, capped expense is zero, don't show this vehicle.
		if capped_energy_cost <= 0.0:
			continue

		var remaining_charge = current_energy - capped_energy_cost

		# Choose an emoji based on the remaining charge percentage.
		var batt_emoji = "🔋" # Default: charged
		if remaining_charge <= (max_energy * 0.2):
			batt_emoji = "🪫" # Low battery

		any_vehicle_shown = true

		var expense_label = Label.new()
		expense_label.text = "%s 🛻 kWh expense: %s kWh %s" % [vehicle_name, _format_resource_value(capped_energy_cost), batt_emoji]
		vehicle_expenses_vbox.add_child(expense_label)

		var progress_bar = ProgressBar.new()
		progress_bar.max_value = max_energy
		progress_bar.value = remaining_charge
		progress_bar.show_percentage = false
		vehicle_expenses_vbox.add_child(progress_bar)

		var sub_label = Label.new()
		sub_label.text = "(%s / %s kWh)" % [_format_resource_value(remaining_charge), _format_resource_value(max_energy)]
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vehicle_expenses_vbox.add_child(sub_label)

	if not any_vehicle_shown:
		var no_cost_label = Label.new()
		no_cost_label.text = "No vehicle energy costs."
		no_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vehicle_expenses_vbox.add_child(no_cost_label)

func _format_resource_value(value: float) -> String:
	# Display one decimal place for non-zero values under 10, otherwise show as integer.
	if value < 10.0 and value > 0.001:
		return "%.1f" % value
	else:
		return "%d" % round(value)

func _on_embark_button_pressed():
	var convoy_id = str(_convoy_data.get("convoy_id"))
	# The journey_id is inside the nested 'journey' dictionary.
	var journey_id = str(_route_data.get("journey", {}).get("journey_id"))
	print("RouteSelectionMenu: Embark requested for convoy %s on journey %s" % [convoy_id, journey_id])
	emit_signal("embark_requested", convoy_id, journey_id)

func _on_back_button_pressed():
	emit_signal("back_requested")
