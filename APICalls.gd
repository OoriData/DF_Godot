# APICalls.gd
extends Node

# Signal to indicate when parsed convoy data has been fetched
signal convoy_data_received(parsed_convoy_list: Array)
# Signal to indicate an error occurred during fetching
signal fetch_error(error_message: String)

const BASE_URL: String = 'http://137.184.246.45:1337'

var _http_request: HTTPRequest
var convoys_in_transit: Array = []  # This will store the latest parsed list of in-transit convoys

func _ready() -> void:
    # Create an HTTPRequest node and add it as a child.
    # This node will handle the actual network communication.
    _http_request = HTTPRequest.new()
    add_child(_http_request)
    _http_request.request_completed.connect(_on_request_completed)

    # Initiate the request to get all in-transit convoys.
    # The data will be processed in _on_request_completed when it arrives.
    get_all_in_transit_convoys()


func get_convoy_data(convoy_id: String) -> void:
    if not convoy_id or convoy_id.is_empty():
        printerr('APICalls: Convoy ID cannot be empty.')
        emit_signal('fetch_error', 'Convoy ID cannot be empty.')
        return

    var url: String = '%s/convoy/get?convoy_id=%s' % [BASE_URL, convoy_id]

    # Headers for the request
    var headers: PackedStringArray = [
        'accept: application/json'
    ]

    # Make the GET request
    # The third argument (body) is empty for GET requests.
    # The fourth argument (custom_headers) is our headers array.
    # The fifth argument (method) is HTTPClient.METHOD_GET.
    var error: Error = _http_request.request(url, headers, HTTPClient.METHOD_GET)

    if error != OK:
        var error_msg = 'APICalls: An error occurred in HTTPRequest: %s'
        printerr(error_msg)
        emit_signal('fetch_error', error_msg)


func get_all_in_transit_convoys() -> void:
    var url: String = '%s/convoy/all_in_transit' % [BASE_URL]

    var headers: PackedStringArray = [  # Headers for the request
        'accept: application/json'
    ]

    # Make the GET request
    var error: Error = _http_request.request(url, headers, HTTPClient.METHOD_GET)

    if error != OK:
        var error_msg = 'APICalls: An error occurred in HTTPRequest for all_in_transit_convoys: %s' % error
        printerr(error_msg)
        emit_signal('fetch_error', error_msg)


# Called when the HTTPRequest has completed.
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    if result != HTTPRequest.RESULT_SUCCESS:
        var error_msg = 'APICalls: Request failed with result code: %s' % result
        printerr(error_msg)
        emit_signal('fetch_error', error_msg)
        return

    if response_code >= 200 and response_code < 300:
        # Successful request
        var response_body_text: String = body.get_string_from_utf8()
        var json_response = JSON.parse_string(response_body_text)

        if json_response == null:
            var error_msg = 'APICalls: Failed to parse JSON response. Body: %s' % response_body_text
            printerr(error_msg)
            printerr('Response Code: ', response_code)
            printerr('Headers: ', headers)
            emit_signal('fetch_error', error_msg)
            return

        print('APICalls: Successfully fetched raw data.')
        # Assuming json_response is an Array for get_all_in_transit_convoys
        if json_response is Array:
            var parsed_data: Array = parse_in_transit_convoy_details(json_response)
            self.convoys_in_transit = parsed_data  # Store the parsed data

            print('APICalls: Parsed convoy details:')
            if parsed_data.is_empty():
                print('  No in-transit convoys found or data was empty after parsing.')
            else:
                for convoy_info in parsed_data:
                    print('  Name: ', convoy_info.get('convoy_name'))
                    print('    Current X: ', convoy_info.get('x'))  # For verification
                    print('    Current Y: ', convoy_info.get('y'))  # For verification
                    print('    Progress: ', convoy_info.get('journey', {}).get('progress'))
                    print('    Efficiency: ', convoy_info.get('efficiency'))
                    print('    Top Speed: ', convoy_info.get('top_speed'))
                    print('    Offroad Capability: ', convoy_info.get('offroad_capability'))
                    print('    Vehicle Names: ', convoy_info.get('vehicle_names'))
                    print('    Destination X: ', convoy_info.get('journey', {}).get('dest_x'))
                    print('    Destination Y: ', convoy_info.get('journey', {}).get('dest_y'))
                    print('    Convoy ID: ', convoy_info.get('convoy_id'))
                    print('')
            emit_signal('convoy_data_received', parsed_data)
        else:
            var error_msg_type = 'APICalls: Expected array from JSON response for all in-transit convoys, got %s.' % typeof(json_response)
            printerr(error_msg_type)
            emit_signal('fetch_error', error_msg_type)
    else:
        # Request failed or returned an error status code
        var error_msg = 'APICalls: Request failed with response code: %s' % response_code
        printerr(error_msg)
        printerr('Response body: ', body.get_string_from_utf8())
        emit_signal('fetch_error', error_msg)


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
        - journey (Dictionary) - The entire journey object.
    """
    var parsed_convoys: Array = []
    if not raw_convoy_list is Array:
        printerr('APICalls: Expected an array for parsing convoy data, got: ', typeof(raw_convoy_list))
        return parsed_convoys

    for convoy_data in raw_convoy_list:
        if not convoy_data is Dictionary:
            printerr('APICalls: Expected a dictionary for individual convoy data, got: ', typeof(convoy_data))
            continue  # Skip this item if it's not a dictionary

        var journey_data: Dictionary = convoy_data.get('journey', {})

        var convoy_details: Dictionary = {}
        convoy_details['convoy_id'] = convoy_data.get('convoy_id', '')  # UUIDs are best handled as Strings in GDScript
        convoy_details['convoy_name'] = convoy_data.get('name', 'Unknown Convoy')
        convoy_details['efficiency'] = convoy_data.get('efficiency', 0.0)
        convoy_details['top_speed'] = convoy_data.get('top_speed', 0.0)
        convoy_details['offroad_capability'] = convoy_data.get('offroad_capability', 0.0)
        # Populate top-level x and y directly from the convoy_data object
        convoy_details['x'] = convoy_data.get('x', 0.0)  # Default to 0.0 if not found
        convoy_details['y'] = convoy_data.get('y', 0.0)  # Default to 0.0 if not found

        var vehicle_names: Array = []
        var vehicles_raw: Array = convoy_data.get('vehicles', [])
        if vehicles_raw is Array:
            for vehicle_data in vehicles_raw:
                if vehicle_data is Dictionary:
                    vehicle_names.append(vehicle_data.get('name', 'Unknown Vehicle'))
        convoy_details['vehicle_names'] = vehicle_names
        convoy_details['journey'] = journey_data  # Store the (potentially modified) journey object

        parsed_convoys.append(convoy_details)

    return parsed_convoys
