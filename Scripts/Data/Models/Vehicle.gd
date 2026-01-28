class_name Vehicle

extends RefCounted

var vehicle_id: String = ""
var name: String = ""
var cargo: Array = []
var parts: Array = []
var raw: Dictionary = {}

func _init(d: Dictionary = {}) -> void:
	load_from_dict(d)

func load_from_dict(d: Dictionary) -> void:
	raw = (d if d != null else {}).duplicate(true)
	vehicle_id = String(raw.get("vehicle_id", raw.get("id", "")))
	name = String(raw.get("name", ""))
	var c_any: Variant = raw.get("cargo", [])
	cargo = (c_any as Array) if c_any is Array else []
	var p_any: Variant = raw.get("parts", [])
	parts = (p_any as Array) if p_any is Array else []

func to_dict() -> Dictionary:
	return raw.duplicate(true)
