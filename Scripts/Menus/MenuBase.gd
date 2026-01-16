extends Control
class_name MenuBase

@warning_ignore("unused_signal")
signal back_requested

var convoy_id: String = ""
var extra: Variant = null
var _last_convoy_data: Dictionary = {}

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
			_last_convoy_data = convoy.duplicate(true)
			_update_ui(convoy)
		else:
			_last_convoy_data = {}
			reset_view()
	else:
		convoy_id = str(data_or_id)
		_last_convoy_data = {}
		_refresh_from_store()

func set_convoy_context(id: String, extra_arg: Variant = null) -> void:
	_ensure_store_subscription()
	convoy_id = id
	extra = extra_arg
	_last_convoy_data = {}
	_refresh_from_store()

func set_extra(extra_arg: Variant) -> void:
	extra = extra_arg

func refresh_now() -> void:
	_ensure_store_subscription()
	_last_convoy_data = {}
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
	print("[MenuBase] _on_convoys_changed triggered for: ", name, " (convoy_id: ", convoy_id, ")")
	_refresh_from_store()

func _refresh_from_store() -> void:
	print("[MenuBase] _refresh_from_store executing for: ", name)
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
			if _has_relevant_changes(_last_convoy_data, convoy):
				_last_convoy_data = convoy.duplicate(true)
				print("[MenuBase] Found relevant changes, calling _update_ui for: ", name)
				_update_ui(convoy)
			else:
				print("[MenuBase] No relevant changes, skipping update for: ", name)
		else:
			_last_convoy_data = {}
			print("[MenuBase] Convoy data empty/missing, calling reset_view for: ", name)
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

func _has_relevant_changes(old_data: Dictionary, new_data: Dictionary) -> bool:
	return old_data.hash() != new_data.hash()
