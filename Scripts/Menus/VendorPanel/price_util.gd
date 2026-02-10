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
			var val = float(item[k])
			if val > 0.0:
				out.container_unit_price = val
				break
	# Resource-specific unit value (total value of contained resources)
	var resource_keys = ["fuel_price", "water_price", "food_price"]
	var amount_keys = ["fuel", "water", "food", "Fuel", "Water", "Food"]
	for rk in resource_keys:
		if item.has(rk) and (item[rk] is float or item[rk] is int):
			var price = float(item[rk])
			if price > 0.0:
				var amount = 0.0
				if item.get("is_raw_resource", false):
					# For bulk resources, the price fields (water_price, fuel_price, etc.)
					# are already PER UNIT prices, so amount = 1.0
					amount = 1.0
				else:
					var prefix = rk.split("_")[0].to_lower()
					for ak in amount_keys:
						if ak.to_lower() == prefix:
							var av = item.get(ak)
							if av is float or av is int:
								amount = float(av)
							break
				if amount > 0.0:
					out.resource_unit_value += (price * amount)
	out.resource_unit_value = max(0.0, out.resource_unit_value) # Fallback / cleanup
	# Allow nested price dicts like { price: { buy: x, sell: y } }
	if item.has("price") and item.price is Dictionary:
		var pd = item.price as Dictionary
		if pd.has("unit") and (pd.unit is float or pd.unit is int):
			out.container_unit_price = float(pd.unit)
		elif pd.has("buy") and (pd.buy is float or pd.buy is int):
			out.container_unit_price = float(pd.buy)
		elif pd.has("sell") and (pd.sell is float or pd.sell is int):
			out.container_unit_price = float(pd.sell)
	if (item.get("perf_log_enabled", false) or item.get("is_raw_resource", false)) and out.resource_unit_value > 0.0:
		print("[PriceUtil] Calculated price components for '%s': Resource=%.2f Container=%.2f" % [item.get("name", "Unknown"), out.resource_unit_value, out.container_unit_price])
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
	var unit = comps.container_unit_price + comps.resource_unit_value
	# If separate buy/sell fields exist, prefer the matching one (if positive)
	if mode == "buy":
		for k in ["buy_price", "price_buy", "unit_buy"]:
			if item.has(k) and (item[k] is float or item[k] is int):
				var fv = float(item[k])
				if fv > 0.0:
					return fv
	elif mode == "sell":
		for k in ["sell_price", "price_sell", "unit_sell"]:
			if item.has(k) and (item[k] is float or item[k] is int):
				var fv = float(item[k])
				if fv > 0.0:
					return fv
	return unit
