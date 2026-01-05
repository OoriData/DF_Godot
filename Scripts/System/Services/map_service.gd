# MapService.gd
extends Node

# Thin domain service for map requests and snapshots via GameStore.

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _store: Node = get_node_or_null("/root/GameStore")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func request_map(x_min: int = -1, x_max: int = -1, y_min: int = -1, y_max: int = -1) -> void:
	if is_instance_valid(_api) and _api.has_method("get_map_data"):
		if is_instance_valid(get_node_or_null("/root/Logger")):
			get_node("/root/Logger").info("MapService.request_map x_min=%s x_max=%s y_min=%s y_max=%s", x_min, x_max, y_min, y_max)
		_api.get_map_data(x_min, x_max, y_min, y_max)

func get_tiles() -> Array:
	if is_instance_valid(_store) and _store.has_method("get_tiles"):
		return _store.get_tiles()
	return []

func get_settlements() -> Array:
	if is_instance_valid(_store) and _store.has_method("get_settlements"):
		return _store.get_settlements()
	return []
