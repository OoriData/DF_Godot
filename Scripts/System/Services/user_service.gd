# UserService.gd
extends Node

# Thin service for user requests and snapshot access.

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")

var _warned_missing_user_id: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Centralize user refresh requests so txns update money even when no UI listens.
	if is_instance_valid(_hub) and _hub.has_signal("user_refresh_requested"):
		var cb := Callable(self, "_on_user_refresh_requested")
		if not _hub.user_refresh_requested.is_connected(cb):
			_hub.user_refresh_requested.connect(cb)

func _on_user_refresh_requested() -> void:
	refresh_user()

func request_user(user_id: String = "") -> void:
	# Back-compat alias used by UI widgets.
	refresh_user(user_id)

func refresh_user(user_id: String = "") -> void:
	var uid := user_id
	# Prefer APICalls current_user_id when available.
	if uid == "" and is_instance_valid(_api):
		var api_uid_any: Variant = _api.get("current_user_id")
		if api_uid_any != null:
			uid = str(api_uid_any)
	# Fallback: use Store user id.
	if uid == "" and is_instance_valid(_store) and _store.has_method("get_user"):
		var u: Dictionary = _store.get_user()
		uid = str(u.get("user_id", u.get("id", "")))
	if uid == "":
		if not _warned_missing_user_id:
			_warned_missing_user_id = true
			print("[UserService] WARN: refresh_user called with no known user id")
		return
	if is_instance_valid(_api):
		if _api.has_method("refresh_user_data"):
			_api.refresh_user_data(uid)
		elif _api.has_method("get_user_data"):
			_api.get_user_data(uid)

func get_user() -> Dictionary:
	if is_instance_valid(_store) and _store.has_method("get_user"):
		return _store.get_user()
	return {}
