extends Node
class_name VendorSelectionManager

static func should_defer_selection(last_selection_change_ms: int, cooldown_ms: int) -> bool:
	if cooldown_ms <= 0:
		return false
	var now_ms = Time.get_ticks_msec()
	return (now_ms - int(last_selection_change_ms)) < int(cooldown_ms)

# Create a debounce timer and connect its timeout to the provided callable.
# Returns the created SceneTreeTimer so callers can track/compare it.
static func schedule_debounce(tree: SceneTree, seconds: float, on_timeout: Callable) -> SceneTreeTimer:
	if not is_instance_valid(tree):
		return null
	var t = tree.create_timer(max(0.0, seconds))
	if on_timeout.is_valid():
		# Connect and bind the timer instance for handlers expecting it.
		t.timeout.connect(on_timeout.bind(t))
	return t

# If the last selection change was recent (within debounce_s), schedule a small defer
# via on_deferred and return true (caller should return early). Otherwise return false.
static func perform_refresh_guard(last_selection_change_ms: int, debounce_s: float, on_deferred: Callable) -> bool:
	var now_ms = Time.get_ticks_msec()
	var threshold_ms = int(max(0.0, debounce_s) * 1000.0)
	if (now_ms - int(last_selection_change_ms)) < threshold_ms:
		# small fixed defer used in the panel code
		if on_deferred.is_valid():
			var tree: SceneTree = Engine.get_main_loop()
			if is_instance_valid(tree):
				var dt = tree.create_timer(0.2)
				dt.timeout.connect(on_deferred)
		return true
	return false

# Start a one-shot watchdog that will call on_timeout with the provided refresh_id after timeout_ms.
static func start_watchdog(tree: SceneTree, refresh_id: int, timeout_ms: int, on_timeout: Callable) -> void:
	if not is_instance_valid(tree) or not on_timeout.is_valid():
		return
	var t = tree.create_timer(float(max(1, timeout_ms)) / 1000.0)
	t.timeout.connect(on_timeout.bind(refresh_id))

# Restore selection in a Tree by cargo_id/vehicle_id or a special key.
# - tree: target Tree
# - item_id: prior id or special key (e.g., "name:...", "res:fuel")
# - on_select: Callable to invoke with the selected agg_data (deferred)
# - matches_fn: Optional Callable(agg_data: Dictionary, key: String) -> bool for custom match logic
static func restore_selection(tree: Tree, item_id, on_select: Callable, matches_fn: Callable = Callable()) -> bool:
	if not is_instance_valid(tree) or tree.get_root() == null:
		if on_select.is_valid():
			on_select.call_deferred(null)
		return false
	var root = tree.get_root()
	var cat = root.get_first_child()
	while cat != null:
		var it = cat.get_first_child()
		while it != null:
			var agg_data = it.get_metadata(0)
			if agg_data and (agg_data is Dictionary) and (agg_data as Dictionary).has("item_data"):
				var idata: Dictionary = agg_data.item_data
				var id = idata.get("cargo_id", idata.get("vehicle_id", null))
				if id != null and str(id) == str(item_id):
					it.select(0)
					if on_select.is_valid():
						on_select.call_deferred(agg_data)
					return true
				elif typeof(item_id) == TYPE_STRING:
					var matched = false
					if matches_fn.is_valid():
						matched = bool(matches_fn.call(agg_data, str(item_id)))
					else:
						matched = _default_matches_restore_key(agg_data, str(item_id))
					if matched:
						it.select(0)
						if on_select.is_valid():
							on_select.call_deferred(agg_data)
						return true
			it = it.get_next()
		cat = cat.get_next()
	# Not found; clear selection via callback with null
	if on_select.is_valid():
		on_select.call_deferred(null)
	return false

static func _default_matches_restore_key(agg_data: Dictionary, key: String) -> bool:
	if not (agg_data is Dictionary) or not (agg_data as Dictionary).has("item_data"):
		return false
	var idata: Dictionary = agg_data.item_data
	if key.begins_with("name:"):
		var nm := str(key.substr(5))
		return str(idata.get("name", "")) == nm
	if key == "res:fuel":
		return bool(idata.get("is_raw_resource", false)) and float(idata.get("fuel", 0.0)) > 0.0
	if key == "res:water":
		return bool(idata.get("is_raw_resource", false)) and float(idata.get("water", 0.0)) > 0.0
	if key == "res:food":
		return bool(idata.get("is_raw_resource", false)) and float(idata.get("food", 0.0)) > 0.0
	return false
