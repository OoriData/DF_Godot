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
var _vendor_cache: Dictionary = {} # vendor_id -> vendor Dictionary (last payload)
var _debug_mechanics: bool = true

func get_cached_vendor(vendor_id: String) -> Dictionary:
	if vendor_id == "":
		return {}
	var v: Variant = _vendor_cache.get(vendor_id, {})
	return v if v is Dictionary else {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(_api):
		# Phase 4: Stop listening to APICalls domain-level mechanics signals; rely on service-driven refreshes.
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

	var cv_x = convoy.get("x", 0)
	var cv_y = convoy.get("y", 0)
	var x := int(roundf(float(cv_x) if cv_x != null else 0.0))
	var y := int(roundf(float(cv_y) if cv_y != null else 0.0))
	# Scan current settlement snapshot for vendor inventories.
	var settlements: Array = []
	if is_instance_valid(_store) and _store.has_method("get_settlements"):
		settlements = _store.get_settlements()
	var settlement: Dictionary = {}
	for s in settlements:
		if not (s is Dictionary):
			continue
		var sx_val = (s as Dictionary).get("x", -999999)
		var sy_val = (s as Dictionary).get("y", -999999)
		var sx := int(roundf(float(sx_val) if sx_val != null else 0.0))
		var sy := int(roundf(float(sy_val) if sy_val != null else 0.0))
		if sx == x and sy == y:
			settlement = s
			break
	if settlement.is_empty():
		return
	var vendors_any: Array = settlement.get("vendors", [])
	# For each vendor in the current settlement, request full details if we don't have them.
	for v in vendors_any:
		var vid := ""
		if v is Dictionary:
			vid = str(v.get("vendor_id", v.get("id", "")))
			# Only ingest if it looks like it might actually have inventory/useful data.
			# Don't let shallow map dictionaries poison the cache.
			if _is_full_vendor_payload(v):
				_ingest_vendor_inventory(v)
		elif v is String:
			vid = v

		# If we don't have a cached full preview for this vendor, request full details.
		var cached: Dictionary = _vendor_cache.get(vid, {})
		if vid != "" and not _is_full_vendor_payload(cached):
			if is_instance_valid(_vendor_service) and _vendor_service.has_method("request_vendor"):
				if _debug_mechanics:
					print("[MechanicsService] Warmup: requesting full details for vendor_id=", vid)
				_vendor_service.request_vendor(vid)
		elif _debug_mechanics and vid != "":
			print("[MechanicsService] Warmup: vendor_id=", vid, " already cached (full). Parts in c2s: ", _preview_cargo_id_to_slot.size())

func _is_full_vendor_payload(v: Dictionary) -> bool:
	if v.is_empty(): return false
	# A full payload from the API typically includes an explicit inventory key.
	# Map snapshots usually only include id, name, and position.
	for k in ["cargo_inventory", "cargoInventory", "inventory", "cargo", "stock"]:
		if v.has(k) and v[k] is Array:
			return true
	# Also consider it full if it has resource prices (common for mechanics/traders).
	if v.has("fuel_price") or v.has("water_price") or v.has("food_price"):
		return true
	return false


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
		else:
			# Even without a slot, if it's identified as a part, we must track it for the preview list.
			if not _preview_cargo_id_to_slot.has(cid):
				_preview_cargo_id_to_slot[cid] = ""
		
		# If we found a part/slot update, tell the Hub so menus can refresh based on enriched data.
		if is_instance_valid(_hub) and _hub.has_signal("vendor_preview_ready"):
			if _debug_mechanics:
				print("[MechanicsService] Enriched part arrived, triggering preview refresh: ", cargo.get("name", "Unknown"), " cid=", cid)
			_hub.vendor_preview_ready.emit(false) # false = cache not cleared, just updated


func _on_vendor_updated(vendor: Dictionary) -> void:
	_ingest_vendor_inventory(vendor)


func _ingest_vendor_inventory(vendor: Variant) -> void:
	if not (vendor is Dictionary):
		return
	var vd: Dictionary = vendor
	# Unwrap common envelopes
	if vd.has("vendor") and vd.get("vendor") is Dictionary:
		vd = vd.get("vendor")
	elif vd.has("data") and vd.get("data") is Dictionary:
		vd = vd.get("data")
	# Robust vendor id extraction
	var vendor_id := ""
	var id_keys := ["vendor_id", "vendorId", "vendorID", "vend_id", "vendor_uuid", "uuid", "id", "_id"]
	for k in id_keys:
		if vd.has(k) and vd.get(k) != null:
			vendor_id = String(vd.get(k, ""))
			if vendor_id != "":
				break
	if vendor_id != "":
		if not _vendor_cache.has(vendor_id) or _is_full_vendor_payload(vd):
			_vendor_cache[vendor_id] = vd
		elif _debug_mechanics:
			print("[MechanicsService] Ingest: ignoring shallow payload for already cached vendor_id=", vendor_id)
	# Vendor payloads can use different keys.
	var cargo_inv: Array = []
	var inv_keys := ["cargo_inventory", "cargoInventory", "cargo_inventory_list", "cargoInventoryList", "inventory", "inv", "cargo", "items", "goods", "stock"]
	for k in inv_keys:
		if vd.has(k):
			var inv: Variant = vd.get(k)
			if inv is Array:
				cargo_inv = inv
				break
			if inv is Dictionary and (inv as Dictionary).has("items") and (inv as Dictionary).get("items") is Array:
				cargo_inv = (inv as Dictionary).get("items")
				break
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
			if _debug_mechanics:
				print("[MechanicsService] Ingested part: ", d.get("name", "Unknown"), " cid=", cid, " slot=", slot)
		else:
			# If it's not a mission and not a resource, proactively enrich it as a potential part.
			var is_mission := false
			if ItemsData != null and ItemsData.MissionItem:
				is_mission = ItemsData.MissionItem._looks_like_mission_dict(d)
			
			var is_resource := false
			for res_key in ["fuel", "water", "food"]:
				var rv = d.get(res_key)
				if rv != null and (rv is float or rv is int) and float(rv) > 0.0:
					is_resource = true
					break
			
			if not is_mission and not is_resource:
				if _debug_mechanics:
					print("[MechanicsService] Proactively enriching potential part: ", d.get("name", "Unknown"), " cid=", cid)
				ensure_cargo_details(cid)
			elif _debug_mechanics:
				# Extra verbose: find out why it's not a part
				var nm := String(d.get("name", "Unknown"))
				print("[MechanicsService] Item skipped (is_mission=%s is_resource=%s): " % [is_mission, is_resource], nm, " cid=", cid)


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
		# Phase 4: Immediately refresh convoy snapshot; Hub will emit updates.
		if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
			_convoy_service.refresh_single(convoy_id)

func detach_part(convoy_id: String, vehicle_id: String, part_id: String) -> void:
	if convoy_id == "" or vehicle_id == "" or part_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("detach_vehicle_part"):
		_vehicle_to_convoy_id[vehicle_id] = convoy_id
		# APICalls signature: detach_vehicle_part(vehicle_id, part_id)
		_api.detach_vehicle_part(vehicle_id, part_id)
		# Phase 4: Immediately refresh convoy snapshot; Hub will emit updates.
		if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
			_convoy_service.refresh_single(convoy_id)

func add_part_from_vendor(vendor_id: String, convoy_id: String, vehicle_id: String, part_cargo_id: String) -> void:
	if vendor_id == "" or convoy_id == "" or vehicle_id == "" or part_cargo_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("add_vehicle_part"):
		_vehicle_to_convoy_id[vehicle_id] = convoy_id
		_api.add_vehicle_part(vendor_id, convoy_id, vehicle_id, part_cargo_id)
		# Phase 4: Immediately refresh convoy snapshot; Hub will emit updates.
		if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
			_convoy_service.refresh_single(convoy_id)

func apply_swaps(convoy_id: String, vehicle_id: String, ordered_swaps: Array, vendor_id: String = "") -> void:
	# Mirrors legacy GameDataManager.apply_mechanic_swaps routing: inventory+removable -> attach;
	# otherwise vendor add when vendor_id is available; else attach fallback.
	if not is_instance_valid(_api):
		return
	var _issued: bool = false
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
			_issued = true
		elif effective_vendor != "" and _api.has_method("add_vehicle_part"):
			if cargo_id_str == "":
				continue
			_api.add_vehicle_part(effective_vendor, convoy_id, vid, cargo_id_str)
			_issued = true
		elif _api.has_method("attach_vehicle_part") and cargo_id_str != "":
			_api.attach_vehicle_part(vid, cargo_id_str)
			_issued = true
	# Phase 4: Immediately refresh convoy snapshot after swap operations.
	if _issued and is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
		_convoy_service.refresh_single(convoy_id)

func check_part_compatibility(vehicle_id: String, cargo_id: String) -> void:
	if vehicle_id == "" or cargo_id == "":
		return
	if is_instance_valid(_api) and _api.has_method("check_vehicle_part_compatibility"):
		_api.check_vehicle_part_compatibility(vehicle_id, cargo_id)

# Phase 4: Domain-level APICalls completion handlers removed; immediate refreshes are issued after operations.

func _on_compatibility_checked(_payload: Dictionary) -> void:
	# Compatibility is consumed directly from APICalls.part_compatibility_checked in newer menus.
	pass

func _on_operation_failed(error: Dictionary) -> void:
	if is_instance_valid(_hub) and _hub.has_signal("error_occurred"):
		_hub.error_occurred.emit(error)
