class_name Convoy

extends RefCounted

var convoy_id: String = ""
var name: String = ""
var x: float = 0.0
var y: float = 0.0
var journey: Dictionary = {}
var vehicle_details_list: Array = []
var raw: Dictionary = {}

func _init(d: Dictionary = {}) -> void:
	load_from_dict(d)

func load_from_dict(d: Dictionary) -> void:
	raw = (d if d != null else {}).duplicate(true)
	convoy_id = String(raw.get("convoy_id", raw.get("id", "")))
	name = String(raw.get("name", raw.get("convoy_name", "")))
	x = _to_float(raw.get("x", 0.0))
	y = _to_float(raw.get("y", 0.0))
	var j: Variant = raw.get("journey", {})
	journey = (j as Dictionary) if j is Dictionary else {}
	var v: Variant = raw.get("vehicle_details_list", raw.get("vehicles", []))
	vehicle_details_list = (v as Array) if v is Array else []

func to_dict() -> Dictionary:
	return raw.duplicate(true)

func get_vehicle_dicts() -> Array:
	return vehicle_details_list

func get_journey_id() -> String:
	if not (journey is Dictionary):
		return ""
	return String(journey.get("journey_id", ""))

static func _to_float(v: Variant) -> float:
	if v == null:
		return 0.0
	if v is float or v is int:
		return float(v)
	if v is String and (v as String).is_valid_float():
		return float(v)
	return 0.0
