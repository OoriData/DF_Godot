extends Node
class_name VendorCargoAggregator
const ItemsData = preload("res://Scripts/Data/Items.gd") # ensures CargoItem class is registered
const INTRINSIC_RESOURCE_CONTAINER_PART_ID := "7d1c1f56-e215-4b16-89f9-dca416a2d58e"

# Helper to aggregate vendor and convoy cargo into category buckets.
# Buckets use stable keys: "missions", "vehicles", "parts", "other", "resources".


static func _to_float_any(v: Variant) -> float:
	if v == null:
		return 0.0
	if v is float or v is int:
		return float(v)
	if v is String:
		var s := (v as String).strip_edges()
		if s.is_valid_float():
			return float(s)
		if s.is_valid_int():
			return float(int(s))
	return 0.0


static func _to_int_any(v: Variant) -> int:
	if v == null:
		return 0
	if v is int:
		return int(v)
	if v is float:
		return int(v)
	if v is String:
		var s := (v as String).strip_edges()
		if s.is_valid_int():
			return int(s)
		if s.is_valid_float():
			return int(float(s))
	return 0


static func _has_positive_price(d: Dictionary, key: String) -> bool:
	if d == null:
		return false
	if not d.has(key):
		return false
	return _to_float_any(d.get(key)) > 0.0


static func _is_intrinsic_resource_container(item: Dictionary) -> bool:
	if item == null:
		return false
	var iid: String = str(item.get("intrinsic_part_id", "")).strip_edges()
	if iid != "" and iid == INTRINSIC_RESOURCE_CONTAINER_PART_ID:
		return true
	# Some payload shapes may only include the container's part_id.
	var pid: String = str(item.get("part_id", "")).strip_edges()
	return pid != "" and pid == INTRINSIC_RESOURCE_CONTAINER_PART_ID

static func build_vendor_buckets(vendor_data: Dictionary, perf_log_enabled: bool, get_vendor_name_for_recipient: Callable) -> Dictionary:
	var aggregated_missions: Dictionary = {}
	var aggregated_resources: Dictionary = {}
	var aggregated_vehicles: Dictionary = {}
	var aggregated_parts: Dictionary = {}
	var aggregated_other: Dictionary = {}

	if vendor_data == null:
		return {
			"missions": aggregated_missions,
			"vehicles": aggregated_vehicles,
			"parts": aggregated_parts,
			"other": aggregated_other,
			"resources": aggregated_resources,
		}

	var v_fuel_p = vendor_data.get("fuel_price", 0)
	var v_water_p = vendor_data.get("water_price", 0)
	var v_food_p = vendor_data.get("food_price", 0)

	for item in vendor_data.get("cargo_inventory", []):
		# Do not surface intrinsic resource containers (e.g., vehicle fuel tanks) as tradable cargo.
		if item is Dictionary and _is_intrinsic_resource_container(item as Dictionary):
			continue

		var category_dict: Dictionary
		var mission_vendor_name: String = ""
		
		# Inject current vendor prices so PriceUtil can see them on the item level
		if item is Dictionary:
			if not item.has("fuel_price") or item.get("fuel_price") == null: item["fuel_price"] = v_fuel_p
			if not item.has("water_price") or item.get("water_price") == null: item["water_price"] = v_water_p
			if not item.has("food_price") or item.get("food_price") == null: item["food_price"] = v_food_p

		# Missions may carry either `recipient` or `mission_vendor_id` depending on payload shape.
		# Prefer `recipient`, but fall back to `mission_vendor_id` so Destination can be resolved.
		var recipient_id_any: Variant = null
		if item.get("recipient") != null:
			recipient_id_any = item.get("recipient")
		elif item.get("mission_vendor_id") != null:
			recipient_id_any = item.get("mission_vendor_id")
		if recipient_id_any != null:
			if perf_log_enabled:
				print("[VendorCargoAggregator] vendor mission item keys=", (item.keys() if item is Dictionary else []))
			category_dict = aggregated_missions
			if recipient_id_any and get_vendor_name_for_recipient.is_valid():
				mission_vendor_name = str(get_vendor_name_for_recipient.call(recipient_id_any))
		elif (item.has("food") and item.get("food") != null and item.get("food") > 0) or \
			 (item.has("water") and item.get("water") != null and item.get("water") > 0) or \
			 (item.has("fuel") and item.get("fuel") != null and item.get("fuel") > 0):
			category_dict = aggregated_resources
		else:
			# Part identification is strictly slot-based.
			if ItemsData != null and ItemsData.PartItem and ItemsData.PartItem._looks_like_part_dict(item):
				category_dict = aggregated_parts
				_aggregate_vendor_item(category_dict, item, mission_vendor_name, perf_log_enabled)
				continue
			category_dict = aggregated_other
		if perf_log_enabled:
			print("[VendorCargoAggregator] Aggregating vendor cargo item:", item)
		var dr_v = item.get("delivery_reward")
		var looks_mission := (dr_v is float or dr_v is int) and float(dr_v) > 0.0
		if looks_mission and not item.has("recipient") and item.has("mission_vendor_id"):
			if perf_log_enabled:
				print("[VendorCargoAggregator] mission without recipient; mission_vendor_id=", str(item.get("mission_vendor_id")))
		_aggregate_vendor_item(category_dict, item, mission_vendor_name, perf_log_enabled)

	# --- Create virtual items for raw resources AFTER processing normal cargo ---
	var raw_fuel_val = vendor_data.get("fuel", 0)
	var raw_fuel_price_val = vendor_data.get("fuel_price", 0)
	if perf_log_enabled:
		print("[VendorCargoAggregator] RAW_FUEL before cast value=", raw_fuel_val, " type=", typeof(raw_fuel_val), " price=", raw_fuel_price_val)
	var fuel_quantity := _to_int_any(raw_fuel_val)
	var fuel_price := _to_float_any(raw_fuel_price_val)
	if fuel_quantity > 0 and fuel_price > 0.0:
		var fuel_item = {
			"name": "Fuel (Bulk)",
			"base_desc": "Bulk fuel to fill your containers.",
			"quantity": fuel_quantity,
			"fuel": fuel_quantity,
			"fuel_price": fuel_price,
			"is_raw_resource": true,
			"unit_weight": 1.0,
			"unit_volume": 0.0,
			"total_weight": fuel_quantity * 1.0,
			"total_volume": 0.0,
		}
		if perf_log_enabled:
			print("[VendorCargoAggregator] Creating vendor bulk fuel item:", fuel_item)
		_aggregate_vendor_item(aggregated_resources, fuel_item, "", perf_log_enabled)
	elif fuel_quantity > 0 and perf_log_enabled:
		print("[VendorCargoAggregator] Skipping vendor bulk fuel (missing/zero price)")

	var raw_water_val = vendor_data.get("water", 0)
	var raw_water_price_val = vendor_data.get("water_price", 0)
	if perf_log_enabled:
		print("[VendorCargoAggregator] RAW_WATER before cast value=", raw_water_val, " type=", typeof(raw_water_val), " price=", raw_water_price_val)
	var water_quantity := _to_int_any(raw_water_val)
	var water_price := _to_float_any(raw_water_price_val)
	if water_quantity > 0 and water_price > 0.0:
		var water_item = {
			"name": "Water (Bulk)",
			"base_desc": "Bulk water to fill your containers.",
			"quantity": water_quantity,
			"water": water_quantity,
			"water_price": water_price,
			"is_raw_resource": true,
			"unit_weight": 1.0,
			"unit_volume": 0.0,
			"total_weight": water_quantity * 1.0,
			"total_volume": 0.0,
		}
		if perf_log_enabled:
			print("[VendorCargoAggregator] Creating vendor bulk water item:", water_item)
		_aggregate_vendor_item(aggregated_resources, water_item, "", perf_log_enabled)
	elif water_quantity > 0 and perf_log_enabled:
		print("[VendorCargoAggregator] Skipping vendor bulk water (missing/zero price)")

	var raw_food_val = vendor_data.get("food", 0)
	var raw_food_price_val = vendor_data.get("food_price", 0)
	if perf_log_enabled:
		print("[VendorCargoAggregator] RAW_FOOD before cast value=", raw_food_val, " type=", typeof(raw_food_val), " price=", raw_food_price_val)
	var food_quantity := _to_int_any(raw_food_val)
	var food_price := _to_float_any(raw_food_price_val)
	if food_quantity > 0 and food_price > 0.0:
		var food_item = {
			"name": "Food (Bulk)",
			"base_desc": "Bulk food supplies.",
			"quantity": food_quantity,
			"food": food_quantity,
			"food_price": food_price,
			"is_raw_resource": true,
			"unit_weight": 1.0,
			"unit_volume": 0.0,
			"total_weight": food_quantity * 1.0,
			"total_volume": 0.0,
		}
		if perf_log_enabled:
			print("[VendorCargoAggregator] Creating vendor bulk food item:", food_item)
		_aggregate_vendor_item(aggregated_resources, food_item, "", perf_log_enabled)
	elif food_quantity > 0 and perf_log_enabled:
		print("[VendorCargoAggregator] Skipping vendor bulk food (missing/zero price)")

	for vehicle in vendor_data.get("vehicle_inventory", []):
		var vid := str(vehicle.get("vehicle_id", ""))
		if vid != "":
			var key := vid
			var vehicle_name := str(vehicle.get("name", "Unknown Vehicle"))
			if not aggregated_vehicles.has(key):
				aggregated_vehicles[key] = {
					"item_data": vehicle,
					"display_name": vehicle_name,
					"total_quantity": 0,
					"total_weight": 0.0,
					"total_volume": 0.0,
					"mission_vendor_name": "",
				}
			aggregated_vehicles[key].total_quantity += 1
		else:
			_aggregate_vendor_item(aggregated_vehicles, vehicle, "", perf_log_enabled)

	return {
		"missions": aggregated_missions,
		"vehicles": aggregated_vehicles,
		"parts": aggregated_parts,
		"other": aggregated_other,
		"resources": aggregated_resources,
	}


static func build_convoy_buckets(convoy_data: Dictionary, vendor_data: Dictionary, _current_mode: String, perf_log_enabled: bool, get_vendor_name_for_recipient: Callable, allow_vehicle_sell: bool) -> Dictionary:
	var aggregated_missions: Dictionary = {}
	var aggregated_resources: Dictionary = {}
	var aggregated_parts: Dictionary = {}
	var aggregated_vehicles: Dictionary = {}
	var aggregated_other: Dictionary = {}

	if convoy_data == null:
		return {
			"missions": aggregated_missions,
			"vehicles": aggregated_vehicles,
			"parts": aggregated_parts,
			"other": aggregated_other,
			"resources": aggregated_resources,
		}

	var found_any_cargo = false
	var is_sell_mode: bool = str(_current_mode) == "sell"
	var vendor_can_buy_cargo: bool = true # Updated rule: every vendor allows selling cargo.
	var vendor_vehicle_inventory_any: Variant = (vendor_data.get("vehicle_inventory") if vendor_data != null else null)
	
	var v_fuel_p = vendor_data.get("fuel_price", 0) if (vendor_data is Dictionary) else 0
	var v_water_p = vendor_data.get("water_price", 0) if (vendor_data is Dictionary) else 0
	var v_food_p = vendor_data.get("food_price", 0) if (vendor_data is Dictionary) else 0
	
	var vendor_can_buy_vehicles: bool = vendor_vehicle_inventory_any is Array and not (vendor_vehicle_inventory_any as Array).is_empty()
	var vendor_buys_fuel: bool = _has_positive_price(vendor_data, "fuel_price")
	var vendor_buys_water: bool = _has_positive_price(vendor_data, "water_price")
	var vendor_buys_food: bool = _has_positive_price(vendor_data, "food_price")
	# Updated rule: vehicles should only show in SELL when vendor actually has vehicles.
	var vehicle_sell_allowed: bool = vendor_can_buy_vehicles
	# Some convoy snapshots use different key shapes (e.g. `all_cargo` and `vehicles`).
	var convoy_all_cargo_any: Variant = convoy_data.get("all_cargo")
	var convoy_vehicles_any: Variant = convoy_data.get("vehicles")
	if perf_log_enabled and is_sell_mode:
		var ac_sz := (int((convoy_all_cargo_any as Array).size()) if convoy_all_cargo_any is Array else -1)
		var v_sz := (int((convoy_vehicles_any as Array).size()) if convoy_vehicles_any is Array else -1)
		print("[VendorCargoAggregator][SellDiag] convoy shapes all_cargo_size=", ac_sz, " vehicles_size=", v_sz,
			" has_vehicle_details_list=", convoy_data.has("vehicle_details_list"),
			" has_cargo_inventory=", convoy_data.has("cargo_inventory"))
	if perf_log_enabled and is_sell_mode:
		var vid_dbg := str((vendor_data.get("vendor_id", "") if vendor_data != null else ""))
		print("[VendorCargoAggregator][SellDiag] vendor_id=", vid_dbg,
			" vendor_can_buy_cargo=", vendor_can_buy_cargo,
			" vendor_can_buy_vehicles=", vendor_can_buy_vehicles,
			" allow_vehicle_sell=", bool(allow_vehicle_sell),
			" vehicle_sell_allowed=", vehicle_sell_allowed,
			" buys(fuel/water/food)=", vendor_buys_fuel, "/", vendor_buys_water, "/", vendor_buys_food,
			" convoy_keys=", (convoy_data.keys() if convoy_data != null else []))
	if convoy_data.has("vehicle_details_list"):
		for vehicle in convoy_data.vehicle_details_list:
			var vehicle_name = vehicle.get("name", "Unknown Vehicle")
			if vehicle_sell_allowed:
				var vid := str(vehicle.get("vehicle_id", ""))
				if vid != "":
					aggregated_vehicles[vid] = {
						"item_data": vehicle,
						"display_name": vehicle_name,
						"total_quantity": 1,
						"total_weight": 0.0,
						"total_volume": 0.0,
						"locations": {},
					}
			if vehicle.has("cargo_items_typed") and vehicle["cargo_items_typed"] is Array and not (vehicle["cargo_items_typed"] as Array).is_empty():
				for typed in vehicle["cargo_items_typed"]:
					if not typed is CargoItem:
						continue
					found_any_cargo = true
					var raw_item: Dictionary = typed.raw.duplicate(true)
					# Do not surface intrinsic resource containers as tradable cargo.
					if _is_intrinsic_resource_container(raw_item):
						continue
					
					# Inject current vendor prices so PriceUtil can see them on the item level
					if not raw_item.has("fuel_price") or raw_item.get("fuel_price") == null: raw_item["fuel_price"] = v_fuel_p
					if not raw_item.has("water_price") or raw_item.get("water_price") == null: raw_item["water_price"] = v_water_p
					if not raw_item.has("food_price") or raw_item.get("food_price") == null: raw_item["food_price"] = v_food_p

					raw_item["quantity"] = typed.quantity
					raw_item["category"] = typed.category
					raw_item["weight"] = typed.total_weight
					raw_item["volume"] = typed.total_volume
					if typed.has_method("get_modifier_summary"):
						var mods: String = str(typed.get_modifier_summary())
						if mods != "":
							raw_item["modifiers"] = mods
					if "stats" in typed and typed.stats is Dictionary and not typed.stats.is_empty():
						raw_item["stats"] = typed.stats.duplicate(true)
					var category_dict: Dictionary
					var is_mission_item: bool = false
					var mission_vendor_name: String = ""
					match typed.category:
						"mission":
							category_dict = aggregated_missions
							is_mission_item = true
						"resource":
							category_dict = aggregated_resources
						"part":
							category_dict = aggregated_parts
						_:
							category_dict = aggregated_other
					var dr_t = raw_item.get("delivery_reward")
					if raw_item.get("recipient") != null or ((dr_t is float or dr_t is int) and float(dr_t) > 0.0):
						category_dict = aggregated_missions
						is_mission_item = true
					if is_mission_item:
						var recipient_id: Variant = raw_item.get("recipient")
						if recipient_id == null:
							recipient_id = raw_item.get("mission_vendor_id")
						if recipient_id and get_vendor_name_for_recipient.is_valid():
							mission_vendor_name = str(get_vendor_name_for_recipient.call(recipient_id))
					# SELL: only include what this vendor can buy.
					if is_sell_mode:
						# Resource-bearing cargo is only sellable if the vendor has a positive price for
						# ALL contained resource types, regardless of which bucket it would land in.
						if not is_mission_item and not VendorTradeVM.vendor_can_buy_item_resources(vendor_data if (vendor_data is Dictionary) else {}, raw_item):
							continue
						# Non-resource cargo (and parts-as-cargo) are always sellable; missions are always allowed.
					_aggregate_item(category_dict, raw_item, vehicle_name, mission_vendor_name, perf_log_enabled)
			else:
				for item in vehicle.get("cargo", []):
					# Do not surface intrinsic resource containers as tradable cargo.
					if item is Dictionary and _is_intrinsic_resource_container(item as Dictionary):
						continue

					found_any_cargo = true
					var category_dict2: Dictionary
					var is_mission_item2: bool = false
					var mission_vendor_name2: String = ""
					var dr = item.get("delivery_reward")
					if item.get("recipient") != null or ((dr is float or dr is int) and float(dr) > 0.0):
						category_dict2 = aggregated_missions
						is_mission_item2 = true
					elif (item.has("food") and item.get("food") != null and item.get("food") > 0) or \
						 (item.has("water") and item.get("water") != null and item.get("water") > 0) or \
						 (item.has("fuel") and item.get("fuel") != null and item.get("fuel") > 0):
						category_dict2 = aggregated_resources
					elif ItemsData != null and ItemsData.PartItem and ItemsData.PartItem._looks_like_part_dict(item):
						# In SELL mode, treat loose part cargo as sellable cargo (not installed parts).
						category_dict2 = aggregated_other if is_sell_mode else aggregated_parts
					else:
						category_dict2 = aggregated_other
					if is_mission_item2:
						var recipient_id2: Variant = item.get("recipient")
						if recipient_id2 == null:
							recipient_id2 = item.get("mission_vendor_id")
						if recipient_id2 and get_vendor_name_for_recipient.is_valid():
							mission_vendor_name2 = str(get_vendor_name_for_recipient.call(recipient_id2))
					# SELL: only include what this vendor can buy.
					if is_sell_mode:
						if not is_mission_item2 and not VendorTradeVM.vendor_can_buy_item_resources(vendor_data if (vendor_data is Dictionary) else {}, item):
							continue
						# Non-resource cargo (and parts-as-cargo) are always sellable; missions are always allowed.
					_aggregate_item(category_dict2, item, vehicle_name, mission_vendor_name2, perf_log_enabled)
			# Vehicle installed parts should not be sellable as loose cargo.
			if not is_sell_mode:
				for part in vehicle.get("parts", []):
					_aggregate_item(aggregated_parts, part, vehicle_name, "", perf_log_enabled)

	if not found_any_cargo and convoy_data.has("cargo_inventory"):
		for item in convoy_data.cargo_inventory:
			# Do not surface intrinsic resource containers as tradable cargo.
			if item is Dictionary and _is_intrinsic_resource_container(item as Dictionary):
				continue

			# Inject current vendor prices so PriceUtil can see them on the item level
			if item is Dictionary:
				if not item.has("fuel_price") or item.get("fuel_price") == null: item["fuel_price"] = v_fuel_p
				if not item.has("water_price") or item.get("water_price") == null: item["water_price"] = v_water_p
				if not item.has("food_price") or item.get("food_price") == null: item["food_price"] = v_food_p

			var category_dict3: Dictionary
			var is_mission_item3: bool = false
			var mission_vendor_name3: String = ""
			var dr2 = item.get("delivery_reward")
			if item.get("recipient") != null or ((dr2 is float or dr2 is int) and float(dr2) > 0.0):
				category_dict3 = aggregated_missions
				is_mission_item3 = true
			elif (item.has("food") and item.get("food") != null and item.get("food") > 0) or \
				 (item.has("water") and item.get("water") != null and item.get("water") > 0) or \
				 (item.has("fuel") and item.get("fuel") != null and item.get("fuel") > 0):
				category_dict3 = aggregated_resources
			elif ItemsData != null and ItemsData.PartItem and ItemsData.PartItem._looks_like_part_dict(item):
				category_dict3 = aggregated_other if is_sell_mode else aggregated_parts
			else:
				category_dict3 = aggregated_other
			if is_mission_item3:
				var recipient_id3: Variant = item.get("recipient")
				if recipient_id3 == null:
					recipient_id3 = item.get("mission_vendor_id")
				if recipient_id3 and get_vendor_name_for_recipient.is_valid():
					mission_vendor_name3 = str(get_vendor_name_for_recipient.call(recipient_id3))
			# SELL: only include what this vendor can buy.
			if is_sell_mode:
				if not is_mission_item3 and not VendorTradeVM.vendor_can_buy_item_resources(vendor_data if (vendor_data is Dictionary) else {}, item):
					continue
				# Non-resource cargo (and parts-as-cargo) are always sellable; missions are always allowed.
			_aggregate_item(category_dict3, item, "Convoy", mission_vendor_name3, perf_log_enabled)

	# Fallback: some snapshots provide a flattened `all_cargo` array instead of `cargo_inventory`.
	if not found_any_cargo and not convoy_data.has("cargo_inventory") and convoy_all_cargo_any is Array:
		for item_any in (convoy_all_cargo_any as Array):
			var item: Dictionary = {}
			var item_category: String = ""
			# all_cargo may contain raw dictionaries OR typed CargoItem Resources.
			if item_any is CargoItem:
				var typed: CargoItem = item_any
				item = typed.raw.duplicate(true)
				item["quantity"] = typed.quantity
				item["category"] = typed.category
				item["weight"] = typed.total_weight
				item["volume"] = typed.total_volume
				item_category = typed.category
				if typed.has_method("get_modifier_summary"):
					var mods: String = str(typed.call("get_modifier_summary"))
					if mods != "":
						item["modifiers"] = mods
				if "stats" in typed and typed.stats is Dictionary and not typed.stats.is_empty():
					item["stats"] = typed.stats.duplicate(true)
			elif item_any is Dictionary:
				item = item_any
			else:
				continue
			# Do not surface intrinsic resource containers as tradable cargo.
			if _is_intrinsic_resource_container(item):
				continue
			
			# Inject current vendor prices so PriceUtil can see them on the item level
			if not item.has("fuel_price") or item.get("fuel_price") == null: item["fuel_price"] = v_fuel_p
			if not item.has("water_price") or item.get("water_price") == null: item["water_price"] = v_water_p
			if not item.has("food_price") or item.get("food_price") == null: item["food_price"] = v_food_p

			found_any_cargo = true
			var category_dict4: Dictionary
			var is_mission_item4: bool = false
			var mission_vendor_name4: String = ""
			var dr4 = item.get("delivery_reward")
			if item.get("recipient") != null or ((dr4 is float or dr4 is int) and float(dr4) > 0.0):
				category_dict4 = aggregated_missions
				is_mission_item4 = true
			elif item_category == "resource" or (item.has("food") and item.get("food") != null and item.get("food") > 0) or \
					 (item.has("water") and item.get("water") != null and item.get("water") > 0) or \
					 (item.has("fuel") and item.get("fuel") != null and item.get("fuel") > 0):
				category_dict4 = aggregated_resources
			elif item_category == "part" or (ItemsData != null and ItemsData.PartItem and ItemsData.PartItem._looks_like_part_dict(item)):
				category_dict4 = aggregated_other if is_sell_mode else aggregated_parts
			else:
				category_dict4 = aggregated_other
			if is_mission_item4:
				var recipient_id4: Variant = item.get("recipient")
				if recipient_id4 == null:
					recipient_id4 = item.get("mission_vendor_id")
				if recipient_id4 and get_vendor_name_for_recipient.is_valid():
					mission_vendor_name4 = str(get_vendor_name_for_recipient.call(recipient_id4))
			# SELL: only include what this vendor can buy.
			if is_sell_mode:
				if not is_mission_item4 and not VendorTradeVM.vendor_can_buy_item_resources(vendor_data if (vendor_data is Dictionary) else {}, item):
					continue
				# Non-resource cargo (and parts-as-cargo) are always sellable; missions are always allowed.
			_aggregate_item(category_dict4, item, "Convoy", mission_vendor_name4, perf_log_enabled)

	# Vehicles fallback: some convoy snapshots provide `vehicles` instead of `vehicle_details_list`.
	if vehicle_sell_allowed and not convoy_data.has("vehicle_details_list") and convoy_vehicles_any is Array:
		for v_any in (convoy_vehicles_any as Array):
			if not (v_any is Dictionary):
				continue
			var v: Dictionary = v_any
			var vid2 := str(v.get("vehicle_id", ""))
			if vid2 == "":
				continue
			if not aggregated_vehicles.has(vid2):
				aggregated_vehicles[vid2] = {
					"item_data": v,
					"display_name": str(v.get("name", "Unknown Vehicle")),
					"total_quantity": 1,
					"total_weight": 0.0,
					"total_volume": 0.0,
					"locations": {},
				}

	var raw_convoy_fuel = convoy_data.get("fuel", 0)
	var raw_convoy_water = convoy_data.get("water", 0)
	var raw_convoy_food = convoy_data.get("food", 0)
	var vendor_fuel_price := _to_float_any(vendor_data.get("fuel_price", 0) if vendor_data != null else 0)
	var vendor_water_price := _to_float_any(vendor_data.get("water_price", 0) if vendor_data != null else 0)
	var vendor_food_price := _to_float_any(vendor_data.get("food_price", 0) if vendor_data != null else 0)
	var convoy_fuel_quantity := _to_int_any(raw_convoy_fuel)
	if convoy_fuel_quantity > 0 and (not is_sell_mode or vendor_buys_fuel):
		var fuel_item2 = {
			"name": "Fuel (Bulk)",
			"base_desc": "Bulk fuel from your convoy's reserves.",
			"quantity": convoy_fuel_quantity,
			"fuel": convoy_fuel_quantity,
			"fuel_price": vendor_fuel_price,
			"is_raw_resource": true,
			"unit_weight": 1.0,
			"unit_volume": 0.0,
			"total_weight": float(convoy_fuel_quantity) * 1.0,
			"total_volume": 0.0,
		}
		if perf_log_enabled:
			print("[VendorCargoAggregator] Creating convoy bulk fuel item:", fuel_item2)
		_aggregate_vendor_item(aggregated_resources, fuel_item2, "", perf_log_enabled)
	elif convoy_fuel_quantity > 0 and perf_log_enabled:
		print("[VendorCargoAggregator] Skipping convoy bulk fuel (unexpected state)")

	var convoy_water_quantity := _to_int_any(raw_convoy_water)
	if convoy_water_quantity > 0 and (not is_sell_mode or vendor_buys_water):
		var water_item2 = {
			"name": "Water (Bulk)",
			"base_desc": "Bulk water from your convoy's reserves.",
			"quantity": convoy_water_quantity,
			"water": convoy_water_quantity,
			"water_price": vendor_water_price,
			"is_raw_resource": true,
			"unit_weight": 1.0,
			"unit_volume": 0.0,
			"total_weight": float(convoy_water_quantity) * 1.0,
			"total_volume": 0.0,
		}
		if perf_log_enabled:
			print("[VendorCargoAggregator] Creating convoy bulk water item:", water_item2)
		_aggregate_vendor_item(aggregated_resources, water_item2, "", perf_log_enabled)
	elif convoy_water_quantity > 0 and perf_log_enabled:
		print("[VendorCargoAggregator] Skipping convoy bulk water (unexpected state)")

	var convoy_food_quantity := _to_int_any(raw_convoy_food)
	if convoy_food_quantity > 0 and (not is_sell_mode or vendor_buys_food):
		var food_item2 = {
			"name": "Food (Bulk)",
			"base_desc": "Bulk food supplies from your convoy's reserves.",
			"quantity": convoy_food_quantity,
			"food": convoy_food_quantity,
			"food_price": vendor_food_price,
			"is_raw_resource": true,
			"unit_weight": 1.0,
			"unit_volume": 0.0,
			"total_weight": float(convoy_food_quantity) * 1.0,
			"total_volume": 0.0,
		}
		if perf_log_enabled:
			print("[VendorCargoAggregator] Creating convoy bulk food item:", food_item2)
		_aggregate_vendor_item(aggregated_resources, food_item2, "", perf_log_enabled)
	elif convoy_food_quantity > 0 and perf_log_enabled:
		print("[VendorCargoAggregator] Skipping convoy bulk food (unexpected state)")

	if perf_log_enabled and is_sell_mode:
		print("[VendorCargoAggregator][SellDiag] buckets sizes missions=", aggregated_missions.size(),
			" vehicles=", aggregated_vehicles.size(),
			" parts=", aggregated_parts.size(),
			" other=", aggregated_other.size(),
			" resources=", aggregated_resources.size())

	return {
		"missions": aggregated_missions,
		"vehicles": aggregated_vehicles,
		"parts": aggregated_parts,
		"other": aggregated_other,
		"resources": aggregated_resources,
	}


static func _aggregate_vendor_item(agg_dict: Dictionary, item: Dictionary, mission_vendor_name: String, perf_log_enabled: bool) -> void:
	if agg_dict == null:
		return
	var item_name = item.get("name", "Unknown Item")
	if not agg_dict.has(item_name):
		agg_dict[item_name] = {
			"item_data": item,
			"total_quantity": 0,
			"total_weight": 0.0,
			"total_volume": 0.0,
			"total_food": 0.0,
			"total_water": 0.0,
			"total_fuel": 0.0,
			"mission_vendor_name": mission_vendor_name,
		}
	var item_quantity = int(item.get("quantity", 1.0))
	if item.get("is_raw_resource", false):
		if item.get("fuel", 0) is int or item.get("fuel", 0) is float:
			item_quantity = max(item_quantity, int(item.get("fuel", 0) or 0))
		if item.get("water", 0) is int or item.get("water", 0) is float:
			item_quantity = max(item_quantity, int(item.get("water", 0) or 0))
		if item.get("food", 0) is int or item.get("food", 0) is float:
			item_quantity = max(item_quantity, int(item.get("food", 0) or 0))
		agg_dict[item_name].item_data["quantity"] = item_quantity
	if perf_log_enabled:
		print("[VendorCargoAggregator] _aggregate_vendor_item before add name=", item_name, "incoming quantity=", item.get("quantity"), "parsed=", item_quantity)
	if mission_vendor_name != "" and agg_dict[item_name].mission_vendor_name == "":
		if perf_log_enabled:
			print("[VendorCargoAggregator] _aggregate_vendor_item set mission_vendor_name=", mission_vendor_name, " for ", item_name)
		agg_dict[item_name].mission_vendor_name = mission_vendor_name
	agg_dict[item_name].total_quantity += item_quantity
	# Vendor inventory payloads typically report per-unit weight/volume with a stock quantity.
	# To keep transaction projections correct, scale per-unit values by quantity.
	var w_any: Variant = item.get("unit_weight", item.get("weight", 0.0))
	var v_any: Variant = item.get("unit_volume", item.get("volume", 0.0))
	var w_add: float = float(w_any) * float(item_quantity) if (w_any is float or w_any is int) else 0.0
	var v_add: float = float(v_any) * float(item_quantity) if (v_any is float or v_any is int) else 0.0
	agg_dict[item_name].total_weight += w_add
	agg_dict[item_name].total_volume += v_add
	if item.get("food") is float or item.get("food") is int:
		agg_dict[item_name].total_food += item.get("food")
	if item.get("water") is float or item.get("water") is int:
		agg_dict[item_name].total_water += item.get("water")
	if item.get("fuel") is float or item.get("fuel") is int:
		agg_dict[item_name].total_fuel += item.get("fuel")
	if perf_log_enabled:
		print("[VendorCargoAggregator] _aggregate_vendor_item after add name=", item_name, "total_quantity=", agg_dict[item_name].total_quantity, "total_fuel=", agg_dict[item_name].total_fuel, "total_water=", agg_dict[item_name].total_water, "total_food=", agg_dict[item_name].total_food)


static func _aggregate_item(agg_dict: Dictionary, item: Dictionary, vehicle_name: String, mission_vendor_name: String, perf_log_enabled: bool) -> void:
	if agg_dict == null:
		return
	var agg_key := _stable_key_for_convoy_item(item)
	var display_name = item.get("name", "Unknown Item")
	if not agg_dict.has(agg_key):
		agg_dict[agg_key] = {
			"item_data": item,
			"display_name": display_name,
			"stable_key": agg_key,
			"total_quantity": 0,
			"locations": {},
			"mission_vendor_name": mission_vendor_name,
			"total_weight": 0.0,
			"total_volume": 0.0,
			"total_food": 0.0,
			"total_water": 0.0,
			"total_fuel": 0.0,
			"items": [],
		}
	var item_quantity = int(item.get("quantity", 1.0))
	if item.get("is_raw_resource", false):
		if item.get("fuel", 0) is int or item.get("fuel", 0) is float:
			item_quantity = max(item_quantity, int(item.get("fuel", 0) or 0))
		if item.get("water", 0) is int or item.get("water", 0) is float:
			item_quantity = max(item_quantity, int(item.get("water", 0) or 0))
		if item.get("food", 0) is int or item.get("food", 0) is float:
			item_quantity = max(item_quantity, int(item.get("food", 0) or 0))
		agg_dict[agg_key].item_data["quantity"] = item_quantity
	agg_dict[agg_key].total_quantity += item_quantity
	agg_dict[agg_key].total_weight += item.get("weight", 0.0)
	agg_dict[agg_key].total_volume += item.get("volume", 0.0)
	if item.get("food") is float or item.get("food") is int:
		agg_dict[agg_key].total_food += item.get("food")
	if item.get("water") is float or item.get("water") is int:
		agg_dict[agg_key].total_water += item.get("water")
	if item.get("fuel") is float or item.get("fuel") is int:
		agg_dict[agg_key].total_fuel += item.get("fuel")
	if not agg_dict[agg_key].locations.has(vehicle_name):
		agg_dict[agg_key].locations[vehicle_name] = 0
	agg_dict[agg_key].locations[vehicle_name] += item_quantity
	agg_dict[agg_key].items.append(item)
	if perf_log_enabled:
		print("[VendorCargoAggregator] _aggregate_item key=", agg_key, " vehicle=", vehicle_name, " qty=", item_quantity)


# Prefer grouping by stable, user-visible semantics so the UI doesn't show one row per cargo stack.
# This also enables SELL-mode multi-stack dispatch via the aggregated "items" list.
static func _stable_key_for_convoy_item(item: Dictionary) -> String:
	if item == null:
		return "cargo:unknown"
	var item_name := str(item.get("name", "Unknown Item")).strip_edges()
	var mods := ""
	if item.has("modifiers") and item.get("modifiers") != null:
		mods = str(item.get("modifiers")).strip_edges()
	var mods_suffix := ("|mods=" + mods) if mods != "" else ""
	# Missions should stay separated by recipient/mission target.
	var dr_v = item.get("delivery_reward")
	var looks_mission := item.get("recipient") != null or ((dr_v is float or dr_v is int) and float(dr_v) > 0.0)
	if looks_mission:
		var recipient_id := ""
		if item.get("recipient") != null:
			recipient_id = str(item.get("recipient"))
		elif item.get("mission_vendor_id") != null:
			recipient_id = str(item.get("mission_vendor_id"))
		if recipient_id != "":
			return ("mission:%s:%s" % [recipient_id, item_name]) + mods_suffix
		return ("mission:%s" % item_name) + mods_suffix
	# Parts should typically not be grouped only by name if slot is available.
	var slot_val := ""
	if item.has("slot") and item.get("slot") != null:
		slot_val = str(item.get("slot")).strip_edges()
	if slot_val != "":
		return ("part:%s:%s" % [slot_val, item_name]) + mods_suffix
	# Fallback: group cargo by display name.
	return ("cargo:%s" % item_name) + mods_suffix
