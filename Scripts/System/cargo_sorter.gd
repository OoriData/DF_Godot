class_name CargoSorter
extends RefCounted

## Defines the metrics by which cargo can be sorted
enum SortMetric {
	PROFIT_MARGIN_PER_UNIT,
	PROFIT_DENSITY_PER_WEIGHT,
	PROFIT_DENSITY_PER_VOLUME,
	TOTAL_ORDER_PROFIT,
	PROFIT_PER_DISTANCE
}

## Sorts an array of cargo dictionaries based on the specified metric.
## 
## @param cargo_array: The array of dictionaries to sort.
## @param metric: The SortMetric enum to sort by.
## @param ascending: If true, sorts lowest to highest. If false (default), sorts highest to lowest profit.
## @param context: Optional context dictionary for extra data like `route_distance`.
static func sort_cargo(cargo_array: Array, metric: SortMetric, ascending: bool = false, context: Dictionary = {}) -> Array:
	var copy = cargo_array.duplicate(false)
	var sort_func: Callable
	
	match metric:
		SortMetric.PROFIT_MARGIN_PER_UNIT:
			sort_func = func(a, b): return _compare_profit_margin_per_unit(a, b, ascending, context)
		SortMetric.PROFIT_DENSITY_PER_WEIGHT:
			sort_func = func(a, b): return _compare_profit_density_per_weight(a, b, ascending, context)
		SortMetric.PROFIT_DENSITY_PER_VOLUME:
			sort_func = func(a, b): return _compare_profit_density_per_volume(a, b, ascending, context)
		SortMetric.TOTAL_ORDER_PROFIT:
			sort_func = func(a, b): return _compare_total_order_profit(a, b, ascending, context)
		SortMetric.PROFIT_PER_DISTANCE:
			sort_func = func(a, b): return _compare_distance_to_recipient(a, b, ascending, context)
			
	copy.sort_custom(sort_func)
	return copy

# --- Comparison Functions ---

static func _compare_profit_margin_per_unit(a: Dictionary, b: Dictionary, ascending: bool, context: Dictionary) -> bool:
	var val_a = get_unit_profit_margin(a, context)
	var val_b = get_unit_profit_margin(b, context)
	return val_a < val_b if ascending else val_a > val_b

static func _compare_profit_density_per_weight(a: Dictionary, b: Dictionary, ascending: bool, context: Dictionary) -> bool:
	# Unit profit margin / unit weight
	var u_profit_a = get_unit_profit_margin(a, context)
	var u_weight_a = get_unit_weight(a)
	var val_a = (u_profit_a / u_weight_a) if u_weight_a > 0.0 else u_profit_a # fallback to flat profit if 0 weight
	
	var u_profit_b = get_unit_profit_margin(b, context)
	var u_weight_b = get_unit_weight(b)
	var val_b = (u_profit_b / u_weight_b) if u_weight_b > 0.0 else u_profit_b
	
	return val_a < val_b if ascending else val_a > val_b

static func _compare_profit_density_per_volume(a: Dictionary, b: Dictionary, ascending: bool, context: Dictionary) -> bool:
	# Unit profit margin / unit volume
	var u_profit_a = get_unit_profit_margin(a, context)
	var u_vol_a = get_unit_volume(a)
	var val_a = (u_profit_a / u_vol_a) if u_vol_a > 0.0 else u_profit_a
	
	var u_profit_b = get_unit_profit_margin(b, context)
	var u_vol_b = get_unit_volume(b)
	var val_b = (u_profit_b / u_vol_b) if u_vol_b > 0.0 else u_profit_b
	
	return val_a < val_b if ascending else val_a > val_b

static func _compare_total_order_profit(a: Dictionary, b: Dictionary, ascending: bool, context: Dictionary) -> bool:
	var val_a = get_total_order_profit(a, context)
	var val_b = get_total_order_profit(b, context)
	return val_a < val_b if ascending else val_a > val_b

static func _compare_distance_to_recipient(a: Dictionary, b: Dictionary, ascending: bool, context: Dictionary) -> bool:
	var dist_a = get_route_distance(a, context)
	var dist_b = get_route_distance(b, context)
	# By default (ascending=false), prefer nearest recipients first.
	# Passing ascending=true flips to farthest-first.
	return dist_a > dist_b if ascending else dist_a < dist_b


# --- Value Extractors ---

## Calculates unit_delivery_reward - unit_purchase_price
static func get_unit_profit_margin(cargo: Dictionary, context: Dictionary) -> float:
	var reward = get_unit_delivery_reward(cargo, context)
	var cost = get_unit_purchase_price(cargo)
	return reward - cost

## Gets the unit price/cost for the cargo
static func get_unit_purchase_price(cargo: Dictionary) -> float:
	if cargo.has("unit_price"): return float(cargo.get("unit_price"))
	if cargo.has("price"): return float(cargo.get("price"))
	if cargo.has("base_price"): return float(cargo.get("base_price"))
	if cargo.has("value"): return float(cargo.get("value"))
	if cargo.has("base_value"): return float(cargo.get("base_value"))
	return 0.0

## Gets the unit delivery reward for the cargo
static func get_unit_delivery_reward(cargo: Dictionary, context: Dictionary) -> float:
	# Priority to context overrides
	if context.has("reward_override") and context.get("reward_override") is Dictionary:
		var ro_dict: Dictionary = context.get("reward_override")
		var cargo_id: String = str(cargo.get("id", cargo.get("cargo_id", "")))
		if ro_dict.has(cargo_id):
			return float(ro_dict.get(cargo_id))

	if cargo.has("unit_delivery_reward"): return float(cargo.get("unit_delivery_reward"))
	# If no specific delivery reward, it might just be the value/sell price
	if cargo.has("delivery_reward"): 
		var qty = get_quantity(cargo)
		if qty > 0:
			return float(cargo.get("delivery_reward")) / float(qty)
	
	# Fallback to sell price if this is not a delivery but a pure market transaction?
	# Typically the mission gives "unit_delivery_reward", but if not, let's use base value
	# so it returns at least something for market items being traded manually.
	return get_unit_purchase_price(cargo)

## Gets the quantity of the cargo item stack
static func get_quantity(cargo: Dictionary) -> int:
	if cargo.has("quantity"): return int(cargo.get("quantity"))
	if cargo.has("total_quantity"): return int(cargo.get("total_quantity"))
	return 1

## Gets the total order profit: (unit_margin) * quantity
static func get_total_order_profit(cargo: Dictionary, context: Dictionary) -> float:
	# Alternatively (total_reward) - (total_cost)
	var unit_margin = get_unit_profit_margin(cargo, context)
	var qty = float(get_quantity(cargo))
	return unit_margin * qty

static func get_unit_weight(cargo: Dictionary) -> float:
	if cargo.has("unit_weight"): return float(cargo.get("unit_weight"))
	if cargo.has("weight"):
		var qty = float(get_quantity(cargo))
		if qty > 0:
			return float(cargo.get("weight")) / qty
	if cargo.has("total_weight"):
		var qty = float(get_quantity(cargo))
		if qty > 0:
			return float(cargo.get("total_weight")) / qty
	return 0.0

static func get_unit_volume(cargo: Dictionary) -> float:
	if cargo.has("unit_volume"): return float(cargo.get("unit_volume"))
	if cargo.has("volume"):
		var qty = float(get_quantity(cargo))
		if qty > 0:
			return float(cargo.get("volume")) / qty
	if cargo.has("total_volume"):
		var qty = float(get_quantity(cargo))
		if qty > 0:
			return float(cargo.get("total_volume")) / qty
	return 0.0

static func get_route_distance(cargo: Dictionary, context: Dictionary) -> float:
	# Priority 1: Check context for a distance map keyed by destination
	if context.has("distance_map") and context.get("distance_map") is Dictionary:
		var d_map: Dictionary = context.get("distance_map")
		var dest: String = str(cargo.get("destination", cargo.get("destination_id", "")))
		if d_map.has(dest):
			return float(d_map.get(dest))
			
	# Priority 2: Standard context override
	if context.has("route_distance"):
		return float(context.get("route_distance"))
		
	# Priority 3: Distance bundled on the cargo itself
	if cargo.has("route_distance"): return float(cargo.get("route_distance"))
	if cargo.has("distance"): return float(cargo.get("distance"))
	
	# Default to 1.0 to avoid divide-by-zero if distance isn't provided
	return 1.0
