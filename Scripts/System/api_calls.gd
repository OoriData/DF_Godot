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

# --- Vendor Transaction Signals ---
signal vehicle_bought(result: Dictionary)
signal vehicle_sold(result: Dictionary)
signal cargo_bought(result: Dictionary)
signal cargo_sold(result: Dictionary)
signal resource_bought(result: Dictionary)
signal resource_sold(result: Dictionary)
signal vendor_data_received(vendor_data: Dictionary)

# const BASE_URL: String = 'https://df-api.oori.dev:1337' # Change this to your test or live URL as needed
const BASE_URL: String = 'http://localhost:1337' # Change this to your test or live URL as needed

var current_user_id: String = "" # To store the logged-in user's ID
var _http_request: HTTPRequest
var convoys_in_transit: Array = []  # This will store the latest parsed list of convoys (either user's or all)
var _last_requested_url: String = "" # To store the URL for logging on error
var _is_local_user_attempt: bool = false # Flag to track if the current USER_CONVOYS request is the initial local one

# --- Request Queue ---
var _request_queue: Array = []
var _is_request_in_progress: bool = false

enum RequestPurpose { NONE, USER_CONVOYS, ALL_CONVOYS, MAP_DATA, USER_DATA, VENDOR_DATA }
var _current_request_purpose: RequestPurpose = RequestPurpose.NONE

var _current_patch_signal_name: String = ""

func _ready() -> void:
	# Create an HTTPRequest node and add it as a child.
	# This node will handle the actual network communication.
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	# Connect with a small delay to ensure the node is fully ready if APICalls is an Autoload
	# and other nodes might try to call it immediately.
	_http_request.request_completed.connect(_on_request_completed.bind())


	# Initiate the request to get all in-transit convoys.
	# The data will be processed in _on_request_completed when it arrives.
	# get_all_in_transit_convoys() # This will now be triggered by GameDataManager after login or if no user

func set_user_id(p_user_id: String) -> void:
	current_user_id = p_user_id
	# print("APICalls: User ID set to: ", current_user_id)


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
	"""
	Fetches map data from the backend API.
	Optional parameters can be used to request a specific region of the map.
	"""
	var url: String = '%s/map/get' % BASE_URL
	var query_params: Array[String] = []

	if x_min != -1:
		query_params.append("x_min=%d" % x_min)
	if x_max != -1:
		query_params.append("x_max=%d" % x_max)
	if y_min != -1:
		query_params.append("y_min=%d" % y_min)
	if y_max != -1:
		query_params.append("y_max=%d" % y_max)

	if not query_params.is_empty():
		url += "?" + "&".join(query_params)

	var headers: PackedStringArray = ['accept: application/json']

	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.MAP_DATA,
		"method": HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	_process_queue()

func get_user_data(p_user_id: String) -> void:
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
		printerr('APICalls: User ID cannot be empty for get_user_convoys. Falling back to all convoys.')
		_is_local_user_attempt = false # Ensure flag is false if we bypass local attempt
		get_all_in_transit_convoys() # Fallback if no user_id provided
		return

	if not _is_valid_uuid(p_user_id):
		printerr('APICalls: Provided ID "%s" is not a valid UUID. Falling back to remote all_in_transit.' % p_user_id)
		_is_local_user_attempt = false # Not a local user attempt eligible for specific user data
		get_all_in_transit_convoys()
		return

	# If we reach here, p_user_id IS a valid UUID. Proceed with local attempt.

	var url: String = '%s/convoy/user_convoys?user_id=%s' % [BASE_URL, p_user_id] # Use BASE_URL here
	var headers: PackedStringArray = ['accept: application/json']
	_is_local_user_attempt = true # This is the initial local attempt

	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.USER_CONVOYS,
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

func _complete_current_request() -> void:
	_current_request_purpose = RequestPurpose.NONE
	_is_request_in_progress = false
	_process_queue()

func _process_queue() -> void:
	if _is_request_in_progress or _request_queue.is_empty():
		return # Don't start a new request if one is running or queue is empty

	_is_request_in_progress = true
	var next_request: Dictionary = _request_queue.pop_front()

	_last_requested_url = next_request.get("url", "")
	_current_request_purpose = next_request.get("purpose", RequestPurpose.NONE)
	_current_patch_signal_name = next_request.get("signal_name", "") # <-- ADD THIS LINE
	var headers: PackedStringArray = next_request.get("headers", [])
	var method: int = next_request.get("method", HTTPClient.METHOD_GET)

	var purpose_str: String = RequestPurpose.keys()[_current_request_purpose]
	print("APICalls (_process_queue): Starting request for purpose '%s'. URL: %s" % [purpose_str, _last_requested_url])

	var error: Error = _http_request.request(_last_requested_url, headers, method)

	if error != OK:
		var error_msg = "APICalls (_process_queue): HTTPRequest initiation failed with error code %s for URL: %s" % [error, _last_requested_url]
		printerr(error_msg)
		emit_signal('fetch_error', error_msg)
		_is_request_in_progress = false
		_current_request_purpose = RequestPurpose.NONE
		call_deferred("_process_queue") # Try to process the next item in the queue


# Called when the HTTPRequest has completed.
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	print("APICalls: _on_request_completed called. Result: %s, Response code: %s" % [result, response_code])

	var request_purpose_at_start = _current_request_purpose
	var was_initial_local_user_attempt = (_current_request_purpose == RequestPurpose.USER_CONVOYS and _is_local_user_attempt)

	# PATCH transaction responses (purpose == NONE, but signal_name is set)
	if _current_request_purpose == RequestPurpose.NONE and _current_patch_signal_name != "":
		if result == HTTPRequest.RESULT_SUCCESS and (response_code >= 200 and response_code < 300):
			print("APICalls: Transaction '%s' successful. Emitting signal." % _current_patch_signal_name)
			emit_signal(_current_patch_signal_name, {"success": true})
		else:
			# The generic error handling below will catch this and emit 'fetch_error'.
			pass

		_complete_current_request()
		return

	# --- Handle initial local user attempt specifically for fallback logic ---
	if was_initial_local_user_attempt:
		_is_local_user_attempt = false # Consume the flag for this attempt sequence

		var local_attempt_failed_or_empty = false
		var failure_reason = ""

		if result != HTTPRequest.RESULT_SUCCESS:
			local_attempt_failed_or_empty = true
			failure_reason = "HTTPRequest level failure (result: %s)" % result
		elif not (response_code >= 200 and response_code < 300):
			local_attempt_failed_or_empty = true
			failure_reason = "HTTP response code %s" % response_code
			printerr('  Local attempt response body for error %s: %s' % [response_code, body.get_string_from_utf8()])
		else: # Successful HTTP response (2xx) from local
			var response_body_text = body.get_string_from_utf8()
			var json_response = JSON.parse_string(response_body_text)

			if json_response == null:
				local_attempt_failed_or_empty = true
				failure_reason = "JSON parsing failed"
				printerr('  Local attempt raw body for JSON parse error: %s' % response_body_text)
			elif not json_response is Array:
				local_attempt_failed_or_empty = true
				failure_reason = "JSON response was not an array (type: %s)" % typeof(json_response)
			else:
				# SUCCESS with local data
				# print("APICalls (_on_request_completed - LOCAL_USER_CONVOYS): Successfully fetched %s user-specific convoy(s) locally. URL: %s" % [json_response.size(), _last_requested_url])
				if not json_response.is_empty():
					print("  Sample Local User Convoy 0: ID: %s" % [json_response[0].get("convoy_id", "N/A")])
				self.convoys_in_transit = json_response
				emit_signal('convoy_data_received', json_response)
				_current_request_purpose = RequestPurpose.NONE
				_complete_current_request()
				return

		if local_attempt_failed_or_empty:
			printerr("APICalls: Local user convoy request failed (%s). URL: %s. Falling back to remote all_in_transit." % [failure_reason, _last_requested_url])
			get_all_in_transit_convoys()
			return # Wait for fallback to complete, do not proceed further in this callback

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
		var error_json = {}
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
		var deserialized_map_data: Dictionary = Tools.deserialize_map_data(body)

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

	# Fallback for any unhandled cases, though ideally all paths are covered.
	if _current_request_purpose != RequestPurpose.NONE:
		printerr("APICalls (_on_request_completed): Reached end of function with _current_request_purpose not NONE. Purpose: %s. This might indicate an unhandled logic path." % RequestPurpose.keys()[_current_request_purpose])
		_complete_current_request() # Ensure reset and queue processing



# --- Vendor Transaction APIs ---
func buy_vehicle(vendor_id: String, convoy_id: String, vehicle_id: String) -> void:
	var url = "%s/vendor/vehicle/buy?vendor_id=%s&convoy_id=%s&vehicle_id=%s" % [BASE_URL, vendor_id, convoy_id, vehicle_id]
	_add_patch_request(url, "vehicle_bought")

func sell_vehicle(vendor_id: String, convoy_id: String, vehicle_id: String) -> void:
	var url = "%s/vendor/vehicle/sell?vendor_id=%s&convoy_id=%s&vehicle_id=%s" % [BASE_URL, vendor_id, convoy_id, vehicle_id]
	_add_patch_request(url, "vehicle_sold")

func buy_cargo(vendor_id: String, convoy_id: String, cargo_id: String, quantity: int) -> void:
	var url = "%s/vendor/cargo/buy?vendor_id=%s&convoy_id=%s&cargo_id=%s&quantity=%d" % [BASE_URL, vendor_id, convoy_id, cargo_id, quantity]
	_add_patch_request(url, "cargo_bought")

func sell_cargo(vendor_id: String, convoy_id: String, cargo_id: String, quantity: int) -> void:
	var url = "%s/vendor/cargo/sell?vendor_id=%s&convoy_id=%s&cargo_id=%s&quantity=%d" % [BASE_URL, vendor_id, convoy_id, cargo_id, quantity]
	_add_patch_request(url, "cargo_sold")

func buy_resource(vendor_id: String, convoy_id: String, resource_type: String, quantity: float) -> void:
	var url = "%s/vendor/resource/buy?vendor_id=%s&convoy_id=%s&resource_type=%s&quantity=%.3f" % [BASE_URL, vendor_id, convoy_id, resource_type, quantity]
	_add_patch_request(url, "resource_bought")

func sell_resource(vendor_id: String, convoy_id: String, resource_type: String, quantity: float) -> void:
	var url = "%s/vendor/resource/sell?vendor_id=%s&convoy_id=%s&resource_type=%s&quantity=%.3f" % [BASE_URL, vendor_id, convoy_id, resource_type, quantity]
	_add_patch_request(url, "resource_sold")

func _add_patch_request(url: String, signal_name: String) -> void:
	var headers: PackedStringArray = ['accept: application/json']
	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.NONE, # Always use enum for purpose
		"signal_name": signal_name,     # Store the signal name separately
		"method": HTTPClient.METHOD_PATCH
	}
	_request_queue.append(request_details)
	_process_queue()

func get_vendor_data(vendor_id: String) -> void:
	if not vendor_id or vendor_id.is_empty():
		printerr("APICalls: Vendor ID cannot be empty for get_vendor_data.")
		emit_signal('fetch_error', 'Vendor ID cannot be empty.')
		return

	var url: String = '%s/vendor/get?vendor_id=%s' % [BASE_URL, vendor_id]
	var headers: PackedStringArray = ['accept: application/json']

	var request_details: Dictionary = {
		"url": url,
		"headers": headers,
		"purpose": RequestPurpose.VENDOR_DATA,
		"method": HTTPClient.METHOD_GET
	}
	_request_queue.append(request_details)
	_process_queue()
