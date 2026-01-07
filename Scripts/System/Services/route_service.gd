# RouteService.gd
extends Node

# Thin service for route choices and journey control.

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
@onready var _convoy_service: Node = get_node_or_null("/root/ConvoyService")

const RouteChoiceModel = preload("res://Scripts/Data/Models/RouteChoice.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Bridge transport to domain events
	if is_instance_valid(_api):
		if _api.has_signal("route_choices_received") and not _api.route_choices_received.is_connected(_on_route_choices_received):
			_api.route_choices_received.connect(_on_route_choices_received)

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
		# Phase 4: APICalls no longer emits domain-level journey signals; refresh snapshot.
		if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
			_convoy_service.refresh_single(convoy_id)

func cancel_journey(convoy_id: String, journey_id: String) -> void:
	if convoy_id == "" or journey_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("cancel_convoy_journey"):
		_api.cancel_convoy_journey(convoy_id, journey_id)
		# Phase 4: APICalls no longer emits domain-level journey signals; refresh snapshot.
		if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
			_convoy_service.refresh_single(convoy_id)

func _on_route_choices_received(routes: Array) -> void:
	var logger := get_node_or_null("/root/Logger")
	if is_instance_valid(logger):
		logger.debug("RouteService: choices received count=%s", routes.size())
	if is_instance_valid(_hub) and _hub.has_signal("route_choices_ready"):
		_hub.route_choices_ready.emit(routes)


func to_models(routes: Array) -> Array:
	var out: Array = []
	for r in routes:
		if r is Dictionary:
			out.append(RouteChoiceModel.new(r))
	return out

