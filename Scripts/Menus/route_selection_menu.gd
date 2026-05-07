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
	
	if _is_mobile():
		_apply_mobile_scaling()

func _is_portrait() -> bool:
	if is_inside_tree():
		var win_size = get_viewport().get_visible_rect().size
		return win_size.y > win_size.x
	return false

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or DisplayServer.get_name() in ["Android", "iOS"] or _is_portrait()

func _get_font_size(base: int) -> int:
	var boost = 2.4 if _is_portrait() else (1.7 if _is_mobile() else 1.2)
	return int(base * boost)

func _apply_mobile_scaling() -> void:
	var is_port = _is_portrait()
	
	# Switch to vertical layout if portrait
	if is_port:
		var columns_hbox = $MainVBox/ColumnsHBox
		if columns_hbox is HBoxContainer:
			# We can't change the class, but we can change the layout
			# Actually, ColumnHBox is a fixed name. 
			# Let's just adjust the separation and flags if we can't change class.
			# Better: if we really want VBox behavior, we'd need to re-parent or change class in scene.
			# But we can simulate it by expanding children.
			for child in columns_hbox.get_children():
				child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Scaling fonts
	_apply_font_scaling_recursive(self)
	
	# Scaling buttons
	if back_button:
		back_button.custom_minimum_size = Vector2(240 if is_port else 180, 100 if is_port else 80)
	if embark_button:
		embark_button.custom_minimum_size = Vector2(240 if is_port else 180, 100 if is_port else 80)
		
	# Adjust MainVBox margin (offset)
	var main_vbox = $MainVBox
	main_vbox.offset_left = 16
	main_vbox.offset_right = -16
	main_vbox.offset_top = 24
	main_vbox.offset_bottom = -24

func _apply_font_scaling_recursive(node: Node) -> void:
	if node is Label:
		var current_fs = node.get_theme_font_size("font_size")
		if current_fs <= 1: 
			if node.name.contains("Title"): current_fs = 24
			else: current_fs = 14
		node.add_theme_font_size_override("font_size", _get_font_size(current_fs))
	elif node is Button:
		node.add_theme_font_size_override("font_size", _get_font_size(16))
	
	for child in node.get_children():
		_apply_font_scaling_recursive(child)

func initialize(route_data: Dictionary) -> void:
	_route_data = route_data
	_update_ui()

func _update_ui() -> void:
	if _route_data.is_empty():
		return
		
	if destination_value:
		destination_value.text = str(_route_data.get("destination_name", "Unknown"))
	if distance_value:
		distance_value.text = NumberFormat.fmt_float(_route_data.get("distance", 0.0), 2) + " km"
	if eta_value:
		eta_value.text = str(_route_data.get("eta", "N/A"))
		
	var costs = _route_data.get("costs", {})
	if costs is Dictionary:
		if fuel_value: fuel_value.text = NumberFormat.fmt_float(costs.get("fuel", 0.0), 2)
		if water_value: water_value.text = NumberFormat.fmt_float(costs.get("water", 0.0), 2)
		if food_value: food_value.text = NumberFormat.fmt_float(costs.get("food", 0.0), 2)

func _on_back_pressed() -> void:
	emit_signal("back_requested")

func _on_embark_pressed() -> void:
	emit_signal("journey_started", _route_data)
