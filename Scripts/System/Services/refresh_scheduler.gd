# RefreshScheduler.gd
extends Node

# Controls periodic refreshes (e.g., convoy polling).

@onready var _convoys: Node = get_node_or_null("/root/ConvoyService")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
var _timer: Timer
var _interval_sec: float = 10.0
var _enabled: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_interval_from_config()
	# Start after initial bootstrap so polling doesn't race auth/map.
	if is_instance_valid(_hub):
		_hub.initial_data_ready.connect(_on_initial_ready)
	else:
		# Fallback: start immediately if hub missing
		_start_convoy_polling()

func _on_initial_ready() -> void:
	_start_convoy_polling()

func enable_polling(enable: bool) -> void:
	_enabled = enable
	if _enabled:
		_start_convoy_polling()
	else:
		_stop_convoy_polling()

func _start_convoy_polling() -> void:
	if not _enabled:
		return
	if not is_instance_valid(_convoys):
		_convoys = get_node_or_null("/root/ConvoyService")
	if _timer and is_instance_valid(_timer):
		_timer.queue_free()
	_timer = Timer.new()
	_timer.name = "ConvoyRefreshTimer"
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer.one_shot = false
	_timer.wait_time = max(1.0, _interval_sec)
	add_child(_timer)
	if _timer.timeout.is_connected(_on_convoy_refresh_timeout):
		_timer.timeout.disconnect(_on_convoy_refresh_timeout)
	_timer.timeout.connect(_on_convoy_refresh_timeout)
	_timer.start()
	var logger := get_node_or_null("/root/Logger")
	if is_instance_valid(logger):
		logger.info("RefreshScheduler: convoy polling started every %ss", _interval_sec)

func _stop_convoy_polling() -> void:
	if _timer and is_instance_valid(_timer):
		_timer.stop()
		_timer.queue_free()
		_timer = null
	var logger := get_node_or_null("/root/Logger")
	if is_instance_valid(logger):
		logger.info("RefreshScheduler: convoy polling stopped")

func _on_convoy_refresh_timeout() -> void:
	if is_instance_valid(_convoys) and _convoys.has_method("refresh_all"):
		_convoys.refresh_all()

func _load_interval_from_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://config/app_config.cfg")
	if err != OK:
		return
	# Optional refresh interval in seconds
	var v := cfg.get_value("refresh", "convoys_interval", _interval_sec)
	var t := typeof(v)
	match t:
		TYPE_FLOAT, TYPE_INT:
			_interval_sec = float(v)
		TYPE_STRING:
			var parsed := String(v).to_float()
			if parsed > 0.0:
				_interval_sec = parsed
