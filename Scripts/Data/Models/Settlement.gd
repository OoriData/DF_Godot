class_name Settlement

extends RefCounted

var sett_id: String = ""
var name: String = ""
var sett_type: String = ""
var x: int = 0
var y: int = 0
var vendors: Array = []
var raw: Dictionary = {}

func _init(d: Dictionary = {}) -> void:
	load_from_dict(d)

func load_from_dict(d: Dictionary) -> void:
	raw = (d if d != null else {}).duplicate(true)
	sett_id = String(raw.get("sett_id", raw.get("id", "")))
	name = String(raw.get("name", ""))
	sett_type = String(raw.get("sett_type", ""))
	x = _to_int(raw.get("x", 0))
	y = _to_int(raw.get("y", 0))
	var v_any: Variant = raw.get("vendors", [])
	vendors = (v_any as Array) if v_any is Array else []

func to_dict() -> Dictionary:
	return raw.duplicate(true)

static func _to_int(v: Variant) -> int:
	if v == null:
		return 0
	if v is int:
		return v
	if v is float:
		return int(roundf(v))
	if v is String:
		var s := v as String
		if s.is_valid_int():
			return int(s)
		if s.is_valid_float():
			return int(roundf(float(s)))
	return 0
