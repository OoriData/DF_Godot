extends MenuBase
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

# --- Top Up State ---
const TOP_UP_RESOURCES := ["fuel", "water", "food"]
var _top_up_plan: Dictionary = {
	"total_cost": 0.0,
	"allocations": [],
	"resources": {},
	"planned_list": []
}
var _current_settlement_data: Dictionary = {} # Cached for Top Up logic
var top_up_button: Button = null # Dynamically created

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

# Destinations depend on settlements from the map snapshot. If the player opens this
# menu before map data arrives, we poll briefly and refresh when available.
var _settlement_poll_attempts: int = 0
var _settlement_poll_timer: Timer = null

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
@onready var _routes: Node = get_node_or_null("/root/RouteService")
@onready var _logger: Node = get_node_or_null("/root/Logger")
@onready var _user_service: Node = get_node_or_null("/root/UserService")
@onready var _convoy_service: Node = get_node_or_null("/root/ConvoyService")
@onready var _api: Node = get_node_or_null("/root/APICalls")

func _log_debug(msg: String, a: Variant = null, b: Variant = null, c: Variant = null) -> void:
	if is_instance_valid(_logger) and _logger.has_method("debug"):
		_logger.debug(msg, a, b, c)

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

	# Canonical route lifecycle + convoy update events.
	if is_instance_valid(_hub):
		if _hub.has_signal("route_choices_request_started") and not _hub.route_choices_request_started.is_connected(_on_route_choices_request_started):
			_hub.route_choices_request_started.connect(_on_route_choices_request_started)
		if _hub.has_signal("route_choices_error") and not _hub.route_choices_error.is_connected(_on_route_choices_error):
			_hub.route_choices_error.connect(_on_route_choices_error)
		if _hub.has_signal("route_choices_ready") and not _hub.route_choices_ready.is_connected(_on_route_choices_ready):
			_hub.route_choices_ready.connect(_on_route_choices_ready)
		if _hub.has_signal("convoy_updated") and not _hub.convoy_updated.is_connected(_on_hub_convoy_updated):
			_hub.convoy_updated.connect(_on_hub_convoy_updated)
		# Refresh planner destinations when map/settlement snapshot arrives.
		if _hub.has_signal("map_changed") and not _hub.map_changed.is_connected(_on_map_changed):
			_hub.map_changed.connect(_on_map_changed)
	elif is_instance_valid(_store):
		# Fallback if hub isn't present for some reason.
		if _store.has_signal("map_changed") and not _store.map_changed.is_connected(_on_map_changed):
			_store.map_changed.connect(_on_map_changed)

	# Listen for money changes to update Top Up button
	if is_instance_valid(_store):
		if _store.has_signal("user_changed") and not _store.user_changed.is_connected(_on_store_user_changed):
			_store.user_changed.connect(_on_store_user_changed)

	# Listen for API errors to unblock overlay if cancellation fails
	if is_instance_valid(_api):
		if _api.has_signal("fetch_error") and not _api.fetch_error.is_connected(_on_fetch_error):
			_api.fetch_error.connect(_on_fetch_error)
		if _api.has_signal("journey_canceled") and not _api.journey_canceled.is_connected(_on_journey_canceled_api):
			_api.journey_canceled.connect(_on_journey_canceled_api)

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

	# If confirmation panel is open, go back to destination list
	if is_instance_valid(_confirmation_panel) and _confirmation_panel.visible:
		_on_change_destination_pressed()
		return
		
	emit_signal("back_requested")

func _process(_delta: float):
	pass

func _physics_process(_delta: float):
	pass

func initialize_with_data(data_or_id: Variant, extra_arg: Variant = null) -> void:
	# MenuBase owns refreshing from GameStore; we only keep local snapshot.
	if data_or_id is Dictionary:
		var d := data_or_id as Dictionary
		convoy_id = String(d.get("convoy_id", d.get("id", "")))
		convoy_data_received = d.duplicate(true)
	else:
		convoy_id = String(data_or_id)
		convoy_data_received = {}
	_log_debug("ConvoyJourneyMenu.initialize_with_data name=%s convoy_id=%s type=%s", name, convoy_id, typeof(data_or_id))
	super.initialize_with_data(data_or_id, extra_arg)

func _update_ui(convoy: Dictionary) -> void:
	# Snapshot update from GameStore.
	convoy_data_received = convoy.duplicate(true)
	var journey_raw: Variant = convoy_data_received.get("journey")
	var has_journey := journey_raw is Dictionary and not (journey_raw as Dictionary).is_empty()
	if is_instance_valid(title_label):
		var convoy_name = convoy_data_received.get("convoy_name", convoy_data_received.get("name", "Convoy"))
		title_label.text = String(convoy_name) + " - " + ("Journey Details" if has_journey else "Journey Planner")

	# If a confirmation preview is open, don't clobber it on background refresh.
	if is_instance_valid(_confirmation_panel) and _confirmation_panel.visible:
		return

	# Deterministic rebuild: prevent duplicated panels/buttons from accumulating.
	for child in content_vbox.get_children():
		child.queue_free()

	if not has_journey:
		var settlement_count: int = (_store.get_settlements().size() if is_instance_valid(_store) and _store.has_method("get_settlements") else -1)
		_log_debug("ConvoyJourneyMenu planner render convoy_id=%s settlements=%s", str(convoy_data_received.get("convoy_id", "")), settlement_count)
		if settlement_count <= 0:
			_show_loading_indicator("Loading destinations…")
			_schedule_destination_retry()
		else:
			_settlement_poll_attempts = 0
			_populate_destination_list()
		return

	# ---- Styled container for in-transit details ----
	var details_panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.16, 0.94)
	if sb.has_method("set_border_width_all"):
		sb.set_border_width_all(1)
	else:
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
	sb.border_color = Color(0.25, 0.30, 0.38)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	details_panel.add_theme_stylebox_override("panel", sb)
	content_vbox.add_child(details_panel)
	var details_vbox := VBoxContainer.new()
	details_vbox.add_theme_constant_override("separation", 8)
	details_panel.add_child(details_vbox)

	# --- ETA headline (centered) ---
	var journey_data: Dictionary = journey_raw as Dictionary
	var eta_str = journey_data.get("eta")
	var eta_val := preload("res://Scripts/System/date_time_util.gd").format_timestamp_display(eta_str, true)
	var eta_headline := Label.new()
	eta_headline.text = "ETA: %s" % eta_val
	eta_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eta_headline.add_theme_font_size_override("font_size", 20)
	eta_headline.add_theme_color_override("font_color", Color(0.92, 0.97, 1))
	details_vbox.add_child(eta_headline)

	# Compute progress percentage for the bar only
	var progress: float = journey_data.get("progress", 0.0)
	var length: float = journey_data.get("length", 0.0)
	var progress_percentage := 0.0
	if length > 0.001:
		progress_percentage = (progress / length) * 100.0

	# --- Location grid with icons ---
	var loc_grid := GridContainer.new()
	loc_grid.columns = 2
	loc_grid.add_theme_constant_override("h_separation", 14)
	loc_grid.add_theme_constant_override("v_separation", 6)
	details_vbox.add_child(loc_grid)
	# Current
	var curr_title := Label.new()
	curr_title.text = "📍 Current"
	curr_title.add_theme_color_override("font_color", Color(0.85,0.9,1))
	loc_grid.add_child(curr_title)
	var curr_value := Label.new()
	var curr_name := _get_settlement_name(null, convoy_data_received.get("x", 0.0), convoy_data_received.get("y", 0.0))
	curr_value.text = "%s  (%s, %s)" % [
		curr_name,
		NumberFormat.fmt_float(convoy_data_received.get("x", 0.0), 0),
		NumberFormat.fmt_float(convoy_data_received.get("y", 0.0), 0),
	]
	loc_grid.add_child(curr_value)
	# Departed (moved below, with emoji)
	var departure_time_str = journey_data.get("departure_time")
	var departed_val := preload("res://Scripts/System/date_time_util.gd").format_timestamp_display(departure_time_str, false)
	var dep_title := Label.new()
	dep_title.text = "🕓 Departed"
	loc_grid.add_child(dep_title)
	var dep_value := Label.new()
	dep_value.text = departed_val
	loc_grid.add_child(dep_value)
	# Origin
	var origin_x = journey_data.get("origin_x")
	var origin_y = journey_data.get("origin_y")
	var origin_title := Label.new()
	origin_title.text = "🏠 Origin"
	loc_grid.add_child(origin_title)
	var origin_value := Label.new()
	if origin_x != null and origin_y != null:
		var origin_name = _get_settlement_name(null, origin_x, origin_y)
		origin_value.text = "%s  (%s, %s)" % [origin_name, NumberFormat.fmt_float(origin_x, 0), NumberFormat.fmt_float(origin_y, 0)]
	else:
		origin_value.text = "N/A"
	loc_grid.add_child(origin_value)
	# Destination
	var dest_x = journey_data.get("dest_x")
	var dest_y = journey_data.get("dest_y")
	var dest_title := Label.new()
	dest_title.text = "🏁 Destination"
	loc_grid.add_child(dest_title)
	var dest_value := Label.new()
	if dest_x != null and dest_y != null:
		var dest_name = _get_settlement_name(null, dest_x, dest_y)
		dest_value.text = "%s  (%s, %s)" % [dest_name, NumberFormat.fmt_float(dest_x, 0), NumberFormat.fmt_float(dest_y, 0)]
	else:
		dest_value.text = "N/A"
	loc_grid.add_child(dest_value)

	# --- Progress bar (styled to match ConvoyMenu journey color) ---
	var progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0, 20)
	progress_bar.value = progress_percentage
	# Match ConvoyMenu: background 2a2a2a with light border; fill uses Color("29b6f6")
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color("2a2a2a")
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = bg_style.bg_color.lightened(0.4)
	bg_style.shadow_color = Color(0, 0, 0, 0.4)
	bg_style.shadow_size = 2
	bg_style.shadow_offset = Vector2(0, 2)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color("29b6f6")
	fill_style.border_width_left = 1
	fill_style.border_width_right = 1
	fill_style.border_width_top = 1
	fill_style.border_width_bottom = 1
	fill_style.border_color = Color("29b6f6").darkened(0.2)
	progress_bar.add_theme_stylebox_override("background", bg_style)
	progress_bar.add_theme_stylebox_override("fill", fill_style)
	details_vbox.add_child(progress_bar)

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
			if is_instance_valid(_routes) and _routes.has_method("cancel_journey"):
				print("[ConvoyJourneyMenu] Cancel Journey pressed convoy="+convoy_id_local+" journey="+journey_id_local)
				_routes.cancel_journey(convoy_id_local, journey_id_local)
			else:
				printerr("ConvoyJourneyMenu: RouteService missing cancel_journey method.")
				_hide_blocking_overlay()
		)
		cancel_btn.add_theme_color_override("font_color", Color(1, 0.92, 0.92))
		details_vbox.add_child(cancel_btn)

func _populate_destination_list():
	# Reset planner loading state for a clean rebuild.
	_settlement_poll_attempts = 0
	# Clear potential prior loading state
	_is_request_in_flight = false
	_loading_label = null
	_last_requested_destination = {}

	if not is_instance_valid(_store) or not _store.has_method("get_settlements"):
		printerr("ConvoyJourneyMenu: GameStore not found or method missing. Cannot populate destinations.")
		var error_label = Label.new()
		error_label.text = "Error: Could not load destination data."
		error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content_vbox.add_child(error_label)
		return

	var all_settlements: Array = _store.get_settlements()
	if all_settlements.is_empty():
		var no_settlements_label = Label.new()
		no_settlements_label.text = "No known destinations to travel to."
		no_settlements_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content_vbox.add_child(no_settlements_label)
		return

	var convoy_pos = Vector2(convoy_data_received.get("x", 0.0), convoy_data_received.get("y", 0.0))

	# Create a reverse map from vendor_id to settlement_name for quick lookups.
	# Also map Vendor Name -> Settlement Name to handle non-ID recipient strings.
	var vendor_to_settlement_map: Dictionary = {}
	var vendor_name_to_settlement_map: Dictionary = {}
	var settlement_id_to_name: Dictionary = {}


	
	for settlement in all_settlements:
		if not (settlement is Dictionary):
			continue
		var settlement_dict := settlement as Dictionary
		var settlement_name = settlement_dict.get("name", "Unknown")
		var vendors: Variant = settlement_dict.get("vendors", [])
		if vendors is Array:
			for vendor in vendors:
				if vendor is Dictionary:
					var v_id = str(vendor.get("vendor_id", ""))
					var v_name = str(vendor.get("name", ""))
					
					if not v_id.is_empty():
						vendor_to_settlement_map[v_id] = settlement_name
					if not v_name.is_empty():
						vendor_name_to_settlement_map[v_name] = settlement_name
		
		# DEBUG: Inspect Green Bay vendors
		# if settlement_name == "Green Bay": ...

		var s_id = str(settlement_dict.get("id", ""))
		if not s_id.is_empty():
			settlement_id_to_name[s_id] = settlement_name
		var s_settlement_id = str(settlement_dict.get("settlement_id", ""))
		if not s_settlement_id.is_empty():
			settlement_id_to_name[s_settlement_id] = settlement_name

	# Fallback: Check if GameStore has a global vendor list (commonly available in this codebase pattern)
	# This handles cases where dynamic vendors (like mission-specific ones) aren't nested in the settlement snapshot.
	if is_instance_valid(_store) and _store.has_method("get_vendors"):
		var all_vendors = _store.get_vendors()
		if all_vendors is Array:
			for vendor in all_vendors:
				if not (vendor is Dictionary): continue
				var v_id = str(vendor.get("vendor_id", ""))
				var v_name = str(vendor.get("name", ""))
				var v_settlement_id = str(vendor.get("settlement_id", "")) # linking key
				
				# We need to find the settlement name for this vendor.
				# If we have settlement_id, we can look it up.
				var linked_settlement_name = ""
				
				# Optimization: check known map first
				if not v_id.is_empty() and vendor_to_settlement_map.has(v_id):
					continue
				
				# Try to resolve settlement name by ID
				if not v_settlement_id.is_empty():
					for s in all_settlements:
						if str(s.get("id")) == v_settlement_id or str(s.get("settlement_id")) == v_settlement_id:
							linked_settlement_name = s.get("name", "")
							break
				
				# If resolved, add to maps
				if not linked_settlement_name.is_empty():
					if not v_id.is_empty():
						vendor_to_settlement_map[v_id] = linked_settlement_name
					if not v_name.is_empty():
						vendor_name_to_settlement_map[v_name] = linked_settlement_name
	


	# Find any mission-specific destinations by resolving recipient IDs to settlement names.
	var mission_destinations: Dictionary = {}
	
	print("[ConvoyJourneyMenu] Convoy Data Keys: ", convoy_data_received.keys())
	
	var vehicles_list = []
	if convoy_data_received.has("vehicle_details_list"):
		vehicles_list = convoy_data_received.get("vehicle_details_list", [])
	elif convoy_data_received.has("vehicles"):
		vehicles_list = convoy_data_received.get("vehicles", [])
	
	if not vehicles_list.is_empty():
		for vehicle in vehicles_list:
			# Aggregate all potential cargo sources
			var all_cargo = []
			if vehicle.get("cargo_items_typed") is Array:
				all_cargo.append_array(vehicle.get("cargo_items_typed"))
			elif vehicle.get("cargo_items") is Array:
				all_cargo.append_array(vehicle.get("cargo_items"))
			
			# Fallback to legacy "cargo" if specific lists are missing or empty? 
			# Or just include it to be safe.
			if vehicle.get("cargo") is Array:
				all_cargo.append_array(vehicle.get("cargo"))
			
			if vehicle.get("all_cargo") is Array:
				all_cargo.append_array(vehicle.get("all_cargo"))
			
			print("[ConvoyJourneyMenu] Vehicle cargo count: ", all_cargo.size())

			for cargo_item in all_cargo:
				if not (cargo_item is Dictionary):
					continue
				
				# Check for mission indicators
				var match_found = false
				
				# 0. Check pre-calculated UI field (unlikely in raw data but checked just in case)
				if cargo_item.get("recipient_settlement_name") is String:
					var rsn = str(cargo_item.get("recipient_settlement_name"))
					if not rsn.is_empty():
						# Exact match logic
						if mission_destinations.has(rsn):
							match_found = true
						# Check if this name is a valid settlement
						elif vendor_to_settlement_map.values().has(rsn):
							mission_destinations[rsn] = cargo_item.get("name", "Delivery Cargo")
							match_found = true
				
				if match_found: continue

				if match_found:
					continue

				# Gather all candidate keys that might identify the destination
				var candidate_keys = []
				
				# string-based keys
				if cargo_item.get("recipient") != null: candidate_keys.append(str(cargo_item.get("recipient")))
				if cargo_item.get("recipient_vendor_id") != null: candidate_keys.append(str(cargo_item.get("recipient_vendor_id")))
				if cargo_item.get("destination_vendor_id") != null: candidate_keys.append(str(cargo_item.get("destination_vendor_id")))
				if cargo_item.get("mission_vendor_id") != null: candidate_keys.append(str(cargo_item.get("mission_vendor_id")))

				for val in candidate_keys:
					if val.is_empty(): continue
					
					var resolved_settlement = ""
					
					# 1. Try ID Match
					if vendor_to_settlement_map.has(val):
						resolved_settlement = vendor_to_settlement_map[val]
					
					# 2. Try Settlement ID Match Directly
					elif settlement_id_to_name.has(val):
						resolved_settlement = settlement_id_to_name[val]
					
					# 2. Try Vendor Name Match (Exact)
					elif vendor_name_to_settlement_map.has(val):
						resolved_settlement = vendor_name_to_settlement_map[val]
					
					# 3. Fuzzy match against Settlement Names directly (e.g. "Green Bay General")
					else:
						# optimization: only do fuzzy loop if not found yet
						var val_lower = val.to_lower()
						for s_data in all_settlements:
							var s_name = s_data.get("name", "")
							if s_name.is_empty(): continue
							var s_name_lower = s_name.to_lower()
							
							# Check if candidate string contains settlement name (e.g. "Green Bay General Store" contains "Green Bay")
							if val_lower.find(s_name_lower) != -1:
								resolved_settlement = s_name
								break
							# Check reverse (unlikely for settlement names, but possible)
							if s_name_lower.find(val_lower) != -1:
								resolved_settlement = s_name
								break
						
						# 4. Fuzzy match against Vendor Names -> link to Settlement
						if resolved_settlement == "":
							for v_name in vendor_name_to_settlement_map.keys():
								# e.g. val="Green Bay Gen" vs v_name="Green Bay General Store"
								if str(v_name).to_lower().find(val_lower) != -1 or val_lower.find(str(v_name).to_lower()) != -1:
									resolved_settlement = vendor_name_to_settlement_map[v_name]
									break

					if resolved_settlement != "":
						if not mission_destinations.has(resolved_settlement):
							mission_destinations[resolved_settlement] = cargo_item.get("name", "Delivery Cargo")
						match_found = true
						print("[ConvoyJourneyMenu] MATCH FOUND for cargo '%s': resolved to '%s' via key '%s'" % [cargo_item.get("name"), resolved_settlement, val])
						break
				
				# if not match_found and (not candidate_keys.is_empty()):
				# 	print("[ConvoyJourneyMenu] NO MATCH for cargo '%s'. Candidate keys: %s" % [cargo_item.get("name"), candidate_keys])
				
				if match_found:
					continue
				
				# Validation / Debug for loose items
				if cargo_item.get("is_mission", false) or (cargo_item.get("mission_id", "") != ""):
					# Valid mission item but destination unknown.
					pass

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
		
		if a_is_mission != b_is_mission:
			return a_is_mission # true (mission) comes before false

		# If both are missions or both are not, sort by distance
		return a.distance < b.distance
	)
	
	print("[ConvoyJourneyMenu] Mission Destinations Found: ", mission_destinations.keys())
	for d in potential_destinations:
		if mission_destinations.has(d.data.get("name", "")):
			print("[ConvoyJourneyMenu] Priority Dest: %s" % d.data.get("name"))

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

func _on_map_changed(_tiles: Array, settlements: Array) -> void:
	_log_debug("ConvoyJourneyMenu map_changed received visible=%s settlements=%s", is_visible_in_tree(), (settlements.size() if settlements != null else -1))
	# When settlements arrive after the menu is opened, refresh the destination list.
	if not is_visible_in_tree():
		return
	if not is_instance_valid(content_vbox):
		return
	# If a journey is active or a confirmation panel is open, don't rebuild planner UI.
	var j: Variant = convoy_data_received.get("journey")
	var has_journey := j is Dictionary and not (j as Dictionary).is_empty()
	if has_journey:
		return
	if is_instance_valid(_confirmation_panel) and _confirmation_panel.visible:
		return
	if settlements == null or settlements.is_empty():
		# Still useful to keep the user informed.
		_show_loading_indicator("Loading destinations…")
		_schedule_destination_retry()
		return
	_log_debug("ConvoyJourneyMenu map_changed -> refresh destinations convoy_id=%s settlements=%s", str(convoy_data_received.get("convoy_id", "")), settlements.size())
	for child in content_vbox.get_children():
		child.queue_free()
	_populate_destination_list()

func _schedule_destination_retry() -> void:
	# Avoid infinite rebuild loops if map never loads.
	if _settlement_poll_attempts >= 10:
		_log_debug("ConvoyJourneyMenu settlement poll giving up attempts=%s", _settlement_poll_attempts)
		return
	_settlement_poll_attempts += 1
	if is_instance_valid(_settlement_poll_timer):
		_settlement_poll_timer.stop()
		_settlement_poll_timer.queue_free()
	_settlement_poll_timer = Timer.new()
	_settlement_poll_timer.one_shot = true
	_settlement_poll_timer.wait_time = 0.5
	add_child(_settlement_poll_timer)
	_settlement_poll_timer.timeout.connect(func():
		if not is_visible_in_tree():
			return
		# Only retry in planner mode (no active journey and no confirmation panel).
		var j: Variant = convoy_data_received.get("journey")
		var has_journey := j is Dictionary and not (j as Dictionary).is_empty()
		if has_journey:
			return
		if is_instance_valid(_confirmation_panel) and _confirmation_panel.visible:
			return
		var cnt: int = (_store.get_settlements().size() if is_instance_valid(_store) and _store.has_method("get_settlements") else -1)
		_log_debug("ConvoyJourneyMenu settlement poll attempt=%s settlements=%s", _settlement_poll_attempts, cnt)
		if cnt > 0:
			for child in content_vbox.get_children():
				child.queue_free()
			_settlement_poll_attempts = 0
			_populate_destination_list()
		else:
			_schedule_destination_retry()
	)
	_settlement_poll_timer.start()

func _get_settlement_name(_unused_gdm_node, coord_x, coord_y) -> String:
	if not is_instance_valid(_store) or not _store.has_method("get_settlements"):
		return "Unknown"
	var x_int := roundi(float(coord_x))
	var y_int := roundi(float(coord_y))
	for s in _store.get_settlements():
		if s is Dictionary:
			var sx := int((s as Dictionary).get("x", -9999))
			var sy := int((s as Dictionary).get("y", -9999))
			if sx == x_int and sy == y_int:
				var settlement_name := str((s as Dictionary).get("name", "Unknown"))
				return settlement_name if settlement_name != "" else "Unknown"
	return "Uncharted Location"

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
	if is_instance_valid(_routes) and _routes.has_method("request_choices"):
		var convoy_id_local := str(convoy_data_received.get("convoy_id"))
		var dest_x := int(destination_data.get("x"))
		var dest_y := int(destination_data.get("y"))
		_routes.request_choices(convoy_id_local, dest_x, dest_y)
		_disable_destination_buttons()
		_show_loading_indicator("Finding routes...")
	else:
		printerr("ConvoyJourneyMenu: RouteService not available; cannot request route choices.")
	_emit_find_route(destination_data)

func _emit_find_route(destination_data: Dictionary):
	emit_signal("find_route_requested", convoy_data_received, destination_data)

func _on_route_choices_request_started():
	print("[ConvoyJourneyMenu] route_choices_request_started")
	_is_request_in_flight = true
	_show_loading_indicator("Calculating routes...")

func _on_route_choices_error(error_message: String):
	print("[ConvoyJourneyMenu] route_choices_error error=", error_message)
	_is_request_in_flight = false
	_clear_loading_indicator()
	_show_error_message(error_message)
	_enable_destination_buttons()

func _on_fetch_error(error_message: String):
	# If we are blocking the UI (e.g. cancelling journey), an API error means we should unblock.
	if is_instance_valid(_blocking_overlay):
		_hide_blocking_overlay()
		_show_inline_toast("Error: " + error_message, 4.0)

func _on_journey_canceled_api(_result: Dictionary):
	# API confirmed cancellation.
	# We still wait for the hub update for data, but we can stop blocking the UI or at least know it succeeded.
	# Actually, since services refresh, we might just want to hide overlay here to be responsive.
	# But let's check if the convoy update handles it.
	# The issue was the overlay STUCK. So let's force hide it here.
	print("[ConvoyJourneyMenu] _on_journey_canceled_api received. Hiding overlay.")
	_hide_blocking_overlay()
	_show_inline_toast("Journey canceled.", 2.0)

func _on_route_choices_ready(routes: Array) -> void:
	_on_route_info_ready(convoy_data_received, _last_requested_destination, routes)

func _on_hub_convoy_updated(updated_convoy: Dictionary) -> void:
	if not (updated_convoy is Dictionary):
		return
	if str(updated_convoy.get("convoy_id", "")) != str(convoy_data_received.get("convoy_id", "")):
		return
	# If journey is now empty, treat it as a cancel completion for UX.
	var j: Variant = updated_convoy.get("journey")
	var is_empty := (j == null) or (j is Dictionary and (j as Dictionary).is_empty())
	if is_empty:
		_on_journey_canceled(updated_convoy)

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
	if not is_instance_valid(_store) or not _store.has_method("get_convoys"):
		return
	if not convoy_data_received.has('convoy_id'):
		return
	var target_id := str(convoy_data_received.get('convoy_id'))
	if target_id == "":
		return
	for c in _store.get_convoys():
		if c is Dictionary and str((c as Dictionary).get('convoy_id', '')) == target_id:
			var latest := c as Dictionary
			# Only update vehicle lists to avoid overwriting selection context
			if latest.has('vehicle_details_list'):
				convoy_data_received['vehicle_details_list'] = latest.get('vehicle_details_list')
			elif latest.has('vehicles'):
				convoy_data_received['vehicle_details_list'] = latest.get('vehicles')
			print('[ConvoyJourneyMenu][DEBUG] Refreshed convoy vehicle snapshot. Vehicles now =', (convoy_data_received.get('vehicle_details_list', []) as Array).size())
			break

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
	summary.text = "Destination: %s\nDistance: %s miles\nEstimated Travel Time: %s" % [ _destination_data.get("name", "Unknown"), NumberFormat.fmt_float(distance_miles, 2), eta_fmt]
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
	var header_labels = ["Resource", "Need", "Have (Capacity)", "Remaining"]
	for h in header_labels:
		var hl = Label.new()
		hl.text = h
		hl.add_theme_color_override("font_color", Color(0.75,0.85,0.95))
		if h != "Resource":
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		res_grid.add_child(hl)
	var _add_res_row = func(label: String, unit: String, need: float, have: float, max_v: float, status: String):
		var row_container = Control.new() # Dummy container just in case needed for spacing
		
		# --- Resource Name ---
		var icon_lbl = Label.new()
		icon_lbl.text = label
		if status == "critical":
			icon_lbl.add_theme_color_override("font_color", Color(1,0.35,0.35))
			icon_lbl.text = "⚠️ " + label
		elif status == "warn":
			icon_lbl.add_theme_color_override("font_color", Color(1,0.75,0.35))
		res_grid.add_child(icon_lbl)
		
		# --- Need ---
		var need_lbl = Label.new()
		need_lbl.text = NumberFormat.fmt_float(need, 2) + unit
		need_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		res_grid.add_child(need_lbl)
		
		# --- Have (Capacity) ---
		var have_lbl = Label.new()
		var have_text = NumberFormat.fmt_float(have, 2)
		if max_v > 0:
			have_text += " / " + NumberFormat.fmt_float(max_v, 0)
		have_lbl.text = have_text + unit
		have_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		res_grid.add_child(have_lbl)
		
		# --- Remaining ---
		var rem_lbl = Label.new()
		var remaining = have - need
		if remaining < 0:
			rem_lbl.text = "Short " + NumberFormat.fmt_float(abs(remaining), 2) + unit
			rem_lbl.add_theme_color_override("font_color", Color(1,0.35,0.35))
			# Visual highlight for the row effect could be simulated by background panel if needed
		elif status == "warn":
			rem_lbl.text = NumberFormat.fmt_float(remaining, 2) + unit
			rem_lbl.add_theme_color_override("font_color", Color(1,0.75,0.35))
		else:
			rem_lbl.text = NumberFormat.fmt_float(remaining, 2) + unit
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
			warn_lbl.add_theme_font_size_override("font_size", 18) # Larger text
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
			var bar_tt = "%s Usage: %s / %s kWh" % [e.name, NumberFormat.fmt_float(e.used, 2), NumberFormat.fmt_float(e.capacity, 2)]
			if e.status == "critical":
				bar_tt += " (Shortfall %s kWh)" % NumberFormat.fmt_float(e.raw_used - e.capacity, 2)
			elif e.status == "discharged":
				bar_tt += " (Fully Discharged)"
			bar.tooltip_text = bar_tt
			energy_grid.add_child(bar)
			var nums_lbl = Label.new()
			if e.status == "critical":
				# Show true need and shortfall for pure electric shortfall
				nums_lbl.text = "Need: %s  Capacity: %s  Short: %s" % [
					NumberFormat.fmt_float(e.raw_used, 2),
					NumberFormat.fmt_float(e.capacity, 2),
					NumberFormat.fmt_float(e.raw_used - e.capacity, 2),
				]
			else:
				# For normal & discharged (IC) cases, cap the displayed need at capacity
				nums_lbl.text = "Need: %s  Capacity: %s" % [NumberFormat.fmt_float(e.used, 2), NumberFormat.fmt_float(e.capacity, 2)]
			energy_grid.add_child(nums_lbl)

	# --- Delivery Manifest Section ---
	# Calculate potential earnings and list items for the selected destination
	var dest_name = _destination_data.get("name", "")
	var dest_settlement_id = str(_destination_data.get("id", ""))
	if dest_settlement_id == "": dest_settlement_id = str(_destination_data.get("settlement_id", ""))
	
	var dest_vendors = _destination_data.get("vendors", [])
	var valid_dest_ids = []
	if dest_settlement_id != "": valid_dest_ids.append(dest_settlement_id)
	
	if dest_vendors is Array:
		for v in dest_vendors:
			if v is Dictionary:
				if v.has("vendor_id"): valid_dest_ids.append(str(v.get("vendor_id")))
				if v.has("id"): valid_dest_ids.append(str(v.get("id")))
	
	print("[ConvoyJourneyMenu] Checking cargo for destination: %s (IDs: %s)" % [dest_name, valid_dest_ids])
	
	var manifest_items = []
	var total_earnings = 0.0
	
	# Helper to check if item is for this destination
	var _is_for_destination = func(item: Dictionary) -> bool:
		# 1. Direct Name Match
		var r_name = str(item.get("recipient_settlement_name", ""))
		if r_name == dest_name and r_name != "": return true
		
		# 2. Output Debug for tricky items
		var recipient = str(item.get("recipient", ""))
		# print("  > Item: %s | Recipient: %s" % [item.get("name"), recipient])

		# 3. ID Match against any valid destination ID (Settlement or Vendor)
		var item_ids = []
		if recipient != "": item_ids.append(recipient)
		if item.has("recipient_vendor_id"): item_ids.append(str(item.get("recipient_vendor_id")))
		if item.has("destination_vendor_id"): item_ids.append(str(item.get("destination_vendor_id")))
		if item.has("mission_vendor_id"): item_ids.append(str(item.get("mission_vendor_id")))
		
		for vid in item_ids:
			if vid != "" and valid_dest_ids.has(vid):
				# print("    MATCH FOUND on ID: %s" % vid)
				return true
				
		return false

	var vehicles_list = _get_vehicle_list()
	for v in vehicles_list:
		if not (v is Dictionary): continue
		var cargo_list = []
		if v.get("cargo_items_typed") is Array: cargo_list.append_array(v.get("cargo_items_typed"))
		elif v.get("cargo_items") is Array: cargo_list.append_array(v.get("cargo_items"))
		elif v.get("cargo") is Array: cargo_list.append_array(v.get("cargo"))
		
		for item in cargo_list:
			if not (item is Dictionary): continue
			
			if _is_for_destination.call(item):
				var item_name = item.get("name", "Unknown Cargo")
				var qty = _coerce_number(item.get("quantity", 1))
				
				# Earnings Logic: Prioritize delivery_reward -> unit_delivery_reward -> sell_price -> value
				var unit_reward = 0.0
				
				# Check for total delivery reward first
				if item.has("delivery_reward") and item.get("delivery_reward") != null:
					unit_reward = _coerce_number(item.get("delivery_reward"))
					# If this is a total reward for the stack, don't multiply by qty? 
					# Usually 'delivery_reward' in JSON example (261) was 381035.0 for qty 1.
					# Let's assume delivery_reward is the TOTAL for the item stack if meaningful, or check unit_delivery_reward.
				elif item.has("unit_delivery_reward") and item.get("unit_delivery_reward") != null:
					unit_reward = _coerce_number(item.get("unit_delivery_reward")) * qty
				elif item.has("sell_price"):
					unit_reward = _coerce_number(item.get("sell_price")) * qty
				elif item.has("value"):
					unit_reward = _coerce_number(item.get("value")) * qty
				
				# Quick fix for the "delivery_reward" field in JSON seemingly being the total or unit?
				# JSON line 261: "delivery_reward": 381035.0, "quantity": 1.0. 
				# JSON line 282: "unit_delivery_reward": 381035.0.
				# It seems delivery_reward might be the total for the line item.
				# So if we used delivery_reward directly, we shouldn't multiply?
				# Let's trust logic: if delivery_reward is present, use it as the Line Total.
				var line_total = unit_reward
				if item.has("delivery_reward") and item.get("delivery_reward") != null:
					line_total = _coerce_number(item.get("delivery_reward"))
				
				manifest_items.append({
					"name": item_name,
					"qty": qty,
					"value": line_total
				})
				total_earnings += line_total

	if not manifest_items.is_empty():
		_confirmation_panel.add_child(HSeparator.new())
		var manifest_header = Label.new()
		manifest_header.text = "Delivery Manifest"
		manifest_header.add_theme_font_size_override("font_size", 18)
		manifest_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_confirmation_panel.add_child(manifest_header)
		
		var manifest_panel = PanelContainer.new()
		var msb = StyleBoxFlat.new()
		msb.bg_color = Color(0.15, 0.18, 0.22, 0.9)
		msb.set_border_width_all(1)
		msb.border_color = Color(0.3, 0.5, 0.4)
		msb.corner_radius_top_left = 4
		msb.corner_radius_top_right = 4
		msb.corner_radius_bottom_left = 4
		msb.corner_radius_bottom_right = 4
		manifest_panel.add_theme_stylebox_override("panel", msb)
		_confirmation_panel.add_child(manifest_panel)
		
		var m_vbox = VBoxContainer.new()
		manifest_panel.add_child(m_vbox)
		
		for m_item in manifest_items:
			var row = HBoxContainer.new()
			var name_lbl = Label.new()
			name_lbl.text = "- %s (x%d)" % [m_item.name, m_item.qty]
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_lbl)
			
			var val_lbl = Label.new()
			val_lbl.text = NumberFormat.format_money(m_item.value)
			val_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
			row.add_child(val_lbl)
			m_vbox.add_child(row)
			
		m_vbox.add_child(HSeparator.new())
		var total_row = HBoxContainer.new()
		var total_lbl = Label.new()
		total_lbl.text = "Total Estimated Earnings:"
		total_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		total_row.add_child(total_lbl)
		
		var total_val = Label.new()
		total_val.text = NumberFormat.format_money(total_earnings)
		total_val.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
		total_val.add_theme_font_size_override("font_size", 18)
		total_row.add_child(total_val)
		m_vbox.add_child(total_row)


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
	
	# --- Top Up Integration ---
	_current_settlement_data = _find_current_settlement()
	if not _current_settlement_data.is_empty():
		top_up_button = Button.new()
		top_up_button.text = "Top Up"
		if not top_up_button.is_connected("pressed", Callable(self, "_on_top_up_button_pressed")):
			top_up_button.pressed.connect(_on_top_up_button_pressed)
		buttons_hbox.add_child(top_up_button)
		_style_top_up_button()
		_update_top_up_button()
	else:
		top_up_button = null
	# --------------------------
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
	var convoy_id_local = str(convoy_data_received.get("convoy_id"))
	var journey_id = str(route_data.get("journey", {}).get("journey_id", ""))
	if journey_id.is_empty():
		printerr("ConvoyJourneyMenu: Cannot confirm journey; missing journey_id")
		return
	if is_instance_valid(_routes) and _routes.has_method("start_journey"):
		_routes.start_journey(convoy_id_local, journey_id)
	else:
		printerr("ConvoyJourneyMenu: RouteService missing start_journey; cannot confirm.")
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

# --- Small UI helper: stat card (title + value) ---
func _make_stat_card(title: String, value_text: String, bg_color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	if sb.has_method("set_border_width_all"):
		sb.set_border_width_all(1)
	else:
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
	sb.border_color = Color(0.28,0.34,0.44)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	card.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.custom_minimum_size = Vector2(120, 60)
	card.add_child(vb)
	var cap := Label.new()
	cap.text = title
	cap.add_theme_color_override("font_color", Color(0.75,0.84,0.95))
	cap.add_theme_font_size_override("font_size", 12)
	vb.add_child(cap)
	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 18)
	val.add_theme_color_override("font_color", Color(0.92,0.97,1))
	vb.add_child(val)
	return card

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
var _blocking_overlay_timer: Timer = null

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

	# Safety timer to prevent infinite blocking
	if is_instance_valid(_blocking_overlay_timer):
		_blocking_overlay_timer.queue_free()
	_blocking_overlay_timer = Timer.new()
	_blocking_overlay_timer.one_shot = true
	_blocking_overlay_timer.wait_time = 10.0 # 10s timeout
	_blocking_overlay_timer.timeout.connect(func():
		if is_instance_valid(_blocking_overlay):
			_hide_blocking_overlay()
			_show_inline_toast("Request timed out.", 3.0)
	)
	add_child(_blocking_overlay_timer)
	_blocking_overlay_timer.start()

func _hide_blocking_overlay():
	if is_instance_valid(_blocking_overlay):
		_blocking_overlay.queue_free()
	_blocking_overlay = null
	if is_instance_valid(_blocking_overlay_timer):
		_blocking_overlay_timer.stop()
		_blocking_overlay_timer.queue_free()
	_blocking_overlay_timer = null

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

# Expose confirm button node for highlight/gating during confirmation step (modified to allow append)
func get_confirm_button_node() -> Button:
	return _confirm_button

# --- Top Up Feature (Cloned from ConvoySettlementMenu) ---

func _find_current_settlement() -> Dictionary:
	if not is_instance_valid(_store) or not _store.has_method("get_tiles"):
		return {}
	
	var cx = int(round(float(convoy_data_received.get("x", -9999))))
	var cy = int(round(float(convoy_data_received.get("y", -9999))))
	
	if cx < 0 or cy < 0:
		return {}

	# Fast lookup via tiles
	var map_tiles = _store.get_tiles()
	if cy >= 0 and cy < map_tiles.size():
		var row = map_tiles[cy]
		if cx >= 0 and cx < row.size():
			var tile = row[cx]
			if tile is Dictionary and tile.has("settlements") and tile.settlements is Array and not tile.settlements.is_empty():
				# Return the first settlement found at this location
				return tile.settlements[0]
				
	return {}

func _update_top_up_button():
	if not is_instance_valid(top_up_button):
		return
	
	# Refresh settlement data just in case
	_current_settlement_data = _find_current_settlement()
		
	if _current_settlement_data.is_empty() or not _current_settlement_data.has("vendors"):
		top_up_button.text = "Top Up (No Vendors)"
		top_up_button.disabled = true
		top_up_button.tooltip_text = "No vendors present in this settlement."
		return
	if convoy_data_received.is_empty():
		top_up_button.text = "Top Up (No Convoy)"
		top_up_button.disabled = true
		top_up_button.tooltip_text = "Convoy data unavailable."
		return

	# Calculate full plan first to see if we need it
	var full_plan = _calculate_top_up_plan()
	var needed_cost = full_plan.get("total_cost", 0.0)
	
	if full_plan.get("planned_list", []).is_empty():
		top_up_button.text = "Top Up (Full)"
		top_up_button.disabled = true
		top_up_button.tooltip_text = "Fuel, Water and Food are already at maximum levels."
		return

	var user_money: float = 0.0
	if is_instance_valid(_user_service) and _user_service.has_method("get_user"):
		var user_data: Dictionary = _user_service.get_user()
		user_money = float(user_data.get("money", 0.0))

	var is_partial = false
	if user_money < needed_cost:
		# User cannot afford full top up. Calculate partial plan with budget.
		_top_up_plan = _calculate_top_up_plan(user_money)
		is_partial = true
	else:
		_top_up_plan = full_plan

	var planned_list: Array = _top_up_plan.get("planned_list", [])
	var total_cost: float = _top_up_plan.get("total_cost", 0.0)
	
	# If even partial plan is empty (cannot afford anything), disable
	if planned_list.is_empty() or total_cost <= 0.0001:
		top_up_button.text = "Top Up"
		top_up_button.disabled = true
		top_up_button.tooltip_text = "Insufficient funds to purchase any resources."
		return

	if is_partial:
		top_up_button.text = "Top Up (Partial)"
	else:
		top_up_button.text = "Top Up"
	
	top_up_button.disabled = false 

	# Build tooltip breakdown (group by resource, showing each vendor line)
	var breakdown_lines: Array = []
	var allocations_by_res: Dictionary = {}
	for alloc in _top_up_plan.allocations:
		var r = String(alloc.get("res",""))
		if r == "":
			continue
		if not allocations_by_res.has(r):
			allocations_by_res[r] = []
		allocations_by_res[r].append(alloc)
	for r in allocations_by_res.keys():
		var group:Array = allocations_by_res[r]
		group.sort_custom(func(a,b): return float(a.price) < float(b.price))
		var res_total_qty:int = 0
		var res_total_cost:float = 0.0
		breakdown_lines.append(r.capitalize() + ":")
		for g in group:
			var qty_i = int(g.get("quantity",0))
			var price_i = float(g.get("price",0.0))
			var vendor_name = String(g.get("vendor_name","?"))
			var sub_i = float(qty_i) * price_i
			res_total_qty += qty_i
			res_total_cost += sub_i
			breakdown_lines.append("  %s: %d @ $%.2f = $%.0f" % [vendor_name, qty_i, price_i, sub_i])
		breakdown_lines.append("  Subtotal %s: %d = $%.0f" % [r, res_total_qty, res_total_cost])
	
	breakdown_lines.append("Total: $%.0f" % total_cost)
	if is_partial:
		var missing = max(0.0, needed_cost - user_money)
		breakdown_lines.append("Partial Top Up (Need $%.0f more for full)." % missing)
	
	top_up_button.tooltip_text = "Top Up Plan:\n" + "\n".join(breakdown_lines)

func _calculate_top_up_plan(budget: float = -1.0) -> Dictionary:
	var plan: Dictionary = {"total_cost": 0.0, "allocations": [], "resources": {}, "planned_list": []}
	if _current_settlement_data.is_empty() or not _current_settlement_data.has("vendors"):
		return plan
	var convoy := convoy_data_received
	if convoy.is_empty():
		return plan

	# Budget/weight constraints
	var remaining_budget: float = budget
	var budget_limited := budget >= 0.0
	if not budget_limited:
		remaining_budget = 999999999.0
	var remaining_weight := float(convoy.get("total_remaining_capacity", 999999.0))
	var weight_limited := remaining_weight <= 0.001
	var resource_weights: Dictionary = convoy.get("resource_weights", {})

	# Build per-resource state with cheapest-vendor priority for that resource.
	var state_by_res: Dictionary = {}
	for res: String in TOP_UP_RESOURCES:
		var max_amount: float = float(convoy.get("max_" + res, 0.0))
		if max_amount <= 0.001:
			continue
		var current_amount: float = float(convoy.get(res, 0.0))
		var needed_exact: float = max(max_amount - current_amount, 0.0)
		var needed_remaining: int = int(floor(needed_exact + 0.0001))
		if needed_remaining <= 0:
			continue

		var price_key: String = String(res) + "_price"
		var vendor_candidates: Array = []
		for v in _current_settlement_data.get("vendors", []):
			if v.has(price_key) and v[price_key] != null and v.has(res):
				var stock_available := int(v.get(res, 0))
				var price := float(v.get(price_key, 0.0))
				if stock_available > 0 and price > 0.0:
					vendor_candidates.append({"vendor": v, "price": price, "stock": stock_available})
		vendor_candidates.sort_custom(func(a, b): return float(a.price) < float(b.price))
		if vendor_candidates.is_empty():
			continue

		var weight_per_unit: float = float(resource_weights.get(res, 1.0))
		if weight_per_unit <= 0.0:
			weight_per_unit = 1.0

		state_by_res[res] = {
			"res": res,
			"max": max_amount,
			"current": current_amount,
			"needed": needed_remaining,
			"vendors": vendor_candidates,
			"vendor_idx": 0,
			"vendor_stock_left": int(vendor_candidates[0].stock),
			"weight_per_unit": weight_per_unit,
		}

	if state_by_res.is_empty():
		return plan

	var planned_set: Dictionary = {}
	# Keyed by "res|vendor_id" so we can merge allocations and avoid 1-unit spam.
	var alloc_index_by_key: Dictionary = {}
	var last_picked_res: String = ""
	var safety := 0
	while true:
		safety += 1
		if safety > 10000:
			break

		if budget_limited and remaining_budget < 0.01:
			break
		if not weight_limited and remaining_weight <= 0.001:
			break

		# Build list of resources that can still accept at least 1 unit.
		var active: Array = []
		for res: String in TOP_UP_RESOURCES:
			if not state_by_res.has(res):
				continue
			var s: Dictionary = state_by_res[res]
			if int(s.get("needed", 0)) <= 0:
				continue
			var vendors: Array = s.get("vendors", [])
			var vidx: int = int(s.get("vendor_idx", 0))
			if vidx >= vendors.size():
				continue
			var price := float(vendors[vidx].price)
			if budget_limited and remaining_budget < price:
				continue
			if not weight_limited:
				var wpu := float(s.get("weight_per_unit", 1.0))
				if remaining_weight < wpu:
					continue
			active.append(res)
		if active.is_empty():
			break

		# Compute min fill percentage among active resources.
		var min_fill := 999.0
		for res: String in active:
			var s: Dictionary = state_by_res[res]
			var fill := 1.0
			var max_amount := float(s.get("max", 0.0))
			if max_amount > 0.001:
				fill = float(s.get("current", 0.0)) / max_amount
			if fill < min_fill:
				min_fill = fill

		# Collect all resources tied for min fill (within epsilon), and rotate tie-breaking.
		var eps := 0.000001
		var tied: Array = []
		for res: String in active:
			var s: Dictionary = state_by_res[res]
			var max_amount := float(s.get("max", 0.0))
			var fill := 1.0
			if max_amount > 0.001:
				fill = float(s.get("current", 0.0)) / max_amount
			if abs(fill - min_fill) <= eps:
				tied.append(res)
		if tied.is_empty():
			break

		var pick_res := String(tied[0])
		if tied.size() > 1 and last_picked_res != "":
			var last_idx := tied.find(last_picked_res)
			if last_idx != -1:
				pick_res = String(tied[(last_idx + 1) % tied.size()])
		last_picked_res = pick_res

		var s_pick: Dictionary = state_by_res[pick_res]
		var max_pick := float(s_pick.get("max", 0.0))
		if max_pick <= 0.001:
			break

		# Find the next higher fill among active resources so we can buy in chunks.
		var next_fill := 1.0
		var found_next := false
		for res: String in active:
			var s: Dictionary = state_by_res[res]
			var max_amount := float(s.get("max", 0.0))
			if max_amount <= 0.001:
				continue
			var fill := float(s.get("current", 0.0)) / max_amount
			if fill > (min_fill + eps):
				if not found_next or fill < next_fill:
					next_fill = fill
					found_next = true
		if not found_next:
			next_fill = 1.0

		var units_to_target := int(ceil(max(0.0, (next_fill - min_fill)) * max_pick))
		if units_to_target <= 0:
			units_to_target = 1

		# Ensure vendor pointer is on a valid candidate with stock.
		var vendors: Array = s_pick.get("vendors", [])
		var vidx: int = int(s_pick.get("vendor_idx", 0))
		var stock_left: int = int(s_pick.get("vendor_stock_left", 0))
		while vidx < vendors.size() and stock_left <= 0:
			vidx += 1
			if vidx < vendors.size():
				stock_left = int(vendors[vidx].stock)
		s_pick.vendor_idx = vidx
		s_pick.vendor_stock_left = stock_left
		state_by_res[pick_res] = s_pick
		if vidx >= vendors.size():
			continue

		var price: float = float(vendors[vidx].price)
		var weight_per_unit: float = float(s_pick.get("weight_per_unit", 1.0))
		var take_qty: int = min(units_to_target, int(s_pick.get("needed", 0)))
		take_qty = min(take_qty, stock_left)
		if budget_limited:
			take_qty = min(take_qty, int(floor(remaining_budget / price)))
		if not weight_limited and remaining_weight < 999998:
			take_qty = min(take_qty, int(floor(remaining_weight / weight_per_unit)))
		if take_qty <= 0:
			continue

		var vdict: Dictionary = vendors[vidx].vendor
		var vendor_id := str(vdict.get("vendor_id", ""))
		var vendor_name := str(vdict.get("name", "Vendor"))
		var subtotal := float(take_qty) * price

		var alloc_key: String = String(pick_res) + "|" + String(vendor_id)
		if alloc_index_by_key.has(alloc_key):
			var idx: int = int(alloc_index_by_key.get(alloc_key, -1))
			if idx >= 0 and idx < plan.allocations.size():
				var existing: Dictionary = plan.allocations[idx]
				existing.quantity = int(existing.get("quantity", 0)) + int(take_qty)
				existing.subtotal = float(existing.get("subtotal", 0.0)) + float(subtotal)
				# Keep vendor_name/price stable; refresh just in case.
				existing.vendor_name = vendor_name
				existing.price = price
				plan.allocations[idx] = existing
			else:
				alloc_index_by_key.erase(alloc_key)
				plan.allocations.append({
					"res": pick_res,
					"vendor_id": vendor_id,
					"vendor_name": vendor_name,
					"price": price,
					"quantity": take_qty,
					"subtotal": subtotal
				})
				alloc_index_by_key[alloc_key] = plan.allocations.size() - 1
		else:
			plan.allocations.append({
				"res": pick_res,
				"vendor_id": vendor_id,
				"vendor_name": vendor_name,
				"price": price,
				"quantity": take_qty,
				"subtotal": subtotal
			})
			alloc_index_by_key[alloc_key] = plan.allocations.size() - 1
		plan.total_cost += subtotal
		remaining_budget -= subtotal
		if not weight_limited:
			remaining_weight -= float(take_qty) * weight_per_unit

		# Update state for the picked resource.
		s_pick.current = float(s_pick.get("current", 0.0)) + float(take_qty)
		s_pick.needed = int(s_pick.get("needed", 0)) - take_qty
		s_pick.vendor_stock_left = stock_left - take_qty
		state_by_res[pick_res] = s_pick

		# Aggregate totals for UI/tooltip.
		if not plan.resources.has(pick_res):
			plan.resources[pick_res] = {"total_quantity": 0, "total_cost": 0.0}
		plan.resources[pick_res].total_quantity += int(take_qty)
		plan.resources[pick_res].total_cost += subtotal
		planned_set[pick_res] = true

	# Preserve a stable resource ordering for any UI consumption.
	for res in TOP_UP_RESOURCES:
		if planned_set.has(res):
			plan.planned_list.append(res)
	return plan

func _on_top_up_button_pressed():
	if _top_up_plan.is_empty() or _top_up_plan.get("resources", {}).is_empty():
		return
	var convoy_uuid = str(convoy_data_received.get("convoy_id", ""))
	if convoy_uuid.is_empty():
		return
	if not is_instance_valid(_api):
		return
	# Execute purchases individually
	for alloc in _top_up_plan.allocations:
		var res = alloc.get("res", "")
		var vendor_id = str(alloc.get("vendor_id", ""))
		var send_qty:int = int(alloc.get("quantity", 0))
		if res == "" or vendor_id.is_empty() or send_qty <= 0:
			continue
		print("[TopUp] Purchasing %d %s from vendor %s (price=%.2f) convoy=%s" % [send_qty, res, vendor_id, float(alloc.get("price",0.0)), convoy_uuid])
		_api.buy_resource(vendor_id, convoy_uuid, String(res), float(send_qty))
	
	# Trigger refreshes
	if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
		_convoy_service.refresh_single(convoy_uuid)
	if is_instance_valid(_user_service) and _user_service.has_method("refresh_user"):
		_user_service.refresh_user()
	
	# Disable button until refresh
	if is_instance_valid(top_up_button):
		top_up_button.disabled = true
		top_up_button.text = "Top Up (Processing...)"

	# Refresh confirmation panel if visible to update resource warnings
	if is_instance_valid(_confirmation_panel) and _confirmation_panel.visible:
		# Small delay to allow transactions to register locally before rebuilding
		get_tree().create_timer(0.2).timeout.connect(func():
			if is_instance_valid(_confirmation_panel) and _confirmation_panel.visible:
				_cycle_route(0)
		)

func _style_top_up_button():
	if not is_instance_valid(top_up_button):
		return
	# --- Button StyleBoxes (Cloned) ---
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.15, 0.18, 1.0)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(0.40, 0.60, 0.90)
	normal.shadow_color = Color(0,0,0,0.6)
	normal.shadow_size = 3

	var hover = normal.duplicate()
	hover.bg_color = Color(0.22, 0.22, 0.28, 1.0)
	hover.border_color = Color(0.55, 0.75, 1.0)

	var pressed = normal.duplicate()
	pressed.bg_color = Color(0.10, 0.10, 0.14, 1.0)
	pressed.border_color = Color(0.30, 0.50, 0.80)

	var disabled = normal.duplicate()
	disabled.bg_color = Color(0.08, 0.08, 0.09, 1.0)
	disabled.border_color = Color(0.20, 0.20, 0.20)
	disabled.shadow_size = 0

	top_up_button.add_theme_stylebox_override("normal", normal)
	top_up_button.add_theme_stylebox_override("hover", hover)
	top_up_button.add_theme_stylebox_override("pressed", pressed)
	top_up_button.add_theme_stylebox_override("disabled", disabled)

	# --- Tooltip Style ---
	var tooltip_panel = StyleBoxFlat.new()
	tooltip_panel.bg_color = Color(0.05, 0.05, 0.06, 1.0)
	tooltip_panel.corner_radius_top_left = 4
	tooltip_panel.corner_radius_top_right = 4
	tooltip_panel.corner_radius_bottom_left = 4
	tooltip_panel.corner_radius_bottom_right = 4
	tooltip_panel.border_color = Color(0.60, 0.60, 0.70)
	tooltip_panel.border_width_left = 1
	tooltip_panel.border_width_right = 1
	tooltip_panel.border_width_top = 1
	tooltip_panel.border_width_bottom = 1
	tooltip_panel.shadow_color = Color(0,0,0,0.7)
	tooltip_panel.shadow_size = 4
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		tooltip_panel.set_content_margin(side, 6)
	top_up_button.add_theme_stylebox_override("tooltip_panel", tooltip_panel)

	# --- Font & Colors ---
	top_up_button.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	top_up_button.add_theme_color_override("font_color_hover", Color(1.0, 1.0, 1.0))
	top_up_button.add_theme_color_override("font_color_pressed", Color(0.85, 0.90, 1.0))
	top_up_button.add_theme_color_override("font_color_disabled", Color(0.55, 0.55, 0.60))
	top_up_button.add_theme_font_size_override("font_size", 18)

	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		normal.set_content_margin(side, normal.get_content_margin(side) + 2)
		hover.set_content_margin(side, hover.get_content_margin(side) + 2)
		pressed.set_content_margin(side, pressed.get_content_margin(side) + 2)
		disabled.set_content_margin(side, disabled.get_content_margin(side) + 2)

func _on_store_user_changed(_user: Dictionary) -> void:
	# Money changes affect top-up affordability/tooltips.
	_update_top_up_button()
