extends Control

signal back_requested

@onready var title_label: Label = $MainVBox/TopBarHBox/TitleLabel
@onready var buy_button: Button = $MainVBox/TopBarHBox/BuyButton
@onready var back_button: Button = $MainVBox/BackButton
@onready var info_label: Label = $MainVBox/Body/InfoLabel
@onready var owned_tabs: TabContainer = $MainVBox/Body/OwnedTabs
@onready var summary_label: Label = $MainVBox/Body/OwnedTabs/Overview/SummaryLabel
@onready var expand_cargo_btn: Button = $MainVBox/Body/OwnedTabs/Overview/ExpandCargoHBox/ExpandCargoBtn
@onready var expand_vehicle_btn: Button = $MainVBox/Body/OwnedTabs/Overview/ExpandVehicleHBox/ExpandVehicleBtn
@onready var cargo_store_dd: OptionButton = $MainVBox/Body/OwnedTabs/Cargo/CargoStoreHBox/CargoStoreDropdown
@onready var cargo_qty_store: SpinBox = $MainVBox/Body/OwnedTabs/Cargo/CargoStoreHBox/CargoQtyStore
@onready var store_cargo_btn: Button = $MainVBox/Body/OwnedTabs/Cargo/CargoStoreHBox/StoreCargoBtn
@onready var cargo_retrieve_dd: OptionButton = $MainVBox/Body/OwnedTabs/Cargo/CargoRetrieveHBox/CargoRetrieveDropdown
@onready var cargo_retrieve_vehicle_dd: OptionButton = $MainVBox/Body/OwnedTabs/Cargo/CargoRetrieveHBox/CargoRetrieveVehicleDropdown
@onready var cargo_qty_retrieve: SpinBox = $MainVBox/Body/OwnedTabs/Cargo/CargoRetrieveHBox/CargoQtyRetrieve
@onready var retrieve_cargo_btn: Button = $MainVBox/Body/OwnedTabs/Cargo/CargoRetrieveHBox/RetrieveCargoBtn
@onready var cargo_usage_label: Label = $MainVBox/Body/OwnedTabs/Cargo/CargoUsageLabel
@onready var cargo_grid: GridContainer = $MainVBox/Body/OwnedTabs/Cargo/CargoInventoryPanel/CargoGridScroll/CargoGrid
@onready var vehicle_store_dd: OptionButton = $MainVBox/Body/OwnedTabs/Vehicles/VehicleStoreHBox/VehicleStoreDropdown
@onready var store_vehicle_btn: Button = $MainVBox/Body/OwnedTabs/Vehicles/VehicleStoreHBox/StoreVehicleBtn
@onready var vehicle_retrieve_dd: OptionButton = $MainVBox/Body/OwnedTabs/Vehicles/VehicleRetrieveHBox/VehicleRetrieveDropdown
@onready var retrieve_vehicle_btn: Button = $MainVBox/Body/OwnedTabs/Vehicles/VehicleRetrieveHBox/RetrieveVehicleBtn
@onready var spawn_vehicle_dd: OptionButton = $MainVBox/Body/OwnedTabs/Vehicles/SpawnHBox/SpawnVehicleDropdown
@onready var spawn_name_input: LineEdit = $MainVBox/Body/OwnedTabs/Vehicles/SpawnHBox/SpawnNameInput
@onready var spawn_convoy_btn: Button = $MainVBox/Body/OwnedTabs/Vehicles/SpawnHBox/SpawnConvoyBtn
@onready var vehicle_grid: GridContainer = $MainVBox/Body/OwnedTabs/Vehicles/VehicleInventoryPanel/VehicleGridScroll/VehicleGrid
@onready var expand_cargo_label: Label = $MainVBox/Body/OwnedTabs/Overview/ExpandCargoHBox/ExpandCargoLabel
@onready var expand_vehicle_label: Label = $MainVBox/Body/OwnedTabs/Overview/ExpandVehicleHBox/ExpandVehicleLabel
@onready var overview_cargo_bar: ProgressBar = $MainVBox/Body/OwnedTabs/Overview/OverviewCargoHBox/OverviewCargoBar
@onready var overview_vehicle_bar: ProgressBar = $MainVBox/Body/OwnedTabs/Overview/OverviewVehicleHBox/OverviewVehicleBar

var _convoy_data: Dictionary
var _settlement: Dictionary
var _warehouse: Dictionary
var gdm: Node
var api: Node
var _is_loading: bool = false
var _pending_action_refresh: bool = false


# Track last-seen dropdown contents to avoid reshuffling
var _last_cargo_store_ids: Array[String] = []
var _last_cargo_retrieve_ids: Array[String] = []
var _last_vehicle_store_ids: Array[String] = []
var _last_vehicle_retrieve_ids: Array[String] = []
var _last_spawn_vehicle_ids: Array[String] = []

const WAREHOUSE_PRICES := {
	"dome": 5000000,
	"city-state": 4000000,
	"city": 3000000,
	"town": 1000000,
	"village": 500000,
	"military_base": null,
}

const WAREHOUSE_UPGRADE_PRICES := {
	"dome": 250000,
	"city-state": 200000,
	"city": 150000,
	"town": 75000,
	"village": 50000,
	"military_base": null,
}

func _ready():
	print("[WarehouseMenu] _ready()")
	gdm = get_node_or_null("/root/GameDataManager")
	api = get_node_or_null("/root/APICalls")
	if is_instance_valid(back_button):
		back_button.pressed.connect(func(): emit_signal("back_requested"))
	if is_instance_valid(buy_button):
		buy_button.pressed.connect(_on_buy_pressed)
	# Selection change hooks to enforce quantity limits
	if is_instance_valid(cargo_store_dd):
		cargo_store_dd.item_selected.connect(func(_idx): _update_store_qty_limit())
	if is_instance_valid(cargo_retrieve_dd):
		cargo_retrieve_dd.item_selected.connect(func(_idx): _update_retrieve_qty_limit())
	# Hook API signals
	if is_instance_valid(api):
		if api.has_signal("warehouse_created") and not api.warehouse_created.is_connected(_on_api_warehouse_created):
			api.warehouse_created.connect(_on_api_warehouse_created)
		if api.has_signal("warehouse_received") and not api.warehouse_received.is_connected(_on_api_warehouse_received):
			api.warehouse_received.connect(_on_api_warehouse_received)
		if api.has_signal("fetch_error") and not api.fetch_error.is_connected(_on_api_error):
			api.fetch_error.connect(_on_api_error)
		# New action signals
		if api.has_signal("warehouse_expanded") and not api.warehouse_expanded.is_connected(_on_api_warehouse_action):
			api.warehouse_expanded.connect(_on_api_warehouse_action)
		if api.has_signal("warehouse_cargo_stored") and not api.warehouse_cargo_stored.is_connected(_on_api_warehouse_action):
			api.warehouse_cargo_stored.connect(_on_api_warehouse_action)
		if api.has_signal("warehouse_cargo_retrieved") and not api.warehouse_cargo_retrieved.is_connected(_on_api_warehouse_action):
			api.warehouse_cargo_retrieved.connect(_on_api_warehouse_action)
		if api.has_signal("warehouse_vehicle_stored") and not api.warehouse_vehicle_stored.is_connected(_on_api_warehouse_action):
			api.warehouse_vehicle_stored.connect(_on_api_warehouse_action)
		if api.has_signal("warehouse_vehicle_retrieved") and not api.warehouse_vehicle_retrieved.is_connected(_on_api_warehouse_action):
			api.warehouse_vehicle_retrieved.connect(_on_api_warehouse_action)
		if api.has_signal("warehouse_convoy_spawned") and not api.warehouse_convoy_spawned.is_connected(_on_api_warehouse_action):
			api.warehouse_convoy_spawned.connect(_on_api_warehouse_action)

	# Wire UI buttons
	if is_instance_valid(expand_cargo_btn):
		expand_cargo_btn.pressed.connect(_on_expand_cargo)
	if is_instance_valid(expand_vehicle_btn):
		expand_vehicle_btn.pressed.connect(_on_expand_vehicle)
	if is_instance_valid(store_cargo_btn):
		store_cargo_btn.pressed.connect(_on_store_cargo)
	if is_instance_valid(retrieve_cargo_btn):
		retrieve_cargo_btn.pressed.connect(_on_retrieve_cargo)
	if is_instance_valid(store_vehicle_btn):
		store_vehicle_btn.pressed.connect(_on_store_vehicle)
	if is_instance_valid(retrieve_vehicle_btn):
		retrieve_vehicle_btn.pressed.connect(_on_retrieve_vehicle)
	if is_instance_valid(spawn_convoy_btn):
		spawn_convoy_btn.pressed.connect(_on_spawn_convoy)
		print("[WarehouseMenu][Debug] Connected spawn_convoy_btn pressed signal path=", spawn_convoy_btn.get_path())
	_update_ui()

func initialize_with_data(data: Dictionary) -> void:
	# Guard: avoid expensive re-initialization if convoy and settlement unchanged
	var incoming_cid := str(data.get("convoy_id", ""))
	var existing_cid := str(_convoy_data.get("convoy_id", "")) if (_convoy_data is Dictionary) else ""
	var incoming_sett: Variant = data.get("settlement", null)
	var incoming_sett_id: String = ""
	if typeof(incoming_sett) == TYPE_DICTIONARY:
		incoming_sett_id = str(incoming_sett.get("sett_id", ""))
	var existing_sett_id := str(_settlement.get("sett_id", "")) if (_settlement is Dictionary) else ""
	if incoming_cid != "" and existing_cid == incoming_cid and incoming_sett_id != "" and existing_sett_id == incoming_sett_id:
		# Still refresh dropdowns lightly (convoy cargo may have changed), but skip heavy logging spam
		_populate_dropdowns()
		return
	_convoy_data = data.duplicate(true)
	var incoming_settlement = data.get("settlement", null)
	if typeof(incoming_settlement) == TYPE_DICTIONARY and not (incoming_settlement as Dictionary).is_empty():
		_settlement = (incoming_settlement as Dictionary).duplicate(true)
	else:
		# Try to resolve from settlement_name or coordinates; if unresolved, keep previous _settlement
		var resolved := _resolve_settlement_from_data(_convoy_data)
		if not resolved.is_empty():
			_settlement = resolved
	# Don't nuke existing settlement if nothing resolved
	print("[WarehouseMenu] initialize_with_data name=", String(_settlement.get("name", _convoy_data.get("settlement_name", ""))), " sett_type_resolved=", _get_settlement_type())
	_update_ui()
	_try_load_warehouse_for_settlement()
	_populate_dropdowns() # initial (may be empty until data arrives)

func _update_ui():
	var sett_name := String(_settlement.get("name", _convoy_data.get("settlement_name", "")))
	if is_instance_valid(title_label):
		if sett_name != "":
			title_label.text = "Warehouse — %s" % sett_name
		else:
			title_label.text = "Warehouse"
	# Basic state: if we have a warehouse object, show summary; else show buy CTA
	if _warehouse is Dictionary and not _warehouse.is_empty():
		if is_instance_valid(buy_button):
			buy_button.visible = false
		# Show the tabs and fill the summary label
		if is_instance_valid(owned_tabs):
			owned_tabs.visible = true
		if is_instance_valid(summary_label):
			summary_label.text = _format_warehouse_summary(_warehouse)
		# Now that we have warehouse details, repopulate dropdowns that depend on it
		_populate_dropdowns()
		_update_expand_buttons()
		_update_upgrade_labels()
		_update_cargo_usage_label()
		_update_overview_bars()
		_render_cargo_grid()
		_render_vehicle_grid()
		print("[WarehouseMenu] Owned state. sett_type=", _get_settlement_type())
		if is_instance_valid(info_label):
			info_label.text = ""
		_update_upgrade_labels()
	else:
		if is_instance_valid(buy_button):
			buy_button.visible = not _is_loading
		if is_instance_valid(owned_tabs):
			owned_tabs.visible = false
		if is_instance_valid(info_label):
			if _is_loading:
				info_label.text = "Loading warehouse..."
			else:
				var price := _get_warehouse_price()
				var funds := _get_user_money()
				var buy_available := _is_buy_available()
				var price_text := _format_money(price) if price > 0 else ("N/A" if not buy_available else "TBD")
				var funds_text := _format_money(funds)
				info_label.text = "No warehouse here yet.\nPrice: %s\nYour funds: %s" % [price_text, funds_text]
				print("[WarehouseMenu] No warehouse. sett_type=", _get_settlement_type(), " price=", price, " buy_available=", buy_available)
				# Update Buy button text and enabled state based on availability and affordability
				if is_instance_valid(buy_button):
					if not buy_available:
						buy_button.text = "Buy"
						buy_button.disabled = true
						buy_button.tooltip_text = "Warehouses are not available in this settlement."
					elif price > 0:
						buy_button.text = "Buy (%s)" % price_text
						var can_afford := funds + 0.0001 >= float(price)
						buy_button.disabled = not can_afford
						var tip := "Price: %s\nYour funds: %s" % [price_text, funds_text]
						if not can_afford:
							tip += "\nInsufficient funds."
						buy_button.tooltip_text = tip
					else:
						buy_button.text = "Buy"
						buy_button.disabled = false
						buy_button.tooltip_text = ""

func _format_warehouse_summary(_w: Dictionary) -> String:
	# Overview now minimal; details moved elsewhere
	var parts: Array[String] = []
	parts.append("Warehouse")
	return "\n".join(parts)

func _on_buy_pressed():
	if not is_instance_valid(api):
		push_warning("API node not available")
		return
	# Need settlement id from provided settlement snapshot
	var sett_id := String(_settlement.get("sett_id", ""))
	if sett_id == "" and is_instance_valid(gdm):
		# Fallback: try to resolve by settlement name from provided data
		var name_guess := String(_settlement.get("name", _convoy_data.get("settlement_name", "")))
		if name_guess != "" and gdm.has_method("get_all_settlements_data"):
			var all_setts: Array = gdm.get_all_settlements_data()
			for s in all_setts:
				if typeof(s) == TYPE_DICTIONARY and String(s.get("name", "")) == name_guess:
					sett_id = String(s.get("sett_id", ""))
					break
	if sett_id == "":
		if is_instance_valid(info_label):
			info_label.text = "No settlement selected."
		return
	# Affordability check (client-side UX only; server remains authoritative)
	var price := _get_warehouse_price()
	var funds := _get_user_money()
	if price > 0 and funds + 0.0001 < float(price):
		if is_instance_valid(info_label):
			info_label.text = "Insufficient funds to buy warehouse. Price: %s, You have: %s" % [_format_money(price), _format_money(funds)]
		if is_instance_valid(buy_button):
			buy_button.disabled = true
		return
	if is_instance_valid(info_label):
		info_label.text = "Purchasing warehouse..."
	if is_instance_valid(buy_button):
		buy_button.disabled = true
	api.warehouse_new(sett_id)

func _on_api_warehouse_created(result: Variant) -> void:
	# Backend returns the new UUID; refresh user data and show confirmation
	if is_instance_valid(buy_button):
		buy_button.disabled = false
	var wid := ""
	if typeof(result) == TYPE_DICTIONARY:
		wid = String((result as Dictionary).get("warehouse_id", ""))
	else:
		wid = String(result)
		wid = wid.strip_edges()
		# If backend returned a JSON string like "uuid", strip quotes
		if wid.length() >= 2 and wid[0] == '"' and wid[wid.length() - 1] == '"':
			wid = wid.substr(1, wid.length() - 2)
	if wid == "":
		if is_instance_valid(info_label):
			info_label.text = "Warehouse created."
	else:
		if is_instance_valid(info_label):
			info_label.text = "Warehouse created: %s" % wid
		# Immediately fetch details
		if is_instance_valid(api):
			_is_loading = true
			_update_ui()
			api.get_warehouse(wid)
	if is_instance_valid(gdm) and gdm.has_method("request_user_data_refresh"):
		gdm.request_user_data_refresh()

func _on_api_warehouse_received(warehouse_data: Dictionary) -> void:
	_warehouse = warehouse_data.duplicate(true)
	_is_loading = false
	_pending_action_refresh = false
	# Re-enable spawn button after any warehouse update (covers convoy spawn completion)
	if is_instance_valid(spawn_convoy_btn):
		spawn_convoy_btn.disabled = false
	# Debug: print warehouse keys and common inventory fields
	var keys: Array = []
	for k in _warehouse.keys():
		keys.append(str(k))
	print("[WarehouseMenu][Debug] Warehouse keys=", ", ".join(PackedStringArray(keys)))
	var cargo_inv: Variant = _warehouse.get("cargo_inventory", null)
	var all_cargo: Variant = _warehouse.get("all_cargo", null)
	var veh_inv: Variant = _warehouse.get("vehicle_inventory", null)
	var cargo_inv_size: int = (cargo_inv.size() if typeof(cargo_inv) == TYPE_ARRAY else -1)
	var all_cargo_size: int = (all_cargo.size() if typeof(all_cargo) == TYPE_ARRAY else -1)
	var veh_inv_size: int = (veh_inv.size() if typeof(veh_inv) == TYPE_ARRAY else -1)
	print("[WarehouseMenu][Debug] cargo_inventory type=", typeof(cargo_inv), " size=", cargo_inv_size)
	print("[WarehouseMenu][Debug] all_cargo type=", typeof(all_cargo), " size=", all_cargo_size)
	print("[WarehouseMenu][Debug] vehicle_inventory type=", typeof(veh_inv), " size=", veh_inv_size)
	_update_ui()
	# Optionally refresh user/convoys if needed
	if is_instance_valid(gdm):
		if gdm.has_method("request_user_data_refresh"):
			gdm.request_user_data_refresh()
		if gdm.has_method("request_convoy_data_refresh"):
			gdm.request_convoy_data_refresh()
	# Update dropdowns since we have fresh warehouse data
	_populate_dropdowns()

func _on_api_error(msg: String) -> void:
	# Only handle if this menu is visible; otherwise ignore
	if not is_inside_tree():
		return
	if is_instance_valid(buy_button):
		buy_button.disabled = false
	# Keep message concise
	if is_instance_valid(info_label):
		info_label.text = str(msg)

func _on_api_warehouse_action(_result: Variant) -> void:
	# After any action, reload warehouse and refresh UI
	print("[WarehouseMenu][ActionComplete] result_type=", typeof(_result))
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	if wid == "" or not is_instance_valid(api):
		return
	_is_loading = true
	_update_ui()
	api.get_warehouse(wid)

# Schedule a one-shot fallback refresh in case signals are delayed or missed
func _schedule_refresh_fallback() -> void:
	var timer := get_tree().create_timer(2.0)
	if timer and timer.timeout and not timer.timeout.is_connected(_on_refresh_fallback_timeout):
		timer.timeout.connect(_on_refresh_fallback_timeout)

func _on_refresh_fallback_timeout() -> void:
	if not _pending_action_refresh:
		return
	_refresh_warehouse()

func _refresh_warehouse() -> void:
	if not is_instance_valid(api):
		return
	var wid := ""
	if _warehouse is Dictionary and _warehouse.has("warehouse_id"):
		wid = str(_warehouse.get("warehouse_id", ""))
	if wid != "":
		_is_loading = true
		_update_ui()
		api.get_warehouse(wid)
	else:
		_try_load_warehouse_for_settlement()

# --- UI action handlers ---
func _on_expand_cargo():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		print("[WarehouseMenu][ExpandCargo] Blocked: warehouse not loaded")
		if is_instance_valid(info_label):
			info_label.text = "Cannot upgrade: warehouse not loaded yet."
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var amt := 1
	var per_unit := _get_upgrade_price_per_unit()
	if per_unit <= 0:
		var stype := _get_settlement_type()
		print("[WarehouseMenu][ExpandCargo] Blocked: upgrades not available at settlement_type=", stype)
		if is_instance_valid(info_label):
			info_label.text = "Upgrades not available at this settlement."
		return
	if wid != "" and is_instance_valid(api):
		info_label.text = "Expanding cargo..."
		api.warehouse_expand({"warehouse_id": wid, "expand_type": "cargo", "amount": amt})
	else:
		print("[WarehouseMenu][ExpandCargo] Blocked: invalid state wid=", wid, " api_valid=", is_instance_valid(api))

func _on_expand_vehicle():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		print("[WarehouseMenu][ExpandVehicle] Blocked: warehouse not loaded")
		if is_instance_valid(info_label):
			info_label.text = "Cannot upgrade: warehouse not loaded yet."
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var amt := 1
	var per_unit := _get_upgrade_price_per_unit()
	if per_unit <= 0:
		var stype := _get_settlement_type()
		print("[WarehouseMenu][ExpandVehicle] Blocked: upgrades not available at settlement_type=", stype)
		if is_instance_valid(info_label):
			info_label.text = "Upgrades not available at this settlement."
		return
	if wid != "" and is_instance_valid(api):
		info_label.text = "Expanding vehicle slots..."
		api.warehouse_expand({"warehouse_id": wid, "expand_type": "vehicle", "amount": amt})
	else:
		print("[WarehouseMenu][ExpandVehicle] Blocked: invalid state wid=", wid, " api_valid=", is_instance_valid(api))

func _on_store_cargo():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cid := str(_convoy_data.get("convoy_id", ""))
	var cargo_id := _get_selected_meta(cargo_store_dd)
	var qty := int(cargo_qty_store.value) if is_instance_valid(cargo_qty_store) else 0
	if wid != "" and cid != "" and cargo_id != "" and qty > 0 and is_instance_valid(api):
		info_label.text = "Storing cargo..."
		_pending_action_refresh = true
		_schedule_refresh_fallback()
		api.warehouse_cargo_store({"warehouse_id": wid, "convoy_id": cid, "cargo_id": cargo_id, "quantity": qty})

func _on_retrieve_cargo():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cid := str(_convoy_data.get("convoy_id", ""))
	var cargo_id := _get_selected_meta(cargo_retrieve_dd)
	# pick vehicle to receive
	var recv_vid := _get_selected_meta(cargo_retrieve_vehicle_dd)
	var qty := int(cargo_qty_retrieve.value) if is_instance_valid(cargo_qty_retrieve) else 0
	if wid != "" and cid != "" and cargo_id != "" and qty > 0 and is_instance_valid(api):
		info_label.text = "Retrieving cargo..."
		var payload := {"warehouse_id": wid, "convoy_id": cid, "cargo_id": cargo_id, "quantity": qty}
		if recv_vid != "":
			payload["vehicle_id"] = recv_vid
		_pending_action_refresh = true
		_schedule_refresh_fallback()
		api.warehouse_cargo_retrieve(payload)

func _on_store_vehicle():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cid := str(_convoy_data.get("convoy_id", ""))
	var vid := _get_selected_meta(vehicle_store_dd)
	if wid != "" and cid != "" and vid != "" and is_instance_valid(api):
		info_label.text = "Storing vehicle..."
		api.warehouse_vehicle_store({"warehouse_id": wid, "convoy_id": cid, "vehicle_id": vid})

func _on_retrieve_vehicle():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cid := str(_convoy_data.get("convoy_id", ""))
	var vid := _get_selected_meta(vehicle_retrieve_dd)
	if wid != "" and cid != "" and vid != "" and is_instance_valid(api):
		info_label.text = "Retrieving vehicle..."
		api.warehouse_vehicle_retrieve({"warehouse_id": wid, "convoy_id": cid, "vehicle_id": vid})

func _on_spawn_convoy():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cname := spawn_name_input.text if is_instance_valid(spawn_name_input) else ""
	if cname == "":
		cname = "New Convoy"
	var spawn_vid := _get_selected_meta(spawn_vehicle_dd)
	# Detailed diagnostics
	print("[WarehouseMenu][SpawnConvoy] Attempt wid=", wid, " spawn_vid=", spawn_vid, " name=", cname, " api_valid=", is_instance_valid(api))
	if wid != "" and spawn_vid != "" and is_instance_valid(api):
		if is_instance_valid(info_label):
			info_label.text = "Spawning convoy..."
		# Temporarily disable button to prevent double clicks
		if is_instance_valid(spawn_convoy_btn):
			spawn_convoy_btn.disabled = true
		_pending_action_refresh = true
		_schedule_refresh_fallback()
		# API spec requires 'new_convoy_name'; send both for backward compatibility
		api.warehouse_convoy_spawn({
			"warehouse_id": wid,
			"vehicle_id": spawn_vid,
			"new_convoy_name": cname,
			"name": cname # legacy / fallback if server still expects 'name'
		})
	else:
		var abort_reason := ""
		if wid == "":
			abort_reason = "missing_warehouse_id"
		elif spawn_vid == "":
			abort_reason = "missing_vehicle_id"
		elif not is_instance_valid(api):
			abort_reason = "api_unavailable"
		else:
			abort_reason = "unknown"
		if is_instance_valid(info_label):
			match abort_reason:
				"missing_warehouse_id": info_label.text = "No warehouse ID available (reload)."
				"missing_vehicle_id": info_label.text = "Select a stored vehicle first."
				"api_unavailable": info_label.text = "Cannot spawn convoy (API unavailable)."
				_: info_label.text = "Cannot spawn convoy (unknown issue)."
		print("[WarehouseMenu][SpawnConvoy][Abort] reason=", abort_reason, " wid=", wid, " spawn_vid=", spawn_vid, " name=", cname)

func _try_load_warehouse_for_settlement() -> void:
	if not is_instance_valid(gdm):
		return
	var sett_id := String(_settlement.get("sett_id", ""))
	if sett_id == "":
		return
	var user: Dictionary = {}
	if is_instance_valid(gdm) and gdm.has_method("get_current_user_data"):
		user = gdm.get_current_user_data()
	var warehouses: Array = []
	if typeof(user) == TYPE_DICTIONARY:
		warehouses = user.get("warehouses", [])
	var local_warehouse: Dictionary = {}
	for w in warehouses:
		if typeof(w) == TYPE_DICTIONARY and String(w.get("sett_id", "")) == sett_id:
			local_warehouse = w
			break
	if not local_warehouse.is_empty():
		var wid := String(local_warehouse.get("warehouse_id", ""))
		if wid != "" and is_instance_valid(api):
			_is_loading = true
			_update_ui()
			api.get_warehouse(wid)

func _get_warehouse_price() -> int:
	var stype := _get_settlement_type()
	if WAREHOUSE_PRICES.has(stype):
		var v = WAREHOUSE_PRICES[stype]
		if v == null:
			return 0
		return int(v)
	# Unknown types: return 0 to indicate no client-side price (server may decide)
	return 0

func _is_buy_available() -> bool:
	var stype := _get_settlement_type()
	if WAREHOUSE_PRICES.has(stype):
		return WAREHOUSE_PRICES[stype] != null
	return true

func _get_upgrade_price_per_unit() -> int:
	# Prefer server-provided price when available
	if _warehouse is Dictionary and _warehouse.has("expansion_price") and _warehouse.get("expansion_price") != null:
		return int(_warehouse.get("expansion_price"))
	var stype := _get_settlement_type()
	if WAREHOUSE_UPGRADE_PRICES.has(stype):
		var v = WAREHOUSE_UPGRADE_PRICES[stype]
		if v == null:
			return 0
		return int(v)
	return 0

func _get_settlement_type() -> String:
	# Try direct type first
	var stype := ""
	if _settlement and _settlement.has("sett_type"):
		stype = String(_settlement.get("sett_type", "")).to_lower()
	if stype != "":
		return _normalize_settlement_type(stype)
	# Try resolve by sett_id
	if _settlement and _settlement.has("sett_id") and is_instance_valid(gdm) and gdm.has_method("get_all_settlements_data"):
		var sid := String(_settlement.get("sett_id", ""))
		if sid != "":
			for s in gdm.get_all_settlements_data():
				if typeof(s) == TYPE_DICTIONARY and String(s.get("sett_id", "")) == sid:
					return _normalize_settlement_type(String(s.get("sett_type", "")).to_lower())
	# Try resolve by name
	if _settlement and _settlement.has("name") and is_instance_valid(gdm) and gdm.has_method("get_all_settlements_data"):
		var sname := String(_settlement.get("name", ""))
		if sname != "":
			for s2 in gdm.get_all_settlements_data():
				if typeof(s2) == TYPE_DICTIONARY and String(s2.get("name", "")) == sname:
					return _normalize_settlement_type(String(s2.get("sett_type", "")).to_lower())
	# Fallback: try convoy_data settlement_name or coords
	if _convoy_data:
		var from_convoy := _resolve_settlement_from_data(_convoy_data)
		if not from_convoy.is_empty():
			_settlement = from_convoy # cache it for later
			if from_convoy.has("sett_type"):
				return _normalize_settlement_type(String(from_convoy.get("sett_type", "")).to_lower())
			# else if only name/id, try again via lookups
			if from_convoy.has("sett_id") and is_instance_valid(gdm) and gdm.has_method("get_all_settlements_data"):
				var sid2 := String(from_convoy.get("sett_id", ""))
				for s3 in gdm.get_all_settlements_data():
					if typeof(s3) == TYPE_DICTIONARY and String(s3.get("sett_id", "")) == sid2:
						return _normalize_settlement_type(String(s3.get("sett_type", "")).to_lower())
			if from_convoy.has("name") and is_instance_valid(gdm) and gdm.has_method("get_all_settlements_data"):
				var sname2 := String(from_convoy.get("name", ""))
				for s4 in gdm.get_all_settlements_data():
					if typeof(s4) == TYPE_DICTIONARY and String(s4.get("name", "")) == sname2:
						return _normalize_settlement_type(String(s4.get("sett_type", "")).to_lower())
	print("[WarehouseMenu][SettlType] Unable to resolve settlement type. settlement=", _settlement)
	return ""

func _normalize_settlement_type(t: String) -> String:
	var s := t.strip_edges(true, true).to_lower()
	# Normalize separators
	s = s.replace("_", "-")
	s = s.replace(" ", "-")
	# Collapse common variants
	if s == "citystate" or s == "city-state" or s == "city-state-":
		s = "city-state"
	elif s == "city_state":
		s = "city-state"
	elif s == "military-base" or s == "military base" or s == "militarybase":
		s = "military_base" # our pricing map uses underscore here
	return s

func _resolve_settlement_from_data(d: Dictionary) -> Dictionary:
	if not is_instance_valid(gdm):
		return {}
	var result: Dictionary = {}
	# Prefer explicit settlement_name on convoy payload
	if d.has("settlement_name") and String(d.get("settlement_name", "")) != "":
		var sname := String(d.get("settlement_name"))
		if gdm.has_method("get_all_settlements_data"):
			for s in gdm.get_all_settlements_data():
				if typeof(s) == TYPE_DICTIONARY and String(s.get("name", "")) == sname:
					result = s.duplicate(true)
					break
		# If we found by name, return immediately
		if not result.is_empty():
			return result
	# Fallback by coordinates if available
	var sx := int(roundf(float(d.get("x", -999999.0))))
	var sy := int(roundf(float(d.get("y", -999999.0))))
	if gdm.has_method("get_settlement_name_from_coords"):
		var name_at := String(gdm.get_settlement_name_from_coords(sx, sy))
		if name_at != "" and gdm.has_method("get_all_settlements_data"):
			for s2 in gdm.get_all_settlements_data():
				if typeof(s2) == TYPE_DICTIONARY and String(s2.get("name", "")) == name_at:
					result = s2.duplicate(true)
					break
	return result

func _get_user_money() -> float:
	if is_instance_valid(gdm) and gdm.has_method("get_current_user_data"):
		var user: Dictionary = gdm.get_current_user_data()
		if typeof(user) == TYPE_DICTIONARY:
			return float(user.get("money", 0.0))
	return 0.0

func _format_money(amount: float) -> String:
	var s := "%.0f" % amount
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		var ch := s[i]
		out = ch + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return "$" + out

func _update_expand_buttons() -> void:
	# With fixed +1 upgrades, enable when upgrades are available for this settlement.
	var per_unit := _get_upgrade_price_per_unit()
	var funds := _get_user_money()
	var total := int(per_unit) * 1
	var available := per_unit > 0
	print("[WarehouseMenu][UpgradeState] update_buttons sett_type=", _get_settlement_type(), " per_unit=", per_unit, " funds=", funds, " available=", available)
	if is_instance_valid(expand_cargo_btn):
		expand_cargo_btn.disabled = not available
		expand_cargo_btn.tooltip_text = ("Upgrades not available" if not available else "Cost: %s (per unit %s)\nYour funds: %s" % [_format_money(total), _format_money(per_unit), _format_money(funds)])
	if is_instance_valid(expand_vehicle_btn):
		expand_vehicle_btn.disabled = not available
		expand_vehicle_btn.tooltip_text = ("Upgrades not available" if not available else "Cost: %s (per unit %s)\nYour funds: %s" % [_format_money(total), _format_money(per_unit), _format_money(funds)])

func _update_upgrade_labels() -> void:
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var cargo_cap := int(_warehouse.get("cargo_storage_capacity", 0))
	var veh_cap := int(_warehouse.get("vehicle_storage_capacity", 0))
	if is_instance_valid(expand_cargo_label):
		expand_cargo_label.text = "Upgrade Cargo Capacity (Cap: %s)" % cargo_cap
	if is_instance_valid(expand_vehicle_label):
		expand_vehicle_label.text = "Upgrade Vehicle Slots (Cap: %s)" % veh_cap

# --- Helpers for dropdowns ---
func _populate_dropdowns() -> void:
	# Convoy cargo (Store): aggregate across vehicles, exclude installed parts, list normal-with-destination first, then other normal, then part cargo
	if is_instance_valid(cargo_store_dd):
		var agg := _aggregate_convoy_cargo(_convoy_data)
		var normals_dest: Array = agg["normal_dest"] if agg.has("normal_dest") else []
		var normals_other: Array = agg["normal_other"] if agg.has("normal_other") else []
		var parts: Array = agg["part"] if agg.has("part") else []
		# Build id/label list in stable order
		var items: Array = []
		for it in normals_dest: items.append({"id": it["cargo_id"], "label": "%s x%d" % [it.get("name", "Unknown"), int(it.get("quantity", 0))]})
		for itn in normals_other: items.append({"id": itn["cargo_id"], "label": "%s x%d" % [itn.get("name", "Unknown"), int(itn.get("quantity", 0))]})
		for it2 in parts: items.append({"id": it2["cargo_id"], "label": "%s x%d" % [it2.get("name", "Unknown"), int(it2.get("quantity", 0))]})
		_set_option_button_items(cargo_store_dd, items, _last_cargo_store_ids)
		# Sync store qty limit to selected item after (re)population
		_update_store_qty_limit()

	# Warehouse cargo (Retrieve): classify normal vs part cargo; prefer cargo_storage
	if is_instance_valid(cargo_retrieve_dd):
		var wh_items: Array = []
		if _warehouse and _warehouse.has("cargo_storage"):
			wh_items = _warehouse.get("cargo_storage", [])
		elif _warehouse and _warehouse.has("cargo_inventory"):
			wh_items = _warehouse.get("cargo_inventory", [])
		elif _warehouse and _warehouse.has("all_cargo"):
			wh_items = _warehouse.get("all_cargo", [])
		# Debug: show how many warehouse cargo items were found before classification
		print("[WarehouseMenu][Debug] Dropdown populate: wh cargo count=", wh_items.size())
		var norm_wh_dest: Array = []
		var norm_wh_other: Array = []
		var part_wh: Array = []
		for wi in wh_items:
			if wi is Dictionary:
				var is_part: bool = wi.has("intrinsic_part_id") and wi.get("intrinsic_part_id") != null
				var entry: Dictionary = (wi as Dictionary).duplicate(true)
				if is_part:
					part_wh.append(entry)
				else:
					# destination (mission) if recipient or delivery_reward present
					var has_dest: bool = (entry.get("recipient") != null) or (entry.get("delivery_reward") != null)
					if has_dest:
						norm_wh_dest.append(entry)
					else:
						norm_wh_other.append(entry)
		norm_wh_dest.sort_custom(func(a, b): return String(a.get("name","")) < String(b.get("name","")) or (String(a.get("name","")) == String(b.get("name","")) and String(a.get("cargo_id","")) < String(b.get("cargo_id",""))))
		norm_wh_other.sort_custom(func(a, b): return String(a.get("name","")) < String(b.get("name","")) or (String(a.get("name","")) == String(b.get("name","")) and String(a.get("cargo_id","")) < String(b.get("cargo_id",""))))
		part_wh.sort_custom(func(a, b): return String(a.get("name","")) < String(b.get("name","")) or (String(a.get("name","")) == String(b.get("name","")) and String(a.get("cargo_id","")) < String(b.get("cargo_id",""))))
		var wh_items_final: Array = []
		for a in norm_wh_dest: wh_items_final.append({"id": String(a.get("cargo_id","")), "label": "%s x%d" % [String(a.get("name","Unknown")), int(a.get("quantity",0))]})
		for a2 in norm_wh_other: wh_items_final.append({"id": String(a2.get("cargo_id","")), "label": "%s x%d" % [String(a2.get("name","Unknown")), int(a2.get("quantity",0))]})
		for b in part_wh: wh_items_final.append({"id": String(b.get("cargo_id","")), "label": "%s x%d" % [String(b.get("name","Unknown")), int(b.get("quantity",0))]})
		_set_option_button_items(cargo_retrieve_dd, wh_items_final, _last_cargo_retrieve_ids)
		# Sync retrieve qty limit to selected item after (re)population
		_update_retrieve_qty_limit()
		# Also re-render cargo grid in case of updates
		_render_cargo_grid()

	# Vehicles from convoy for store and target vehicle dropdowns (stable sort by name then id)
	var convoy_vehicles: Array = []
	if _convoy_data and _convoy_data.has("vehicle_details_list"):
		convoy_vehicles = _convoy_data.get("vehicle_details_list", [])
	var convoy_vehicle_items: Array = []
	for v in convoy_vehicles:
		if v is Dictionary:
			convoy_vehicle_items.append({"name": String(v.get("name","Vehicle")), "id": String(v.get("vehicle_id",""))})
	convoy_vehicle_items.sort_custom(func(a, b): return a["name"] < b["name"] or (a["name"] == b["name"] and a["id"] < b["id"]))
	if is_instance_valid(vehicle_store_dd):
		var items_vs: Array = []
		for cv in convoy_vehicle_items: items_vs.append({"id": cv["id"], "label": cv["name"]})
		_set_option_button_items(vehicle_store_dd, items_vs, _last_vehicle_store_ids)
	if is_instance_valid(cargo_retrieve_vehicle_dd):
		var items_recv: Array = []
		for cv2 in convoy_vehicle_items: items_recv.append({"id": cv2["id"], "label": cv2["name"]})
		_set_option_button_items(cargo_retrieve_vehicle_dd, items_recv, []) # no last tracking needed

	# Warehouse vehicles (retrieve/spawn) stable sort; prefer vehicle_storage
	var wh_vehicle_items: Array = []
	if _warehouse and _warehouse.has("vehicle_storage"):
		for v2 in _warehouse.get("vehicle_storage", []):
			if v2 is Dictionary:
				wh_vehicle_items.append({"name": String(v2.get("name","Vehicle")), "id": String(v2.get("vehicle_id",""))})
	elif _warehouse and _warehouse.has("vehicle_inventory"):
		for v3 in _warehouse.get("vehicle_inventory", []):
			if v3 is Dictionary:
				wh_vehicle_items.append({"name": String(v3.get("name","Vehicle")), "id": String(v3.get("vehicle_id",""))})
	wh_vehicle_items.sort_custom(func(a, b): return a["name"] < b["name"] or (a["name"] == b["name"] and a["id"] < b["id"]))
	if is_instance_valid(vehicle_retrieve_dd):
		var items_vr: Array = []
		for wv in wh_vehicle_items: items_vr.append({"id": wv["id"], "label": wv["name"]})
		_set_option_button_items(vehicle_retrieve_dd, items_vr, _last_vehicle_retrieve_ids)
	if is_instance_valid(spawn_vehicle_dd):
		var items_sv: Array = []
		for wv2 in wh_vehicle_items: items_sv.append({"id": wv2["id"], "label": wv2["name"]})
		_set_option_button_items(spawn_vehicle_dd, items_sv, _last_spawn_vehicle_ids)
		# UX: manage spawn button enable state based on availability
		if is_instance_valid(spawn_convoy_btn):
			if spawn_vehicle_dd.item_count == 0:
				spawn_convoy_btn.disabled = true
				spawn_convoy_btn.tooltip_text = "Store a vehicle first to spawn a new convoy."
			else:
				spawn_convoy_btn.disabled = false
				spawn_convoy_btn.tooltip_text = "Spawn a new convoy using the selected stored vehicle."
	# Update vehicle grid visuals as well
	_render_vehicle_grid()

func _get_selected_meta(dd: OptionButton) -> String:
	if not is_instance_valid(dd) or dd.item_count == 0:
		return ""
	var idx := dd.get_selected_id()
	if idx < 0:
		idx = dd.get_selected()
	if idx < 0:
		return ""
	var meta = dd.get_item_metadata(idx)
	return String(meta) if meta != null else ""

func _update_cargo_usage_label() -> void:
	if not is_instance_valid(cargo_usage_label):
		return
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		cargo_usage_label.text = "Cargo: 0 / 0 L"
		return
	var cap := int(_warehouse.get("cargo_storage_capacity", 0))
	var used := int(_warehouse.get("stored_volume", 0))
	cargo_usage_label.text = "Cargo: %s / %s L" % [str(used), str(cap)]
	_update_overview_bars()

func _update_overview_bars() -> void:
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		if is_instance_valid(overview_cargo_bar):
			overview_cargo_bar.value = 0
		if is_instance_valid(overview_vehicle_bar):
			overview_vehicle_bar.value = 0
		return
	# Cargo bar
	var cap_cargo := float(_warehouse.get("cargo_storage_capacity", 0))
	var used_cargo := float(_warehouse.get("stored_volume", 0))
	if cap_cargo <= 0:
		cap_cargo = 1.0
	var display_used_cargo := used_cargo
	# Guarantee at least a visible 1% if there is any cargo (>0 but below 1%)
	var one_percent_cargo := cap_cargo * 0.01
	if display_used_cargo > 0.0 and display_used_cargo < one_percent_cargo:
		display_used_cargo = one_percent_cargo
	if is_instance_valid(overview_cargo_bar):
		overview_cargo_bar.max_value = cap_cargo
		overview_cargo_bar.value = clamp(display_used_cargo, 0.0, cap_cargo)
	# Vehicle bar (derive from counts if capacity key exists, else hide)
	var veh_list: Array = []
	if _warehouse.has("vehicle_storage"):
		veh_list = _warehouse.get("vehicle_storage", [])
	elif _warehouse.has("vehicle_inventory"):
		veh_list = _warehouse.get("vehicle_inventory", [])
	var veh_used := float(veh_list.size())
	var veh_cap := float(_warehouse.get("vehicle_storage_capacity", max(veh_used, 1)))
	if veh_cap <= 0:
		veh_cap = max(veh_used, 1.0)
	var display_veh_used := veh_used
	var one_percent_veh := veh_cap * 0.01
	if display_veh_used > 0.0 and display_veh_used < one_percent_veh:
		display_veh_used = one_percent_veh
	if is_instance_valid(overview_vehicle_bar):
		overview_vehicle_bar.max_value = veh_cap
		overview_vehicle_bar.value = clamp(display_veh_used, 0.0, veh_cap)

func _render_cargo_grid() -> void:
	if not is_instance_valid(cargo_grid):
		return
	# Clear existing
	for c in cargo_grid.get_children():
		c.queue_free()
	if not (_warehouse is Dictionary):
		return
	var wh_items: Array = []
	if _warehouse.has("cargo_storage"):
		wh_items = _warehouse.get("cargo_storage", [])
	elif _warehouse.has("cargo_inventory"):
		wh_items = _warehouse.get("cargo_inventory", [])
	elif _warehouse.has("all_cargo"):
		wh_items = _warehouse.get("all_cargo", [])
	# Render simple boxes (no icons) with name + qty
	for wi in wh_items:
		if wi is Dictionary:
			var item_name := String(wi.get("name", "Item"))
			var qty := int(wi.get("quantity", 0))
			var panel := PanelContainer.new()
			panel.custom_minimum_size = Vector2(120, 32)
			var vb := VBoxContainer.new()
			var label := Label.new()
			label.text = "%s x%d" % [item_name, qty]
			vb.add_child(label)
			panel.add_child(vb)
			cargo_grid.add_child(panel)

func _render_vehicle_grid() -> void:
	if not is_instance_valid(vehicle_grid):
		return
	for c in vehicle_grid.get_children():
		c.queue_free()
	if not (_warehouse is Dictionary):
		return
	var wh_vehicles: Array = []
	if _warehouse.has("vehicle_storage"):
		wh_vehicles = _warehouse.get("vehicle_storage", [])
	elif _warehouse.has("vehicle_inventory"):
		wh_vehicles = _warehouse.get("vehicle_inventory", [])
	for v in wh_vehicles:
		if v is Dictionary:
			var vehicle_name := String(v.get("name", "Vehicle"))
			var panel := PanelContainer.new()
			panel.custom_minimum_size = Vector2(120, 32)
			var vb := VBoxContainer.new()
			var label := Label.new()
			label.text = vehicle_name
			vb.add_child(label)
			panel.add_child(vb)
			vehicle_grid.add_child(panel)

# Enforce SpinBox max based on selected cargo quantities
func _update_store_qty_limit() -> void:
	if not is_instance_valid(cargo_qty_store):
		return
	var cargo_id := _get_selected_meta(cargo_store_dd)
	var max_qty := 1
	if cargo_id != "":
		max_qty = max(1, _get_convoy_cargo_quantity_by_id(cargo_id))
	cargo_qty_store.min_value = 1
	cargo_qty_store.step = 1
	cargo_qty_store.allow_greater = false
	cargo_qty_store.max_value = float(max_qty)
	if cargo_qty_store.value > cargo_qty_store.max_value:
		cargo_qty_store.value = cargo_qty_store.max_value
	# Optionally disable button if none available
	if is_instance_valid(store_cargo_btn):
		store_cargo_btn.disabled = (cargo_id == "" or max_qty <= 0)

func _update_retrieve_qty_limit() -> void:
	if not is_instance_valid(cargo_qty_retrieve):
		return
	var cargo_id := _get_selected_meta(cargo_retrieve_dd)
	var max_qty := 1
	if cargo_id != "":
		max_qty = max(1, _get_warehouse_cargo_quantity_by_id(cargo_id))
	cargo_qty_retrieve.min_value = 1
	cargo_qty_retrieve.step = 1
	cargo_qty_retrieve.allow_greater = false
	cargo_qty_retrieve.max_value = float(max_qty)
	if cargo_qty_retrieve.value > cargo_qty_retrieve.max_value:
		cargo_qty_retrieve.value = cargo_qty_retrieve.max_value
	if is_instance_valid(retrieve_cargo_btn):
		retrieve_cargo_btn.disabled = (cargo_id == "" or max_qty <= 0)

func _get_convoy_cargo_quantity_by_id(cargo_id: String) -> int:
	if cargo_id == "":
		return 0
	var agg := _aggregate_convoy_cargo(_convoy_data)
	for arr_name in ["normal_dest", "normal_other", "part"]:
		if agg.has(arr_name):
			for it in agg[arr_name]:
				if String(it.get("cargo_id", "")) == cargo_id:
					return int(it.get("quantity", 0))
	return 0

func _get_warehouse_cargo_quantity_by_id(cargo_id: String) -> int:
	if cargo_id == "" or not (_warehouse is Dictionary) or _warehouse.is_empty():
		return 0
	var total := 0
	var wh_items: Array = []
	if _warehouse.has("cargo_storage"):
		wh_items = _warehouse.get("cargo_storage", [])
	elif _warehouse.has("cargo_inventory"):
		wh_items = _warehouse.get("cargo_inventory", [])
	elif _warehouse.has("all_cargo"):
		wh_items = _warehouse.get("all_cargo", [])
	for wi in wh_items:
		if wi is Dictionary and String(wi.get("cargo_id", "")) == cargo_id:
			total += int(wi.get("quantity", 0))
	return total

# Helpers for stable dropdown population and cargo aggregation
func _set_option_button_items(dd: OptionButton, items: Array, last_ids_ref: Array) -> void:
	if not is_instance_valid(dd):
		return
	# Build current ids from control
	var current_ids: Array[String] = []
	for i in range(dd.item_count):
		var m = dd.get_item_metadata(i)
		current_ids.append(String(m) if m != null else "")
	# Build new ids
	var new_ids: Array[String] = []
	for it in items:
		new_ids.append(String(it.get("id","")))
	# If unchanged, just return to avoid reshuffle
	if current_ids == new_ids:
		return
	# Preserve selection by id
	var prev_selected_id := _get_selected_meta(dd)
	dd.clear()
	for it2 in items:
		dd.add_item(String(it2.get("label","")))
		dd.set_item_metadata(dd.item_count - 1, String(it2.get("id","")))
	# Restore selection if possible
	if prev_selected_id != "":
		for j in range(dd.item_count):
			if String(dd.get_item_metadata(j)) == prev_selected_id:
				dd.select(j)
				break
	# Update last ids tracking if provided
	if typeof(last_ids_ref) == TYPE_ARRAY:
		last_ids_ref.clear()
		for nid in new_ids: last_ids_ref.append(nid)

func _aggregate_convoy_cargo(convoy: Dictionary) -> Dictionary:
	var result := {"normal_dest": [], "normal_other": [], "part": []}
	if not (convoy is Dictionary) or not convoy.has("vehicle_details_list"):
		return result
	var by_id: Dictionary = {}
	var by_id_is_part: Dictionary = {}
	var by_id_has_dest: Dictionary = {}

	# Build set of installed part IDs to exclude corresponding cargo entries if present
	var installed_part_ids: Dictionary = {} # set-like
	for veh0 in convoy.get("vehicle_details_list", []):
		if not (veh0 is Dictionary):
			continue
		var parts_arr: Array = veh0.get("parts", [])
		for p in parts_arr:
			if p is Dictionary:
				var pid := String(p.get("part_id", p.get("intrinsic_part_id", "")))
				if pid != "":
					installed_part_ids[pid] = true
	for veh in convoy.get("vehicle_details_list", []):
		if not (veh is Dictionary):
			continue
		var cargo_arr: Array = veh.get("cargo", [])
		for item in cargo_arr:
			if not (item is Dictionary):
				continue
			var cid := String(item.get("cargo_id", ""))
			if cid == "":
				continue
			var qty := int(item.get("quantity", 0))
			if qty <= 0:
				continue
			# Classify as part cargo if intrinsic_part_id present; installed parts are not in cargo[]
			var is_part: bool = item.has("intrinsic_part_id") and item.get("intrinsic_part_id") != null
			# If this is a part cargo and this intrinsic_part_id is installed on any vehicle, skip showing it
			if is_part:
				var intr_id := String(item.get("intrinsic_part_id", ""))
				if intr_id != "" and installed_part_ids.has(intr_id):
					continue
			if not by_id.has(cid):
				by_id[cid] = {
					"cargo_id": cid,
					"name": String(item.get("name", "Unknown")),
					"quantity": qty
				}
				by_id_is_part[cid] = is_part
				by_id_has_dest[cid] = (item.get("recipient") != null) or (item.get("delivery_reward") != null)
			else:
				by_id[cid]["quantity"] = int(by_id[cid].get("quantity", 0)) + qty
				# If any occurrence flags as part, keep it as part
				if is_part:
					by_id_is_part[cid] = true
				# If any occurrence has destination, keep it as true
				if (item.get("recipient") != null) or (item.get("delivery_reward") != null):
					by_id_has_dest[cid] = true
	# Split and sort
	var normals_dest: Array = []
	var normals_other: Array = []
	var parts: Array = []
	for cid2 in by_id.keys():
		var entry = by_id[cid2]
		if by_id_is_part.get(cid2, false):
			parts.append(entry)
		else:
			if by_id_has_dest.get(cid2, false):
				normals_dest.append(entry)
			else:
				normals_other.append(entry)
	normals_dest.sort_custom(func(a, b): return String(a.get("name","")) < String(b.get("name","")) or (String(a.get("name","")) == String(b.get("name","")) and String(a.get("cargo_id","")) < String(b.get("cargo_id",""))))
	normals_other.sort_custom(func(a, b): return String(a.get("name","")) < String(b.get("name","")) or (String(a.get("name","")) == String(b.get("name","")) and String(a.get("cargo_id","")) < String(b.get("cargo_id",""))))
	parts.sort_custom(func(a, b): return String(a.get("name","")) < String(b.get("name","")) or (String(a.get("name","")) == String(b.get("name","")) and String(a.get("cargo_id","")) < String(b.get("cargo_id",""))))
	result["normal_dest"] = normals_dest
	result["normal_other"] = normals_other
	result["part"] = parts
	return result
