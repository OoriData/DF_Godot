extends Node

# Manages the lifecycle and visual properties of ConvoyNode instances on the map.

const CONVOY_NODE_Z_INDEX = 10 # Same as it was in main.gd

var convoy_node_scene = preload("res://Scenes/ConvoyNode.tscn") # Ensure this path is correct

var _active_convoy_nodes: Dictionary = {} # { "convoy_id_str": ConvoyNode }

# Node references that will be set during initialization
var convoy_parent_node: Node
var terrain_tilemap: TileMapLayer # Reference to the tilemap for coordinate conversion

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
@onready var _convoy_service: Node = get_node_or_null("/root/ConvoyService")

var _latest_convoys: Array = []
var _selected_convoy_ids: Array[String] = []
var _initialized: bool = false


func initialize(p_convoy_parent_node: Node, p_terrain_tilemap: TileMapLayer):
	convoy_parent_node = p_convoy_parent_node
	terrain_tilemap = p_terrain_tilemap
	if not is_instance_valid(convoy_parent_node):
		printerr("ConvoyVisualsManager: convoy_parent_node is invalid during initialization.")
	if not is_instance_valid(terrain_tilemap):
		printerr("ConvoyVisualsManager: terrain_tilemap is invalid during initialization.")
	_initialized = true
	# If we already have data (autoload order), render immediately.
	if not _latest_convoys.is_empty():
		_refresh_visuals()


func _ready():
	# Subscribe to store snapshots.
	if is_instance_valid(_store) and _store.has_signal("convoys_changed"):
		if not _store.convoys_changed.is_connected(_on_store_convoys_changed):
			_store.convoys_changed.connect(_on_store_convoys_changed)
		_latest_convoys = _store.get_convoys() if _store.has_method("get_convoys") else []

	# Subscribe to selection highlights (migrated selection system).
	if is_instance_valid(_hub) and _hub.has_signal("selected_convoy_ids_changed"):
		if not _hub.selected_convoy_ids_changed.is_connected(_on_selected_convoy_ids_changed):
			_hub.selected_convoy_ids_changed.connect(_on_selected_convoy_ids_changed)

	# If initialized early and store already has data, render now.
	if _initialized and not _latest_convoys.is_empty():
		_refresh_visuals()


func _on_store_convoys_changed(convoys: Array) -> void:
	_latest_convoys = convoys if convoys != null else []
	var logger := get_node_or_null("/root/Logger")
	if is_instance_valid(logger) and logger.has_method("debug"):
		logger.debug("ConvoyVisualsManager.store_update count=%s", _latest_convoys.size())
	_refresh_visuals()


func _on_selected_convoy_ids_changed(selected_ids: Array) -> void:
	_selected_convoy_ids = []
	if selected_ids is Array:
		for item in selected_ids:
			var id_str := str(item)
			if id_str != "":
				_selected_convoy_ids.append(id_str)
	_refresh_visuals()


func update_selected_convoys(selected_ids: Array) -> void:
	# Back-compat: main.gd currently calls this directly.
	_on_selected_convoy_ids_changed(selected_ids)


func _refresh_visuals() -> void:
	if not _initialized:
		return
	if not is_instance_valid(convoy_parent_node) or not is_instance_valid(terrain_tilemap):
		return
	var convoy_id_to_color_map: Dictionary = {}
	if is_instance_valid(_convoy_service) and _convoy_service.has_method("get_color_map"):
		convoy_id_to_color_map = _convoy_service.get_color_map()
	var augmented_data = augment_convoy_data_with_offsets(_latest_convoys)
	update_convoy_nodes_on_map(augmented_data, convoy_id_to_color_map, _selected_convoy_ids)


func augment_convoy_data_with_offsets(convoy_data_array: Array) -> Array:
	"""
	Calculates and adds '_pixel_offset_for_icon' to each convoy data dictionary.
	This logic is simplified as we now use the TileMap for coordinate info.
	"""
	if not is_instance_valid(terrain_tilemap) or not is_instance_valid(terrain_tilemap.tile_set):
		printerr("ConvoyVisualsManager: terrain_tilemap or its tile_set is not valid for augmenting data.")
		return convoy_data_array

	var tile_size = terrain_tilemap.tile_set.tile_size
	var base_offset_magnitude = min(tile_size.x, tile_size.y) * 0.2

	# --- Build shared_segments_data for icon offsetting ---
	var shared_segments_data_for_icons: Dictionary = {}
	for convoy_item_for_shared in convoy_data_array:
		if convoy_item_for_shared is Dictionary and convoy_item_for_shared.has("journey"):
			var convoy_id_for_segment = str(convoy_item_for_shared.get("convoy_id", ""))
			if convoy_id_for_segment.is_empty(): continue

			var journey_data_for_shared: Dictionary = {}
			var raw_journey = convoy_item_for_shared.get("journey")
			if raw_journey is Dictionary:
				journey_data_for_shared = raw_journey
			if journey_data_for_shared is Dictionary:
				var route_x_s: Array = journey_data_for_shared.get("route_x", [])
				var route_y_s: Array = journey_data_for_shared.get("route_y", [])
				if route_x_s.size() >= 2 and route_y_s.size() == route_x_s.size():
					for k_segment in range(route_x_s.size() - 1):
						var a := Vector2i(int(route_x_s[k_segment]), int(route_y_s[k_segment]))
						var b := Vector2i(int(route_x_s[k_segment + 1]), int(route_y_s[k_segment + 1]))
						# Normalize order for key stability (consistent with UI_manager.gd)
						var p_min := a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
						var p_max := b if (p_min == a) else a
						var segment_key := "%d,%d-%d,%d" % [p_min.x, p_min.y, p_max.x, p_max.y]
						
						if not shared_segments_data_for_icons.has(segment_key):
							shared_segments_data_for_icons[segment_key] = []
						if not shared_segments_data_for_icons[segment_key].has(convoy_id_for_segment):
							shared_segments_data_for_icons[segment_key].append(convoy_id_for_segment)
	# Sort the convoy_id_str lists in shared_segments_data_for_icons for stable ordering
	for seg_key_sort in shared_segments_data_for_icons:
		shared_segments_data_for_icons[seg_key_sort].sort()

	# --- Augment convoy data further with _pixel_offset_for_icon ---
	var processed_convoy_data_temp: Array = []
	for convoy_item in convoy_data_array:
		var convoy_item_augmented = convoy_item.duplicate(true)
		if convoy_item_augmented is Dictionary:
			var icon_offset_v = Vector2.ZERO
			var current_convoy_id_str_for_offset = str(convoy_item_augmented.get("convoy_id", ""))
			if current_convoy_id_str_for_offset.is_empty(): continue

			if convoy_item_augmented.has("journey"):
				var current_seg_idx = convoy_item_augmented.get("_current_segment_start_idx", -1)
				var journey_d: Dictionary = {}
				var raw_journey = convoy_item_augmented.get("journey")
				if raw_journey is Dictionary:
					journey_d = raw_journey

				if current_seg_idx != -1 and journey_d.get("route_x", []).size() > current_seg_idx + 1:
					var rx_c = journey_d.get("route_x")
					var ry_c = journey_d.get("route_y")
					var si = current_seg_idx
					var a := Vector2i(int(rx_c[si]), int(ry_c[si]))
					var b := Vector2i(int(rx_c[si+1]), int(ry_c[si+1]))
					# Normalize order for key stability (consistent with UI_manager.gd)
					var p_min := a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
					var p_max := b if (p_min == a) else a
					var segment_key := "%d,%d-%d,%d" % [p_min.x, p_min.y, p_max.x, p_max.y]
					
					var overlapping_convoys = shared_segments_data_for_icons.get(segment_key, [])
					var overlap_index = overlapping_convoys.find(current_convoy_id_str_for_offset)
					
					if overlap_index != -1:
						# Use a canonical direction for normal calculation (p_min to p_max)
						# so that lanes are consistent regardless of which way the convoy is moving.
						var pA_canonical := terrain_tilemap.map_to_local(p_min)
						var pB_canonical := terrain_tilemap.map_to_local(p_max)
						var dir_canonical := pB_canonical - pA_canonical
						
						var normal_canonical := Vector2.ZERO
						if dir_canonical.length() > 0.0001:
							normal_canonical = Vector2(-dir_canonical.y, dir_canonical.x).normalized()
						
						var lane_centered = 0.0
						if overlap_index != -1:
							var pA_actual := terrain_tilemap.map_to_local(a)
							var pB_actual := terrain_tilemap.map_to_local(b)
							var travel_dir := pB_actual - pA_actual
							var alignment := 1.0 if (travel_dir.dot(dir_canonical) >= 0.0) else -1.0
							lane_centered = (float(overlap_index) - float(overlapping_convoys.size() - 1) * 0.5) * alignment
						
						# base_offset_magnitude is 20% of tile size usually
						# We should match the base_sep_px from UI_manager.gd (which is 28% of tile size)
						var tile_size_vec = terrain_tilemap.tile_set.tile_size
						var sep_px = max(1.0, min(tile_size_vec.x, tile_size_vec.y) * 0.32)
						
						icon_offset_v = normal_canonical * lane_centered * sep_px
			
			convoy_item_augmented["_pixel_offset_for_icon"] = icon_offset_v
			processed_convoy_data_temp.append(convoy_item_augmented)
			
	return processed_convoy_data_temp


func update_convoy_nodes_on_map(
		augmented_all_convoy_data: Array,
		convoy_id_to_color_map: Dictionary,
		selected_convoy_ids_list: Array[String]
	):
	"""
	Creates, updates, or removes ConvoyNode instances based on the provided data.
	Uses the TileMapLayer for positioning.
	"""
	if not is_instance_valid(convoy_parent_node):
		printerr("ConvoyVisualsManager: convoy_parent_node is not valid. Cannot update convoy nodes.")
		return
	if not is_instance_valid(terrain_tilemap):
		printerr("ConvoyVisualsManager: terrain_tilemap is not valid. Cannot update convoy nodes.")
		return

	var current_convoy_ids_from_data: Array[String] = []
	for convoy_item_data in augmented_all_convoy_data:
		var convoy_id_val = convoy_item_data.get("convoy_id")
		if convoy_id_val == null: continue
		var convoy_id_str = str(convoy_id_val)
		current_convoy_ids_from_data.append(convoy_id_str)

		var is_selected = selected_convoy_ids_list.has(convoy_id_str)
		var convoy_color = convoy_id_to_color_map.get(convoy_id_str, Color.GRAY)

		if _active_convoy_nodes.has(convoy_id_str):
			var existing_node = _active_convoy_nodes[convoy_id_str]
			# Pass the tilemap instead of pixel sizes
			existing_node.set_convoy_data(convoy_item_data, convoy_color, terrain_tilemap)
			existing_node.z_index = CONVOY_NODE_Z_INDEX + 1 if is_selected else CONVOY_NODE_Z_INDEX
			# Position is now handled entirely within ConvoyNode.gd
		else:
			var new_convoy_node = convoy_node_scene.instantiate()
			convoy_parent_node.add_child(new_convoy_node)
			# Pass the tilemap instead of pixel sizes
			new_convoy_node.set_convoy_data(convoy_item_data, convoy_color, terrain_tilemap)
			new_convoy_node.z_index = CONVOY_NODE_Z_INDEX + 1 if is_selected else CONVOY_NODE_Z_INDEX
			
			new_convoy_node.name = "ConvoyNode_" + convoy_id_str 
			_active_convoy_nodes[convoy_id_str] = new_convoy_node

	var ids_to_remove: Array = _active_convoy_nodes.keys().filter(func(id_str): return not current_convoy_ids_from_data.has(id_str))
	for id_str_to_remove in ids_to_remove:
		if _active_convoy_nodes.has(id_str_to_remove):
			_active_convoy_nodes[id_str_to_remove].queue_free()
			_active_convoy_nodes.erase(id_str_to_remove)
