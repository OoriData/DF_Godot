# VendorService.gd
extends Node

# Thin service for vendor data flows and transaction outcomes.

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")

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

func request_vendor_panel(convoy_id: String, vendor_id: String) -> void:
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
