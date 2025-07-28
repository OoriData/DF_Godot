extends Node

# Manages the lifecycle and visual properties of ConvoyNode instances on the map.

const CONVOY_NODE_Z_INDEX = 1 # Same as it was in main.gd

var convoy_node_scene = preload("res://Scenes/ConvoyNode.tscn") # Ensure this path is correct

var _active_convoy_nodes: Dictionary = {} # { "convoy_id_str": ConvoyNode }

# Node references that will be set during initialization
var convoy_parent_node: Node
var terrain_tilemap: TileMapLayer # Reference to the tilemap for coordinate conversion

# Add a reference to GameDataManager
var gdm: Node = null


func initialize(p_convoy_parent_node: Node, p_terrain_tilemap: TileMapLayer):
	convoy_parent_node = p_convoy_parent_node
	terrain_tilemap = p_terrain_tilemap
	if not is_instance_valid(convoy_parent_node):
		printerr("ConvoyVisualsManager: convoy_parent_node is invalid during initialization.")
	if not is_instance_valid(terrain_tilemap):
		printerr("ConvoyVisualsManager: terrain_tilemap is invalid during initialization.")


func _ready():
	# Connect to GameDataManager's convoy_data_updated signal
	gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(gdm):
		if not gdm.is_connected("convoy_data_updated", Callable(self, "_on_gdm_convoy_data_updated")):
			gdm.convoy_data_updated.connect(Callable(self, "_on_gdm_convoy_data_updated"))


# Handler for updated convoy data
func _on_gdm_convoy_data_updated(all_convoy_data: Array) -> void:
	# This function is now the primary trigger for updating convoy visuals.
	# The augmentation and update logic will be called from here.

	# In a real scenario, this would come from an interaction manager or game state manager.
	var selected_convoy_ids_list: Array[String] = [] # Placeholder
	var convoy_id_to_color_map: Dictionary = {}
	if is_instance_valid(gdm):
		convoy_id_to_color_map = gdm.get_convoy_id_to_color_map()

	var augmented_data = augment_convoy_data_with_offsets(all_convoy_data)
	update_convoy_nodes_on_map(augmented_data, convoy_id_to_color_map, selected_convoy_ids_list)


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
						var p1_map: Vector2 = Vector2(float(route_x_s[k_segment]), float(route_y_s[k_segment]))
						var p2_map: Vector2 = Vector2(float(route_x_s[k_segment + 1]), float(route_y_s[k_segment + 1]))
						# Sort points to make segment key consistent regardless of direction
						var key_points = [p1_map, p2_map]
						key_points.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
						var segment_key = str(key_points[0]) + "-" + str(key_points[1])
						
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
					var r_x = journey_d.get("route_x")
					var r_y = journey_d.get("route_y")
					var p1_m = Vector2(float(r_x[current_seg_idx]), float(r_y[current_seg_idx]))
					var p2_m = Vector2(float(r_x[current_seg_idx + 1]), float(r_y[current_seg_idx + 1]))
					
					var key_points = [p1_m, p2_m]
					key_points.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
					var segment_key = str(key_points[0]) + "-" + str(key_points[1])
					
					var overlapping_convoys = shared_segments_data_for_icons.get(segment_key, [])
					var overlap_index = overlapping_convoys.find(current_convoy_id_str_for_offset)
					
					if overlap_index != -1:
						var angle = (PI * 2 * overlap_index) / max(1, overlapping_convoys.size())
						icon_offset_v = Vector2(cos(angle), sin(angle)) * base_offset_magnitude
			
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
