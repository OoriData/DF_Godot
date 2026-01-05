# WarehouseService.gd
extends Node

# Thin service for warehouse data and actions. Bridges APICalls warehouse signals
# into domain-level SignalHub events and provides minimal request wrappers.

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(_api):
		if _api.has_signal("warehouse_created") and not _api.warehouse_created.is_connected(_on_warehouse_created):
			_api.warehouse_created.connect(_on_warehouse_created)
		if _api.has_signal("warehouse_received") and not _api.warehouse_received.is_connected(_on_warehouse_received):
			_api.warehouse_received.connect(_on_warehouse_received)
		if _api.has_signal("warehouse_expanded") and not _api.warehouse_expanded.is_connected(_on_warehouse_expanded):
			_api.warehouse_expanded.connect(_on_warehouse_expanded)
		if _api.has_signal("warehouse_cargo_stored") and not _api.warehouse_cargo_stored.is_connected(_on_warehouse_cargo_stored):
			_api.warehouse_cargo_stored.connect(_on_warehouse_cargo_stored)
		if _api.has_signal("warehouse_cargo_retrieved") and not _api.warehouse_cargo_retrieved.is_connected(_on_warehouse_cargo_retrieved):
			_api.warehouse_cargo_retrieved.connect(_on_warehouse_cargo_retrieved)
		if _api.has_signal("warehouse_vehicle_stored") and not _api.warehouse_vehicle_stored.is_connected(_on_warehouse_vehicle_stored):
			_api.warehouse_vehicle_stored.connect(_on_warehouse_vehicle_stored)
		if _api.has_signal("warehouse_vehicle_retrieved") and not _api.warehouse_vehicle_retrieved.is_connected(_on_warehouse_vehicle_retrieved):
			_api.warehouse_vehicle_retrieved.connect(_on_warehouse_vehicle_retrieved)
		if _api.has_signal("warehouse_convoy_spawned") and not _api.warehouse_convoy_spawned.is_connected(_on_warehouse_convoy_spawned):
			_api.warehouse_convoy_spawned.connect(_on_warehouse_convoy_spawned)

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
	if is_instance_valid(_api) and _api.has_method("warehouse_expand_v2"):
		var wid := String(params.get("warehouse_id", ""))
		var cargo_units := int(params.get("cargo_units", 0))
		var vehicle_units := int(params.get("vehicle_units", 0))
		if wid != "": _api.warehouse_expand_v2(wid, cargo_units, vehicle_units)
	elif is_instance_valid(_api) and _api.has_method("warehouse_expand_json"):
		_api.warehouse_expand_json(params)
	elif is_instance_valid(_api) and _api.has_method("warehouse_expand"):
		_api.warehouse_expand(params)

func store_cargo(params: Dictionary) -> void:
	if is_instance_valid(_api) and _api.has_method("warehouse_cargo_store"):
		_api.warehouse_cargo_store(params)

func retrieve_cargo(params: Dictionary) -> void:
	if is_instance_valid(_api) and _api.has_method("warehouse_cargo_retrieve"):
		_api.warehouse_cargo_retrieve(params)

func store_vehicle(params: Dictionary) -> void:
	if is_instance_valid(_api) and _api.has_method("warehouse_vehicle_store"):
		_api.warehouse_vehicle_store(params)

func retrieve_vehicle(params: Dictionary) -> void:
	if is_instance_valid(_api) and _api.has_method("warehouse_vehicle_retrieve"):
		_api.warehouse_vehicle_retrieve(params)

func spawn_convoy(params: Dictionary) -> void:
	if is_instance_valid(_api) and _api.has_method("warehouse_convoy_spawn"):
		_api.warehouse_convoy_spawn(params)

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
