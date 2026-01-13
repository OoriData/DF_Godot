# MenuBase Contract

Purpose: standardize initialization and signals across menus.

Contract
- Signals: `back_requested`
- Method: `initialize_with_data(data_or_id: Variant, extra: Variant = null)` accepts a convoy `Dictionary` or a `String convoy_id`
- Method: `reset_view()` (optional, clears state when data missing)
- Subscriptions: `GameStore.convoys_changed` with guarded connections and visibility checks

Example (pattern)
```gdscript
extends Control
class_name MenuBase
signal back_requested

var convoy_id: String = ""
var extra: Variant = null

func initialize_with_data(data_or_id: Variant, extra_arg: Variant = null) -> void:
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

func _ready() -> void:
	var store = get_node_or_null("/root/GameStore")
	if store and store.has_signal("convoys_changed"):
		var cb := Callable(self, "_on_convoys_changed")
		if not store.convoys_changed.is_connected(cb):
			store.convoys_changed.connect(cb)

func _on_convoys_changed(_convoys: Array) -> void:
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
			for c in store.get_convoys():
				if c is Dictionary and String(c.get("convoy_id", c.get("id", ""))) == convoy_id:
					convoy = c
					break
		if convoy and not convoy.is_empty():
			_update_ui(convoy)
		else:
			reset_view()

func _update_ui(convoy: Dictionary) -> void:
	# Implement in concrete menu
	pass

func reset_view() -> void:
	# Optional: clear UI when convoy missing
	pass

func _exit_tree() -> void:
	var store = get_node_or_null("/root/GameStore")
	if store and store.has_signal("convoys_changed"):
		var cb := Callable(self, "_on_convoys_changed")
		if store.convoys_changed.is_connected(cb):
			store.convoys_changed.disconnect(cb)
```

Notes
- Keep initialization lightweight; avoid deep copies of convoy data.
- Prefer storing identifiers (e.g., `convoy_id`) and reading snapshots from `GameStore`.
- Use services (`VendorService`, `RouteService`, etc.) for backend actions and event subscriptions.
- Implement `_update_ui(convoy)` as a minimal redraw; avoid repopulating expensive trees on store changes to preserve selection.
