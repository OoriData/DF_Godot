# AutoSellService.gd
extends Node

# Persistent storage for cargo snapshots
const SNAPSHOT_PATH = "user://cargo_snapshot.json"
const LOG_TAG = "[AutoSell]"

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
@onready var _logger: Node = get_node_or_null("/root/Logger")

var _latest_settlements: Array = []

func _log(msg: String, data: Variant = null) -> void:
	var final_msg = LOG_TAG + " " + msg
	if data != null:
		final_msg += " | data: " + str(data)
	
	if is_instance_valid(_logger) and _logger.has_method("info"):
		_logger.info(final_msg)
	else:
		print(final_msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log("Service ready")
	
	if is_instance_valid(_hub):
		if not _hub.initial_data_ready.is_connected(_on_initial_data_ready):
			_hub.initial_data_ready.connect(_on_initial_data_ready)
			_log("Connected to SignalHub.initial_data_ready")
		
		if not _hub.map_changed.is_connected(_on_map_changed):
			_hub.map_changed.connect(_on_map_changed)
	else:
		_log("WARN: SignalHub not found")
	
	if is_instance_valid(_store):
		if not _store.convoys_changed.is_connected(_on_convoys_changed):
			_store.convoys_changed.connect(_on_convoys_changed)
			_log("Connected to GameStore.convoys_changed")
	else:
		_log("WARN: GameStore not found")

func _on_map_changed(_tiles: Array, settlements: Array) -> void:
	_latest_settlements = settlements

func _on_initial_data_ready() -> void:
	_log("signal initial_data_ready received")
	# Sync settlements if store has them already
	if is_instance_valid(_store) and _store.has_method("get_settlements"):
		_latest_settlements = _store.get_settlements()
		_log("Synced settlements from store: " + str(_latest_settlements.size()))
	
	# Check for missing items since last session
	_compare_and_report()

func _on_convoys_changed(_convoys: Array) -> void:
	_save_snapshot_debounced()

var _save_timer: SceneTreeTimer = null
func _save_snapshot_debounced() -> void:
	if _save_timer != null:
		return
	_log("Queueing snapshot save (5s debounce)")
	_save_timer = get_tree().create_timer(5.0)
	_save_timer.timeout.connect(func():
		_save_timer = null
		_save_snapshot()
	)

func _save_snapshot() -> void:
	if not is_instance_valid(_store):
		_log("ERR: Cannot save snapshot, store invalid")
		return
	var convoys = _store.get_convoys()
	var current_cargo = _get_flat_cargo_list(convoys)
	_log("Saving snapshot... items found: " + str(current_cargo.size()))
	
	var file = FileAccess.open(SNAPSHOT_PATH, FileAccess.WRITE)
	if file:
		var json_str = JSON.stringify(current_cargo)
		file.store_string(json_str)
		file.close()
		_log("Snapshot saved to " + SNAPSHOT_PATH + " (size: " + str(json_str.length()) + ")")
	else:
		_log("ERR: Failed to open snapshot file for writing: " + str(FileAccess.get_open_error()))

func _compare_and_report() -> void:
	_log("Starting comparison...")
	if not FileAccess.file_exists(SNAPSHOT_PATH):
		_log("No existing snapshot found. Creating initial snapshot.")
		_save_snapshot()
		return

	var file = FileAccess.open(SNAPSHOT_PATH, FileAccess.READ)
	if not file:
		_log("ERR: Failed to open snapshot file for reading")
		return
		
	var last_cargo_raw = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(last_cargo_raw) != OK:
		_log("ERR: Failed to parse snapshot JSON")
		_save_snapshot()
		return
	
	var last_cargo = json.get_data()
	if not (last_cargo is Array):
		return
		
	var current_convoys = _store.get_convoys()
	var current_cargo = _get_flat_cargo_list(current_convoys)
	
	_log("Comparing snapshot (" + str(last_cargo.size()) + " items) with current (" + str(current_cargo.size()) + " items)")
	
	var sold_items = _find_missing_items(last_cargo, current_cargo)
	
	if not sold_items.is_empty():
		var total_credits = 0.0
		for item in sold_items:
			total_credits += float(item.get("delivery_reward", 0.0))
			# Resolve recipient name for each item
			item["resolved_recipient"] = _resolve_recipient_name(item)
		
		_log("DETECTION: Found " + str(sold_items.size()) + " auto-sold items! Total Credits: " + str(total_credits))
		
		if is_instance_valid(_hub):
			var receipt_payload = {
				"items": sold_items,
				"total_credits": total_credits
			}
			_hub.auto_sell_receipt_ready.emit(receipt_payload)
	else:
		_log("No items missing. Nothing auto-sold.")
	
	_save_snapshot()

func _resolve_recipient_name(item: Dictionary) -> String:
	# 1) Direct name fields (highest priority)
	var name_fields = [
		"recipient_settlement_name", 
		"destination_settlement_name", 
		"dest_settlement", 
		"destination_name",
		"target_settlement_name"
	]
	for k in name_fields:
		var v = item.get(k)
		if v != null:
			var s = str(v).strip_edges()
			if s != "" and s != "null":
				return s

	# 2) Recursive-ish check for 'recipient' or 'destination' blocks
	for block_key in ["recipient", "destination", "recipient_settlement"]:
		var block = item.get(block_key)
		if block is Dictionary:
			# Try name inside block
			var bname = block.get("name", block.get("settlement_name", ""))
			if str(bname) != "" and str(bname) != "null":
				return str(bname)
			
			# Try settlement IDs inside block
			var rsid = str(block.get("recipient_settlement_id", block.get("settlement_id", block.get("sett_id", ""))))
			if rsid != "" and rsid != "null":
				var name = _get_settlement_name_by_id(rsid)
				if name != "": return name
				
			# Try vendor IDs inside block
			var rvid = str(block.get("vendor_id", block.get("recipient_vendor_id", "")))
			if rvid != "" and rvid != "null":
				var name = _get_settlement_name_by_vendor_id(rvid)
				if name != "": return name
				
			# Try coordinates inside block
			var rx = block.get("x", block.get("coord_x"))
			var ry = block.get("y", block.get("coord_y"))
			if rx != null and ry != null:
				return "Coord (%d, %d)" % [int(rx), int(ry)]
		
		elif block != null and (block is String or block is int or block is float):
			# block is likely a raw ID
			var rid = str(block)
			if rid != "" and rid != "null":
				# Try as settlement ID
				var s_name = _get_settlement_name_by_id(rid)
				if s_name != "": return s_name
				# Try as vendor ID
				var v_name = _get_settlement_name_by_vendor_id(rid)
				if v_name != "": return v_name

	# 3) Top-level IDs (mission data often looks like this)
	var id_fields = ["mission_vendor_id", "recipient_vendor_id", "vendor_id", "destination_vendor_id"]
	for k in id_fields:
		var vid = str(item.get(k, ""))
		if vid != "" and vid != "null":
			var name = _get_settlement_name_by_vendor_id(vid)
			if name != "": return name
			
	var sett_id_fields = ["recipient_settlement_id", "settlement_id", "sett_id", "destination_settlement_id"]
	for k in sett_id_fields:
		var sid = str(item.get(k, ""))
		if sid != "" and sid != "null":
			var name = _get_settlement_name_by_id(sid)
			if name != "": return name

	# 4) Top-level Coordinates fallback
	var dx = item.get("dest_coord_x", item.get("coord_x", item.get("x")))
	var dy = item.get("dest_coord_y", item.get("coord_y", item.get("y")))
	if dx != null and dy != null:
		return "Coord (%d, %d)" % [int(dx), int(dy)]
		
	return "Unknown Recipient"

func _get_settlement_name_by_id(id: String) -> String:
	for s in _latest_settlements:
		if not s is Dictionary: continue
		var sid = str(s.get("sett_id", s.get("id", "")))
		if sid == id:
			return str(s.get("name", ""))
	return ""

func _get_settlement_name_by_vendor_id(vendor_id: String) -> String:
	# Some settlement objects in the snapshot carry a vendors array
	for s in _latest_settlements:
		if not s is Dictionary: continue
		var vendors = s.get("vendors", [])
		for v in vendors:
			var vid = ""
			if v is Dictionary: vid = str(v.get("vendor_id", v.get("id", "")))
			elif v is String: vid = v
			if vid == vendor_id:
				return str(s.get("name", ""))
	return ""

func _get_flat_cargo_list(convoys: Array) -> Array:
	var flat_list = []
	for convoy in convoys:
		if not (convoy is Dictionary): continue
		var vehicles = convoy.get("vehicle_details_list", convoy.get("vehicles", []))
		if vehicles is Array:
			for vehicle in vehicles:
				if not (vehicle is Dictionary): continue
				var cargo_keys = ["cargo", "cargo_items", "cargo_items_typed"]
				for key in cargo_keys:
					if vehicle.has(key) and vehicle[key] is Array:
						for item in vehicle[key]:
							if item is Dictionary:
								flat_list.append(item.duplicate(true))
				if vehicle.has("parts") and vehicle.get("parts") is Array:
					for p in vehicle.get("parts"):
						if not (p is Dictionary): continue
						if p.get("vehicle_id") == null:
							flat_list.append(p.duplicate(true))
	return flat_list

func _find_missing_items(old_list: Array, new_list: Array) -> Array:
	var missing = []
	var new_map = {}
	for item in new_list:
		var uid = item.get("part_uid", item.get("uid", ""))
		if uid != "":
			new_map[uid] = item
		else:
			var cid = item.get("cargo_id", item.get("id", "unknown"))
			new_map[cid] = new_map.get(cid, 0) + int(item.get("quantity", 1))
	
	for item in old_list:
		var uid = item.get("part_uid", item.get("uid", ""))
		if uid != "":
			if not new_map.has(uid):
				missing.append(item)
		else:
			var cid = item.get("cargo_id", item.get("id", "unknown"))
			var old_qty = int(item.get("quantity", 1))
			var new_qty = new_map.get(cid, 0)
			if new_qty < old_qty:
				var diff = old_qty - new_qty
				var missing_item = item.duplicate(true)
				missing_item["quantity"] = diff
				missing.append(missing_item)
				new_map[cid] = 0
			else:
				new_map[cid] -= old_qty
	return missing

func simulate_autosell() -> void:
	_log("DEBUG: Simulating auto-sell event with complex recipient data")
	if not FileAccess.file_exists(SNAPSHOT_PATH):
		_save_snapshot()
		await get_tree().create_timer(0.5).timeout
	
	var file = FileAccess.open(SNAPSHOT_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	
	if data and data is Array and not data.is_empty():
		# Case 1: Nested recipient object (already tested partially, but let's be explicit)
		var fake_item1 = data[0].duplicate(true)
		fake_item1["part_uid"] = "DEBUG_NESTED_" + str(Time.get_ticks_msec())
		fake_item1["name"] = "DEBUG: Shield Generator"
		fake_item1["recipient"] = {"name": "Echo Station Alpha"}
		fake_item1["delivery_reward"] = 1250.0
		data.append(fake_item1)
		
		# Case 2: Raw Vendor ID for a known settlement (if available)
		# We'll try to find a real vendor ID from our latest settlements list if possible
		var some_vendor_id = "unknown_vendor_id"
		if not _latest_settlements.is_empty():
			for s in _latest_settlements:
				var v_list = s.get("vendors", [])
				if not v_list.is_empty():
					var v = v_list[0]
					some_vendor_id = str(v.get("vendor_id", v.get("id", "")))
					break

		var fake_item2 = data[0].duplicate(true)
		fake_item2["part_uid"] = "DEBUG_RAW_ID_" + str(Time.get_ticks_msec() + 1)
		fake_item2["name"] = "DEBUG: Hydro-Cell"
		fake_item2["recipient"] = some_vendor_id
		fake_item2["delivery_reward"] = 450.0
		data.append(fake_item2)

		# Case 3: Coordinates only
		var fake_item3 = data[0].duplicate(true)
		fake_item3["part_uid"] = "DEBUG_COORDS_" + str(Time.get_ticks_msec() + 2)
		fake_item3["name"] = "DEBUG: Scrap Metal"
		fake_item3.erase("recipient")
		fake_item3["dest_coord_x"] = 12
		fake_item3["dest_coord_y"] = 34
		fake_item3["delivery_reward"] = 150.0
		data.append(fake_item3)
		
		var write_file = FileAccess.open(SNAPSHOT_PATH, FileAccess.WRITE)
		write_file.store_string(JSON.stringify(data))
		write_file.close()
		_compare_and_report()
