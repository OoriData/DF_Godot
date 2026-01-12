# VendorService.gd
extends Node

# Thin service for vendor data flows and transaction outcomes.

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")

const VendorModel = preload("res://Scripts/Data/Models/Vendor.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Bridge transport to domain event
	if is_instance_valid(_api) and _api.has_signal("vendor_data_received"):
		if not _api.vendor_data_received.is_connected(_on_vendor_data_received):
			_api.vendor_data_received.connect(_on_vendor_data_received)

func request_vendor(vendor_id: String) -> void:
	if vendor_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("request_vendor_data"):
		_api.request_vendor_data(vendor_id)

func request_vendor_panel(_convoy_id: String, vendor_id: String) -> void:
	# Thin alias for now; downstream UI can differentiate by listening to panel event.
	if vendor_id == "":
		return
	request_vendor(vendor_id)

func request_vendor_preview(vendor_id: String) -> void:
	# Thin alias to request vendor; emits preview event on receive.
	if vendor_id == "":
		return
	request_vendor(vendor_id)

func _on_vendor_data_received(vendor_data: Dictionary) -> void:
	var data := vendor_data if vendor_data != null else {}
	var logger := get_node_or_null("/root/Logger")
	if is_instance_valid(logger):
		logger.debug("VendorService: vendor data received keys=%s", (data.keys() if data is Dictionary else []))
	if is_instance_valid(_hub) and _hub.has_signal("vendor_updated"):
		_hub.vendor_updated.emit(data)
	# Emit panel and preview events for downstream UI flows
	if is_instance_valid(_hub) and _hub.has_signal("vendor_panel_ready"):
		_hub.vendor_panel_ready.emit(data)
	if is_instance_valid(_hub) and _hub.has_signal("vendor_preview_ready"):
		_hub.vendor_preview_ready.emit(data)


func to_model(vendor_data: Dictionary):
	return VendorModel.new(vendor_data)

# --- Transaction wrappers (Phase 4): UI calls VendorService, not APICalls ---
func buy_resource(vendor_id: String, convoy_id: String, resource_type: String, quantity: float) -> void:
	if not is_instance_valid(_api):
		return
	if _api.has_method("buy_resource"):
		_api.buy_resource(vendor_id, convoy_id, resource_type, quantity)

func sell_resource(vendor_id: String, convoy_id: String, resource_type: String, quantity: float) -> void:
	if not is_instance_valid(_api):
		return
	if _api.has_method("sell_resource"):
		_api.sell_resource(vendor_id, convoy_id, resource_type, quantity)

func buy_cargo(vendor_id: String, convoy_id: String, cargo_id: String, quantity: int) -> void:
	if not is_instance_valid(_api):
		return
	if _api.has_method("buy_cargo"):
		_api.buy_cargo(vendor_id, convoy_id, cargo_id, quantity)

func sell_cargo(vendor_id: String, convoy_id: String, cargo_id: String, quantity: int) -> void:
	if not is_instance_valid(_api):
		return
	if _api.has_method("sell_cargo"):
		_api.sell_cargo(vendor_id, convoy_id, cargo_id, quantity)

func buy_vehicle(vendor_id: String, convoy_id: String, vehicle_id: String) -> void:
	if not is_instance_valid(_api):
		return
	if _api.has_method("buy_vehicle"):
		_api.buy_vehicle(vendor_id, convoy_id, vehicle_id)

func sell_vehicle(vendor_id: String, convoy_id: String, vehicle_id: String) -> void:
	if not is_instance_valid(_api):
		return
	if _api.has_method("sell_vehicle"):
		_api.sell_vehicle(vendor_id, convoy_id, vehicle_id)
