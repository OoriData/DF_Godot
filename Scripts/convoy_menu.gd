extends Control # Or Panel, VBoxContainer, etc., depending on your menu's root node

# Signal that MenuManager will listen for
signal back_requested # Ensure this line exists and is spelled correctly

# Optional: If your menu needs to display data passed from MenuManager
var convoy_data_received: Dictionary

# --- @onready vars for new labels ---
@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var location_label: Label = $VBoxContainer/LocationLabel
@onready var fuel_label: Label = $VBoxContainer/FuelLabel
@onready var water_label: Label = $VBoxContainer/WaterLabel
@onready var food_label: Label = $VBoxContainer/FoodLabel
@onready var speed_label: Label = $VBoxContainer/SpeedLabel
@onready var offroad_label: Label = $VBoxContainer/OffroadLabel
@onready var efficiency_label: Label = $VBoxContainer/EfficiencyLabel
@onready var cargo_volume_label: Label = $VBoxContainer/CargoVolumeLabel
@onready var cargo_weight_label: Label = $VBoxContainer/CargoWeightLabel
@onready var journey_dest_label: Label = $VBoxContainer/JourneyDestLabel
@onready var journey_progress_label: Label = $VBoxContainer/JourneyProgressLabel
@onready var journey_eta_label: Label = $VBoxContainer/JourneyETALabel
@onready var vehicles_label: Label = $VBoxContainer/VehiclesLabel
@onready var all_cargo_label: Label = $VBoxContainer/AllCargoLabel

func _ready():
	# IMPORTANT: Ensure you have a Button node in your ConvoyMenu.tscn scene
	# and that its name is "BackButton".
	# The third argument 'false' for find_child means 'owned by this node' is not checked,
	# which is usually fine for finding children within a scene instance.
	var back_button = find_child("BackButton", true, false) 

	if back_button and back_button is Button:
		# print("ConvoyMenu: BackButton found. Connecting its 'pressed' signal.") # DEBUG
		# Check if already connected to prevent duplicate connections if _ready is called multiple times (unlikely for menus but good practice)
		if not back_button.is_connected("pressed", Callable(self, "_on_back_button_pressed")):
			back_button.pressed.connect(_on_back_button_pressed, CONNECT_ONE_SHOT) # Use ONE_SHOT as menu is freed
	else:
		printerr("ConvoyMenu: CRITICAL - BackButton node NOT found or is not a Button. Ensure it's named 'BackButton' in ConvoyMenu.tscn.")

func _on_back_button_pressed():
	print("ConvoyMenu: Back button pressed. Emitting 'back_requested' signal.")
	emit_signal("back_requested")

func initialize_with_data(data: Dictionary):
		convoy_data_received = data.duplicate() # Duplicate to avoid modifying the original if needed
		# print("ConvoyMenu: Initialized with data: ", convoy_data_received) # DEBUG

		# --- Populate Convoy Overview & Status ---
		if is_instance_valid(name_label):
			name_label.text = "Name: %s (ID: %s)" % [convoy_data_received.get("convoy_name", "N/A"), convoy_data_received.get("convoy_id", "N/A")]
		if is_instance_valid(location_label):
			location_label.text = "Location: (%.1f, %.1f)" % [convoy_data_received.get("x", 0.0), convoy_data_received.get("y", 0.0)]
		if is_instance_valid(fuel_label):
			fuel_label.text = "Fuel: %.1f / %.1f" % [convoy_data_received.get("fuel", 0.0), convoy_data_received.get("max_fuel", 0.0)]
		if is_instance_valid(water_label):
			water_label.text = "Water: %.1f / %.1f" % [convoy_data_received.get("water", 0.0), convoy_data_received.get("max_water", 0.0)]
		if is_instance_valid(food_label):
			food_label.text = "Food: %.1f / %.1f" % [convoy_data_received.get("food", 0.0), convoy_data_received.get("max_food", 0.0)]
		if is_instance_valid(speed_label):
			speed_label.text = "Top Speed: %.1f" % convoy_data_received.get("top_speed", 0.0)
		if is_instance_valid(offroad_label):
			offroad_label.text = "Offroad: %.1f" % convoy_data_received.get("offroad_capability", 0.0)
		if is_instance_valid(efficiency_label):
			efficiency_label.text = "Efficiency: %.1f" % convoy_data_received.get("efficiency", 0.0)
		if is_instance_valid(cargo_volume_label):
			var used_volume = convoy_data_received.get("total_cargo_capacity", 0.0) - convoy_data_received.get("total_free_space", 0.0)
			cargo_volume_label.text = "Cargo Volume: %.1f / %.1f" % [used_volume, convoy_data_received.get("total_cargo_capacity", 0.0)]
		if is_instance_valid(cargo_weight_label):
			var used_weight = convoy_data_received.get("total_weight_capacity", 0.0) - convoy_data_received.get("total_remaining_capacity", 0.0)
			cargo_weight_label.text = "Cargo Weight: %.1f / %.1f" % [used_weight, convoy_data_received.get("total_weight_capacity", 0.0)]

		# --- Populate Journey Details ---
		var journey_data: Dictionary = convoy_data_received.get("journey", {})
		if is_instance_valid(journey_dest_label):
			journey_dest_label.text = "Destination: (%.1f, %.1f)" % [journey_data.get("dest_x", 0.0), journey_data.get("dest_y", 0.0)]
		if is_instance_valid(journey_progress_label):
			journey_progress_label.text = "Progress: %.1f / %.1f" % [journey_data.get("progress", 0.0), journey_data.get("length", 0.0)]
		if is_instance_valid(journey_eta_label):
			# Basic ETA display, you'll want to format this nicely later
			journey_eta_label.text = "ETA: %s" % journey_data.get("eta", "N/A")

		# --- Populate Vehicle Manifest (Simplified) ---
		if is_instance_valid(vehicles_label):
			var vehicle_list: Array = convoy_data_received.get("vehicle_details_list", [])
			var vehicle_names: Array = []
			for vehicle_detail in vehicle_list:
				if vehicle_detail is Dictionary:
					vehicle_names.append(vehicle_detail.get("name", "Unknown Vehicle"))
			vehicles_label.text = "Vehicles: " + ", ".join(vehicle_names)

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


# The _update_label function is no longer needed with this simplified structure.
# You can remove it or comment it out.
# func _update_label(node_path: String, text_content: Variant):
# 	...
