# APICalls.gd
extends Node

# Signal to indicate when parsed convoy data has been fetched
signal convoy_data_received(parsed_convoy_list: Array)
# Signal to indicate an error occurred during fetching
signal map_data_received(map_data: Dictionary)
# Signal to indicate when user data has been fetched
signal user_data_received(user_data: Dictionary)
# Signal to indicate an error occurred during fetching
signal fetch_error(error_message: String)

# --- Auth Signals ---
signal auth_url_received(data: Dictionary)
signal auth_token_received(data: Dictionary)
signal auth_status_update(status: String)
signal auth_session_received(session_token: String)
signal user_id_resolved(user_id: String)
signal auth_expired
signal auth_poll_started
signal auth_poll_finished(success: bool)

# --- Vendor Transaction Signals ---
@warning_ignore("unused_signal")
signal vehicle_bought(result: Dictionary)
@warning_ignore("unused_signal")
signal vehicle_sold(result: Dictionary)
@warning_ignore("unused_signal")
signal cargo_bought(result: Dictionary)
@warning_ignore("unused_signal")
signal cargo_sold(result: Dictionary)
@warning_ignore("unused_signal")
signal resource_bought(result: Dictionary)
@warning_ignore("unused_signal")
signal resource_sold(result: Dictionary)
signal vendor_data_received(vendor_data: Dictionary)
signal part_compatibility_checked(payload: Dictionary) # { vehicle_id, part_id, data }
signal cargo_data_received(cargo: Dictionary)
@warning_ignore("unused_signal")
signal vehicle_part_attached(result: Dictionary)
@warning_ignore("unused_signal")
signal vehicle_part_added(result: Dictionary)
@warning_ignore("unused_signal")
signal vehicle_part_detached(result: Dictionary)

# --- Journey Planning Signals ---
signal route_choices_received(routes: Array)
@warning_ignore("unused_signal")
signal convoy_sent_on_journey(updated_convoy_data: Dictionary)
@warning_ignore("unused_signal")
signal convoy_journey_canceled(updated_convoy_data: Dictionary)

# --- Warehouse Signals ---
@warning_ignore("unused_signal")
signal warehouse_created(result: Variant) # API returns UUID or dict; treat as Variant
@warning_ignore("unused_signal")
signal warehouse_received(warehouse_data: Dictionary)
@warning_ignore("unused_signal")
signal warehouse_expanded(result: Variant)
@warning_ignore("unused_signal")
signal warehouse_cargo_stored(result: Variant)
@warning_ignore("unused_signal")
signal warehouse_cargo_retrieved(result: Variant)
@warning_ignore("unused_signal")
signal warehouse_vehicle_stored(result: Variant)
@warning_ignore("unused_signal")
signal warehouse_vehicle_retrieved(result: Variant)
@warning_ignore("unused_signal")
signal warehouse_convoy_spawned(result: Variant)

var BASE_URL: String = 'http://127.0.0.1:1337' # default
# var BASE_URL: String = 'https://df-api.oori.dev:1337' # default
# Allow override via environment (cannot be const due to runtime lookup)
func _init():
	if OS.has_environment('DF_API_BASE_URL'):
		BASE_URL = OS.get_environment('DF_API_BASE_URL')

var current_user_id: String = "" # To store the logged-in user's ID
var _http_request: HTTPRequest
var _http_request_map: HTTPRequest  # Dedicated non-queued requester for map data
var _http_request_route: HTTPRequest # Dedicated requester for route finding (non-queued)
var _http_request_mech_pool: Array = [] # ephemeral HTTPRequest nodes for part compatibility checks
var convoys_in_transit: Array = []  # This will store the latest parsed list of convoys (either user's or all)
var _last_requested_url: String = "" # To store the URL for logging on error
var _is_local_user_attempt: bool = false # Flag to track if the current USER_CONVOYS request is the initial local one

# --- Request Queue ---
var _request_queue: Array = []
var _is_request_in_progress: bool = false

# Add AUTH_STATUS, AUTH_ME to purposes
enum RequestPurpose { NONE, USER_CONVOYS, ALL_CONVOYS, MAP_DATA, USER_DATA, VENDOR_DATA, FIND_ROUTE, AUTH_URL, AUTH_TOKEN, AUTH_STATUS, AUTH_ME, CARGO_DATA, WAREHOUSE_GET }
var _current_request_purpose: RequestPurpose = RequestPurpose.NONE

var _current_patch_signal_name: String = ""

# --- Auth State ---
var _auth_bearer_token: String = '' # Stored session token (JWT) for Authorization header
var _auth_poll: Dictionary = {
	'active': false,
	'state': '',
	'attempt': 0,
	'max_attempts': 80,
	'interval': 1.5
}
var _auth_token_expiry: int = 0 # Unix timestamp of token expiry
var _auth_me_requested: bool = false
var _user_data_requested_once: bool = false
const SESSION_CFG_PATH: String = "user://session.cfg"
var _login_in_progress: bool = false

# Add after enum declaration
var _current_request_start_time: float = 0.0
var _request_timeout_timer: Timer
const REQUEST_TIMEOUT_SECONDS := {
	RequestPurpose.MAP_DATA: 5.0,
	RequestPurpose.AUTH_URL: 5.0,
	RequestPurpose.AUTH_STATUS: 5.0,
	RequestPurpose.AUTH_ME: 5.0,
	RequestPurpose.CARGO_DATA: 5.0,
	RequestPurpose.WAREHOUSE_GET: 5.0,
}

var _probe_stalled_count: int = 0
var _auth_me_resolve_attempts: int = 0
const AUTH_ME_MAX_ATTEMPTS: int = 5
const AUTH_ME_RETRY_INTERVAL: float = 0.75

func _ready() -> void:
	# Ensure this autoload keeps processing while login screen pauses the tree
	process_mode = Node.PROCESS_MODE_ALWAYS
	print('[APICalls] _ready(): process_mode set to ALWAYS (was paused tree workaround)')
	# Create an HTTPRequest node and add it as a child.
	# This node will handle the actual network communication.
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	# Reconnect without .bind() so callback signature matches exactly
	if _http_request.request_completed.is_connected(_on_request_completed):
		_http_request.request_completed.disconnect(_on_request_completed)
	_http_request.request_completed.connect(_on_request_completed)
	# Parallel map HTTPRequest
	_http_request_map = HTTPRequest.new()
	_http_request_map.name = "MapHTTPRequest"
	add_child(_http_request_map)
	if _http_request_map.request_completed.is_connected(_on_map_request_completed):
		_http_request_map.request_completed.disconnect(_on_map_request_completed)
	_http_request_map.request_completed.connect(_on_map_request_completed)
	# NEW: Dedicated route HTTPRequest (bypasses queue so UI not blocked by long user convoy fetches)
	_http_request_route = HTTPRequest.new()
	_http_request_route.name = "RouteHTTPRequest"
	add_child(_http_request_route)
	if _http_request_route.request_completed.is_connected(_on_route_request_completed):
		_http_request_route.request_completed.disconnect(_on_route_request_completed)
	_http_request_route.request_completed.connect(_on_route_request_completed)

	# No persistent requester for mechanics; we will create ephemeral HTTPRequest nodes per request
	_start_request_status_probe()
	_load_auth_session_token()
	# Proactively connect to GameDataManager if available so mechanics pipeline receives compat responses
	_call_deferred_connect_gdm()
func _call_deferred_connect_gdm() -> void:
	call_deferred("_try_connect_gdm")

func _try_connect_gdm() -> void:
	var gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if gdm.has_method("_on_part_compatibility_checked"):
			if not is_connected("part_compatibility_checked", gdm._on_part_compatibility_checked):
				print("[APICalls] Wiring part_compatibility_checked -> GameDataManager._on_part_compatibility_checked")
				part_compatibility_checked.connect(gdm._on_part_compatibility_checked)
		else:
			print("[APICalls] GameDataManager missing handler _on_part_compatibility_checked; skipping auto-wire")
	else:
		print("[APICalls] GameDataManager not present at ready; will rely on GDM to connect.")
	# Auto-resolve user if we have a still-valid token
	if is_auth_token_valid():
		print("[APICalls] Auto-login attempt with persisted session token.")
		resolve_current_user_id()
	# Initiate the request to get all in-transit convoys.
	# The data will be processed in _on_request_completed when it arrives.
	# get_all_in_transit_convoys() # This will now be triggered by GameDataManager after login or if no user

func set_user_id(p_user_id: String) -> void:
	current_user_id = p_user_id
	# print("APICalls: User ID set to: ", current_user_id)

# --- Auth helpers ---
func set_auth_session_token(token: String) -> void:
	_auth_bearer_token = token
	_auth_token_expiry = _decode_jwt_expiry(token)
	print("[APICalls] Auth session set (len=", token.length(), ", exp=", _auth_token_expiry, ")")
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "session_token", token)
	cfg.set_value("auth", "token_expiry", _auth_token_expiry)
	cfg.save(SESSION_CFG_PATH)

func clear_auth_session_token() -> void:
	_auth_bearer_token = ""
	_auth_token_expiry = 0
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "session_token", "")
	cfg.set_value("auth", "token_expiry", 0)
	cfg.save(SESSION_CFG_PATH)
	print("[APICalls] Auth session cleared.")

func _apply_auth_header(headers: PackedStringArray) -> PackedStringArray:
	var out := headers.duplicate()
	if _auth_bearer_token != "":
		var has_auth := false
		for h in out:
			if h.begins_with("Authorization:") or h.begins_with("authorization:"):
				has_auth = true
				break
		if not has_auth:
			out.append("Authorization: Bearer %s" % _auth_bearer_token)
	return out

# --- Auth API ---

func _load_auth_session_token() -> void:
	var cfg := ConfigFile.new()
	var err = cfg.load(SESSION_CFG_PATH)
	if err == OK:
		var token = cfg.get_value("auth", "session_token", "")
		var expiry = int(cfg.get_value("auth", "token_expiry", 0))
		if token != "" and expiry > 0:
			if Time.get_unix_time_from_system() < expiry:
				_auth_bearer_token = token
				_auth_token_expiry = expiry
				print("[APICalls] Loaded session token from disk, exp=", expiry)
			else:
				print("[APICalls] Saved session token expired, clearing.")
				clear_auth_session_token()
		else:
			print("[APICalls] No valid session token found on disk.")
	else:
		print("[APICalls] No session.cfg found.")

func is_auth_token_valid() -> bool:
	return _auth_bearer_token != "" and _auth_token_expiry > Time.get_unix_time_from_system()

func _is_auth_token_expired() -> bool:
	return _auth_bearer_token != "" and _auth_token_expiry <= Time.get_unix_time_from_system()

func logout() -> void:
	clear_auth_session_token()
	emit_signal("fetch_error", "Logged out.")

func get_auth_url(_provider: String = "") -> void:
	# Abort map fetch if it's blocking
	_abort_map_request_for_auth()
	if _login_in_progress or _auth_poll.active:
		print("[APICalls] Ignoring get_auth_url; login already in progress.")
		return
	print("[APICalls] get_auth_url(): queueing AUTH_URL request (provider=%s). Current queue length before append=%d" % [_provider, _request_queue.size()])
	var url := "%s/auth/discord/url" % BASE_URL
	var headers: PackedStringArray = ['accept: application/json']
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.AUTH_URL,
		"method": HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	print("[APICalls] get_auth_url(): appended. Queue length now=%d in_progress=%s" % [_request_queue.size(), str(_is_request_in_progress)])
	_process_queue()
	# Failsafe: schedule a deferred attempt and a watchdog
	call_deferred("_process_queue")
	_create_queue_watchdog()

func start_auth_poll(state: String, interval: float = 1.5, timeout_seconds: float = 120.0) -> void:
	_auth_poll.active = true
	_auth_poll.state = state
	_auth_poll.attempt = 0
	_auth_poll.interval = interval
	_auth_poll.max_attempts = int(ceil(timeout_seconds / max(0.2, interval)))
	_login_in_progress = true
	emit_signal("auth_poll_started")
	print("[APICalls] Starting auth status poll for state=", state)
	_enqueue_auth_status_request(state)

func _enqueue_auth_status_request(state: String) -> void:
	if not _auth_poll.active:
		return
	var url := "%s/auth/status?state=%s" % [BASE_URL, state]
	var headers: PackedStringArray = ['accept: application/json']
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.AUTH_STATUS,
		"method": HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	_process_queue()

func resolve_current_user_id(force: bool = false) -> void:
	if _auth_me_requested and not force:
		print('[APICalls] resolve_current_user_id(): already requested; skipping.')
		return
	if force:
		print('[APICalls] resolve_current_user_id(): forced retry attempt %d' % (_auth_me_resolve_attempts + 1))
	_auth_me_requested = true
	_auth_me_resolve_attempts += 1
	if current_user_id != '' and not force:
		print('[APICalls] resolve_current_user_id(): already have user id (%s); skipping.' % current_user_id)
		return
	var url := '%s/auth/me' % BASE_URL
	var headers: PackedStringArray = ['accept: application/json']
	var request_details: Dictionary = {
		'url': url,
		'headers': headers,
		'purpose': RequestPurpose.AUTH_ME,
		'method': HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	_process_queue()

func exchange_auth_token(code: String, state: String, code_verifier: String) -> void:
	# Updated to Discord-specific endpoint (kept for non-polling flows)
	var url := "%s/auth/discord/token" % BASE_URL
	var headers: PackedStringArray = ['accept: application/json', 'content-type: application/json']
	var body := JSON.stringify({
		"code": code,
		"state": state,
		"code_verifier": code_verifier,
	})
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.AUTH_TOKEN,
		"method": HTTPClient.METHOD_POST,
		"body": body,
	}
	_request_queue.append(request_details)
	_process_queue()

# --- Existing APIs ---
func get_convoy_data(convoy_id: String) -> void:
	if not convoy_id or convoy_id.is_empty():
		printerr('APICalls (get_convoy_data): Convoy ID cannot be empty.')
		emit_signal('fetch_error', 'Convoy ID cannot be empty.')
		return

	var url: String = '%s/convoy/get?convoy_id=%s' % [BASE_URL, convoy_id]

	# Headers for the request
	var headers: PackedStringArray = [
		'accept: application/json'
	]

	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE, # Special case for single convoy, handled in _on_request_completed
		"method": HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	_process_queue()

func get_map_data(x_min: int = -1, x_max: int = -1, y_min: int = -1, y_max: int = -1) -> void:
	# Parallel (non-queued) map fetch: does not block auth or other queued requests.
	var url: String = '%s/map/get' % BASE_URL
	var query_params: Array[String] = []
	if x_min != -1: query_params.append("x_min=%d" % x_min)
	if x_max != -1: query_params.append("x_max=%d" % x_max)
	if y_min != -1: query_params.append("y_min=%d" % y_min)
	if y_max != -1: query_params.append("y_max=%d" % y_max)
	if not query_params.is_empty():
		url += "?" + "&".join(query_params)
	# Abort any in-flight map request (optional latest-wins strategy)
	if _http_request_map.get_http_client_status() == HTTPClient.STATUS_REQUESTING:
		print('[APICalls] Aborting previous map request to start a new one.')
		_http_request_map.cancel_request()
	print('[APICalls][MAP] Dispatching parallel map request: %s' % url)
	var headers: PackedStringArray = ['accept: application/octet-stream']
	# Apply auth header if we have a token (map now protected)
	headers = _apply_auth_header(headers)
	var err := _http_request_map.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		printerr('[APICalls][MAP] Failed to start map request (error=%s) URL=%s' % [err, url])

func get_user_data(p_user_id: String) -> void:
	if _user_data_requested_once:
		print('[APICalls] get_user_data(): already fetched once this session; skip duplicate.')
		return
	_user_data_requested_once = true
	if not _is_valid_uuid(p_user_id):
		var error_msg = "APICalls (get_user_data): Provided ID '%s' is not a valid UUID." % p_user_id
		printerr(error_msg)
		emit_signal('fetch_error', error_msg)
		return

	var url: String = '%s/user/get?user_id=%s' % [BASE_URL, p_user_id]
	var headers: PackedStringArray = ['accept: application/json']

	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.USER_DATA,
		"method": HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	_process_queue()

func _is_valid_uuid(uuid_string: String) -> bool:
	# Basic UUID regex: 8-4-4-4-12 hexadecimal characters
	var uuid_regex = RegEx.new()
	uuid_regex.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
	return uuid_regex.search(uuid_string) != null

func get_user_convoys(p_user_id: String) -> void:
	if p_user_id.is_empty():
		printerr('APICalls: User ID cannot be empty for get_user_convoys.')
		emit_signal('fetch_error', 'User ID cannot be empty for get_user_convoys.')
		return
	if not _is_valid_uuid(p_user_id):
		printerr('APICalls: Provided ID "%s" is not a valid UUID for get_user_convoys.' % p_user_id)
		emit_signal('fetch_error', 'Invalid user_id for get_user_convoys.')
		return
	# Swap: Fetch full user via /user/get instead of convoy endpoints
	var url: String = '%s/user/get?user_id=%s' % [BASE_URL, p_user_id]
	var headers: PackedStringArray = ['accept: application/json']
	_is_local_user_attempt = false
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.USER_CONVOYS, # reuse purpose but now expect Dictionary
		"method": HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	_process_queue()

func get_all_in_transit_convoys() -> void:
	var url: String = '%s/convoy/all_in_transit' % [BASE_URL]
	var headers: PackedStringArray = [  # Headers for the request
		'accept: application/json'
	]
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.ALL_CONVOYS,
		"method": HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	_process_queue()

# --- Vendor / Transaction Requests (added) ---
func request_vendor_data(vendor_id: String) -> void:
	if vendor_id.is_empty() or not _is_valid_uuid(vendor_id):
		printerr("APICalls (request_vendor_data): invalid vendor_id %s" % vendor_id)
		return
	var url := "%s/vendor/get?vendor_id=%s" % [BASE_URL, vendor_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.VENDOR_DATA,
		"method": HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	_process_queue()

# --- Cargo detail by ID ---
func get_cargo(cargo_id: String) -> void:
	if cargo_id.is_empty() or not _is_valid_uuid(cargo_id):
		printerr("APICalls (get_cargo): invalid cargo_id %s" % cargo_id)
		return
	var url := "%s/cargo/get?cargo_id=%s" % [BASE_URL, cargo_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.CARGO_DATA,
		"method": HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	_process_queue()

# --- Warehouse requests ---
func warehouse_new(sett_id: String) -> void:
	if sett_id.is_empty() or not _is_valid_uuid(sett_id):
		printerr("APICalls (warehouse_new): invalid sett_id %s" % sett_id)
		return
	var url := "%s/warehouse/new?sett_id=%s" % [BASE_URL, sett_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_POST,
		"body": "",
		"signal_name": "warehouse_created"
	})
	_process_queue()

func get_warehouse(warehouse_id: String) -> void:
	if warehouse_id.is_empty() or not _is_valid_uuid(warehouse_id):
		printerr("APICalls (get_warehouse): invalid warehouse_id %s" % warehouse_id)
		return
	var url := "%s/warehouse/get?warehouse_id=%s" % [BASE_URL, warehouse_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.WAREHOUSE_GET,
		"method": HTTPClient.METHOD_GET
	})
	_process_queue()

# --- Warehouse action PATCH wrappers ---
func _build_query(params: Dictionary) -> String:
	if params.is_empty():
		return ""
	var parts: Array[String] = []
	for k in params.keys():
		var key := String(k)
		var val := str(params[k])
		# Basic URI encoding for safety
		var enc_key := key.uri_encode()
		var enc_val := val.uri_encode()
		parts.append("%s=%s" % [enc_key, enc_val])
	return "?" + "&".join(parts)

func warehouse_expand(params: Dictionary) -> void:
	var url := "%s/warehouse/expand%s" % [BASE_URL, _build_query(params)]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "warehouse_expanded"
	})
	_process_queue()

func warehouse_cargo_store(params: Dictionary) -> void:
	var url := "%s/warehouse/cargo/store%s" % [BASE_URL, _build_query(params)]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "warehouse_cargo_stored"
	})
	_process_queue()

func warehouse_cargo_retrieve(params: Dictionary) -> void:
	var url := "%s/warehouse/cargo/retrieve%s" % [BASE_URL, _build_query(params)]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "warehouse_cargo_retrieved"
	})
	_process_queue()

func warehouse_vehicle_store(params: Dictionary) -> void:
	var url := "%s/warehouse/vehicle/store%s" % [BASE_URL, _build_query(params)]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "warehouse_vehicle_stored"
	})
	_process_queue()

func warehouse_vehicle_retrieve(params: Dictionary) -> void:
	var url := "%s/warehouse/vehicle/retrieve%s" % [BASE_URL, _build_query(params)]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "warehouse_vehicle_retrieved"
	})
	_process_queue()

func warehouse_convoy_spawn(params: Dictionary) -> void:
	var url := "%s/warehouse/convoy/spawn%s" % [BASE_URL, _build_query(params)]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "warehouse_convoy_spawned"
	})
	_process_queue()

# --- Mechanics / Part Compatibility ---
func check_vehicle_part_compatibility(vehicle_id: String, part_cargo_id: String) -> void:
	if vehicle_id.is_empty() or part_cargo_id.is_empty():
		print("[PartCompatAPI] SKIP: empty id(s) vehicle=", vehicle_id, " part_cargo_id=", part_cargo_id)
		return
	var url := "%s/vehicle/part/check_compatibility?vehicle_id=%s&part_cargo_id=%s" % [BASE_URL, vehicle_id, part_cargo_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	var req := HTTPRequest.new()
	req.name = "PartCompatRequest_%s_%s" % [vehicle_id.substr(0, 8), part_cargo_id.substr(0, 8)]
	add_child(req)
	_http_request_mech_pool.append(req)
	if req.request_completed.is_connected(_on_part_compat_request_completed):
		req.request_completed.disconnect(_on_part_compat_request_completed)
	# Bind the requester and identifiers so handler can emit a useful payload (vehicle_id, part_id)
	req.request_completed.connect(_on_part_compat_request_completed.bind(req, vehicle_id, part_cargo_id))
	print("[PartCompatAPI] REQUEST vehicle=", vehicle_id, " part_cargo_id=", part_cargo_id, " url=", url)
	var err := req.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		var emsg := "[PartCompatAPI] Request error err=%d url=%s" % [err, url]
		print(emsg)
		emit_signal('fetch_error', emsg)

func _on_part_compat_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, requester: HTTPRequest, vehicle_id: String, part_cargo_id: String) -> void:
	print("[PartCompatAPI] COMPLETE vehicle=", vehicle_id, " part=", part_cargo_id, " result=", result, " code=", response_code, " bytes=", body.size())
	var text := body.get_string_from_utf8()
	var data: Variant = {}
	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err == OK:
		data = json.data
	else:
		var emsg := "[PartCompatAPI] Parse error: %s for vehicle=%s part=%s body=%s" % [str(parse_err), vehicle_id, part_cargo_id, text]
		print(emsg)
		emit_signal('fetch_error', emsg)
	var payload := {
		"vehicle_id": vehicle_id,
		"part_cargo_id": part_cargo_id,
		"http_result": result,
		"status": response_code,
		"data": data
	}
	print("[PartCompatAPI] RESPONSE payload=", payload)
	emit_signal('part_compatibility_checked', payload)
	# Cleanup requester
	if is_instance_valid(requester):
		if requester in _http_request_mech_pool:
			_http_request_mech_pool.erase(requester)
		requester.queue_free()

# Backwards compatibility alias: older code expects get_vendor_data()
func get_vendor_data(vendor_id: String) -> void:
	request_vendor_data(vendor_id)

func buy_cargo(vendor_id: String, convoy_id: String, cargo_id: String, quantity: int) -> void:
	if vendor_id.is_empty() or convoy_id.is_empty() or cargo_id.is_empty():
		printerr("APICalls (buy_cargo): missing id(s)")
		return
	# New route shape (consistent with resource/vehicle routes): /vendor/cargo/buy
	var url := "%s/vendor/cargo/buy?vendor_id=%s&convoy_id=%s&cargo_id=%s&quantity=%d" % [BASE_URL, vendor_id, convoy_id, cargo_id, quantity]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "cargo_bought"
	})
	_process_queue()

func sell_cargo(vendor_id: String, convoy_id: String, cargo_id: String, quantity: int) -> void:
	if vendor_id.is_empty() or convoy_id.is_empty() or cargo_id.is_empty():
		printerr("APICalls (sell_cargo): missing id(s)")
		return
	# New route shape: /vendor/cargo/sell
	var url := "%s/vendor/cargo/sell?vendor_id=%s&convoy_id=%s&cargo_id=%s&quantity=%d" % [BASE_URL, vendor_id, convoy_id, cargo_id, quantity]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "cargo_sold"
	})
	_process_queue()

func buy_vehicle(vendor_id: String, convoy_id: String, vehicle_id: String) -> void:
	if vendor_id.is_empty() or convoy_id.is_empty() or vehicle_id.is_empty():
		printerr("APICalls (buy_vehicle): missing id(s)")
		return
	var url := "%s/vendor/buy_vehicle?vendor_id=%s&convoy_id=%s&vehicle_id=%s" % [BASE_URL, vendor_id, convoy_id, vehicle_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "vehicle_bought"
	})
	_process_queue()

func sell_vehicle(vendor_id: String, convoy_id: String, vehicle_id: String) -> void:
	if vendor_id.is_empty() or convoy_id.is_empty() or vehicle_id.is_empty():
		printerr("APICalls (sell_vehicle): missing id(s)")
		return
	var url := "%s/vendor/sell_vehicle?vendor_id=%s&convoy_id=%s&vehicle_id=%s" % [BASE_URL, vendor_id, convoy_id, vehicle_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "vehicle_sold"
	})
	_process_queue()

func buy_resource(vendor_id: String, convoy_id: String, resource_type: String, quantity: float) -> void:
	# Backend route: PATCH /vendor/resource/buy with all fields in query params
	if vendor_id.is_empty() or convoy_id.is_empty() or resource_type.is_empty() or quantity <= 0:
		printerr("APICalls (buy_resource): invalid args")
		return
	var qty_str := String.num(quantity, 3).rstrip("0").rstrip(".")
	var url := "%s/vendor/resource/buy?vendor_id=%s&convoy_id=%s&resource_type=%s&quantity=%s" % [BASE_URL, vendor_id, convoy_id, resource_type, qty_str]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	print("[APICalls][buy_resource] PATCH url=", url, " (query only)")
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "resource_bought"
	})
	_process_queue()

func sell_resource(vendor_id: String, convoy_id: String, resource_type: String, quantity: float) -> void:
	# Backend route: PATCH /vendor/resource/sell with all fields in query params
	if vendor_id.is_empty() or convoy_id.is_empty() or resource_type.is_empty() or quantity <= 0:
		printerr("APICalls (sell_resource): invalid args")
		return
	var qty_str := String.num(quantity, 3).rstrip("0").rstrip(".")
	var url := "%s/vendor/resource/sell?vendor_id=%s&convoy_id=%s&resource_type=%s&quantity=%s" % [BASE_URL, vendor_id, convoy_id, resource_type, qty_str]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	print("[APICalls][sell_resource] PATCH url=", url, " (query only)")
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "resource_sold"
	})
	_process_queue()

# --- Mechanics / Part Attach ---
func attach_vehicle_part(vehicle_id: String, part_cargo_id: String) -> void:
	# Endpoint: PATCH /vehicle/part/attach?vehicle_id=<uuid>&part_cargo_id=<uuid>
	if vehicle_id.is_empty() or not _is_valid_uuid(vehicle_id):
		printerr("[APICalls][attach_vehicle_part] Invalid vehicle_id '%s'" % vehicle_id)
		emit_signal('fetch_error', "Invalid vehicle_id for part attach")
		return
	if part_cargo_id.is_empty() or not _is_valid_uuid(part_cargo_id):
		printerr("[APICalls][attach_vehicle_part] Invalid part_cargo_id '%s'" % part_cargo_id)
		emit_signal('fetch_error', "Invalid part_cargo_id for part attach")
		return
	var url := "%s/vehicle/part/attach?vehicle_id=%s&part_cargo_id=%s" % [BASE_URL, vehicle_id, part_cargo_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	print("[APICalls][attach_vehicle_part] PATCH url=", url, " auth_present=", _auth_bearer_token != "")
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "vehicle_part_attached"
	})
	_process_queue()

# --- Mechanics / Part Detach ---
func detach_vehicle_part(vehicle_id: String, part_id: String) -> void:
	# Endpoint: PATCH /vehicle/part/detach?vehicle_id=<uuid>&part_id=<uuid>
	if vehicle_id.is_empty() or not _is_valid_uuid(vehicle_id):
		printerr("[APICalls][detach_vehicle_part] Invalid vehicle_id '%s'" % vehicle_id)
		emit_signal('fetch_error', "Invalid vehicle_id for part detach")
		return
	if part_id.is_empty() or not _is_valid_uuid(part_id):
		printerr("[APICalls][detach_vehicle_part] Invalid part_id '%s'" % part_id)
		emit_signal('fetch_error', "Invalid part_id for part detach")
		return
	var url := "%s/vehicle/part/detach?vehicle_id=%s&part_id=%s" % [BASE_URL, vehicle_id, part_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	print("[APICalls][detach_vehicle_part] PATCH url=", url, " auth_present=", _auth_bearer_token != "")
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "vehicle_part_detached"
	})
	_process_queue()

# --- Mechanics / Vendor Add Part (purchase + install) ---
func add_vehicle_part(vendor_id: String, convoy_id: String, vehicle_id: String, part_cargo_id: String) -> void:
	# Endpoint: PATCH /vendor/vehicle/part/add with query params
	if vendor_id.is_empty() or not _is_valid_uuid(vendor_id):
		printerr("[APICalls][add_vehicle_part] Invalid vendor_id '%s'" % vendor_id)
		emit_signal('fetch_error', "Invalid vendor_id for add part")
		return
	if convoy_id.is_empty() or not _is_valid_uuid(convoy_id):
		printerr("[APICalls][add_vehicle_part] Invalid convoy_id '%s'" % convoy_id)
		emit_signal('fetch_error', "Invalid convoy_id for add part")
		return
	if vehicle_id.is_empty() or not _is_valid_uuid(vehicle_id):
		printerr("[APICalls][add_vehicle_part] Invalid vehicle_id '%s'" % vehicle_id)
		emit_signal('fetch_error', "Invalid vehicle_id for add part")
		return
	if part_cargo_id.is_empty() or not _is_valid_uuid(part_cargo_id):
		printerr("[APICalls][add_vehicle_part] Invalid part_cargo_id '%s'" % part_cargo_id)
		emit_signal('fetch_error', "Invalid part_cargo_id for add part")
		return
	var url := "%s/vendor/vehicle/part/add?vendor_id=%s&convoy_id=%s&vehicle_id=%s&part_cargo_id=%s" % [BASE_URL, vendor_id, convoy_id, vehicle_id, part_cargo_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	print("[APICalls][add_vehicle_part] PATCH url=", url, " auth_present=", _auth_bearer_token != "")
	_request_queue.append({
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "vehicle_part_added"
	})
	_process_queue()

# --- Journey Planning Requests ---
var _last_route_params: Dictionary = {} # {convoy_id, dest_x, dest_y}

func find_route(convoy_id: String, dest_x: int, dest_y: int) -> void:
	# Backend contract: HTTP POST to /convoy/journey/find_route with query params (no JSON body)
	_last_route_params = {"convoy_id": convoy_id, "dest_x": dest_x, "dest_y": dest_y}
	if convoy_id.is_empty() or not _is_valid_uuid(convoy_id):
		var err_msg = 'APICalls (find_route): Invalid convoy_id "%s" (must be UUID).' % convoy_id
		printerr(err_msg)
		emit_signal('fetch_error', err_msg)
		return
	if not is_instance_valid(_http_request_route):
		printerr("APICalls (find_route): _http_request_route not initialized.")
		emit_signal('fetch_error', 'Internal route requester missing')
		return
	if _http_request_route.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http_request_route.cancel_request()
	var url: String = "%s/convoy/journey/find_route?convoy_id=%s&dest_x=%d&dest_y=%d" % [BASE_URL, convoy_id, dest_x, dest_y]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	print('[APICalls][FIND_ROUTE] Sending POST (query params) url=%s' % url)
	var err = _http_request_route.request(url, headers, HTTPClient.METHOD_POST) # empty body; params in query string
	if err != OK:
		var err_msg2 = 'APICalls (find_route): HTTPRequest error code %s' % err
		printerr(err_msg2)
		emit_signal('fetch_error', err_msg2)

# Send convoy on selected journey
func send_convoy(convoy_id: String, journey_id: String) -> void:
	# Validate inputs
	if convoy_id.is_empty() or not _is_valid_uuid(convoy_id):
		var err1 = 'APICalls (send_convoy): Invalid convoy_id "%s" (must be UUID).' % convoy_id
		printerr(err1)
		emit_signal('fetch_error', err1)
		return
	if journey_id.is_empty() or not _is_valid_uuid(journey_id):
		var err2 = 'APICalls (send_convoy): Invalid journey_id "%s" (must be UUID).' % journey_id
		printerr(err2)
		emit_signal('fetch_error', err2)
		return
	# Backend expects convoy_id & journey_id as query parameters (422 showed missing query fields)
	var url := "%s/convoy/journey/send?convoy_id=%s&journey_id=%s" % [BASE_URL, convoy_id, journey_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	var has_auth := _auth_bearer_token != ""
	print('[APICalls][SEND_JOURNEY] PATCH (query params) ', url, ' auth_present=', has_auth)
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "", # No body; params in query string
		"signal_name": "convoy_sent_on_journey"
	}
	_request_queue.append(request_details)
	_process_queue()

# Cancel an in-progress convoy journey (PATCH with query params)
func cancel_convoy_journey(convoy_id: String, journey_id: String) -> void:
	if convoy_id.is_empty() or not _is_valid_uuid(convoy_id):
		var err1 = 'APICalls (cancel_convoy_journey): Invalid convoy_id "%s" (must be UUID).' % convoy_id
		printerr(err1)
		emit_signal('fetch_error', err1)
		return
	if journey_id.is_empty() or not _is_valid_uuid(journey_id):
		var err2 = 'APICalls (cancel_convoy_journey): Invalid journey_id "%s" (must be UUID).' % journey_id
		printerr(err2)
		emit_signal('fetch_error', err2)
		return
	var url := "%s/convoy/journey/cancel?convoy_id=%s&journey_id=%s" % [BASE_URL, convoy_id, journey_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	print('[APICalls][CANCEL_JOURNEY] PATCH (query params) ', url, ' auth_present=', _auth_bearer_token != "")
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "convoy_journey_canceled"
	}
	_request_queue.append(request_details)
	_process_queue()

func _on_route_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	print('[APICalls][FIND_ROUTE] request_completed result=%d code=%d bytes=%d' % [result, response_code, body.size()])
	if result != HTTPRequest.RESULT_SUCCESS:
		var err_msg = 'APICalls (_on_route_request_completed): Network error result=%d code=%d' % [result, response_code]
		printerr(err_msg)
		emit_signal('fetch_error', err_msg)
		return
	var response_body_text: String = body.get_string_from_utf8()
	print('[APICalls][FIND_ROUTE] Raw body: ', response_body_text)
	var json_response = JSON.parse_string(response_body_text)
	if json_response == null:
		var error_msg_json = 'APICalls (_on_route_request_completed): Failed to parse JSON.'
		printerr(error_msg_json)
		printerr('  Raw Body: %s' % response_body_text)
		emit_signal('fetch_error', error_msg_json)
		return
	# Expected primary shape: Array of route dicts
	if json_response is Array:
		print('[APICalls][FIND_ROUTE] Parsed %d route choice(s) (Array).' % json_response.size())
		emit_signal('route_choices_received', json_response)
		return
	if json_response is Dictionary:
		# Accept wrappers or single journey dict
		if json_response.has('routes') and json_response['routes'] is Array:
			var arr: Array = json_response['routes']
			print('[APICalls][FIND_ROUTE] Parsed %d route choice(s) from routes[] wrapper.' % arr.size())
			emit_signal('route_choices_received', arr)
			return
		elif json_response.has('journey'):
			print('[APICalls][FIND_ROUTE] Received single route object; wrapping into array.')
			emit_signal('route_choices_received', [json_response])
			return
		elif json_response.has('detail'):
			# FastAPI style validation error; surface nicely
			var detail = json_response['detail']
			var msg = 'Route find failed: %s' % str(detail)
			printerr('[APICalls][FIND_ROUTE] ' + msg)
			emit_signal('fetch_error', msg)
			return
	var error_msg_type = 'APICalls (_on_route_request_completed): Unexpected route response shape (type=%s).' % typeof(json_response)
	printerr(error_msg_type)
	emit_signal('fetch_error', error_msg_type)
func _complete_current_request() -> void:
	_current_request_purpose = RequestPurpose.NONE
	_is_request_in_progress = false
	_process_queue()

func _create_queue_watchdog():
	# If already scheduled, skip
	if has_node("QueueWatchdogTimer"):
		return
	var t := Timer.new()
	# Ensure timer runs under paused tree
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	t.name = "QueueWatchdogTimer"
	t.one_shot = true
	t.wait_time = 1.0
	add_child(t)
	t.timeout.connect(func():
		if _request_queue.size() > 0 and not _is_request_in_progress:
			print("[APICalls][Watchdog] Detected pending requests with no active processing. Forcing _process_queue().")
			_process_queue()
		elif _request_queue.size() > 0 and _is_request_in_progress:
			print("[APICalls][Watchdog] Still in progress (purpose=%s). If stuck, will allow next watchdog (requeue)." % RequestPurpose.keys()[_current_request_purpose])
	)
	t.start()

func _start_request_status_probe():
	if has_node('HTTPRequestStatusProbe'):
		return
	var t := Timer.new()
	# Ensure timer runs while paused
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	t.name = 'HTTPRequestStatusProbe'
	t.wait_time = 0.5
	t.one_shot = false
	add_child(t)
	_probe_stalled_count = 0
	t.timeout.connect(func():
		if _is_request_in_progress and _http_request:
			var st = _http_request.get_http_client_status()
			print('[APICalls][Probe] in_progress purpose=%s status=%d queue_len=%d url=%s' % [RequestPurpose.keys()[_current_request_purpose], st, _request_queue.size(), _last_requested_url])
			if _current_request_purpose == RequestPurpose.AUTH_URL:
				if st == HTTPClient.STATUS_RESOLVING or st == HTTPClient.STATUS_CONNECTING:
					_probe_stalled_count += 1
				else:
					_probe_stalled_count = 0
				if _probe_stalled_count >= 10: # ~5s
					print('[APICalls][Probe] AUTH_URL request appears stalled; retrying with alternate host.')
					_probe_stalled_count = 0
					_retry_auth_url_alternate_host()
	)
	t.start()

func _retry_auth_url_alternate_host():
	if _current_request_purpose != RequestPurpose.AUTH_URL:
		return
	var alt_host = ''
	if BASE_URL.find('127.0.0.1') != -1:
		alt_host = BASE_URL.replace('127.0.0.1', 'localhost')
	elif BASE_URL.find('localhost') != -1:
		alt_host = BASE_URL.replace('localhost', '127.0.0.1')
	else:
		alt_host = BASE_URL
	print('[APICalls] Retrying AUTH_URL against alt host base=%s' % alt_host)
	if _http_request:
		_http_request.cancel_request()
	_is_request_in_progress = false
	_current_request_purpose = RequestPurpose.NONE
	# Replace queued AUTH_URL if another is pending
	for i in range(_request_queue.size()):
		var r = _request_queue[i]
		if r.get('purpose', -1) == RequestPurpose.AUTH_URL:
			_request_queue.remove_at(i)
			break
	var url := '%s/auth/discord/url' % alt_host
	var headers: PackedStringArray = ['accept: application/json']
	_request_queue.push_front({
		'url': url,
		'headers': headers,
		'purpose': RequestPurpose.AUTH_URL,
		'method': HTTPClient.METHOD_GET
	})
	_process_queue()
func _process_queue() -> void:
	print("[APICalls] _process_queue(): entry. in_progress=%s queue_len=%d" % [str(_is_request_in_progress), _request_queue.size()])
	if _is_request_in_progress or _request_queue.is_empty():
		return
	if _is_auth_token_expired():
		print("[APICalls] Session token expired; clearing before request.")
		clear_auth_session_token()
		emit_signal("fetch_error", "Session expired. Please log in again.")
		return
	_is_request_in_progress = true
	print("[APICalls] _process_queue(): dequeuing next request. Remaining (before pop)=%d" % _request_queue.size())
	var next_request: Dictionary = _request_queue.pop_front()
	print("[APICalls] _process_queue(): dequeued. Remaining (after pop)=%d" % _request_queue.size())
	_last_requested_url = next_request.get("url", "")
	_current_request_purpose = next_request.get("purpose", RequestPurpose.NONE)
	_current_patch_signal_name = next_request.get("signal_name", "")
	var headers: PackedStringArray = next_request.get("headers", [])
	var method: int = next_request.get("method", HTTPClient.METHOD_GET)
	var body: String = next_request.get("body", "")
	headers = _apply_auth_header(headers)
	var purpose_str: String = RequestPurpose.keys()[_current_request_purpose]
	print("[APICalls] _process_queue(): dispatching purpose=%s URL=%s method=%d" % [purpose_str, _last_requested_url, method])
	_current_request_start_time = Time.get_unix_time_from_system()
	_arm_request_timeout()
	var error: Error = _http_request.request(_last_requested_url, headers, method, body)
	if error != OK:
		var error_msg = "APICalls (_process_queue): HTTPRequest initiation failed with error code %s for URL: %s" % [error, _last_requested_url]
		printerr(error_msg)
		emit_signal('fetch_error', error_msg)
		_is_request_in_progress = false
		_current_request_purpose = RequestPurpose.NONE
		call_deferred("_process_queue")

func _arm_request_timeout():
	if _request_timeout_timer and is_instance_valid(_request_timeout_timer):
		_request_timeout_timer.queue_free()
	var timeout_sec = 0.0
	if REQUEST_TIMEOUT_SECONDS.has(_current_request_purpose):
		timeout_sec = REQUEST_TIMEOUT_SECONDS[_current_request_purpose]
	if timeout_sec <= 0.0:
		return
	_request_timeout_timer = Timer.new()
	_request_timeout_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_request_timeout_timer.one_shot = true
	_request_timeout_timer.wait_time = timeout_sec
	add_child(_request_timeout_timer)
	_request_timeout_timer.timeout.connect(_handle_request_timeout)
	_request_timeout_timer.start()

func _handle_request_timeout():
	if not _is_request_in_progress:
		return
	var elapsed = Time.get_unix_time_from_system() - _current_request_start_time
	var purpose_str = RequestPurpose.keys()[_current_request_purpose]
	print("[APICalls][Timeout] Purpose=%s elapsed=%.2fs (timeout triggered)" % [purpose_str, elapsed])
	# Cancel only long-running map fetch to unblock auth
	if _current_request_purpose == RequestPurpose.MAP_DATA:
		if _http_request:
			_http_request.cancel_request()
			print("[APICalls][Timeout] Canceled MAP_DATA request; will retry later after auth.")
		# Requeue map data for later (optional)
		_requeue_map_after_auth()
	# Mark request complete with error
	_is_request_in_progress = false
	_current_request_purpose = RequestPurpose.NONE
	call_deferred("_process_queue")

func _requeue_map_after_auth():
	# Avoid duplicate if already queued
	for r in _request_queue:
		if r.get("purpose", -1) == RequestPurpose.MAP_DATA:
			return
	var url: String = '%s/map/get' % BASE_URL
	var headers: PackedStringArray = ['accept: application/json']
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.MAP_DATA,
		"method": HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	print("[APICalls] _requeue_map_after_auth(): map request requeued (queue_len=%d)." % _request_queue.size())

func _abort_map_request_for_auth():
	if _is_request_in_progress and _current_request_purpose == RequestPurpose.MAP_DATA:
		print("[APICalls] Aborting in-flight MAP_DATA request to prioritize auth flow.")
		if _http_request:
			_http_request.cancel_request()
		_is_request_in_progress = false
		_current_request_purpose = RequestPurpose.NONE
		# Requeue map for later after auth resolves
		_requeue_map_after_auth()
		# Give queue a turn
		call_deferred("_process_queue")


# Called when the HTTPRequest has completed.
func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	print("[APICalls] _on_request_completed() purpose=%s result=%d code=%d url=%s" % [RequestPurpose.keys()[_current_request_purpose], result, response_code, _last_requested_url])
	var request_purpose_at_start = _current_request_purpose
	# Global 401 handling (auth expired)
	if response_code == 401 and _auth_bearer_token != "" and request_purpose_at_start != RequestPurpose.AUTH_STATUS:
		print("[APICalls] Received 401 with auth token present. Treating as expired.")
		clear_auth_session_token()
		emit_signal("auth_expired")
		# Continue to normal error handling path below
	# PATCH transaction responses (purpose == NONE, but signal_name is set)
	if _current_request_purpose == RequestPurpose.NONE and _current_patch_signal_name != "":
		if result == HTTPRequest.RESULT_SUCCESS and (response_code >= 200 and response_code < 300):
			print("[APICalls][PATCH_TXN] signal=%s code=%d size=%d url=%s" % [_current_patch_signal_name, response_code, body.size(), _last_requested_url])
			var response_body_text = body.get_string_from_utf8()
			var preview = response_body_text.substr(0, 400)
			print("[APICalls][PATCH_TXN] body_preview=", preview)
			var json_response = JSON.parse_string(response_body_text)
			if json_response == null:
				# Accept plain-text bodies (e.g., UUID) by emitting the raw string
				print("[APICalls][PATCH_TXN] Non-JSON success body; emitting raw text for signal '%s'." % _current_patch_signal_name)
				emit_signal(_current_patch_signal_name, response_body_text)
			else:
				print("APICalls: Transaction '%s' successful. Emitting signal with data." % _current_patch_signal_name)
				emit_signal(_current_patch_signal_name, json_response)
			
			_complete_current_request()
			return
		else:
			# Optional compatibility fallback: if we tried new cargo route and got 404, retry legacy path once.
			if response_code == 404 and _last_requested_url.find("/vendor/cargo/") != -1 and (_current_patch_signal_name == "cargo_bought" or _current_patch_signal_name == "cargo_sold"):
				var legacy_url := _last_requested_url
				legacy_url = legacy_url.replace("/vendor/cargo/buy?", "/vendor/buy_cargo?")
				legacy_url = legacy_url.replace("/vendor/cargo/sell?", "/vendor/sell_cargo?")
				if legacy_url != _last_requested_url:
					print("[APICalls][PATCH_TXN][Fallback] 404 on new cargo route; retrying legacy URL=", legacy_url)
					# Mark current attempt ended and enqueue fallback
					_is_request_in_progress = false
					_current_request_purpose = RequestPurpose.NONE
					# Rebuild headers with auth
					var headers: PackedStringArray = ['accept: application/json']
					headers = _apply_auth_header(headers)
					_request_queue.push_front({
						"url": legacy_url,
						"headers": headers,
						"purpose": RequestPurpose.NONE,
						"method": HTTPClient.METHOD_PATCH,
						"body": "",
						"signal_name": _current_patch_signal_name
					})
					_process_queue()
					return
			print("[APICalls][PATCH_TXN] signal=%s FAILED result=%d code=%d url=%s" % [_current_patch_signal_name, result, response_code, _last_requested_url])
			var fail_body_text := body.get_string_from_utf8()
			var fail_preview := fail_body_text.substr(0, 400)
			print("[APICalls][PATCH_TXN] fail_body_preview=", fail_preview)
			# Try to parse JSON error for clearer feedback (e.g. FastAPI validation 'detail')
			var fail_json = JSON.parse_string(fail_body_text)
			if typeof(fail_json) == TYPE_DICTIONARY:
				var msg_parts: Array = []
				if fail_json.has("detail"):
					msg_parts.append(str(fail_json["detail"]))
				if fail_json.has("error"):
					msg_parts.append(str(fail_json["error"]))
				if msg_parts.size() > 0:
					var combined := "PATCH '" + _current_patch_signal_name + "' failed: " + "; ".join(msg_parts)
					emit_signal('fetch_error', combined)
			elif typeof(fail_json) == TYPE_ARRAY and fail_json.size() > 0:
				# FastAPI may return list of validation issues
				var first_issue = fail_json[0]
				if typeof(first_issue) == TYPE_DICTIONARY and first_issue.has("msg"):
					emit_signal('fetch_error', "PATCH '" + _current_patch_signal_name + "' failed: " + str(first_issue["msg"]))
			# Complete request now; we've surfaced error
			_complete_current_request()
			return

	# --- Handle fallback (ALL_CONVOYS) or other direct remote requests ---
	# This block is reached if:
	# 1. It was a fallback call (get_all_in_transit_convoys was called, so request_purpose_at_start is ALL_CONVOYS).
	# 2. It was a direct call to get_all_in_transit_convoys initially.
	# 3. It was a call to get_convoy_data (which has its own logic, not an Array response).

	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg_http_fallback = 'APICalls (_on_request_completed - Purpose: %s): Request failed with HTTPRequest result code: %s. URL: %s' % [RequestPurpose.keys()[request_purpose_at_start], result, _last_requested_url]
		printerr(error_msg_http_fallback)
		emit_signal('fetch_error', error_msg_http_fallback)
		_complete_current_request()
		return

	if not (response_code >= 200 and response_code < 300):
		var response_text = ""
		# Try to decode the body safely
		if body.size() > 0:
			# Try utf-8 first
			response_text = body.get_string_from_utf8()
			if response_text == "" and body.size() > 0:
				# Fallback: print as raw bytes if decoding failed
				response_text = str(body)
		else:
			response_text = "[No response body]"
		
		print("*** API ERROR RESPONSE BODY ***\n" + response_text + "\n*****************************")
		printerr("API error response code: ", response_code)
		printerr("API error response body: ", response_text)
		
		# Try to extract "detail" from JSON error
		var error_detail = ""
		var json_result = JSON.parse_string(response_text)
		if typeof(json_result) == TYPE_DICTIONARY and json_result.has("detail"):
			error_detail = json_result["detail"]
			emit_signal('fetch_error', error_detail)
		else:
			emit_signal('fetch_error', response_text)
		_complete_current_request()
		return

	# Successful HTTP response routing by purpose
	if request_purpose_at_start == RequestPurpose.ALL_CONVOYS or request_purpose_at_start == RequestPurpose.USER_CONVOYS:
		var response_body_text_convoys: String = body.get_string_from_utf8()
		var json_response_convoys = JSON.parse_string(response_body_text_convoys)
		if json_response_convoys == null:
			var error_msg_json_convoys = 'APICalls (_on_request_completed - Purpose: %s, Code: %s): Failed to parse JSON response. URL: %s' % [RequestPurpose.keys()[request_purpose_at_start], response_code, _last_requested_url]
			printerr(error_msg_json_convoys)
			printerr('  Raw Body: %s' % response_body_text_convoys)
			emit_signal('fetch_error', error_msg_json_convoys)
			_complete_current_request()
			return
		# Accept either an Array of convoys OR a wrapper Dictionary containing a convoys-like key
		if not (json_response_convoys is Array):
			if json_response_convoys is Dictionary:
				var extracted: Array = []
				var candidate_keys = ["convoys", "user_convoys", "convoys_in_transit"]
				for k in candidate_keys:
					if json_response_convoys.has(k) and json_response_convoys[k] is Array:
						extracted = json_response_convoys[k]
						print("APICalls: Extracted convoys array from wrapper key '%s' size=%d" % [k, extracted.size()])
						break
				if extracted.is_empty():
					var error_msg_type_convoys = 'APICalls (_on_request_completed - Purpose: %s, Code: %s): Expected convoy array or wrapper with convoys key, got type=%s. URL: %s' % [RequestPurpose.keys()[request_purpose_at_start], response_code, typeof(json_response_convoys), _last_requested_url]
					printerr(error_msg_type_convoys)
					emit_signal('fetch_error', error_msg_type_convoys)
					_complete_current_request()
					return
				json_response_convoys = extracted
			else:
				var error_msg_type_convoys2 = 'APICalls (_on_request_completed - Purpose: %s, Code: %s): Unexpected convoy response type=%s. URL: %s' % [RequestPurpose.keys()[request_purpose_at_start], response_code, typeof(json_response_convoys), _last_requested_url]
				printerr(error_msg_type_convoys2)
				emit_signal('fetch_error', error_msg_type_convoys2)
				_complete_current_request()
				return
		if not json_response_convoys.is_empty():
			var first_convoy2 = json_response_convoys[0]
			print("APICalls: First convoy keys: ", first_convoy2.keys())
			print("APICalls: First convoy vehicle_details_list: ", first_convoy2.get("vehicle_details_list", []))
			if first_convoy2.has("vehicle_details_list") and first_convoy2["vehicle_details_list"].size() > 0:
				print("APICalls: First vehicle keys: ", first_convoy2["vehicle_details_list"][0].keys())
		print("APICalls (_on_request_completed - %s): Successfully fetched %s convoy(s). URL: %s" % [RequestPurpose.keys()[request_purpose_at_start], json_response_convoys.size(), _last_requested_url])
		if not json_response_convoys.is_empty():
			print("  Sample Convoy 0: ID: %s" % [json_response_convoys[0].get("convoy_id", "N/A")])
		self.convoys_in_transit = json_response_convoys
		emit_signal('convoy_data_received', json_response_convoys)
		_complete_current_request()
		return

	if request_purpose_at_start == RequestPurpose.NONE: # Likely get_convoy_data (expects Dictionary)
		if _current_patch_signal_name == "":
			var response_body_text_single = body.get_string_from_utf8()
			var json_response_single = JSON.parse_string(response_body_text_single)
			if json_response_single == null or not json_response_single is Dictionary:
				printerr("APICalls (_on_request_completed - Purpose: NONE): Failed to parse convoy data as Dictionary. URL: %s" % _last_requested_url)
				emit_signal('fetch_error', "Failed to parse convoy data as Dictionary.")
			else:
				print("APICalls (_on_request_completed - Purpose: NONE): Successfully fetched single convoy data. URL: %s" % _last_requested_url)
				emit_signal('convoy_data_received', [json_response_single])
			_complete_current_request()
			return

	elif request_purpose_at_start == RequestPurpose.MAP_DATA:
		if body.is_empty():
			var error_msg_empty = 'APICalls (_on_request_completed - Purpose: MAP_DATA, Code: %s): Request successful, but the server returned an EMPTY response body. Cannot parse map data. URL: %s' % [response_code, _last_requested_url]
			printerr(error_msg_empty)
			emit_signal('fetch_error', error_msg_empty)
			_complete_current_request()
			return

		# The server sends custom binary data, not JSON. We need to deserialize it.
		var deserialized_map_data: Dictionary = preload("res://Scripts/System/tools.gd").deserialize_map_data(body)

		if deserialized_map_data.is_empty():
			var error_msg = "APICalls (_on_request_completed - MAP_DATA): Deserialization of binary map data failed. The data might be corrupt or the format has changed."
			printerr(error_msg)
			emit_signal('fetch_error', error_msg)
		else:
			var tiles_array = deserialized_map_data.get("tiles", [])
			print("APICalls (_on_request_completed - MAP_DATA): Successfully deserialized binary map data. Rows: %s, Cols: %s. URL: %s" % [tiles_array.size(), tiles_array[0].size() if not tiles_array.is_empty() else 0, _last_requested_url])
			emit_signal('map_data_received', deserialized_map_data)
		_complete_current_request()
		return
	
	elif request_purpose_at_start == RequestPurpose.USER_DATA:
		var response_body_text: String = body.get_string_from_utf8()
		var json_response = JSON.parse_string(response_body_text)

		if json_response == null:
			var error_msg_json = 'APICalls (_on_request_completed - USER_DATA): Failed to parse JSON. URL: %s' % _last_requested_url
			printerr(error_msg_json)
			printerr('  Raw Body: %s' % response_body_text)
			emit_signal('fetch_error', error_msg_json)
		elif not json_response is Dictionary:
			var error_msg_type = 'APICalls (_on_request_completed - USER_DATA): Expected Dictionary, got %s. URL: %s' % [typeof(json_response), _last_requested_url]
			printerr(error_msg_type)
			emit_signal('fetch_error', error_msg_type)
		else:
			# SUCCESS with user data
			print("APICalls (_on_request_completed - USER_DATA): Successfully fetched user data. URL: %s" % _last_requested_url)
			# print("  - User Money: %s" % json_response.get("money", "N/A"))
			emit_signal('user_data_received', json_response)

		_complete_current_request()
		return

	elif request_purpose_at_start == RequestPurpose.VENDOR_DATA:
		var response_body_text: String = body.get_string_from_utf8()
		var json_response = JSON.parse_string(response_body_text)

		if json_response == null or not json_response is Dictionary:
			var error_msg = 'APICalls (_on_request_completed - VENDOR_DATA): Failed to parse vendor data. URL: %s' % _last_requested_url
			printerr(error_msg)
			emit_signal('fetch_error', error_msg)
		else:
			print("APICalls (_on_request_completed - VENDOR_DATA): Successfully fetched vendor data. URL: %s" % _last_requested_url)
			emit_signal('vendor_data_received', json_response)

		_complete_current_request()
		return

	elif request_purpose_at_start == RequestPurpose.CARGO_DATA:
		var response_body_text: String = body.get_string_from_utf8()
		var json_response = JSON.parse_string(response_body_text)
		if json_response == null or not json_response is Dictionary:
			var error_msg = 'APICalls (_on_request_completed - CARGO_DATA): Failed to parse cargo data. URL: %s' % _last_requested_url
			printerr(error_msg)
			emit_signal('fetch_error', error_msg)
		else:
			print("APICalls (_on_request_completed - CARGO_DATA): Successfully fetched cargo data. URL: %s" % _last_requested_url)
			emit_signal('cargo_data_received', json_response)
		_complete_current_request()
		return

	elif request_purpose_at_start == RequestPurpose.WAREHOUSE_GET:
		var response_body_text_w: String = body.get_string_from_utf8()
		var json_w = JSON.parse_string(response_body_text_w)
		if json_w == null or not json_w is Dictionary:
			var error_msg_w = 'APICalls (_on_request_completed - WAREHOUSE_GET): Failed to parse warehouse data. URL: %s' % _last_requested_url
			printerr(error_msg_w)
			emit_signal('fetch_error', error_msg_w)
		else:
			print("APICalls (_on_request_completed - WAREHOUSE_GET): Successfully fetched warehouse data. URL: %s" % _last_requested_url)
			emit_signal('warehouse_received', json_w)
		_complete_current_request()
		return

	elif request_purpose_at_start == RequestPurpose.FIND_ROUTE:
		var response_body_text: String = body.get_string_from_utf8()
		var json_response = JSON.parse_string(response_body_text)

		if json_response == null:
			var error_msg_json = 'APICalls (_on_request_completed - FIND_ROUTE): Failed to parse JSON. URL: %s' % _last_requested_url
			printerr(error_msg_json)
			printerr('  Raw Body: %s' % response_body_text)
			emit_signal('fetch_error', error_msg_json)
		elif not json_response is Array:
			var error_msg_type = 'APICalls (_on_request_completed - FIND_ROUTE): Expected Array, got %s. URL: %s' % [typeof(json_response), _last_requested_url]
			printerr(error_msg_type)
			emit_signal('fetch_error', error_msg_type)
		else:
			# SUCCESS with route data
			print("APICalls (_on_request_completed - FIND_ROUTE): Successfully fetched %d route choices. URL: %s" % [json_response.size(), _last_requested_url])
			emit_signal('route_choices_received', json_response)

		_complete_current_request()
		return

	elif request_purpose_at_start == RequestPurpose.AUTH_URL:
		var response_body_text: String = body.get_string_from_utf8()
		print("[APICalls] AUTH_URL raw response code=%d body=%s" % [response_code, response_body_text])
		var json_response = JSON.parse_string(response_body_text)
		if json_response == null or not json_response is Dictionary:
			var error_msg = 'APICalls (_on_request_completed - AUTH_URL): Failed to parse JSON or unexpected type. URL: %s' % _last_requested_url
			printerr(error_msg)
			emit_signal('fetch_error', error_msg)
		else:
			print("[APICalls] (_on_request_completed - AUTH_URL): Got auth URL: %s" % json_response.get("url", "<missing>"))
			emit_signal('auth_url_received', json_response)
			if json_response.has("state"):
				start_auth_poll(str(json_response["state"]))
		_complete_current_request()
		return

	elif request_purpose_at_start == RequestPurpose.AUTH_TOKEN:
		var response_body_text: String = body.get_string_from_utf8()
		var json_response = JSON.parse_string(response_body_text)

		if json_response == null or not json_response is Dictionary:
			print("APICalls (_on_request_completed - AUTH_TOKEN): Non-JSON or unexpected response; wrapping as {raw}.")
			emit_signal('auth_token_received', {"raw": response_body_text})
		else:
			print("APICalls (_on_request_completed - AUTH_TOKEN): Token exchange successful.")
			emit_signal('auth_token_received', json_response)

		_complete_current_request()
		return

	elif request_purpose_at_start == RequestPurpose.AUTH_STATUS:
		var response_body_text: String = body.get_string_from_utf8()
		print('[APICalls][AUTH_STATUS] raw body=', response_body_text)
		var json_response = JSON.parse_string(response_body_text)
		if json_response == null or not json_response is Dictionary:
			printerr('APICalls (AUTH_STATUS): Failed to parse status JSON.')
			_auth_poll.active = false
			_login_in_progress = false
			emit_signal('auth_poll_finished', false)
			emit_signal('fetch_error', 'Auth status parse error')
		else:
			var status: String = str(json_response.get('status', 'pending'))
			print('[APICalls][AUTH_STATUS] attempt=%d/%d status=%s state=%s' % [_auth_poll.attempt, _auth_poll.max_attempts, status, _auth_poll.state])
			emit_signal('auth_status_update', status)
			if status == 'pending':
				_auth_poll.attempt += 1
				if _auth_poll.attempt >= _auth_poll.max_attempts:
					_auth_poll.active = false
					_login_in_progress = false
					emit_signal('auth_poll_finished', false)
					emit_signal('fetch_error', 'Authentication timed out.')
				else:
					_schedule_next_auth_status_poll()
			elif status == 'complete':
				_auth_poll.active = false
				_login_in_progress = false
				var token: String = str(json_response.get('session_token', ''))
				print('[APICalls][AUTH_STATUS] complete received; token length=%d' % token.length())
				if token.is_empty():
					emit_signal('auth_poll_finished', false)
					emit_signal('fetch_error', 'Auth complete but no session_token')
				else:
					set_auth_session_token(token)
					emit_signal('auth_session_received', token)
					emit_signal('auth_poll_finished', true)
					# RESET and FORCE resolve of user id (previous failed attempt set flag true)
					_auth_me_requested = false
					_auth_me_resolve_attempts = 0
					print('[APICalls][AUTH_STATUS] Forcing /auth/me resolution now that token is set.')
					resolve_current_user_id(true)
			else:
				_auth_poll.active = false
				_login_in_progress = false
				var err_msg := str(json_response.get('error', 'Authentication failed'))
				printerr('[APICalls][AUTH_STATUS] failure status=%s error=%s' % [status, err_msg])
				emit_signal('auth_poll_finished', false)
				emit_signal('fetch_error', err_msg)
		_complete_current_request()
		return

	elif request_purpose_at_start == RequestPurpose.AUTH_ME:
		var response_body_text: String = body.get_string_from_utf8()
		var json_response = JSON.parse_string(response_body_text)
		if json_response == null or not json_response is Dictionary:
			printerr('[APICalls][AUTH_ME] Failed to parse /auth/me response: ', response_body_text)
		else:
			var uid_str: String = str(json_response.get('user_id', ''))
			if not uid_str.is_empty() and _is_valid_uuid(uid_str):
				print('[APICalls][AUTH_ME] Resolved user id (attempt %d): %s' % [_auth_me_resolve_attempts, uid_str])
				_auth_me_resolve_attempts = 0
				emit_signal('user_id_resolved', uid_str)
			else:
				print('[APICalls][AUTH_ME] Missing/invalid user_id (attempt %d/%d). Body=%s' % [_auth_me_resolve_attempts, AUTH_ME_MAX_ATTEMPTS, response_body_text])
				if _auth_me_resolve_attempts < AUTH_ME_MAX_ATTEMPTS:
					_auth_me_requested = false
					var retry_timer := get_tree().create_timer(AUTH_ME_RETRY_INTERVAL, true)
					retry_timer.timeout.connect(func(): resolve_current_user_id(true))
				else:
					printerr('[APICalls][AUTH_ME] Gave up resolving user id after %d attempts.' % AUTH_ME_MAX_ATTEMPTS)
		_complete_current_request()
		return
func _on_map_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	print('[APICalls][MAP][Parallel] completed result=%d code=%d size=%d' % [result, response_code, body.size()])
	if result != HTTPRequest.RESULT_SUCCESS:
		printerr('[APICalls][MAP] Parallel map request failed (result=%d).' % result)
		emit_signal('fetch_error', 'Map request failed (result)')
		return
	if not (response_code >= 200 and response_code < 300):
		var body_txt := body.get_string_from_utf8()
		printerr('[APICalls][MAP] HTTP %d for map request. Body preview=%s' % [response_code, body_txt.left(200)])
		if response_code == 401 and _auth_bearer_token != '':
			print('[APICalls][MAP] 401 received; clearing auth and emitting auth_expired.')
			clear_auth_session_token()
			emit_signal('auth_expired')
		else:
			emit_signal('fetch_error', 'Map request HTTP %d' % response_code)
		return
	if body.is_empty():
		printerr('[APICalls][MAP] Empty body for map response.')
		emit_signal('fetch_error', 'Empty map response')
		return
	var tools := preload('res://Scripts/System/tools.gd')
	var deserialized: Dictionary = tools.deserialize_map_data(body)
	if deserialized.is_empty() or not deserialized.has('tiles'):
		printerr('[APICalls][MAP] Deserialization returned empty/invalid dict.')
		emit_signal('fetch_error', 'Map deserialization failed')
		return
	print('[APICalls][MAP] Deserialized map: rows=%d cols=%d' % [deserialized.tiles.size(), deserialized.tiles[0].size() if deserialized.tiles.size() > 0 else 0])
	emit_signal('map_data_received', deserialized)
func _decode_jwt_expiry(token: String) -> int:
	if token == "":
		return 0
	var parts = token.split('.')
	if parts.size() < 2:
		return 0
	var payload_b64: String = parts[1]
	payload_b64 = payload_b64.replace('-', '+').replace('_', '/')
	while payload_b64.length() % 4 != 0:
		payload_b64 += "="
	var raw_bytes := Marshalls.base64_to_raw(payload_b64)
	var json_text := raw_bytes.get_string_from_utf8()
	var payload = JSON.parse_string(json_text)
	if typeof(payload) == TYPE_DICTIONARY and payload.has('exp'):
		return int(payload['exp'])
	return 0

# Schedule next auth status poll helper
func _schedule_next_auth_status_poll():
	if not _auth_poll.active:
		return
	var delay: float = max(0.2, float(_auth_poll.interval))
	var t := get_tree().create_timer(delay, true)
	t.timeout.connect(func(): _enqueue_auth_status_request(_auth_poll.state))
