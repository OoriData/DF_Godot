# UserService.gd
extends Node

# Thin service for user requests and snapshot access.

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _store: Node = get_node_or_null("/root/GameStore")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func refresh_user(user_id: String = "") -> void:
	var uid := user_id
	if uid == "" and is_instance_valid(_api):
		uid = String(_api.current_user_id)
	if uid == "":
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
