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

const BASE_URL: String = 'https://df-api.oori.dev:1337'
const LOCAL_BASE_URL: String = 'https://df-api.oori.dev:1337' # Changed to live DB URL


var current_user_id: String = "" # To store the logged-in user's ID
var _http_request: HTTPRequest
var convoys_in_transit: Array = []  # This will store the latest parsed list of convoys (either user's or all)
var _last_requested_url: String = "" # To store the URL for logging on error
var _is_local_user_attempt: bool = false # Flag to track if the current USER_CONVOYS request is the initial local one

# --- Request Queue ---
var _request_queue: Array = []
var _is_request_in_progress: bool = false

enum RequestPurpose { NONE, USER_CONVOYS, ALL_CONVOYS, MAP_DATA, USER_DATA }
var _current_request_purpose: RequestPurpose = RequestPurpose.NONE

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

	var url: String = '%s/convoy/user_convoys?user_id=%s' % [LOCAL_BASE_URL, p_user_id] # Try LOCAL first
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
	var request_purpose_at_start = _current_request_purpose # Store for logging
	var was_initial_local_user_attempt = (_current_request_purpose == RequestPurpose.USER_CONVOYS and _is_local_user_attempt)

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
				var parsed_data = parse_in_transit_convoy_details(json_response)
				if parsed_data.is_empty():
					local_attempt_failed_or_empty = true
					failure_reason = "received an empty list"
				else:
					# SUCCESS with local data
					print("APICalls (_on_request_completed - LOCAL_USER_CONVOYS): Successfully fetched %s user-specific convoy(s) locally. URL: %s" % [parsed_data.size(), _last_requested_url])
					if not parsed_data.is_empty(): # Should always be true here due to check above
						print("  Sample Local User Convoy 0: ID: %s, Name: %s" % [parsed_data[0].get("convoy_id", "N/A"), parsed_data[0].get("convoy_name", "N/A")])
					self.convoys_in_transit = parsed_data
					emit_signal('convoy_data_received', parsed_data)
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
		var error_msg_response_fallback = 'APICalls (_on_request_completed - Purpose: %s): Request failed with response code: %s. URL: %s' % [RequestPurpose.keys()[request_purpose_at_start], response_code, _last_requested_url]
		printerr(error_msg_response_fallback)
		printerr('  Response body: ', body.get_string_from_utf8())
		emit_signal('fetch_error', error_msg_response_fallback)
		_complete_current_request()
		return

	# Successful HTTP response for fallback or direct remote
	if request_purpose_at_start == RequestPurpose.NONE: # Likely get_convoy_data (expects Dictionary)
		# Handle get_convoy_data response (assuming it expects a Dictionary)
		# This part needs to be fleshed out if get_convoy_data is actively used and its response is a Dictionary.
		# For now, we'll assume it's not the primary flow being addressed.
		printerr("APICalls (_on_request_completed - Purpose: NONE): Received response for get_convoy_data. Needs specific handling if it's not an Array. URL: %s" % _last_requested_url)
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

		# Successfully parsed array for fallback or direct remote (that expects array)
		if request_purpose_at_start == RequestPurpose.ALL_CONVOYS or \
		   (request_purpose_at_start == RequestPurpose.USER_CONVOYS and not was_initial_local_user_attempt): # Second condition should ideally not be met if logic is tight
			var parsed_data: Array = parse_in_transit_convoy_details(json_response)
			var log_prefix = "REMOTE_ALL_CONVOYS_FALLBACK" if request_purpose_at_start == RequestPurpose.ALL_CONVOYS else "REMOTE_USER_CONVOYS_DIRECT"
			print("APICalls (_on_request_completed - %s): Successfully fetched %s convoy(s). URL: %s" % [log_prefix, parsed_data.size(), _last_requested_url])
			if not parsed_data.is_empty():
				print("  Sample %s Convoy 0: ID: %s, Name: %s" % [log_prefix, parsed_data[0].get("convoy_id", "N/A"), parsed_data[0].get("convoy_name", "N/A")])
			self.convoys_in_transit = parsed_data
			emit_signal('convoy_data_received', parsed_data)
			_complete_current_request()

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

	# Fallback for any unhandled cases, though ideally all paths are covered.
	if _current_request_purpose != RequestPurpose.NONE:
		printerr("APICalls (_on_request_completed): Reached end of function with _current_request_purpose not NONE. Purpose: %s. This might indicate an unhandled logic path." % RequestPurpose.keys()[_current_request_purpose])
		_complete_current_request() # Ensure reset and queue processing


func parse_in_transit_convoy_details(raw_convoy_list: Array) -> Array:
	"""
	Parses the raw array of in-transit convoy data from the API
	into a more structured format, extracting specific details.

	Args:
		raw_convoy_list: An Array of Dictionaries, where each dictionary
						 is a raw convoy object from the API response.

	Returns:
		An Array of Dictionaries. Each dictionary represents a convoy and contains:
		- convoy_id (String)
		- convoy_name (String)
		- efficiency (float)
		- top_speed (float)
		- offroad_capability (float)
		- vehicle_names (Array[String])
		- journey (Dictionary) - The entire journey object
		- fuel, max_fuel, water, max_water, food, max_food (floats)
		- total_cargo_capacity, total_weight_capacity, total_free_space, total_remaining_capacity (floats)
		- vehicle_details_list (Array of Dictionaries, each with name, description, efficiency, top_speed, offroad_capability)
		- all_cargo (Array of cargo details) - The entire all_cargo array.
	"""
	var parsed_convoys: Array = []
	if not raw_convoy_list is Array:
		printerr('APICalls: Expected an array for parsing convoy data, got: ', typeof(raw_convoy_list))
		return parsed_convoys

	# --- START: New code to save raw convoy data to file ---
	var file_path = "res://Other/raw_convoy_data.json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if FileAccess.get_open_error() != OK:
		printerr("APICalls: Error opening file for raw convoy data: %s. Error: %s" % [file_path, FileAccess.get_open_error()])
	else:
		# Use JSON.stringify with a tab for pretty printing, making it easier to read
		var json_string = JSON.stringify(raw_convoy_list, "\t")
		if json_string == "":
			printerr("APICalls: Error converting raw convoy data to JSON string.")
		else:
			file.store_string(json_string)
			file.close()
			print("APICalls: Raw convoy data saved to: %s" % file_path)
	# --- END: New code ---

	for convoy_data in raw_convoy_list:
		if not convoy_data is Dictionary:
			printerr('APICalls: Expected a dictionary for individual convoy data, got: ', typeof(convoy_data))
			continue  # Skip this item if it's not a dictionary

		var raw_journey_value = convoy_data.get('journey')
		var journey_data: Dictionary = {} # Default to an empty dictionary
		if raw_journey_value is Dictionary: # Check if the retrieved value is actually a dictionary
			journey_data = raw_journey_value # If yes, assign it
		# If raw_journey_value was null or not a Dictionary, journey_data remains the safe default {}


		var convoy_details: Dictionary = {}
		convoy_details['convoy_id'] = convoy_data.get('convoy_id', '')  # UUIDs are best handled as Strings in GDScript
		convoy_details['convoy_name'] = convoy_data.get('name', 'Unknown Convoy')
		convoy_details['efficiency'] = convoy_data.get('efficiency', 0.0)
		convoy_details['top_speed'] = convoy_data.get('top_speed', 0.0)
		convoy_details['offroad_capability'] = convoy_data.get('offroad_capability', 0.0)
		# Populate top-level x and y directly from the convoy_data object
		convoy_details['x'] = convoy_data.get('x', 0.0)  # Default to 0.0 if not found
		convoy_details['y'] = convoy_data.get('y', 0.0)  # Default to 0.0 if not found

		# Add top-level resource and capacity stats
		convoy_details['fuel'] = convoy_data.get('fuel', 0.0)
		convoy_details['max_fuel'] = convoy_data.get('max_fuel', 0.0)
		convoy_details['water'] = convoy_data.get('water', 0.0)
		convoy_details['max_water'] = convoy_data.get('max_water', 0.0)
		convoy_details['food'] = convoy_data.get('food', 0.0)
		convoy_details['max_food'] = convoy_data.get('max_food', 0.0)
		convoy_details['total_cargo_capacity'] = convoy_data.get('total_cargo_capacity', 0.0)
		convoy_details['total_weight_capacity'] = convoy_data.get('total_weight_capacity', 0.0)
		convoy_details['total_free_space'] = convoy_data.get('total_free_space', 0.0)
		convoy_details['total_remaining_capacity'] = convoy_data.get('total_remaining_capacity', 0.0)

		# Process vehicle details
		var vehicle_details_list: Array = []
		var vehicles_raw: Array = convoy_data.get('vehicles', [])
		if vehicles_raw is Array:
			for vehicle_data in vehicles_raw:
				if vehicle_data is Dictionary:
					var single_vehicle_details: Dictionary = {}
					single_vehicle_details['name'] = vehicle_data.get('name', 'Unknown Vehicle')
					single_vehicle_details['make_model'] = vehicle_data.get('make_model', 'Unknown Make/Model')
					# Get the original 'description' field from the raw data
					single_vehicle_details['description'] = vehicle_data.get('description', 'No description available.')
					# Add 'base_desc' as a separate, distinct field
					single_vehicle_details['base_desc'] = vehicle_data.get('base_desc', 'No base description available.')
					single_vehicle_details['efficiency'] = vehicle_data.get('efficiency', 0.0)
					single_vehicle_details['top_speed'] = vehicle_data.get('top_speed', 0.0)
					single_vehicle_details['offroad_capability'] = vehicle_data.get('offroad_capability', 0.0)
					single_vehicle_details['base_value'] = vehicle_data.get('base_value', 0.0)
					single_vehicle_details['value'] = vehicle_data.get('value', 0.0) # Add the vehicle's current value
					single_vehicle_details['color'] = vehicle_data.get('color', 'N/A')
					single_vehicle_details['shape'] = vehicle_data.get('shape', 'N/A')
					single_vehicle_details['cargo'] = vehicle_data.get('cargo', [])
					single_vehicle_details['parts'] = vehicle_data.get('parts', []) # Add the parts array
					vehicle_details_list.append(single_vehicle_details)
		convoy_details['vehicle_details_list'] = vehicle_details_list

		convoy_details['journey'] = journey_data  # Store the (potentially modified) journey object

		# Store the entire 'cargo_inventory' array, aliased from the 'all_cargo' key in the raw API data.
		convoy_details['cargo_inventory'] = convoy_data.get('all_cargo', [])

		parsed_convoys.append(convoy_details)

	print("APICalls (parse_in_transit_convoy_details): Successfully parsed %s convoy(s) from raw data." % parsed_convoys.size())
	return parsed_convoys
