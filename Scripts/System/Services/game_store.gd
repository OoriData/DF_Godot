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

func _derive_settlements_from_tiles(tiles: Array) -> Array:
	# Tools.deserialize_map_data returns settlements nested per-tile under tile["settlements"].
	# Many UI paths expect a flat settlements array (and map_changed(tiles, settlements)).
	var out: Array = []
	var seen: Dictionary = {}
	if tiles == null:
		return out
	for row in tiles:
		if not (row is Array):
			continue
		for tile in row:
			if not (tile is Dictionary):
				continue
			var s_any: Variant = (tile as Dictionary).get("settlements", [])
			if not (s_any is Array):
				continue
			for s in (s_any as Array):
				if not (s is Dictionary):
					continue
				var sd := s as Dictionary
				var key := ""
				if sd.has("sett_id"):
					key = "id:" + str(sd.get("sett_id"))
				else:
					key = "xy:" + str(sd.get("x", "?")) + "," + str(sd.get("y", "?")) + ":" + str(sd.get("name", ""))
				if seen.has(key):
					continue
				seen[key] = true
				out.append(sd)
	return out

# Setters emit signals (also emit via SignalHub if present)
func set_map(tiles: Array, settlements: Array) -> void:
	_tiles = tiles if tiles != null else []
	_settlements = settlements if settlements != null else []
	# Back-compat + correctness: if callers pass no settlements (common), derive from tiles.
	if _settlements.is_empty() and not _tiles.is_empty():
		_settlements = _derive_settlements_from_tiles(_tiles)
		var logger := get_node_or_null("/root/Logger")
		if is_instance_valid(logger) and logger.has_method("debug"):
			logger.debug("GameStore.set_map derived settlements=%s", _settlements.size())
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
	var old_user := _user if _user != null else {}
	var old_money := 0
	if old_user.has("money"):
		var om = old_user["money"]
		if typeof(om) in [TYPE_INT, TYPE_FLOAT]:
			old_money = int(om)
		elif typeof(om) == TYPE_STRING and om.is_valid_float():
			old_money = int(float(om))

	_user = user if user != null else {}
	
	# Robustly parse and normalize 'money'
	var new_money := 0
	var raw_money = _user.get("money", 0)
	var money_type = typeof(raw_money)
	
	if money_type in [TYPE_INT, TYPE_FLOAT]:
		new_money = int(raw_money)
	elif money_type == TYPE_STRING:
		if raw_money.is_valid_float():
			new_money = int(float(raw_money))
			# Update the dictionary so downstream consumers get an int
			_user["money"] = new_money
		else:
			print("[GameStore] WARN: User money contains invalid string: ", raw_money)
	
	var logger := get_node_or_null("/root/Logger")
	if is_instance_valid(logger) and logger.has_method("info"):
		logger.info("GameStore.set_user money old=%s new=%s (raw_type=%s val=%s)" % [old_money, new_money, money_type, raw_money])
		
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


func reset_all() -> void:
	# Wipe snapshots and readiness flags (used for logout / switching accounts).
	_tiles = []
	_settlements = []
	_convoys = []
	_user = {}
	_map_ready = false
	_convoys_ready = false
	_initial_emitted = false

	emit_signal("map_changed", _tiles, _settlements)
	emit_signal("convoys_changed", _convoys)
	emit_signal("user_changed", _user)

	var hub := get_node_or_null("/root/SignalHub")
	if is_instance_valid(hub):
		if hub.has_signal("map_changed"):
			hub.map_changed.emit(_tiles, _settlements)
		if hub.has_signal("convoys_changed"):
			hub.convoys_changed.emit(_convoys)
		if hub.has_signal("user_changed"):
			hub.user_changed.emit(_user)

func _maybe_emit_initial_ready() -> void:
	if _initial_emitted:
		return
	if _map_ready and _convoys_ready:
		var hub := get_node_or_null("/root/SignalHub")
		if is_instance_valid(hub):
			hub.initial_data_ready.emit()
		_initial_emitted = true
