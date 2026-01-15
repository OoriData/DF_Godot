extends Control
class_name MenuBase

@warning_ignore("unused_signal")
signal back_requested

var convoy_id: String = ""
var extra: Variant = null

func _ensure_store_subscription() -> void:
	var store = get_node_or_null("/root/GameStore")
	if store and store.has_signal("convoys_changed"):
		var cb := Callable(self, "_on_convoys_changed")
		if not store.convoys_changed.is_connected(cb):
			store.convoys_changed.connect(cb)

func initialize_with_data(data_or_id: Variant, extra_arg: Variant = null) -> void:
	"""
	Standardized initializer:
	- If provided a Dictionary (convoy snapshot), sets context and calls _update_ui(convoy) directly.
	- If provided a String (convoy_id), sets context and refreshes from store.
	"""
	_ensure_store_subscription()
	extra = extra_arg
	if data_or_id is Dictionary:
		var convoy: Dictionary = data_or_id
		convoy_id = str(convoy.get("convoy_id", convoy.get("id", "")))
		if not convoy.is_empty():
			_update_ui(convoy)
		else:
			reset_view()
	else:
		convoy_id = str(data_or_id)
		_refresh_from_store()

func set_convoy_context(id: String, extra_arg: Variant = null) -> void:
	_ensure_store_subscription()
	convoy_id = id
	extra = extra_arg
	_refresh_from_store()

func set_extra(extra_arg: Variant) -> void:
	extra = extra_arg

func refresh_now() -> void:
	_ensure_store_subscription()
	_refresh_from_store()

func _ready() -> void:
	_ensure_store_subscription()

func _notification(what: int) -> void:
	# Important for embedded menus inside hidden tabs:
	# they may miss refreshes while hidden, so refresh when shown.
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree() and convoy_id != "":
			_refresh_from_store()

func _on_convoys_changed(_convoys: Array) -> void:
	# Only refresh if this menu is visible and has a convoy context.
	if not is_visible_in_tree() or convoy_id == "":
		return
	_refresh_from_store()

func _refresh_from_store() -> void:
	var store = get_node_or_null("/root/GameStore")
	if store and convoy_id != "":
		var convoy: Dictionary = {}
		if store.has_method("get_convoy_by_id"):
			convoy = store.get_convoy_by_id(convoy_id)
		elif store.has_method("get_convoys"):
			var all = store.get_convoys()
			if all is Array:
				for c in all:
					if c is Dictionary and String(c.get("convoy_id", c.get("id", ""))) == convoy_id:
						convoy = c
						break
		if convoy and not convoy.is_empty():
			_update_ui(convoy)
		else:
			reset_view()

func _exit_tree() -> void:
	# Disconnect to avoid duplicate connections on reopen
	var store = get_node_or_null("/root/GameStore")
	if store and store.has_signal("convoys_changed"):
		var cb := Callable(self, "_on_convoys_changed")
		if store.convoys_changed.is_connected(cb):
			store.convoys_changed.disconnect(cb)

func _update_ui(_convoy: Dictionary) -> void:
	pass

func reset_view() -> void:
	pass
