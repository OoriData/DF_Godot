extends Control

signal back_requested

@onready var title_label: Label = $MainVBox/TopBarHBox/TitleLabel
@onready var buy_button: Button = $MainVBox/TopBarHBox/BuyButton
@onready var back_button: Button = $MainVBox/BackButton
@onready var info_label: Label = $MainVBox/Body/InfoLabel
@onready var owned_tabs: TabContainer = $MainVBox/Body/OwnedTabs
@onready var summary_label: Label = $MainVBox/Body/OwnedTabs/Overview/SummaryLabel
@onready var expand_cargo_amount: SpinBox = $MainVBox/Body/OwnedTabs/Overview/ExpandCargoHBox/ExpandCargoAmount
@onready var expand_cargo_btn: Button = $MainVBox/Body/OwnedTabs/Overview/ExpandCargoHBox/ExpandCargoBtn
@onready var expand_vehicle_amount: SpinBox = $MainVBox/Body/OwnedTabs/Overview/ExpandVehicleHBox/ExpandVehicleAmount
@onready var expand_vehicle_btn: Button = $MainVBox/Body/OwnedTabs/Overview/ExpandVehicleHBox/ExpandVehicleBtn
@onready var cargo_id_input_store: LineEdit = $MainVBox/Body/OwnedTabs/Cargo/CargoStoreHBox/CargoIdInputStore
@onready var cargo_qty_store: SpinBox = $MainVBox/Body/OwnedTabs/Cargo/CargoStoreHBox/CargoQtyStore
@onready var store_cargo_btn: Button = $MainVBox/Body/OwnedTabs/Cargo/CargoStoreHBox/StoreCargoBtn
@onready var cargo_id_input_retrieve: LineEdit = $MainVBox/Body/OwnedTabs/Cargo/CargoRetrieveHBox/CargoIdInputRetrieve
@onready var cargo_qty_retrieve: SpinBox = $MainVBox/Body/OwnedTabs/Cargo/CargoRetrieveHBox/CargoQtyRetrieve
@onready var retrieve_cargo_btn: Button = $MainVBox/Body/OwnedTabs/Cargo/CargoRetrieveHBox/RetrieveCargoBtn
@onready var vehicle_id_input_store: LineEdit = $MainVBox/Body/OwnedTabs/Vehicles/VehicleStoreHBox/VehicleIdInputStore
@onready var store_vehicle_btn: Button = $MainVBox/Body/OwnedTabs/Vehicles/VehicleStoreHBox/StoreVehicleBtn
@onready var vehicle_id_input_retrieve: LineEdit = $MainVBox/Body/OwnedTabs/Vehicles/VehicleRetrieveHBox/VehicleIdInputRetrieve
@onready var retrieve_vehicle_btn: Button = $MainVBox/Body/OwnedTabs/Vehicles/VehicleRetrieveHBox/RetrieveVehicleBtn
@onready var spawn_name_input: LineEdit = $MainVBox/Body/OwnedTabs/Actions/SpawnHBox/SpawnNameInput
@onready var spawn_convoy_btn: Button = $MainVBox/Body/OwnedTabs/Actions/SpawnHBox/SpawnConvoyBtn

var _convoy_data: Dictionary
var _settlement: Dictionary
var _warehouse: Dictionary
var gdm: Node
var api: Node
var _is_loading: bool = false

const WAREHOUSE_PRICES := {
	"dome": 5000000,
	"city": 3000000,
	"town": 1000000,
}

func _ready():
	gdm = get_node_or_null("/root/GameDataManager")
	api = get_node_or_null("/root/APICalls")
	if is_instance_valid(back_button):
		back_button.pressed.connect(func(): emit_signal("back_requested"))
	if is_instance_valid(buy_button):
		buy_button.pressed.connect(_on_buy_pressed)
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
	_update_ui()

func initialize_with_data(data: Dictionary) -> void:
	_convoy_data = data.duplicate(true)
	_settlement = data.get("settlement", {})
	_update_ui()
	_try_load_warehouse_for_settlement()

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
		if is_instance_valid(info_label):
			info_label.text = ""
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
				var price_text := _format_money(price) if price > 0 else "TBD"
				var funds_text := _format_money(funds)
				info_label.text = "No warehouse here yet.\nPrice: %s\nYour funds: %s" % [price_text, funds_text]
				# Update Buy button text and enabled state based on affordability
				if is_instance_valid(buy_button):
					if price > 0:
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

func _format_warehouse_summary(w: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append("Warehouse ID: %s" % str(w.get("warehouse_id", "?")))
	parts.append("Cargo cap: %s L" % str(w.get("cargo_storage_capacity", 0)))
	parts.append("Vehicle slots: %s" % str(w.get("vehicle_storage_capacity", 0)))
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
	_update_ui()
	# Optionally refresh user/convoys if needed
	if is_instance_valid(gdm):
		if gdm.has_method("request_user_data_refresh"):
			gdm.request_user_data_refresh()
		if gdm.has_method("request_convoy_data_refresh"):
			gdm.request_convoy_data_refresh()

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
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	if wid == "" or not is_instance_valid(api):
		return
	_is_loading = true
	_update_ui()
	api.get_warehouse(wid)

# --- UI action handlers ---
func _on_expand_cargo():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var amt := int(expand_cargo_amount.value) if is_instance_valid(expand_cargo_amount) else 0
	if wid != "" and amt > 0 and is_instance_valid(api):
		info_label.text = "Expanding cargo..."
		api.warehouse_expand({"warehouse_id": wid, "expand_type": "cargo", "amount": amt})

func _on_expand_vehicle():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var amt := int(expand_vehicle_amount.value) if is_instance_valid(expand_vehicle_amount) else 0
	if wid != "" and amt > 0 and is_instance_valid(api):
		info_label.text = "Expanding vehicle slots..."
		api.warehouse_expand({"warehouse_id": wid, "expand_type": "vehicle", "amount": amt})

func _on_store_cargo():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cid := str(_convoy_data.get("convoy_id", ""))
	var cargo_id := cargo_id_input_store.text if is_instance_valid(cargo_id_input_store) else ""
	var qty := int(cargo_qty_store.value) if is_instance_valid(cargo_qty_store) else 0
	if wid != "" and cid != "" and cargo_id != "" and qty > 0 and is_instance_valid(api):
		info_label.text = "Storing cargo..."
		api.warehouse_cargo_store({"warehouse_id": wid, "convoy_id": cid, "cargo_id": cargo_id, "quantity": qty})

func _on_retrieve_cargo():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cid := str(_convoy_data.get("convoy_id", ""))
	var cargo_id := cargo_id_input_retrieve.text if is_instance_valid(cargo_id_input_retrieve) else ""
	var qty := int(cargo_qty_retrieve.value) if is_instance_valid(cargo_qty_retrieve) else 0
	if wid != "" and cid != "" and cargo_id != "" and qty > 0 and is_instance_valid(api):
		info_label.text = "Retrieving cargo..."
		api.warehouse_cargo_retrieve({"warehouse_id": wid, "convoy_id": cid, "cargo_id": cargo_id, "quantity": qty})

func _on_store_vehicle():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cid := str(_convoy_data.get("convoy_id", ""))
	var vid := vehicle_id_input_store.text if is_instance_valid(vehicle_id_input_store) else ""
	if wid != "" and cid != "" and vid != "" and is_instance_valid(api):
		info_label.text = "Storing vehicle..."
		api.warehouse_vehicle_store({"warehouse_id": wid, "convoy_id": cid, "vehicle_id": vid})

func _on_retrieve_vehicle():
	if not (_warehouse is Dictionary) or _warehouse.is_empty():
		return
	var wid := str(_warehouse.get("warehouse_id", ""))
	var cid := str(_convoy_data.get("convoy_id", ""))
	var vid := vehicle_id_input_retrieve.text if is_instance_valid(vehicle_id_input_retrieve) else ""
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
	if wid != "" and is_instance_valid(api):
		info_label.text = "Spawning convoy..."
		api.warehouse_convoy_spawn({"warehouse_id": wid, "name": cname})

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
	var stype := String(_settlement.get("sett_type", "")).to_lower()
	if WAREHOUSE_PRICES.has(stype):
		return int(WAREHOUSE_PRICES[stype])
	# Unknown types: return 0 to indicate no client-side price (server may decide)
	return 0

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
