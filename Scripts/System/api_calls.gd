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
signal vehicle_bought(result: Dictionary)
signal vehicle_sold(result: Dictionary)
signal cargo_bought(result: Dictionary)
signal cargo_sold(result: Dictionary)
signal resource_bought(result: Dictionary)
signal resource_sold(result: Dictionary)
signal vendor_data_received(vendor_data: Dictionary)

# --- Journey Planning Signals ---
signal route_choices_received(routes: Array)
signal convoy_sent_on_journey(updated_convoy_data: Dictionary)

var BASE_URL: String = 'http://127.0.0.1:1337' # default
# Allow override via environment (cannot be const due to runtime lookup)
func _init():
	if OS.has_environment('DF_API_BASE_URL'):
		BASE_URL = OS.get_environment('DF_API_BASE_URL')

var current_user_id: String = "" # To store the logged-in user's ID
var _http_request: HTTPRequest
var _http_request_map: HTTPRequest  # Dedicated non-queued requester for map data
var convoys_in_transit: Array = []  # This will store the latest parsed list of convoys (either user's or all)
var _last_requested_url: String = "" # To store the URL for logging on error
var _is_local_user_attempt: bool = false # Flag to track if the current USER_CONVOYS request is the initial local one

# --- Request Queue ---
var _request_queue: Array = []
var _is_request_in_progress: bool = false

# Add AUTH_STATUS, AUTH_ME to purposes
enum RequestPurpose { NONE, USER_CONVOYS, ALL_CONVOYS, MAP_DATA, USER_DATA, VENDOR_DATA, FIND_ROUTE, AUTH_URL, AUTH_TOKEN, AUTH_STATUS, AUTH_ME }
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
}

var _probe_stalled_count: int = 0
var _auth_me_resolve_attempts: int = 0
const AUTH_ME_MAX_ATTEMPTS: int = 5
const AUTH_ME_RETRY_INTERVAL: float = 0.75
var _pending_discord_id: String = ""
var _emitted_new_user_required: bool = false
var _creating_user: bool = false

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
	_start_request_status_probe()
	_load_auth_session_token()
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

# --- Journey Planning Requests ---
func find_route(convoy_id: String, dest_x: int, dest_y: int) -> void:
	# Validate convoy_id (must be UUID) and coordinates
	if convoy_id.is_empty() or not _is_valid_uuid(convoy_id):
		var err_msg = 'APICalls (find_route): Invalid convoy_id "%s".' % convoy_id
		printerr(err_msg)
		emit_signal('fetch_error', err_msg)
		return
	var url: String = "%s/convoy/journey/find_route?convoy_id=%s&dest_x=%d&dest_y=%d" % [BASE_URL, convoy_id, dest_x, dest_y]
	var headers: PackedStringArray = ['accept: application/json']
	headers = _apply_auth_header(headers)
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.FIND_ROUTE,
		"method": HTTPClient.METHOD_GET
	}
	print('[APICalls] Queueing find_route request purpose=FIND_ROUTE url=', url)
	_request_queue.append(request_details)
	_process_queue()
# ...existing code...
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
			var response_body_text = body.get_string_from_utf8()
			var json_response = JSON.parse_string(response_body_text)
			if json_response == null:
				var error_msg = "APICalls (PATCH): Failed to parse JSON for '%s'. Body: %s" % [_current_patch_signal_name, response_body_text]
				printerr(error_msg)
				emit_signal('fetch_error', error_msg)
			else:
				print("APICalls: Transaction '%s' successful. Emitting signal with data." % _current_patch_signal_name)
				emit_signal(_current_patch_signal_name, json_response)
			
			_complete_current_request()
			return
		# If the PATCH request failed, it will fall through to the generic error handlers below.
		# This is intentional, so we don't have to duplicate error handling logic.

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

	# Successful HTTP response for fallback or direct remote
	if request_purpose_at_start == RequestPurpose.NONE: # Likely get_convoy_data (expects Dictionary)
		# Handle get_convoy_data response (assuming it expects a Dictionary)
		# This part needs to be fleshed out if get_convoy_data is actively used and its response is a Dictionary.
		# For now, we'll assume it's not the primary flow being addressed.
		if request_purpose_at_start == RequestPurpose.NONE and _current_patch_signal_name == "":
			var response_body_text = body.get_string_from_utf8()
			var json_response = JSON.parse_string(response_body_text)
			if json_response == null or not json_response is Dictionary:
				printerr("APICalls (_on_request_completed - Purpose: NONE): Failed to parse convoy data as Dictionary. URL: %s" % _last_requested_url)
				emit_signal('fetch_error', "Failed to parse convoy data as Dictionary.")
			else:
				print("APICalls (_on_request_completed - Purpose: NONE): Successfully fetched single convoy data. URL: %s" % _last_requested_url)
				# Emit as a single-item array for consistency
				emit_signal('convoy_data_received', [json_response])
			_complete_current_request()
			return

		# Process Array response (for ALL_CONVOYS or a non-initial USER_CONVOYS)
		if request_purpose_at_start == RequestPurpose.ALL_CONVOYS or request_purpose_at_start == RequestPurpose.USER_CONVOYS:
			var response_body_text: String = body.get_string_from_utf8()
			var json_response = JSON.parse_string(response_body_text)

			if json_response == null:
				var error_msg_json_fallback = 'APICalls (_on_request_completed - Purpose: %s, Code: %s): Failed to parse JSON response. URL: %s' % [RequestPurpose.keys()[request_purpose_at_start], response_code, _last_requested_url]
				printerr(error_msg_json_fallback)
				printerr('  Raw Body: %s' % response_body_text)
				emit_signal('fetch_error', error_msg_json_fallback)
				_complete_current_request()
				return

			if not json_response is Array:
				var error_msg_type_fallback = 'APICalls (_on_request_completed - Purpose: %s, Code: %s): Expected array from JSON response, got %s. URL: %s' % [RequestPurpose.keys()[request_purpose_at_start], response_code, typeof(json_response), _last_requested_url]
				printerr(error_msg_type_fallback)
				emit_signal('fetch_error', error_msg_type_fallback)
				_complete_current_request()
				return

			# --- ADD THIS LOGGING ---
			if not json_response.is_empty():
				var first_convoy = json_response[0]
				print("APICalls: First convoy keys: ", first_convoy.keys())
				print("APICalls: First convoy vehicle_details_list: ", first_convoy.get("vehicle_details_list", []))
				if first_convoy.has("vehicle_details_list") and first_convoy["vehicle_details_list"].size() > 0:
					print("APICalls: First vehicle keys: ", first_convoy["vehicle_details_list"][0].keys())
			# --- END LOGGING ---

			# Successfully parsed array for fallback or direct remote (that expects array)
			print("APICalls (_on_request_completed - %s): Successfully fetched %s convoy(s). URL: %s" % [RequestPurpose.keys()[request_purpose_at_start], json_response.size(), _last_requested_url])
			if not json_response.is_empty():
				print("  Sample Convoy 0: ID: %s" % [json_response[0].get("convoy_id", "N/A")])
			self.convoys_in_transit = json_response
			emit_signal('convoy_data_received', json_response)
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
