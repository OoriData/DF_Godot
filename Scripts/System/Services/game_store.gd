# GameStore.gd
extends Node

# Holds snapshots of core domain data. Emits *_changed when updated.

signal map_changed(tiles: Array, settlements: Array)
signal convoys_changed(convoys: Array)
signal user_changed(user: Dictionary)

var _tiles: Array = []
var _settlements: Array = []
var _convoys: Array = []
var _user: Dictionary = {}

var _map_ready: bool = false
var _convoys_ready: bool = false
var _initial_emitted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# Setters emit signals (also emit via SignalHub if present)
func set_map(tiles: Array, settlements: Array) -> void:
	_tiles = tiles if tiles != null else []
	_settlements = settlements if settlements != null else []
	emit_signal("map_changed", _tiles, _settlements)
	var hub := get_node_or_null("/root/SignalHub")
	if is_instance_valid(hub):
		hub.map_changed.emit(_tiles, _settlements)
	_map_ready = true
	_maybe_emit_initial_ready()

func set_convoys(convoys: Array) -> void:
	_convoys = convoys if convoys != null else []
	var logger := get_node_or_null("/root/Logger")
	if is_instance_valid(logger) and logger.has_method("info"):
		logger.info("GameStore.set_convoys count=%s", _convoys.size())
	emit_signal("convoys_changed", _convoys)
	var hub := get_node_or_null("/root/SignalHub")
	if is_instance_valid(hub):
		hub.convoys_changed.emit(_convoys)
	_convoys_ready = true
	_maybe_emit_initial_ready()

func set_user(user: Dictionary) -> void:
	_user = user if user != null else {}
	emit_signal("user_changed", _user)
	var hub := get_node_or_null("/root/SignalHub")
	if is_instance_valid(hub):
		hub.user_changed.emit(_user)

# Getters
func get_tiles() -> Array:
	return _tiles

func get_settlements() -> Array:
	return _settlements

func get_convoys() -> Array:
	return _convoys

func get_user() -> Dictionary:
	return _user

func _maybe_emit_initial_ready() -> void:
	if _initial_emitted:
		return
	if _map_ready and _convoys_ready:
		var hub := get_node_or_null("/root/SignalHub")
		if is_instance_valid(hub):
			hub.initial_data_ready.emit()
		_initial_emitted = true
