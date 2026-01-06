# ConvoySelectionService.gd
extends Node

# Owns the "selection intent -> resolved selection" flow.
# UI emits `SignalHub.convoy_selection_requested(convoy_id, allow_toggle)`.
# This service resolves the convoy payload from `GameStore` snapshots and emits:
# - `SignalHub.convoy_selection_changed(selected_convoy_data)`
# - `SignalHub.selected_convoy_ids_changed([id])`

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
@onready var _mechanics: Node = get_node_or_null("/root/MechanicsService")

var _selected_convoy_id: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(_hub) and _hub.has_signal("convoy_selection_requested"):
		if not _hub.convoy_selection_requested.is_connected(_on_hub_convoy_selection_requested):
			_hub.convoy_selection_requested.connect(_on_hub_convoy_selection_requested)
	if is_instance_valid(_store) and _store.has_signal("convoys_changed"):
		if not _store.convoys_changed.is_connected(_on_store_convoys_changed):
			_store.convoys_changed.connect(_on_store_convoys_changed)


func _on_hub_convoy_selection_requested(convoy_id: String, allow_toggle: bool) -> void:
	select_convoy_by_id(convoy_id, allow_toggle)


func _on_store_convoys_changed(_convoys: Array) -> void:
	# If the currently-selected convoy disappears from snapshots, clear selection.
	if _selected_convoy_id == "":
		return
	var still_exists := false
	for c in _get_convoys_snapshot():
		if c is Dictionary and str((c as Dictionary).get("convoy_id", "")) == _selected_convoy_id:
			still_exists = true
			break
	if not still_exists:
		select_convoy_by_id("", false)


func select_convoy_by_id(convoy_id_to_select: String, _allow_toggle: bool = true) -> void:
	"""
	Central method to change the globally selected convoy by its ID.

	TOGGLE DISABLED: Re-selecting the same convoy ID does nothing.
	To explicitly clear selection, pass an empty string "" as the convoy_id.
	"""
	# Explicit deselect
	if convoy_id_to_select == "":
		if _selected_convoy_id != "":
			_selected_convoy_id = ""
			_emit_selection(null)
		return

	# No-op if already selected
	if _selected_convoy_id == convoy_id_to_select:
		return

	_selected_convoy_id = convoy_id_to_select
	var selected: Variant = get_selected_convoy()
	_emit_selection(selected)
	if selected is Dictionary and not (selected as Dictionary).is_empty():
		# Best-effort warm-up for mechanics preview flows (replaces legacy GDM prefetch).
		if is_instance_valid(_mechanics) and _mechanics.has_method("warm_mechanics_data_for_convoy"):
			_mechanics.warm_mechanics_data_for_convoy(selected)


func get_selected_convoy() -> Variant:
	if _selected_convoy_id == "":
		return null
	for c in _get_convoys_snapshot():
		if c is Dictionary and str((c as Dictionary).get("convoy_id", "")) == _selected_convoy_id:
			return c
	_selected_convoy_id = ""
	return null


func _emit_selection(selected_convoy_data: Variant) -> void:
	if not is_instance_valid(_hub):
		return
	if _hub.has_signal("convoy_selection_changed"):
		_hub.convoy_selection_changed.emit(selected_convoy_data)
	if _hub.has_signal("selected_convoy_ids_changed"):
		if selected_convoy_data is Dictionary and not (selected_convoy_data as Dictionary).is_empty():
			_hub.selected_convoy_ids_changed.emit([_selected_convoy_id])
		else:
			_hub.selected_convoy_ids_changed.emit([])


func _get_convoys_snapshot() -> Array:
	if is_instance_valid(_store) and _store.has_method("get_convoys"):
		return _store.get_convoys()
	return []
