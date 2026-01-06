# MechanicsService.gd
extends Node

# Thin service for mechanics compatibility flows: attach/detach parts.

const ItemsData = preload("res://Scripts/Data/Items.gd")

@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
@onready var _convoy_service: Node = get_node_or_null("/root/ConvoyService")
@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _vendor_service: Node = get_node_or_null("/root/VendorService")

# Track which convoy a vehicle belongs to for follow-up refreshes.
var _vehicle_to_convoy_id: Dictionary = {} # vehicle_id -> convoy_id

# --- Phase C: Minimal mechanics vendor preview cache (replaces legacy GameDataManager probe snapshot) ---
var _preview_active_convoy_id: String = ""
var _preview_cargo_id_to_slot: Dictionary = {} # cargo_id -> slot_name
var _cargo_detail_cache: Dictionary = {} # cargo_id -> cargo Dictionary
var _cargo_enrichment_pending: Dictionary = {} # cargo_id -> true while request in-flight

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(_api):
		if _api.has_signal("vehicle_part_attached") and not _api.vehicle_part_attached.is_connected(_on_attach_completed):
			_api.vehicle_part_attached.connect(_on_attach_completed)
		if _api.has_signal("vehicle_part_added") and not _api.vehicle_part_added.is_connected(_on_add_completed):
			_api.vehicle_part_added.connect(_on_add_completed)
		if _api.has_signal("vehicle_part_detached") and not _api.vehicle_part_detached.is_connected(_on_detach_completed):
			_api.vehicle_part_detached.connect(_on_detach_completed)
		if _api.has_signal("part_compatibility_checked") and not _api.part_compatibility_checked.is_connected(_on_compatibility_checked):
			_api.part_compatibility_checked.connect(_on_compatibility_checked)
		if _api.has_signal("mechanic_operation_failed") and not _api.mechanic_operation_failed.is_connected(_on_operation_failed):
			_api.mechanic_operation_failed.connect(_on_operation_failed)
		if _api.has_signal("cargo_data_received") and not _api.cargo_data_received.is_connected(_on_cargo_data_received):
			_api.cargo_data_received.connect(_on_cargo_data_received)

	# Keep the preview cache warm by ingesting vendor updates.
	if is_instance_valid(_hub) and _hub.has_signal("vendor_updated") and not _hub.vendor_updated.is_connected(_on_vendor_updated):
		_hub.vendor_updated.connect(_on_vendor_updated)
	if is_instance_valid(_hub) and _hub.has_signal("vendor_preview_ready") and not _hub.vendor_preview_ready.is_connected(_on_vendor_updated):
		_hub.vendor_preview_ready.connect(_on_vendor_updated)
	if is_instance_valid(_hub) and _hub.has_signal("vendor_panel_ready") and not _hub.vendor_panel_ready.is_connected(_on_vendor_updated):
		_hub.vendor_panel_ready.connect(_on_vendor_updated)
	# If the map snapshot changes, clear slot cache so it can be rebuilt for the new settlement context.
	if is_instance_valid(_store) and _store.has_signal("map_changed") and not _store.map_changed.is_connected(_on_store_map_changed):
		_store.map_changed.connect(_on_store_map_changed)


func start_mechanics_probe_session(convoy_id: String) -> void:
	_preview_active_convoy_id = convoy_id


func end_mechanics_probe_session() -> void:
	_preview_active_convoy_id = ""
	_preview_cargo_id_to_slot.clear()


func warm_mechanics_data_for_convoy(convoy: Dictionary) -> void:
	# Best-effort warmup used by ConvoyMenu to populate the "Available Parts" preview.
	if not (convoy is Dictionary) or convoy.is_empty():
		return
	var cid := String(convoy.get("convoy_id", ""))
	if cid != "":
		_preview_active_convoy_id = cid

	var x := int(roundf(float(convoy.get("x", 0))))
	var y := int(roundf(float(convoy.get("y", 0))))
	# Scan current settlement snapshot for vendor inventories.
	var settlements: Array = []
	if is_instance_valid(_store) and _store.has_method("get_settlements"):
		settlements = _store.get_settlements()
	var settlement: Dictionary = {}
	for s in settlements:
		if not (s is Dictionary):
			continue
		var sx := int(roundf(float((s as Dictionary).get("x", -999999))))
		var sy := int(roundf(float((s as Dictionary).get("y", -999999))))
		if sx == x and sy == y:
			settlement = s
			break
	if settlement.is_empty():
		return
	var vendors_any: Array = settlement.get("vendors", [])
	for v in vendors_any:
		if v is Dictionary:
			_ingest_vendor_inventory(v)
		elif v is String:
			# Request vendor details so Hub emits vendor_updated and we can ingest inventory.
			if is_instance_valid(_vendor_service) and _vendor_service.has_method("request_vendor"):
				_vendor_service.request_vendor(String(v))


func get_mechanic_probe_snapshot() -> Dictionary:
	# Matches the subset used by ConvoyMenu.
	return {
		"cargo_id_to_slot": _preview_cargo_id_to_slot.duplicate(true)
	}


func get_enriched_cargo(cargo_id: String) -> Dictionary:
	if cargo_id == "":
		return {}
	var cached: Variant = _cargo_detail_cache.get(cargo_id, {})
	return cached if cached is Dictionary else {}


func ensure_cargo_details(cargo_id: String) -> void:
	if cargo_id == "":
		return
	if _cargo_detail_cache.has(cargo_id) or _cargo_enrichment_pending.has(cargo_id):
		return
	if is_instance_valid(_api) and _api.has_method("get_cargo"):
		_cargo_enrichment_pending[cargo_id] = true
		_api.get_cargo(cargo_id)


func _on_cargo_data_received(cargo: Dictionary) -> void:
	if not (cargo is Dictionary) or cargo.is_empty():
		return
	var cid := String(cargo.get("cargo_id", cargo.get("id", "")))
	if cid == "":
		return
	_cargo_detail_cache[cid] = cargo
	_cargo_enrichment_pending.erase(cid)
	# If this looks like a part, try to populate slot mapping.
	if ItemsData != null and ItemsData.PartItem and ItemsData.PartItem._looks_like_part_dict(cargo):
		var slot := String(cargo.get("slot", ""))
		if slot == "" and cargo.has("parts") and (cargo.get("parts") is Array) and not (cargo.get("parts") as Array).is_empty():
			var first_p = (cargo.get("parts") as Array)[0]
			if first_p is Dictionary:
				slot = String((first_p as Dictionary).get("slot", ""))
		if slot != "":
			_preview_cargo_id_to_slot[cid] = slot


func _on_vendor_updated(vendor: Dictionary) -> void:
	_ingest_vendor_inventory(vendor)


func _ingest_vendor_inventory(vendor: Variant) -> void:
	if not (vendor is Dictionary):
		return
	var vd: Dictionary = vendor
	# Vendor payloads can use different keys.
	var cargo_inv: Array = []
	if vd.has("cargo_inventory") and (vd.get("cargo_inventory") is Array):
		cargo_inv = vd.get("cargo_inventory")
	elif vd.has("inventory") and (vd.get("inventory") is Array):
		cargo_inv = vd.get("inventory")
	if cargo_inv.is_empty():
		return
	for item in cargo_inv:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var cid := String(d.get("cargo_id", d.get("id", "")))
		if cid == "":
			continue
		# Cache raw details for ConvoyMenu name lookups.
		if not _cargo_detail_cache.has(cid):
			_cargo_detail_cache[cid] = d
		# If the item is part-like, populate slot mapping.
		if ItemsData != null and ItemsData.PartItem and ItemsData.PartItem._looks_like_part_dict(d):
			var slot := String(d.get("slot", ""))
			if slot == "" and d.has("parts") and (d.get("parts") is Array) and not (d.get("parts") as Array).is_empty():
				var first_p = (d.get("parts") as Array)[0]
				if first_p is Dictionary:
					slot = String((first_p as Dictionary).get("slot", ""))
			if slot != "":
				_preview_cargo_id_to_slot[cid] = slot
			else:
				# Leave an empty slot entry so ConvoyMenu can still count the item.
				if not _preview_cargo_id_to_slot.has(cid):
					_preview_cargo_id_to_slot[cid] = ""


func _on_store_map_changed(_tiles: Array, _settlements: Array) -> void:
	# Settlement inventory context may have changed; clear slot cache so next warmup rebuilds.
	_preview_cargo_id_to_slot.clear()

func attach_part(convoy_id: String, vehicle_id: String, part_id: String) -> void:
	if convoy_id == "" or vehicle_id == "" or part_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("attach_vehicle_part"):
		_vehicle_to_convoy_id[vehicle_id] = convoy_id
		# APICalls signature: attach_vehicle_part(vehicle_id, part_cargo_id)
		_api.attach_vehicle_part(vehicle_id, part_id)

func detach_part(convoy_id: String, vehicle_id: String, part_id: String) -> void:
	if convoy_id == "" or vehicle_id == "" or part_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("detach_vehicle_part"):
		_vehicle_to_convoy_id[vehicle_id] = convoy_id
		# APICalls signature: detach_vehicle_part(vehicle_id, part_id)
		_api.detach_vehicle_part(vehicle_id, part_id)

func add_part_from_vendor(vendor_id: String, convoy_id: String, vehicle_id: String, part_cargo_id: String) -> void:
	if vendor_id == "" or convoy_id == "" or vehicle_id == "" or part_cargo_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("add_vehicle_part"):
		_vehicle_to_convoy_id[vehicle_id] = convoy_id
		_api.add_vehicle_part(vendor_id, convoy_id, vehicle_id, part_cargo_id)

func apply_swaps(convoy_id: String, vehicle_id: String, ordered_swaps: Array, vendor_id: String = "") -> void:
	# Mirrors legacy GameDataManager.apply_mechanic_swaps routing: inventory+removable -> attach;
	# otherwise vendor add when vendor_id is available; else attach fallback.
	if not is_instance_valid(_api):
		return
	for s in ordered_swaps:
		if not (s is Dictionary):
			continue
		var vid := String(s.get("vehicle_id", ""))
		if vid == "" or (vehicle_id != "" and vid != vehicle_id):
			continue
		var to_part: Dictionary = s.get("to_part", {})
		var cargo_id_str := String(to_part.get("cargo_id", ""))
		var part_id_str := String(to_part.get("part_id", ""))
		if part_id_str == "":
			part_id_str = String(to_part.get("id", ""))
		if cargo_id_str == "" and part_id_str == "":
			continue
		var swap_vendor_id := String(s.get("vendor_id", ""))
		var effective_vendor := swap_vendor_id if swap_vendor_id != "" else vendor_id
		var source := String(s.get("source", "")).to_lower()
		var removable := false
		var rv: Variant = to_part.get("removable", false)
		if rv is bool:
			removable = rv
		elif rv is int:
			removable = int(rv) != 0
		elif rv is String:
			var rvs := String(rv).to_lower()
			removable = (rvs == "true" or rvs == "1" or rvs == "yes")

		_vehicle_to_convoy_id[vid] = convoy_id
		var prefer_attach := (source == "inventory" and removable and cargo_id_str != "")
		if prefer_attach and _api.has_method("attach_vehicle_part"):
			_api.attach_vehicle_part(vid, cargo_id_str)
		elif effective_vendor != "" and _api.has_method("add_vehicle_part"):
			if cargo_id_str == "":
				continue
			_api.add_vehicle_part(effective_vendor, convoy_id, vid, cargo_id_str)
		elif _api.has_method("attach_vehicle_part") and cargo_id_str != "":
			_api.attach_vehicle_part(vid, cargo_id_str)

func check_part_compatibility(vehicle_id: String, cargo_id: String) -> void:
	if vehicle_id == "" or cargo_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("check_vehicle_part_compatibility"):
		_api.check_vehicle_part_compatibility(vehicle_id, cargo_id)

func _on_attach_completed(updated_convoy_data: Dictionary) -> void:
	# APICalls returns an updated vehicle dictionary; follow up with an authoritative refresh.
	var vehicle_id := String(updated_convoy_data.get("vehicle_id", ""))
	var convoy_id := String(_vehicle_to_convoy_id.get(vehicle_id, ""))
	if convoy_id != "" and is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
		_convoy_service.refresh_single(convoy_id)

func _on_detach_completed(updated_convoy_data: Dictionary) -> void:
	# APICalls returns an updated vehicle dictionary; follow up with an authoritative refresh.
	var vehicle_id := String(updated_convoy_data.get("vehicle_id", ""))
	var convoy_id := String(_vehicle_to_convoy_id.get(vehicle_id, ""))
	if convoy_id != "" and is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
		_convoy_service.refresh_single(convoy_id)

func _on_add_completed(result: Dictionary) -> void:
	# APICalls may return a full convoy dict or a wrapper containing convoy_after.
	if not (result is Dictionary):
		return
	var updated_convoy: Dictionary = {}
	if result.has("convoy_id"):
		updated_convoy = result
	elif result.has("convoy_after") and (result.get("convoy_after") is Dictionary):
		updated_convoy = result.get("convoy_after")
	elif result.has("convoy") and (result.get("convoy") is Dictionary):
		updated_convoy = result.get("convoy")
	else:
		for v in result.values():
			if v is Dictionary and v.has("convoy_id"):
				updated_convoy = v
				break
	if is_instance_valid(_hub) and _hub.has_signal("convoy_updated") and not updated_convoy.is_empty():
		_hub.convoy_updated.emit(updated_convoy)
	# Also refresh the convoy snapshot so GameStore stays authoritative.
	var convoy_id := String(updated_convoy.get("convoy_id", ""))
	if convoy_id != "" and is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
		_convoy_service.refresh_single(convoy_id)

func _on_compatibility_checked(payload: Dictionary) -> void:
	# Compatibility is consumed directly from APICalls.part_compatibility_checked in newer menus.
	pass

func _on_operation_failed(error: Dictionary) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("error_occurred"):
		_hub.error_occurred.emit(error)
