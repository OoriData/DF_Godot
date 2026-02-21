class_name Vehicle

extends RefCounted

var vehicle_id: String = ""
var name: String = ""
var color: String = ""
var shape: String = ""
var weight_class: float = 0.0
var cargo: Array = []
var parts: Array = []
var raw: Dictionary = {}

func _init(d: Dictionary = {}) -> void:
	load_from_dict(d)

func load_from_dict(d: Dictionary) -> void:
	raw = (d if d != null else {}).duplicate(true)
	vehicle_id = String(raw.get("vehicle_id", raw.get("id", "")))
	name = String(raw.get("name", ""))
	color = String(raw.get("color", ""))
	shape = String(raw.get("shape", ""))
	weight_class = _to_float(raw.get("weight_class", 0.0))
	
	var c_any: Variant = raw.get("cargo", [])
	cargo = (c_any as Array) if c_any is Array else []
	var p_any: Variant = raw.get("parts", [])
	parts = (p_any as Array) if p_any is Array else []

func to_dict() -> Dictionary:
	return raw.duplicate(true)

static func _to_float(v: Variant) -> float:
	if v == null:
		return 0.0
	if v is float or v is int:
		return float(v)
	if v is String and (v as String).is_valid_float():
		return float(v)
	return 0.0
