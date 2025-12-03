extends Control # Or Panel, VBoxContainer, etc., depending on your menu's root node

# Signal that MenuManager will listen for
signal back_requested # Ensure this line exists and is spelled correctly

# Optional: If your menu needs to display data passed from MenuManager
var convoy_data_received: Dictionary

# Classification helpers from centralized item data
const ItemsData = preload("res://Scripts/Data/Items.gd")

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
@onready var mission_cargo_preview_label: Label = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/MissionCargoLabel
@onready var compatible_parts_preview_label: Label = $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel/VendorPreviewVBox/CompatiblePartsLabel
@onready var back_button: Button = $MainVBox/BottomBackHBox/BackButton

# --- Placeholder Menu Buttons ---
@onready var vehicle_menu_button: Button = $MainVBox/BottomBarPanel/BottomMenuButtonsHBox/VehicleMenuButton
@onready var journey_menu_button: Button = $MainVBox/BottomBarPanel/BottomMenuButtonsHBox/JourneyMenuButton
@onready var settlement_menu_button: Button = $MainVBox/BottomBarPanel/BottomMenuButtonsHBox/SettlementMenuButton
@onready var cargo_menu_button: Button = $MainVBox/BottomBarPanel/BottomMenuButtonsHBox/CargoMenuButton

# --- Signals for Sub-Menu Navigation ---
signal open_vehicle_menu_requested(convoy_data)
signal open_journey_menu_requested(convoy_data)
signal open_settlement_menu_requested(convoy_data)
signal open_cargo_menu_requested(convoy_data)

# Cached GDM reference
var _gdm: Node = null
var _debug_convoy_menu: bool = true # toggle verbose diagnostics for this menu
var _latest_all_settlements: Array = [] # cached list from GDM settlement_data_updated

func _ready():
	# --- DIAGNOSTIC: Check if UI nodes are valid ---
	if not is_instance_valid(title_label):
		printerr("ConvoyMenu: CRITICAL - TitleLabel node not found. Check the path in the script.")

	# Style bottom bar panel if present
	var bottom_panel := $MainVBox/BottomBarPanel if has_node("MainVBox/BottomBarPanel") else null
	if is_instance_valid(bottom_panel):
		var bar_style := StyleBoxFlat.new()
		bar_style.bg_color = Color(0.18, 0.18, 0.18, 0.85)
		bar_style.corner_radius_top_left = 6
		bar_style.corner_radius_top_right = 6
		bar_style.border_width_top = 1
		bar_style.border_color = Color(0.28, 0.28, 0.28)
		bottom_panel.add_theme_stylebox_override("panel", bar_style)

	# Style vendor preview panel if present
	var vendor_preview_panel := $MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel if has_node("MainVBox/ScrollContainer/ContentVBox/VendorPreviewPanel") else null
	if is_instance_valid(vendor_preview_panel):
		var vp_style := StyleBoxFlat.new()
		vp_style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
		vp_style.corner_radius_top_left = 6
		vp_style.corner_radius_top_right = 6
		vp_style.corner_radius_bottom_left = 6
		vp_style.corner_radius_bottom_right = 6
		vp_style.border_width_left = 1
		vp_style.border_width_right = 1
		vp_style.border_width_top = 1
		vp_style.border_width_bottom = 1
		vp_style.border_color = Color(0.25, 0.35, 0.55, 0.9)
		vp_style.shadow_color = Color(0,0,0,0.45)
		vp_style.shadow_size = 4
		vendor_preview_panel.add_theme_stylebox_override("panel", vp_style)
		# Adjust inner label colors slightly for readability
		if is_instance_valid(mission_cargo_preview_label):
			mission_cargo_preview_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
		if is_instance_valid(compatible_parts_preview_label):
			compatible_parts_preview_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))

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

	# Cache GameDataManager and connect relevant signals for live updates
	_gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(_gdm):
		# Opportunistically warm vendor caches for this settlement to populate missions
		if convoy_data_received != null and convoy_data_received.has("x") and convoy_data_received.has("y"):
			var warm_x := roundi(float(convoy_data_received.get("x", 0)))
			var warm_y := roundi(float(convoy_data_received.get("y", 0)))
			if _gdm.has_method("_request_settlement_vendor_data_at_coords"):
				_gdm.call("_request_settlement_vendor_data_at_coords", warm_x, warm_y)
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] requested vendor warm-up at (", warm_x, ",", warm_y, ")")
		# Refresh vendor preview when mechanics compatibility updates arrive
		if _gdm.has_signal("mechanic_vendor_slot_availability") and not _gdm.mechanic_vendor_slot_availability.is_connected(_on_mech_vendor_availability):
			_gdm.mechanic_vendor_slot_availability.connect(_on_mech_vendor_availability)
		if _gdm.has_signal("part_compatibility_ready") and not _gdm.part_compatibility_ready.is_connected(_on_part_compat_ready):
			_gdm.part_compatibility_ready.connect(_on_part_compat_ready)
		# Refresh when vendor panel data becomes ready (post warm-up)
		if _gdm.has_signal("vendor_panel_data_ready") and not _gdm.vendor_panel_data_ready.is_connected(_on_vendor_panel_ready):
			_gdm.vendor_panel_data_ready.connect(_on_vendor_panel_ready)
		# Also refresh on settlement/vendor changes if available
		if _gdm.has_signal("settlement_data_updated") and not _gdm.settlement_data_updated.is_connected(_on_settlement_data_updated):
			_gdm.settlement_data_updated.connect(_on_settlement_data_updated)
		# New: If initial_data_ready fires after this menu opens, refresh preview
		if _gdm.has_signal("initial_data_ready") and not _gdm.initial_data_ready.is_connected(_on_initial_data_ready):
			_gdm.initial_data_ready.connect(_on_initial_data_ready)
		# Attempt to prime cached settlements immediately if GDM already has them
		if _gdm.has_method("get_all_settlements_data"):
			var pre_cached = _gdm.get_all_settlements_data()
			if pre_cached is Array and not (pre_cached as Array).is_empty():
				_latest_all_settlements = pre_cached
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] pre-cached all_settlements count=", _latest_all_settlements.size())

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

		# --- Populate Journey Details (or hide them if no journey) ---
		var journey_data = convoy_data_received.get("journey")
		var has_journey = journey_data != null and not journey_data.is_empty()

		# Set visibility of all journey-related labels
		if is_instance_valid(journey_dest_label): journey_dest_label.visible = has_journey
		if is_instance_valid(journey_progress_label): journey_progress_label.visible = has_journey
		if is_instance_valid(journey_eta_label): journey_eta_label.visible = has_journey

		# Only populate the labels if there is a journey
		if has_journey:
			if is_instance_valid(journey_dest_label):
				var dest_text: String = "Destination: N/A"
				# Assuming journey_data contains destination coordinates, e.g., 'dest_coord_x', 'dest_coord_y'
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

		# --- Vendor Preview ---
		# Kick off a mechanics probe/warm-up so compatibility can populate
		if is_instance_valid(_gdm):
			if _gdm.has_method("warm_mechanics_data_for_convoy"):
				_gdm.warm_mechanics_data_for_convoy(convoy_data_received)
			elif _gdm.has_method("start_mechanics_probe_session"):
				var cid := String(convoy_data_received.get("convoy_id", ""))
				if cid != "":
					_gdm.start_mechanics_probe_session(cid)
		_update_vendor_preview()
		
		# Initial font size update after data is populated
		call_deferred("_update_font_sizes")

func _update_vendor_preview() -> void:
	if convoy_data_received == null:
		return
	# Mission cargo preview: show items marked mission-critical if present
	if is_instance_valid(mission_cargo_preview_label):
		var convoy_missions: Array = _collect_mission_cargo_items(convoy_data_received)
		var settlement_missions: Array = _collect_settlement_mission_items()
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] convoy_missions count=", convoy_missions.size(), " items=", convoy_missions)
			print("[ConvoyMenu][Debug] settlement_missions count=", settlement_missions.size(), " items=", settlement_missions)
		var convoy_line := "Convoy Missions: " + (", ".join(convoy_missions) if convoy_missions.size() > 0 else "None")
		var settlement_line := "Settlement Missions: " + (", ".join(settlement_missions) if settlement_missions.size() > 0 else "None")
		# Provide a helpful hint when settlement missions are None
		if settlement_missions.is_empty():
			var sx: int = 0
			var sy: int = 0
			if convoy_data_received != null and convoy_data_received.has("x") and convoy_data_received.has("y"):
				sx = roundi(float(convoy_data_received.get("x", 0)))
				sy = roundi(float(convoy_data_received.get("y", 0)))
			settlement_line += " (at %d,%d)" % [sx, sy]
		mission_cargo_preview_label.text = convoy_line + "\n" + settlement_line

	# Compatible parts preview: use GDM mechanic vendor availability snapshot if available
	if is_instance_valid(compatible_parts_preview_label):
		var compat_summary: Array = []
		if is_instance_valid(_gdm) and _gdm.has_method("get_mechanic_probe_snapshot"):
			var snap: Dictionary = _gdm.get_mechanic_probe_snapshot()
			if _debug_convoy_menu:
				print("[ConvoyMenu][Debug] mech_probe_snapshot keys=", snap.keys())
			# Prefer showing actual part names using cargo_id enrichment
			var part_names: Array[String] = []
			var c2s: Dictionary = snap.get("cargo_id_to_slot", {}) if snap.has("cargo_id_to_slot") else {}
			if c2s is Dictionary and not c2s.is_empty():
				# Attempt to fetch enriched cargo names for each cargo_id
				if _gdm.has_method("get_enriched_cargo"):
					for cid in c2s.keys():
						var cargo: Dictionary = _gdm.get_enriched_cargo(String(cid))
						var nm := String(cargo.get("name", cargo.get("base_name", "")))
						if nm == "" and _gdm.has_method("ensure_cargo_details"):
							# Trigger enrichment for future updates
							_gdm.ensure_cargo_details(String(cid))
						if nm != "":
							part_names.append(nm)
			# If names are still empty, fall back to slot summary counts
			if part_names.is_empty():
				if c2s is Dictionary and not c2s.is_empty():
					var slot_counts: Dictionary = {}
					for cid in c2s.keys():
						var slot_name: String = String(c2s.get(cid, ""))
						if slot_name != "":
							slot_counts[slot_name] = int(slot_counts.get(slot_name, 0)) + 1
					for sname in slot_counts.keys():
						compat_summary.append("%s (%d)" % [String(sname), int(slot_counts.get(sname, 0))])
			# If we found names, use them directly
			if not part_names.is_empty():
				compat_summary = part_names
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] compat_summary=", compat_summary)
		compatible_parts_preview_label.text = "Compatible Parts: " + (", ".join(compat_summary) if compat_summary.size() > 0 else "None detected")

func _collect_mission_cargo_items(convoy: Dictionary) -> Array:
	# Mirror vendor_trade_panel.gd logic to avoid mismatches.
	# Rules:
	# 1) Prefer vehicle.cargo_items_typed entries where typed.category == "mission".
	# 2) Else, treat raw cargo entries as mission if they have non-null `recipient` or `delivery_reward`.
	# 3) Skip items that represent intrinsic parts (have `intrinsic_part_id`).
	# 4) If no per-vehicle cargo found, fall back to `convoy.cargo_inventory` with the same rules.
	var out: Array = []
	var found_any_cargo := false
	var agg: Dictionary = {} # name -> total quantity
	var diag_typed_mission := 0
	var diag_raw_mission := 0
	var diag_allcargo_mission := 0
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] start mission aggregation. convoy keys=", convoy.keys())

	if convoy.has("vehicle_details_list") and convoy.vehicle_details_list is Array:
		for vehicle in convoy.vehicle_details_list:
			var vname := String((vehicle as Dictionary).get("name", "Vehicle")) if vehicle is Dictionary else "Vehicle"
			if _debug_convoy_menu:
				var typed_sz := 0
				if vehicle is Dictionary and vehicle.has("cargo_items_typed") and vehicle["cargo_items_typed"] is Array:
					typed_sz = (vehicle["cargo_items_typed"] as Array).size()
				var raw_sz := 0
				if vehicle is Dictionary and vehicle.has("cargo") and vehicle["cargo"] is Array:
					raw_sz = (vehicle["cargo"] as Array).size()
				print("[ConvoyMenu][Debug] vehicle=", vname, " typed_sz=", typed_sz, " raw_sz=", raw_sz)
			# Typed cargo path
			if vehicle.has("cargo_items_typed") and vehicle["cargo_items_typed"] is Array and not (vehicle["cargo_items_typed"] as Array).is_empty():
				for typed in vehicle["cargo_items_typed"]:
					# Accept both typed objects (Resource) and plain dictionaries
					var typed_cat := ""
					if typed is Dictionary:
						typed_cat = String((typed as Dictionary).get("category", ""))
					else:
						# GDScript Resources don't have has(), use get()
						var cat_any = typed.get("category") if typed is Object else null
						if cat_any != null:
							typed_cat = String(cat_any)
					if _debug_convoy_menu:
						print("[ConvoyMenu][Debug] typed item cat=", typed_cat, " q=", (typed.get("quantity") if typed is Object else ((typed as Dictionary).get("quantity", null) if typed is Dictionary else null)))
					found_any_cargo = true
					if typed_cat == "mission":
						var raw_item: Dictionary = {}
						if typed is Dictionary:
							raw_item = (typed as Dictionary).get("raw", {})
						else:
							# Try property access via get() on Resource
							var raw_any = typed.get("raw") if typed is Object else null
							if raw_any is Dictionary:
								raw_item = raw_any
						if raw_item.is_empty():
							continue
						# Exclude parts to avoid double-counting parts as mission cargo
						if _is_part_item(raw_item):
							if _debug_convoy_menu:
								print("[ConvoyMenu][Debug] skip typed mission (part) name=", String(raw_item.get("name", "Item")))
							continue
						if raw_item.has("intrinsic_part_id") and raw_item.get("intrinsic_part_id") != null:
							continue
						var item_name := String(raw_item.get("name", "Item"))
						var qty := 1
						if typed is Dictionary:
							qty = int((typed as Dictionary).get("quantity", 1))
						else:
							var q_any = typed.get("quantity") if typed is Object else null
							if q_any != null:
								qty = int(q_any)
						agg[item_name] = int(agg.get(item_name, 0)) + qty
						diag_typed_mission += 1
				# Also scan raw cargo for mission items regardless of typed presence
				var cargo_arr: Array = vehicle.get("cargo", [])
				if cargo_arr is Array and not cargo_arr.is_empty():
					for item in cargo_arr:
						found_any_cargo = true
						if not (item is Dictionary):
							continue
						if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
							continue
						if _looks_like_mission_item(item):
							var item_name2 := String(item.get("name", "Item"))
							var qty2 := int(item.get("quantity", 1))
							if _debug_convoy_menu:
								print("[ConvoyMenu][Debug] raw mission item=", item_name2, " q=", qty2)
							agg[item_name2] = int(agg.get(item_name2, 0)) + qty2
							diag_raw_mission += 1

	# Fallback to convoy-level inventory if nothing was found in vehicles
	if not found_any_cargo and convoy.has("cargo_inventory") and convoy.cargo_inventory is Array:
		for item in convoy.cargo_inventory:
			if not (item is Dictionary):
				continue
			if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
				continue
			if _looks_like_mission_item(item):
				var item_name3 := String(item.get("name", "Item"))
				var qty3 := int(item.get("quantity", 1))
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] inventory mission item=", item_name3, " q=", qty3)
				agg[item_name3] = int(agg.get(item_name3, 0)) + qty3
				diag_raw_mission += 1

	# Also scan convoy-level all_cargo for mission stacks
	var all_cargo: Array = convoy.get("all_cargo", [])
	if all_cargo is Array and not all_cargo.is_empty():
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] scanning all_cargo sz=", all_cargo.size())
		for ac in all_cargo:
			if not (ac is Dictionary):
				continue
			if ac.has("intrinsic_part_id") and ac.get("intrinsic_part_id") != null:
				continue
			if _looks_like_mission_item(ac):
				var aname := String(ac.get("name", "Item"))
				var aq := int(ac.get("quantity", 1))
				agg[aname] = int(agg.get(aname, 0)) + (aq if aq > 0 else 1)
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] all_cargo mission item=", aname, " q=", aq)
				diag_allcargo_mission += 1

	# Build display strings from aggregated totals
	for k in agg.keys():
		out.append("%s x%s" % [String(k), int(agg[k])])
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] mission agg result=", out)
		print("[ConvoyMenu][Debug] diag typed=", diag_typed_mission, " raw=", diag_raw_mission, " all=", diag_allcargo_mission)
	return out

func _is_resource_item(d: Dictionary) -> bool:
	if not d:
		return false
	# Prefer centralized classification
	if ItemsData != null and ItemsData.ResourceItem:
		return ItemsData.ResourceItem._looks_like_resource_dict(d)
	# Fallback heuristics
	if d.get("is_raw_resource", false):
		return true
	if String(d.get("category", "")).to_lower() == "resource":
		return true
	for k in ["fuel", "water", "food"]:
		var v = d.get(k)
		if (v is float or v is int) and float(v) > 0.0:
			return true
	return false

func _is_part_item(d: Dictionary) -> bool:
	if not d:
		return false
	if ItemsData != null and ItemsData.PartItem:
		return ItemsData.PartItem._looks_like_part_dict(d)
	# Fallback: crude hint keys often present on parts
	var hint_keys = ["slot", "slot_name", "quality", "condition", "part_type", "part_modifiers"]
	for hk in hint_keys:
		if d.has(hk):
			return true
	return false

func _looks_like_mission_item(item: Dictionary) -> bool:
	# Prefer centralized classification when available
	if ItemsData != null and ItemsData.MissionItem:
		# Keep central classification but ensure reward-positive
		if not item:
			return false
		var dr_any = item.get("delivery_reward")
		if dr_any != null and (dr_any is float or dr_any is int) and float(dr_any) > 0.0:
			return true
		return false
	# Local rule: mission cargo must have positive delivery_reward and not be an intrinsic part
	if not item:
		return false
	if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
		return false
	if _is_part_item(item):
		return false
	var dr = item.get("delivery_reward")
	return (dr is float or dr is int) and float(dr) > 0.0

# Helper: scan an array of settlement records and aggregate mission items into agg
func _scan_settlement_array(arr: Array, agg: Dictionary) -> void:
	for it in arr:
		if not (it is Dictionary):
			continue
		if it.has("intrinsic_part_id") and it.get("intrinsic_part_id") != null:
			continue
		var mission_ok := false
		if ItemsData != null and ItemsData.MissionItem:
			mission_ok = ItemsData.MissionItem._looks_like_mission_dict(it)
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] _scan_settlement_array item=", String(it.get("name", it.get("base_name", "?"))), " mission=", mission_ok)
		if mission_ok:
			var nm := String(it.get("name", "Item"))
			var q := int(it.get("quantity", 1))
			agg[nm] = int(agg.get(nm, 0)) + (q if q > 0 else 1)

# Helper: extract integer-ish coords from a dictionary with flexible shapes
func _extract_coords_from_dict(d: Dictionary) -> Vector2i:
	var x_val: Variant = null
	var y_val: Variant = null
	if d.has("x") and d.has("y"):
		x_val = d.get("x")
		y_val = d.get("y")
	elif d.has("coord_x") and d.has("coord_y"):
		x_val = d.get("coord_x")
		y_val = d.get("coord_y")
	elif d.has("coords") and d.get("coords") is Array and (d.get("coords") as Array).size() >= 2:
		var ar: Array = d.get("coords")
		x_val = ar[0]
		y_val = ar[1]
	elif d.has("coord") and d.get("coord") is Array and (d.get("coord") as Array).size() >= 2:
		var ar2: Array = d.get("coord")
		x_val = ar2[0]
		y_val = ar2[1]

	var xi: int = roundi(float(x_val)) if x_val != null else 0
	var yi: int = roundi(float(y_val)) if y_val != null else 0
	return Vector2i(xi, yi)

# Collect available mission cargo at the current settlement (not in convoy)
func _collect_settlement_mission_items() -> Array:
	var out: Array = []
	if not is_instance_valid(_gdm) or convoy_data_received == null:
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] GDM missing or convoy_data_received null; cannot collect settlement missions.")
		return out

	# Determine current convoy coordinates (round to match settlement keys)
	var sx: int = 0
	var sy: int = 0
	if convoy_data_received.has("x") and convoy_data_received.has("y"):
		sx = roundi(float(convoy_data_received.get("x", 0)))
		sy = roundi(float(convoy_data_received.get("y", 0)))
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] Collecting settlement missions at coords (", sx, ",", sy, ")")

	# Use GameDataManager source-of-truth aggregation for missions
	if _gdm.has_method("get_settlement_mission_items"):
		var missions: Array = _gdm.get_settlement_mission_items(sx, sy)
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] GDM.get_settlement_mission_items exists; returned count=", (missions.size() if missions is Array else -1))
		if missions is Array and not missions.is_empty():
			for item in missions:
				if not (item is Dictionary):
					continue
				var nm := String(item.get("name", item.get("base_name", "Item")))
				var q := int(item.get("quantity", 1))
				out.append("%s x%d" % [nm, (q if q > 0 else 1)])
			if _debug_convoy_menu:
				print("[ConvoyMenu][Debug] Settlement missions via GDM: ", out)
		else:
			if _debug_convoy_menu:
				print("[ConvoyMenu][Debug] GDM returned no settlement missions for (", sx, ",", sy, ")")
		return out

	# Fallback to prior scanning logic if API not available
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] get_settlement_mission_items not available; using fallback scan")
	var agg: Dictionary = {}
	var settlement_data: Dictionary = {}
	if _gdm.has_method("get_all_settlements_data"):
		var all_res = _gdm.get_all_settlements_data()
		if all_res is Array:
			_latest_all_settlements = all_res
			if _debug_convoy_menu:
				print("[ConvoyMenu][Debug] get_all_settlements_data size=", _latest_all_settlements.size())
	for s in _latest_all_settlements:
		if not (s is Dictionary):
			continue
		var sc := _extract_coords_from_dict(s)
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] inspecting settlement at (", sc.x, ",", sc.y, ") name=", String(s.get("name", "?")))
		if sc.x == sx and sc.y == sy:
			settlement_data = s
			break
	if settlement_data.is_empty():
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] No settlement found at current coords; preview will show None.")
		return out
	# Existing missions arrays (if present)
	if settlement_data.has("missions") and settlement_data.missions is Array:
		_scan_settlement_array(settlement_data.missions, agg)
	# Scan vendors' cargo_inventory for delivery_reward > 0 (strict mission rule)
	if settlement_data.has("vendors") and settlement_data.vendors is Array:
		var vendor_count := 0
		for v in settlement_data.vendors:
			if not (v is Dictionary):
				continue
			vendor_count += 1
			if _debug_convoy_menu:
				print("[ConvoyMenu][Debug] scanning vendor id=", String(v.get("vendor_id", "?")), " name=", String(v.get("name", "?")))
			# Scan explicit vendor missions array if present
			if v.has("missions") and v.missions is Array:
				_scan_settlement_array(v.missions, agg)
			# Strict mission detection from cargo_inventory
			if v.has("cargo_inventory") and v.cargo_inventory is Array:
				if _debug_convoy_menu:
					print("[ConvoyMenu][Debug] vendor cargo_inventory size=", (v.cargo_inventory.size() as int))
				for ci in v.cargo_inventory:
					if not (ci is Dictionary):
						continue
					if ci.has("intrinsic_part_id") and ci.get("intrinsic_part_id") != null:
						continue
					var dr = ci.get("delivery_reward")
					if (dr is float or dr is int) and float(dr) > 0.0:
						var nm := String(ci.get("name", ci.get("base_name", "Item")))
						var q := int(ci.get("quantity", 1))
						agg[nm] = int(agg.get(nm, 0)) + (q if q > 0 else 1)
						if _debug_convoy_menu:
							print("[ConvoyMenu][Debug] mission cargo detected: ", nm, " x", (q if q > 0 else 1), " dr=", float(dr))
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] scanned vendors count=", vendor_count, " aggregated mission names=", agg.keys())
	for nm in agg.keys():
		out.append("%s x%d" % [String(nm), int(agg[nm])])
	if _debug_convoy_menu and out.is_empty():
		print("[ConvoyMenu][Debug] Settlement mission aggregation produced no items; showing None.")
	return out

func _on_mech_vendor_availability(_veh_id: String, _slot_availability: Dictionary) -> void:
	_update_vendor_preview()

func _on_part_compat_ready(_payload: Dictionary) -> void:
	_update_vendor_preview()

func _on_settlement_data_updated(_list: Array) -> void:
	# Cache the latest all-settlements payload for local lookups
	if _list is Array:
		_latest_all_settlements = _list
		if _debug_convoy_menu:
			print("[ConvoyMenu][Debug] cached all_settlements count=", _latest_all_settlements.size())
	_update_vendor_preview()

func _on_initial_data_ready() -> void:
	# When initial data comes online (map + convoys), try to sync settlements
	if is_instance_valid(_gdm) and _gdm.has_method("get_all_settlements_data"):
		var arr = _gdm.get_all_settlements_data()
		if arr is Array:
			_latest_all_settlements = arr
			if _debug_convoy_menu:
				print("[ConvoyMenu][Debug] initial_data_ready -> synced settlements count=", _latest_all_settlements.size())
	_update_vendor_preview()

func _on_vendor_panel_ready(_payload: Dictionary) -> void:
	# Vendor data updated; refresh settlement missions preview
	if _debug_convoy_menu:
		print("[ConvoyMenu][Debug] vendor_panel_data_ready -> refresh vendor preview")
	_update_vendor_preview()

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

	# Consistent min height already set in scene; enforce if loaded dynamically
	if button_node.custom_minimum_size.y < 30.0:
		button_node.custom_minimum_size = Vector2(button_node.custom_minimum_size.x, 34.0)

	var style_box_normal := StyleBoxFlat.new()
	style_box_normal.bg_color = COLOR_MENU_BUTTON_GREY_BG
	style_box_normal.corner_radius_top_left = 4
	style_box_normal.corner_radius_top_right = 4
	style_box_normal.corner_radius_bottom_left = 4
	style_box_normal.corner_radius_bottom_right = 4
	style_box_normal.border_width_left = 1
	style_box_normal.border_width_right = 1
	style_box_normal.border_width_top = 1
	style_box_normal.border_width_bottom = 1
	style_box_normal.border_color = COLOR_BOX_FONT.darkened(0.2)
	style_box_normal.shadow_size = 4
	style_box_normal.shadow_color = Color(0,0,0,0.4)

	var style_box_hover := style_box_normal.duplicate()
	style_box_hover.bg_color = COLOR_MENU_BUTTON_GREY_BG.lightened(0.1)

	var style_box_pressed := style_box_normal.duplicate()
	style_box_pressed.bg_color = COLOR_MENU_BUTTON_GREY_BG.darkened(0.15)
	style_box_pressed.shadow_size = 2
	style_box_pressed.shadow_color = Color(0,0,0,0.25)

	button_node.add_theme_stylebox_override("normal", style_box_normal)
	button_node.add_theme_stylebox_override("hover", style_box_hover)
	button_node.add_theme_stylebox_override("pressed", style_box_pressed)
	button_node.add_theme_color_override("font_color", COLOR_BOX_FONT)

# The _update_label function is no longer needed with this simplified structure.
# You can remove it or comment it out.
# func _update_label(node_path: String, text_content: Variant):
# 	...
