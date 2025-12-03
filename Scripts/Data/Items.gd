extends Resource
# Data classes for standardized convoy/vendor cargo items.
# Each item type exposes predictable, typed properties and helper methods.
# Factory usage: var item = CargoItem.from_dict(raw_dict)

class_name CargoItem

# --- Core Common Properties ---
var id: String = ""              # cargo_id or constructed synthetic id
var name: String = ""            # display-friendly name
var quantity: int = 0             # total quantity (>=1)
var unit_weight: float = 0.0      # weight per unit
var unit_volume: float = 0.0      # volume per unit
var total_weight: float = 0.0     # cached total (quantity * unit_weight)
var total_volume: float = 0.0     # cached total (quantity * unit_volume)
var category: String = "other"    # coarse bucket: part / mission / resource / vehicle / other
var base_desc: String = ""        # base description if present
var quality: float = -1.0         # -1 when not applicable
var condition: float = -1.0       # -1 when not applicable
var tags: Array[String] = []      # category/type/subtype tags
var raw: Dictionary = {}          # original raw dictionary (for legacy fallback / migration)

# --- Construction / Parsing Helpers ---
static func _to_float(v) -> float:
	if v == null: return 0.0
	if v is float or v is int: return float(v)
	if v is String and v.is_valid_float(): return float(v)
	return 0.0

static func _to_int(v) -> int:
	if v == null: return 0
	if v is int: return v
	if v is float: return int(v)
	if v is String and v.is_valid_int(): return int(v)
	if v is String and v.is_valid_float(): return int(float(v))
	return 0

static func _safe_name(d: Dictionary) -> String:
	for k in ["name", "base_name", "specific_name"]:
		if d.has(k):
			var v = d.get(k)
			var s = v if v is String else str(v)
			if s.strip_edges() != "":
				return s
	return "Unknown Item"

static func _compute_unit(base_total: float, qty: int, explicit_unit: float) -> float:
	if explicit_unit > 0.0: return explicit_unit
	if qty > 0 and base_total > 0.0: return base_total / float(qty)
	return 0.0

# --- Factory ---
static func from_dict(d: Dictionary) -> CargoItem:
	# Decide subtype and delegate to its parser
	if MissionItem._looks_like_mission_dict(d):
		return MissionItem._from_mission_dict(d)
	if ResourceItem._looks_like_resource_dict(d):
		return ResourceItem._from_resource_dict(d)
	if VehicleItem._looks_like_vehicle_dict(d):
		return VehicleItem._from_vehicle_dict(d)
	if PartItem._looks_like_part_dict(d):
		return PartItem._from_part_dict(d)
	return _parse_base(d)

# Internal: parse only the base fields without re-classification to avoid recursion
static func _parse_base(d: Dictionary) -> CargoItem:
	var item := CargoItem.new()
	item.raw = d.duplicate(true)
	item.id = String(d.get("cargo_id", d.get("id", "")))
	item.name = _safe_name(d)
	item.quantity = max(1, _to_int(d.get("quantity", 1)))
	var raw_total_weight = _to_float(d.get("weight", d.get("total_weight", 0)))
	var raw_total_volume = _to_float(d.get("volume", d.get("total_volume", 0)))
	var unit_w = _to_float(d.get("unit_weight", 0))
	var unit_v = _to_float(d.get("unit_volume", 0))
	item.unit_weight = _compute_unit(raw_total_weight, item.quantity, unit_w)
	item.unit_volume = _compute_unit(raw_total_volume, item.quantity, unit_v)
	item.total_weight = item.unit_weight * float(item.quantity)
	item.total_volume = item.unit_volume * float(item.quantity)
	item.category = "other"
	var base_desc_val = d.get("base_desc") if d.has("base_desc") else d.get("description", "")
	item.base_desc = base_desc_val if base_desc_val is String else str(base_desc_val)
	item.quality = _to_float(d.get("quality", -1))
	item.condition = _to_float(d.get("condition", -1))
	for tag_k in ["category", "type", "subtype"]:
		if d.has(tag_k):
			var tv = d.get(tag_k)
			var ts = tv if tv is String else str(tv)
			if ts.strip_edges() != "":
				item.tags.append(ts)
	return item

func get_total_weight() -> float:
	return unit_weight * float(quantity)

func get_total_volume() -> float:
	return unit_volume * float(quantity)

func is_part() -> bool: return category == "part"
func is_resource() -> bool: return category == "resource"
func is_mission() -> bool: return category == "mission"
func is_vehicle() -> bool: return category == "vehicle"

func summary_line() -> String:
	# Generic fallback summary
	var bits: Array[String] = []
	if quality >= 0: bits.append("Q%.0f" % quality)
	if condition >= 0: bits.append("Cond%.0f" % condition)
	return name + (" (" + ", ".join(bits) + ")" if not bits.is_empty() else "")

# ================= PartItem =================
class PartItem:
	extends CargoItem
	var slot: String = ""
	var modifiers: Dictionary = {} # additive / capacity stats
	var stats: Dictionary = {}      # optional nested stats dictionary
	var modifiers_summary: String = "" # precomputed concise summary

	static func _looks_like_part_dict(d: Dictionary) -> bool:
		if not d:
			return false

		# First, rule out items that are explicitly resources to avoid misclassifying containers.
		if d.get("is_raw_resource", false):
			return false
		if str(d.get("category", "")).to_lower() == "resource":
			return false
		if ((d.get("food") is float or d.get("food") is int) and float(d.get("food", 0.0)) > 0.0) or \
		   ((d.get("water") is float or d.get("water") is int) and float(d.get("water", 0.0)) > 0.0) or \
		   ((d.get("fuel") is float or d.get("fuel") is int) and float(d.get("fuel", 0.0)) > 0.0):
			return false

		# --- Now check for part signals, from strongest to weakest ---
		if str(d.get("category", "")).to_lower() == "part":
			return true
		if d.has("slot") and d.get("slot") != null and String(d.get("slot")).length() > 0:
			return true
		if d.has("intrinsic_part_id"):
			return true
		if d.has("parts") and d.get("parts") is Array and not (d.get("parts") as Array).is_empty():
			var first_p = (d.get("parts") as Array)[0]
			if first_p is Dictionary and first_p.has("slot") and first_p.get("slot") != null and String(first_p.get("slot")).length() > 0:
				return true
		if d.has("is_part") and bool(d.get("is_part")):
			return true

		var type_s := String(d.get("type", "")).to_lower()
		if type_s == "part":
			return true

		# Check for a non-empty 'stats' dictionary, which is a strong indicator of a part.
		if d.has("stats") and d.get("stats") is Dictionary and not (d.get("stats") as Dictionary).is_empty():
			return true

		var stat_keys := ["top_speed_add", "efficiency_add", "offroad_capability_add", "cargo_capacity_add", "weight_capacity_add", "fuel_capacity", "kwh_capacity"]
		for sk in stat_keys:
			if d.has(sk) and d[sk] != null and (d[sk] is int or d[sk] is float) and float(d[sk]) != 0.0:
				return true

		return false

	static func _from_part_dict(d: Dictionary) -> PartItem:
		var p := PartItem.new()
		var base := CargoItem._parse_base(d)
		for f in ["id","name","quantity","unit_weight","unit_volume","total_weight","total_volume","base_desc","quality","condition","tags"]:
			p.set(f, base.get(f))
		p.raw = base.raw
		p.category = "part"
		p.slot = String(d.get("slot", ""))
		# If slot is empty, try to infer it from a nested 'parts' array. This is common for container-like parts.
		if p.slot == "" and d.has("parts") and d.get("parts") is Array and not (d.get("parts") as Array).is_empty():
			var first_p = (d.get("parts") as Array)[0]
			if first_p is Dictionary and first_p.has("slot") and first_p.get("slot") != null:
				var nested_slot = String(first_p.get("slot"))
				if not nested_slot.is_empty():
					p.slot = nested_slot
		var mod_keys = ["top_speed_add","efficiency_add","offroad_capability_add","cargo_capacity_add","weight_capacity_add","fuel_capacity","kwh_capacity"]
		for mk in mod_keys:
			if d.has(mk): p.modifiers[mk] = CargoItem._to_float(d.get(mk))
		if d.has("modifiers") and d.get("modifiers") is Dictionary:
			for k in d.get("modifiers").keys():
				p.modifiers[k] = d.get("modifiers")[k]
		if d.has("stats") and d.get("stats") is Dictionary:
			p.stats = d.get("stats").duplicate(true)
		p.modifiers_summary = p.get_modifier_summary()
		return p

	func get_modifier_summary() -> String:
		var bits: Array[String] = []
		var compact_labels := {
			"top_speed_add":"Spd","efficiency_add":"Eff","offroad_capability_add":"Off","cargo_capacity_add":"Cargo","weight_capacity_add":"Weight","fuel_capacity":"FuelCap","kwh_capacity":"kWh"
		}
		for k in compact_labels.keys():
			if modifiers.has(k) and CargoItem._to_float(modifiers[k]) > 0.0:
				var v = CargoItem._to_float(modifiers[k])
				bits.append(compact_labels[k] + " " + ("%.0f" % v))
		return "(" + ", ".join(bits) + ")" if not bits.is_empty() else ""

	func summary_line() -> String:
		var base := super.summary_line()
		return base + (" " + modifiers_summary if modifiers_summary != "" else "")

# ================= MissionItem =================
class MissionItem:
	extends CargoItem
	var mission_id: String = ""
	var mission_vendor_id: String = ""
	var mission_type: String = ""

	static func _looks_like_mission_dict(d: Dictionary) -> bool:
		if not d: return false
		if d.get("is_mission", false): return true
		# Check for non-null and non-empty string IDs
		if d.has("mission_id") and d.get("mission_id") != null and str(d.get("mission_id")).strip_edges() != "":
			return true
		if d.has("mission_vendor_id") and d.get("mission_vendor_id") != null and str(d.get("mission_vendor_id")).strip_edges() != "":
			return true
		# Mission cargo must have a positive delivery_reward
		if d.has("delivery_reward"):
			var dr = d.get("delivery_reward")
			if dr != null and (dr is float or dr is int) and float(dr) > 0.0:
				return true
		return false

	static func _from_mission_dict(d: Dictionary) -> MissionItem:
		var m := MissionItem.new()
		var base := CargoItem._parse_base(d)
		for f in ["id","name","quantity","unit_weight","unit_volume","total_weight","total_volume","base_desc","quality","condition","tags"]:
			m.set(f, base.get(f))
		m.raw = base.raw
		m.category = "mission"
		m.mission_id = String(d.get("mission_id",""))
		m.mission_vendor_id = String(d.get("mission_vendor_id",""))
		m.mission_type = String(d.get("mission_type", d.get("type", "")))
		return m

# ================= ResourceItem =================
class ResourceItem:
	extends CargoItem
	var resource_type: String = ""  # fuel / water / food / generic
	var unit_price: float = 0.0

	static func _looks_like_resource_dict(d: Dictionary) -> bool:
		if not d: return false
		if d.get("is_raw_resource", false): return true
		if d.has("resource_type"): return true # explicit type
		# Check for positive resource values. Having a key with value 0 (e.g. `fuel: 0`)
		# should not classify an item as a resource, as parts might have this.
		for k in ["fuel", "water", "food"]:
			if d.has(k):
				var v = d.get(k)
				if (v is float or v is int) and float(v) > 0.0:
					return true
		return false

	static func _from_resource_dict(d: Dictionary) -> ResourceItem:
		var r := ResourceItem.new()
		var base := CargoItem._parse_base(d)
		for f in ["id","name","quantity","unit_weight","unit_volume","total_weight","total_volume","base_desc","quality","condition","tags"]:
			r.set(f, base.get(f))
		r.raw = base.raw
		r.category = "resource"
		for t in ["resource_type","fuel","water","food"]:
			if d.has(t):
				r.resource_type = (t if t in ["fuel","water","food"] else String(d.get(t)))
				break
		if r.resource_type == "":
			r.resource_type = "generic"
		for pk in ["unit_price","price","resource_unit_value","container_unit_price","buy_price","sell_price"]:
			if d.has(pk):
				var v = CargoItem._to_float(d.get(pk))
				if v > 0.0: r.unit_price = v; break
		return r

# ================= VehicleItem =================
class VehicleItem:
	extends CargoItem
	var vehicle_id: String = ""
	var top_speed: float = 0.0
	var efficiency: float = 0.0
	var offroad_capability: float = 0.0
	var cargo_capacity: float = 0.0
	var weight_capacity: float = 0.0

	static func _looks_like_vehicle_dict(d: Dictionary) -> bool:
		if not d:
			return false

		# A dictionary cannot be a vehicle if it's also explicitly a piece of cargo.
		# Cargo items have a cargo_id, vehicle records do not.
		if d.has("cargo_id") and d.get("cargo_id") != null:
			return false

		# Now check for positive signals that it IS a vehicle.
		# Having a vehicle_id (and no cargo_id) is the strongest signal.
		if d.has("vehicle_id") and d.get("vehicle_id") != null:
			return true

		if d.get("is_vehicle", false): return true
		if d.has("top_speed") and d.has("efficiency"): return true

		return false

	static func _from_vehicle_dict(d: Dictionary) -> VehicleItem:
		var v := VehicleItem.new()
		var base := CargoItem._parse_base(d)
		for f in ["id","name","quantity","unit_weight","unit_volume","total_weight","total_volume","base_desc","quality","condition","tags"]:
			v.set(f, base.get(f))
		v.raw = base.raw
		v.category = "vehicle"
		v.vehicle_id = String(d.get("vehicle_id", d.get("id", "")))
		v.top_speed = CargoItem._to_float(d.get("top_speed", d.get("top_speed_add", 0)))
		v.efficiency = CargoItem._to_float(d.get("efficiency", d.get("efficiency_add", 0)))
		v.offroad_capability = CargoItem._to_float(d.get("offroad_capability", d.get("offroad_capability_add", 0)))
		v.cargo_capacity = CargoItem._to_float(d.get("cargo_capacity", d.get("cargo_capacity_add", 0)))
		v.weight_capacity = CargoItem._to_float(d.get("weight_capacity", d.get("weight_capacity_add", 0)))
		return v

# --- Convenience utilities ---
static func classify_many(raw_items: Array) -> Array:
	var out: Array = []
	for r in raw_items:
		if r is Dictionary:
			out.append(CargoItem.from_dict(r))
	return out

static func bucket_by_category(items: Array) -> Dictionary:
	var buckets := {"mission": [], "part": [], "resource": [], "vehicle": [], "other": []}
	for it in items:
		var cat = it.category if it is CargoItem else "other"
		if not buckets.has(cat): buckets[cat] = []
		buckets[cat].append(it)
	return buckets
