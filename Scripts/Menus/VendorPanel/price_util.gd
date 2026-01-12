extends Node
class_name PriceUtil

# Returns a Dictionary with keys:
# - container_unit_price: float
# - resource_unit_value: float
static func get_item_price_components(item: Dictionary) -> Dictionary:
	var out = {
		"container_unit_price": 0.0,
		"resource_unit_value": 0.0
	}
	if item == null:
		return out
	# Common fields on cargo/parts/resources
	# Try several common price keys in priority order
	var container_keys = ["container_unit_price", "unit_price", "price", "base_price", "buy_price", "sell_price"]
	for k in container_keys:
		if item.has(k) and (item[k] is float or item[k] is int):
			out.container_unit_price = float(item[k])
			break
	# Resource-specific unit value (raw value per unit)
	var resource_keys = ["resource_unit_value", "unit_value", "value"]
	for rk in resource_keys:
		if item.has(rk) and (item[rk] is float or item[rk] is int):
			out.resource_unit_value = float(item[rk])
			break
	# Allow nested price dicts like { price: { buy: x, sell: y } }
	if item.has("price") and item.price is Dictionary:
		var pd = item.price as Dictionary
		if pd.has("unit") and (pd.unit is float or pd.unit is int):
			out.container_unit_price = float(pd.unit)
		elif pd.has("buy") and (pd.buy is float or pd.buy is int):
			out.container_unit_price = float(pd.buy)
		elif pd.has("sell") and (pd.sell is float or pd.sell is int):
			out.container_unit_price = float(pd.sell)
	return out

# True if the dictionary represents a vehicle record
static func is_vehicle_item(d: Dictionary) -> bool:
	if d == null:
		return false
	if d.has("vehicle_id") and str(d.vehicle_id) != "":
		# Many cargo items reference vehicle_id; try to detect by explicit flags
		if d.has("is_vehicle") and bool(d.is_vehicle):
			return true
		# If it has typical vehicle fields
		if d.has("chassis") or d.has("slots") or d.has("engine"):
			return true
	return false

# Resolve a vehicle's absolute price
static func get_vehicle_price(vehicle: Dictionary) -> float:
	if vehicle == null:
		return 0.0
	var keys = ["vehicle_price", "price", "base_price", "unit_price", "buy_price", "sell_price"]
	for k in keys:
		if vehicle.has(k) and (vehicle[k] is float or vehicle[k] is int):
			return float(vehicle[k])
	# Nested price dict
	if vehicle.has("price") and vehicle.price is Dictionary:
		var pd = vehicle.price as Dictionary
		if pd.has("vehicle") and (pd.vehicle is float or pd.vehicle is int):
			return float(pd.vehicle)
		for nk in ["buy", "sell", "unit"]:
			if pd.has(nk) and (pd[nk] is float or pd[nk] is int):
				return float(pd[nk])
	return 0.0

# Context-aware unit price used in panel (buy/sell)
static func get_contextual_unit_price(item: Dictionary, mode: String) -> float:
	if item == null:
		return 0.0
	if is_vehicle_item(item):
		return get_vehicle_price(item)
	var comps = get_item_price_components(item)
	var unit = comps.container_unit_price
	# If separate buy/sell fields exist, prefer the matching one
	if mode == "buy":
		for k in ["buy_price", "price_buy", "unit_buy"]:
			if item.has(k) and (item[k] is float or item[k] is int):
				return float(item[k])
	elif mode == "sell":
		for k in ["sell_price", "price_sell", "unit_sell"]:
			if item.has(k) and (item[k] is float or item[k] is int):
				return float(item[k])
	return unit
