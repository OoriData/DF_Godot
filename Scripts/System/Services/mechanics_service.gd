# MechanicsService.gd
extends Node

# Thin service for mechanics compatibility flows: attach/detach parts.

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(_api):
		if _api.has_signal("vehicle_part_attached") and not _api.vehicle_part_attached.is_connected(_on_attach_completed):
			_api.vehicle_part_attached.connect(_on_attach_completed)
		if _api.has_signal("vehicle_part_detached") and not _api.vehicle_part_detached.is_connected(_on_detach_completed):
			_api.vehicle_part_detached.connect(_on_detach_completed)
		if _api.has_signal("part_compatibility_checked") and not _api.part_compatibility_checked.is_connected(_on_compatibility_checked):
			_api.part_compatibility_checked.connect(_on_compatibility_checked)
		if _api.has_signal("mechanic_operation_failed") and not _api.mechanic_operation_failed.is_connected(_on_operation_failed):
			_api.mechanic_operation_failed.connect(_on_operation_failed)

func attach_part(convoy_id: String, vehicle_id: String, part_id: String) -> void:
	if convoy_id == "" or vehicle_id == "" or part_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("attach_vehicle_part"):
		_api.attach_vehicle_part(convoy_id, vehicle_id, part_id)

func detach_part(convoy_id: String, vehicle_id: String, part_id: String) -> void:
	if convoy_id == "" or vehicle_id == "" or part_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("detach_vehicle_part"):
		_api.detach_vehicle_part(convoy_id, vehicle_id, part_id)

func check_part_compatibility(vehicle_id: String, cargo_id: String) -> void:
	if vehicle_id == "" or cargo_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("check_vehicle_part_compatibility"):
		_api.check_vehicle_part_compatibility(vehicle_id, cargo_id)

func _on_attach_completed(updated_convoy_data: Dictionary) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("convoy_updated"):
		_hub.convoy_updated.emit(updated_convoy_data)

func _on_detach_completed(updated_convoy_data: Dictionary) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("convoy_updated"):
		_hub.convoy_updated.emit(updated_convoy_data)

func _on_compatibility_checked(payload: Dictionary) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("part_compatibility_ready"):
		_hub.part_compatibility_ready.emit(payload)

func _on_operation_failed(error: Dictionary) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("error_occurred"):
		_hub.error_occurred.emit(error)
