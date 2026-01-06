# wiring_smoke_test.gd
# Headless wiring verification for core autoloads and convoy selection flow.
# Usage (macOS):
#   Godot.app/Contents/MacOS/Godot --headless --path . --script res://Scripts/Debug/wiring_smoke_test.gd

extends SceneTree

var _ok: bool = true
var _selection_payload: Variant = null
var _selected_ids_payload: Array = []

var _hub_map_changed_called: bool = false
var _hub_convoys_changed_called: bool = false
var _hub_initial_ready_count: int = 0

var _reconnect_menu_selection_handler: bool = false

func _init() -> void:
	# Let autoloads initialize.
	create_timer(0.1).timeout.connect(_run)


func _run() -> void:
	var root := get_root()
	var hub: Node = root.get_node_or_null("SignalHub")
	var store: Node = root.get_node_or_null("GameStore")
	var api: Node = root.get_node_or_null("APICalls")
	var menu_manager: Node = root.get_node_or_null("MenuManager")
	var selection_svc: Node = root.get_node_or_null("ConvoySelectionService")
	var refresh_scheduler: Node = root.get_node_or_null("RefreshScheduler")
	var convoy_service: Node = root.get_node_or_null("ConvoyService")
	var map_service: Node = root.get_node_or_null("MapService")
	var user_service: Node = root.get_node_or_null("UserService")
	var vendor_service: Node = root.get_node_or_null("VendorService")
	var mechanics_service: Node = root.get_node_or_null("MechanicsService")
	var route_service: Node = root.get_node_or_null("RouteService")
	var warehouse_service: Node = root.get_node_or_null("WarehouseService")

	_require(is_instance_valid(api), "Missing autoload: APICalls")
	_require(is_instance_valid(hub), "Missing autoload: SignalHub")
	_require(is_instance_valid(store), "Missing autoload: GameStore")
	_require(is_instance_valid(refresh_scheduler), "Missing autoload: RefreshScheduler")
	_require(is_instance_valid(convoy_service), "Missing autoload: ConvoyService")
	_require(is_instance_valid(map_service), "Missing autoload: MapService")
	_require(is_instance_valid(user_service), "Missing autoload: UserService")
	_require(is_instance_valid(vendor_service), "Missing autoload: VendorService")
	_require(is_instance_valid(mechanics_service), "Missing autoload: MechanicsService")
	_require(is_instance_valid(route_service), "Missing autoload: RouteService")
	_require(is_instance_valid(warehouse_service), "Missing autoload: WarehouseService")
	_require(is_instance_valid(menu_manager), "Missing autoload: MenuManager")
	_require(is_instance_valid(selection_svc), "Missing autoload: ConvoySelectionService")

	if is_instance_valid(hub):
		_require(hub.has_signal("map_changed"), "SignalHub missing signal: map_changed")
		_require(hub.has_signal("convoys_changed"), "SignalHub missing signal: convoys_changed")
		_require(hub.has_signal("user_changed"), "SignalHub missing signal: user_changed")
		_require(hub.has_signal("initial_data_ready"), "SignalHub missing signal: initial_data_ready")
		_require(hub.has_signal("convoy_selection_requested"), "SignalHub missing signal: convoy_selection_requested")
		_require(hub.has_signal("convoy_selection_changed"), "SignalHub missing signal: convoy_selection_changed")
		_require(hub.has_signal("selected_convoy_ids_changed"), "SignalHub missing signal: selected_convoy_ids_changed")

	if is_instance_valid(store):
		_require(store.has_signal("map_changed"), "GameStore missing signal: map_changed")
		_require(store.has_signal("convoys_changed"), "GameStore missing signal: convoys_changed")
		_require(store.has_signal("user_changed"), "GameStore missing signal: user_changed")
		_require(store.has_method("set_map"), "GameStore missing method: set_map")
		_require(store.has_method("set_convoys"), "GameStore missing method: set_convoys")
		_require(store.has_method("set_user"), "GameStore missing method: set_user")

	# Verify key connections exist.
	if is_instance_valid(hub) and is_instance_valid(refresh_scheduler) and hub.has_signal("initial_data_ready"):
		var c0 := Callable(refresh_scheduler, "_on_initial_ready")
		_require(hub.initial_data_ready.is_connected(c0), "initial_data_ready is not connected to RefreshScheduler")

	if is_instance_valid(hub) and is_instance_valid(selection_svc) and hub.has_signal("convoy_selection_requested"):
		var c := Callable(selection_svc, "_on_hub_convoy_selection_requested")
		_require(hub.convoy_selection_requested.is_connected(c), "convoy_selection_requested is not connected to ConvoySelectionService")

	if is_instance_valid(hub) and is_instance_valid(menu_manager) and hub.has_signal("convoy_selection_changed"):
		var c2 := Callable(menu_manager, "_on_hub_convoy_selection_changed")
		_require(hub.convoy_selection_changed.is_connected(c2), "convoy_selection_changed is not connected to MenuManager")
		# In headless tests, we don't want to instantiate UI scenes (MenuManager requires a registered container host).
		# Temporarily disconnect it for the flow test, but keep the wiring assertion above.
		if hub.convoy_selection_changed.is_connected(c2):
			hub.convoy_selection_changed.disconnect(c2)
			_reconnect_menu_selection_handler = true

	if is_instance_valid(store) and is_instance_valid(menu_manager) and store.has_signal("convoys_changed"):
		var c3 := Callable(menu_manager, "_on_store_convoys_changed")
		_require(store.convoys_changed.is_connected(c3), "GameStore.convoys_changed is not connected to MenuManager")

	# Verify deterministic flow without network:
	# 1) Store emits to Hub (map_changed/convoys_changed) and triggers initial_data_ready once.
	# 2) Selection intent resolves into selection_changed + selected_ids_changed.
	if is_instance_valid(hub) and is_instance_valid(store) and store.has_method("set_convoys") and store.has_method("set_map"):
		# Prevent polling timers from starting during the test.
		if is_instance_valid(refresh_scheduler) and refresh_scheduler.has_method("enable_polling"):
			refresh_scheduler.enable_polling(false)

		_hub_map_changed_called = false
		_hub_convoys_changed_called = false
		_hub_initial_ready_count = 0
		_selection_payload = null
		_selected_ids_payload = []

		if hub.has_signal("map_changed") and not hub.map_changed.is_connected(Callable(self, "_on_hub_map_changed")):
			hub.map_changed.connect(Callable(self, "_on_hub_map_changed"))
		if hub.has_signal("convoys_changed") and not hub.convoys_changed.is_connected(Callable(self, "_on_hub_convoys_changed")):
			hub.convoys_changed.connect(Callable(self, "_on_hub_convoys_changed"))
		if hub.has_signal("initial_data_ready") and not hub.initial_data_ready.is_connected(Callable(self, "_on_hub_initial_ready")):
			hub.initial_data_ready.connect(Callable(self, "_on_hub_initial_ready"))

		if hub.has_signal("convoy_selection_changed") and not hub.convoy_selection_changed.is_connected(Callable(self, "_on_sel_changed")):
			hub.convoy_selection_changed.connect(Callable(self, "_on_sel_changed"))
		if hub.has_signal("selected_convoy_ids_changed") and not hub.selected_convoy_ids_changed.is_connected(Callable(self, "_on_selected_ids_changed")):
			hub.selected_convoy_ids_changed.connect(Callable(self, "_on_selected_ids_changed"))

		store.set_map([[{"terrain_difficulty": 0}]], [])
		store.set_convoys([
			{
				"convoy_id": "1",
				"convoy_name": "Smoke Test Convoy",
				"x": 0,
				"y": 0,
			}
		])
		hub.convoy_selection_requested.emit("1", false)
		create_timer(0.05).timeout.connect(_assert_flows)
		return

	_finish()


func _assert_flows() -> void:
	_require(_hub_map_changed_called, "Store.set_map did not emit SignalHub.map_changed")
	_require(_hub_convoys_changed_called, "Store.set_convoys did not emit SignalHub.convoys_changed")
	_require(_hub_initial_ready_count == 1, "SignalHub.initial_data_ready did not fire exactly once")
	_require(_selection_payload is Dictionary and not (_selection_payload as Dictionary).is_empty(), "convoy_selection_changed did not emit a valid convoy payload")
	if _selection_payload is Dictionary:
		_require(str((_selection_payload as Dictionary).get("convoy_id", "")) == "1", "Selected convoy_id mismatch")
	_require(_selected_ids_payload.size() == 1 and str(_selected_ids_payload[0]) == "1", "selected_convoy_ids_changed did not emit ['1']")
	_finish()


func _finish() -> void:
	# Restore MenuManager handler if we temporarily disconnected it.
	var root := get_root()
	var hub: Node = root.get_node_or_null("SignalHub")
	var menu_manager: Node = root.get_node_or_null("MenuManager")
	if _reconnect_menu_selection_handler and is_instance_valid(hub) and is_instance_valid(menu_manager) and hub.has_signal("convoy_selection_changed"):
		var c2 := Callable(menu_manager, "_on_hub_convoy_selection_changed")
		if not hub.convoy_selection_changed.is_connected(c2):
			hub.convoy_selection_changed.connect(c2)
	_reconnect_menu_selection_handler = false

	if _ok:
		print("[wiring_smoke_test] PASS")
		quit(0)
	else:
		print("[wiring_smoke_test] FAIL")
		quit(1)


func _require(cond: bool, msg: String) -> void:
	if cond:
		return
	_ok = false
	push_error("[wiring_smoke_test] " + msg)


func _on_sel_changed(payload: Variant) -> void:
	_selection_payload = payload


func _on_selected_ids_changed(ids: Array) -> void:
	_selected_ids_payload = ids


func _on_hub_map_changed(_tiles: Array, _settlements: Array) -> void:
	_hub_map_changed_called = true


func _on_hub_convoys_changed(_convoys: Array) -> void:
	_hub_convoys_changed_called = true


func _on_hub_initial_ready() -> void:
	_hub_initial_ready_count += 1
