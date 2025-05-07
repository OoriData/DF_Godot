# /Users/choccy/dev/DF_Godot/APICalls.gd
extends Node

# Signal to indicate when convoy data has been fetched
signal convoy_data_received(data: Variant)
# Signal to indicate an error occurred during fetching
signal fetch_error(error_message: String)

const BASE_URL: String = "http://137.184.246.45:1337"

var _http_request: HTTPRequest

func _ready() -> void:
	# Create an HTTPRequest node and add it as a child.
	# This node will handle the actual network communication.
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

	# Example usage: Fetch a specific convoy when the scene is ready
	# You can remove or comment this out later.
	get_all_in_transit_convoys()

func get_convoy_data(convoy_id: String) -> void:
	if not convoy_id or convoy_id.is_empty():
		printerr("APICalls: Convoy ID cannot be empty.")
		emit_signal("fetch_error", "Convoy ID cannot be empty.")
		return

	var url: String = "%s/convoy/get?convoy_id=%s" % [BASE_URL, convoy_id]
	
	# Headers for the request
	var headers: PackedStringArray = [
		"accept: application/json"
	]
	
	# Make the GET request
	# The third argument (body) is empty for GET requests.
	# The fourth argument (custom_headers) is our headers array.
	# The fifth argument (method) is HTTPClient.METHOD_GET.
	var error: Error = _http_request.request(url, headers, HTTPClient.METHOD_GET)
	
	if error != OK:
		var error_msg = "APICalls: An error occurred in HTTPRequest: %s"
		printerr(error_msg)
		emit_signal("fetch_error", error_msg)

func get_all_in_transit_convoys() -> void:
	var url: String = "%s/convoy/get_all_in_transit" % [BASE_URL]
	
	# Headers for the request
	var headers: PackedStringArray = [
		"accept: application/json"
	]
	
	# Make the GET request
	var error: Error = _http_request.request(url, headers, HTTPClient.METHOD_GET)
	
	if error != OK:
		var error_msg = "APICalls: An error occurred in HTTPRequest for get_all_in_transit_convoys: %s" % error
		printerr(error_msg)
		emit_signal("fetch_error", error_msg)


# Called when the HTTPRequest has completed.
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg = "APICalls: Request failed with result code: %s" % result
		printerr(error_msg)
		emit_signal("fetch_error", error_msg)
		return

	if response_code >= 200 and response_code < 300:
		# Successful request
		var response_body_text: String = body.get_string_from_utf8()
		var json_response = JSON.parse_string(response_body_text)
		
		if json_response == null:
			var error_msg = "APICalls: Failed to parse JSON response. Body: %s" % response_body_text
			printerr(error_msg)
			printerr("Response Code: ", response_code)
			printerr("Headers: ", headers)
			emit_signal("fetch_error", error_msg)
			return
			
		print("APICalls: Successfully fetched and parsed data:")
		print(json_response) # Print the parsed JSON
		emit_signal("convoy_data_received", json_response)
	else:
		# Request failed or returned an error status code
		var error_msg = "APICalls: Request failed with response code: %s" % response_code
		printerr(error_msg)
		printerr("Response body: ", body.get_string_from_utf8())
		emit_signal("fetch_error", error_msg)
