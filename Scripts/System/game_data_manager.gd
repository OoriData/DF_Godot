extends Node

# Emitted when the initial map and settlement data has been loaded.
signal map_data_loaded(map_tiles_data: Array)
signal settlement_data_updated(settlement_data_list: Array)

# Emitted when convoy data is received and processed.
# Passes the fully augmented convoy data.
signal convoy_data_updated(all_convoy_data_list: Array)
# Emitted when the current user's data (like money) is updated.
signal user_data_updated(user_data: Dictionary)
signal vendor_panel_data_ready(vendor_panel_data: Dictionary)
# Emitted when a convoy is selected or deselected in the UI.
signal convoy_selection_changed(selected_convoy_data: Variant)
signal journey_canceled(convoy_data: Dictionary)

# New lifecycle / aggregation signals
signal initial_data_ready  # Fired once after first map + first convoy data loaded
signal game_data_reset      # Fired when user-auth related data is cleared (logout / expiry)


# --- Journey Planning Signals ---
signal route_info_ready(convoy_data: Dictionary, destination_data: Dictionary, route_choices: Array)
# Removed unused journey_started signal (was flagged as unused)
# NEW: emitted when a route choice request starts so UI can show loading
signal route_choices_request_started(convoy_id: String, destination_data: Dictionary)
# NEW: emitted if the route choice request fails (API error or empty result)
signal route_choices_error(convoy_id: String, destination_data: Dictionary, error_message: String)

# --- Node References ---
# Adjust the path if your APICallsInstance is located differently relative to GameDataManager
# when GameDataManager is an Autoload (it will be /root/APICallsInstance if APICallsInstance is also an Autoload or a direct child of root).
# For now, assuming APICallsInstance will also be an Autoload or accessible globally.
var api_calls_node: Node = null # Will be fetched in _ready

# --- Data Storage ---
var map_tiles: Array = []
var all_settlement_data: Array = []
var all_convoy_data: Array = [] # Stores augmented convoy data
var current_user_data: Dictionary = {}
var _selected_convoy_id: String = ""
var convoy_id_to_color_map: Dictionary = {}

# --- Journey Planning State ---
var _pending_journey_convoy_id: String = ""
var _pending_journey_destination_data: Dictionary = {}

# --- Internal State ---
var _last_assigned_color_idx: int = -1
var _map_loaded: bool = false
var _convoys_loaded: bool = false
var _initial_data_ready_emitted: bool = false
var _user_bootstrap_done: bool = false
var _map_request_in_flight: bool = false

# --- Debug Toggles ---
const VEHICLE_DEBUG_DUMP := true # Set true to print raw & augmented convoy + vehicle data on receipt
const ROUTE_DEBUG_DUMP := true # Dump route choice structures when received
const DEBUG_JSON_CHAR_LIMIT := 2500

func _json_snippet(data: Variant, label: String="") -> void:
	var encoded := JSON.stringify(data, "  ")
	if encoded.length() > DEBUG_JSON_CHAR_LIMIT:
		encoded = encoded.substr(0, DEBUG_JSON_CHAR_LIMIT) + "...<truncated>"
	if label != "":
		print('[GameDataManager][DEBUG][JSON]', label, '=', encoded)
	else:
		print('[GameDataManager][DEBUG][JSON]', encoded)

# This should be the single source of truth for these colors.
const PREDEFINED_CONVOY_COLORS: Array[Color] = [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW, Color.CYAN, Color.MAGENTA,
	Color('orange'), Color('purple'), Color('lime'), Color('pink')
]


func _ready():
	print("[GameDataManager] _ready: Initializing...")
	# Use call_deferred to ensure all Autoload nodes have completed their _ready functions
	# before we try to access them. This is a robust way to handle inter-Autoload dependencies.
	call_deferred("_initiate_preload")

func _initiate_preload():
	# APICalls is now an Autoload, so we can get it directly.
	# It should be loaded before GameDataManager in the project settings.
	api_calls_node = get_node_or_null("/root/APICalls")
	if is_instance_valid(api_calls_node):
		# Connect signals directly
		if api_calls_node.has_signal('convoy_data_received'):
			api_calls_node.convoy_data_received.connect(_on_raw_convoy_data_received)
		if api_calls_node.has_signal('map_data_received'):
			api_calls_node.map_data_received.connect(_on_map_data_received_from_api)
		if api_calls_node.has_signal('user_data_received'):
			api_calls_node.user_data_received.connect(_on_user_data_received_from_api)
		if api_calls_node.has_signal('vendor_data_received'):
			api_calls_node.vendor_data_received.connect(update_single_vendor)
		# Transaction patch signals that return updated convoy objects (resource buys etc.)
		if api_calls_node.has_signal('resource_bought') and not api_calls_node.resource_bought.is_connected(_on_resource_transaction):
			api_calls_node.resource_bought.connect(_on_resource_transaction)
		if api_calls_node.has_signal('resource_sold') and not api_calls_node.resource_sold.is_connected(_on_resource_transaction):
			api_calls_node.resource_sold.connect(_on_resource_transaction)
		if api_calls_node.has_signal('cargo_bought') and not api_calls_node.cargo_bought.is_connected(_on_convoy_transaction):
			api_calls_node.cargo_bought.connect(_on_convoy_transaction)
		if api_calls_node.has_signal('cargo_sold') and not api_calls_node.cargo_sold.is_connected(_on_convoy_transaction):
			api_calls_node.cargo_sold.connect(_on_convoy_transaction)
		if api_calls_node.has_signal('vehicle_bought') and not api_calls_node.vehicle_bought.is_connected(_on_convoy_transaction):
			api_calls_node.vehicle_bought.connect(_on_convoy_transaction)
		if api_calls_node.has_signal('vehicle_sold') and not api_calls_node.vehicle_sold.is_connected(_on_convoy_transaction):
			api_calls_node.vehicle_sold.connect(_on_convoy_transaction)
		if api_calls_node.has_signal('route_choices_received'):
			api_calls_node.route_choices_received.connect(_on_api_route_choices_received)
		if api_calls_node.has_signal('convoy_sent_on_journey'):
			api_calls_node.convoy_sent_on_journey.connect(_on_convoy_sent_on_journey)
		if api_calls_node.has_signal('convoy_journey_canceled') and not api_calls_node.convoy_journey_canceled.is_connected(_on_convoy_journey_canceled):
			api_calls_node.convoy_journey_canceled.connect(_on_convoy_journey_canceled)
		# New auth-related signals
		if api_calls_node.has_signal('auth_session_received'):
			api_calls_node.auth_session_received.connect(_on_auth_session_received)
		if api_calls_node.has_signal('user_id_resolved'):
			api_calls_node.user_id_resolved.connect(_on_user_id_resolved)
		if api_calls_node.has_signal('auth_expired'):
			api_calls_node.auth_expired.connect(_on_auth_expired)
		# If user already authenticated before this node ready (auto-login path)
		if api_calls_node.has_method('is_auth_token_valid') and api_calls_node.is_auth_token_valid():
			# Directly access property (script variable) instead of has_variable (invalid in Godot 4)
			var existing_id: String = api_calls_node.current_user_id
			if typeof(existing_id) == TYPE_STRING and existing_id != "":
				print('[GameDataManager] Detected existing authenticated user id. Bootstrapping data loads.')
				_on_user_id_resolved(existing_id)
		else:
			print('[GameDataManager] No valid auth token at init.')
		# Removed early request_map_data(); will be triggered after login success or separately by UI.
		if api_calls_node.has_signal('fetch_error') and not api_calls_node.fetch_error.is_connected(_on_api_fetch_error):
			api_calls_node.fetch_error.connect(_on_api_fetch_error)
	else:
		printerr("GameDataManager (_initiate_preload): Could not find APICalls Autoload. Map data will not be preloaded.")

func _on_auth_session_received(_token: String) -> void:
	# After session token, the APICalls will try to resolve DF user id via /auth/me
	print('[GameDataManager] Auth session received. Awaiting DF user id…')

func _on_user_id_resolved(user_id: String) -> void:
	if _user_bootstrap_done:
		print('[GameDataManager] _on_user_id_resolved ignored; bootstrap already done.')
		return
	print('[GameDataManager] Resolved DF user id from session: ', user_id)
	_user_bootstrap_done = true
	if is_instance_valid(api_calls_node):
		api_calls_node.set_user_id(user_id)
		request_user_data_refresh()
		if api_calls_node.has_method('get_user_convoys'):
			api_calls_node.get_user_convoys(user_id)
		# Trigger map load now that auth began (parallel path) if not already loaded
		if not _map_loaded and not _map_request_in_flight:
			_map_request_in_flight = true
			request_map_data()

func _on_auth_expired() -> void:
	print('[GameDataManager] Auth expired. Resetting user-related state.')
	reset_user_state()

func reset_user_state(clear_map: bool = false) -> void:
	# Clear user-associated runtime data while optionally retaining map tiles.
	current_user_data = {}
	all_convoy_data = []
	convoy_id_to_color_map.clear()
	_selected_convoy_id = ""
	_last_assigned_color_idx = -1
	_convoys_loaded = false
	_initial_data_ready_emitted = false
	_user_bootstrap_done = false
	_map_request_in_flight = false
	if clear_map:
		map_tiles = []
		all_settlement_data = []
		_map_loaded = false
	convoy_data_updated.emit(all_convoy_data)
	user_data_updated.emit(current_user_data)
	game_data_reset.emit()

func _maybe_emit_initial_ready() -> void:
	if _initial_data_ready_emitted:
		return
	if _map_loaded and _convoys_loaded:
		_initial_data_ready_emitted = true
		print('[GameDataManager] Initial data ready (map + convoys). Emitting initial_data_ready.')
		initial_data_ready.emit()


func _on_map_data_received_from_api(map_data_dict: Dictionary):
	_map_request_in_flight = false
	if not map_data_dict.has("tiles"):
		printerr("GameDataManager: Received map data dictionary from API, but it's missing the 'tiles' key.")
		return

	var tiles_from_api: Array = map_data_dict.get("tiles", [])
	map_tiles = tiles_from_api # Store the tiles array
	map_data_loaded.emit(map_tiles)
	# print("GameDataManager: Map data loaded. Tiles count: %s" % map_tiles.size())

	# Extract settlement data
	all_settlement_data.clear()
	if not map_tiles.is_empty():
		for y_idx in range(map_tiles.size()):
			var row = map_tiles[y_idx]
			if not row is Array: continue
			for x_idx in range(row.size()):
				var tile_data = row[x_idx]
				if tile_data is Dictionary and tile_data.has('settlements'):
					var settlements_on_tile = tile_data.get('settlements', [])
					if settlements_on_tile is Array:
						for settlement_entry in settlements_on_tile:
							if settlement_entry is Dictionary and settlement_entry.has('name'):
								var settlement_info_for_render = settlement_entry.duplicate()
								settlement_info_for_render['x'] = x_idx
								settlement_info_for_render['y'] = y_idx
								all_settlement_data.append(settlement_info_for_render)
	settlement_data_updated.emit(all_settlement_data)
	_map_loaded = true
	_maybe_emit_initial_ready()

	# print("GameDataManager: Settlement data extracted. Count: %s" % all_settlement_data.size())


func _on_user_data_received_from_api(p_user_data: Dictionary):
	if p_user_data.is_empty():
		printerr("GameDataManager: Received empty user data dictionary.")
		return
	current_user_data = p_user_data
	# Debug: show top-level keys and try to surface convoy-related fields
	print("[GameDataManager] User data keys: ", current_user_data.keys())
	if current_user_data.has("convoys") and current_user_data.convoys is Array:
		print("[GameDataManager] Found 'convoys' with ", current_user_data.convoys.size(), " entries.")
	elif current_user_data.has("user_convoys") and current_user_data.user_convoys is Array:
		print("[GameDataManager] Found 'user_convoys' with ", current_user_data.user_convoys.size(), " entries.")

	user_data_updated.emit(current_user_data)

	# Extract convoy list from the user payload and integrate with existing flow
	var convoy_list: Array = _extract_convoys_from_user(current_user_data)
	if convoy_list is Array and not convoy_list.is_empty():
		print("[GameDataManager] Extracted ", convoy_list.size(), " convoy records from user data. Integrating...")
		_on_raw_convoy_data_received(convoy_list)
	else:
		print("[GameDataManager] No convoy list found in user data. Waiting for next update or different schema.")

# Attempt to find the convoy array in various common fields or nested structures
func _extract_convoys_from_user(user_dict: Dictionary) -> Array:
	var fields := [
		"convoys", "user_convoys", "convoy_list", "convoyData", "convoy_data"
	]
	for f in fields:
		if user_dict.has(f) and user_dict[f] is Array:
			return user_dict[f]
	# Look into common nesting containers
	var nest_keys := ["data", "attributes", "result", "payload"]
	for nk in nest_keys:
		if user_dict.has(nk) and user_dict[nk] is Dictionary:
			var arr := _extract_convoys_from_user(user_dict[nk])
			if arr is Array and not arr.is_empty():
				return arr
	return []

func _on_raw_convoy_data_received(raw_data: Variant):
	# Always expect raw convoy data (Array of Dictionaries) from APICalls.
	var parsed_convoy_list: Array = []

	# Accept both Array and Dictionary (for single convoy fetch)
	if raw_data is Array:
		parsed_convoy_list = raw_data
	elif raw_data is Dictionary:
		parsed_convoy_list = [raw_data]
	else:
		printerr('GameDataManager: Received convoy data is not in a recognized format. Data: ', raw_data)
		all_convoy_data = [] # Clear existing data
		convoy_data_updated.emit(all_convoy_data)
		return

	# Only print if no convoys found
	if parsed_convoy_list.is_empty():
		print("[GameDataManager] No convoys found in raw data.")

	var augmented_convoys: Array = []
	for raw_convoy_item in parsed_convoy_list:
		var augmented = augment_single_convoy(raw_convoy_item)
		augmented_convoys.append(augmented)
		if VEHICLE_DEBUG_DUMP and raw_convoy_item is Dictionary:
			_print_convoy_debug_dump(raw_convoy_item, augmented)

	all_convoy_data = augmented_convoys

	# --- ADD THIS LOGGING ---
	# if not all_convoy_data.is_empty():
		# var first_aug = all_convoy_data[0]
		# print("GameDataManager: First AUGMENTED convoy keys: ", first_aug.keys())
		# print("GameDataManager: First AUGMENTED vehicle_details_list: ", first_aug.get("vehicle_details_list", []))
		# if first_aug.has("vehicle_details_list") and first_aug["vehicle_details_list"].size() > 0:
		# 	print("GameDataManager: First AUGMENTED vehicle keys: ", first_aug["vehicle_details_list"][0].keys())
	# --- END LOGGING ---

	convoy_data_updated.emit(all_convoy_data)
	_convoys_loaded = true
	_maybe_emit_initial_ready()


func get_convoy_id_to_color_map() -> Dictionary:
	"""Provides the current mapping of convoy IDs to colors."""
	return convoy_id_to_color_map

func augment_single_convoy(raw_convoy_item: Dictionary) -> Dictionary:
	"""
	Takes a single raw convoy dictionary from the API and returns a fully
	processed ("augmented") version with client-side data like colors and
	journey progress calculations.
	"""
	if not raw_convoy_item is Dictionary:
		printerr("GameDataManager (augment_single_convoy): Expected a Dictionary, but got %s." % typeof(raw_convoy_item))
		return {}

	var augmented_item = raw_convoy_item.duplicate(true)

	# --- Ensure convoy_name is set correctly ---
	if not augmented_item.has("convoy_name"):
		if augmented_item.has("name"):
			augmented_item["convoy_name"] = str(augmented_item["name"])
		else:
			augmented_item["convoy_name"] = "Unnamed Convoy"

	# --- Map vehicles to vehicle_details_list for UI compatibility ---
	if not augmented_item.has("vehicle_details_list") and augmented_item.has("vehicles"):
		augmented_item["vehicle_details_list"] = augmented_item["vehicles"]

	# Assign color if it's a new convoy
	var convoy_id_val = augmented_item.get('convoy_id')
	if convoy_id_val != null:
		var convoy_id_str = str(convoy_id_val)
		if not convoy_id_str.is_empty() and not convoy_id_to_color_map.has(convoy_id_str):
			_last_assigned_color_idx = (_last_assigned_color_idx + 1) % PREDEFINED_CONVOY_COLORS.size()
			convoy_id_to_color_map[convoy_id_str] = PREDEFINED_CONVOY_COLORS[_last_assigned_color_idx]

	# Calculate precise position and progress details
	augmented_item = _calculate_convoy_progress_details(augmented_item)

	# Only print if convoy_name is missing
	if not raw_convoy_item.has("convoy_name"):
		print("[GameDataManager] augment_single_convoy: convoy_name missing for convoy_id:", raw_convoy_item.get("convoy_id", "N/A"))

	return augmented_item

# --- Debug helper to dump convoy, journey, and vehicle data ---
func _print_convoy_debug_dump(raw_convoy: Dictionary, augmented_convoy: Dictionary) -> void:
	var cid_raw = str(raw_convoy.get('convoy_id', ''))
	print('\n[GameDataManager][DEBUG][ConvoyDump] --- RAW CONVOY START id=', cid_raw, ' ---')
	print('[GameDataManager][DEBUG][ConvoyDump] Raw keys: ', raw_convoy.keys())
	if raw_convoy.has('journey') and raw_convoy.journey is Dictionary:
		print('[GameDataManager][DEBUG][ConvoyDump] Raw journey keys: ', raw_convoy.journey.keys(), ' progress=', raw_convoy.journey.get('progress'), ' length=', raw_convoy.journey.get('length'))
		print('[GameDataManager][DEBUG][ConvoyDump] Raw journey route sizes rx=', (raw_convoy.journey.get('route_x', []) as Array).size(), ' ry=', (raw_convoy.journey.get('route_y', []) as Array).size())
	if raw_convoy.has('vehicles') and raw_convoy.vehicles is Array:
		print('[GameDataManager][DEBUG][ConvoyDump] Raw vehicles count=', raw_convoy.vehicles.size())
		for v in raw_convoy.vehicles:
			if not (v is Dictionary):
				continue
			var vid = v.get('vehicle_id')
			var v_keys = v.keys()
			print('[GameDataManager][DEBUG][ConvoyDump][VehicleRaw] id=', vid, ' name=', v.get('name'), ' keys=', v_keys)
			# Surface possible battery / energy related fields
			var energy_fields: Array = []
			for k in v_keys:
				var kl = str(k).to_lower()
				if kl.find('battery') != -1 or kl.find('kwh') != -1 or kl.find('charge') != -1 or kl.find('energy') != -1:
					energy_fields.append(str(k) + '=' + str(v.get(k)))
			if not energy_fields.is_empty():
				print('[GameDataManager][DEBUG][ConvoyDump][VehicleRaw] id=', vid, ' energy_fields: ', energy_fields)
			if v.has('cargo') and v.cargo is Array and v.cargo.size() > 0:
				var cargo_energy: Array = []
				for item in v.cargo:
					if item is Dictionary:
						for ck in item.keys():
							var ckl = str(ck).to_lower()
							if ckl.find('kwh') != -1 or ckl.find('battery') != -1 or ckl.find('charge') != -1 or ckl.find('energy') != -1:
								cargo_energy.append(str(ck) + '=' + str(item.get(ck)))
				if not cargo_energy.is_empty():
					print('[GameDataManager][DEBUG][ConvoyDump][VehicleRaw] id=', vid, ' cargo_energy_fields: ', cargo_energy)
	print('[GameDataManager][DEBUG][ConvoyDump] --- RAW CONVOY END id=', cid_raw, ' ---')
	# Augmented snapshot
	var cid_aug = str(augmented_convoy.get('convoy_id', cid_raw))
	print('[GameDataManager][DEBUG][ConvoyDump] --- AUGMENTED CONVOY START id=', cid_aug, ' ---')
	print('[GameDataManager][DEBUG][ConvoyDump] Aug keys: ', augmented_convoy.keys())
	if augmented_convoy.has('journey') and augmented_convoy.journey is Dictionary:
		print('[GameDataManager][DEBUG][ConvoyDump] Aug journey keys: ', augmented_convoy.journey.keys(), ' progress=', augmented_convoy.journey.get('progress'), ' length=', augmented_convoy.journey.get('length'))
	if augmented_convoy.has('vehicle_details_list') and augmented_convoy.vehicle_details_list is Array:
		print('[GameDataManager][DEBUG][ConvoyDump] Aug vehicles count=', augmented_convoy.vehicle_details_list.size())
		for v in augmented_convoy.vehicle_details_list:
			if not (v is Dictionary):
				continue
			var vid2 = v.get('vehicle_id')
			var v_keys2 = v.keys()
			print('[GameDataManager][DEBUG][ConvoyDump][VehicleAug] id=', vid2, ' name=', v.get('name'), ' keys=', v_keys2)
			var energy_fields2: Array = []
			for k in v_keys2:
				var kl2 = str(k).to_lower()
				if kl2.find('battery') != -1 or kl2.find('kwh') != -1 or kl2.find('charge') != -1 or kl2.find('energy') != -1:
					energy_fields2.append(str(k) + '=' + str(v.get(k)))
			if not energy_fields2.is_empty():
				print('[GameDataManager][DEBUG][ConvoyDump][VehicleAug] id=', vid2, ' energy_fields: ', energy_fields2)
			if v.has('cargo') and v.cargo is Array and v.cargo.size() > 0:
				var cargo_energy2: Array = []
				for item in v.cargo:
					if item is Dictionary:
						for ck in item.keys():
							var ckl2 = str(ck).to_lower()
							if ckl2.find('kwh') != -1 or ckl2.find('battery') != -1 or ckl2.find('charge') != -1 or ckl2.find('energy') != -1:
								cargo_energy2.append(str(ck) + '=' + str(item.get(ck)))
				if not cargo_energy2.is_empty():
					print('[GameDataManager][DEBUG][ConvoyDump][VehicleAug] id=', vid2, ' cargo_energy_fields: ', cargo_energy2)
	print('[GameDataManager][DEBUG][ConvoyDump] --- AUGMENTED CONVOY END id=', cid_aug, ' ---\n')


func _calculate_convoy_progress_details(convoy_data_item: Dictionary) -> Dictionary:
	# This function MODIFIES the convoy_data_item by adding '_current_segment_start_idx', 
	# '_progress_in_segment', and updates 'x' and 'y' to the precise interpolated tile coordinates.
	if not convoy_data_item is Dictionary:
		return convoy_data_item

	var convoy_id_str = str(convoy_data_item.get("convoy_id", "N/A"))
	var raw_journey = convoy_data_item.get("journey")
	
	# --- In-Transit Convoy Calculation ---
	if raw_journey is Dictionary:
		var journey_data_for_shared: Dictionary = raw_journey
		var route_x: Array = journey_data_for_shared.get("route_x", [])
		var route_y: Array = journey_data_for_shared.get("route_y", [])

		# Debug: Print journey route info for this convoy
		print("[GameDataManager] _calculate_convoy_progress_details convoy_id:", convoy_id_str, "route_x:", route_x, "route_y:", route_y)
		if convoy_data_item.has("x") and convoy_data_item.has("y"):
			print("[GameDataManager] convoy_data_item x:", convoy_data_item["x"], "y:", convoy_data_item["y"])
		if route_x.size() >= 2 and route_y.size() == route_x.size():
			var journey_progress: float = journey_data_for_shared.get("progress", 0.0)
			var num_total_segments = route_x.size() - 1
			var cumulative_dist: float = 0.0
			var total_path_length: float = 0.0

			for k_calc_idx in range(num_total_segments):
				var p_s_calc = Vector2(float(route_x[k_calc_idx]), float(route_y[k_calc_idx]))
				var p_e_calc = Vector2(float(route_x[k_calc_idx+1]), float(route_y[k_calc_idx+1]))
				total_path_length += p_s_calc.distance_to(p_e_calc)

			if total_path_length <= 0.001:
				convoy_data_item["x"] = float(route_x[0])
				convoy_data_item["y"] = float(route_y[0])
				convoy_data_item["_current_segment_start_idx"] = 0
				convoy_data_item["_progress_in_segment"] = 0.0
			elif journey_progress <= 0.001:
				convoy_data_item["x"] = float(route_x[0])
				convoy_data_item["y"] = float(route_y[0])
				convoy_data_item["_current_segment_start_idx"] = 0
				convoy_data_item["_progress_in_segment"] = 0.0
			elif journey_progress >= total_path_length - 0.001:
				convoy_data_item["x"] = float(route_x[num_total_segments])
				convoy_data_item["y"] = float(route_y[num_total_segments])
				convoy_data_item["_current_segment_start_idx"] = num_total_segments - 1
				convoy_data_item["_progress_in_segment"] = 1.0
			else:
				var found_segment = false
				for k_idx in range(num_total_segments):
					var p_start_tile = Vector2(float(route_x[k_idx]), float(route_y[k_idx]))
					var p_end_tile = Vector2(float(route_x[k_idx+1]), float(route_y[k_idx+1]))
					var segment_length = p_start_tile.distance_to(p_end_tile)
					
					if journey_progress >= cumulative_dist - 0.001 and journey_progress <= cumulative_dist + segment_length + 0.001:
						var progress_within_segment = 0.0
						if segment_length > 0.001:
							progress_within_segment = (journey_progress - cumulative_dist) / segment_length
						else:
							progress_within_segment = 1.0
						
						progress_within_segment = clamp(progress_within_segment, 0.0, 1.0)
						
						var interpolated_pos = p_start_tile.lerp(p_end_tile, progress_within_segment)
						convoy_data_item["x"] = interpolated_pos.x
						convoy_data_item["y"] = interpolated_pos.y
						convoy_data_item["_current_segment_start_idx"] = k_idx
						convoy_data_item["_progress_in_segment"] = progress_within_segment
						found_segment = true
						break
					cumulative_dist += segment_length
					
				if not found_segment:
					convoy_data_item["x"] = float(route_x[num_total_segments])
					convoy_data_item["y"] = float(route_y[num_total_segments])
					convoy_data_item["_current_segment_start_idx"] = num_total_segments - 1
					convoy_data_item["_progress_in_segment"] = 1.0
			return convoy_data_item

	# --- Stationary Convoy Handling (or journey with no route) ---
	if not convoy_data_item.has("x") or not convoy_data_item.has("y"):
		# Try to use last known tile position if available
		if convoy_data_item.has("tile_x") and convoy_data_item.has("tile_y"):
			convoy_data_item["x"] = int(convoy_data_item["tile_x"])
			convoy_data_item["y"] = int(convoy_data_item["tile_y"])
		elif convoy_data_item.has("current_tile_x") and convoy_data_item.has("current_tile_y"):
			convoy_data_item["x"] = int(convoy_data_item["current_tile_x"])
			convoy_data_item["y"] = int(convoy_data_item["current_tile_y"])
		else:
			# Fallback to 0,0 if no position info is available
			convoy_data_item["x"] = 0
			convoy_data_item["y"] = 0
	
	convoy_data_item["_current_segment_start_idx"] = -1
	convoy_data_item["_progress_in_segment"] = 0.0
	return convoy_data_item


func request_convoy_data_refresh() -> void:
	"""
	Called by an external system (e.g., a timer in main.gd) to trigger a new fetch
	of convoy data.
	"""
	if is_instance_valid(api_calls_node):
		if not api_calls_node.current_user_id.is_empty() and api_calls_node.has_method("get_user_convoys"):
			api_calls_node.get_user_convoys(api_calls_node.current_user_id)
		elif api_calls_node.has_method("get_all_in_transit_convoys"):
			api_calls_node.get_all_in_transit_convoys()
		else:
			printerr("GameDataManager: APICallsInstance is missing 'get_user_convoys' or 'get_all_in_transit_convoys' method.")
	else:
		printerr("GameDataManager: Cannot request convoy data refresh. APICallsInstance is invalid.")

func request_map_data(x_min: int = -1, x_max: int = -1, y_min: int = -1, y_max: int = -1) -> void:
	"""
	Triggers a request to the APICalls node to fetch map data from the backend.
	"""
	if is_instance_valid(api_calls_node) and api_calls_node.has_method("get_map_data"):
		api_calls_node.get_map_data(x_min, x_max, y_min, y_max)
	else:
		printerr("GameDataManager: Cannot request map data. APICallsInstance is invalid or missing 'get_map_data' method.")

func request_user_data_refresh() -> void:
	"""
	Called to trigger a new fetch of the current user's data (e.g., money).
	"""
	if is_instance_valid(api_calls_node):
		var user_id = api_calls_node.current_user_id
		if not user_id.is_empty() and api_calls_node.has_method("get_user_data"):
			api_calls_node.get_user_data(user_id)
		else:
			printerr("GameDataManager: Cannot request user data. User ID is not set or APICallsInstance is missing 'get_user_data' method.")
	else:
		printerr("GameDataManager: Cannot request user data refresh. APICallsInstance is invalid.")

func request_vendor_data_refresh(vendor_id: String) -> void:
	"""
	Called to trigger a new fetch of a specific vendor's data.
	Supports either request_vendor_data() (new) or get_vendor_data() (legacy alias).
	"""
	if not is_instance_valid(api_calls_node):
		printerr("GameDataManager: Cannot request vendor data. APICallsInstance is invalid.")
		return
	if api_calls_node.has_method("request_vendor_data"):
		api_calls_node.request_vendor_data(vendor_id)
	elif api_calls_node.has_method("get_vendor_data"):
		api_calls_node.get_vendor_data(vendor_id)
	else:
		printerr("GameDataManager: Cannot request vendor data. APICallsInstance missing both 'request_vendor_data' and 'get_vendor_data'.")

# --- Transaction Handlers ---
func _on_resource_transaction(result: Dictionary) -> void:
	# Backend returns the updated convoy object (convoy_after). Integrate it.
	if result.is_empty():
		printerr("GameDataManager: resource transaction returned empty result")
		return
	# Expect convoy keys like convoy_id, fuel, water, food, money etc.
	if result.has("convoy_id"):
		update_single_convoy(result)
		# Also refresh user money (if money changed) by requesting user data (lightweight)
		request_user_data_refresh()
		# Force authoritative single-convoy refetch to eliminate any drift vs backend computed fields
		var cid := str(result.get("convoy_id", ""))
		if cid != "" and is_instance_valid(api_calls_node) and api_calls_node.has_method("get_convoy_data"):
			print("[GameDataManager][ResourceTxn] Forcing post-transaction convoy refetch convoy_id=", cid)
			api_calls_node.get_convoy_data(cid)
	else:
		printerr("GameDataManager: resource transaction result missing convoy_id")

func _on_convoy_transaction(result: Dictionary) -> void:
	# Generic handler for cargo/vehicle buy/sell returning updated convoy
	if result.is_empty():
		return
	if result.has("convoy_id"):
		update_single_convoy(result)
		request_user_data_refresh()

func trigger_initial_convoy_data_fetch(p_user_id: String) -> void:
	if is_instance_valid(api_calls_node) and api_calls_node.has_method("get_user_convoys"):
		# Set the user ID for this and future refreshes.
		api_calls_node.set_user_id(p_user_id)
		# Also trigger a fetch for the user's own data (like money)
		request_user_data_refresh()
		# Let APICalls handle the validation and fallback logic internally.
		api_calls_node.get_user_convoys(p_user_id)
	else:
		printerr("GameDataManager: Cannot trigger initial convoy data fetch. APICallsInstance is invalid or missing 'get_user_convoys' method.")


func get_all_settlements_data() -> Array:
	"""Returns the cached list of all settlement data."""
	return all_settlement_data

func get_current_user_data() -> Dictionary:
	"""Returns the cached user data dictionary."""
	return current_user_data

func select_convoy_by_id(convoy_id_to_select: String, allow_toggle: bool = true) -> void:
	"""
	Central method to change the globally selected convoy by its ID.
	Handles selecting a new convoy. If allow_toggle is true, it will deselect if the same ID is passed again.
	"""
	var new_id_to_set = convoy_id_to_select
	# If the same ID is passed and toggling is allowed, it's a toggle to deselect.
	if allow_toggle and _selected_convoy_id == convoy_id_to_select:
		new_id_to_set = ""

	if _selected_convoy_id != new_id_to_set:
		_selected_convoy_id = new_id_to_set
		# Emit the signal with the full data of the selected convoy (or null)
		convoy_selection_changed.emit(get_selected_convoy())

func get_selected_convoy() -> Variant:
	"""Returns the full data dictionary of the selected convoy, or null."""
	if _selected_convoy_id.is_empty():
		return null
	for convoy in all_convoy_data:
		if str(convoy.get("convoy_id")) == _selected_convoy_id:
			return convoy
	_selected_convoy_id = "" # Clear invalid ID
	return null


func get_settlement_name_from_coords(target_x: int, target_y: int) -> String:
	"""
	Finds a settlement name from the loaded map_tiles data using direct x, y coordinates.
	Assumes map_tiles is structured as map_tiles[y_coord][x_coord].
	"""
	if map_tiles.is_empty():
		printerr("GameDataManager (get_settlement_name_from_coords): Map data not loaded or empty.")
		return "N/A (Map Data Missing)"

	if target_y >= 0 and target_y < map_tiles.size():
		var row_array: Array = map_tiles[target_y]
		if target_x >= 0 and target_x < row_array.size():
			var tile_data: Dictionary = row_array[target_x]
			var settlements_array: Array = tile_data.get("settlements", [])
			if not settlements_array.is_empty():
				var first_settlement: Dictionary = settlements_array[0]
				if first_settlement.has("name"):
					return first_settlement.get("name")
				else:
					printerr("GameDataManager: Settlement at (", target_x, ",", target_y, ") has no 'name' key.")
					return "N/A (Settlement Name Missing)"
			else:
				return "N/A (No Settlements at Coords)"
		else:
			return "N/A (X Out of Bounds)"
	else:
		return "N/A (Y Out of Bounds)"

func update_user_money(amount_delta: float):
	"""
	Updates the user's money by a given delta and emits the user_data_updated signal.
	This should be the single point of entry for all client-side money changes.
	"""
	if not current_user_data.has("money"):
		current_user_data["money"] = 0.0
	current_user_data["money"] += amount_delta
	# ...existing code...
	user_data_updated.emit(current_user_data)

func update_single_convoy(raw_updated_convoy: Dictionary) -> void:
	if not raw_updated_convoy.has("convoy_id"):
		printerr("GameDataManager: Tried to update convoy but no convoy_id present.")
		return

	# CRITICAL: Augment the raw convoy data from the API before updating the list.
	# This ensures it has all the same client-side fields as the other convoys.
	var augmented_convoy = augment_single_convoy(raw_updated_convoy)

	var updated_id = str(augmented_convoy["convoy_id"])
	var found = false
	for i in range(all_convoy_data.size()):
		var convoy = all_convoy_data[i]
		if convoy.has("convoy_id") and str(convoy["convoy_id"]) == updated_id:
			all_convoy_data[i] = augmented_convoy
			found = true
			break
	if not found:
		all_convoy_data.append(augmented_convoy)
	convoy_data_updated.emit(all_convoy_data)

	# Opportunistically sync global user money from convoy (if present) so header updates immediately
	_maybe_sync_user_money_from_convoy(augmented_convoy)

func _maybe_sync_user_money_from_convoy(convoy_dict: Dictionary) -> void:
	# Some backend responses (e.g., resource / cargo transactions) may include an up-to-date 'money' field.
	# If so, mirror it into current_user_data and emit user_data_updated immediately instead of waiting
	# for the asynchronous user data refetch to complete.
	if not (convoy_dict is Dictionary):
		return
	if not convoy_dict.has("money"):
		return
	var new_money_val = convoy_dict.get("money")
	if not (new_money_val is int or new_money_val is float):
		return
	var new_money_f := float(new_money_val)
	var needs_emit := false
	if not current_user_data.has("money"):
		current_user_data["money"] = new_money_f
		needs_emit = true
	else:
		var old_money_f := 0.0
		var old_raw = current_user_data.get("money")
		if old_raw is int or old_raw is float:
			old_money_f = float(old_raw)
		if abs(old_money_f - new_money_f) > 0.0001:
			current_user_data["money"] = new_money_f
			needs_emit = true
	if needs_emit:
		print("[GameDataManager][MoneySync] Updated user money from convoy data ->", new_money_f)
		user_data_updated.emit(current_user_data)

func update_single_vendor(new_vendor_data: Dictionary) -> void:
	if not new_vendor_data.has("vendor_id"):
		printerr("GameDataManager: Tried to update vendor but no vendor_id present.")
		return

	var updated_id = str(new_vendor_data["vendor_id"])
	var found = false

	for settlement in all_settlement_data:
		if settlement.has("vendors") and settlement.vendors is Array:
			for i in range(settlement.vendors.size()):
				var vendor = settlement.vendors[i]
				if vendor.has("vendor_id") and str(vendor["vendor_id"]) == updated_id:
					settlement.vendors[i] = new_vendor_data
					found = true
					print("GameDataManager: Updated vendor data for ID: %s in settlement: %s" % [updated_id, settlement.get("name", "N/A")])
					break
		if found:
			break

	if found:
		settlement_data_updated.emit(all_settlement_data)
	else:
		printerr("GameDataManager: Vendor ID %s not found in any settlement." % updated_id)

func request_vendor_panel_data(convoy_id: String, vendor_id: String) -> void:
	var vendor_data = get_vendor_by_id(vendor_id)
	var convoy_data = get_convoy_by_id(convoy_id)
	var settlement_data = get_settlement_for_vendor(vendor_id)

	# --- Aggregation logic moved here ---
	var vendor_items = _aggregate_vendor_items(vendor_data)
	var convoy_items = _aggregate_convoy_items(convoy_data, vendor_data)

	var vendor_panel_data = {
		"vendor_data": vendor_data,
		"convoy_data": convoy_data,
		"settlement_data": settlement_data,
		"all_settlement_data": all_settlement_data,
		"user_data": current_user_data,
		"vendor_items": vendor_items,
		"convoy_items": convoy_items
	}
	vendor_panel_data_ready.emit(vendor_panel_data)

# --- Journey Planning ---
func request_route_choices(convoy_id: String, dest_x: int, dest_y: int) -> void:
	print("[GameDataManager] request_route_choices convoy_id=%s dest=(%d,%d)" % [convoy_id, dest_x, dest_y])
	if is_instance_valid(api_calls_node) and api_calls_node.has_method("find_route"):
		_pending_journey_convoy_id = convoy_id
		_pending_journey_destination_data = {"x": dest_x, "y": dest_y, "name": get_settlement_name_from_coords(dest_x, dest_y)}
		route_choices_request_started.emit(convoy_id, _pending_journey_destination_data)
		api_calls_node.find_route(convoy_id, dest_x, dest_y)
	else:
		printerr("GameDataManager: Cannot request route choices; APICalls missing or method not found.")
		route_choices_error.emit(convoy_id, {"x": dest_x, "y": dest_y}, "Routing service unavailable")
		return

func start_convoy_journey(convoy_id: String, journey_id: String) -> void:
	if is_instance_valid(api_calls_node) and api_calls_node.has_method("send_convoy"):
		api_calls_node.send_convoy(convoy_id, journey_id)
	else:
		printerr("GameDataManager: Cannot start journey; APICalls missing send_convoy method.")

func cancel_convoy_journey(convoy_id: String, journey_id: String) -> void:
	if is_instance_valid(api_calls_node) and api_calls_node.has_method("cancel_convoy_journey"):
		api_calls_node.cancel_convoy_journey(convoy_id, journey_id)
	else:
		printerr("GameDataManager: Cannot cancel journey; APICalls missing cancel_convoy_journey method.")

func get_vendor_by_id(vendor_id: String) -> Variant:
	var vendor_data = null
	for settlement in all_settlement_data:
		if settlement.has("vendors"):
			for vendor in settlement.vendors:
				if str(vendor.get("vendor_id", "")) == str(vendor_id):
					vendor_data = vendor
					break
		if vendor_data:
			break
	return vendor_data

func get_settlement_for_vendor(vendor_id: String) -> Variant:
	var settlement_data = null
	for settlement in all_settlement_data:
		if settlement.has("vendors"):
			for vendor in settlement.vendors:
				if str(vendor.get("vendor_id", "")) == str(vendor_id):
					settlement_data = settlement
					break
		if settlement_data:

			break
	return settlement_data

func get_convoy_by_id(convoy_id: String) -> Variant:
	if convoy_id.is_empty():
		return null
	for convoy in all_convoy_data:
		if str(convoy.get("convoy_id")) == convoy_id:
			return convoy
	return null

# Aggregates vendor's inventory into categories
func _aggregate_vendor_items(vendor_data: Dictionary) -> Dictionary:
	var aggregated = {
		"missions": {},
		"resources": {},
		"vehicles": {},
		"other": {}
	}
	if not vendor_data:
		return aggregated

	for item in vendor_data.get("cargo_inventory", []):
		if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
			continue
		var category = "other"
		if item.get("recipient") != null:
			category = "missions"
		elif (item.has("food") and item.get("food", 0) > 0) or (item.has("water") and item.get("water", 0) > 0) or (item.has("fuel") and item.get("fuel", 0) > 0):
			category = "resources"
		_aggregate_item(aggregated[category], item)

	# Add bulk resources
	for res in ["fuel", "water", "food"]:
		var qty = int(vendor_data.get(res, 0) or 0)
		var price = float(vendor_data.get(res + "_price", 0) or 0)
		# We want to show bulk resources whenever qty > 0 even if price == 0 (could be free / placeholder pricing)
		if qty > 0:
			var item = {
				"name": "%s (Bulk)" % res.capitalize(),
				"quantity": qty,
				"is_raw_resource": true
			}
			item[res] = qty # dynamic quantity field (fuel/water/food)
			# Preserve the unit price field so UI pricing helpers can pick it up
			item[res + "_price"] = price
			_aggregate_item(aggregated["resources"], item)
			if VEHICLE_DEBUG_DUMP:
				print("[GameDataManager][DEBUG][VendorBulk] Added %s qty=%d price=%f" % [res, qty, price])

	# Vehicles
	for vehicle in vendor_data.get("vehicle_inventory", []):
		_aggregate_item(aggregated["vehicles"], vehicle)

	return aggregated

# Aggregates convoy's inventory into categories
func _aggregate_convoy_items(convoy_data: Dictionary, vendor_data: Dictionary) -> Dictionary:
	var aggregated = {
		"missions": {},
		"resources": {},
		"parts": {},
		"other": {}
	}
	if not convoy_data:
		return aggregated

	var found_any_cargo = false
	if convoy_data.has("vehicle_details_list"):
		for vehicle in convoy_data.vehicle_details_list:
			var vehicle_name = vehicle.get("name", "Unknown Vehicle")
			for item in vehicle.get("cargo", []):
				found_any_cargo = true
				if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
					continue
				var category = "other"
				if item.get("recipient") != null or item.get("delivery_reward") != null:
					category = "missions"
				elif (item.has("food") and item.get("food", 0) > 0) or (item.has("water") and item.get("water", 0) > 0) or (item.has("fuel") and item.get("fuel", 0) > 0):
					category = "resources"
				_aggregate_item(aggregated[category], item, vehicle_name)
			for item in vehicle.get("parts", []):
				if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
					continue
				_aggregate_item(aggregated["parts"], item, vehicle_name)

	# Fallback: If no cargo found in vehicles, use cargo_inventory
	if not found_any_cargo and convoy_data.has("cargo_inventory"):
		for item in convoy_data.cargo_inventory:
			var category = "other"
			if item.get("recipient") != null or item.get("delivery_reward") != null:
				category = "missions"
			elif (item.has("food") and item.get("food", 0) > 0) or (item.has("water") and item.get("water", 0) > 0) or (item.has("fuel") and item.get("fuel", 0) > 0):
				category = "resources"
			_aggregate_item(aggregated[category], item, "Convoy")

	# Add bulk resources
	for res in ["fuel", "water", "food"]:
		var qty = int(convoy_data.get(res, 0) or 0)
		# Only allow selling this resource if vendor advertises a price (non-null and numeric). 0 is allowed (free) but null/absent blocks.
		var raw_price_val = null
		if vendor_data and vendor_data.has(res + "_price"):
			raw_price_val = vendor_data.get(res + "_price")
		var has_price := raw_price_val is int or raw_price_val is float
		var price: float = 0.0
		if has_price:
			price = float(raw_price_val)
		if qty > 0 and has_price:
			var item = {
				"name": "%s (Bulk)" % res.capitalize(),
				"quantity": qty,
				"is_raw_resource": true
			}
			item[res] = qty
			item[res + "_price"] = price
			_aggregate_item(aggregated["resources"], item)
		elif qty > 0 and not has_price and VEHICLE_DEBUG_DUMP:
			print("[GameDataManager][DEBUG][ConvoyBulkFilter] Skipping %s: qty=%d vendor has no %s_price" % [res, qty, res])
			if VEHICLE_DEBUG_DUMP:
				print("[GameDataManager][DEBUG][ConvoyBulk] Added %s qty=%d price=%f" % [res, qty, price])

	return aggregated

# Helper for aggregation
func _aggregate_item(agg_dict: Dictionary, item: Dictionary, vehicle_name: String = "", mission_vendor_name: String = "") -> void:
	# Use cargo_id as aggregation key if present, else fallback to name
	var agg_key = str(item.get("cargo_id")) if item.has("cargo_id") else item.get("name", "Unknown Item")
	if not agg_dict.has(agg_key):
		agg_dict[agg_key] = {
			"item_data": item,
			"total_quantity": 0,
			"locations": {},
			"mission_vendor_name": mission_vendor_name,
			"total_weight": 0.0,
			"total_volume": 0.0,
			"total_food": 0.0,
			"total_water": 0.0,
			"total_fuel": 0.0
		}
	var item_quantity = int(item.get("quantity", 1.0))
	# For raw bulk resources, prefer the explicit resource amount if larger.
	if item.get("is_raw_resource", false):
		if item.has("fuel") and (item.get("fuel") is int or item.get("fuel") is float):
			item_quantity = max(item_quantity, int(item.get("fuel")))
		if item.has("water") and (item.get("water") is int or item.get("water") is float):
			item_quantity = max(item_quantity, int(item.get("water")))
		if item.has("food") and (item.get("food") is int or item.get("food") is float):
			item_quantity = max(item_quantity, int(item.get("food")))
		# Mirror back to item_data so UI picking uses the larger number
		agg_dict[agg_key].item_data["quantity"] = item_quantity
	agg_dict[agg_key].total_quantity += item_quantity
	agg_dict[agg_key].total_weight += item.get("weight", 0.0)
	agg_dict[agg_key].total_volume += item.get("volume", 0.0)
	if item.get("food") is float or item.get("food") is int: agg_dict[agg_key].total_food += item.get("food")
	if item.get("water") is float or item.get("water") is int: agg_dict[agg_key].total_water += item.get("water")
	if item.get("fuel") is float or item.get("fuel") is int: agg_dict[agg_key].total_fuel += item.get("fuel")
	if vehicle_name != "":
		if not agg_dict[agg_key].locations.has(vehicle_name):
			agg_dict[agg_key].locations[vehicle_name] = 0
		agg_dict[agg_key].locations[vehicle_name] += item_quantity

func buy_item(convoy_id: String, vendor_id: String, item_data: Dictionary, quantity: int) -> void:
	if not is_instance_valid(api_calls_node):
		printerr("GameDataManager: Cannot buy item, APICallsInstance is invalid.")
		return

	# Check cargo first!
	if item_data.has("cargo_id"):
		api_calls_node.buy_cargo(vendor_id, convoy_id, item_data["cargo_id"], quantity)
	elif item_data.has("vehicle_id"):
		api_calls_node.buy_vehicle(vendor_id, convoy_id, item_data["vehicle_id"])
	elif item_data.has("is_raw_resource"):
		if item_data.has("fuel"):
			api_calls_node.buy_resource(vendor_id, convoy_id, "fuel", float(quantity))
		elif item_data.has("water"):
			api_calls_node.buy_resource(vendor_id, convoy_id, "water", float(quantity))
		elif item_data.has("food"):
			api_calls_node.buy_resource(vendor_id, convoy_id, "food", float(quantity))
		else:
			printerr("GameDataManager: Unknown raw resource type in buy_item.")
	else:
		printerr("GameDataManager: Unknown item type for buy_item.")

func sell_item(convoy_id: String, vendor_id: String, item_data: Dictionary, quantity: int) -> void:
	if not is_instance_valid(api_calls_node):
		printerr("GameDataManager: Cannot sell item, APICallsInstance is invalid.")
		return

	# Check cargo first!
	if item_data.has("cargo_id"):
		api_calls_node.sell_cargo(vendor_id, convoy_id, item_data["cargo_id"], quantity)
	elif item_data.has("vehicle_id"):
		api_calls_node.sell_vehicle(vendor_id, convoy_id, item_data["vehicle_id"])
	elif item_data.has("is_raw_resource"):
		# Determine resource type & available amount from current convoy snapshot
		var resource_type := ""
		if item_data.has("fuel") and (item_data.get("fuel") is int or item_data.get("fuel") is float) and int(item_data.get("fuel")) > 0:
			resource_type = "fuel"
		elif item_data.has("water") and (item_data.get("water") is int or item_data.get("water") is float) and int(item_data.get("water")) > 0:
			resource_type = "water"
		elif item_data.has("food") and (item_data.get("food") is int or item_data.get("food") is float) and int(item_data.get("food")) > 0:
			resource_type = "food"
		else:
			printerr("GameDataManager: Unknown raw resource type in sell_item (no positive resource field).")
			return
		var convoy_snapshot = get_convoy_by_id(convoy_id)
		var available := 0.0
		if convoy_snapshot is Dictionary and convoy_snapshot.has(resource_type):
			var av_val = convoy_snapshot.get(resource_type)
			if av_val is int or av_val is float:
				available = float(av_val)
		# Clamp quantity to available (avoid backend 500 due to invalid over-sell)
		if quantity > int(available):
			print("[GameDataManager][SellResource] Clamp requested quantity from", quantity, "to available", int(available), "resource_type=", resource_type, "convoy_id=", convoy_id)
			quantity = int(available)
		if quantity <= 0:
			printerr("[GameDataManager][SellResource] Aborting sell; no available", resource_type, "in convoy.")
			return
		print("[GameDataManager][SellResource] Attempting sell resource_type=", resource_type, "qty=", quantity, "available=", available, "convoy_id=", convoy_id, "vendor_id=", vendor_id)
		api_calls_node.sell_resource(vendor_id, convoy_id, resource_type, float(quantity))
	else:
		printerr("GameDataManager: Unknown item type for sell_item.")

func _on_api_route_choices_received(routes: Array) -> void:
	if _pending_journey_convoy_id.is_empty():
		return
	var convoy_id_local = _pending_journey_convoy_id
	var convoy_data = get_convoy_by_id(convoy_id_local)
	var destination_data = _pending_journey_destination_data
	print("[GameDataManager] _on_api_route_choices_received convoy_id=%s routes=%d" % [convoy_id_local, routes.size()])
	if ROUTE_DEBUG_DUMP:
		for i in range(routes.size()):
			var r = routes[i]
			if not (r is Dictionary):
				continue
			var journey_dict = r.get('journey', {})
			var kwh_keys: Array = []
			if r.has('kwh_expenses') and r.get('kwh_expenses') is Dictionary:
				kwh_keys = r.get('kwh_expenses').keys()
			print('[GameDataManager][DEBUG][RouteChoice] idx=', i, ' keys=', r.keys(), ' kwh_keys=', kwh_keys, ' delta_t=', r.get('delta_t'))
			if journey_dict is Dictionary:
				print('[GameDataManager][DEBUG][RouteChoice][Journey] origin=(', journey_dict.get('origin_x'), ',', journey_dict.get('origin_y'), ') dest=(', journey_dict.get('dest_x'), ',', journey_dict.get('dest_y'), ') len route_x=', (journey_dict.get('route_x', []) as Array).size(), ' progress=', journey_dict.get('progress'))
				_json_snippet(journey_dict, 'route['+str(i)+'].journey')
			if r.has('kwh_expenses'):
				_json_snippet(r.get('kwh_expenses'), 'route['+str(i)+'].kwh_expenses')
	if routes.is_empty():
		print("[GameDataManager] No routes returned; emitting error.")
		route_choices_error.emit(convoy_id_local, destination_data, "No routes available")
		_pending_journey_convoy_id = ""
		_pending_journey_destination_data = {}
		return
	route_info_ready.emit(convoy_data, destination_data, routes)
	_pending_journey_convoy_id = ""
	_pending_journey_destination_data = {}

func _on_api_fetch_error(error_message: String) -> void:
	if not _pending_journey_convoy_id.is_empty():
		print("[GameDataManager] Routing fetch_error for convoy_id=%s: %s" % [_pending_journey_convoy_id, error_message])
		route_choices_error.emit(_pending_journey_convoy_id, _pending_journey_destination_data, error_message)
		_pending_journey_convoy_id = ""
		_pending_journey_destination_data = {}

func _on_convoy_sent_on_journey(updated_convoy_data: Dictionary) -> void:
	print("GameDataManager: Received confirmation that journey has started. Updating local data.")
	update_single_convoy(updated_convoy_data)
	# After updating a convoy, convey updated list via existing convoy_data_updated signal already called inside update_single_convoy.
	# If UI wants specific journey start handling later, reintroduce a dedicated signal.
	# NEW: Force a fresh fetch of this convoy from backend to ensure we have authoritative state
	var cid := str(updated_convoy_data.get("convoy_id", ""))
	if cid != "" and is_instance_valid(api_calls_node) and api_calls_node.has_method("get_convoy_data"):
		print("[GameDataManager] Post-journey send: fetching updated convoy from server convoy_id=", cid)
		api_calls_node.get_convoy_data(cid)

func _on_convoy_journey_canceled(updated_convoy_data: Dictionary) -> void:
	print("GameDataManager: Journey cancel confirmed. Updating convoy data.")
	update_single_convoy(updated_convoy_data)
	journey_canceled.emit(updated_convoy_data)
