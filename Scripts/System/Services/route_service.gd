# RouteService.gd
extends Node

# Thin service for route choices and journey control.

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Bridge transport to domain events
	if is_instance_valid(_api):
		if _api.has_signal("route_choices_received") and not _api.route_choices_received.is_connected(_on_route_choices_received):
			_api.route_choices_received.connect(_on_route_choices_received)
		if _api.has_signal("convoy_sent_on_journey") and not _api.convoy_sent_on_journey.is_connected(_on_convoy_on_journey):
			_api.convoy_sent_on_journey.connect(_on_convoy_on_journey)
		if _api.has_signal("convoy_journey_canceled") and not _api.convoy_journey_canceled.is_connected(_on_convoy_journey_canceled):
			_api.convoy_journey_canceled.connect(_on_convoy_journey_canceled)

func request_choices(convoy_id: String, dest_x: int, dest_y: int) -> void:
	if convoy_id == "":
		return
	if is_instance_valid(_hub) and _hub.has_signal("route_choices_request_started"):
		_hub.route_choices_request_started.emit()
	if is_instance_valid(_api) and _api.has_method("find_route"):
		_api.find_route(convoy_id, dest_x, dest_y)

func start_journey(convoy_id: String, journey_id: String) -> void:
	if convoy_id == "" or journey_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("send_convoy"):
		_api.send_convoy(convoy_id, journey_id)

func cancel_journey(convoy_id: String, journey_id: String) -> void:
	if convoy_id == "" or journey_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("cancel_convoy_journey"):
		_api.cancel_convoy_journey(convoy_id, journey_id)

func _on_route_choices_received(routes: Array) -> void:
	var logger := get_node_or_null("/root/Logger")
	if is_instance_valid(logger):
		logger.debug("RouteService: choices received count=%s", routes.size())
	if is_instance_valid(_hub) and _hub.has_signal("route_choices_ready"):
		_hub.route_choices_ready.emit(routes)

func _on_convoy_on_journey(updated_convoy_data: Dictionary) -> void:
	var hub := _hub
	if is_instance_valid(hub) and hub.has_signal("convoy_updated"):
		hub.convoy_updated.emit(updated_convoy_data)

func _on_convoy_journey_canceled(updated_convoy_data: Dictionary) -> void:
	var hub := _hub
	if is_instance_valid(hub) and hub.has_signal("convoy_updated"):
		hub.convoy_updated.emit(updated_convoy_data)
