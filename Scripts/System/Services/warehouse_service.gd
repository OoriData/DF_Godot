# WarehouseService.gd
extends Node

# Thin service for warehouse data and actions. Bridges APICalls warehouse signals
# into domain-level SignalHub events and provides minimal request wrappers.

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(_api):
		if _api.has_signal("warehouse_received") and not _api.warehouse_received.is_connected(_on_warehouse_received):
			_api.warehouse_received.connect(_on_warehouse_received)

# --- Thin request wrappers ---
func request_new(settlement_id: String) -> void:
	if settlement_id == "": return
	if is_instance_valid(_api) and _api.has_method("warehouse_new"):
		_api.warehouse_new(settlement_id)

func request_get(warehouse_id: String) -> void:
	if warehouse_id == "": return
	if is_instance_valid(_api) and _api.has_method("get_warehouse"):
		_api.get_warehouse(warehouse_id)

func request_expand(params: Dictionary) -> void:
	if params == null: return
	# Prefer JSON body when explicit expand_type is provided (fallback path)
	if is_instance_valid(_api) and params.has("expand_type") and _api.has_method("warehouse_expand_json"):
		_api.warehouse_expand_json(params)
		_refresh_warehouse_if_possible(params)
	elif is_instance_valid(_api) and _api.has_method("warehouse_expand_v2"):
		var wid := String(params.get("warehouse_id", ""))
		var cargo_units := int(params.get("cargo_units", 0))
		var vehicle_units := int(params.get("vehicle_units", 0))
		if wid != "": _api.warehouse_expand_v2(wid, cargo_units, vehicle_units)
		_refresh_warehouse_if_possible({"warehouse_id": wid})
	elif is_instance_valid(_api) and _api.has_method("warehouse_expand_json"):
		_api.warehouse_expand_json(params)
		_refresh_warehouse_if_possible(params)
	elif is_instance_valid(_api) and _api.has_method("warehouse_expand"):
		_api.warehouse_expand(params)
		_refresh_warehouse_if_possible(params)

func store_cargo(params: Dictionary) -> void:
	if is_instance_valid(_api) and _api.has_method("warehouse_cargo_store"):
		_api.warehouse_cargo_store(params)
		_refresh_warehouse_if_possible(params)

func retrieve_cargo(params: Dictionary) -> void:
	if is_instance_valid(_api) and _api.has_method("warehouse_cargo_retrieve"):
		_api.warehouse_cargo_retrieve(params)
		_refresh_warehouse_if_possible(params)

func store_vehicle(params: Dictionary) -> void:
	if is_instance_valid(_api) and _api.has_method("warehouse_vehicle_store"):
		_api.warehouse_vehicle_store(params)
		_refresh_warehouse_if_possible(params)

func retrieve_vehicle(params: Dictionary) -> void:
	if is_instance_valid(_api) and _api.has_method("warehouse_vehicle_retrieve"):
		_api.warehouse_vehicle_retrieve(params)
		_refresh_warehouse_if_possible(params)

func spawn_convoy(params: Dictionary) -> void:
	if is_instance_valid(_api) and _api.has_method("warehouse_convoy_spawn"):
		_api.warehouse_convoy_spawn(params)
		_refresh_warehouse_if_possible(params)

# --- Helpers ---
func _refresh_warehouse_if_possible(params: Dictionary) -> void:
	if params == null:
		return
	var wid := String(params.get("warehouse_id", params.get("id", "")))
	if wid == "":
		return
	if is_instance_valid(_api) and _api.has_method("get_warehouse"):
		_api.get_warehouse(wid)

# --- Signal forwards to SignalHub ---
func _on_warehouse_created(result: Variant) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("warehouse_created"):
		_hub.warehouse_created.emit(result)

func _on_warehouse_received(warehouse_data: Dictionary) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("warehouse_updated"):
		_hub.warehouse_updated.emit(warehouse_data)

func _on_warehouse_expanded(result: Variant) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("warehouse_expanded"):
		_hub.warehouse_expanded.emit(result)

func _on_warehouse_cargo_stored(result: Variant) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("warehouse_cargo_stored"):
		_hub.warehouse_cargo_stored.emit(result)

func _on_warehouse_cargo_retrieved(result: Variant) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("warehouse_cargo_retrieved"):
		_hub.warehouse_cargo_retrieved.emit(result)

func _on_warehouse_vehicle_stored(result: Variant) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("warehouse_vehicle_stored"):
		_hub.warehouse_vehicle_stored.emit(result)

func _on_warehouse_vehicle_retrieved(result: Variant) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("warehouse_vehicle_retrieved"):
		_hub.warehouse_vehicle_retrieved.emit(result)

func _on_warehouse_convoy_spawned(result: Variant) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("warehouse_convoy_spawned"):
		_hub.warehouse_convoy_spawned.emit(result)
