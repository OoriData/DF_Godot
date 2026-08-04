extends RefCounted
class_name CargoFillPlanner

# S13-7 — how many whole units of one cargo item will ACTUALLY fit in a convoy.
#
# A unit is indivisible: it cannot be split across two vehicles. Pooled arithmetic
# (total_free_space / unit_volume) therefore over-counts whenever an item is large relative to a
# single vehicle — 40 m³ of free space spread across four vehicles cannot accept one 15 m³ item.
# That over-count is what made "Max" offer quantities the server then rejected.
#
# ⚠️ This mirrors the backend allocator EXACTLY — desolate_frontiers
# `chassis/df_obj/vendor_cls.py`, module-level `plan_cargo_placement()` (called by
# `Vendor.sell_cargo()`; it was inline in that method until S13-20 split it out so a refusal could
# report its fit count without moving cargo first). Vehicles are visited largest-free-volume first,
# and each takes
#     min(floor(free_volume / unit_volume), floor(free_weight / unit_weight), units still needed).
# The two implementations must stay in step. If the server's ordering or rounding ever changes,
# change it here in the same pass, or Max goes back to predicting a quantity the server refuses.
#
# When the two DO disagree, the server wins: a refused buy carries a `[fits:N/M]` marker, and the
# panel honours that N over anything computed here (S13-20, `vendor_trade_panel.gd:_server_fit`) —
# this planner's inputs are the likelier stale party.
#
# Raw/bulk resources (Fuel, Water, Food) are deliberately NOT planned here: a litre of fuel is
# divisible across containers, so pooled arithmetic is correct for them. Callers keep the pooled
# path for `is_raw_resource` rows.


## Per-vehicle spare room, read from `convoy_data.vehicle_details_list`.
## Field precedence matches the per-vehicle capacity bars in `convoy_menu.gd:2862-2867`: prefer the
## explicit used totals, fall back to the server's own `free_space` / `remaining_capacity`.
## Returns an Array of {"name": String, "free_volume": float, "free_weight": float}.
static func build_vehicle_spaces(convoy_data: Dictionary) -> Array:
	var out: Array = []
	for v_any in vehicle_rows(convoy_data):
		if not (v_any is Dictionary):
			continue
		var vd: Dictionary = v_any
		# Prefer the server's OWN free_space / remaining_capacity: they are precisely the values
		# Vendor.sell_cargo() allocates against, so using them keeps the preview identical to the
		# decision the server will make. Capacity-minus-used is only a fallback for augmented convoy
		# dicts that dropped those two fields.
		var free_vol: float
		if vd.has("free_space"):
			free_vol = float(vd.get("free_space", 0.0))
		else:
			free_vol = float(vd.get("cargo_capacity", 0.0)) - float(vd.get("total_cargo_volume", 0.0))
		var free_wt: float
		if vd.has("remaining_capacity"):
			free_wt = float(vd.get("remaining_capacity", 0.0))
		else:
			free_wt = float(vd.get("weight_capacity", 0.0)) - float(vd.get("total_cargo_weight", 0.0))
		out.append({
			"name": str(vd.get("name", "Vehicle")),
			# A vehicle over-filled by the old server allocator (S13-16) reads negative here. Clamp,
			# so it simply contributes nothing instead of eating another vehicle's room.
			"free_volume": maxf(0.0, free_vol),
			"free_weight": maxf(0.0, free_wt),
		})
	return out


## The convoy's per-vehicle rows, whichever key this particular convoy dict happens to carry.
## The API emits `vehicles` (backend `Convoy.to_JSONable_dict`); augmented client-side copies use
## `vehicle_details_list`. Reading only one of them silently yields an empty plan — which is not a
## safe failure, because callers then fall back to pooled maths and Max over-offers again (S13-19).
## Same fallback chain every other consumer here uses (e.g. `mechanics_menu.gd:102`,
## `convoy_menu.gd:2653`, `warehouse_menu.gd:2732-2750`).
static func vehicle_rows(convoy_data: Dictionary) -> Array:
	for key in ["vehicle_details_list", "vehicles", "vehicle_list"]:
		var v: Variant = convoy_data.get(key)
		if v is Array and not (v as Array).is_empty():
			return v as Array
	return []


## Plan the placement of up to `wanted` units.
## `unit_volume` / `unit_weight` <= 0 mean "this dimension is unknown" and the constraint is skipped —
## callers should treat an unknown as a reason to log, not to trust (see `explain_unknowns`).
## Returns {
##   "quantity": int,                  # how many actually fit
##   "placements": Array of {"name", "quantity"},
##   "blocked_by": "" | "volume" | "weight",   # what stopped the NEXT unit, when short
##   "best_free_volume": float,        # most room left in any single vehicle, after placement
##   "best_free_weight": float,
## }
static func plan(vehicle_spaces: Array, unit_volume: float, unit_weight: float, wanted: int) -> Dictionary:
	var placements: Array = []
	if wanted <= 0:
		return {"quantity": 0, "placements": placements, "blocked_by": "",
				"best_free_volume": 0.0, "best_free_weight": 0.0}

	# Work on copies: callers reuse the space list, and we deduct as we go so the leftovers below
	# describe the convoy AFTER this purchase, which is what the shortfall message needs.
	var ordered: Array = []
	for space_any in vehicle_spaces:
		if space_any is Dictionary:
			ordered.append((space_any as Dictionary).duplicate())
	# Largest free volume first. Same order as the server, and filling small vehicles first would
	# strand room that no whole unit could then use.
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("free_volume", 0.0)) > float(b.get("free_volume", 0.0))
	)

	var remaining: int = wanted
	for space in ordered:
		if remaining <= 0:
			break
		var free_vol: float = float(space.get("free_volume", 0.0))
		var free_wt: float = float(space.get("free_weight", 0.0))
		var fits_by_volume: int = remaining
		if unit_volume > 0.0:
			fits_by_volume = int(floor(free_vol / unit_volume))
		var fits_by_weight: int = remaining
		if unit_weight > 0.0:
			fits_by_weight = int(floor(free_wt / unit_weight))
		var take: int = mini(mini(fits_by_volume, fits_by_weight), remaining)
		if take <= 0:
			continue
		placements.append({"name": str(space.get("name", "Vehicle")), "quantity": take})
		space["free_volume"] = free_vol - float(take) * maxf(0.0, unit_volume)
		space["free_weight"] = free_wt - float(take) * maxf(0.0, unit_weight)
		remaining -= take

	# What's left anywhere, and which dimension refuses the next unit. Volume is reported first
	# because it is the one players can see in the cargo list.
	var best_vol: float = 0.0
	var best_wt: float = 0.0
	for space in ordered:
		best_vol = maxf(best_vol, float(space.get("free_volume", 0.0)))
		best_wt = maxf(best_wt, float(space.get("free_weight", 0.0)))
	var blocked_by: String = ""
	if remaining > 0:
		if unit_volume > 0.0 and best_vol < unit_volume:
			blocked_by = "volume"
		elif unit_weight > 0.0 and best_wt < unit_weight:
			blocked_by = "weight"

	return {
		"quantity": wanted - remaining,
		"placements": placements,
		"blocked_by": blocked_by,
		"best_free_volume": best_vol,
		"best_free_weight": best_wt,
	}


## Short, player-facing explanation of why only `plan.quantity` of `wanted` fit. "" when it all fits.
## Deliberately terse — this lands on the Buy button and one footer line, both of which are tight in
## portrait.
static func describe_shortfall(plan_result: Dictionary, wanted: int) -> String:
	var fits: int = int(plan_result.get("quantity", 0))
	if fits >= wanted:
		return ""
	var blocked: String = str(plan_result.get("blocked_by", ""))
	var detail: String = ""
	match blocked:
		"volume":
			detail = "biggest space left is %s m³" % NumberFormat.fmt_float(float(plan_result.get("best_free_volume", 0.0)), 1)
		"weight":
			detail = "only %s kg spare in any vehicle" % NumberFormat.fmt_float(float(plan_result.get("best_free_weight", 0.0)), 0)
		_:
			detail = "convoy is full"
	if fits <= 0:
		return "None fit — %s" % detail
	return "Only %d of %d fit — %s" % [fits, wanted, detail]


## S13-20 — read the server's fit count off a refused buy.
## `Vendor.sell_cargo()` appends ` [fits:N/M]` to every refusal it raises: N units of the M asked for
## would have fitted, measured by the allocator this file mirrors, over convoy state the server had
## just read. Lives here rather than in the panel because it is the other half of the same wire
## contract — if the marker's shape changes on the server, it changes here, next to the algorithm.
## Returns {"message": String with the marker removed, "fits": int, "requested": int, "found": bool}.
## The message MUST be stripped before display: ErrorTranslator matches on substrings and would
## otherwise print "[fits:3/13]" to the player.
static func parse_server_fit_marker(raw_message: String) -> Dictionary:
	var out: Dictionary = {"message": raw_message, "fits": 0, "requested": 0, "found": false}
	var re := RegEx.new()
	if re.compile("\\s*\\[fits:(\\d+)/(\\d+)\\]") != OK:
		return out
	var m: RegExMatch = re.search(raw_message)
	if m == null:
		return out
	out["message"] = (raw_message.substr(0, m.get_start()) + raw_message.substr(m.get_end())).strip_edges()
	out["fits"] = int(m.get_string(1))
	out["requested"] = int(m.get_string(2))
	out["found"] = true
	return out


## Human-readable note about dimensions we could not measure, or "" when both were known.
## The old pooled code let a missing unit_weight/unit_volume silently disable that constraint
## (S13-7); this exists so the gap is at least visible in the log instead.
static func explain_unknowns(unit_volume: float, unit_weight: float) -> String:
	var missing: Array = []
	if unit_volume <= 0.0:
		missing.append("volume")
	if unit_weight <= 0.0:
		missing.append("weight")
	if missing.is_empty():
		return ""
	return "unit %s unknown — that constraint was NOT applied" % " and ".join(missing)
