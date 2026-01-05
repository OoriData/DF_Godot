# ConvoyService.gd
extends Node

# Thin domain service for convoy orchestration: refresh and snapshots.

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _store: Node = get_node_or_null("/root/GameStore")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func refresh_all() -> void:
	# Triggers a transport call; APICalls will route results into GameStore.
	if is_instance_valid(_api) and _api.has_method("get_all_in_transit_convoys"):
		if is_instance_valid(get_node_or_null("/root/Logger")):
			get_node("/root/Logger").info("ConvoyService.refresh_all()")
		_api.get_all_in_transit_convoys()

func refresh_single(convoy_id: String) -> void:
	if convoy_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("get_convoy_data"):
		if is_instance_valid(get_node_or_null("/root/Logger")):
			get_node("/root/Logger").info("ConvoyService.refresh_single id=%s", convoy_id)
		_api.get_convoy_data(convoy_id)

func get_convoys() -> Array:
	if is_instance_valid(_store) and _store.has_method("get_convoys"):
		return _store.get_convoys()
	return []
