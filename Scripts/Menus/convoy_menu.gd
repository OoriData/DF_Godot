extends Control # Or Panel, VBoxContainer, etc., depending on your menu's root node

# Signal that MenuManager will listen for
signal back_requested # Ensure this line exists and is spelled correctly

# Optional: If your menu needs to display data passed from MenuManager
var convoy_data_received: Dictionary

# --- Font Scaling Parameters ---
const BASE_FONT_SIZE: float = 18.0  # Increased from 14.0
const BASE_TITLE_FONT_SIZE: float = 22.0 # Increased from 18.0
const REFERENCE_MENU_HEIGHT: float = 600.0 # The menu height at which BASE_FONT_SIZE looks best
const MIN_FONT_SIZE: float = 8.0
const MAX_FONT_SIZE: float = 24.0
const MAX_TITLE_FONT_SIZE: float = 30.0

# --- Color Constants for Styling ---
const COLOR_GREEN: Color = Color("66bb6a") # Material Green 400
const COLOR_YELLOW: Color = Color("ffee58") # Material Yellow 400
const COLOR_RED: Color = Color("ef5350")   # Material Red 400
const COLOR_BOX_FONT: Color = Color("000000") # Black font for boxes for contrast
const COLOR_PERFORMANCE_BOX_BG: Color = Color("666666") # Medium Gray
const COLOR_MENU_BUTTON_GREY_BG: Color = Color("b0b0b0") # Light-Medium Grey for menu buttons
const COLOR_PERFORMANCE_BOX_FONT: Color = Color.WHITE   # White

# --- @onready vars for new labels ---
# Paths updated to reflect the new TopBarHBox container in the scene.
@onready var title_label: Label = $MainVBox/TopBarHBox/TitleLabel

# Resource/Stat Boxes (Panel and inner Label)
@onready var fuel_box: Panel = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox/FuelBox
@onready var fuel_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox/FuelBox/FuelTextLabel
@onready var water_box: Panel = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox/WaterBox
@onready var water_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox/WaterBox/WaterTextLabel
@onready var food_box: Panel = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox/FoodBox
@onready var food_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/ResourceStatsHBox/FoodBox/FoodTextLabel

@onready var speed_box: Panel = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox/SpeedBox
@onready var speed_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox/SpeedBox/SpeedTextLabel
@onready var offroad_box: Panel = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox/OffroadBox
@onready var offroad_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox/OffroadBox/OffroadTextLabel
@onready var efficiency_box: Panel = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox/EfficiencyBox
@onready var efficiency_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/PerformanceStatsHBox/EfficiencyBox/EfficiencyTextLabel

# Cargo Progress Bars and Labels
@onready var cargo_volume_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/CargoVolumeContainer/CargoVolumeTextLabel
@onready var cargo_volume_bar: ProgressBar = $MainVBox/ScrollContainer/ContentVBox/CargoVolumeContainer/CargoVolumeBar
@onready var cargo_weight_text_label: Label = $MainVBox/ScrollContainer/ContentVBox/CargoWeightContainer/CargoWeightTextLabel
@onready var cargo_weight_bar: ProgressBar = $MainVBox/ScrollContainer/ContentVBox/CargoWeightContainer/CargoWeightBar

@onready var journey_dest_label: Label = $MainVBox/ScrollContainer/ContentVBox/JourneyDestLabel
@onready var journey_progress_label: Label = $MainVBox/ScrollContainer/ContentVBox/JourneyProgressLabel
@onready var journey_eta_label: Label = $MainVBox/ScrollContainer/ContentVBox/JourneyETALabel
@onready var vehicles_label: Label = $MainVBox/ScrollContainer/ContentVBox/VehiclesLabel
@onready var all_cargo_label: Label = $MainVBox/ScrollContainer/ContentVBox/AllCargoLabel
@onready var back_button: Button = $MainVBox/BackButton

# --- Placeholder Menu Buttons ---
@onready var vehicle_menu_button: Button = $MainVBox/ScrollContainer/ContentVBox/MenuButtons/VehicleMenuButton
@onready var journey_menu_button: Button = $MainVBox/ScrollContainer/ContentVBox/MenuButtons/JourneyMenuButton
@onready var settlement_menu_button: Button = $MainVBox/ScrollContainer/ContentVBox/MenuButtons/SettlementMenuButton
@onready var cargo_menu_button: Button = $MainVBox/ScrollContainer/ContentVBox/MenuButtons/CargoMenuButton

# --- Signals for Sub-Menu Navigation ---
signal open_vehicle_menu_requested(convoy_data)
signal open_journey_menu_requested(convoy_data)
signal open_settlement_menu_requested(convoy_data)
signal open_cargo_menu_requested(convoy_data)

func _ready():
	# --- DIAGNOSTIC: Check if UI nodes are valid ---
	if not is_instance_valid(title_label):
		printerr("ConvoyMenu: CRITICAL - TitleLabel node not found. Check the path in the script.")

	# IMPORTANT: Ensure you have a Button node in your ConvoyMenu.tscn scene
	# and that its name is "BackButton".
	# The third argument 'false' for find_child means 'owned by this node' is not checked,
	# which is usually fine for finding children within a scene instance.
	# var back_button = find_child("BackButton", true, false) # Now using @onready var

	if back_button and back_button is Button:
		# print("ConvoyMenu: BackButton found. Connecting its 'pressed' signal.") # DEBUG
		# Check if already connected to prevent duplicate connections if _ready is called multiple times (unlikely for menus but good practice)
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed, CONNECT_ONE_SHOT) # Use ONE_SHOT as menu is freed
	else:
		printerr("ConvoyMenu: CRITICAL - BackButton node NOT found or is not a Button. Ensure it's named 'BackButton' in ConvoyMenu.tscn.")

	# Connect placeholder menu buttons
	if is_instance_valid(vehicle_menu_button):
		if not vehicle_menu_button.is_connected("pressed", Callable(self, "_on_vehicle_menu_button_pressed")):
			_style_menu_button(vehicle_menu_button)
			vehicle_menu_button.pressed.connect(_on_vehicle_menu_button_pressed)
	if is_instance_valid(journey_menu_button):
		if not journey_menu_button.is_connected("pressed", Callable(self, "_on_journey_menu_button_pressed")):
			_style_menu_button(journey_menu_button)
			journey_menu_button.pressed.connect(_on_journey_menu_button_pressed)
	if is_instance_valid(settlement_menu_button):
		if not settlement_menu_button.is_connected("pressed", Callable(self, "_on_settlement_menu_button_pressed")):
			_style_menu_button(settlement_menu_button)
			settlement_menu_button.pressed.connect(_on_settlement_menu_button_pressed)
	if is_instance_valid(cargo_menu_button):
		if not cargo_menu_button.is_connected("pressed", Callable(self, "_on_cargo_menu_button_pressed")):
			_style_menu_button(cargo_menu_button)
			cargo_menu_button.pressed.connect(_on_cargo_menu_button_pressed)

	# Initial font size update
	call_deferred("_update_font_sizes")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		# Call deferred to ensure the new size is fully applied before calculating font sizes
		call_deferred("_update_font_sizes")

func _on_back_button_pressed():
	print("ConvoyMenu: Back button pressed. Emitting 'back_requested' signal.")
	emit_signal("back_requested")

func initialize_with_data(data: Dictionary):
		convoy_data_received = data.duplicate() # Duplicate to avoid modifying the original if needed
		# print("ConvoyMenu: Initialized with data: ", convoy_data_received) # DEBUG

		# --- Convoy Name as Title ---
		if is_instance_valid(title_label):
			title_label.text = convoy_data_received.get("convoy_name", "N/A")

		# --- Resources (Fuel, Water, Food) ---
		var current_fuel = convoy_data_received.get("fuel", 0.0)
		var max_fuel = convoy_data_received.get("max_fuel", 0.0)
		if is_instance_valid(fuel_text_label): fuel_text_label.text = "Fuel: %.1f / %.1f" % [current_fuel, max_fuel]
		if is_instance_valid(fuel_box): _set_resource_box_style(fuel_box, fuel_text_label, current_fuel, max_fuel)

		var current_water = convoy_data_received.get("water", 0.0)
		var max_water = convoy_data_received.get("max_water", 0.0)
		if is_instance_valid(water_text_label): water_text_label.text = "Water: %.1f / %.1f" % [current_water, max_water]
		if is_instance_valid(water_box): _set_resource_box_style(water_box, water_text_label, current_water, max_water)

		var current_food = convoy_data_received.get("food", 0.0)
		var max_food = convoy_data_received.get("max_food", 0.0)
		if is_instance_valid(food_text_label): food_text_label.text = "Food: %.1f / %.1f" % [current_food, max_food]
		if is_instance_valid(food_box): _set_resource_box_style(food_box, food_text_label, current_food, max_food)

		# --- Performance Stats (Speed, Offroad, Efficiency) ---
		# Assuming these are rated 0-100 for coloring, adjust max_value if different
		var top_speed = convoy_data_received.get("top_speed", 0.0)
		if is_instance_valid(speed_text_label): speed_text_label.text = "Top Speed: %.1f" % top_speed
		if is_instance_valid(speed_box): _set_fixed_color_box_style(speed_box, speed_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)

		var offroad = convoy_data_received.get("offroad_capability", 0.0)
		if is_instance_valid(offroad_text_label): offroad_text_label.text = "Offroad: %.1f" % offroad
		if is_instance_valid(offroad_box): _set_fixed_color_box_style(offroad_box, offroad_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)

		var efficiency = convoy_data_received.get("efficiency", 0.0)
		if is_instance_valid(efficiency_text_label): efficiency_text_label.text = "Efficiency: %.1f" % efficiency
		if is_instance_valid(efficiency_box): _set_fixed_color_box_style(efficiency_box, efficiency_text_label, COLOR_PERFORMANCE_BOX_BG, COLOR_PERFORMANCE_BOX_FONT)

		# --- Cargo Volume and Weight Bars ---
		if is_instance_valid(cargo_volume_text_label) and is_instance_valid(cargo_volume_bar):
			var used_volume = convoy_data_received.get("total_cargo_capacity", 0.0) - convoy_data_received.get("total_free_space", 0.0)
			var total_volume = convoy_data_received.get("total_cargo_capacity", 0.0)
			cargo_volume_text_label.text = "Cargo Volume: %.1f / %.1f" % [used_volume, total_volume]
			_set_progressbar_style(cargo_volume_bar, used_volume, total_volume)
		if is_instance_valid(cargo_weight_text_label) and is_instance_valid(cargo_weight_bar):
			var used_weight = convoy_data_received.get("total_weight_capacity", 0.0) - convoy_data_received.get("total_remaining_capacity", 0.0)
			var total_weight = convoy_data_received.get("total_weight_capacity", 0.0)
			cargo_weight_text_label.text = "Cargo Weight: %.1f / %.1f" % [used_weight, total_weight]
			_set_progressbar_style(cargo_weight_bar, used_weight, total_weight)

		# --- Populate Journey Details ---
		# Assuming journey_data contains "destination_name", "progress", "length", and "eta" (as a timestamp)
		var journey_data = convoy_data_received.get("journey")
		if journey_data == null:
			journey_data = {}
		if is_instance_valid(journey_dest_label):
			var dest_text: String = "Destination: N/A"
			if not journey_data.is_empty():
				# Assuming journey_data contains destination coordinates, e.g., 'dest_coord_x', 'dest_coord_y'
				# Adjust these keys if your data structure is different.
				var dest_coord_x_val # Can be float or int
				var dest_coord_y_val # Can be float or int

				var direct_x = journey_data.get("dest_coord_x")
				var direct_y = journey_data.get("dest_coord_y")

				if direct_x != null and direct_y != null:
					dest_coord_x_val = direct_x
					dest_coord_y_val = direct_y
				else:
					# Fallback: Try to get destination from the end of route_x and route_y arrays
					var route_x_arr: Array = journey_data.get("route_x", [])
					var route_y_arr: Array = journey_data.get("route_y", [])
					if not route_x_arr.is_empty() and not route_y_arr.is_empty():
						if route_x_arr.size() == route_y_arr.size(): # Ensure arrays are consistent
							dest_coord_x_val = route_x_arr[-1] # Get last element
							dest_coord_y_val = route_y_arr[-1] # Get last element
						else:
							printerr("ConvoyMenu: route_x and route_y arrays have different sizes.")
							# dest_coord_x_val and dest_coord_y_val remain null (or unassigned)
					# If still null here, the next check will handle it.

				if dest_coord_x_val != null and dest_coord_y_val != null:
					var gdm = get_node_or_null("/root/GameDataManager") # Access the GameDataManager singleton
					if is_instance_valid(gdm):
						# Convert/round float coordinates to int for map lookup
						var dest_x_int: int = roundi(float(dest_coord_x_val)) # Cast to float then round to int
						var dest_y_int: int = roundi(float(dest_coord_y_val))
						if gdm.has_method("get_settlement_name_from_coords"):
							var settlement_name: String = gdm.get_settlement_name_from_coords(dest_x_int, dest_y_int)
							if settlement_name.begins_with("N/A"): # Check if lookup failed
								dest_text = "Destination: %s (at %.1f, %.1f)" % [settlement_name, dest_coord_x_val, dest_coord_y_val]
								printerr("ConvoyMenu: Could not find settlement name for coords: ", dest_x_int, ", ", dest_y_int, ". GDM returned: ", settlement_name)
							else:
								dest_text = "Destination: %s" % settlement_name
						else:
							dest_text = "Destination: GDM Method Error (at %.1f, %.1f)" % [dest_coord_x_val, dest_coord_y_val]
							printerr("ConvoyMenu: GameDataManager does not have 'get_settlement_name_from_coords' method.")
					else:
						dest_text = "Destination: GDM Node Missing (at %.1f, %.1f)" % [dest_coord_x_val, dest_coord_y_val]
						printerr("ConvoyMenu: GameDataManager node not found.")
				else:
					dest_text = "Destination: No coordinates"
			journey_dest_label.text = dest_text

		if is_instance_valid(journey_progress_label):
			var progress = journey_data.get("progress", 0.0)
			var length = journey_data.get("length", 0.0)
			var progress_percentage = 0.0
			if length > 0:
				progress_percentage = (progress / length) * 100.0
			# Display progress as a percentage
			journey_progress_label.text = "Progress: %.1f%%" % progress_percentage

		if is_instance_valid(journey_eta_label):
			var eta_value = journey_data.get("eta")
			var formatted_eta: String = preload("res://Scripts/System/date_time_util.gd").format_timestamp_display(eta_value, true)
			journey_eta_label.text = "ETA: " + formatted_eta

		# --- Populate Vehicle Manifest (Simplified) ---
		if is_instance_valid(vehicles_label):
			var vehicle_list: Array = convoy_data_received.get("vehicle_details_list", [])
			var vehicle_display_strings: Array = []
			for vehicle_detail in vehicle_list:
				if vehicle_detail is Dictionary:
					var v_name = vehicle_detail.get("name", "Unknown Vehicle")
					var v_make_model = vehicle_detail.get("make_model", "")
					if not v_make_model.is_empty():
						vehicle_display_strings.append("- %s (%s)" % [v_name, v_make_model])
					else:
						vehicle_display_strings.append("- %s" % v_name)
			vehicles_label.text = "Vehicles:\n" + "\n".join(vehicle_display_strings)

		# --- Populate Cargo Details (Simplified) ---
		if is_instance_valid(all_cargo_label):
			var all_cargo_list: Array = convoy_data_received.get("all_cargo", [])
			var cargo_summary: Array = []
			var cargo_counts: Dictionary = {}
			for cargo_item in all_cargo_list:
				if cargo_item is Dictionary:
					var item_name = cargo_item.get("name", "Unknown Item")
					cargo_counts[item_name] = cargo_counts.get(item_name, 0) + cargo_item.get("quantity", 0)
			for item_name in cargo_counts:
				cargo_summary.append("%s x%s" % [item_name, cargo_counts[item_name]])
			all_cargo_label.text = "Cargo: " + ", ".join(cargo_summary)
		
		# Initial font size update after data is populated
		call_deferred("_update_font_sizes")

# --- Placeholder Button Handlers ---
func _on_vehicle_menu_button_pressed():
	print("ConvoyMenu: Vehicle Menu button pressed. Emitting 'open_vehicle_menu_requested'.")
	emit_signal("open_vehicle_menu_requested", convoy_data_received)

func _on_journey_menu_button_pressed():
	print("ConvoyMenu: Journey Menu button pressed. Emitting 'open_journey_menu_requested'.")
	emit_signal("open_journey_menu_requested", convoy_data_received)

func _on_settlement_menu_button_pressed():
	print("ConvoyMenu: Settlement Menu button pressed. Emitting 'open_settlement_menu_requested'.")
	emit_signal("open_settlement_menu_requested", convoy_data_received)

func _on_cargo_menu_button_pressed():
	print("ConvoyMenu: Cargo Menu button pressed. Emitting 'open_cargo_menu_requested'.")
	emit_signal("open_cargo_menu_requested", convoy_data_received)

func _get_color_for_percentage(percentage: float) -> Color:
	if percentage > 0.7:
		return COLOR_GREEN
	elif percentage > 0.3:
		return COLOR_YELLOW
	else:
		return COLOR_RED

func _set_resource_box_style(panel_node: Panel, label_node: Label, current_value: float, max_value: float):
	if not is_instance_valid(panel_node) or not is_instance_valid(label_node):
		return

	var percentage: float = 0.0
	if max_value > 0:
		percentage = clamp(current_value / max_value, 0.0, 1.0)
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = _get_color_for_percentage(percentage)
	style_box.corner_radius_top_left = 3
	style_box.corner_radius_top_right = 3
	style_box.corner_radius_bottom_left = 3
	style_box.corner_radius_bottom_right = 3
	panel_node.add_theme_stylebox_override("panel", style_box)
	label_node.add_theme_color_override("font_color", COLOR_BOX_FONT)

func _set_fixed_color_box_style(panel_node: Panel, label_node: Label, p_bg_color: Color, p_font_color: Color):
	if not is_instance_valid(panel_node) or not is_instance_valid(label_node):
		return

	var style_box = StyleBoxFlat.new()
	style_box.bg_color = p_bg_color
	style_box.corner_radius_top_left = 3
	style_box.corner_radius_top_right = 3
	style_box.corner_radius_bottom_left = 3
	style_box.corner_radius_bottom_right = 3
	panel_node.add_theme_stylebox_override("panel", style_box)
	label_node.add_theme_color_override("font_color", p_font_color)


func _set_progressbar_style(progressbar_node: ProgressBar, current_value: float, max_value: float):
	if not is_instance_valid(progressbar_node):
		return
	
	var percentage: float = 0.0
	if max_value > 0:
		percentage = clamp(current_value / max_value, 0.0, 1.0)
		progressbar_node.value = percentage * 100.0
	else:
		progressbar_node.value = 0.0

	var fill_style_box = StyleBoxFlat.new()
	fill_style_box.bg_color = _get_color_for_percentage(percentage)
	progressbar_node.add_theme_stylebox_override("fill", fill_style_box)

func _update_font_sizes() -> void:
	if REFERENCE_MENU_HEIGHT <= 0:
		printerr("ConvoyMenu: REFERENCE_MENU_HEIGHT is not positive. Cannot scale fonts.")
		return

	var current_menu_height: float = self.size.y
	if current_menu_height <= 0: # Menu might not have a size yet if called too early
		return

	var scale_factor: float = current_menu_height / REFERENCE_MENU_HEIGHT

	var new_font_size: int = clamp(int(BASE_FONT_SIZE * scale_factor), MIN_FONT_SIZE, MAX_FONT_SIZE)
	var new_title_font_size: int = clamp(int(BASE_TITLE_FONT_SIZE * scale_factor), MIN_FONT_SIZE, MAX_TITLE_FONT_SIZE)

	var labels_to_scale: Array[Label] = [
		fuel_text_label, water_text_label, food_text_label,
		speed_text_label, offroad_text_label, efficiency_text_label,
		cargo_volume_text_label, cargo_weight_text_label,
		journey_dest_label, journey_progress_label, journey_eta_label,
		vehicles_label, all_cargo_label,
		# Add text of placeholder buttons if they need scaling
		# vehicle_menu_button, journey_menu_button, 
		# settlement_menu_button, cargo_menu_button 
	]
	# title_label is handled separately as it's the main convoy name title

	if is_instance_valid(title_label):
		title_label.add_theme_font_size_override("font_size", new_title_font_size)

	for label_node in labels_to_scale:
		if is_instance_valid(label_node):
			label_node.add_theme_font_size_override("font_size", new_font_size)

	if is_instance_valid(back_button):
		back_button.add_theme_font_size_override("font_size", new_font_size)
	
	# Scale placeholder button fonts if they are valid
	if is_instance_valid(vehicle_menu_button):
		vehicle_menu_button.add_theme_font_size_override("font_size", new_font_size)
	if is_instance_valid(journey_menu_button):
		journey_menu_button.add_theme_font_size_override("font_size", new_font_size)
	if is_instance_valid(settlement_menu_button):
		settlement_menu_button.add_theme_font_size_override("font_size", new_font_size)
	if is_instance_valid(cargo_menu_button):
		cargo_menu_button.add_theme_font_size_override("font_size", new_font_size)

	# print("ConvoyMenu: Updated font sizes. Scale: %.2f, Base: %d, Title: %d" % [scale_factor, new_font_size, new_title_font_size]) # DEBUG


func _style_menu_button(button_node: Button) -> void:
	if not is_instance_valid(button_node):
		return

	var style_box_normal = StyleBoxFlat.new()
	style_box_normal.bg_color = COLOR_MENU_BUTTON_GREY_BG
	style_box_normal.corner_radius_top_left = 3
	style_box_normal.corner_radius_top_right = 3
	style_box_normal.corner_radius_bottom_left = 3
	style_box_normal.corner_radius_bottom_right = 3
	button_node.add_theme_stylebox_override("normal", style_box_normal)
	button_node.add_theme_color_override("font_color", COLOR_BOX_FONT) # Using black for contrast

# The _update_label function is no longer needed with this simplified structure.
# You can remove it or comment it out.
# func _update_label(node_path: String, text_content: Variant):
# 	...
