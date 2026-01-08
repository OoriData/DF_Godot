# ConvoyService.gd
extends Node

# Thin domain service for convoy orchestration: refresh and snapshots.

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _store: Node = get_node_or_null("/root/GameStore")

const ConvoyModel = preload("res://Scripts/Data/Models/Convoy.gd")

# This should be the single source of truth for convoy colors.
const PREDEFINED_CONVOY_COLORS: Array[Color] = [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW, Color.CYAN, Color.MAGENTA,
	Color("orange"), Color("purple"), Color("lime"), Color("pink")
]

var _convoy_id_to_color_map: Dictionary = {} # convoy_id_str -> Color
var _last_assigned_color_idx: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(_store) and _store.has_signal("convoys_changed"):
		if not _store.convoys_changed.is_connected(_on_store_convoys_changed):
			_store.convoys_changed.connect(_on_store_convoys_changed)
		# Prime colors from current snapshot.
		_on_store_convoys_changed(get_convoys())


func _on_store_convoys_changed(convoys: Array) -> void:
	# Ensure stable colors for any convoy ids we haven't seen before.
	if PREDEFINED_CONVOY_COLORS.is_empty():
		return
	for convoy in convoys:
		if convoy is Dictionary and convoy.has("convoy_id"):
			var convoy_id_str := str(convoy.get("convoy_id"))
			if convoy_id_str == "":
				continue
			if not _convoy_id_to_color_map.has(convoy_id_str):
				_last_assigned_color_idx = (_last_assigned_color_idx + 1) % PREDEFINED_CONVOY_COLORS.size()
				_convoy_id_to_color_map[convoy_id_str] = PREDEFINED_CONVOY_COLORS[_last_assigned_color_idx]


func get_color_map() -> Dictionary:
	return _convoy_id_to_color_map.duplicate(true)


func get_color_for(convoy_id: String, fallback: Color = Color.GRAY) -> Color:
	if convoy_id == "":
		return fallback
	return _convoy_id_to_color_map.get(convoy_id, fallback)

func refresh_all() -> void:
	# Triggers a transport call; APICalls will route results into GameStore.
	if not is_instance_valid(_api):
		return
	var logger := get_node_or_null("/root/Logger")
	if is_instance_valid(logger) and logger.has_method("info"):
		logger.info("ConvoyService.refresh_all()")
	# Prefer user-specific convoys when we have a user id (avoids 403 on global endpoint)
	var uid: String = ""
	if is_instance_valid(_store) and _store.has_method("get_user"):
		var u: Dictionary = _store.get_user()
		uid = str(u.get("user_id", u.get("id", "")))
	if uid == "":
		var maybe_uid = _api.get("current_user_id")
		if typeof(maybe_uid) == TYPE_STRING:
			uid = String(maybe_uid)
	if is_instance_valid(logger) and logger.has_method("info"):
		logger.info("ConvoyService.refresh_all using uid=%s", uid)
	if uid != "" and _api.has_method("get_user_convoys"):
		_api.get_user_convoys(uid)
	elif _api.has_method("get_all_in_transit_convoys"):
		if is_instance_valid(logger) and logger.has_method("info"):
			logger.info("ConvoyService.refresh_all falling back to ALL_CONVOYS")
		_api.get_all_in_transit_convoys()
	else:
		printerr("ConvoyService: APICalls missing convoy fetch methods.")

func refresh_single(convoy_id: String) -> void:
	if convoy_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("get_convoy_data"):
		if is_instance_valid(get_node_or_null("/root/Logger")):
			get_node("/root/Logger").info("ConvoyService.refresh_single id=%s", convoy_id)
		_api.get_convoy_data(convoy_id)

func get_convoys() -> Array:
	if is_instance_valid(_store) and _store.has_method("get_convoys"):
		return _store.get_convoys()
	return []


func get_convoy_models() -> Array:
	var out: Array = []
	for c in get_convoys():
		if c is Dictionary:
			out.append(ConvoyModel.new(c))
	return out
