extends RefCounted
## TopUpPlanner — pure resource top-up planner extracted from convoy_settlement_menu.gd (Sprint 5).
##
## Given a convoy snapshot and a settlement snapshot (whose vendors carry `<res>` stock + `<res>_price`),
## produce an allocation plan that levels Fuel/Water/Food toward full using the cheapest vendor for each
## resource, respecting an optional money `budget` and the convoy's remaining weight capacity.
##
## No node access, no side effects — both the base Convoy Menu and any other surface can reuse it.
## Returned shape:
##   {
##     total_cost: float,
##     allocations: Array[{res, vendor_id, vendor_name, price, quantity, subtotal}],
##     resources:  { <res>: {total_quantity:int, total_cost:float} },
##     planned_list: Array[String]   # ordered subset of RESOURCES actually purchased
##   }

const RESOURCES := ["fuel", "water", "food"]

static func calculate_plan(convoy: Dictionary, settlement: Dictionary, budget: float = -1.0) -> Dictionary:
	var plan: Dictionary = {"total_cost": 0.0, "allocations": [], "resources": {}, "planned_list": []}
	if settlement.is_empty() or not settlement.has("vendors"):
		return plan
	if convoy.is_empty():
		return plan

	# Budget/weight constraints
	var remaining_budget: float = budget
	var budget_limited := budget >= 0.0
	if not budget_limited:
		remaining_budget = 999999999.0
	var remaining_weight := float(convoy.get("total_remaining_capacity", 999999.0))
	var weight_limited := remaining_weight <= 0.001
	var resource_weights: Dictionary = convoy.get("resource_weights", {})

	# Build per-resource state with cheapest-vendor priority for that resource.
	# Then allocate in a leveling loop (always buy for the lowest fill%), which naturally
	# distributes purchases evenly instead of fully topping up one resource first.
	var state_by_res: Dictionary = {}
	for res: String in RESOURCES:
		var max_amount: float = float(convoy.get("max_" + res, 0.0))
		if max_amount <= 0.001:
			continue
		var current_amount: float = float(convoy.get(res, 0.0))
		var needed_exact: float = max(max_amount - current_amount, 0.0)
		var needed_remaining: int = int(floor(needed_exact + 0.0001))
		if needed_remaining <= 0:
			continue

		var price_key: String = String(res) + "_price"
		var vendor_candidates: Array = []
		for v in settlement.get("vendors", []):
			if v.has(price_key) and v[price_key] != null and v.has(res):
				var stock_available := int(v.get(res, 0))
				var price := float(v.get(price_key, 0.0))
				if stock_available > 0 and price > 0.0:
					vendor_candidates.append({"vendor": v, "price": price, "stock": stock_available})
		vendor_candidates.sort_custom(func(a, b): return float(a.price) < float(b.price))
		if vendor_candidates.is_empty():
			continue

		var weight_per_unit: float = float(resource_weights.get(res, 1.0))
		if weight_per_unit <= 0.0:
			weight_per_unit = 1.0

		state_by_res[res] = {
			"res": res,
			"max": max_amount,
			"current": current_amount,
			"needed": needed_remaining,
			"vendors": vendor_candidates,
			"vendor_idx": 0,
			"vendor_stock_left": int(vendor_candidates[0].stock),
			"weight_per_unit": weight_per_unit,
		}

	if state_by_res.is_empty():
		return plan

	var planned_set: Dictionary = {}
	# Keyed by "res|vendor_id" so we can merge allocations and avoid 1-unit spam.
	var alloc_index_by_key: Dictionary = {}
	var last_picked_res: String = ""
	var safety := 0
	while true:
		safety += 1
		if safety > 10000:
			break

		if budget_limited and remaining_budget < 0.01:
			break
		if not weight_limited and remaining_weight <= 0.001:
			break

		# Build list of resources that can still accept at least 1 unit.
		var active: Array = []
		for res: String in RESOURCES:
			if not state_by_res.has(res):
				continue
			var s: Dictionary = state_by_res[res]
			if int(s.get("needed", 0)) <= 0:
				continue
			var vendors: Array = s.get("vendors", [])
			var vidx: int = int(s.get("vendor_idx", 0))
			if vidx >= vendors.size():
				continue
			var price := float(vendors[vidx].price)
			if budget_limited and remaining_budget < price:
				continue
			if not weight_limited:
				var wpu := float(s.get("weight_per_unit", 1.0))
				if remaining_weight < wpu:
					continue
			active.append(res)
		if active.is_empty():
			break

		# Compute min fill percentage among active resources.
		var min_fill := 999.0
		for res: String in active:
			var s: Dictionary = state_by_res[res]
			var fill := 1.0
			var max_amount := float(s.get("max", 0.0))
			if max_amount > 0.001:
				fill = float(s.get("current", 0.0)) / max_amount
			if fill < min_fill:
				min_fill = fill

		# Collect all resources tied for min fill (within epsilon), and rotate tie-breaking.
		var eps := 0.000001
		var tied: Array = []
		for res: String in active:
			var s: Dictionary = state_by_res[res]
			var max_amount := float(s.get("max", 0.0))
			var fill := 1.0
			if max_amount > 0.001:
				fill = float(s.get("current", 0.0)) / max_amount
			if abs(fill - min_fill) <= eps:
				tied.append(res)
		if tied.is_empty():
			break

		var pick_res := String(tied[0])
		if tied.size() > 1 and last_picked_res != "":
			var last_idx := tied.find(last_picked_res)
			if last_idx != -1:
				pick_res = String(tied[(last_idx + 1) % tied.size()])
		last_picked_res = pick_res

		var s_pick: Dictionary = state_by_res[pick_res]
		var max_pick := float(s_pick.get("max", 0.0))
		if max_pick <= 0.001:
			break

		# Find the next higher fill among active resources so we can buy in chunks.
		var next_fill := 1.0
		var found_next := false
		for res: String in active:
			var s: Dictionary = state_by_res[res]
			var max_amount := float(s.get("max", 0.0))
			if max_amount <= 0.001:
				continue
			var fill := float(s.get("current", 0.0)) / max_amount
			if fill > (min_fill + eps):
				if not found_next or fill < next_fill:
					next_fill = fill
					found_next = true
		if not found_next:
			next_fill = 1.0

		var units_to_target := int(ceil(max(0.0, (next_fill - min_fill)) * max_pick))
		if units_to_target <= 0:
			units_to_target = 1

		# Ensure vendor pointer is on a valid candidate with stock.
		var vendors: Array = s_pick.get("vendors", [])
		var vidx: int = int(s_pick.get("vendor_idx", 0))
		var stock_left: int = int(s_pick.get("vendor_stock_left", 0))
		while vidx < vendors.size() and stock_left <= 0:
			vidx += 1
			if vidx < vendors.size():
				stock_left = int(vendors[vidx].stock)
		s_pick.vendor_idx = vidx
		s_pick.vendor_stock_left = stock_left
		state_by_res[pick_res] = s_pick
		if vidx >= vendors.size():
			continue

		var price: float = float(vendors[vidx].price)
		var weight_per_unit: float = float(s_pick.get("weight_per_unit", 1.0))
		var take_qty: int = min(units_to_target, int(s_pick.get("needed", 0)))
		take_qty = min(take_qty, stock_left)
		if budget_limited:
			take_qty = min(take_qty, int(floor(remaining_budget / price)))
		if not weight_limited and remaining_weight < 999998:
			take_qty = min(take_qty, int(floor(remaining_weight / weight_per_unit)))
		if take_qty <= 0:
			continue

		var vdict: Dictionary = vendors[vidx].vendor
		var vendor_id := str(vdict.get("vendor_id", ""))
		var vendor_name := str(vdict.get("name", "Vendor"))
		var subtotal := float(take_qty) * price

		var alloc_key: String = String(pick_res) + "|" + String(vendor_id)
		if alloc_index_by_key.has(alloc_key):
			var idx: int = int(alloc_index_by_key.get(alloc_key, -1))
			if idx >= 0 and idx < plan.allocations.size():
				var existing: Dictionary = plan.allocations[idx]
				existing.quantity = int(existing.get("quantity", 0)) + int(take_qty)
				existing.subtotal = float(existing.get("subtotal", 0.0)) + float(subtotal)
				# Keep vendor_name/price stable; refresh just in case.
				existing.vendor_name = vendor_name
				existing.price = price
				plan.allocations[idx] = existing
			else:
				alloc_index_by_key.erase(alloc_key)
				plan.allocations.append({
					"res": pick_res,
					"vendor_id": vendor_id,
					"vendor_name": vendor_name,
					"price": price,
					"quantity": take_qty,
					"subtotal": subtotal
				})
				alloc_index_by_key[alloc_key] = plan.allocations.size() - 1
		else:
			plan.allocations.append({
				"res": pick_res,
				"vendor_id": vendor_id,
				"vendor_name": vendor_name,
				"price": price,
				"quantity": take_qty,
				"subtotal": subtotal
			})
			alloc_index_by_key[alloc_key] = plan.allocations.size() - 1
		plan.total_cost += subtotal
		remaining_budget -= subtotal
		if not weight_limited:
			remaining_weight -= float(take_qty) * weight_per_unit

		# Update state for the picked resource.
		s_pick.current = float(s_pick.get("current", 0.0)) + float(take_qty)
		s_pick.needed = int(s_pick.get("needed", 0)) - take_qty
		s_pick.vendor_stock_left = stock_left - take_qty
		state_by_res[pick_res] = s_pick

		# Aggregate totals for UI/tooltip.
		if not plan.resources.has(pick_res):
			plan.resources[pick_res] = {"total_quantity": 0, "total_cost": 0.0}
		plan.resources[pick_res].total_quantity += int(take_qty)
		plan.resources[pick_res].total_cost += subtotal
		planned_set[pick_res] = true

	# Preserve a stable resource ordering for any UI consumption.
	for res in RESOURCES:
		if planned_set.has(res):
			plan.planned_list.append(res)
	return plan
