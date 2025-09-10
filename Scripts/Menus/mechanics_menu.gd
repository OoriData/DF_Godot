extends Control

# Signals
signal back_requested
signal changes_committed(convoy_id: String, vehicle_id: String, swaps: Array, estimated_cost: float)

# UI refs
@onready var title_label: Label = $MainVBox/TitleLabel
@onready var vehicle_option_button: OptionButton = $MainVBox/VehicleOptionButton
@onready var tab_container: TabContainer = $MainVBox/TabContainer
@onready var parts_scroll: ScrollContainer = $MainVBox/TabContainer/Parts
@onready var parts_vbox: VBoxContainer = $MainVBox/TabContainer/Parts/PartsVBox
@onready var pending_scroll: ScrollContainer = $MainVBox/TabContainer/Pending
@onready var pending_vbox: VBoxContainer = $MainVBox/TabContainer/Pending/PendingVBox
@onready var back_button: Button = $MainVBox/BottomBar/BackButton
@onready var apply_button: Button = $MainVBox/BottomBar/ApplyButton
@onready var vendor_hint_label: Label = $MainVBox/VendorHintLabel

# State
var _convoy: Dictionary = {}
var _vehicles: Array = []
var _selected_vehicle_idx: int = -1

# Pending swaps: [{slot, from_part, to_part, source: "inventory"|"vendor", price: float}]
var _pending_swaps: Array = []
var _gdm: Node = null
var _slot_vendor_availability: Dictionary = {}
var _compat_cache: Dictionary = {} # key: part_cargo_id -> payload
var _current_swap_ctx: Dictionary = {} # { dialog: AcceptDialog, vehicle_id: String, row_map: { cargo_id: HBoxContainer } }
var _cargo_to_slot: Dictionary = {} # cargo_id -> slot_name for vendor candidates

func _ready():
	if is_instance_valid(back_button):
		back_button.pressed.connect(func(): emit_signal("back_requested"))
	if is_instance_valid(apply_button):
		apply_button.pressed.connect(_on_apply_pressed)
	if is_instance_valid(vehicle_option_button):
		vehicle_option_button.item_selected.connect(_on_vehicle_selected)
	_refresh_apply_state()
	_gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(_gdm) and _gdm.has_signal("part_compatibility_ready") and not _gdm.part_compatibility_ready.is_connected(_on_part_compatibility_ready):
		_gdm.part_compatibility_ready.connect(_on_part_compatibility_ready)
	# Also listen for precomputed vendor slot availability to pre-highlight Swap buttons
	if is_instance_valid(_gdm) and _gdm.has_signal("mechanic_vendor_slot_availability") and not _gdm.mechanic_vendor_slot_availability.is_connected(_on_mechanic_vendor_slot_availability):
		_gdm.mechanic_vendor_slot_availability.connect(_on_mechanic_vendor_slot_availability)

func initialize_with_data(data: Dictionary):
	if not is_node_ready():
		call_deferred("initialize_with_data", data)
		return
	_convoy = data.duplicate(true)
	title_label.text = "Mechanic — %s" % _convoy.get("convoy_name", "Convoy")
	_vehicles = _convoy.get("vehicle_details_list", [])
	# Proactively warm mechanics data: ask GDM to fetch vendor inventories at this settlement
	if _gdm == null:
		_gdm = get_node_or_null("/root/GameDataManager")
	if is_instance_valid(_gdm) and _gdm.has_method("warm_mechanics_data_for_convoy"):
		_gdm.warm_mechanics_data_for_convoy(_convoy)
	_populate_vehicle_dropdown()
	if not _vehicles.is_empty():
		vehicle_option_button.select(0)
		_on_vehicle_selected(0)
	_refresh_apply_state()

func _exit_tree() -> void:
	# End mechanics session to stop auto re-probes targeting this convoy when menu is closed
	if is_instance_valid(_gdm) and _gdm.has_method("end_mechanics_probe_session"):
		_gdm.end_mechanics_probe_session()

func _populate_vehicle_dropdown():
	vehicle_option_button.clear()
	if _vehicles.is_empty():
		vehicle_option_button.add_item("No Vehicles Available")
		vehicle_option_button.disabled = true
		_clear_parts_ui()
		_show_info(parts_vbox, "No vehicles in this convoy.")
		return
	vehicle_option_button.disabled = false
	for i in range(_vehicles.size()):
		var v = _vehicles[i]
		var label = "%s (%s)" % [v.get("name", "Vehicle %d" % (i+1)), v.get("make_model", "")] 
		vehicle_option_button.add_item(label, i)

func _on_vehicle_selected(index: int):
	if index < 0 or index >= _vehicles.size():
		return
	_selected_vehicle_idx = index
	_refresh_slot_vendor_availability()
	_rebuild_parts_tab(_vehicles[index])
	_rebuild_pending_tab()
	# Fire UI-side vendor compatibility checks immediately for this vehicle for better logs/feedback
	_start_vendor_compat_checks_for_vehicle(_vehicles[index])
	# Ask GDM to probe across all vehicles/vendors for this convoy so highlights can be ready next time
	if is_instance_valid(_gdm) and _gdm.has_method("probe_mechanic_vendor_availability_for_convoy"):
		_gdm.probe_mechanic_vendor_availability_for_convoy(_convoy)


func _rebuild_parts_tab(vehicle_data: Dictionary):
	_clear_parts_ui()
	var installed_parts: Array = []
	if vehicle_data.has("parts") and vehicle_data.parts is Array:
		installed_parts.append_array(vehicle_data.parts)
	if vehicle_data.has("cargo") and vehicle_data.cargo is Array:
		for item in vehicle_data.cargo:
			if item is Dictionary and item.get("intrinsic_part_id") != null:
				installed_parts.append(item)
	if installed_parts.is_empty():
		_show_info(parts_vbox, "No installed parts detected.")
		return
	# Group by slot
	var by_slot: Dictionary = {}
	for p in installed_parts:
		var slot = String(p.get("slot", "other"))
		if not by_slot.has(slot):
			by_slot[slot] = []
		by_slot[slot].append(p)
	var slots_sorted: Array = by_slot.keys()
	slots_sorted.sort()
	for slot_name in slots_sorted:
		var header = Label.new()
		header.text = slot_name.capitalize().replace("_", " ")
		header.add_theme_font_size_override("font_size", 16)
		header.add_theme_color_override("font_color", Color.YELLOW)
		parts_vbox.add_child(header)

		for part in by_slot[slot_name]:
			var row = HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.set_meta("slot_name", slot_name)
			var name_label = Label.new()
			name_label.text = "  " + String(part.get("name", "Unknown Part"))
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var change_btn = Button.new()
			change_btn.name = "SwapButton"
			change_btn.text = "Swap…"
			change_btn.custom_minimum_size.y = 30
			_style_swap_button(change_btn, slot_name)
			change_btn.pressed.connect(_on_swap_part_pressed.bind(slot_name, part))
			row.add_child(name_label)
			row.add_child(change_btn)
			parts_vbox.add_child(row)

func _refresh_slot_vendor_availability():
	_slot_vendor_availability.clear()
	# Build a set of slots that have at least one vendor part available in the current settlement
	var slot_set := {}
	var slots: Array = []
	# Scan a sample of common slots from installed parts to reduce work
	if _selected_vehicle_idx >= 0 and _selected_vehicle_idx < _vehicles.size():
		var v = _vehicles[_selected_vehicle_idx]
		for p in v.get("parts", []):
			var s = String(p.get("slot", ""))
			if not s.is_empty() and not slot_set.has(s):
				slot_set[s] = true
				slots.append(s)
		for c in v.get("cargo", []):
			if c is Dictionary and c.get("intrinsic_part_id") != null:
				var cs = String(c.get("slot", ""))
				if not cs.is_empty() and not slot_set.has(cs):
					slot_set[cs] = true
					slots.append(cs)
	# For each slot, check vendor parts
	for s in slots:
		var vendor_parts = _collect_vendor_parts_for_slot(s)
		_slot_vendor_availability[s] = not vendor_parts.is_empty()
	_slot_vendor_availability.clear()
	# Build a set of slots to track; initialize to false (we'll flip to true when backend confirms)
	var slot_set2 := {}
	var slots2: Array = []
	if _selected_vehicle_idx >= 0 and _selected_vehicle_idx < _vehicles.size():
		var v = _vehicles[_selected_vehicle_idx]
		for p in v.get("parts", []):
			var s_val = p.get("slot", "")
			var s: String = s_val if typeof(s_val) == TYPE_STRING else ""
			if s != "" and not slot_set2.has(s):
				slot_set2[s] = true
				slots2.append(s)
		for c in v.get("cargo", []):
			if c is Dictionary and c.get("intrinsic_part_id") != null:
				var cs_val = c.get("slot", "")
				var cs: String = cs_val if typeof(cs_val) == TYPE_STRING else ""
				if cs != "" and not slot_set2.has(cs):
					slot_set2[cs] = true
					slots2.append(cs)
	for s in slots2:
		_slot_vendor_availability[s] = false

func _restyle_swap_buttons_for_slot(slot_name: String) -> void:
	for child in parts_vbox.get_children():
		if child is HBoxContainer and child.has_meta("slot_name") and String(child.get_meta("slot_name")) == slot_name:
			var swap_btn: Button = child.get_child(child.get_child_count()-1) if child.get_child_count() > 0 else null
			if swap_btn is Button:
				_style_swap_button(swap_btn, slot_name)

func _start_vendor_compat_checks_for_vehicle(vehicle: Dictionary) -> void:
	# For each tracked slot, request backend compatibility for vendor parts at this settlement
	var vehicle_id: String = str(vehicle.get("vehicle_id", ""))
	if vehicle_id == "":
		return
	for s in _slot_vendor_availability.keys():
		var vendor_parts = _collect_vendor_parts_for_slot(s)
		for entry in vendor_parts:
			var cand: Dictionary = entry.get("part", {})
			var cid_val = cand.get("cargo_id", null)
			if typeof(cid_val) != TYPE_STRING or cid_val == "":
				continue
			var cid: String = cid_val
			_cargo_to_slot[cid] = s
			if _compat_cache.has(cid):
				var cached: Dictionary = _compat_cache[cid]
				var ok := false
				var data: Dictionary = cached.get("data", {}) if cached.get("data") is Dictionary else {}
				if data.has("compatible"):
					ok = bool(data.get("compatible"))
				elif data.has("fitment") and data.get("fitment") is Dictionary and data.fitment.has("compatible"):
					ok = bool(data.fitment.get("compatible"))
				if ok and not bool(_slot_vendor_availability.get(s, false)):
					_slot_vendor_availability[s] = true
					_restyle_swap_buttons_for_slot(s)
				continue
			if is_instance_valid(_gdm):
				print("[PartCompatUI] REQUEST vehicle=", vehicle_id, " slot=", s, " cargo_id=", cid)
				_gdm.request_part_compatibility(vehicle_id, cid)

func _style_swap_button(btn: Button, slot_name: String):
	var available: bool = bool(_slot_vendor_availability.get(slot_name, false))
	if available:
		# Soft green highlight with border
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.25, 0.12, 1.0)
		sb.border_color = Color(0.35, 0.8, 0.35, 1.0)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
		btn.tooltip_text = "Vendor has parts for this slot"
		if is_instance_valid(vendor_hint_label): vendor_hint_label.visible = true
	else:
		# Default style; keep tooltip blank
		btn.remove_theme_stylebox_override("normal")
		btn.remove_theme_color_override("font_color")

func _rebuild_pending_tab():
	for c in pending_vbox.get_children():
		c.queue_free()
	if _pending_swaps.is_empty():
		_show_info(pending_vbox, "No pending changes. Select Swap… to choose a replacement part.")
		return
	var total_cost: float = 0.0
	for swap in _pending_swaps:
		var line = HBoxContainer.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label = Label.new()
		var from_n = String(swap.get("from_part", {}).get("name", "Old"))
		var to_n = String(swap.get("to_part", {}).get("name", "New"))
		var src = String(swap.get("source", "inventory"))
		var price = float(swap.get("price", 0.0))
		label.text = "%s: %s → %s%s" % [swap.get("slot","slot").capitalize(), from_n, to_n, (" (Buy $%d)" % int(price)) if src == "vendor" and price > 0.0 else ""]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var remove_btn = Button.new()
		remove_btn.text = "Remove"
		remove_btn.pressed.connect(func():
			_pending_swaps.erase(swap)
			_rebuild_pending_tab()
			_refresh_apply_state()
		)
		line.add_child(label)
		line.add_child(remove_btn)
		pending_vbox.add_child(line)
		total_cost += price
	var total_label = Label.new()
	total_label.text = "\nEstimated Cost: $%d" % int(total_cost)
	total_label.add_theme_font_size_override("font_size", 16)
	pending_vbox.add_child(total_label)
	_refresh_apply_state()

func _on_swap_part_pressed(slot_name: String, current_part: Dictionary):
	# Pretty chooser with grouping and compatibility hints
	var vehicle
	if _selected_vehicle_idx >= 0 and _selected_vehicle_idx < _vehicles.size():
		vehicle = _vehicles[_selected_vehicle_idx]
	else:
		vehicle = {}
	_debug_swap_open_dump(slot_name, current_part, vehicle)

	var chooser = AcceptDialog.new()
	chooser.title = "Swap: " + slot_name.capitalize().replace("_", " ")
	chooser.min_size = Vector2(700, 520)
	var root = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	chooser.add_child(root)
	var veh_id: String = str(vehicle.get("vehicle_id", ""))
	_current_swap_ctx = {"dialog": chooser, "vehicle_id": veh_id, "row_map": {}}

	# Header: current part summary
	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hdr_left = VBoxContainer.new()
	hdr_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_lbl = Label.new()
	title_lbl.text = "Slot: " + slot_name.capitalize().replace("_", " ")
	title_lbl.add_theme_font_size_override("font_size", 18)
	var current_lbl = Label.new()
	current_lbl.text = "Current: " + String(current_part.get("name", "None")) + " " + _part_summary(current_part)
	current_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	hdr_left.add_child(title_lbl)
	hdr_left.add_child(current_lbl)
	header.add_child(hdr_left)
	root.add_child(header)

	var sep = HSeparator.new()
	root.add_child(sep)

	# Lists: Compatible first, then Incompatible
	var compatible_box = VBoxContainer.new()
	compatible_box.add_theme_constant_override("separation", 6)
	var comp_header = Label.new()
	comp_header.text = "Compatible replacements"
	comp_header.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	comp_header.add_theme_font_size_override("font_size", 16)
	compatible_box.add_child(comp_header)

	var incompatible_box = VBoxContainer.new()
	incompatible_box.add_theme_constant_override("separation", 6)
	var incomp_header = Label.new()
	incomp_header.text = "Not compatible"
	incomp_header.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	incomp_header.add_theme_font_size_override("font_size", 16)
	incompatible_box.add_child(incomp_header)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lists_vb = VBoxContainer.new()
	lists_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists_vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lists_vb.add_child(compatible_box)
	lists_vb.add_child(HSeparator.new())
	lists_vb.add_child(incompatible_box)
	scroll.add_child(lists_vb)
	root.add_child(scroll)

	var all_candidates: Array = []
	for c in _collect_candidate_parts_for_slot(slot_name):
		all_candidates.append({"part": c, "source": "inventory", "price": 0.0})
	for v in _collect_vendor_parts_for_slot(slot_name):
		all_candidates.append(v) # expects {part, source:"vendor", price}

	# Kick off compatibility checks for each candidate using backend, log responses when they arrive
	var vehicle_id: String = str(vehicle.get("vehicle_id", ""))
	if is_instance_valid(_gdm) and not vehicle_id.is_empty():
		for entry in all_candidates:
			var cand: Dictionary = entry.get("part", {})
			var cargo_id: String = str(cand.get("cargo_id", ""))
			if cargo_id == "":
				continue
			if not _compat_cache.has(cargo_id):
				_gdm.request_part_compatibility(vehicle_id, cargo_id)

	if all_candidates.is_empty():
		var none = Label.new()
		none.text = "No parts found for this slot in convoy inventory or shop."
		root.add_child(none)
	else:
		for entry in all_candidates:
			var cand: Dictionary = entry.get("part", {})
			var source: String = String(entry.get("source", "inventory"))
			var price: float = float(entry.get("price", 0.0))
			# Temporarily rely on existing UI grouping, but backend results will be printed for accuracy
			var comp_ok := _is_part_compatible(vehicle, slot_name, cand)
			var row = _make_candidate_row(cand, source, price, comp_ok)
			var cid2: String = str(cand.get("cargo_id", ""))
			if cid2 != "":
				_current_swap_ctx["row_map"][cid2] = row
			if comp_ok:
				# attach select handler
				var select_btn: Button = row.get_node_or_null("SelectBtn")
				if is_instance_valid(select_btn):
					select_btn.pressed.connect(func():
						_add_pending_swap(slot_name, current_part, cand, source, price)
						chooser.queue_free()
						_rebuild_pending_tab()
					)
				compatible_box.add_child(row)
			else:
				# annotate with reason
				var reason = _compat_reason(vehicle, slot_name, cand)
				row.tooltip_text = reason
				var select_btn_in: Button = row.get_node_or_null("SelectBtn")
				if is_instance_valid(select_btn_in):
					select_btn_in.disabled = true
				incompatible_box.add_child(row)

	get_tree().root.add_child(chooser)
	chooser.popup_centered_ratio(0.8)
	chooser.connect("confirmed", Callable(chooser, "queue_free"))
	chooser.connect("popup_hide", Callable(chooser, "queue_free"))
	chooser.connect("popup_hide", func():
		_current_swap_ctx.clear()
	)

func _collect_candidate_parts_for_slot(slot_name: String) -> Array:
	var out: Array = []
	# Collect from all vehicles' cargo for now; later narrow to convoy-wide inventory
	for v in _vehicles:
		var cargo: Array = v.get("cargo", [])
		for item in cargo:
			if item is Dictionary and item.get("slot", "") == slot_name and item.get("intrinsic_part_id") == null:
				# Not currently installed (no intrinsic id) and matches slot
				out.append(item)
	return out

func _collect_vendor_parts_for_slot(slot_name: String) -> Array:
	# Return items as [{ part: Dictionary, source: "vendor", price: float }]
	var results: Array = []
	if _gdm == null:
		_gdm = get_node_or_null("/root/GameDataManager")
	if _gdm == null:
		return results

	# Locate the current settlement by convoy coordinates
	var sx := int(roundf(float(_convoy.get("x", -99999.0))))
	var sy := int(roundf(float(_convoy.get("y", -99999.0))))
	var settlements: Array = []
	if _gdm.has_method("get_all_settlements_data"):
		settlements = _gdm.get_all_settlements_data()
	if settlements.is_empty():
		print("[PartCompatUI] No settlements loaded; cannot collect vendor parts for slot=", slot_name, " at (", sx, ",", sy, ")")

	var settlement_match: Dictionary = {}
	for s in settlements:
		if not (s is Dictionary):
			continue
		if int(s.get("x", 123456)) == sx and int(s.get("y", 123456)) == sy:
			settlement_match = s
			break

	if settlement_match.is_empty():
		print("[PartCompatUI] No settlement match at (", sx, ",", sy, ") while collecting vendor parts for slot=", slot_name)
		return results

	# Scan vendors at this settlement
	var vendors: Array = settlement_match.get("vendors", [])
	if vendors.is_empty():
		print("[PartCompatUI] Settlement has no vendors at (", sx, ",", sy, ")")
	for vendor in vendors:
		if not (vendor is Dictionary):
			continue
		var cargo_inv: Array = vendor.get("cargo_inventory", [])
		for item in cargo_inv:
			if not (item is Dictionary):
				continue
			if item.get("intrinsic_part_id") != null:
				continue # skip intrinsic-installed markers

			var price_f := _extract_price_from_dict(item)
			# Case 1: top-level part (has slot)
			if item.has("slot") and item.get("slot") != null and String(item.get("slot")).length() > 0:
				if String(item.get("slot")) == slot_name:
					results.append({"part": item, "source": "vendor", "price": price_f})
				continue

			# Case 2: container with nested parts[]
			if item.has("parts") and item.get("parts") is Array and not (item.get("parts") as Array).is_empty():
				var nested_parts: Array = item.get("parts")
				# Use the first nested part as representative for slot matching
				var first_part: Dictionary = nested_parts[0]
				var slot_val = first_part.get("slot", "")
				var pslot: String = slot_val if typeof(slot_val) == TYPE_STRING else ""
				if pslot == slot_name:
					# Prefer the nested part for display (has the stats), but attach the container cargo_id for backend checks/purchases
					var display_part: Dictionary = first_part.duplicate(true)
					var cont_id_val: String = str(item.get("cargo_id", ""))
					if cont_id_val != "":
						display_part["cargo_id"] = cont_id_val
					results.append({"part": display_part, "source": "vendor", "price": price_f})
	if results.is_empty():
		print("[PartCompatUI] No vendor parts found for slot=", slot_name, " at (", sx, ",", sy, ")")
	return results

func _extract_price_from_dict(d: Dictionary) -> float:
	var val = d.get("price")
	if val is float or val is int:
		return float(val)
	var base_val = d.get("base_price")
	if base_val is float or base_val is int:
		return float(base_val)
	var container_val = d.get("container_price")
	if container_val is float or container_val is int:
		return float(container_val)
	return 0.0

func _add_pending_swap(slot_name: String, from_part: Dictionary, to_part: Dictionary, source: String, price: float):
	_pending_swaps.append({
		"slot": slot_name,
		"from_part": from_part.duplicate(true),
		"to_part": to_part.duplicate(true),
		"source": source,
		"price": price,
	})

func _on_apply_pressed():
	if _pending_swaps.is_empty():
		return
	if _selected_vehicle_idx < 0 or _selected_vehicle_idx >= _vehicles.size():
		return
	var vehicle_id = String(_vehicles[_selected_vehicle_idx].get("vehicle_id", ""))
	var convoy_id = String(_convoy.get("convoy_id", ""))
	var total_cost: float = 0.0
	for s in _pending_swaps:
		total_cost += float(s.get("price", 0.0))
	emit_signal("changes_committed", convoy_id, vehicle_id, _pending_swaps.duplicate(true), total_cost)
	# Prototype: just clear changes after emit
	_pending_swaps.clear()
	_rebuild_pending_tab()

func _make_candidate_row(part: Dictionary, source: String, price: float, compatible: bool) -> HBoxContainer:
	var hb = HBoxContainer.new()
	hb.name = "Row"
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 8)
	# Track cargo id on the row for later updates
	var mid_val = part.get("cargo_id", null)
	if typeof(mid_val) == TYPE_STRING and mid_val != "":
		var cargo_id: String = mid_val
		hb.set_meta("cargo_id", cargo_id)

	# Source badge
	var badge = Label.new()
	badge.text = source.capitalize()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.35, 0.15, 1.0) if source == "vendor" else Color(0.15, 0.25, 0.35, 1.0)
	sb.border_color = Color(0.8, 0.8, 0.9)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	badge.add_theme_stylebox_override("normal", sb)
	badge.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	badge.custom_minimum_size = Vector2(80, 26)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(badge)

	# Name + summary
	var name_lbl = Label.new()
	name_lbl.text = String(part.get("name", "Part")) + " " + _part_summary(part)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	hb.add_child(name_lbl)

	# Compatibility status label (updated asynchronously from backend)
	var compat_lbl = Label.new()
	compat_lbl.name = "CompatLabel"
	compat_lbl.text = "Checking…"
	compat_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	compat_lbl.tooltip_text = "Awaiting backend check"
	hb.add_child(compat_lbl)

	# Price (if vendor)
	if source == "vendor":
		var price_lbl = Label.new()
		price_lbl.text = "$%d" % int(price) if price > 0.0 else "$—"
		price_lbl.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
		hb.add_child(price_lbl)

	# Select button
	var btn = Button.new()
	btn.name = "SelectBtn"
	btn.text = "Select" if compatible else "Incompatible"
	hb.add_child(btn)
	return hb

func _update_row_from_compat_payload(payload: Dictionary) -> void:
	if _current_swap_ctx.is_empty():
		return
	var vehicle_id_ctx: String = str(_current_swap_ctx.get("vehicle_id", ""))
	var vid: String = str(payload.get("vehicle_id", ""))
	if vehicle_id_ctx == "" or vid == "" or vid != vehicle_id_ctx:
		return
	var cid: String = str(payload.get("part_cargo_id", ""))
	if cid == "":
		return
	var row_map: Dictionary = _current_swap_ctx.get("row_map", {})
	if not row_map.has(cid):
		return
	var row: HBoxContainer = row_map[cid]
	if not is_instance_valid(row):
		return
	var compat_lbl: Label = row.get_node_or_null("CompatLabel")
	var btn: Button = row.get_node_or_null("SelectBtn")
	var data: Dictionary = payload.get("data", {}) if payload.get("data") is Dictionary else {}
	var compatible := false
	var reason := ""
	if data.has("compatible"):
		compatible = bool(data.get("compatible"))
	elif data.has("fitment") and data.get("fitment") is Dictionary and data.fitment.has("compatible"):
		compatible = bool(data.fitment.get("compatible"))
		reason = String(data.fitment.get("reason", ""))
	if is_instance_valid(compat_lbl):
		compat_lbl.text = "Compatible" if compatible else "Not compatible"
		compat_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if compatible else Color(1.0, 0.6, 0.6))
		if reason != "":
			compat_lbl.tooltip_text = reason
		else:
			compat_lbl.tooltip_text = ""
	if is_instance_valid(btn):
		btn.text = "Select" if compatible else "Incompatible"
		btn.disabled = not compatible

func _part_summary(part: Dictionary) -> String:
	var bits: Array[String] = []
	var keys = ["top_speed_add", "efficiency_add", "offroad_capability_add", "cargo_capacity_add", "weight_capacity_add"]
	var labels = {"top_speed_add": "Spd", "efficiency_add": "Eff", "offroad_capability_add": "Off", "cargo_capacity_add": "Cargo", "weight_capacity_add": "Weight"}
	for k in keys:
		var v = part.get(k, null)
		if v != null and float(v) != 0.0:
			bits.append("%s %+.0f" % [labels.get(k, k), float(v)])
	if part.has("fuel_capacity") and part.fuel_capacity:
		bits.append("FuelCap %.0f" % float(part.fuel_capacity))
	if part.has("kwh_capacity") and part.kwh_capacity:
		bits.append("kWh %.0f" % float(part.kwh_capacity))
	return "" if bits.is_empty() else "(" + ", ".join(bits) + ")"

func _is_part_compatible(vehicle: Dictionary, slot_name: String, part: Dictionary) -> bool:
	# Baseline rule: slot must match and part must be removable/bolt-on if required
	if String(part.get("slot", "")) != slot_name:
		return false
	# If part has explicit requirements, attempt a naive check
	if part.has("requirements") and part.requirements is Array and not (part.requirements as Array).is_empty():
		# Look for simple string requirements that match vehicle fields (model/class) if present
		var reqs: Array = part.requirements
		var vmodel = String(vehicle.get("make_model", vehicle.get("model", ""))).to_lower()
		for r in reqs:
			if r is String and not r.is_empty():
				var rlow = r.to_lower()
				if vmodel.find(rlow) == -1:
					return false
	return true

func _compat_reason(_vehicle: Dictionary, slot_name: String, part: Dictionary) -> String:
	if String(part.get("slot", "")) != slot_name:
		return "Different slot (needs %s)." % slot_name
	if part.has("requirements") and part.requirements is Array and not (part.requirements as Array).is_empty():
		return "Doesn't meet part requirements."
	return "Not compatible with this vehicle."

func _debug_snippet(data: Variant, label: String="", max_chars: int = 1500) -> void:
	var encoded := JSON.stringify(data, "  ")
	if encoded.length() > max_chars:
		encoded = encoded.substr(0, max_chars) + "...<truncated>"
	if label != "":
		print("[MechanicsMenu][DEBUG] ", label, " = ", encoded)
	else:
		print("[MechanicsMenu][DEBUG] ", encoded)

func _debug_swap_open_dump(slot_name: String, current_part: Dictionary, vehicle: Dictionary) -> void:
	print("\n==== Mechanics Swap Debug ====")
	_debug_snippet({
		"slot": slot_name,
		"vehicle_id": (vehicle.get("vehicle_id", "") if typeof(vehicle.get("vehicle_id", "")) == TYPE_STRING else ""),
		"vehicle_make_model": vehicle.get("make_model", vehicle.get("model", "")),
	}, "Context")
	_debug_snippet(current_part, "Current Part")
	var inv_cands = _collect_candidate_parts_for_slot(slot_name)
	_debug_snippet({
		"inventory_candidates_count": inv_cands.size(),
		"first_two": inv_cands.slice(0, min(2, inv_cands.size()))
	}, "Inventory Candidates")
	var vend_cands = _collect_vendor_parts_for_slot(slot_name)
	_debug_snippet({
		"vendor_candidates_count": vend_cands.size(),
		"first_two": vend_cands.slice(0, min(2, vend_cands.size()))
	}, "Vendor Candidates")

func _clear_parts_ui():
	for c in parts_vbox.get_children():
		c.queue_free()

func _show_info(where: VBoxContainer, text: String):
	var l = Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	where.add_child(l)

func _refresh_apply_state():
	var has_changes = not _pending_swaps.is_empty()
	apply_button.disabled = not has_changes

func _on_part_compatibility_ready(payload: Dictionary) -> void:
	# Cache result and log with a clear keyword for filtering
	var part_cargo_id := str(payload.get("part_cargo_id", ""))
	if part_cargo_id != "":
		_compat_cache[part_cargo_id] = payload
	# Dual logs: concise keyword + structured snippet
	print("[PartCompatUI] payload=", payload)
	_debug_snippet(payload, "PartCompatUI.payload")
	_update_row_from_compat_payload(payload)

func _on_mechanic_vendor_slot_availability(vehicle_id: String, slot_availability: Dictionary) -> void:
	# Only apply for the currently selected vehicle
	if _selected_vehicle_idx < 0 or _selected_vehicle_idx >= _vehicles.size():
		return
	var sel_v = _vehicles[_selected_vehicle_idx]
	var vid: String = str(sel_v.get("vehicle_id", ""))
	if vid == "" or vehicle_id != vid:
		return
	# Merge availability and restyle
	for s in slot_availability.keys():
		var flag := bool(slot_availability[s])
		if flag and not bool(_slot_vendor_availability.get(s, false)):
			_slot_vendor_availability[s] = true
			_restyle_swap_buttons_for_slot(s)
