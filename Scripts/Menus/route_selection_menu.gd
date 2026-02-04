extends Control

# Signals to communicate with the parent/manager
signal back_requested
signal journey_started(route_data)

# Node references based on Scene structure
@onready var title_label: Label = $MainVBox/TitleLabel
@onready var fuel_value: Label = $MainVBox/ColumnsHBox/LeftColumn/ExpensesGrid/FuelValue
@onready var water_value: Label = $MainVBox/ColumnsHBox/LeftColumn/ExpensesGrid/WaterValue
@onready var food_value: Label = $MainVBox/ColumnsHBox/LeftColumn/ExpensesGrid/FoodValue
@onready var destination_value: Label = $MainVBox/ColumnsHBox/RightColumn/DetailsGrid/DestinationValue
@onready var distance_value: Label = $MainVBox/ColumnsHBox/RightColumn/DetailsGrid/DistanceValue
@onready var eta_value: Label = $MainVBox/ColumnsHBox/RightColumn/DetailsGrid/ETAValue
@onready var vehicle_expenses_vbox: VBoxContainer = $MainVBox/ColumnsHBox/LeftColumn/ScrollContainer/VehicleExpensesVBox
@onready var back_button: Button = $MainVBox/ButtonsHBox/BackButton
@onready var embark_button: Button = $MainVBox/ButtonsHBox/EmbarkButton

var _route_data: Dictionary = {}

func _ready() -> void:
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if embark_button:
		embark_button.pressed.connect(_on_embark_pressed)

func initialize(route_data: Dictionary) -> void:
	_route_data = route_data
	_update_ui()

func _update_ui() -> void:
	if _route_data.is_empty():
		return
		
	# Populate details from route_data
	# Note: Adjust keys based on actual API response structure for 'find_route'
	# Assuming: destination_name, distance, eta, resource_cost, vehicle_costs
	
	if destination_value:
		destination_value.text = str(_route_data.get("destination_name", "Unknown"))
	if distance_value:
		distance_value.text = "%.1f km" % float(_route_data.get("distance", 0.0))
	if eta_value:
		# Use basic formatting or a helper if available
		eta_value.text = str(_route_data.get("eta", "N/A"))
		
	var costs = _route_data.get("costs", {})
	if costs is Dictionary:
		if fuel_value: fuel_value.text = "%.1f" % float(costs.get("fuel", 0.0))
		if water_value: water_value.text = "%.1f" % float(costs.get("water", 0.0))
		if food_value: food_value.text = "%.1f" % float(costs.get("food", 0.0))

func _on_back_pressed() -> void:
	emit_signal("back_requested")

func _on_embark_pressed() -> void:
	# Tutorial resolver looks for 'journey_confirm_button' - ensure this button matches expectations or the flow uses this signal
	emit_signal("journey_started", _route_data)
