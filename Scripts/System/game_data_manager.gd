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
# Mechanics / part compatibility relay
signal part_compatibility_ready(payload: Dictionary) # { vehicle_id, part_id, data }
signal mechanic_vendor_slot_availability(vehicle_id: String, slot_availability: Dictionary)
# Emitted when a convoy is selected or deselected in the UI.
signal convoy_selection_changed(selected_convoy_data: Variant)
signal journey_canceled(convoy_data: Dictionary)

# New lifecycle / aggregation signals
signal initial_data_ready  # Fired once after first map + first convoy data loaded
signal game_data_reset      # Fired when user-auth related data is cleared (logout / expiry)
signal inline_error_handled # Fired when a UI component handles a recoverable error locally


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
var _mech_vendor_cargo_slot: Dictionary = {} # part_id -> slot_name (best-effort until backend fitment confirms)
var _mech_vendor_availability: Dictionary = {} # vehicle_id -> { slot_name: bool }
var _mech_probe_last_candidate_ids: Array = [] # last set of cargo_ids checked
var _mech_probe_last_vehicle_ids: Array = [] # last set of vehicle_ids checked
var _mech_probe_last_coords: Dictionary = {} # {x:int, y:int}
var _mech_active_convoy_id: String = "" # convoy id that opened Mechanics; used to auto re-probe on vendor updates
var _mech_wait_convoy_id: String = "" # convoy id waiting for settlements to load for warm-up
var _cargo_detail_cache: Dictionary = {} # cargo_id -> full cargo Dictionary from /cargo/get
var _cargo_enrichment_pending: Dictionary = {} # cargo_id -> true while request in-flight
var _mech_probe_pending_cargo_ids: Dictionary = {} # cargo_id -> true expected to enrich this probe

# --- Standardized Item Data (typed cargo objects) ---
const ItemsData = preload("res://Scripts/Data/Items.gd")

# --- Periodic Refresh ---
@export var convoy_refresh_interval_seconds: float = 2.5 # How often to poll backend for convoy movement
var _convoy_refresh_timer: Timer = null

# --- Debug Toggles ---
const VEHICLE_DEBUG_DUMP := true # Set true to print raw & augmented convoy + vehicle data on receipt
const ROUTE_DEBUG_DUMP := true # Dump route choice structures when received
const DEBUG_JSON_CHAR_LIMIT := 2500
const MECH_DEBUG_FORCE_SAMPLE := true # Force one sample compat request if no vendor parts found

# --- Heuristics for detecting parts by name/description (fallback when no explicit slot/type) ---
func _looks_like_vehicle_part(item: Dictionary) -> Dictionary:
	var name_l := String(item.get("name", "")).to_lower()
	var desc_l := String(item.get("base_desc", item.get("description", ""))).to_lower()
	var text := name_l + "\n" + desc_l
	# Core part-ish keywords
	var kw_any := [
		"cvt", "transmission", "gearbox", "clutch",
		"differential", "limited slip", "lsd", "welded diff",
		"axle", "double-wishbone", "wishbone", "suspension", "shock", "spring", "strut",
		"fuel cell", "fuel tank", "battery", "kwh",
		"engine", "motor",
		"radiator", "cooler", "intercooler",
		"turbo", "supercharger",
		"brake", "rotor", "caliper", "drum",
		"wheel", "tire", "tyre", "spare",
		"body", "chassis", "frame", "bed"
	]
	var likely := false
	for kw in kw_any:
		if text.find(kw) != -1:
			likely = true
			break

	# Try weak slot guess mapping for faster UI grouping; backend will confirm via fitment.slot.
	var slot_guess := ""
	if likely:
		if text.find("cvt") != -1 or text.find("transmission") != -1 or text.find("gearbox") != -1 or text.find("clutch") != -1:
			slot_guess = "transmission"
		elif text.find("differential") != -1 or text.find("lsd") != -1 or text.find("welded diff") != -1:
			slot_guess = "differential"
		elif text.find("double-wishbone") != -1 or text.find("suspension") != -1 or text.find("shock") != -1 or text.find("spring") != -1 or text.find("strut") != -1 or text.find("axle") != -1:
			slot_guess = "suspension"
		elif text.find("fuel cell") != -1 or text.find("fuel tank") != -1:
			slot_guess = "fuel_tank"
		elif text.find("battery") != -1 or text.find("kwh") != -1:
			slot_guess = "battery"
		elif text.find("engine") != -1 or text.find("motor") != -1:
			slot_guess = "engine"
		elif text.find("radiator") != -1 or text.find("cooler") != -1:
			slot_guess = "cooling"
		elif text.find("turbo") != -1 or text.find("supercharger") != -1:
			slot_guess = "forced_induction"
		elif text.find("brake") != -1 or text.find("rotor") != -1 or text.find("caliper") != -1 or text.find("drum") != -1:
			slot_guess = "brakes"
		elif text.find("wheel") != -1 or text.find("tire") != -1 or text.find("tyre") != -1 or text.find("spare") != -1:
			slot_guess = "spare_tire" if text.find("spare") != -1 else "wheel"
		elif text.find("body") != -1 or text.find("chassis") != -1 or text.find("frame") != -1 or text.find("bed") != -1:
			slot_guess = "body"
	return {"likely": likely, "slot_guess": slot_guess}

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
		if api_calls_node.has_signal('user_metadata_updated') and not api_calls_node.user_metadata_updated.is_connected(_on_user_metadata_updated):
			api_calls_node.user_metadata_updated.connect(_on_user_metadata_updated)
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
		# Mechanics: vehicle part attach returns updated vehicle; handle and refresh convoy
		if api_calls_node.has_signal('vehicle_part_attached') and not api_calls_node.vehicle_part_attached.is_connected(_on_vehicle_part_attached):
			api_calls_node.vehicle_part_attached.connect(_on_vehicle_part_attached)
		if api_calls_node.has_signal('vehicle_part_added') and not api_calls_node.vehicle_part_added.is_connected(_on_vehicle_part_added):
			api_calls_node.vehicle_part_added.connect(_on_vehicle_part_added)
		# Mechanics: vehicle part detach returns updated vehicle; handle and refresh convoy
		if api_calls_node.has_signal('vehicle_part_detached') and not api_calls_node.vehicle_part_detached.is_connected(_on_vehicle_part_detached):
			api_calls_node.vehicle_part_detached.connect(_on_vehicle_part_detached)
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
		# Mechanics: part compatibility
		if api_calls_node.has_signal('part_compatibility_checked') and not api_calls_node.part_compatibility_checked.is_connected(_on_part_compatibility_checked):
			api_calls_node.part_compatibility_checked.connect(_on_part_compatibility_checked)
		# Mechanics: cargo enrichment
		if api_calls_node.has_signal('cargo_data_received') and not api_calls_node.cargo_data_received.is_connected(_on_cargo_data_received):
			api_calls_node.cargo_data_received.connect(_on_cargo_data_received)
		# Onboarding: listen for newly created convoy
		if api_calls_node.has_signal('convoy_created') and not api_calls_node.convoy_created.is_connected(_on_convoy_created):
			api_calls_node.convoy_created.connect(_on_convoy_created)
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
		# After login, if user has no convoys yet, UI will prompt creation.
		api_calls_node.set_user_id(user_id)
		request_user_data_refresh()
		if api_calls_node.has_method('get_user_convoys'):
			api_calls_node.get_user_convoys(user_id)
		# Trigger map load now that auth began (parallel path) if not already loaded
		if not _map_loaded and not _map_request_in_flight:
			_map_request_in_flight = true
			request_map_data()

	# Start periodic convoy refresh after auth/user bootstrap
	_start_convoy_refresh_timer()

func _on_auth_expired() -> void:
	print('[GameDataManager] Auth expired. Resetting user-related state.')
	reset_user_state()
	_stop_convoy_refresh_timer()

# --- Public helper: expose current convoy list ---
func get_all_convoy_data() -> Array:
	return all_convoy_data

# --- Onboarding: create a new convoy by name ---
func create_new_convoy(convoy_name: String) -> void:
	if not is_instance_valid(api_calls_node):
		printerr("GameDataManager.create_new_convoy: APICalls not available")
		return
	if not api_calls_node.has_method('create_convoy'):
		printerr("GameDataManager.create_new_convoy: APICalls.create_convoy missing")
		return
	print('[GameDataManager] create_new_convoy name="', convoy_name, '"')
	api_calls_node.create_convoy(convoy_name)

func _on_convoy_created(result: Dictionary) -> void:
	# Expect result to contain new convoy or at least success indicator
	# Refresh user + convoy data; server will return the new convoy next fetch
	print('[GameDataManager] convoy_created received: keys=', (result.keys() if typeof(result)==TYPE_DICTIONARY else []))
	# Force-refresh user data (bypass one-time guard) and convoys
	if is_instance_valid(api_calls_node):
		var uid := String(api_calls_node.current_user_id)
		if uid != "" and api_calls_node.has_method('refresh_user_data'):
			api_calls_node.refresh_user_data(uid)
	# Also refresh convoy list for the user right away
	request_convoy_data_refresh()
	# If API also returns a convoy_id, try to select it
	var new_id := String(result.get('convoy_id', ''))
	if new_id != "":
		select_convoy_by_id(new_id, false)

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
	# Also ensure background timers are stopped when user state is cleared
	_stop_convoy_refresh_timer()

func _start_convoy_refresh_timer() -> void:
	# Create and start a repeating timer that refreshes convoy movement periodically
	if _convoy_refresh_timer != null and is_instance_valid(_convoy_refresh_timer):
		return # already running
	_convoy_refresh_timer = Timer.new()
	_convoy_refresh_timer.name = "ConvoyRefreshTimer"
	# Ensure timer fires even if some parts of the tree pause (e.g., opening menus)
	_convoy_refresh_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_convoy_refresh_timer.wait_time = max(0.5, float(convoy_refresh_interval_seconds))
	_convoy_refresh_timer.one_shot = false
	add_child(_convoy_refresh_timer)
	_convoy_refresh_timer.timeout.connect(_on_convoy_refresh_tick)
	_convoy_refresh_timer.start()
	print("[GameDataManager] Started convoy refresh timer at ", _convoy_refresh_timer.wait_time, "s")

func _stop_convoy_refresh_timer() -> void:
	if _convoy_refresh_timer != null and is_instance_valid(_convoy_refresh_timer):
		_convoy_refresh_timer.stop()
		_convoy_refresh_timer.queue_free()
		_convoy_refresh_timer = null
		print("[GameDataManager] Stopped convoy refresh timer")

func _any_convoy_in_transit() -> bool:
	for c in all_convoy_data:
		if not (c is Dictionary):
			continue
		var j = c.get("journey")
		if j is Dictionary:
			var rx: Array = j.get("route_x", [])
			var ry: Array = j.get("route_y", [])
			if rx is Array and ry is Array and rx.size() >= 2 and ry.size() == rx.size():
				return true
	return false

func _on_convoy_refresh_tick() -> void:
	# Only refresh if authenticated and there's at least one convoy in transit
	if not is_instance_valid(api_calls_node):
		return
	var uid := String(api_calls_node.current_user_id)
	if uid == "":
		return
	if _any_convoy_in_transit():
		request_convoy_data_refresh()

func _on_user_metadata_updated(updated_user_data: Dictionary):
	if updated_user_data.is_empty():
		printerr("GameDataManager: Received empty data on user metadata update.")
		return
	
	# The full user object is often returned, so we can just use the existing handler.
	# This ensures convoy lists and other user data are also refreshed from the same response.
	_on_user_data_received_from_api(updated_user_data)
	print("[GameDataManager] User metadata updated and local cache synced.")

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

	# --- Convert each vehicle's cargo to typed data objects (merge 'cargo' + 'cargo_inventory') ---
	if augmented_item.has("vehicle_details_list") and augmented_item["vehicle_details_list"] is Array:
		for v in augmented_item["vehicle_details_list"]:
			if v is Dictionary:
				var raw_cargo: Array = []
				# Primary in existing UI: 'cargo'
				if v.has("cargo") and v.cargo is Array:
					raw_cargo += v.cargo
				# Secondary / fallback: 'cargo_inventory'
				if v.has("cargo_inventory") and v.cargo_inventory is Array:
					raw_cargo += v.cargo_inventory
				# Append synthetic bulk resources (vehicle-scoped, if any)
				for res_key in ["fuel","water","food"]:
					if v.has(res_key) and (v.get(res_key) is int or v.get(res_key) is float) and float(v.get(res_key)) > 0.0:
						var qty = int(v.get(res_key))
						raw_cargo.append({
							"cargo_id": "bulk_" + res_key + "_" + String(v.get("vehicle_id", v.get("id", ""))),
							"name": res_key.capitalize(),
							"quantity": qty,
							"resource_type": res_key,
							"is_raw_resource": true
						})
				# Build typed list; store under new key 'cargo_items_typed'
				v["cargo_items_typed"] = ItemsData.classify_many(raw_cargo)

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

# --- Mechanics / Part Compatibility ---
func request_part_compatibility(vehicle_id: String, part_cargo_id: String) -> void:
	if not is_instance_valid(api_calls_node):
		printerr("[PartCompatGDM] Cannot request compatibility; APICalls invalid.")
		return
	if vehicle_id.is_empty() or part_cargo_id.is_empty():
		printerr("[PartCompatGDM] Missing vehicle_id or part_cargo_id; vehicle_id=", vehicle_id, " part_cargo_id=", part_cargo_id)
		return
	print("[PartCompatGDM] REQUEST vehicle=", vehicle_id, " part_cargo_id=", part_cargo_id)
	if api_calls_node.has_method("check_vehicle_part_compatibility"):
		api_calls_node.check_vehicle_part_compatibility(vehicle_id, part_cargo_id)
	else:
		printerr("[PartCompatGDM] APICalls missing check_vehicle_part_compatibility")

# Apply mechanic swaps (ordered for a specific vehicle). Each entry should contain to_part with cargo_id or part_id.
func apply_mechanic_swaps(convoy_id: String, vehicle_id: String, ordered_swaps: Array, vendor_id: String = "") -> void:
	if not is_instance_valid(api_calls_node):
		printerr("[GameDataManager][MechanicApply] APICalls missing; cannot apply swaps")
		return
	print("[GameDataManager][MechanicApply] BEGIN convoy=", convoy_id, " vehicle=", vehicle_id, " vendor=", vendor_id, " swaps=", ordered_swaps.size())
	# Remember active convoy for follow-up refreshes
	if convoy_id != "":
		_mech_active_convoy_id = convoy_id
	var applied := 0
	for s in ordered_swaps:
		if not (s is Dictionary):
			continue
		var vid := String(s.get("vehicle_id", ""))
		if vid == "" or (vehicle_id != "" and vid != vehicle_id):
			continue
		var to_part: Dictionary = s.get("to_part", {})
		# Prefer cargo_id for attach and part_id for vendor add; compute both if available
		var cargo_id_str := String(to_part.get("cargo_id", ""))
		var part_id_str := String(to_part.get("part_id", ""))
		# Some vendor payloads may use "id" for the part identifier
		if part_id_str == "":
			part_id_str = String(to_part.get("id", ""))
		# If neither id is present, we cannot proceed
		if cargo_id_str == "" and part_id_str == "":
			printerr("[GameDataManager][MechanicApply] Swap missing cargo/part id; skipping entry")
			continue
		var swap_vendor_id := String(s.get("vendor_id", ""))
		var effective_vendor := swap_vendor_id if swap_vendor_id != "" else vendor_id
		# Determine source and whether this can be self-installed (removable)
		var source := String(s.get("source", ""))
		source = source.to_lower()
		var removable := false
		var rv: Variant = to_part.get("removable", false)
		if rv is bool:
			removable = rv
		elif rv is int:
			removable = int(rv) != 0
		elif rv is String:
			var rvs := String(rv).to_lower()
			removable = (rvs == "true" or rvs == "1" or rvs == "yes")

		var prefer_attach := (source == "inventory" and removable and cargo_id_str != "")

		if prefer_attach and api_calls_node.has_method("attach_vehicle_part"):
			print("[GameDataManager][MechanicApply] ATTACH queue reason=inventory+removable vehicle=", vid, " cargo=", cargo_id_str)
			api_calls_node.attach_vehicle_part(vid, cargo_id_str)
			applied += 1
		elif effective_vendor != "" and api_calls_node.has_method("add_vehicle_part"):
			# New API requires part_cargo_id (vendor cargo id) — do not pass part_id here
			if cargo_id_str == "":
				printerr("[GameDataManager][MechanicApply] Vendor ADD requires cargo_id (part_cargo_id) but it's missing; skipping entry for vehicle=", vid)
				continue
			print("[GameDataManager][MechanicApply] ADD via vendor queue vendor=", effective_vendor, " convoy=", convoy_id, " vehicle=", vid, " cargo=", cargo_id_str, " reason=", ("vendor-source" if source == "vendor" else ("non-removable or missing cargo")))
			api_calls_node.add_vehicle_part(effective_vendor, convoy_id, vid, cargo_id_str)
			applied += 1
		elif api_calls_node.has_method("attach_vehicle_part") and cargo_id_str != "":
			print("[GameDataManager][MechanicApply] ATTACH fallback (no vendor or add unavailable) vehicle=", vid, " cargo=", cargo_id_str)
			api_calls_node.attach_vehicle_part(vid, cargo_id_str)
			applied += 1
		else:
			printerr("[GameDataManager][MechanicApply] No attach/add method available or missing identifiers for vehicle=", vid)
	print("[GameDataManager][MechanicApply] QUEUED ", applied, " mechanic request(s)")

func _on_vehicle_part_attached(result: Dictionary) -> void:
	# Backend returns updated vehicle dictionary. Update the convoy immediately and emit, then optionally refresh.
	print("[GameDataManager][MechanicApply] vehicle_part_attached result keys=", result.keys())
	var vid := String(result.get("vehicle_id", ""))
	var target_convoy_id := _mech_active_convoy_id
	var updated_locally := false
	# Try to find convoy by vehicle_id if needed
	if target_convoy_id == "":
		if vid != "":
			for c in all_convoy_data:
				if not (c is Dictionary):
					continue
				var vlist0: Array = c.get("vehicle_details_list", [])
				for v0 in vlist0:
					if String(v0.get("vehicle_id", "")) == vid:
						target_convoy_id = String(c.get("convoy_id", ""))
						break
				if target_convoy_id != "":
					break
	# Patch convoy in-place if we can locate it and emit update immediately
	if vid != "" and target_convoy_id != "":
		for i in range(all_convoy_data.size()):
			var conv: Dictionary = all_convoy_data[i]
			if not (conv is Dictionary):
				continue
			if String(conv.get("convoy_id", "")) != target_convoy_id:
				continue
			var vlist: Array = conv.get("vehicle_details_list", [])
			var replaced := false
			for j in range(vlist.size()):
				var vdict: Dictionary = vlist[j]
				if String(vdict.get("vehicle_id", "")) == vid:
					vlist[j] = result # use server-returned vehicle immediately
					replaced = true
					break
			if replaced:
				conv["vehicle_details_list"] = vlist
				all_convoy_data[i] = conv
				convoy_data_updated.emit(all_convoy_data)
				updated_locally = true
				print("[GameDataManager][MechanicApply] Updated convoy ", target_convoy_id, " with returned vehicle ", vid, " and emitted update.")
				break
	# Optionally also refresh from server to ensure authoritative state
	if target_convoy_id != "" and is_instance_valid(api_calls_node) and api_calls_node.has_method("get_convoy_data"):
		if not updated_locally:
			print("[GameDataManager][MechanicApply] Refreshing convoy after attach convoy_id=", target_convoy_id)
		api_calls_node.get_convoy_data(target_convoy_id)
	elif not updated_locally:
		printerr("[GameDataManager][MechanicApply] Could not resolve convoy to update/refresh after attach.")

func _on_vehicle_part_added(result: Dictionary) -> void:
	# Backend returns updated convoy dict (convoy_after). Update state and user money immediately.
	if not (result is Dictionary):
		return
	print("[GameDataManager][MechanicApply] vehicle_part_added keys=", result.keys())
	var updated_convoy: Dictionary = {}
	# Accept multiple common shapes: top-level convoy, or nested under convoy_after / convoy
	if result.has("convoy_id"):
		updated_convoy = result
	elif result.has("convoy_after") and (result.get("convoy_after") is Dictionary):
		updated_convoy = result.get("convoy_after")
	elif result.has("convoy") and (result.get("convoy") is Dictionary):
		updated_convoy = result.get("convoy")
	else:
		# Best-effort: scan for any nested dictionary with a convoy_id
		for v in result.values():
			if v is Dictionary and v.has("convoy_id"):
				updated_convoy = v
				break
	if not updated_convoy.is_empty() and updated_convoy.has("convoy_id"):
		# Log money delta if available
		var prev_money := 0.0
		if current_user_data.has("money"):
			var pm = current_user_data.get("money")
			if pm is int or pm is float:
				prev_money = float(pm)
		update_single_convoy(updated_convoy)
		_maybe_sync_user_money_from_convoy(updated_convoy)
		if updated_convoy.has("money") and (updated_convoy.get("money") is int or updated_convoy.get("money") is float):
			var new_money := float(updated_convoy.get("money"))
			var delta := new_money - prev_money
			print("[GameDataManager][MoneySync] Convoy money now=", new_money, " (delta=", String.num(delta, 2), ")")
		# Optional: backend may include a top-level user_after with authoritative money
		if result.has("user_after") and (result.get("user_after") is Dictionary):
			var ua: Dictionary = result.get("user_after")
			if ua.has("money") and (ua.get("money") is int or ua.get("money") is float):
				var ua_money := float(ua.get("money"))
				var need_emit := false
				if not current_user_data.has("money") or abs(float(current_user_data.get("money", 0.0)) - ua_money) > 0.0001:
					current_user_data["money"] = ua_money
					need_emit = true
				if need_emit:
					print("[GameDataManager][MoneySync] Synced from user_after money=", ua_money)
					user_data_updated.emit(current_user_data)
	else:
		printerr("[GameDataManager][MechanicApply] vehicle_part_added response missing convoy_after/convoy with convoy_id; cannot update list.")

# Public API: request detach of a removable installed part; backend returns updated vehicle
func detach_vehicle_part(convoy_id: String, vehicle_id: String, part_id: String) -> void:
	if not is_instance_valid(api_calls_node):
		printerr("[GameDataManager][Detach] APICalls missing; cannot detach part")
		return
	# Track active convoy for refresh logic, similar to attach
	if convoy_id != "":
		_mech_active_convoy_id = convoy_id
	print("[GameDataManager][Detach] Request detach vehicle=", vehicle_id, " part=", part_id)
	if api_calls_node.has_method("detach_vehicle_part"):
		api_calls_node.detach_vehicle_part(vehicle_id, part_id)
	else:
		printerr("[GameDataManager][Detach] APICalls missing detach_vehicle_part method")

func _on_vehicle_part_detached(result: Dictionary) -> void:
	# Backend returns updated vehicle dictionary. Update convoy immediately and optionally refresh.
	if not (result is Dictionary):
		return
	print("[GameDataManager][Detach] vehicle_part_detached keys=", result.keys())
	var vid := String(result.get("vehicle_id", ""))
	var target_convoy_id := _mech_active_convoy_id
	var updated_locally := false
	if target_convoy_id == "" and vid != "":
		for c in all_convoy_data:
			if not (c is Dictionary):
				continue
			var vlist0: Array = c.get("vehicle_details_list", [])
			for v0 in vlist0:
				if String(v0.get("vehicle_id", "")) == vid:
					target_convoy_id = String(c.get("convoy_id", ""))
					break
			if target_convoy_id != "":
				break
	if vid != "" and target_convoy_id != "":
		for i in range(all_convoy_data.size()):
			var conv: Dictionary = all_convoy_data[i]
			if not (conv is Dictionary):
				continue
			if String(conv.get("convoy_id", "")) != target_convoy_id:
				continue
			var vlist: Array = conv.get("vehicle_details_list", [])
			var replaced := false
			for j in range(vlist.size()):
				var vdict: Dictionary = vlist[j]
				if String(vdict.get("vehicle_id", "")) == vid:
					vlist[j] = result
					replaced = true
					break
			if replaced:
				conv["vehicle_details_list"] = vlist
				all_convoy_data[i] = conv
				convoy_data_updated.emit(all_convoy_data)
				updated_locally = true
				print("[GameDataManager][Detach] Updated convoy ", target_convoy_id, " with returned vehicle ", vid, " and emitted update.")
				break
	# Optionally refresh authoritative state
	if target_convoy_id != "" and is_instance_valid(api_calls_node) and api_calls_node.has_method("get_convoy_data"):
		if not updated_locally:
			print("[GameDataManager][Detach] Refreshing convoy after detach convoy_id=", target_convoy_id)
		api_calls_node.get_convoy_data(target_convoy_id)
	elif not updated_locally:
		printerr("[GameDataManager][Detach] Could not resolve convoy to update/refresh after detach.")

# Public: return enriched cargo (full object from /cargo/get) if available; empty dict otherwise
func get_enriched_cargo(cargo_id: String) -> Dictionary:
	if cargo_id == "":
		return {}
	if _cargo_detail_cache.has(cargo_id):
		var d: Variant = _cargo_detail_cache[cargo_id]
		return d if d is Dictionary else {}
	return {}

# Public: ensure that a cargo_id is queued for enrichment if not already cached
func ensure_cargo_details(cargo_id: String) -> void:
	_ensure_cargo_enrichment(cargo_id)

# Ensure we have full cargo data; if not cached or already pending, request /cargo/get
func _ensure_cargo_enrichment(cargo_id: String) -> void:
	if cargo_id == "":
		return
	if _cargo_detail_cache.has(cargo_id):
		return
	if _cargo_enrichment_pending.has(cargo_id):
		return
	if not is_instance_valid(api_calls_node):
		return
	if api_calls_node.has_method("get_cargo"):
		print("[PartCompatGDM] ENRICH cargo/get dispatch cargo_id=", cargo_id)
		_cargo_enrichment_pending[cargo_id] = true
		api_calls_node.get_cargo(cargo_id)
	else:
		printerr("[PartCompatGDM] APICalls missing get_cargo; cannot enrich cargo ", cargo_id)

# After receiving full cargo details, cache, infer slot, and dispatch compat checks across probed vehicles
func _on_cargo_data_received(cargo: Dictionary) -> void:
	if not (cargo is Dictionary):
		return
	var cid: String = str(cargo.get("cargo_id", cargo.get("id", "")))
	if cid == "":
		return
	_cargo_detail_cache[cid] = cargo
	if _cargo_enrichment_pending.has(cid):
		_cargo_enrichment_pending.erase(cid)
	var slot_name := ""
	if cargo.has("slot") and cargo.get("slot") != null and String(cargo.get("slot")).length() > 0:
		slot_name = String(cargo.get("slot"))
	elif cargo.has("parts") and (cargo.get("parts") is Array) and not ((cargo.get("parts") as Array).is_empty()):
		var p0: Dictionary = (cargo.get("parts") as Array)[0]
		if p0 is Dictionary and p0.has("slot"):
			slot_name = String(p0.get("slot", ""))
	if slot_name != "":
		_mech_vendor_cargo_slot[cid] = slot_name
		print("[PartCompatGDM] ENRICH cargo_id=", cid, " slot=", slot_name)
	# If this cargo was observed during the current probe, dispatch compat only if it is a vehicle part
	if _mech_probe_last_vehicle_ids.size() > 0 and _mech_probe_pending_cargo_ids.has(cid):
		var is_vehicle_part := false
		if slot_name != "":
			is_vehicle_part = true
		elif cargo.has("parts") and (cargo.get("parts") is Array) and not ((cargo.get("parts") as Array).is_empty()):
			is_vehicle_part = true
		if is_vehicle_part:
			_dispatch_compat_for_cargo(cid)
		else:
			print("[PartCompatGDM] ENRICH cargo_id=", cid, " not a vehicle part; skipping compat dispatch")
		_mech_probe_pending_cargo_ids.erase(cid)

func _dispatch_compat_for_cargo(cargo_id: String) -> void:
	if cargo_id == "":
		return
	for veh_id in _mech_probe_last_vehicle_ids:
		request_part_compatibility(String(veh_id), cargo_id)
	# Track in snapshot
	if not (_mech_probe_last_candidate_ids.has(cargo_id)):
		_mech_probe_last_candidate_ids.append(cargo_id)

func _on_part_compatibility_checked(payload: Dictionary) -> void:
	# Relay to UI; include a JSON snippet for quick filtering
	_json_snippet(payload, "PartCompatGDM.payload")
	part_compatibility_ready.emit(payload)
	# Update mechanic vendor availability cache and emit per-vehicle slot availability when compatible
	var v_id: String = str(payload.get("vehicle_id", ""))
	var cid: String = str(payload.get("part_cargo_id", ""))
	if v_id == "" or cid == "":
		return
	var data: Dictionary = payload.get("data", {}) if payload.get("data") is Dictionary else {}
	var is_compat := false
	if data.has("compatible"):
		is_compat = bool(data.get("compatible"))
	elif data.has("fitment") and data.get("fitment") is Dictionary and data.fitment.has("compatible"):
		is_compat = bool(data.fitment.get("compatible"))
	if not is_compat:
		return
	var slot_name: String = ""
	if _mech_vendor_cargo_slot.has(cid):
		slot_name = String(_mech_vendor_cargo_slot[cid])
	else:
		# Try to infer from backend payload (fitment.slot)
		if data.has("fitment") and data.fitment is Dictionary and data.fitment.has("slot"):
			slot_name = str(data.fitment.get("slot", ""))
	if slot_name == "":
		return
	if not _mech_vendor_availability.has(v_id):
		_mech_vendor_availability[v_id] = {}
	_mech_vendor_availability[v_id][slot_name] = true
	mechanic_vendor_slot_availability.emit(v_id, _mech_vendor_availability[v_id])

# Mechanics vendor availability probe: cross-reference vendors in settlement vs all convoy vehicles
func probe_mechanic_vendor_availability_for_convoy(convoy: Dictionary) -> void:
	if convoy.is_empty():
		return
	var sx := int(roundf(float(convoy.get("x", -999999))))
	var sy := int(roundf(float(convoy.get("y", -999999))))
	print("[PartCompatGDM] PROBE start convoy_id=", str(convoy.get("convoy_id", "")), " at (", sx, ",", sy, ")")
	# Reset snapshot for this run
	_mech_probe_last_candidate_ids.clear()
	_mech_probe_last_vehicle_ids.clear()
	_mech_probe_last_coords = {"x": sx, "y": sy}
	_mech_probe_pending_cargo_ids.clear()
	var vehicles: Array = convoy.get("vehicle_details_list", []) if convoy.has("vehicle_details_list") else convoy.get("vehicles", [])
	if vehicles.is_empty():
		print("[PartCompatGDM] PROBE: convoy has no vehicles; aborting")
		return
	# Find settlement by coordinates
	var settlement_match: Dictionary = {}
	for s in all_settlement_data:
		if not (s is Dictionary):
			continue
		if int(s.get("x", 123456)) == sx and int(s.get("y", 123456)) == sy:
			settlement_match = s
			break
	if settlement_match.is_empty():
		if all_settlement_data.is_empty():
			print("[PartCompatGDM] PROBE: all_settlement_data is empty; map/settlements not yet loaded")
		else:
			print("[PartCompatGDM] PROBE: no settlement matched at (", sx, ",", sy, ")")
		return
	# Collect vendor candidates by slot and map cargo_id -> slot; also collect slotless part candidates
	var vendor_parts_by_slot: Dictionary = {}
	var any_candidate_ids: Array = []
	var sample_part_cargo_id: String = ""
	_mech_vendor_cargo_slot.clear()
	var vendors: Array = settlement_match.get("vendors", [])
	if vendors.is_empty():
		print("[PartCompatGDM] PROBE: settlement has no vendors at (", sx, ",", sy, ")")
	else:
		print("[PartCompatGDM] PROBE: vendors at settlement count=", vendors.size())
	for vendor in vendors:
		if not (vendor is Dictionary):
			continue
		var cargo_inv: Array = vendor.get("cargo_inventory", [])
		if cargo_inv.is_empty():
			# Log basic vendor identity and keys to aid debugging
			var vk = vendor.keys()
			var vid_log := ""
			if vendor.has("vendor_id"): vid_log = str(vendor.get("vendor_id"))
			print("[PartCompatGDM] PROBE: vendor has empty cargo; vendor_id=", vid_log, " keys=", vk)
		# If inventory is missing/empty, trigger a refresh for this vendor using best-effort id key detection
		if (cargo_inv.is_empty() or cargo_inv.size() == 0) and is_instance_valid(api_calls_node):
			var vid := ""
			var id_keys := ["vendor_id", "id", "vendorId", "vendorID", "_id"]
			for k in id_keys:
				if vendor.has(k):
					vid = str(vendor.get(k, ""))
					if vid != "":
						break
			if vid != "":
				print("[PartCompatGDM] PROBE: refreshing vendor inventory vendor_id=", vid)
				request_vendor_data_refresh(vid)
		else:
			print("[PartCompatGDM] PROBE: vendor cargo count=", cargo_inv.size())
		for item in cargo_inv:
			if not (item is Dictionary):
				continue
			if item.get("intrinsic_part_id") != null:
				continue
			var _price_f = 0.0 # unused here
			# Prefer cargo_id for compatibility API
			var cid_any: String = str(item.get("cargo_id", ""))
			if cid_any == "":
				cid_any = str(item.get("part_id", ""))
			# Heuristic: detect likely parts even without explicit slot
			var is_likely_part := false
			if item.has("is_part") and item.get("is_part"):
				is_likely_part = true
			var type_s := String(item.get("type", "")).to_lower()
			var itype_s := String(item.get("item_type", "")).to_lower()
			if type_s == "part" or itype_s == "part":
				is_likely_part = true
			var stat_keys := ["top_speed_add", "efficiency_add", "offroad_capability_add", "cargo_capacity_add", "weight_capacity_add", "fuel_capacity", "kwh_capacity"]
			for sk in stat_keys:
				if item.has(sk) and item[sk] != null:
					is_likely_part = true
					break
			# Name/description-based fallback using sample data patterns (e.g., CVT Kit, Differentials, Fuel Cell, Box Truck Body)
			if not is_likely_part:
				var name_heur = _looks_like_vehicle_part(item)
				if name_heur.get("likely", false):
					is_likely_part = true
					# If we got a slot guess, record it for grouping; backend fitment will confirm/override
					var s_guess := String(name_heur.get("slot_guess", ""))
					if s_guess != "" and cid_any != "":
						if not vendor_parts_by_slot.has(s_guess):
							vendor_parts_by_slot[s_guess] = []
						# Shallow copy to avoid mutating original vendor cargo
						var guessed_item = item.duplicate(true)
						guessed_item["slot"] = s_guess
						vendor_parts_by_slot[s_guess].append(guessed_item)
						_mech_vendor_cargo_slot[cid_any] = s_guess
						if sample_part_cargo_id == "":
							sample_part_cargo_id = cid_any
			# If cargo item contains a parts list, print it for debugging
			if item.has("parts") and item.get("parts") is Array:
				var parts_arr: Array = item.get("parts")
				var preview := []
				for p in parts_arr:
					if p is Dictionary:
						preview.append({"name": p.get("name", ""), "slot": p.get("slot", ""), "part_id": p.get("part_id", "")})
				print("[PartCompatGDM] PROBE cargo.parts vendor=", str(vendor.get("vendor_id", "")), " cargo_id=", str(item.get("cargo_id", "")), " parts=", preview)
			# Top-level part with slot
			if item.has("slot") and item.get("slot") != null and String(item.get("slot")).length() > 0:
				var s_name = String(item.get("slot"))
				if not vendor_parts_by_slot.has(s_name):
					vendor_parts_by_slot[s_name] = []
				vendor_parts_by_slot[s_name].append(item)
				if cid_any != "":
					_mech_vendor_cargo_slot[cid_any] = s_name
					any_candidate_ids.append(cid_any)
					if sample_part_cargo_id == "":
						sample_part_cargo_id = cid_any
				continue
			# Container with nested parts[]
			if item.has("parts") and item.get("parts") is Array and not (item.get("parts") as Array).is_empty():
				var nested_parts: Array = item.get("parts")
				var first_part: Dictionary = nested_parts[0]
				var slot_val = first_part.get("slot", "")
				var pslot: String = slot_val if typeof(slot_val) == TYPE_STRING else ""
				if pslot != "":
					if not vendor_parts_by_slot.has(pslot):
						vendor_parts_by_slot[pslot] = []
					# Attach container cargo_id to nested part for compat check
					var display_part: Dictionary = first_part.duplicate(true)
					var cont_or_part_id: String = str(item.get("cargo_id", ""))
					if cont_or_part_id == "":
						cont_or_part_id = str(first_part.get("part_id", ""))
					if cont_or_part_id != "":
						display_part["cargo_id"] = cont_or_part_id
						_mech_vendor_cargo_slot[cont_or_part_id] = pslot
						any_candidate_ids.append(cont_or_part_id)
						if sample_part_cargo_id == "":
							sample_part_cargo_id = cont_or_part_id
					vendor_parts_by_slot[pslot].append(display_part)
			# If still no explicit slot/parts, request cargo enrichment and wait; don't add to candidates yet
			elif cid_any != "":
				_mech_probe_pending_cargo_ids[cid_any] = true
				_ensure_cargo_enrichment(cid_any)

		# Fallback: if we still found nothing for this vendor, re-run using aggregator logic (same as VendorTradePanel)
		if (not vendor_parts_by_slot.keys().size() > 0) and any_candidate_ids.is_empty():
			var agg := _aggregate_vendor_items(vendor)
			if agg.has("parts") and (agg["parts"] is Dictionary) and not (agg["parts"] as Dictionary).is_empty():
				var moved := 0
				for pname in agg["parts"].keys():
					var entry = agg["parts"][pname]
					if entry is Dictionary and entry.has("item_data") and (entry.item_data is Dictionary):
						var pd: Dictionary = entry.item_data
						var slot_name := String(pd.get("slot", ""))
						var cid_f := str(pd.get("cargo_id", ""))
						if cid_f == "": cid_f = str(pd.get("part_id", ""))
						if slot_name != "" and cid_f != "":
							if not vendor_parts_by_slot.has(slot_name): vendor_parts_by_slot[slot_name] = []
							vendor_parts_by_slot[slot_name].append(pd)
							_mech_vendor_cargo_slot[cid_f] = slot_name
							any_candidate_ids.append(cid_f)
							if sample_part_cargo_id == "": sample_part_cargo_id = cid_f
							moved += 1
				if moved > 0:
					print("[PartCompatGDM] PROBE fallback aggregator detected ", moved, " part(s) for vendor.")
	# Summarize what we'll check
	if vendor_parts_by_slot.is_empty():
		if not any_candidate_ids.is_empty():
			print("[PartCompatGDM] PROBE: found ", any_candidate_ids.size(), " vendor part candidate id(s) without explicit slots; backend will infer slot. candidates(sample)=", any_candidate_ids.slice(0, min(5, any_candidate_ids.size())))
		else:
			print("[PartCompatGDM] PROBE: no vendor parts found at settlement (", sx, ",", sy, ")")
			# DEBUG: Force a single compatibility request so we can observe API response shape
			if MECH_DEBUG_FORCE_SAMPLE and sample_part_cargo_id != "" and vehicles.size() > 0:
				var first_vehicle: Dictionary = vehicles[0]
				if first_vehicle is Dictionary:
					var vdbg := str(first_vehicle.get("vehicle_id", ""))
					if vdbg != "":
						print("[PartCompatGDM][DEBUG] Forcing sample compatibility check: vehicle=", vdbg, " part_cargo_id=", sample_part_cargo_id, " (no parts found)")
						request_part_compatibility(vdbg, sample_part_cargo_id)
			# If no candidates at all, nothing to do
			if any_candidate_ids.is_empty():
				return
	else:
		var total_parts := 0
		for k in vendor_parts_by_slot.keys():
			total_parts += (vendor_parts_by_slot[k] as Array).size()
		print("[PartCompatGDM] PROBE: found ", total_parts, " parts across ", vendor_parts_by_slot.size(), " slot(s) to check")

	# Build a unique set of all part_cargo_ids to check (only those with known/inferred slots)
	var all_cargo_ids: Dictionary = {}
	for sname in vendor_parts_by_slot.keys():
		for p in (vendor_parts_by_slot[sname] as Array):
			if p is Dictionary:
				var cidk: String = str(p.get("cargo_id", ""))
				if cidk == "":
					cidk = str(p.get("part_id", ""))
				if cidk != "":
					all_cargo_ids[cidk] = true

	# Initialize and dispatch checks per vehicle for all candidate cargo_ids
	for veh in vehicles:
		if not (veh is Dictionary):
			continue
		var veh_id: String = str(veh.get("vehicle_id", ""))
		if veh_id == "":
			continue
		# Initialize/reset availability dict for this vehicle for this probe
		_mech_vendor_availability[veh_id] = {}
		_mech_probe_last_vehicle_ids.append(veh_id)
		for cid_out in all_cargo_ids.keys():
			request_part_compatibility(veh_id, cid_out)
	# Cache candidate ids after dispatch
	_mech_probe_last_candidate_ids = all_cargo_ids.keys()

func get_mechanic_probe_snapshot() -> Dictionary:
	"""Returns the most recent mechanic probe snapshot.
	Fields:
	- vehicle_ids: Array[String]
	- part_cargo_ids: Array[String]
	- cargo_id_to_slot: Dictionary (known or inferred locally during probe; may be empty for slotless until response)
	- coords: {x:int, y:int}
	"""
	return {
		"vehicle_ids": _mech_probe_last_vehicle_ids.duplicate(),
		"part_cargo_ids": _mech_probe_last_candidate_ids.duplicate(),
		"cargo_id_to_slot": _mech_vendor_cargo_slot.duplicate(),
		"coords": _mech_probe_last_coords.duplicate()
	}

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
		# The result of a transaction is an updated convoy object.
		# We update our local cache with it and emit the convoy_data_updated signal.
		update_single_convoy(result)
		# We no longer need to request a full user data refresh, as the transaction
		# result gives us the immediate data we need. This prevents a second, delayed
		# convoy_data_updated signal which was causing race conditions with the tutorial.
		# The user's money is synced opportunistically inside update_single_convoy.
		# request_user_data_refresh()

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

func update_user_tutorial_stage(new_stage: int) -> void:
	if not is_instance_valid(api_calls_node):
		printerr("GameDataManager: Cannot update tutorial stage, APICalls node is invalid.")
		return
	if not api_calls_node.has_method("update_user_metadata"):
		printerr("GameDataManager: APICalls node is missing 'update_user_metadata' method.")
		return

	var user_id: String = api_calls_node.current_user_id
	if user_id.is_empty():
		printerr("GameDataManager: Cannot update tutorial stage, no user_id.")
		return

	# Preserve existing metadata
	var new_metadata := {}
	if current_user_data.has("metadata") and current_user_data.metadata is Dictionary:
		new_metadata = current_user_data.metadata.duplicate(true)
	
	new_metadata["tutorial"] = new_stage
	api_calls_node.update_user_metadata(user_id, new_metadata)

func get_all_settlements_data() -> Array:
	"""Returns the cached list of all settlement data."""
	return all_settlement_data

func get_current_user_data() -> Dictionary:
	"""Returns the cached user data dictionary."""
	return current_user_data

func select_convoy_by_id(convoy_id_to_select: String, _allow_toggle: bool = true) -> void:
	"""
	Central method to change the globally selected convoy by its ID.

	TOGGLE DISABLED: Re-selecting the same convoy ID now does nothing (keeps it selected).
	To explicitly clear selection, pass an empty string "" as the convoy_id.
	The allow_toggle parameter is preserved for backward compatibility but no longer causes deselection.
	"""
	# Explicit deselect request (empty string provided and something is selected)
	if convoy_id_to_select == "":
		if not _selected_convoy_id.is_empty():
			_selected_convoy_id = ""
			convoy_selection_changed.emit(get_selected_convoy()) # Will emit null
		return

	# If the requested ID is already selected, do nothing (toggle behavior removed)
	if _selected_convoy_id == convoy_id_to_select:
		return

	# Change selection and emit update
	_selected_convoy_id = convoy_id_to_select
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
	# --- START TUTORIAL DIAGNOSTIC ---
	# This log shows who is connected to the signal right before it is emitted.
	# This is the ultimate ground truth for our debugging.
	print("[GDM][DIAGNOSTIC] --- Emitting 'convoy_data_updated'. Checking connections... ---")
	var connections = convoy_data_updated.get_connections()
	if connections.is_empty():
		print("[GDM][DIAGNOSTIC]   -> No nodes are connected.")
	else:
		for conn in connections:
			var target_node = conn.get("target")
			var method_name = conn.get("callable").get_method()
			var target_id = target_node.get_instance_id() if is_instance_valid(target_node) else "N/A"
			var target_path = target_node.get_path() if is_instance_valid(target_node) else "<INVALID INSTANCE>"
			print("[GDM][DIAGNOSTIC]   -> Connected: %s (ID: %s) -> %s()" % [target_path, str(target_id), method_name])
	# --- END TUTORIAL DIAGNOSTIC ---
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
		# Auto re-probe mechanic/vendor availability for Mechanics-active convoy (if set),
		# but ONLY if a mechanics session is active. Do not probe on general vendor updates.
		var probe_target: Dictionary = {}
		if _mech_active_convoy_id != "":
			var mech_conv = get_convoy_by_id(_mech_active_convoy_id)
			if mech_conv is Dictionary and not mech_conv.is_empty():
				probe_target = mech_conv
		if not probe_target.is_empty():
			print("[PartCompatGDM] PROBE: vendor updated; re-probing convoy_id=", str(probe_target.get("convoy_id", "")))
			probe_mechanic_vendor_availability_for_convoy(probe_target)
	else:
		printerr("GameDataManager: Vendor ID %s not found in any settlement." % updated_id)

func notify_inline_error_handled() -> void:
	"""Allows UI components to announce they are handling a recoverable error, so other systems (like tutorials) can pause."""
	emit_signal("inline_error_handled")

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

# Safe numeric checker to handle nulls and non-numeric values from API
func _is_positive_number(v: Variant) -> bool:
	return (v is float or v is int) and float(v) > 0.0

# Aggregates vendor's inventory into categories
func _aggregate_vendor_items(vendor_data: Dictionary) -> Dictionary:
	var aggregated = {
		"missions": {},
		"resources": {},
		"vehicles": {},
		"parts": {},
		"other": {}
	}
	if not vendor_data:
		return aggregated

	for item in vendor_data.get("cargo_inventory", []):
		if item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null:
			continue
		var category = "other"
		var is_mission := item.get("recipient") != null
		# Guard against null values in resource fields (API may send null instead of 0)
		var is_resource: bool = (
			(item.has("food") and _is_positive_number(item.get("food"))) or
			(item.has("water") and _is_positive_number(item.get("water"))) or
			(item.has("fuel") and _is_positive_number(item.get("fuel")))
		)
		var is_part: bool = item.has("slot") and item.get("slot") != null and String(item.get("slot")).length() > 0
		if is_mission:
			category = "missions"
		elif is_resource:
			category = "resources"
		elif is_part:
			category = "parts"
			if VEHICLE_DEBUG_DUMP:
				print("[GameDataManager][DEBUG][VendorParts] Detected part in vendor cargo name=", item.get("name","?"), " slot=", item.get("slot","?"))
		elif item.has("parts") and item.get("parts") is Array and not (item.get("parts") as Array).is_empty():
			# Normalize a vendor cargo container that embeds a single part; lift slot up for categorization
			var nested_parts: Array = item.get("parts")
			var first_part: Dictionary = nested_parts[0]
			var norm_item: Dictionary = item.duplicate(true)
			if not norm_item.has("slot") and first_part.has("slot"):
				norm_item["slot"] = first_part.get("slot")
			category = "parts"
			if VEHICLE_DEBUG_DUMP:
				print("[GameDataManager][DEBUG][VendorParts] Container with nested part name=", norm_item.get("name","?"), " slot=", norm_item.get("slot","?"))
			_aggregate_item(aggregated[category], norm_item)
			continue
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
				elif (item.has("food") and _is_positive_number(item.get("food"))) or (item.has("water") and _is_positive_number(item.get("water"))) or (item.has("fuel") and _is_positive_number(item.get("fuel"))):
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
			elif (item.has("food") and _is_positive_number(item.get("food"))) or (item.has("water") and _is_positive_number(item.get("water"))) or (item.has("fuel") and _is_positive_number(item.get("fuel"))):
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
	# --- START DIAGNOSTIC LOG ---
	# This log helps us trace what part of the code is initiating a purchase.
	var item_name_for_log = item_data.get("name", "<no_name>")
	var cargo_id_for_log = item_data.get("cargo_id", "<no_cargo_id>")
	print("[GDM][buy_item] CALLED. Item: '%s', cargo_id: '%s', quantity: %d" % [item_name_for_log, cargo_id_for_log, quantity])
	print_stack()
	# --- END DIAGNOSTIC LOG ---

	if not is_instance_valid(api_calls_node):
		printerr("GameDataManager: Cannot buy item, APICallsInstance is invalid.")
		return

	# Check cargo first!
	if item_data.has("cargo_id"):
		api_calls_node.buy_cargo(vendor_id, convoy_id, item_data["cargo_id"], quantity)
	elif item_data.has("vehicle_id"):
		api_calls_node.buy_vehicle(vendor_id, convoy_id, item_data["vehicle_id"])
	elif item_data.has("is_raw_resource"):
		if item_data.has("fuel") and _is_positive_number(item_data.get("fuel")):
			api_calls_node.buy_resource(vendor_id, convoy_id, "fuel", float(quantity))
		elif item_data.has("water") and _is_positive_number(item_data.get("water")):
			api_calls_node.buy_resource(vendor_id, convoy_id, "water", float(quantity))
		elif item_data.has("food") and _is_positive_number(item_data.get("food")):
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

# --- Mechanics warm-up helpers ---
func start_mechanics_probe_session(convoy_id: String) -> void:
	_mech_active_convoy_id = convoy_id
	print("[PartCompatGDM] Mechanics session started for convoy_id=", convoy_id)

func end_mechanics_probe_session() -> void:
	if _mech_active_convoy_id != "":
		print("[PartCompatGDM] Mechanics session ended for convoy_id=", _mech_active_convoy_id)
	_mech_active_convoy_id = ""

func _request_settlement_vendor_data_at_coords(x: int, y: int) -> void:
	# Ask backend for fresh vendor inventories at these coordinates (if known in map cache)
	if all_settlement_data.is_empty():
		return
	var sett_match: Dictionary = {}
	for s in all_settlement_data:
		if not (s is Dictionary):
			continue
		if int(s.get("x", 123456)) == x and int(s.get("y", 123456)) == y:
			sett_match = s
			break
	if sett_match.is_empty():
		return
	var vendors: Array = sett_match.get("vendors", [])
	if vendors.is_empty() and VEHICLE_DEBUG_DUMP:
		print("[PartCompatGDM] Warm-up: settlement at (", x, ",", y, ") has no vendors array in map data.")
	for v in vendors:
		if not (v is Dictionary):
			if VEHICLE_DEBUG_DUMP:
				print("[PartCompatGDM] Warm-up: vendor entry is not a Dictionary: ", v)
			continue
		# Try multiple key candidates for vendor id
		var vid := ""
		var id_keys := ["vendor_id", "id", "vendorId", "vendorID", "_id"]
		for k in id_keys:
			if v.has(k):
				vid = str(v.get(k, ""))
				break
		if vid == "" and VEHICLE_DEBUG_DUMP:
			print("[PartCompatGDM] Warm-up: vendor has no id field; keys=", v.keys())
		# Refresh if cargo inventory missing or empty
		var inv: Array = v.get("cargo_inventory", []) if v.has("cargo_inventory") else []
		if vid != "" and (inv.is_empty() or inv.size() == 0):
			request_vendor_data_refresh(vid)
			if VEHICLE_DEBUG_DUMP:
				print("[PartCompatGDM] Requested vendor refresh vendor_id=", vid, " at (", x, ",", y, ") for Mechanics warm-up")

func warm_mechanics_data_for_convoy(convoy: Dictionary) -> void:
	if convoy.is_empty():
		return
	var cid: String = str(convoy.get("convoy_id", ""))
	if cid == "":
		return
	start_mechanics_probe_session(cid)
	# If settlements aren't ready yet, wait for them, then resume warm-up
	if all_settlement_data.is_empty():
		print("[PartCompatGDM] Mechanics warm-up deferred; settlements not loaded yet. Waiting…")
		_mech_wait_convoy_id = cid
		# Kick a map data request if none in flight
		if not _map_request_in_flight:
			_map_request_in_flight = true
			request_map_data()
		# Connect to settlement_data_updated once to continue warm-up
		if not settlement_data_updated.is_connected(_on_mechanics_settlements_ready):
			settlement_data_updated.connect(_on_mechanics_settlements_ready)
		return
	var sx := int(roundf(float(convoy.get("x", -999999))))
	var sy := int(roundf(float(convoy.get("y", -999999))))
	# Proactively request vendor inventories for this settlement
	_request_settlement_vendor_data_at_coords(sx, sy)
	# Kick off an initial probe now (will re-probe automatically as vendors update)
	probe_mechanic_vendor_availability_for_convoy(convoy)

func _on_mechanics_settlements_ready(_list: Array) -> void:
	# Resume warm-up once settlements arrive
	if _mech_wait_convoy_id == "":
		return
	var conv = get_convoy_by_id(_mech_wait_convoy_id)
	if conv is Dictionary and not conv.is_empty():
		print("[PartCompatGDM] Settlements ready; resuming Mechanics warm-up for convoy_id=", _mech_wait_convoy_id)
		# Avoid repeated triggers; clear the wait id
		_mech_wait_convoy_id = ""
		warm_mechanics_data_for_convoy(conv)

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
