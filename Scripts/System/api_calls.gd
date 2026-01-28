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

# --- Vendor Signals (transport-level only) ---
# Phase 4: Removed UI-facing vendor transaction signals (buy/sell). Services drive refreshes.
@warning_ignore("unused_signal")
signal user_metadata_updated(result: Dictionary)
signal vendor_data_received(vendor_data: Dictionary)
signal part_compatibility_checked(payload: Dictionary) # { vehicle_id, part_id, data }
signal cargo_data_received(cargo: Dictionary)
@warning_ignore("unused_signal")
signal vehicle_data_received(vehicle_data: Dictionary)

# Transaction signals (restored for UI feedback)
signal cargo_bought(result: Dictionary)
signal cargo_sold(result: Dictionary)
signal vehicle_bought(result: Dictionary)
signal vehicle_sold(result: Dictionary)
signal resource_bought(result: Dictionary)
signal resource_sold(result: Dictionary)

# --- Journey Planning Signals ---
signal route_choices_received(routes: Array)
signal convoy_created(convoy: Dictionary) # Restored for service-driven refresh

# --- Warehouse Signals ---
signal warehouse_received(warehouse_data: Dictionary)

var BASE_URL: String = 'http://127.0.0.1:1337' # default (overridden via config/env)
# Allow override via configuration and environment (cannot be const due to runtime lookup)
func _init():
	_load_base_url_from_config()
	if OS.has_environment('DF_API_BASE_URL'):
		BASE_URL = OS.get_environment('DF_API_BASE_URL')
		print("[APICalls] BASE_URL overridden by env: ", BASE_URL)
	else:
		print("[APICalls] BASE_URL from config: ", BASE_URL)

func _load_base_url_from_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://config/app_config.cfg")
	if err != OK:
		return
	# Direct base_url wins if provided; otherwise use active_env mapping
	var direct := String(cfg.get_value("api", "base_url", ""))
	if direct != "":
		BASE_URL = direct
		return
	var active_env := String(cfg.get_value("api", "active_env", "dev")).to_lower()
	var dev := String(cfg.get_value("api", "base_url_dev", BASE_URL))
	var prod := String(cfg.get_value("api", "base_url_prod", BASE_URL))
	match active_env:
		"prod":
			BASE_URL = prod
		_:
			BASE_URL = dev

var current_user_id: String = "" # To store the logged-in user's ID
var _http_request: Node
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
var _disable_request_timeouts_for_tests: bool = false
const REQUEST_TIMEOUT_SECONDS := {
	RequestPurpose.MAP_DATA: 5.0,
	RequestPurpose.AUTH_URL: 5.0,
	RequestPurpose.AUTH_STATUS: 5.0,
	RequestPurpose.AUTH_ME: 5.0,
	RequestPurpose.CARGO_DATA: 5.0,
	RequestPurpose.WAREHOUSE_GET: 5.0,
}

# --- Logging helpers (gate prints behind Logger) ---
func _log_debug(msg: String) -> void:
	var logger := get_node_or_null("/root/Logger") if is_inside_tree() else null
	if is_instance_valid(logger) and logger.has_method("debug"):
		logger.debug(msg)
	else:
		print(msg)

func _log_info(msg: String) -> void:
	var logger := get_node_or_null("/root/Logger") if is_inside_tree() else null
	if is_instance_valid(logger) and logger.has_method("info"):
		logger.info(msg)
	else:
		print(msg)


func set_disable_request_timeouts_for_tests(disabled: bool) -> void:
	_disable_request_timeouts_for_tests = disabled


func set_http_request_for_tests(requester: Node) -> void:
	# Test-only helper: allow unit tests to inject a stub HTTPRequest.
	# Keeps runtime behavior unchanged when not used.
	if requester == null:
		return
	if is_instance_valid(_http_request):
		if _http_request.is_connected("request_completed", Callable(self, "_on_request_completed")):
			_http_request.disconnect("request_completed", Callable(self, "_on_request_completed"))
		# Keep the old node if it was created by _ready(); tests may be running in a scene tree.
	_http_request = requester
	if not is_ancestor_of(_http_request):
		add_child(_http_request)
	if _http_request.is_connected("request_completed", Callable(self, "_on_request_completed")):
		_http_request.disconnect("request_completed", Callable(self, "_on_request_completed"))
	_http_request.connect("request_completed", Callable(self, "_on_request_completed"))

var _probe_stalled_count: int = 0
var _auth_me_resolve_attempts: int = 0
const AUTH_ME_MAX_ATTEMPTS: int = 5
const AUTH_ME_RETRY_INTERVAL: float = 0.75

# --- Diagnostics (queue + txn tracing) ---
var _client_txn_seq: int = 0
var _current_client_txn_id: int = -1
var _current_request_start_ms: int = 0
var _pending_vendor_refresh: Dictionary = {} # vendor_id -> true
var _inflight_vendor_id: String = ""

func _extract_query_param(url: String, key: String) -> String:
	var q_idx := url.find("?")
	if q_idx == -1:
		return ""
	var query := url.substr(q_idx + 1)
	var parts := query.split("&")
	for p in parts:
		var kv := p.split("=")
		if kv.size() >= 2 and String(kv[0]) == key:
			return String(kv[1]).uri_decode()
	return ""

func _diag_enqueue(tag: String, details: Dictionary) -> void:
	# Stamp enqueue time and client txn id for tracing if it's a PATCH or interesting GET
	var qlen_before := _request_queue.size()
	_client_txn_seq += 1
	details["client_txn_id"] = _client_txn_seq
	details["enqueued_at_ms"] = Time.get_ticks_msec()
	details["debug_tag"] = tag
	var method_i := int(details.get("method", HTTPClient.METHOD_GET))
	var url_s := String(details.get("url", ""))
	var is_patch_txn := (method_i == HTTPClient.METHOD_PATCH and String(details.get("signal_name", "")) != "")
	_log_debug("[APICalls][Enqueue] tag=" + tag + " id=" + str(_client_txn_seq) + " method=" + str(method_i) + " qlen_before=" + str(qlen_before) + " in_progress=" + str(_is_request_in_progress) + " url=" + url_s + " prio_patch=" + str(is_patch_txn))
	print("[APICalls][Debug] Enqueuing request tag=%s. Queue size: %d" % [tag, _request_queue.size()])
	if is_patch_txn:
		_request_queue.push_front(details)
	else:
		_request_queue.append(details)
	_process_queue()

func _ready() -> void:
	# Ensure this autoload keeps processing while login screen pauses the tree
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log_info('[APICalls] _ready(): process_mode set to ALWAYS (was paused tree workaround)')
	# Create an HTTPRequest node and add it as a child.
	# This node will handle the actual network communication.
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	# Reconnect without .bind() so callback signature matches exactly
	if _http_request.is_connected("request_completed", Callable(self, "_on_request_completed")):
		_http_request.disconnect("request_completed", Callable(self, "_on_request_completed"))
	_http_request.connect("request_completed", Callable(self, "_on_request_completed"))
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
	# Auto-resolve user if we have a still-valid token
	if is_auth_token_valid():
		print("[APICalls] Auto-login attempt with persisted session token.")
		resolve_current_user_id()
	# Initial data requests (map/user/convoys) are triggered by the post-login bootstrap
	# (e.g., GameScreenManager / services).

func set_user_id(p_user_id: String) -> void:
	current_user_id = p_user_id
	# print("APICalls: User ID set to: ", current_user_id)

# --- Auth helpers ---
func set_auth_session_token(token: String) -> void:
	_auth_bearer_token = token
	_auth_token_expiry = _decode_jwt_expiry(token)
	_log_info("[APICalls] Auth session set (len=" + str(token.length()) + ", exp=" + str(_auth_token_expiry) + ")")
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
	_log_info("[APICalls] Auth session cleared.")

func _load_auth_session_token() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SESSION_CFG_PATH)
	if err != OK:
		return
	var token: String = String(cfg.get_value("auth", "session_token", ""))
	var expiry: int = int(cfg.get_value("auth", "token_expiry", 0))
	if token != "":
		_auth_bearer_token = token
		_auth_token_expiry = expiry
		print("[APICalls] Loaded persisted session token (len=%d, exp=%d)" % [token.length(), expiry])

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
func is_auth_token_valid() -> bool:
	return _auth_bearer_token != "" and not _is_auth_token_expired()

func _is_auth_token_expired() -> bool:
	if _auth_bearer_token == "":
		return false
	return _auth_token_expiry <= Time.get_unix_time_from_system()

func logout() -> void:
	clear_auth_session_token()
	emit_signal("fetch_error", "Logged out.")

func get_auth_url(_provider: String = "") -> void:
	# Abort map fetch if it's blocking
	_abort_map_request_for_auth()
	if _login_in_progress or _auth_poll.active:
		print("[APICalls] Ignoring get_auth_url; login already in progress.")
		return
	_log_debug("[APICalls] get_auth_url(): queueing AUTH_URL request (provider=" + _provider + "). Current queue length before append=" + str(_request_queue.size()))
	var url := "%s/auth/discord/url" % BASE_URL
	var headers: PackedStringArray = ['accept: application/json']
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.AUTH_URL,
		"method": HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	_log_debug("[APICalls] get_auth_url(): appended. Queue length now=" + str(_request_queue.size()) + " in_progress=" + str(_is_request_in_progress))
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
	_log_info("[APICalls] Starting auth status poll for state=" + state)
	_emit_hub_auth_state("pending")
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
		_log_debug('[APICalls] resolve_current_user_id(): forced retry attempt ' + str(_auth_me_resolve_attempts + 1))
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
	_diag_enqueue("get_convoy_data", request_details)

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
	_log_info('[APICalls][MAP] Dispatching parallel map request: ' + url)
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
	_diag_enqueue("get_user_data", request_details)

# Force a user data refresh regardless of the one-time guard. Useful after creation events.
func refresh_user_data(p_user_id: String) -> void:
	if not _is_valid_uuid(p_user_id):
		var error_msg = "APICalls (refresh_user_data): Provided ID '%s' is not a valid UUID." % p_user_id
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
	_log_debug('[APICalls] refresh_user_data(): enqueue URL=' + url)
	_diag_enqueue("refresh_user_data", request_details)

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
	var logger := get_node_or_null('/root/Logger') if is_inside_tree() else null
	if is_instance_valid(logger) and logger.has_method('info'):
		logger.info("APICalls.enqueue USER_CONVOYS url=%s", url)
	_diag_enqueue("get_user_convoys", request_details)

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
	var logger := get_node_or_null('/root/Logger') if is_inside_tree() else null
	if is_instance_valid(logger) and logger.has_method('info'):
		logger.info("APICalls.enqueue ALL_CONVOYS url=%s", url)
	_diag_enqueue("get_all_in_transit_convoys", request_details)




func update_user_metadata(user_id: String, metadata: Dictionary) -> void:
	if user_id.is_empty() or not _is_valid_uuid(user_id):
		printerr("APICalls (update_user_metadata): invalid user_id %s" % user_id)
		return

	# Per API documentation, the endpoint is /user/update_metadata and it takes
	# the user_id as a query parameter and the new metadata object in the body.
	var url := "%s/user/update_metadata?user_id=%s" % [BASE_URL, user_id]
	var headers: PackedStringArray = ['accept: application/json', 'content-type: application/json']
	headers = _apply_auth_header(headers)
	
	# The body should be the metadata dictionary itself, not wrapped in another object.
	var body_json := JSON.stringify(metadata)
	
	_diag_enqueue("update_user_metadata", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": body_json,
		"signal_name": "user_metadata_updated"
	})

# --- Vendor / Transaction Requests (added) ---
func request_vendor_data(vendor_id: String) -> void:
	if vendor_id.is_empty() or not _is_valid_uuid(vendor_id):
		printerr("APICalls (request_vendor_data): invalid vendor_id %s" % vendor_id)
		return
	# Coalesce duplicate requests for the same vendor_id
	if _pending_vendor_refresh.has(vendor_id) or (_is_request_in_progress and _current_request_purpose == RequestPurpose.VENDOR_DATA and _inflight_vendor_id == vendor_id):
		print("[APICalls][Coalesce] Skip duplicate VENDOR_DATA for vendor_id=", vendor_id)
		return
	var url := "%s/vendor/get?vendor_id=%s" % [BASE_URL, vendor_id]
	# Optional user_id for scenario logging purposes.
	if current_user_id != "" and _is_valid_uuid(current_user_id):
		url += "&user_id=%s" % current_user_id
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	# Remove any queued older VENDOR_DATA for the same vendor
	for i in range(_request_queue.size() - 1, -1, -1):
		var r: Dictionary = _request_queue[i]
		if r.get("purpose", -1) == RequestPurpose.VENDOR_DATA:
			var r_vid := String(r.get("vendor_id", ""))
			if r_vid == "":
				r_vid = _extract_query_param(String(r.get("url", "")), "vendor_id")
			if r_vid == vendor_id:
				_request_queue.remove_at(i)
	_pending_vendor_refresh[vendor_id] = true
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.VENDOR_DATA,
		"method": HTTPClient.METHOD_GET,
		"vendor_id": vendor_id
	}
	_diag_enqueue("request_vendor_data", request_details)

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
	_diag_enqueue("get_cargo", request_details)

# --- Vehicle detail by ID ---
func get_vehicle_data(vehicle_id: String) -> void:
	if vehicle_id.is_empty() or not _is_valid_uuid(vehicle_id):
		printerr("APICalls (get_vehicle_data): invalid vehicle_id %s" % vehicle_id)
		return
	var url := "%s/vehicle/get?vehicle_id=%s" % [BASE_URL, vehicle_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_diag_enqueue("get_vehicle_data", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_GET,
		"signal_name": "vehicle_data_received"
	})

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
		var key_type := typeof(k)
		var key_str := ""
		match key_type:
			TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
				key_str = str(k)
			_:
				print("[APICalls][Diag][_build_query] Non-primitive key encountered typeof=", key_type, " value=", k)
				key_str = str(k)
		var val_raw = params.get(k, "")
		var val_str := ""
		var val_type := typeof(val_raw)
		match val_type:
			TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
				val_str = str(val_raw)
			_:
				# Avoid hitting String(<complex>) pitfalls; log and stringify
				print("[APICalls][Diag][_build_query] Non-primitive value typeof=", val_type, " key=", key_str, " value=", val_raw)
				val_str = str(val_raw)
		var enc_key := key_str.uri_encode()
		var enc_val := val_str.uri_encode()
		parts.append("%s=%s" % [enc_key, enc_val])
	return "?" + "&".join(parts)

func warehouse_expand(params: Dictionary) -> void:
	_log_debug("[APICalls][warehouse_expand] invoked params=" + str(params) + " types=" + str(_diagnose_param_types(params)))
	var wid_raw = params.get("warehouse_id", "")
	var expand_type_raw = params.get("expand_type", "")
	var amount_raw = params.get("amount", 1)
	# Accept alt key names defensively
	if expand_type_raw == "" and params.has("type"):
		expand_type_raw = params.get("type")
	if expand_type_raw == "" and params.has("expand"):
		expand_type_raw = params.get("expand")
	if amount_raw == 1 and params.has("units"):
		amount_raw = params.get("units")
	var wid := str(wid_raw)
	var expand_type := str(expand_type_raw)
	var amount := str(amount_raw)
	if wid == "":
		printerr("[APICalls][warehouse_expand] Missing warehouse_id in params raw=", wid_raw)
		return
	if expand_type == "":
		printerr("[APICalls][warehouse_expand] Missing expand_type in params raw=", expand_type_raw)
		return
	var query_dict := {"warehouse_id": wid, "expand_type": expand_type, "amount": amount, "type": expand_type, "expand": expand_type}
	_log_debug("[APICalls][warehouse_expand] Prepared query wid=" + wid + " expand_type=" + expand_type + " amount=" + amount + " final_query_dict=" + str(query_dict))
	var url := "%s/warehouse/expand%s" % [BASE_URL, _build_query(query_dict)]
	_log_debug("[APICalls][warehouse_expand] Enqueue URL=" + url)
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_diag_enqueue("warehouse_expand", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
	})
	_log_debug("[APICalls][warehouse_expand] Queue length now=" + str(_request_queue.size()))

# Alternative expansion using JSON body (fallback if query version shows no effect)
func warehouse_expand_json(params: Dictionary) -> void:
	_log_debug("[APICalls][warehouse_expand_json] invoked params=" + str(params) + " types=" + str(_diagnose_param_types(params)))
	var wid_raw = params.get("warehouse_id", "")
	var expand_type_raw = params.get("expand_type", params.get("type", params.get("expand", "")))
	var amount_raw = params.get("amount", params.get("units", 1))
	var wid := str(wid_raw)
	var expand_type := str(expand_type_raw)
	var amount := int(amount_raw)
	if wid == "" or not _is_valid_uuid(wid):
		printerr("[APICalls][warehouse_expand_json] Missing/invalid warehouse_id=", wid)
		return
	if expand_type == "":
		printerr("[APICalls][warehouse_expand_json] Missing expand_type")
		return
	var url := "%s/warehouse/expand" % BASE_URL
	var headers: PackedStringArray = ['accept: application/json', 'content-type: application/json']
	headers = _apply_auth_header(headers)
	var body_dict := {"warehouse_id": wid, "expand_type": expand_type, "amount": amount}
	var body_json := JSON.stringify(body_dict)
	_diag_enqueue("warehouse_expand_json", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": body_json,
	})
	_log_debug("[APICalls][warehouse_expand_json] Enqueued JSON PATCH url=" + url + " body=" + body_json)

# Preferred v2 expansion using explicit field names cargo_capacity_upgrade / vehicle_capacity_upgrade
func warehouse_expand_v2(warehouse_id: String, cargo_units: int, vehicle_units: int) -> void:
	# Always send both fields (0 where not upgrading) so backend can't misinterpret omission.
	if warehouse_id == "" or not _is_valid_uuid(warehouse_id):
		printerr("[APICalls][warehouse_expand_v2] Invalid warehouse_id=", warehouse_id)
		return
	var cargo_u := int(max(0, cargo_units))
	var vehicle_u := int(max(0, vehicle_units))
	_log_debug("[APICalls][warehouse_expand_v2] wid=" + warehouse_id + " cargo_units=" + str(cargo_u) + " vehicle_units=" + str(vehicle_u))
	var q_params := {
		"warehouse_id": warehouse_id,
		"cargo_capacity_upgrade": str(cargo_u),
		"vehicle_capacity_upgrade": str(vehicle_u)
	}
	var url_query := _build_query(q_params)
	var url := "%s/warehouse/expand%s" % [BASE_URL, url_query]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_diag_enqueue("warehouse_expand_v2", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
	})
	_log_debug("[APICalls][warehouse_expand_v2] Enqueued URL=" + url)
	# Also enqueue JSON fallback immediately (optional) if first returns no change we can trigger manually
	var body_dict := {
		"warehouse_id": warehouse_id,
		"cargo_capacity_upgrade": cargo_u,
		"vehicle_capacity_upgrade": vehicle_u
	}
	var body_json := JSON.stringify(body_dict)
	_diag_enqueue("warehouse_expand_v2_fallback_json", {
		"url": "%s/warehouse/expand" % BASE_URL,
		"headers": _apply_auth_header(['accept: application/json', 'content-type: application/json']),
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": body_json,
	})
	_log_debug("[APICalls][warehouse_expand_v2] (Queued JSON fallback second) body=" + body_json + " queue_len=" + str(_request_queue.size()))

func _diagnose_param_types(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		out[str(k)] = typeof(d.get(k))
	return out

func warehouse_cargo_store(params: Dictionary) -> void:
	var url := "%s/warehouse/cargo/store%s" % [BASE_URL, _build_query(params)]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_diag_enqueue("warehouse_cargo_store", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
	})

func warehouse_cargo_retrieve(params: Dictionary) -> void:
	var url := "%s/warehouse/cargo/retrieve%s" % [BASE_URL, _build_query(params)]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_diag_enqueue("warehouse_cargo_retrieve", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
	})

func warehouse_vehicle_store(params: Dictionary) -> void:
	var url := "%s/warehouse/vehicle/store%s" % [BASE_URL, _build_query(params)]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_diag_enqueue("warehouse_vehicle_store", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
	})

func warehouse_vehicle_retrieve(params: Dictionary) -> void:
	var url := "%s/warehouse/vehicle/retrieve%s" % [BASE_URL, _build_query(params)]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_diag_enqueue("warehouse_vehicle_retrieve", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
	})

func warehouse_convoy_spawn(params: Dictionary) -> void:
	# Normalize param naming: prefer 'new_convoy_name' per latest API spec.
	# If only legacy 'name' provided, map it to 'new_convoy_name'. If both provided, keep new_convoy_name.
	var effective: Dictionary = params.duplicate()
	if not effective.has("new_convoy_name") and effective.has("name"):
		effective["new_convoy_name"] = effective.get("name", "")
	# Avoid sending both if server rejects duplicates; remove 'name' now.
	if effective.has("name"):
		effective.erase("name")
	var url := "%s/warehouse/convoy/spawn%s" % [BASE_URL, _build_query(effective)]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	print("[APICalls][Enqueue] warehouse_convoy_spawn url=", url, " queue_len_before=", _request_queue.size(), " in_progress=", _is_request_in_progress)
	_diag_enqueue("warehouse_convoy_spawn", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
	})
	print("[APICalls][Enqueue] warehouse_convoy_spawn appended queue_len_after=", _request_queue.size())

# TEMP diagnostic: bypass queue to see if HTTP call itself works
func warehouse_convoy_spawn_direct(params: Dictionary) -> void:
	var effective: Dictionary = params.duplicate()
	if not effective.has("new_convoy_name") and effective.has("name"):
		effective["new_convoy_name"] = effective.get("name", "")
	if effective.has("name"):
		effective.erase("name")
	var url := "%s/warehouse/convoy/spawn%s" % [BASE_URL, _build_query(effective)]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	print("[APICalls][Direct] warehouse_convoy_spawn_direct url=", url)
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result:int, code:int, _h:PackedStringArray, body:PackedByteArray):
		print("[APICalls][Direct] completion result=", result, " code=", code, " bytes=", body.size())
		var text := body.get_string_from_utf8()
		print("[APICalls][Direct] body=", text.substr(0, 300))
		# No direct domain signal emissions; services will refresh warehouse state.
	)
	var err := req.request(url, headers, HTTPClient.METHOD_PATCH, "")
	if err != OK:
		printerr("[APICalls][Direct] request failed err=", err)

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
	_log_debug("[PartCompatAPI] RESPONSE payload=" + str(payload))
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
	print("[APICalls][Debug] buy_cargo called. vendor=%s convoy=%s cargo=%s qty=%d" % [vendor_id, convoy_id, cargo_id, quantity])
	if vendor_id.is_empty() or convoy_id.is_empty() or cargo_id.is_empty():
		printerr("APICalls (buy_cargo): missing id(s)")
		return
	# New route shape (consistent with resource/vehicle routes): /vendor/cargo/buy
	var url := "%s/vendor/cargo/buy?vendor_id=%s&convoy_id=%s&cargo_id=%s&quantity=%d" % [BASE_URL, vendor_id, convoy_id, cargo_id, quantity]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_diag_enqueue("buy_cargo", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "cargo_bought"
	})

func sell_cargo(vendor_id: String, convoy_id: String, cargo_id: String, quantity: int) -> void:
	if vendor_id.is_empty() or convoy_id.is_empty() or cargo_id.is_empty():
		printerr("APICalls (sell_cargo): missing id(s)")
		return
	# New route shape: /vendor/cargo/sell
	var url := "%s/vendor/cargo/sell?vendor_id=%s&convoy_id=%s&cargo_id=%s&quantity=%d" % [BASE_URL, vendor_id, convoy_id, cargo_id, quantity]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_diag_enqueue("sell_cargo", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "cargo_sold"
	})

func buy_vehicle(vendor_id: String, convoy_id: String, vehicle_id: String) -> void:
	if vendor_id.is_empty() or convoy_id.is_empty() or vehicle_id.is_empty():
		printerr("APICalls (buy_vehicle): missing id(s)")
		return
	# Use new route shape consistent with others: /vendor/vehicle/buy
	var url := "%s/vendor/vehicle/buy?vendor_id=%s&convoy_id=%s&vehicle_id=%s" % [BASE_URL, vendor_id, convoy_id, vehicle_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_diag_enqueue("buy_vehicle", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "vehicle_bought"
	})

func sell_vehicle(vendor_id: String, convoy_id: String, vehicle_id: String) -> void:
	if vendor_id.is_empty() or convoy_id.is_empty() or vehicle_id.is_empty():
		printerr("APICalls (sell_vehicle): missing id(s)")
		return
	# Use new route shape consistent with others: /vendor/vehicle/sell
	var url := "%s/vendor/vehicle/sell?vendor_id=%s&convoy_id=%s&vehicle_id=%s" % [BASE_URL, vendor_id, convoy_id, vehicle_id]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_diag_enqueue("sell_vehicle", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "vehicle_sold"
	})

func buy_resource(vendor_id: String, convoy_id: String, resource_type: String, quantity: float) -> void:
	# Backend route: PATCH /vendor/resource/buy with all fields in query params
	if vendor_id.is_empty() or convoy_id.is_empty() or resource_type.is_empty() or quantity <= 0:
		printerr("APICalls (buy_resource): invalid args")
		return
	var qty_str := String.num(quantity, 3).rstrip("0").rstrip(".")
	var url := "%s/vendor/resource/buy?vendor_id=%s&convoy_id=%s&resource_type=%s&quantity=%s" % [BASE_URL, vendor_id, convoy_id, resource_type, qty_str]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_log_info("[APICalls][buy_resource] PATCH url=" + url + " (query only)")
	_diag_enqueue("buy_resource", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "resource_bought"
	})

func sell_resource(vendor_id: String, convoy_id: String, resource_type: String, quantity: float) -> void:
	# Backend route: PATCH /vendor/resource/sell with all fields in query params
	if vendor_id.is_empty() or convoy_id.is_empty() or resource_type.is_empty() or quantity <= 0:
		printerr("APICalls (sell_resource): invalid args")
		return
	var qty_str := String.num(quantity, 3).rstrip("0").rstrip(".")
	var url := "%s/vendor/resource/sell?vendor_id=%s&convoy_id=%s&resource_type=%s&quantity=%s" % [BASE_URL, vendor_id, convoy_id, resource_type, qty_str]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	_log_info("[APICalls][sell_resource] PATCH url=" + url + " (query only)")
	_diag_enqueue("sell_resource", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "resource_sold"
	})

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
	_log_info("[APICalls][attach_vehicle_part] PATCH url=" + url + " auth_present=" + str(_auth_bearer_token != ""))
	_diag_enqueue("attach_vehicle_part", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
	})

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
	_log_info("[APICalls][detach_vehicle_part] PATCH url=" + url + " auth_present=" + str(_auth_bearer_token != ""))
	_diag_enqueue("detach_vehicle_part", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
	})

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
	_log_info("[APICalls][add_vehicle_part] PATCH url=" + url + " auth_present=" + str(_auth_bearer_token != ""))
	_diag_enqueue("add_vehicle_part", {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
	})

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
	_log_info('[APICalls][FIND_ROUTE] Sending POST (query params) url=%s' % url)
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
	_log_info('[APICalls][SEND_JOURNEY] PATCH (query params) %s auth_present=%s' % [url, str(has_auth)])
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "", # No body; params in query string
		"signal_name": "" # Phase 4: no domain-level signal emitted; services will refresh
	}
	_diag_enqueue("send_convoy", request_details)

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
	_log_info('[APICalls][CANCEL_JOURNEY] PATCH (query params) %s auth_present=%s' % [url, str(_auth_bearer_token != "")])
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE,
		"method": HTTPClient.METHOD_PATCH,
		"body": "",
		"signal_name": "" # Phase 4: no domain-level signal emitted; services will refresh
	}
	_diag_enqueue("cancel_convoy_journey", request_details)

func _on_route_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_log_info('[APICalls][FIND_ROUTE] request_completed result=%d code=%d bytes=%d' % [result, response_code, body.size()])
	if result != HTTPRequest.RESULT_SUCCESS:
		var err_msg = 'APICalls (_on_route_request_completed): Network error result=%d code=%d' % [result, response_code]
		printerr(err_msg)
		emit_signal('fetch_error', err_msg)
		return
	var response_body_text: String = body.get_string_from_utf8()
	_log_debug('[APICalls][FIND_ROUTE] Raw body: ' + response_body_text)
	var json_response = JSON.parse_string(response_body_text)
	if json_response == null:
		var error_msg_json = 'APICalls (_on_route_request_completed): Failed to parse JSON.'
		printerr(error_msg_json)
		printerr('  Raw Body: %s' % response_body_text)
		emit_signal('fetch_error', error_msg_json)
		return
	# Expected primary shape: Array of route dicts
	if json_response is Array:
		_log_info('[APICalls][FIND_ROUTE] Parsed %d route choice(s) (Array).' % json_response.size())
		emit_signal('route_choices_received', json_response)
		return
	if json_response is Dictionary:
		# Accept wrappers or single journey dict
		if json_response.has('routes') and json_response['routes'] is Array:
			var arr: Array = json_response['routes']
			_log_info('[APICalls][FIND_ROUTE] Parsed %d route choice(s) from routes[] wrapper.' % arr.size())
			emit_signal('route_choices_received', arr)
			return
		elif json_response.has('journey'):
			_log_info('[APICalls][FIND_ROUTE] Received single route object; wrapping into array.')
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
	_current_client_txn_id = -1
	_inflight_vendor_id = ""
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

# Helper: emit auth state into SignalHub if present
func _emit_hub_auth_state(state: String) -> void:
	if not is_inside_tree():
		return
	var hub := get_node_or_null('/root/SignalHub')
	if is_instance_valid(hub) and hub.has_signal('auth_state_changed'):
		hub.auth_state_changed.emit(state)

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
	print("[APICalls][Debug] _process_queue(): entry. in_progress=%s queue_len=%d" % [str(_is_request_in_progress), _request_queue.size()])
	# When instantiated as a plain script (e.g., unit tests), we are not in the scene tree
	# and should not attempt to dispatch HTTP requests.
	if not is_inside_tree():
		return
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
	var q_after := _request_queue.size()
	var enq_ms := int(next_request.get("enqueued_at_ms", -1))
	var now_ms := Time.get_ticks_msec()
	var wait_ms := (now_ms - enq_ms) if enq_ms >= 0 else -1
	_current_client_txn_id = int(next_request.get("client_txn_id", -1))
	var dbg_tag := String(next_request.get("debug_tag", ""))
	print("[APICalls][Dequeue] tag=", dbg_tag, " id=", _current_client_txn_id, " wait_ms=", wait_ms, " qlen_after=", q_after)
	_last_requested_url = next_request.get("url", "")
	_current_request_purpose = next_request.get("purpose", RequestPurpose.NONE)
	_current_patch_signal_name = next_request.get("signal_name", "")
	if _current_request_purpose == RequestPurpose.VENDOR_DATA:
		_inflight_vendor_id = String(next_request.get("vendor_id", ""))
		if _inflight_vendor_id == "":
			_inflight_vendor_id = _extract_query_param(_last_requested_url, "vendor_id")
	var headers: PackedStringArray = next_request.get("headers", [])
	var method: int = next_request.get("method", HTTPClient.METHOD_GET)
	var body: String = next_request.get("body", "")
	headers = _apply_auth_header(headers)
	var purpose_str: String = RequestPurpose.keys()[_current_request_purpose]
	print("[APICalls] _process_queue(): dispatching purpose=%s URL=%s method=%d" % [purpose_str, _last_requested_url, method])
	_current_request_start_time = Time.get_unix_time_from_system()
	_current_request_start_ms = Time.get_ticks_msec()
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
	if _disable_request_timeouts_for_tests:
		return
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
	var done_ms := Time.get_ticks_msec()
	var http_elapsed_ms := done_ms - _current_request_start_ms
	_log_info("[APICalls] _on_request_completed() purpose=%s result=%d code=%d url=%s id=%d http_ms=%d" % [RequestPurpose.keys()[_current_request_purpose], result, response_code, _last_requested_url, _current_client_txn_id, http_elapsed_ms])
	if _current_patch_signal_name == "warehouse_convoy_spawned":
		_log_info("[APICalls][SpawnConvoy] completion result=%d http_code=%d body_bytes=%d" % [result, response_code, body.size()])
	var request_purpose_at_start = _current_request_purpose
	# Global 401 handling (auth expired)
	if response_code == 401 and _auth_bearer_token != "" and request_purpose_at_start != RequestPurpose.AUTH_STATUS:
		_log_info("[APICalls] Received 401 with auth token present. Treating as expired.")
		clear_auth_session_token()
		emit_signal("auth_expired")
		_emit_hub_auth_state("expired")
		# Continue to normal error handling path below
	# PATCH transaction responses (purpose == NONE, but signal_name is set)
	if _current_request_purpose == RequestPurpose.NONE and _current_patch_signal_name != "":
		if result == HTTPRequest.RESULT_SUCCESS and (response_code >= 200 and response_code < 300):
			_log_info("[APICalls][PATCH_TXN] signal=%s code=%d size=%d url=%s id=%d http_ms=%d" % [_current_patch_signal_name, response_code, body.size(), _last_requested_url, _current_client_txn_id, http_elapsed_ms])
			var response_body_text = body.get_string_from_utf8()
			var preview = response_body_text.substr(0, 400)
			print("[APICalls][Debug] Transaction Response Body: ", response_body_text)
			_log_debug("[APICalls][PATCH_TXN] body_preview=" + preview)
			var json_response = JSON.parse_string(response_body_text)
			if json_response == null:
				# Accept plain-text bodies (e.g., UUID) by emitting the raw string
				var sig_n := _current_patch_signal_name
				var is_txn := (sig_n == "vehicle_bought" or sig_n == "vehicle_sold" or sig_n == "cargo_bought" or sig_n == "cargo_sold" or sig_n == "resource_bought" or sig_n == "resource_sold")
				var can_emit := has_signal(sig_n)
				if not is_txn and can_emit:
					_log_info("[APICalls][PATCH_TXN] Non-JSON success body; emitting raw text for signal '%s'." % sig_n)
					emit_signal(sig_n, response_body_text)
				else:
					_log_info("[APICalls][PATCH_TXN] Non-JSON success for '%s'; skipping emit (services will refresh or signal removed)." % sig_n)
			else:
				# Normalize common txn payloads: if server wraps convoy in 'convoy_after', emit the inner convoy
				var sig2 := _current_patch_signal_name
				var skip_emit := false
				var can_emit2 := has_signal(sig2)
				if typeof(json_response) == TYPE_DICTIONARY and not skip_emit and can_emit2:
					if json_response.has("convoy_after") and typeof(json_response["convoy_after"]) == TYPE_DICTIONARY:
						_log_info("[APICalls][PATCH_TXN] Unwrapping 'convoy_after' for signal '" + sig2 + "'.")
						emit_signal(sig2, json_response["convoy_after"])
						_complete_current_request()
						return
				if not skip_emit and can_emit2:
					_log_info("APICalls: Transaction '%s' successful. Emitting signal with data." % sig2)
					emit_signal(sig2, json_response)
				else:
					_log_info("APICalls: Transaction '%s' successful. Skipping emit (services will refresh or signal removed)." % sig2)
			
			_complete_current_request()
			return
		else:
			# Optional compatibility fallback: if we tried new cargo/vehicle routes and got 404, retry legacy path once.
			if response_code == 404 and _last_requested_url.find("/vendor/cargo/") != -1 and (_current_patch_signal_name == "cargo_bought" or _current_patch_signal_name == "cargo_sold"):
				var legacy_url := _last_requested_url
				legacy_url = legacy_url.replace("/vendor/cargo/buy?", "/vendor/buy_cargo?")
				legacy_url = legacy_url.replace("/vendor/cargo/sell?", "/vendor/sell_cargo?")
				if legacy_url != _last_requested_url:
					_log_info("[APICalls][PATCH_TXN][Fallback] 404 on new cargo route; retrying legacy URL=" + legacy_url)
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
			# Vehicle route fallback: try alternate naming and bare /vehicle endpoints
			if response_code == 404 and (_current_patch_signal_name == "vehicle_bought" or _current_patch_signal_name == "vehicle_sold"):
				var candidates: Array[String] = []
				# 1) Swap vendor/vehicle route to vendor/buy_vehicle|sell_vehicle
				var c1 := _last_requested_url.replace("/vendor/vehicle/buy?", "/vendor/buy_vehicle?")
				c1 = c1.replace("/vendor/vehicle/sell?", "/vendor/sell_vehicle?")
				if c1 != _last_requested_url:
					candidates.append(c1)
				# 2) Swap vendor/buy_vehicle|sell_vehicle back to vendor/vehicle/buy|sell
				var c2 := _last_requested_url.replace("/vendor/buy_vehicle?", "/vendor/vehicle/buy?")
				c2 = c2.replace("/vendor/sell_vehicle?", "/vendor/vehicle/sell?")
				if c2 != _last_requested_url:
					candidates.append(c2)
				# 3) Try bare /vehicle/buy|sell (server-side route provided)
				var c3 := _last_requested_url.replace("/vendor/vehicle/buy?", "/vehicle/buy?")
				c3 = c3.replace("/vendor/buy_vehicle?", "/vehicle/buy?")
				if c3 != _last_requested_url:
					candidates.append(c3)
				var c4 := _last_requested_url.replace("/vendor/vehicle/sell?", "/vehicle/sell?")
				c4 = c4.replace("/vendor/sell_vehicle?", "/vehicle/sell?")
				if c4 != _last_requested_url:
					candidates.append(c4)
				# Enqueue the first viable candidate
				if not candidates.is_empty():
					var alt_url := candidates[0]
					_log_info("[APICalls][PATCH_TXN][Fallback] 404 on vehicle route; retrying alternate URL=" + alt_url)
					_is_request_in_progress = false
					_current_request_purpose = RequestPurpose.NONE
					var headers2: PackedStringArray = ['accept: application/json']
					headers2 = _apply_auth_header(headers2)
					_request_queue.push_front({
						"url": alt_url,
						"headers": headers2,
						"purpose": RequestPurpose.NONE,
						"method": HTTPClient.METHOD_PATCH,
						"body": "",
						"signal_name": _current_patch_signal_name
					})
					_process_queue()
					return
			_log_info("[APICalls][PATCH_TXN] signal=%s FAILED result=%d code=%d url=%s id=%d http_ms=%d" % [_current_patch_signal_name, result, response_code, _last_requested_url, _current_client_txn_id, http_elapsed_ms])
			var fail_body_text := body.get_string_from_utf8()
			var fail_preview := fail_body_text.substr(0, 400)
			print("[APICalls][Debug] Transaction Failed. Code: %d. Body: %s" % [response_code, fail_body_text])
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
			else:
				# Fallback for non-JSON error body
				emit_signal('fetch_error', "PATCH '" + _current_patch_signal_name + "' failed: " + fail_body_text)
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
		var response_body_text: String = body.get_string_from_utf8()
		var json_response = JSON.parse_string(response_body_text)
		if json_response == null:
			var error_msg_json = 'APICalls (_on_request_completed - Purpose: %s, Code: %s): Failed to parse JSON response. URL: %s' % [RequestPurpose.keys()[request_purpose_at_start], response_code, _last_requested_url]
			printerr(error_msg_json)
			printerr('  Raw Body: %s' % response_body_text)
			emit_signal('fetch_error', error_msg_json)
			_complete_current_request()
			return

		var final_convoy_list: Array
		if json_response is Array:
			final_convoy_list = json_response
		elif json_response is Dictionary:
			# This is likely a user object from /user/get, which contains a convoy list.
			# Also emit the full user object for downstream consumers.
			if request_purpose_at_start == RequestPurpose.USER_CONVOYS:
				emit_signal('user_data_received', json_response)

				var extracted: Array = []
				var candidate_keys = ["convoys", "user_convoys", "convoy_list", "convoyData", "convoy_data"]
				for k in candidate_keys:
					if json_response.has(k) and json_response[k] is Array:
						extracted = json_response[k]
						print("APICalls: Extracted convoys array from wrapper key '%s' size=%d" % [k, extracted.size()])
						break
				if extracted.is_empty():
					print("[APICalls] User object received, but no convoy list found inside it. Assuming user has no convoys.")
					var logger_missing := get_node_or_null('/root/Logger') if is_inside_tree() else null
					if is_instance_valid(logger_missing) and logger_missing.has_method('warn'):
						logger_missing.warn("APICalls USER_CONVOYS: user payload missing convoy list keys. url=%s", _last_requested_url)
					final_convoy_list = []
				else:
					final_convoy_list = extracted
		else:
			var error_msg_type = 'APICalls (_on_request_completed - Purpose: %s, Code: %s): Unexpected convoy response type=%s. URL: %s' % [RequestPurpose.keys()[request_purpose_at_start], response_code, typeof(json_response), _last_requested_url]
			printerr(error_msg_type)
			emit_signal('fetch_error', error_msg_type)
			_complete_current_request()
			return

		print("APICalls (_on_request_completed - %s): Successfully fetched %s convoy(s). URL: %s" % [RequestPurpose.keys()[request_purpose_at_start], final_convoy_list.size(), _last_requested_url])
		var logger2 := get_node_or_null('/root/Logger') if is_inside_tree() else null
		if is_instance_valid(logger2) and logger2.has_method('info'):
			logger2.info("APICalls.ok %s count=%s url=%s", RequestPurpose.keys()[request_purpose_at_start], final_convoy_list.size(), _last_requested_url)
		# Normalize convoy keys for UI/Map consumers (ensure 'convoy_id' and 'convoy_name')
		var normalized_convoys: Array = []
		for item in final_convoy_list:
			if item is Dictionary:
				var d: Dictionary = (item as Dictionary).duplicate(true)
				if not d.has("convoy_id"):
					var raw_id = d.get("id", d.get("convoyId", ""))
					if typeof(raw_id) != TYPE_NIL and str(raw_id) != "":
						d["convoy_id"] = str(raw_id)
				if not d.has("convoy_name"):
					var raw_name = d.get("convoy_name", d.get("name", d.get("convoyName", "")))
					if typeof(raw_name) != TYPE_NIL and str(raw_name) != "":
						d["convoy_name"] = str(raw_name)
				normalized_convoys.append(d)
			else:
				normalized_convoys.append(item)
		self.convoys_in_transit = normalized_convoys
		# Route to GameStore (and SignalHub via store) as a non-breaking shim
		var store := get_node_or_null('/root/GameStore') if is_inside_tree() else null
		if is_instance_valid(store) and store.has_method('set_convoys'):
			store.set_convoys(normalized_convoys)
		emit_signal('convoy_data_received', normalized_convoys)
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
			# Route to GameStore (and SignalHub via store)
			var store := get_node_or_null('/root/GameStore') if is_inside_tree() else null
			if is_instance_valid(store) and store.has_method('set_map'):
				store.set_map(deserialized_map_data.get('tiles', []), deserialized_map_data.get('settlements', []))
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
			# Update GameStore then emit legacy signal
			var store := get_node_or_null('/root/GameStore') if is_inside_tree() else null
			if is_instance_valid(store) and store.has_method('set_user'):
				store.set_user(json_response)
			emit_signal('user_data_received', json_response)

		_complete_current_request()
		return

	elif request_purpose_at_start == RequestPurpose.VENDOR_DATA:
		# Clear pending flag for this vendor id on completion
		var vid_done := _inflight_vendor_id
		if vid_done == "":
			vid_done = _extract_query_param(_last_requested_url, "vendor_id")
		var response_body_text: String = body.get_string_from_utf8()
		var json_response = JSON.parse_string(response_body_text)

		if json_response == null or not json_response is Dictionary:
			var error_msg = 'APICalls (_on_request_completed - VENDOR_DATA): Failed to parse vendor data. URL: %s' % _last_requested_url
			printerr(error_msg)
			emit_signal('fetch_error', error_msg)
		else:
			print("APICalls (_on_request_completed - VENDOR_DATA): Successfully fetched vendor data. URL: %s" % _last_requested_url)
			emit_signal('vendor_data_received', json_response)
		if vid_done != "" and _pending_vendor_refresh.has(vid_done):
			_pending_vendor_refresh.erase(vid_done)
		if _inflight_vendor_id == vid_done:
			_inflight_vendor_id = ""

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
			_emit_hub_auth_state(status)
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
					_emit_hub_auth_state('complete')
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
	# Route to GameStore (and SignalHub via store) as a non-breaking shim
	var store := get_node_or_null('/root/GameStore') if is_inside_tree() else null
	if is_instance_valid(store) and store.has_method('set_map'):
		store.set_map(deserialized.get('tiles', []), deserialized.get('settlements', []))
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
	# Use a one-shot timer to delay the next status request
	var t := Timer.new()
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	t.one_shot = true
	t.wait_time = max(0.2, float(_auth_poll.interval))
	add_child(t)
	t.timeout.connect(func():
		if _auth_poll.active:
			_enqueue_auth_status_request(_auth_poll.state)
		t.queue_free()
	)
	t.start()

# --- New Convoy Creation (Direct POST) ---
func create_convoy(convoy_name: String) -> void:
	# Use documented endpoint first; fall back only if needed.
	var primary_url := "%s/convoy/new" % [BASE_URL]
	print("[APICalls][create_convoy] Dispatching POST to ", primary_url, " name=", convoy_name)
	_post_convoy_create(convoy_name, primary_url, 0, false)

func _post_convoy_create(convoy_name: String, url: String, retry_stage: int, is_retry: bool) -> void:
	# Uses a dedicated HTTPRequest to avoid queue coupling for onboarding UX
	var requester := HTTPRequest.new()
	add_child(requester)
	requester.request_completed.connect(_on_create_convoy_completed.bind(requester, convoy_name, url, retry_stage, is_retry))
	var headers: PackedStringArray = ["accept: application/json"]
	headers = _apply_auth_header(headers)

	var effective_url := url
	var method := HTTPClient.METHOD_POST
	var body_str := ""

	if url.ends_with("/convoy/new"):
		# Server expects query params for user_id and convoy_name
		var params: Dictionary = {}
		if current_user_id != "":
			params["user_id"] = current_user_id
		params["convoy_name"] = String(convoy_name)
		effective_url = "%s%s" % [url, _build_query(params)]
		print("[APICalls][create_convoy] Using query params url=", effective_url)
	else:
		# Legacy/alternate endpoint: send JSON body
		headers.append("Content-Type: application/json")
		var body := {}
		match retry_stage:
			0:
				body = {"name": String(convoy_name)}
			1:
				body = {"convoy_name": String(convoy_name)}
				if current_user_id != "":
					body["user_id"] = current_user_id
			2:
				body = {"new_convoy_name": String(convoy_name)}
				if current_user_id != "":
					body["user_id"] = current_user_id
			_:
				body = {"name": String(convoy_name)}
		body_str = JSON.stringify(body)
		print("[APICalls][create_convoy] Using JSON body for ", url, " body=", body)

	var err = requester.request(effective_url, headers, method, body_str)
	if err != OK:
		var msg = "[APICalls][create_convoy] request() failed err=%d url=%s" % [err, effective_url]
		push_error(msg)
		emit_signal("fetch_error", msg)
		requester.queue_free()

func _on_create_convoy_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, requester: HTTPRequest, convoy_name: String, url_used: String, retry_stage: int, was_retry: bool) -> void:
	if is_instance_valid(requester):
		requester.queue_free()
	var ok := (result == HTTPRequest.RESULT_SUCCESS) and (response_code >= 200 and response_code < 300)
	var payload: Variant = null
	var raw_text := ""
	if body.size() > 0:
		raw_text = body.get_string_from_utf8()
		var parse = JSON.new()
		if parse.parse(raw_text) == OK:
			payload = parse.get_data()
	if ok:
		if typeof(payload) == TYPE_DICTIONARY:
			print("[APICalls][create_convoy] Success http=", response_code, " payload keys=", payload.keys())
		elif typeof(payload) == TYPE_STRING:
			print("[APICalls][create_convoy] Success (UUID string) http=", response_code, " uuid=", payload)
		else:
			print("[APICalls][create_convoy] Success http=", response_code, " non-JSON or unexpected type; raw=", raw_text.substr(0, 200))
		# Signal success to listeners (ConvoyService)
		emit_signal("convoy_created", payload if typeof(payload) == TYPE_DICTIONARY else {})
	else:
		print("[APICalls][create_convoy] Failure result=", result, " http=", response_code, " url=", url_used, " was_retry=", was_retry, " body=", (raw_text.substr(0, 300) if raw_text != "" else "<empty>"))
		# If the primary endpoint failed (e.g., 404/405/400), try alternate '/convoy/new' once
		if not was_retry and (response_code == 404 or response_code == 405 or response_code == 400) and not url_used.ends_with("/convoy/new"):
			var alt_url := "%s/convoy/new" % [BASE_URL]
			print("[APICalls][create_convoy] Retrying with alternate endpoint ", alt_url)
			_post_convoy_create(convoy_name, alt_url, 0, true)
			return
		# If validation failed on new endpoint, try alternate payload shapes (limited attempts)
		if url_used.ends_with("/convoy/new") and response_code == 422 and retry_stage < 2:
			var next_stage := retry_stage + 1
			print("[APICalls][create_convoy] 422 Unprocessable. Retrying payload variant stage=", next_stage)
			_post_convoy_create(convoy_name, url_used, next_stage, true)
			return
		var err_msg := "APICalls.create_convoy failed http=%d url=%s" % [response_code, url_used]
		emit_signal("fetch_error", err_msg)
	if not _auth_poll.active:
		return
	var delay: float = max(0.2, float(_auth_poll.interval))
	var t := get_tree().create_timer(delay, true)
	t.timeout.connect(func(): _enqueue_auth_status_request(_auth_poll.state))
