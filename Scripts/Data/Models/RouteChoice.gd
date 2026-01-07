class_name RouteChoice

extends RefCounted

var journey_id: String = ""
var route_x: Array = []
var route_y: Array = []
var journey: Dictionary = {}
var raw: Dictionary = {}

func _init(d: Dictionary = {}) -> void:
	load_from_dict(d)

func load_from_dict(d: Dictionary) -> void:
	raw = (d if d != null else {}).duplicate(true)
	var j_any: Variant = raw.get("journey", {})
	journey = (j_any as Dictionary) if j_any is Dictionary else {}
	journey_id = String(journey.get("journey_id", raw.get("journey_id", "")))
	var rx_any: Variant = journey.get("route_x", raw.get("route_x", []))
	var ry_any: Variant = journey.get("route_y", raw.get("route_y", []))
	route_x = (rx_any as Array) if rx_any is Array else []
	route_y = (ry_any as Array) if ry_any is Array else []

func to_dict() -> Dictionary:
	return raw.duplicate(true)

func get_path_points() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if route_x.size() != route_y.size():
		return out
	for i in range(route_x.size()):
		out.append(Vector2i(int(route_x[i]), int(route_y[i])))
	return out
