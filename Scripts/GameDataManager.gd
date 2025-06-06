extends Node

# Emitted when the initial map and settlement data has been loaded.
signal map_data_loaded(map_tiles_data: Array)
signal settlement_data_updated(settlement_data_list: Array)

# Emitted when convoy data is received and processed.
# Passes the fully augmented convoy data.
signal convoy_data_updated(all_convoy_data_list: Array)

# --- Node References ---
# Adjust the path if your APICallsInstance is located differently relative to GameDataManager
# when GameDataManager is an Autoload (it will be /root/APICallsInstance if APICallsInstance is also an Autoload or a direct child of root).
# For now, assuming APICallsInstance will also be an Autoload or accessible globally.
var api_calls_node: Node = null # Will be fetched in _ready

# --- Configuration ---
@export var map_data_file_path: String = "res://Other/foo.json"

# --- Data Storage ---
var map_tiles: Array = []
var all_settlement_data: Array = []
var all_convoy_data: Array = [] # Stores augmented convoy data
var convoy_id_to_color_map: Dictionary = {}

# --- Internal State ---
var _last_assigned_color_idx: int = -1

# This should be the single source of truth for these colors.
const PREDEFINED_CONVOY_COLORS: Array[Color] = [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW, Color.CYAN, Color.MAGENTA,
	Color('orange'), Color('purple'), Color('lime'), Color('pink')
]


func _ready():
	print("!!!!!!!!!! GAMEDATAMANAGER _ready() IS RUNNING !!!!!!!!!!") # <-- ADD THIS
	# Attempt to get APICallsInstance node.
	# This needs to be robust to different scene setups (e.g., game_root vs. MapView running directly).
	var path_to_api_calls_str : String = "" # For logging the path used

	# Check path when game_root.tscn is the main scene
	if get_tree().root.has_node("GameRoot/MapRender/APICallsInstance"):
		path_to_api_calls_str = "GameRoot/MapRender/APICallsInstance"
		api_calls_node = get_tree().root.get_node(path_to_api_calls_str)
	# Check path when MapView.tscn is run directly (and its root is MapRender)
	elif get_tree().root.has_node("MapRender/APICallsInstance"):
		path_to_api_calls_str = "MapRender/APICallsInstance"
		api_calls_node = get_tree().root.get_node(path_to_api_calls_str)
	# Fallback: if APICallsInstance were an Autoload or direct child of root (less likely for current setup)
	elif get_tree().root.has_node("APICallsInstance"):
		path_to_api_calls_str = "APICallsInstance"
		api_calls_node = get_tree().root.get_node(path_to_api_calls_str)

	if is_instance_valid(api_calls_node):
		print("GameDataManager: Successfully found APICallsInstance at /root/%s" % path_to_api_calls_str)
	else:
		printerr("GameDataManager: APICallsInstance node not found. Tried common paths. Convoy data will not be fetched.")

	_load_map_and_settlement_data()

	if is_instance_valid(api_calls_node):
		if api_calls_node.has_signal('convoy_data_received'):
			api_calls_node.convoy_data_received.connect(_on_raw_convoy_data_received)
			print('GameDataManager: Successfully connected to APICalls.convoy_data_received signal.')
		else:
			printerr('GameDataManager: APICalls node does not have "convoy_data_received" signal.')
	else:
		printerr('GameDataManager: APICalls node not found. Cannot connect signal for convoy data.')


func _load_map_and_settlement_data():
	print("GameDataManager: Attempting to load map data from: '", map_data_file_path, "'") # <-- ADD THIS
	var file = FileAccess.open(map_data_file_path, FileAccess.READ)
	if FileAccess.get_open_error() != OK:
		printerr('GameDataManager: Error opening map json file: ', map_data_file_path)
		return

	var json_string = file.get_as_text()
	file.close()
	var json_data = JSON.parse_string(json_string)

	if json_data == null:
		printerr('GameDataManager: Error parsing JSON map data from: ', map_data_file_path)
		return

	if not json_data is Dictionary or not json_data.has('tiles'):
		printerr('GameDataManager: JSON data does not contain a "tiles" key.')
		return

	map_tiles = json_data.get('tiles', []) # type: Array
	map_data_loaded.emit.call_deferred(map_tiles) # Emit deferred
	print("GameDataManager: Map data loaded. Tiles count: %s" % map_tiles.size())

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
	settlement_data_updated.emit.call_deferred(all_settlement_data) # Emit deferred
	print("GameDataManager: Settlement data extracted. Count: %s" % all_settlement_data.size())


func _on_raw_convoy_data_received(raw_data: Variant):
	print('GameDataManager: Received raw convoy data.')
	var parsed_convoy_list: Array

	if raw_data is Array:
		parsed_convoy_list = raw_data
	elif raw_data is Dictionary and raw_data.has('results') and raw_data['results'] is Array:
		parsed_convoy_list = raw_data['results']
	else:
		printerr('GameDataManager: Received convoy data is not in a recognized format. Data: ', raw_data)
		all_convoy_data = [] # Clear existing data
		emit_signal("convoy_data_updated", all_convoy_data)
		return

	var augmented_convoys: Array = []
	for convoy_item_original in parsed_convoy_list:
		if convoy_item_original is Dictionary:
			var convoy_item_augmented = convoy_item_original.duplicate(true)

			# Assign color
			var convoy_id_val = convoy_item_augmented.get('convoy_id')
			if convoy_id_val != null:
				var convoy_id_str = str(convoy_id_val)
				if not convoy_id_str.is_empty() and not convoy_id_to_color_map.has(convoy_id_str):
					_last_assigned_color_idx = (_last_assigned_color_idx + 1) % PREDEFINED_CONVOY_COLORS.size()
					convoy_id_to_color_map[convoy_id_str] = PREDEFINED_CONVOY_COLORS[_last_assigned_color_idx]
			
			# Calculate progress details
			convoy_item_augmented = _calculate_convoy_progress_details(convoy_item_augmented)
			
			# Note: _pixel_offset_for_icon calculation is visual-context dependent and will be handled
			# by the consumer of this data (e.g., main.gd or a ConvoyVisualsManager)
			# as it requires map_renderer_node and tile pixel dimensions.

			augmented_convoys.append(convoy_item_augmented)
		else:
			augmented_convoys.append(convoy_item_original) # Should not happen with consistent API

	all_convoy_data = augmented_convoys
	print('GameDataManager: Processed and stored %s convoy objects.' % all_convoy_data.size())
	convoy_data_updated.emit.call_deferred(all_convoy_data) # Emit deferred


func get_convoy_id_to_color_map() -> Dictionary:
	"""Provides the current mapping of convoy IDs to colors."""
	return convoy_id_to_color_map


func _calculate_convoy_progress_details(convoy_data_item: Dictionary) -> Dictionary:
	# This function MODIFIES the convoy_data_item by adding '_current_segment_start_idx', 
	# '_progress_in_segment', and updates 'x' and 'y' to the precise interpolated tile coordinates.
	if not (convoy_data_item is Dictionary and convoy_data_item.has("journey")):
		return convoy_data_item

	var journey_data: Dictionary = convoy_data_item.get("journey")
	if not (journey_data is Dictionary):
		return convoy_data_item

	var route_x: Array = journey_data.get("route_x", [])
	var route_y: Array = journey_data.get("route_y", [])
	var journey_progress: float = journey_data.get("progress", 0.0)

	var current_segment_start_idx: int = -1
	var progress_within_segment: float = 0.0

	if route_x.size() >= 2 and route_y.size() == route_x.size():
		var num_total_segments = route_x.size() - 1
		var cumulative_dist: float = 0.0
		var total_path_length: float = 0.0

		for k_calc_idx in range(num_total_segments):
			var p_s_calc = Vector2(float(route_x[k_calc_idx]), float(route_y[k_calc_idx]))
			var p_e_calc = Vector2(float(route_x[k_calc_idx+1]), float(route_y[k_calc_idx+1]))
			total_path_length += p_s_calc.distance_to(p_e_calc)

		if total_path_length <= 0.001:
			current_segment_start_idx = 0
			progress_within_segment = 0.0
			if num_total_segments >= 0 :
				convoy_data_item["x"] = float(route_x[0])
				convoy_data_item["y"] = float(route_y[0])
		elif journey_progress <= 0.001:
			current_segment_start_idx = 0
			progress_within_segment = 0.0
			convoy_data_item["x"] = float(route_x[0])
			convoy_data_item["y"] = float(route_y[0])
		elif journey_progress >= total_path_length - 0.001:
			current_segment_start_idx = num_total_segments - 1
			progress_within_segment = 1.0
			convoy_data_item["x"] = float(route_x[num_total_segments])
			convoy_data_item["y"] = float(route_y[num_total_segments])
		else:
			var found_segment = false
			for k_idx in range(num_total_segments):
				var p_start_tile = Vector2(float(route_x[k_idx]), float(route_y[k_idx]))
				var p_end_tile = Vector2(float(route_x[k_idx+1]), float(route_y[k_idx+1]))
				var segment_length = p_start_tile.distance_to(p_end_tile)
				if journey_progress >= cumulative_dist - 0.001 and journey_progress < cumulative_dist + segment_length - 0.001:
					current_segment_start_idx = k_idx
					progress_within_segment = (journey_progress - cumulative_dist) / segment_length if segment_length > 0.0001 else 1.0
					progress_within_segment = clamp(progress_within_segment, 0.0, 1.0)
					var interpolated_pos_tile = p_start_tile.lerp(p_end_tile, progress_within_segment)
					convoy_data_item["x"] = interpolated_pos_tile.x
					convoy_data_item["y"] = interpolated_pos_tile.y
					found_segment = true; break
				cumulative_dist += segment_length
			if not found_segment:
				current_segment_start_idx = num_total_segments - 1; progress_within_segment = 1.0
				convoy_data_item["x"] = float(route_x[num_total_segments]); convoy_data_item["y"] = float(route_y[num_total_segments])

	convoy_data_item["_current_segment_start_idx"] = current_segment_start_idx
	convoy_data_item["_progress_in_segment"] = progress_within_segment
	return convoy_data_item


func request_convoy_data_refresh() -> void:
	"""
	Called by an external system (e.g., a timer in main.gd) to trigger a new fetch
	of convoy data.
	"""
	if is_instance_valid(api_calls_node) and api_calls_node.has_method("fetch_convoy_data"):
		api_calls_node.fetch_convoy_data()
	else:
		printerr("GameDataManager: Cannot request convoy data refresh. APICallsInstance is invalid or missing 'fetch_convoy_data' method.")