class_name Vendor

extends RefCounted

var vendor_id: String = ""
var name: String = ""
var sett_id: String = ""
var cargo_inventory: Array = []
var vehicle_inventory: Array = []
var raw: Dictionary = {}

func _init(d: Dictionary = {}) -> void:
	load_from_dict(d)

func load_from_dict(d: Dictionary) -> void:
	raw = (d if d != null else {}).duplicate(true)
	vendor_id = String(raw.get("vendor_id", raw.get("id", "")))
	name = String(raw.get("name", ""))
	sett_id = String(raw.get("sett_id", ""))
	var c_any: Variant = raw.get("cargo_inventory", [])
	cargo_inventory = (c_any as Array) if c_any is Array else []
	var vi_any: Variant = raw.get("vehicle_inventory", [])
	vehicle_inventory = (vi_any as Array) if vi_any is Array else []

func to_dict() -> Dictionary:
	return raw.duplicate(true)
