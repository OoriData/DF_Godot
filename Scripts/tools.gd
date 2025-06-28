extends Node
class_name Tools

# --- Binary Deserialization Helpers ---

static func _unpack_string(p_array: PackedByteArray, p_offset: int, p_length: int) -> String:
	""" Helper to read a fixed-length, null-padded string. """
	if p_offset + p_length > p_array.size():
		printerr("Tools (_unpack_string): Read out of bounds.")
		return ""
	var bytes = p_array.slice(p_offset, p_offset + p_length)
	var null_pos = bytes.find(0)
	if null_pos != -1:
		bytes = bytes.slice(0, null_pos)
	return bytes.get_string_from_utf8()

static func _read_u16_be(p_array: PackedByteArray, p_offset: int) -> int:
	""" Helper to read a 16-bit unsigned integer (H) in big-endian format. """
	if p_offset + 1 >= p_array.size():
		printerr("Tools (_read_u16_be): Read out of bounds.")
		return 0
	return (p_array[p_offset] << 8) | p_array[p_offset + 1]

static func _read_s16_be(p_array: PackedByteArray, p_offset: int) -> int:
	""" Helper to read a 16-bit signed integer (h) in big-endian format. """
	var val = _read_u16_be(p_array, p_offset)
	if val >= 32768: val -= 65536
	return val

static func _read_u32_be(p_array: PackedByteArray, p_offset: int) -> int:
	""" Helper to read a 32-bit unsigned integer (I or i) in big-endian format. """
	if p_offset + 3 >= p_array.size():
		printerr("Tools (_read_u32_be): Read out of bounds.")
		return 0
	return (p_array[p_offset] << 24) | (p_array[p_offset + 1] << 16) | (p_array[p_offset + 2] << 8) | p_array[p_offset + 3]

static func _read_f32_be(p_array: PackedByteArray, p_offset: int) -> float:
	""" Helper to read a 32-bit float (f) in big-endian format. """
	if p_offset + 3 >= p_array.size():
		printerr("Tools (_read_f32_be): Read out of bounds.")
		return 0.0
	var bytes = p_array.slice(p_offset, p_offset + 4)
	bytes.reverse() # Convert big-endian to little-endian for Godot's decoder
	return bytes.decode_float(0)

static func deserialize_cargo(p_binary_data: PackedByteArray, p_offset: int) -> Dictionary:
	var cargo: Dictionary = {}
	cargo['cargo_id'] = _unpack_string(p_binary_data, p_offset, 36); p_offset += 36
	cargo['name'] = _unpack_string(p_binary_data, p_offset, 64); p_offset += 64
	cargo['base_desc'] = _unpack_string(p_binary_data, p_offset, 512); p_offset += 512
	cargo['quantity'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	cargo['volume'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	cargo['weight'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	cargo['capacity'] = _read_f32_be(p_binary_data, p_offset); p_offset += 4
	cargo['fuel'] = _read_f32_be(p_binary_data, p_offset); p_offset += 4
	cargo['water'] = _read_f32_be(p_binary_data, p_offset); p_offset += 4
	cargo['food'] = _read_f32_be(p_binary_data, p_offset); p_offset += 4
	cargo['base_price'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	cargo['delivery_reward'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	cargo['distributor'] = _unpack_string(p_binary_data, p_offset, 36); p_offset += 36
	cargo['vehicle_id'] = _unpack_string(p_binary_data, p_offset, 36); p_offset += 36
	cargo['warehouse_id'] = _unpack_string(p_binary_data, p_offset, 36); p_offset += 36
	cargo['vendor_id'] = _unpack_string(p_binary_data, p_offset, 36); p_offset += 36
	return {"data": cargo, "offset": p_offset}

static func deserialize_vehicle(p_binary_data: PackedByteArray, p_offset: int) -> Dictionary:
	var vehicle: Dictionary = {}
	vehicle['vehicle_id'] = _unpack_string(p_binary_data, p_offset, 36); p_offset += 36
	vehicle['name'] = _unpack_string(p_binary_data, p_offset, 64); p_offset += 64
	vehicle['base_desc'] = _unpack_string(p_binary_data, p_offset, 512); p_offset += 512
	vehicle['wear'] = _read_f32_be(p_binary_data, p_offset); p_offset += 4
	vehicle['base_fuel_efficiency'] = _read_u16_be(p_binary_data, p_offset); p_offset += 2
	vehicle['base_top_speed'] = _read_u16_be(p_binary_data, p_offset); p_offset += 2
	vehicle['base_offroad_capability'] = _read_u16_be(p_binary_data, p_offset); p_offset += 2
	vehicle['base_cargo_capacity'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	vehicle['base_weight_capacity'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	vehicle['base_towing_capacity'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	vehicle['ap'] = _read_u16_be(p_binary_data, p_offset); p_offset += 2
	vehicle['base_max_ap'] = _read_u16_be(p_binary_data, p_offset); p_offset += 2
	vehicle['base_value'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	vehicle['vendor_id'] = _unpack_string(p_binary_data, p_offset, 36); p_offset += 36
	vehicle['warehouse_id'] = _unpack_string(p_binary_data, p_offset, 36); p_offset += 36
	return {"data": vehicle, "offset": p_offset}

static func deserialize_vendor(p_binary_data: PackedByteArray, p_offset: int) -> Dictionary:
	var vendor: Dictionary = {}
	vendor['vendor_id'] = _unpack_string(p_binary_data, p_offset, 36); p_offset += 36
	vendor['name'] = _unpack_string(p_binary_data, p_offset, 64); p_offset += 64
	vendor['base_desc'] = _unpack_string(p_binary_data, p_offset, 512); p_offset += 512
	vendor['money'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	vendor['fuel'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	vendor['fuel_price'] = _read_s16_be(p_binary_data, p_offset); p_offset += 2
	vendor['water'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	vendor['water_price'] = _read_s16_be(p_binary_data, p_offset); p_offset += 2
	vendor['food'] = _read_u32_be(p_binary_data, p_offset); p_offset += 4
	vendor['food_price'] = _read_s16_be(p_binary_data, p_offset); p_offset += 2
	vendor['repair_price'] = _read_s16_be(p_binary_data, p_offset); p_offset += 2
	var cargo_count = _read_u16_be(p_binary_data, p_offset); p_offset += 2
	var vehicle_count = _read_u16_be(p_binary_data, p_offset); p_offset += 2

	var cargo_inventory: Array = []
	for _i in range(cargo_count):
		var result = deserialize_cargo(p_binary_data, p_offset)
		cargo_inventory.append(result.data)
		p_offset = result.offset
	vendor['cargo_inventory'] = cargo_inventory

	var vehicle_inventory: Array = []
	for _i in range(vehicle_count):
		var result = deserialize_vehicle(p_binary_data, p_offset)
		vehicle_inventory.append(result.data)
		p_offset = result.offset
	vendor['vehicle_inventory'] = vehicle_inventory

	return {"data": vendor, "offset": p_offset}

static func deserialize_settlement(p_binary_data: PackedByteArray, p_offset: int) -> Dictionary:
	var settlement: Dictionary = {}
	settlement['sett_id'] = _unpack_string(p_binary_data, p_offset, 36); p_offset += 36
	settlement['name'] = _unpack_string(p_binary_data, p_offset, 64); p_offset += 64
	settlement['base_desc'] = _unpack_string(p_binary_data, p_offset, 1024); p_offset += 1024
	var sett_type_id = p_binary_data[p_offset]; p_offset += 1
	var _imports_count = p_binary_data[p_offset]; p_offset += 1 # Not used in client
	var _exports_count = p_binary_data[p_offset]; p_offset += 1 # Not used in client
	var vendor_count = p_binary_data[p_offset]; p_offset += 1

	var sett_types = {1: 'tutorial', 2: 'dome', 3: 'city', 4: 'town', 5: 'city-state', 6: 'military_base', 7 : 'village'}
	settlement['sett_type'] = sett_types.get(sett_type_id, 'unknown')

	var vendors: Array = []
	for _i in range(vendor_count):
		var result = deserialize_vendor(p_binary_data, p_offset)
		var vendor_data = result.data
		vendor_data['sett_id'] = settlement['sett_id']
		vendors.append(vendor_data)
		p_offset = result.offset
	settlement['vendors'] = vendors

	return {"data": settlement, "offset": p_offset}

static func deserialize_map_data(p_binary_data: PackedByteArray) -> Dictionary:
	var offset: int = 0
	if p_binary_data.size() < 4: return {}

	var height: int = _read_u16_be(p_binary_data, offset); offset += 2
	var width: int = _read_u16_be(p_binary_data, offset); offset += 2

	var tiles: Array = []
	for y in range(height):
		var row: Array = []
		for x in range(width):
			if offset + 6 > p_binary_data.size(): # Bounds check for 6-byte tile header
				printerr("Tools (deserialize_map_data): Read out of bounds for tile header at (%s, %s)." % [x, y])
				return {}

			var terrain_difficulty: int = p_binary_data[offset]; offset += 1
			var region: int = p_binary_data[offset]; offset += 1
			var weather: int = p_binary_data[offset]; offset += 1
			var special: int = p_binary_data[offset]; offset += 1
			var settlement_count: int = _read_u16_be(p_binary_data, offset); offset += 2

			var settlements: Array = []
			for _i in range(settlement_count):
				var result = deserialize_settlement(p_binary_data, offset)
				var settlement_data = result.data
				settlement_data['x'] = x
				settlement_data['y'] = y
				settlements.append(settlement_data)
				offset = result.offset

			row.append({
				'x': x, 'y': y, 'terrain_difficulty': terrain_difficulty,
				'region': region, 'weather': weather, 'special': special, 'settlements': settlements
			})
		tiles.append(row)

	var highlights: Array = []
	var lowlights: Array = []
	for location_list in [highlights, lowlights]:
		var count: int = _read_u16_be(p_binary_data, offset); offset += 2
		for _i in range(count):
			var h_x: int = _read_u16_be(p_binary_data, offset); offset += 2
			var h_y: int = _read_u16_be(p_binary_data, offset); offset += 2
			location_list.append([h_x, h_y])

	return { 'tiles': tiles, 'highlights': highlights, 'lowlights': lowlights }
