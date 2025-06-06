extends Node

# Manages the lifecycle and visual properties of ConvoyNode instances on the map.

const CONVOY_NODE_Z_INDEX = 1 # Same as it was in main.gd

var convoy_node_scene = preload("res://Scenes/ConvoyNode.tscn") # Ensure this path is correct

var _active_convoy_nodes: Dictionary = {} # { "convoy_id_str": ConvoyNode }

# Node references that will be set during initialization
var map_container: Node2D 
var map_renderer_node: Node # For offset calculations


func initialize(p_map_container: Node2D, p_map_renderer_node: Node):
	map_container = p_map_container
	map_renderer_node = p_map_renderer_node
	if not is_instance_valid(map_container):
		printerr("ConvoyVisualsManager: map_container is invalid during initialization.")
	if not is_instance_valid(map_renderer_node):
		printerr("ConvoyVisualsManager: map_renderer_node is invalid during initialization.")


func augment_convoy_data_with_offsets(
		convoy_data_array: Array, # Array of convoy data dictionaries
		map_tiles: Array,         # For calculating tile dimensions
		map_display_node: TextureRect # For full map texture size
	) -> Array:
	"""
	Calculates and adds '_pixel_offset_for_icon' to each convoy data dictionary.
	This logic is moved from main.gd's _on_gdm_convoy_data_updated.
	"""
	if not (is_instance_valid(map_display_node) and is_instance_valid(map_display_node.texture) and \
			is_instance_valid(map_renderer_node) and \
			map_tiles and not map_tiles.is_empty() and \
			map_tiles[0] is Array and not map_tiles[0].is_empty()):
		printerr("ConvoyVisualsManager (augment_convoy_data_with_offsets): Missing necessary data/nodes for offset calculation.")
		return convoy_data_array # Return original data if prerequisites are missing

	var actual_tile_width_f: float = 0.0
	var actual_tile_height_f: float = 0.0
	var scaled_journey_line_offset_step_pixels_for_icons: float = 0.0

	var map_cols: int = map_tiles[0].size()
	var map_rows: int = map_tiles.size()
	var full_map_texture_size: Vector2 = map_display_node.custom_minimum_size

	if map_cols > 0 and map_rows > 0 and full_map_texture_size.x > 0:
		actual_tile_width_f = full_map_texture_size.x / float(map_cols)
		actual_tile_height_f = full_map_texture_size.y / float(map_rows)
		
		var reference_float_tile_size_for_offsets: float = min(actual_tile_width_f, actual_tile_height_f)
		var base_tile_size_prop: float = map_renderer_node.base_tile_size_for_proportions
		var base_linear_visual_scale: float = 1.0
		if base_tile_size_prop > 0.001:
			base_linear_visual_scale = reference_float_tile_size_for_offsets / base_tile_size_prop
		scaled_journey_line_offset_step_pixels_for_icons = map_renderer_node.journey_line_offset_step_pixels * base_linear_visual_scale
	else:
		printerr("ConvoyVisualsManager: Cannot calculate common values for icon offset due to invalid map_tiles or map_display size.")
		return convoy_data_array

	var shared_segments_data_for_icons: Dictionary = {}
	for convoy_idx_for_shared_data in range(convoy_data_array.size()):
		var convoy_item_for_shared = convoy_data_array[convoy_idx_for_shared_data]
		if convoy_item_for_shared is Dictionary and convoy_item_for_shared.has("journey"):
			var journey_data_for_shared: Dictionary = convoy_item_for_shared.get("journey")
			if journey_data_for_shared is Dictionary:
				var route_x_s: Array = journey_data_for_shared.get("route_x", [])
				var route_y_s: Array = journey_data_for_shared.get("route_y", [])
				if route_x_s.size() >= 2 and route_y_s.size() == route_x_s.size():
					for k_segment in range(route_x_s.size() - 1):
						var p1_map = Vector2(float(route_x_s[k_segment]), float(route_y_s[k_segment]))
						var p2_map = Vector2(float(route_x_s[k_segment + 1]), float(route_y_s[k_segment + 1]))
						var segment_key = map_renderer_node.get_normalized_segment_key_with_info(p1_map, p2_map).key
						if not shared_segments_data_for_icons.has(segment_key):
							shared_segments_data_for_icons[segment_key] = []
						shared_segments_data_for_icons[segment_key].append(convoy_idx_for_shared_data)

	var processed_convoy_data_temp: Array = []
	for convoy_idx in range(convoy_data_array.size()):
		var convoy_item_augmented = convoy_data_array[convoy_idx].duplicate(true)
		if convoy_item_augmented is Dictionary:
			var icon_offset_v = Vector2.ZERO
			var current_seg_idx = convoy_item_augmented.get("_current_segment_start_idx", -1)
			var journey_d = convoy_item_augmented.get("journey")
			if journey_d is Dictionary and current_seg_idx != -1 and journey_d.get("route_x", []).size() > current_seg_idx + 1:
				var r_x = journey_d.get("route_x")
				var r_y = journey_d.get("route_y")
				var p1_m = Vector2(float(r_x[current_seg_idx]), float(r_y[current_seg_idx]))
				var p2_m = Vector2(float(r_x[current_seg_idx + 1]), float(r_y[current_seg_idx + 1]))
				var p1_px = Vector2i(round((p1_m.x + 0.5) * actual_tile_width_f), round((p1_m.y + 0.5) * actual_tile_height_f))
				var p2_px = Vector2i(round((p2_m.x + 0.5) * actual_tile_width_f), round((p2_m.y + 0.5) * actual_tile_height_f))
				icon_offset_v = map_renderer_node.get_journey_segment_offset_vector(p1_m, p2_m, p1_px, p2_px, convoy_idx, shared_segments_data_for_icons, scaled_journey_line_offset_step_pixels_for_icons)
			convoy_item_augmented["_pixel_offset_for_icon"] = icon_offset_v
			processed_convoy_data_temp.append(convoy_item_augmented)
	return processed_convoy_data_temp


func update_convoy_nodes_on_map(
		augmented_all_convoy_data: Array, # Already contains _pixel_offset_for_icon
		convoy_id_to_color_map: Dictionary,
		tile_pixel_width_on_texture: float,
		tile_pixel_height_on_texture: float
	):
	"""
	Creates, updates, or removes ConvoyNode instances based on the provided data.
	This logic is moved from main.gd's _update_convoy_nodes.
	"""
	if not is_instance_valid(map_container):
		printerr("ConvoyVisualsManager: map_container is not valid. Cannot update convoy nodes.")
		return
	if tile_pixel_width_on_texture <= 0 or tile_pixel_height_on_texture <= 0:
		printerr("ConvoyVisualsManager: Invalid tile dimensions for convoy nodes (w:%s, h:%s)." % [tile_pixel_width_on_texture, tile_pixel_height_on_texture])
		return

	var current_convoy_ids_from_data: Array[String] = []
	for convoy_item_data in augmented_all_convoy_data:
		var convoy_id_val = convoy_item_data.get("convoy_id")
		if convoy_id_val == null: continue
		var convoy_id_str = str(convoy_id_val)
		current_convoy_ids_from_data.append(convoy_id_str)

		var convoy_color = convoy_id_to_color_map.get(convoy_id_str, Color.GRAY)

		if _active_convoy_nodes.has(convoy_id_str):
			_active_convoy_nodes[convoy_id_str].set_convoy_data(convoy_item_data, convoy_color, tile_pixel_width_on_texture, tile_pixel_height_on_texture)
		else:
			var new_convoy_node = convoy_node_scene.instantiate()
			new_convoy_node.z_index = CONVOY_NODE_Z_INDEX
			map_container.add_child(new_convoy_node)
			new_convoy_node.set_convoy_data(convoy_item_data, convoy_color, tile_pixel_width_on_texture, tile_pixel_height_on_texture)
			_active_convoy_nodes[convoy_id_str] = new_convoy_node

	var ids_to_remove: Array = _active_convoy_nodes.keys().filter(func(id_str): return not current_convoy_ids_from_data.has(id_str))
	for id_str_to_remove in ids_to_remove:
		if _active_convoy_nodes.has(id_str_to_remove):
			_active_convoy_nodes[id_str_to_remove].queue_free()
			_active_convoy_nodes.erase(id_str_to_remove)