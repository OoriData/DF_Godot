extends MenuBase

# Signals
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
@onready var _overlay: ColorRect = $ColorRect

# State
var _convoy: Dictionary = {}
var _vehicles: Array = []
var _selected_vehicle_idx: int = -1

# Pending swaps: [{slot, from_part, to_part, source: "inventory"|"vendor", price: float}]
var _pending_swaps: Array = []
var _slot_vendor_availability: Dictionary = {}
var _slot_inventory_availability: Dictionary = {} # highlights when convoy cargo has compatible upgrade
var _compat_cache: Dictionary = {} # key: vehicle_id||part_cargo_id -> payload
var _current_swap_ctx: Dictionary = {} # { dialog: AcceptDialog, vehicle_id: String, row_map: { part_cargo_id: HBoxContainer } }
var _cargo_to_slot: Dictionary = {} # cargo_id -> slot_name for vendor candidates
var _all_vendor_candidates_cache: Array = [] # cached vendor part candidates at current settlement
var _install_price_cache: Dictionary = {} # key: vehicle_id||part_uid -> float

# Developer toggle: when true, emit detailed cost audit lines to the console
var _cost_audit_enabled: bool = true
var _show_cost_breakdown: bool = false
var _breakdown_toggle: CheckButton = null

# When embedded inside another menu/tab, we hide redundant chrome.
var embedded_mode: bool = false

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _hub: Node = get_node_or_null("/root/SignalHub")
@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _mechanics_service: Node = get_node_or_null("/root/MechanicsService")
@onready var _convoy_service: Node = get_node_or_null("/root/ConvoyService")

func set_embedded_mode(val: bool) -> void:
	embedded_mode = val
	_apply_embedded_mode_visibility()

func _apply_embedded_mode_visibility() -> void:
	# Hide header and vehicle selector when embedded to match Vehicle menu tab style
	if is_instance_valid(title_label):
		title_label.visible = not embedded_mode
	if is_instance_valid(vehicle_option_button):
		vehicle_option_button.visible = not embedded_mode
	# Back button is redundant inside a tab; keep Apply visible
	if is_instance_valid(back_button):
		back_button.visible = not embedded_mode
	# Remove dark overlay when embedded inside a tab for visual consistency
	if is_instance_valid(_overlay):
		_overlay.visible = not embedded_mode

	# Adjust margins to remove double-padding when embedded
	var main_vbox: VBoxContainer = $MainVBox
	if is_instance_valid(main_vbox):
		if embedded_mode:
			main_vbox.offset_left = 0
			main_vbox.offset_top = 0
			main_vbox.offset_right = 0
			main_vbox.offset_bottom = 0
		else: # Restore default margins for standalone mode
			main_vbox.offset_left = 10
			main_vbox.offset_top = 10
			main_vbox.offset_right = -10
			main_vbox.offset_bottom = -10

func _get_slot_from_item(item: Dictionary) -> String:
	# Accept alternative slot key names; backend may vary
	var keys := ["slot", "slot_name", "slotType"]
	for k in keys:
		if item.has(k) and item.get(k) != null:
			var v = item.get(k)
			if typeof(v) == TYPE_STRING and String(v) != "":
				return String(v)
	return ""

# Resolve a slot for a cargo item using multiple sources: direct, nested parts[0], then simple heuristics
func _detect_slot_for_item(item: Dictionary) -> String:
	if not (item is Dictionary):
		return ""
	# 1) Direct keys on item
	var s := _get_slot_from_item(item)
	if s != "":
		return s
	# 2) Nested parts array (containers)
	if item.has("parts") and (item.get("parts") is Array):
		var parts_arr: Array = item.get("parts")
		if not parts_arr.is_empty() and (parts_arr[0] is Dictionary):
			var s2 := _get_slot_from_item(parts_arr[0])
			if s2 != "":
				return s2
	# 3) Basic local heuristic for common items like tires/wheels
	var nm := String(item.get("name", "")).to_lower()
	if nm.find("tire") != -1 or nm.find("tyre") != -1:
		return "tires"
	if nm.find("wheel") != -1:
		return "wheels"
	return ""

# Given a cargo item, return the dictionary to display in the chooser (prefers nested part or enriched copy),
# always carrying cargo_id.
func _resolve_display_part_for_item(item: Dictionary) -> Dictionary:
	if not (item is Dictionary):
		return {}
	var cid_any: String = String(item.get("cargo_id", ""))
	if cid_any == "":
		cid_any = String(item.get("part_id", ""))
	# Prefer nested part when available (copy and attach cargo_id)
	if item.has("parts") and (item.get("parts") is Array):
		var parts_arr: Array = item.get("parts")
		if not parts_arr.is_empty() and (parts_arr[0] is Dictionary):
			var disp: Dictionary = (parts_arr[0] as Dictionary).duplicate(true)
			if cid_any != "":
				disp["cargo_id"] = cid_any
			return disp
	# Fallback to original item (ensure cargo_id retained)
	var base: Dictionary = item.duplicate(true)
	if cid_any != "":
		base["cargo_id"] = cid_any
	return base

# Unique ID helpers for deduping and pricing
func _install_cache_key(vehicle_id: String, part_uid: String) -> String:
	return "%s||%s" % [vehicle_id, part_uid]

func _get_install_price_from_cache(vehicle_id: String, part_uid: String) -> float:
	var key := _install_cache_key(vehicle_id, part_uid)
	return float(_install_price_cache.get(key, 0.0))

func _set_install_price(vehicle_id: String, part_uid: String, price: float) -> void:
	if vehicle_id == "" or part_uid == "":
		return
	var key := _install_cache_key(vehicle_id, part_uid)
	_install_price_cache[key] = float(price)
	# Update any open chooser row
	if not _current_swap_ctx.is_empty():
		var row_map: Dictionary = _current_swap_ctx.get("row_map", {})
		if row_map.has(part_uid):
			var row: HBoxContainer = row_map[part_uid]
			if is_instance_valid(row):
				_update_row_price_from_cache(row)
	# Update any pending swap entries
	_refresh_pending_prices_for_part(vehicle_id, part_uid)

func _log_cost_audit(tag: String, fields: Dictionary) -> void:
	if not _cost_audit_enabled:
		return
	var payload := fields.duplicate(true)
	payload["tag"] = tag
	print("[CostAudit] ", JSON.stringify(payload))

func _estimate_install_price(vehicle_id: String, part: Dictionary) -> float:
	# Simple one-off estimate using current vehicle value (does NOT include speculative earlier cart changes).
	# For cart sequencing we compute a more accurate stepwise projection in _compute_pending_schedules().
	if _is_part_removable(part):
		return 0.0
	if vehicle_id == "":
		return 0.0
	var v10: float = _get_vehicle_value(vehicle_id) * 0.10
	var p25: float = _get_part_value(part) * 0.25
	return _round_install(v10 + p25)

func _format_price_label(vendor_price: float, install_price: float) -> String:
	var total := vendor_price + install_price
	return "Part $%s + Installation $%s = $%s" % ["%.2f" % vendor_price, "%.2f" % install_price, "%.2f" % total]


func _make_breakdown_text(vehicle_id: String, part: Dictionary, install_price: float, use_server: bool) -> String:
	if not _show_cost_breakdown:
		return ""
	if vehicle_id == "" or part.is_empty():
		return ""
	var v10: float = _get_vehicle_value(vehicle_id) * 0.10
	var p25: float = _get_part_value(part) * 0.25
	var round_note := "banker’s" # ties-to-even
	var source := "server" if use_server else "estimate"
	return "(10%%=$%s, 25%%=$%s, %s: $%s, %s)" % ["%.0f" % v10, "%.0f" % p25, source, "%.0f" % install_price, round_note]

func _attach_or_update_breakdown_label(row: HBoxContainer, text: String) -> void:
	if not is_instance_valid(row):
		return
	var existing: Label = row.get_node_or_null("BreakdownLabel")
	if not _show_cost_breakdown:
		if is_instance_valid(existing):
			existing.queue_free()
		return
	if not is_instance_valid(existing):
		var lbl = Label.new()
		lbl.name = "BreakdownLabel"
		lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		# Insert before the SelectBtn at the end
		var insert_at: int = max(0, row.get_child_count() - 1)
		row.add_child(lbl)
		row.move_child(lbl, insert_at)
		existing = lbl
	existing.text = text

func _update_all_breakdown_labels() -> void:
	# Update any open chooser rows when toggled
	if _current_swap_ctx.is_empty():
		return
	var row_map: Dictionary = _current_swap_ctx.get("row_map", {})
	for k in row_map.keys():
		var row: HBoxContainer = row_map[k]
		if not is_instance_valid(row):
			continue
		var veh_id := String(row.get_meta("vehicle_id", "")) if row.has_meta("vehicle_id") else ""
		var part_uid := String(row.get_meta("part_uid", "")) if row.has_meta("part_uid") else ""
		var part_dict: Dictionary = row.get_meta("part_dict", {}) if row.has_meta("part_dict") else {}
		var server_val := _get_install_price_from_cache(veh_id, part_uid)
		var use_server := server_val > 0.0
		var install_price := server_val if use_server else _estimate_install_price(veh_id, part_dict)
		var text := _make_breakdown_text(veh_id, part_dict, install_price, use_server)
		_attach_or_update_breakdown_label(row, text)

func _update_row_price_from_cache(row: HBoxContainer) -> void:
	if not is_instance_valid(row):
		return
	var price_lbl: Label = row.get_node_or_null("PriceLabel")
	if not is_instance_valid(price_lbl):
		return
	var vendor_price := 0.0
	if row.has_meta("vendor_price"):
		vendor_price = float(row.get_meta("vendor_price", 0.0))
	if vendor_price <= 0.0 and row.has_meta("part_dict"):
		# Try vendor listing style fields
		vendor_price = _extract_price_from_dict(row.get_meta("part_dict", {}))
	# Final fallback for vendor-sourced rows: intrinsic part value
	if vendor_price <= 0.0 and row.has_meta("source") and String(row.get_meta("source", "")) == "vendor" and row.has_meta("part_dict"):
		var pd_fallback: Dictionary = row.get_meta("part_dict", {})
		vendor_price = _get_part_value(pd_fallback)
	var veh_id := String(row.get_meta("vehicle_id", ""))
	var part_uid := String(row.get_meta("part_uid", ""))
	var install_price := _get_install_price_from_cache(veh_id, part_uid)
	# Fallback to estimation if cache isn't available: 10% of current vehicle value + 25% of abs(part.value) for non-removable; 0 for removable
	if install_price <= 0.0:
		var part_ctx: Dictionary = row.get_meta("part_dict", {}) if row.has_meta("part_dict") else {}
		var removable := _is_part_removable(part_ctx)
		if removable:
			install_price = 0.0
		elif veh_id != "":
			install_price = _estimate_install_price(veh_id, part_ctx)
			_log_cost_audit("row_update_fallback", {
				"vehicle_id": veh_id,
				"part_uid": part_uid,
				"removable": removable,
				"vehicle_value": _get_vehicle_value(veh_id),
				"part_value": _get_part_value(part_ctx),
				"install_price": install_price,
			})
	# If this row represents an inventory part, only show installation cost; otherwise show full vendor breakdown
	var src := String(row.get_meta("source", "")) if row.has_meta("source") else ""
	if src != "vendor":
		price_lbl.text = "Installation $%s" % ["%.2f" % install_price]
	else:
		var price_text := _format_price_label(vendor_price, install_price)
		price_lbl.text = price_text
	# Update breakdown label for this row if enabled
	var part_ctx2: Dictionary = row.get_meta("part_dict", {}) if row.has_meta("part_dict") else {}
	var use_server2 := _get_install_price_from_cache(veh_id, part_uid) > 0.0
	var breakdown_txt2 := _make_breakdown_text(veh_id, part_ctx2, install_price, use_server2)
	_attach_or_update_breakdown_label(row, breakdown_txt2)

func _refresh_pending_prices_for_part(vehicle_id: String, part_uid: String) -> void:
	# If any pending entries match this part and vehicle, refresh the pending UI
	for s in _pending_swaps:
		var vid := String(s.get("vehicle_id", ""))
		if vid != vehicle_id:
			continue
		var to_p: Dictionary = s.get("to_part", {})
		if _get_part_unique_id(to_p) == part_uid:
			_rebuild_pending_tab()
			return

func _maybe_cache_install_price_from_payload(payload: Dictionary) -> void:
	var vehicle_id := String(payload.get("vehicle_id", ""))
	var part_uid := String(payload.get("part_cargo_id", ""))
	if vehicle_id == "" or part_uid == "":
		return
	var data_any = payload.get("data")
	var install_price := -1.0
	if data_any is Dictionary and (data_any as Dictionary).has("installation_price"):
		install_price = float((data_any as Dictionary).get("installation_price", 0.0))
	elif data_any is Array and (data_any as Array).size() > 0:
		var first = (data_any as Array)[0]
		if first is Dictionary and (first as Dictionary).has("installation_price"):
			install_price = float((first as Dictionary).get("installation_price", 0.0))
	if install_price >= 0.0:
		_set_install_price(vehicle_id, part_uid, install_price)
		# Try to enrich with part name/slot/value from payload or current row map
		var part_name := ""
		var part_slot := ""
		var part_val_log := 0.0
		if data_any is Dictionary:
			if (data_any as Dictionary).has("name"): part_name = String((data_any as Dictionary).get("name", ""))
			if (data_any as Dictionary).has("slot"): part_slot = String((data_any as Dictionary).get("slot", ""))
			if (data_any as Dictionary).has("value"): part_val_log = float((data_any as Dictionary).get("value", 0.0))
		elif data_any is Array and (data_any as Array).size() > 0 and (data_any[0] is Dictionary):
			var d0: Dictionary = data_any[0]
			if d0.has("name"): part_name = String(d0.get("name", ""))
			if d0.has("slot"): part_slot = String(d0.get("slot", ""))
			if d0.has("value"): part_val_log = float(d0.get("value", 0.0))
		# Fall back to current chooser row_map if open
		if part_name == "" or part_slot == "" or part_val_log == 0.0:
			if not _current_swap_ctx.is_empty():
				var row_map2: Dictionary = _current_swap_ctx.get("row_map", {})
				if row_map2.has(part_uid):
					var row2: HBoxContainer = row_map2[part_uid]
					if is_instance_valid(row2) and row2.has_meta("part_dict"):
						var pd: Dictionary = row2.get_meta("part_dict", {})
						if part_name == "" and pd.has("name"): part_name = String(pd.get("name", ""))
						if part_slot == "" and pd.has("slot"): part_slot = String(pd.get("slot", ""))
						if part_val_log == 0.0 and pd.has("value") and pd.get("value") != null:
							part_val_log = float(pd.get("value", 0.0))
		_log_cost_audit("server_install_price", {
			"vehicle_id": vehicle_id,
			"part_uid": part_uid,
			"server_install_price": install_price,
			"part_name": part_name,
			"slot": part_slot,
			"part_value": part_val_log,
		})

# Summarize stat deltas between parts for quick UI badges
func _delta_sign(v: float) -> String:
	return "+" if v > 0.0 else ("-" if v < 0.0 else "")

func _part_delta_summary(from_part: Dictionary, to_part: Dictionary) -> String:
	var keys = [
		"top_speed_add",
		"efficiency_add",
		"offroad_capability_add",
		"cargo_capacity_add",
		"weight_capacity_add",
		"fuel_capacity",
		"kwh_capacity",
	]
	var labels = {
		"top_speed_add": "Spd",
		"efficiency_add": "Eff",
		"offroad_capability_add": "Off",
		"cargo_capacity_add": "Volume",
		"weight_capacity_add": "Weight",
		"fuel_capacity": "Fuel",
		"kwh_capacity": "kWh",
	}
	var bits: Array[String] = []
	for k in keys:
		var from_v := 0.0
		var to_v := 0.0
		if from_part.has(k) and from_part.get(k) != null:
			from_v = float(from_part.get(k))
		if to_part.has(k) and to_part.get(k) != null:
			to_v = float(to_part.get(k))
		var delta := to_v - from_v
		if abs(delta) >= 0.5:
			var sym = _delta_sign(delta)
			var num = abs(delta)
			bits.append("%s %s%.0f" % [labels.get(k, k), sym, num])
	return ", ".join(bits)

func _create_styled_part_row(part: Dictionary, slot_name: String, item_index: int) -> HBoxContainer:
	var outer_row := HBoxContainer.new()
	outer_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_row.mouse_filter = Control.MOUSE_FILTER_PASS
	outer_row.set_meta("slot_name", slot_name) # Keep meta for styling

	var bg_panel := PanelContainer.new()
	bg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	if item_index % 2 == 0:
		sb.bg_color = Color(0.13, 0.15, 0.19, 0.8)
	else:
		sb.bg_color = Color(0.10, 0.12, 0.16, 0.8)
	sb.set_content_margin_all(6)
	bg_panel.add_theme_stylebox_override("panel", sb)
	
	outer_row.add_child(bg_panel)

	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 10)
	bg_panel.add_child(content_row)

	var name_label = Label.new()
	var part_name_text = "  — None installed —" if String(part.get("name", "None")) == "None" else "  " + String(part.get("name", "Unknown Part"))
	name_label.text = part_name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content_row.add_child(name_label)

	var change_btn = Button.new()
	change_btn.name = "SwapButton"
	change_btn.text = "Swap…"
	change_btn.custom_minimum_size.x = 80
	change_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_swap_button(change_btn, slot_name)
	change_btn.pressed.connect(_on_swap_part_pressed.bind(slot_name, part))
	content_row.add_child(change_btn)

	# Hover effect
	outer_row.mouse_entered.connect(func(): sb.bg_color = sb.bg_color.lightened(0.1))
	outer_row.mouse_exited.connect(func():
		sb.bg_color = Color(0.13, 0.15, 0.19, 0.8) if item_index % 2 == 0 else Color(0.10, 0.12, 0.16, 0.8)
	)

	return outer_row

# Unique ID helpers for deduping pending swaps
func _get_part_unique_id(part: Dictionary) -> String:
	var id: String = String(part.get("cargo_id", ""))
	if id == "":
		id = String(part.get("part_id", ""))
	return id

func _is_part_id_already_pending(id: String) -> bool:
	if id == "":
		return false
	for s in _pending_swaps:
		var to_p: Dictionary = s.get("to_part", {})
		var sid := _get_part_unique_id(to_p)
		if sid != "" and sid == id:
			return true
	return false

func _is_part_already_pending(part: Dictionary) -> bool:
	return _is_part_id_already_pending(_get_part_unique_id(part))

func _ready():
	if is_instance_valid(back_button):
		back_button.pressed.connect(func(): emit_signal("back_requested"))
	if is_instance_valid(apply_button):
		apply_button.pressed.connect(_on_apply_pressed)
	if is_instance_valid(vehicle_option_button):
		vehicle_option_button.item_selected.connect(_on_vehicle_selected)
	# If we're embedded in a tab, ensure chrome matches
	_apply_embedded_mode_visibility()
	# Rename the 'Pending' tab to 'Cart' for better UX wording
	_rename_pending_tab_to_cart()
	_refresh_apply_state()
	# Listen for compatibility checks directly from APICalls.
	if is_instance_valid(_api) and _api.has_signal("part_compatibility_checked") and not _api.part_compatibility_checked.is_connected(_on_part_compatibility_ready):
		_api.part_compatibility_checked.connect(_on_part_compatibility_ready)
	# Keep the menu in sync with authoritative convoy snapshots.
	if is_instance_valid(_store) and _store.has_signal("convoys_changed") and not _store.convoys_changed.is_connected(_on_store_convoys_changed):
		_store.convoys_changed.connect(_on_store_convoys_changed)
	# Optional point updates (vendor add can emit convoy dict).
	if is_instance_valid(_hub) and _hub.has_signal("convoy_updated") and not _hub.convoy_updated.is_connected(_on_hub_convoy_updated):
		_hub.convoy_updated.connect(_on_hub_convoy_updated)

	# Add an on-screen developer toggle for cost breakdowns
	var main_vb: VBoxContainer = null
	if is_instance_valid(title_label):
		var p := title_label.get_parent()
		if p is VBoxContainer:
			main_vb = p
	if is_instance_valid(main_vb):
		var row = HBoxContainer.new()
		row.name = "DevTogglesRow"
		row.add_theme_constant_override("separation", 8)
		var cb = CheckButton.new()
		cb.name = "BreakdownToggle"
		cb.text = "Show cost breakdown"
		cb.button_pressed = _show_cost_breakdown
		cb.toggled.connect(func(pressed: bool):
			_show_cost_breakdown = pressed
			_update_all_breakdown_labels()
			_rebuild_pending_tab()
		)
		row.add_child(cb)
		# Insert after the vendor hint label if present; otherwise append before bottom bar
		var inserted := false
		if is_instance_valid(vendor_hint_label):
			var idx := vendor_hint_label.get_index()
			main_vb.add_child(row)
			row.get_parent().move_child(row, idx + 1)
			inserted = true
		if not inserted:
			main_vb.add_child(row)
		_breakdown_toggle = cb

func _rename_pending_tab_to_cart() -> void:
	if not is_instance_valid(tab_container) or not is_instance_valid(pending_scroll):
		return
	var idx := tab_container.get_tab_idx_from_control(pending_scroll)
	if idx >= 0:
		tab_container.set_tab_title(idx, "Cart")

func _close_open_swap_dialog() -> void:
	# Ensure any open swap chooser is closed before we rebuild UI or switch vehicles
	if _current_swap_ctx.is_empty():
		return
	var dlg = _current_swap_ctx.get("dialog", null)
	# Check validity BEFORE type to avoid 'Left operand of "is" is a previously freed instance'
	if is_instance_valid(dlg) and dlg is AcceptDialog:
		(dlg as AcceptDialog).queue_free()
	_current_swap_ctx.clear()

func initialize_with_data(data_or_id: Variant, extra_arg: Variant = null) -> void:
	if data_or_id is Dictionary:
		var d: Dictionary = data_or_id as Dictionary
		convoy_id = String(d.get("convoy_id", d.get("id", "")))
		if not is_node_ready():
			call_deferred("initialize_with_data", d, extra_arg)
			return
		_convoy = d.duplicate(true)
	else:
		convoy_id = String(data_or_id)
		if not is_node_ready():
			call_deferred("initialize_with_data", data_or_id, extra_arg)
			return
		_convoy = {}
	super.initialize_with_data(data_or_id, extra_arg)
	if is_instance_valid(title_label):
		title_label.text = "Mechanic — %s" % _convoy.get("convoy_name", "Convoy")
	_vehicles = _convoy.get("vehicle_details_list", [])
	# Clear vendor candidates so we re-derive them from the latest map snapshot.
	_all_vendor_candidates_cache.clear()
	_populate_vehicle_dropdown()
	if not _vehicles.is_empty():
		if is_instance_valid(vehicle_option_button):
			vehicle_option_button.select(0)
		_on_vehicle_selected(0)

	# If called with a vendor prefill, add the part to the cart immediately
	if data_or_id is Dictionary and (data_or_id as Dictionary).has("_mechanic_prefill") and (data_or_id as Dictionary)._mechanic_prefill is Dictionary:
		var pre: Dictionary = (data_or_id as Dictionary)._mechanic_prefill
		var part: Dictionary = pre.get("part", {})
		var qty: int = int(pre.get("quantity", 1))
		var vendor_id: String = String(pre.get("vendor_id", ""))
		if not part.is_empty():
			# Choose a target vehicle: prefer first compatible one if slot present
			var chosen_vehicle_idx := 0
			var slot_name: String = String(part.get("slot", ""))
			if slot_name == "" and part.has("parts") and part.get("parts") is Array and not (part.get("parts") as Array).is_empty():
				var p0: Dictionary = (part.get("parts") as Array)[0]
				slot_name = String(p0.get("slot", ""))
			# Find a vehicle that has this slot
			if slot_name != "" and not _vehicles.is_empty():
				for i in range(_vehicles.size()):
					var v: Dictionary = _vehicles[i]
					var has_slot := false
					for ip in v.get("parts", []):
						if String(ip.get("slot", "")) == slot_name:
							has_slot = true
							break
					if has_slot:
						chosen_vehicle_idx = i
						break
			# Switch selection if needed
			if chosen_vehicle_idx != _selected_vehicle_idx and chosen_vehicle_idx >= 0 and chosen_vehicle_idx < _vehicles.size():
				set_selected_vehicle_index(chosen_vehicle_idx)
			# Build a minimal from_part by finding currently installed in slot
			var from_part: Dictionary = {}
			if slot_name != "" and _selected_vehicle_idx >= 0 and _selected_vehicle_idx < _vehicles.size():
				for ip2 in _vehicles[_selected_vehicle_idx].get("parts", []):
					if String(ip2.get("slot", "")) == slot_name:
						from_part = ip2
						break
			# Add requested quantity times; prevent duplicates via internal dedupe
			for _i in range(max(1, qty)):
				_add_pending_swap(slot_name if slot_name != "" else "other", from_part, part, "vendor", _extract_price_from_dict(part), vendor_id)
			# Switch to Cart tab
			_rename_pending_tab_to_cart()
			if is_instance_valid(tab_container) and is_instance_valid(pending_scroll):
				var cart_idx := tab_container.get_tab_idx_from_control(pending_scroll)
				if cart_idx >= 0:
					tab_container.current_tab = cart_idx
			_rebuild_pending_tab()
	_refresh_apply_state()

func _exit_tree() -> void:
	# Also ensure any open chooser is closed to avoid dangling node references
	_close_open_swap_dialog()
	# Disconnect update signals to avoid duplicate connections on reopen
	if is_instance_valid(_store) and _store.has_signal("convoys_changed") and _store.convoys_changed.is_connected(_on_store_convoys_changed):
		_store.convoys_changed.disconnect(_on_store_convoys_changed)
	if is_instance_valid(_hub) and _hub.has_signal("convoy_updated") and _hub.convoy_updated.is_connected(_on_hub_convoy_updated):
		_hub.convoy_updated.disconnect(_on_hub_convoy_updated)
	if is_instance_valid(_api) and _api.has_signal("part_compatibility_checked") and _api.part_compatibility_checked.is_connected(_on_part_compatibility_ready):
		_api.part_compatibility_checked.disconnect(_on_part_compatibility_ready)

# Allow parent to set the selected vehicle index directly (to keep tabs in sync)
func set_selected_vehicle_index(idx: int) -> void:
	if _vehicles.is_empty():
		return
	var safe_idx = clamp(idx, 0, _vehicles.size() - 1)
	if safe_idx == _selected_vehicle_idx:
		return
	_selected_vehicle_idx = safe_idx
	if is_instance_valid(vehicle_option_button):
		vehicle_option_button.select(safe_idx)
	_on_vehicle_selected(safe_idx)

func _on_store_convoys_changed(all_convoys: Array) -> void:
	# Refresh this menu when our convoy is updated in the canonical snapshot.
	if _convoy.is_empty():
		return
	var target_id := String(_convoy.get("convoy_id", ""))
	if target_id == "":
		return
	var selected_vehicle_id := ""
	if _selected_vehicle_idx >= 0 and _selected_vehicle_idx < _vehicles.size():
		selected_vehicle_id = String(_vehicles[_selected_vehicle_idx].get("vehicle_id", ""))
	for c in all_convoys:
		if not (c is Dictionary):
			continue
		if String(c.get("convoy_id", "")) == target_id:
			_convoy = (c as Dictionary).duplicate(true)
			_vehicles = _convoy.get("vehicle_details_list", [])
			# Restore previous selection if possible
			var new_index := 0
			if selected_vehicle_id != "":
				for i in range(_vehicles.size()):
					if String(_vehicles[i].get("vehicle_id", "")) == selected_vehicle_id:
						new_index = i
						break
			_populate_vehicle_dropdown()
			if _vehicles.size() > 0:
				_on_vehicle_selected(new_index)
			_refresh_apply_state()
			break

func _on_hub_convoy_updated(updated_convoy: Dictionary) -> void:
	# Best-effort: if a service emitted an updated convoy dict, refresh UI immediately.
	if _convoy.is_empty() or updated_convoy.is_empty():
		return
	var target_id := String(_convoy.get("convoy_id", ""))
	if target_id == "" or String(updated_convoy.get("convoy_id", "")) != target_id:
		return
	_convoy = updated_convoy.duplicate(true)
	_vehicles = _convoy.get("vehicle_details_list", [])
	_populate_vehicle_dropdown()
	if _vehicles.size() > 0:
		var idx: int = int(clamp(_selected_vehicle_idx, 0, _vehicles.size() - 1))
		_on_vehicle_selected(idx if _selected_vehicle_idx >= 0 else 0)
	_refresh_apply_state()

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
	# Close any open chooser tied to previous vehicle to avoid stale node references
	_close_open_swap_dialog()
	# Rebuild UI first, then refresh highlights to avoid touching rows that may be freed
	_rebuild_parts_tab(_vehicles[index])
	# Highlight Swap when convoy cargo has compatible upgrades
	_refresh_slot_inventory_availability()
	_refresh_slot_vendor_availability()
	_rebuild_pending_tab()
	# Fire UI-side vendor compatibility checks immediately for this vehicle for better logs/feedback
	_start_vendor_compat_checks_for_vehicle(_vehicles[index])
	# (Probe removed: compatibility checks are driven via MechanicsService/APICalls)


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

	var part_row_index = 0
	for slot_name in slots_sorted:
		var header = Label.new()
		header.text = slot_name.capitalize().replace("_", " ")
		header.add_theme_font_size_override("font_size", 16)
		header.add_theme_color_override("font_color", Color.YELLOW)
		parts_vbox.add_child(header)

		for part in by_slot[slot_name]:
			var row = _create_styled_part_row(part, slot_name, part_row_index)
			parts_vbox.add_child(row)
			part_row_index += 1
		
		# Add a separator between slot groups
		var sep = HSeparator.new()
		sep.custom_minimum_size.y = 8
		parts_vbox.add_child(sep)

func _refresh_slot_vendor_availability():
	_slot_vendor_availability.clear()
	# Build a set of slots to track for the selected vehicle; initialize to false.
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

	# Restyle all visible rows for these slots to clear any previous highlight
	for s in slots2:
		_restyle_swap_buttons_for_slot(s)

func _refresh_slot_inventory_availability() -> void:
	# Determine which slots have a compatible replacement in convoy cargo for the SELECTED vehicle
	_slot_inventory_availability.clear()
	if _selected_vehicle_idx < 0 or _selected_vehicle_idx >= _vehicles.size():
		return
	var vsel: Dictionary = _vehicles[_selected_vehicle_idx]
	var vid: String = String(vsel.get("vehicle_id", ""))
	# Build slot list from selected vehicle (installed parts and any slot markers in cargo items)
	var slot_set: Dictionary = {}
	var slots: Array = []
	for p in vsel.get("parts", []):
		var s_val = p.get("slot", "")
		var s: String = s_val if typeof(s_val) == TYPE_STRING else ""
		if s != "" and not slot_set.has(s):
			slot_set[s] = true
			slots.append(s)
	for c in vsel.get("cargo", []):
		if c is Dictionary and c.get("intrinsic_part_id") != null:
			var cs_val = c.get("slot", "")
			var cs: String = cs_val if typeof(cs_val) == TYPE_STRING else ""
			if cs != "" and not slot_set.has(cs):
				slot_set[cs] = true
				slots.append(cs)

	# NEW: include slots from ALL convoy cargo items (loose parts) across vehicles
	for v in _vehicles:
		var cargo_all: Array = v.get("cargo", [])
		for item in cargo_all:
			if not (item is Dictionary):
				continue
			if item.get("intrinsic_part_id") != null:
				continue
			var s_detected := _detect_slot_for_item(item)
			if typeof(s_detected) == TYPE_STRING and s_detected != "" and not slot_set.has(s_detected):
				slot_set[s_detected] = true
				slots.append(s_detected)
	# For each slot, scan convoy cargo across ALL vehicles for a compatible part against the selected vehicle
	for s in slots:
		var has_inv_upgrade := false
		for v in _vehicles:
			var cargo: Array = v.get("cargo", [])
			for item in cargo:
				if not (item is Dictionary):
					continue
				# Only consider loose cargo parts (not currently installed markers)
				if item.get("intrinsic_part_id") != null:
					continue
				if _detect_slot_for_item(item) != s:
					continue
				# Prefer backend compatibility cache when available
				var cid_val: String = String(item.get("cargo_id", ""))
				if cid_val == "":
					cid_val = String(item.get("part_id", ""))
				var ck := "%s||%s" % [vid, cid_val]
				var comp_ok := false
				if _compat_cache.has(ck):
					var payload: Dictionary = _compat_cache[ck]
					var data: Dictionary = payload.get("data", {}) if payload.get("data") is Dictionary else {}
					if data.has("compatible"):
						comp_ok = bool(data.get("compatible"))
					elif data.has("fitment") and data.get("fitment") is Dictionary and data.fitment.has("compatible"):
						comp_ok = bool(data.fitment.get("compatible"))
				else:
					# Fallback: light local check
					comp_ok = _is_part_compatible(vsel, s, item)
					# Opportunistically request backend compat to firm up future highlights
					if is_instance_valid(_mechanics_service) and cid_val != "" and vid != "" and _mechanics_service.has_method("check_part_compatibility"):
						_mechanics_service.check_part_compatibility(vid, cid_val)
				if comp_ok:
					has_inv_upgrade = true
					break
			if has_inv_upgrade:
				break
		_slot_inventory_availability[s] = has_inv_upgrade
		if has_inv_upgrade:
			# Ensure a row exists even if the vehicle currently has nothing installed in this slot
			_ensure_slot_row(s)
		# Restyle any visible rows for this slot
		_restyle_swap_buttons_for_slot(s)

func _restyle_swap_buttons_for_slot(slot_name: String) -> void:
	for child in parts_vbox.get_children():
		if not is_instance_valid(child):
			continue
		if child is HBoxContainer and child.has_meta("slot_name") and String(child.get_meta("slot_name")) == slot_name:
			# The button is nested inside the styled row; find it by name.
			var swap_btn: Button = child.find_child("SwapButton", true, false) as Button
			if is_instance_valid(swap_btn):
				_style_swap_button(swap_btn, slot_name)

func _start_vendor_compat_checks_for_vehicle(vehicle: Dictionary) -> void:
	# Request backend compatibility for ALL vendor part candidates at this settlement for this vehicle
	var vehicle_id: String = str(vehicle.get("vehicle_id", ""))
	if vehicle_id == "":
		return
	if _all_vendor_candidates_cache.is_empty():
		_all_vendor_candidates_cache = _collect_all_vendor_part_candidates()
	print("[PartCompatUI] Dispatching compat checks for ", _all_vendor_candidates_cache.size(), " vendor candidates for vehicle=", vehicle_id)
	for entry in _all_vendor_candidates_cache:
		var cand: Dictionary = entry.get("part", {})
		# Prefer cargo_id for compatibility endpoint; fall back to part_id
		var cid_val = cand.get("cargo_id", null)
		if typeof(cid_val) != TYPE_STRING or cid_val == "":
			cid_val = cand.get("part_id", null)
		if typeof(cid_val) != TYPE_STRING or cid_val == "":
			continue
		var cid: String = cid_val
		# Track any known local slot (backend remains source of truth)
		var s_loc_val = cand.get("slot", "")
		var s_loc: String = s_loc_val if typeof(s_loc_val) == TYPE_STRING else ""
		if s_loc != "":
			_cargo_to_slot[cid] = s_loc
		# Use per-vehicle cache key, since compatibility depends on vehicle
		var cache_key := "%s||%s" % [vehicle_id, cid]
		if _compat_cache.has(cache_key):
			var cached: Dictionary = _compat_cache[cache_key]
			var ok := false
			var data: Dictionary = cached.get("data", {}) if cached.get("data") is Dictionary else {}
			if data.has("compatible"):
				ok = bool(data.get("compatible"))
			elif data.has("fitment") and data.get("fitment") is Dictionary and data.fitment.has("compatible"):
				ok = bool(data.fitment.get("compatible"))
			if ok:
				# Already known compatible for this vehicle; synthesize slot and restyle now
				var slot_name := ""
				if data.has("fitment") and data.fitment is Dictionary and data.fitment.has("slot"):
					slot_name = String(data.fitment.get("slot", ""))
				elif _cargo_to_slot.has(cid):
					slot_name = String(_cargo_to_slot.get(cid, ""))
				if slot_name != "":
					_slot_vendor_availability[slot_name] = true
					_restyle_swap_buttons_for_slot(slot_name)
				continue
		if is_instance_valid(_mechanics_service) and _mechanics_service.has_method("check_part_compatibility"):
			print("[PartCompatUI] REQUEST vehicle=", vehicle_id, " part_cargo_id=", cid)
			_mechanics_service.check_part_compatibility(vehicle_id, cid)

func _style_swap_button(btn: Button, slot_name: String):
	if not is_instance_valid(btn):
		return

	# Reset to default style first
	btn.remove_theme_stylebox_override("normal")
	btn.remove_theme_color_override("font_color")
	btn.tooltip_text = ""

	var vendor_available: bool = bool(_slot_vendor_availability.get(slot_name, false))
	var inventory_available: bool = bool(_slot_inventory_availability.get(slot_name, false))

	if vendor_available or inventory_available:
		var sb = StyleBoxFlat.new()
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6

		if vendor_available and inventory_available:
			# Combined style: Green background, blue border for dual availability
			sb.bg_color = Color(0.12, 0.25, 0.12, 1.0) # Green
			sb.border_color = Color(0.35, 0.6, 0.9, 1.0) # Blue
			btn.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85)) # Light green text
			btn.tooltip_text = "Upgrades available (Vendor + Inventory)"
		elif vendor_available:
			# Vendor only: Green style
			sb.bg_color = Color(0.12, 0.25, 0.12, 1.0) # Green
			sb.border_color = Color(0.35, 0.8, 0.35, 1.0) # Green border
			btn.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85)) # Light green text
			btn.tooltip_text = "Vendor has parts for this slot"
		elif inventory_available:
			# Inventory only: Blue style
			sb.bg_color = Color(0.12, 0.18, 0.30, 1.0) # Blue
			sb.border_color = Color(0.35, 0.6, 0.9, 1.0) # Blue border
			btn.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0)) # Light blue text
			btn.tooltip_text = "Inventory has parts for this slot"

		btn.add_theme_stylebox_override("normal", sb)

		# Preserve vendor hint visibility behavior
		if vendor_available and is_instance_valid(vendor_hint_label):
			vendor_hint_label.visible = true

func _rebuild_pending_tab():
	for c in pending_vbox.get_children():
		c.queue_free()
	if _pending_swaps.size() == 0:
		_show_info(pending_vbox, "Your cart is empty. Select Swap… to add a part.")
		return

	# Compute per-vehicle schedules and costs
	var schedules: Dictionary = _compute_pending_schedules()
	var grand_parts_cost: float = 0.0
	var grand_install_cost: float = 0.0
	var item_index := 0
	for vid in schedules.keys():
		# Vehicle-level Changes Overview (before first row for this vehicle)
		var entries: Array = schedules[vid]
		var before_stats := _extract_vehicle_stats_by_id(vid)
		var after_stats := _compute_projected_stats_for_vehicle(vid, entries)
		var overview_panel := _make_stat_overview_panel(vid, before_stats, after_stats)
		if is_instance_valid(overview_panel):
			pending_vbox.add_child(overview_panel)

		for e in entries:
			var outer_row := HBoxContainer.new()
			outer_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			outer_row.mouse_filter = Control.MOUSE_FILTER_PASS

			# Panel row with multiline text and right-aligned Remove button
			var panel = PanelContainer.new()
			panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			outer_row.add_child(panel)

			var sb = StyleBoxFlat.new()
			if item_index % 2 == 0:
				sb.bg_color = Color(0.13, 0.15, 0.19, 0.8)
			else:
				sb.bg_color = Color(0.10, 0.12, 0.16, 0.8)
			sb.set_content_margin_all(8)
			panel.add_theme_stylebox_override("panel", sb)

			# Hover effect
			outer_row.mouse_entered.connect(func():
				sb.bg_color = sb.bg_color.lightened(0.1)
			)
			outer_row.mouse_exited.connect(func():
				if item_index % 2 == 0:
					sb.bg_color = Color(0.13, 0.15, 0.19, 0.8)
				else:
					sb.bg_color = Color(0.10, 0.12, 0.16, 0.8)
			)

			var row_hb = HBoxContainer.new()
			row_hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row_hb.add_theme_constant_override("separation", 10)
			panel.add_child(row_hb)

			var left_vb = VBoxContainer.new()
			left_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			left_vb.add_theme_constant_override("separation", 2)
			row_hb.add_child(left_vb)

			var title_lbl = Label.new()
			var from_n = String(e.get("from_name", "Old"))
			var to_n = String(e.get("to_name", "New"))
			var slot_title = String(e.get("slot","slot")).capitalize()
			title_lbl.text = "%s: %s → %s" % [slot_title, from_n, to_n]
			title_lbl.add_theme_font_size_override("font_size", 14)
			title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			left_vb.add_child(title_lbl)

			# Source indicator (Vendor vs Inventory)
			var src_lbl = Label.new()
			var sref_any = e.get("swap_ref", {})
			var src_str := ""
			if sref_any is Dictionary:
				src_str = String((sref_any as Dictionary).get("source", ""))
			src_lbl.text = "Source: %s" % ("Vendor" if src_str == "vendor" else "Inventory")
			if src_str == "vendor":
				src_lbl.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
			else:
				src_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
			left_vb.add_child(src_lbl)

			# Resolve the effective part cost the player pays (vendor items only; inventory items are free)
			var _vendor_price := _effective_part_cost_for_entry(e)
			var install_cost := float(e.get("install_cost", 0.0))
			var part_value := float(e.get("part_value", 0.0))
			var removable_flag := bool(e.get("removable", false))
			# Costs line
			var costs_lbl = Label.new()
			var is_vendor := sref_any is Dictionary and String((sref_any as Dictionary).get("source", "")) == "vendor"
			if is_vendor:
				costs_lbl.text = _format_price_label(_vendor_price, install_cost)
			else:
				# Inventory: only installation cost
				costs_lbl.text = "Installation $%s" % ["%.2f" % install_cost]
			costs_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			left_vb.add_child(costs_lbl)

			# Value line: clearly separated
			var value_lbl = Label.new()
			var value_delta := float(e.get("value_delta", part_value))
			var sign_str := "+" if value_delta >= 0.0 else ""
			var value_text = "Vehicle Value %s$%s" % [sign_str, "%.2f" % value_delta]
			if removable_flag:
				value_text += " (removable)"
			value_lbl.text = value_text
			value_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			left_vb.add_child(value_lbl)

			# Optional stat deltas
			var swap_ref_local = e.get("swap_ref")
			if swap_ref_local is Dictionary:
				var from_p: Dictionary = (swap_ref_local as Dictionary).get("from_part", {})
				var to_p: Dictionary = (swap_ref_local as Dictionary).get("to_part", {})
				var delta_txt := _part_delta_summary(from_p, to_p)
				if delta_txt != "":
					var delta_lbl = Label.new()
					delta_lbl.text = delta_txt
					delta_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
					delta_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
					left_vb.add_child(delta_lbl)

			var right_vb = VBoxContainer.new()
			right_vb.size_flags_horizontal = Control.SIZE_SHRINK_END
			right_vb.alignment = BoxContainer.ALIGNMENT_END
			row_hb.add_child(right_vb)

			var remove_btn = Button.new()
			remove_btn.text = "Remove"
			remove_btn.custom_minimum_size = Vector2(100, 28)
			remove_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
			remove_btn.pressed.connect(func():
				_pending_swaps.erase(swap_ref_local)
				_rebuild_pending_tab()
				_refresh_apply_state()
			)
			right_vb.add_child(remove_btn)

			pending_vbox.add_child(outer_row)
			# Cart parts cost sums effective price (inventory parts typically 0)
			grand_parts_cost += _vendor_price
			grand_install_cost += install_cost
			item_index += 1
	# Summary: If there are vendor parts, show full breakdown; otherwise show only installation
	if grand_parts_cost > 0.0:
		var parts_label = Label.new()
		parts_label.text = "Parts cost: $%s" % ("%.2f" % grand_parts_cost)
		parts_label.add_theme_font_size_override("font_size", 16)
		pending_vbox.add_child(parts_label)

		var install_label = Label.new()
		install_label.text = "Installation: $%s" % ("%.2f" % grand_install_cost)
		install_label.add_theme_font_size_override("font_size", 16)
		pending_vbox.add_child(install_label)

		var total_label = Label.new()
		var grand_total := grand_parts_cost + grand_install_cost
		total_label.text = "Total: $%s" % ("%.2f" % grand_total)
		total_label.add_theme_font_size_override("font_size", 16)
		pending_vbox.add_child(total_label)
	else:
		var install_label = Label.new()
		install_label.text = "Installation: $%s" % ("%.2f" % grand_install_cost)
		install_label.add_theme_font_size_override("font_size", 16)
		pending_vbox.add_child(install_label)
	_refresh_apply_state()

func _effective_part_cost_for_entry(e: Dictionary) -> float:
	# Player pays intrinsic part value only when acquiring from vendor. Inventory parts are free (already owned).
	var sref_any = e.get("swap_ref", {})
	if not (sref_any is Dictionary):
		return 0.0
	var sref: Dictionary = sref_any
	if String(sref.get("source", "")) != "vendor":
		return 0.0
	return _get_part_value(sref.get("to_part", {}))

func _effective_price_for_swap(s: Dictionary) -> float:
	# Scheduling heuristic: order vendor swaps by intrinsic value (cheaper first) to minimize cumulative install.
	if String(s.get("source", "")) != "vendor":
		return 0.0
	return _get_part_value(s.get("to_part", {}))

func _extract_vehicle_stats_by_id(vehicle_id: String) -> Dictionary:
	for v in _vehicles:
		if String(v.get("vehicle_id", "")) == vehicle_id:
			return _extract_vehicle_stats(v)
	return {
		"top_speed": 0.0,
		"efficiency": 0.0,
		"offroad_capability": 0.0,
		"cargo_capacity": 0.0,
		"weight_capacity": 0.0,
		"fuel_capacity": 0.0,
		"kwh_capacity": 0.0,
		"value": 0.0,
	}

func _extract_vehicle_stats(v: Dictionary) -> Dictionary:
	# Read common base stats, defaulting to 0 when missing
	var out := {
		"top_speed": _to_float(v.get("top_speed", 0.0)),
		"efficiency": _to_float(v.get("efficiency", 0.0)),
		"offroad_capability": _to_float(v.get("offroad_capability", 0.0)),
		"cargo_capacity": _to_float(v.get("cargo_capacity", 0.0)),
		"weight_capacity": _to_float(v.get("weight_capacity", 0.0)),
		"fuel_capacity": _to_float(v.get("fuel_capacity", 0.0)),
		"kwh_capacity": _to_float(v.get("kwh_capacity", 0.0)),
		"value": _to_float(v.get("value", 0.0)),
	}
	return out

func _extract_part_effects(p: Dictionary) -> Dictionary:
	# Normalize effects contributed by a part; treat *_add as additive and include capacity fields
	return {
		"top_speed": _to_float(p.get("top_speed_add", 0.0)),
		"efficiency": _to_float(p.get("efficiency_add", 0.0)),
		"offroad_capability": _to_float(p.get("offroad_capability_add", 0.0)),
		"cargo_capacity": _to_float(p.get("cargo_capacity_add", 0.0)),
		"weight_capacity": _to_float(p.get("weight_capacity_add", 0.0)),
		# Some parts may carry absolute capacities; treat as additive deltas when present
		"fuel_capacity": _to_float(p.get("fuel_capacity", 0.0)),
		"kwh_capacity": _to_float(p.get("kwh_capacity", 0.0)),
		# value handled separately in schedule, but keep 0 here for stats-only math
		"value": 0.0,
	}

func _compute_projected_stats_for_vehicle(vehicle_id: String, schedule_entries: Array) -> Dictionary:
	var stats := _extract_vehicle_stats_by_id(vehicle_id).duplicate(true)
	for e in schedule_entries:
		var swap_ref = e.get("swap_ref")
		if not (swap_ref is Dictionary):
			continue
		var from_p: Dictionary = (swap_ref as Dictionary).get("from_part", {})
		var to_p: Dictionary = (swap_ref as Dictionary).get("to_part", {})
		var from_eff := _extract_part_effects(from_p)
		var to_eff := _extract_part_effects(to_p)
		for k in stats.keys():
			# Subtract old part contribution, then add new part
				stats[k] = _to_float(stats.get(k, 0.0)) - _to_float(from_eff.get(k, 0.0)) + _to_float(to_eff.get(k, 0.0))
	# Project value using the same rounding as backend's value property (ties-to-even per Python round)
	var base_val := _round_bankers(_to_float(stats.get("value", 0.0)))
	var running := base_val
	for e2 in schedule_entries:
		# Use value delta (to.value - from.value) when available; fallback to part_value
		var step_delta := _to_float(e2.get("value_delta", e2.get("part_value", 0.0)))
		running = _round_bankers(running + step_delta)
	stats["value"] = running
	return stats

func _make_stat_overview_panel(vehicle_id: String, before_stats: Dictionary, after_stats: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	# Use a consistent, slightly different background for summary panels to distinguish them
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.9)
	sb.border_color = Color(0.4, 0.45, 0.5, 1.0)
	sb.border_width_left = 1
	sb.border_width_bottom = 1
	sb.set_content_margin_all(8)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	# Header with vehicle name
	var vname := "Vehicle"
	for v in _vehicles:
		if String(v.get("vehicle_id", "")) == vehicle_id:
			vname = String(v.get("name", v.get("make_model", "Vehicle")))
			break
	var hdr = Label.new()
	hdr.text = "%s — Changes Overview" % vname
	hdr.add_theme_font_size_override("font_size", 15)
	hdr.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	vb.add_child(hdr)

	var labels := {
		"top_speed": "Top Speed",
		"efficiency": "Efficiency",
		"offroad_capability": "Off-road",
		"cargo_capacity": "Cargo Cap",
		"weight_capacity": "Weight Cap",
		"fuel_capacity": "Fuel Cap",
		"kwh_capacity": "Battery kWh",
		"value": "Vehicle value ($)",
	}
	for k in labels.keys():
		var before := _to_float(before_stats.get(k, 0.0))
		var after := _to_float(after_stats.get(k, 0.0))
		var delta := after - before
		# Show only lines that have non-zero deltas, except include Value always if there are entries
		var must_show: bool = abs(delta) > 0.0001 or k == "value"
		if not must_show:
			continue
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 6)
		var name_lbl = Label.new()
		name_lbl.text = String(labels[k]) + ":"
		name_lbl.custom_minimum_size.x = 140
		var values_lbl = Label.new()
		var arrow := " → "
		if k == "value":
			values_lbl.text = "$%s%s$%s (%s%s)" % ["%.0f" % before, arrow, "%.0f" % after, "+" if delta > 0.0 else ("" if delta == 0.0 else ""), "%.0f" % delta]
		else:
			values_lbl.text = "%s%s%s (%s%s)" % ["%.0f" % before, arrow, "%.0f" % after, "+" if delta > 0.0 else ("" if delta == 0.0 else ""), "%.0f" % delta]
		# Color delta: green positive, red negative, neutral grey
		var color := Color(0.85, 0.85, 0.95)
		if delta > 0.0:
			color = Color(0.6, 1.0, 0.6)
		elif delta < 0.0:
			color = Color(1.0, 0.6, 0.6)
		values_lbl.add_theme_color_override("font_color", color)
		row.add_child(name_lbl)
		row.add_child(values_lbl)
		vb.add_child(row)

	return panel

func _to_float(v: Variant, default_val: float = 0.0) -> float:
	if v == null:
		return default_val
	match typeof(v):
		TYPE_FLOAT:
			return v
		TYPE_INT:
			return v * 1.0
		TYPE_BOOL:
			return 1.0 if v else 0.0
		TYPE_STRING:
			return String(v).to_float()
		_:
			return default_val

func _get_vehicle_value(vid: String) -> float:
	for v in _vehicles:
		if String(v.get("vehicle_id", "")) == vid:
			return float(v.get("value", 0.0))
	return 0.0

func _get_part_value(part: Dictionary) -> float:
	# Intrinsic part value (distinct from any vendor listing price). Backend install cost uses part.value.
	# Provide fallbacks for alternate schema keys and container wrapping.
	var keys: Array = ["value", "base_value", "part_value", "market_value"]
	for k in keys:
		if part.has(k) and part.get(k) != null:
			var v: Variant = part.get(k)
			if (v is float or v is int):
				var f := float(v)
				if abs(f) > 0.000001: # use first non-zero encountered
					return f
	# Recurse into first nested part if this is a cargo container wrapping a part
	if part.has("parts") and part.get("parts") is Array and not (part.get("parts") as Array).is_empty():
		var nested: Array = part.get("parts")
		var first = nested[0]
		if first is Dictionary:
			return _get_part_value(first)
	# Allow legitimate zero value
	if part.has("value") and part.get("value") != null:
		return float(part.get("value"))
	return 0.0

func _round_install(x: float) -> float:
	# Wrapper to centralize rounding semantics for install cost. Currently uses banker's rounding.
	return _round_bankers(x)

func _round_bankers(x: float) -> float:
	# Python's round() uses banker's rounding (ties to even) at integer precision.
	# Implement ties-to-even for .5 at integer boundary.
	var f: float = floor(x)
	var diff: float = x - f
	if is_equal_approx(diff, 0.5):
		var fi: int = int(f)
		if (fi % 2) == 0:
			return float(fi)
		else:
			return float(fi + 1)
	else:
		return round(x)

func _is_part_removable(part: Dictionary) -> bool:
	return bool(part.get("removable", false))

func _compute_pending_schedules() -> Dictionary:
	# Returns { vehicle_id: [ { swap_ref, slot, from_name, to_name, vendor_price, install_cost, part_value, removable } ... ] }
	var per_vehicle: Dictionary = {}
	for s in _pending_swaps:
		var vid := String(s.get("vehicle_id", ""))
		if vid == "":
			continue
		if not per_vehicle.has(vid):
			per_vehicle[vid] = []
		per_vehicle[vid].append(s)
	# Build schedules with ordering: non-removable by vendor price asc, then removable
	var out: Dictionary = {}
	for vid in per_vehicle.keys():
		var swaps: Array = per_vehicle[vid]
		var non_rem: Array = []
		var rem: Array = []
		for s in swaps:
			var to_p: Dictionary = s.get("to_part", {})
			if _is_part_removable(to_p):
				rem.append(s)
			else:
				non_rem.append(s)
		# Order non-removable parts to minimize cumulative install cost.
		# Heuristic: ascending by (to_part.value - from_part.value) first (lower delta means lower subsequent base),
		# then by intrinsic to_part.value, then by vendor acquisition cost heuristic.
		non_rem.sort_custom(func(a, b):
			var a_to := _get_part_value(a.get("to_part", {}))
			var a_from := _get_part_value(a.get("from_part", {}))
			var b_to := _get_part_value(b.get("to_part", {}))
			var b_from := _get_part_value(b.get("from_part", {}))
			var a_delta := a_to - a_from
			var b_delta := b_to - b_from
			if a_delta != b_delta:
				return a_delta < b_delta
			if a_to != b_to:
				return a_to < b_to
			var ap := self._effective_price_for_swap(a)
			var bp := self._effective_price_for_swap(b)
			return ap < bp
		)
		# Final order: cheapest non-removable first (ascending by vendor price), then removable parts
		# Final order: cheapest non-removable first (ascending by part value), then removable parts
		var ordered: Array = non_rem + rem
		var schedule: Array = []
		var cur_val := _get_vehicle_value(vid)
		# Track cumulative projected vehicle value for downstream installs.
		for s in ordered:
			var to_p: Dictionary = s.get("to_part", {})
			var to_val := _get_part_value(to_p)
			var from_p: Dictionary = s.get("from_part", {})
			var from_val := _get_part_value(from_p)
			var delta_val := to_val - from_val
			var pv := to_val
			var removable := _is_part_removable(to_p)
			var install_cost := 0.0
			if not removable:
				# IMPORTANT: installation cost uses vehicle value BEFORE adding this part (cur_val)
				var vehicle_value_mod := cur_val * 0.10
				var part_value_mod: float = to_val * 0.25
				install_cost = _round_install(vehicle_value_mod + part_value_mod)
				_log_cost_audit("schedule_step", {
					"vehicle_id": vid,
					"slot": String(s.get("slot","slot")),
					"vehicle_value_pre": cur_val,
					"to_value": to_val,
					"from_value": from_val,
					"delta_value": delta_val,
					"v10": vehicle_value_mod,
					"p25": part_value_mod,
					"install_cost": install_cost,
					"removable": removable,
				})
			# Update projected vehicle value AFTER install (base + delta), rounding to mirror backend value property
			cur_val = _round_bankers(cur_val + delta_val)
			var entry := {
				"swap_ref": s,
				"slot": String(s.get("slot","slot")),
				"from_name": String(s.get("from_part", {}).get("name", "Old")),
				"to_name": String(to_p.get("name", "New")),
				"vendor_price": float(s.get("price", 0.0)),
				"install_cost": float(install_cost),
				"part_value": float(pv), # absolute new part value
				"value_delta": float(delta_val), # value change used in projections
				"removable": removable,
			}
			schedule.append(entry)
		out[vid] = schedule
		# Optional: debug dump of per-step costs (disabled by default)
		if false:
			_debug_dump_schedule(vid, schedule)
	return out

func _debug_dump_schedule(vehicle_id: String, schedule_entries: Array) -> void:
	print("[MechanicsMenu][DEBUG] Schedule for ", vehicle_id)
	var base := _get_vehicle_value(vehicle_id)
	var running := base
	for e in schedule_entries:
		var s = e.get("swap_ref", {})
		var to_p: Dictionary = (s as Dictionary).get("to_part", {})
		var to_val := _get_part_value(to_p)
		var from_p: Dictionary = (s as Dictionary).get("from_part", {})
		var from_val := _get_part_value(from_p)
		var delta_val := to_val - from_val
		var removable := _is_part_removable(to_p)
		var v10 := running * 0.10
		# Backend: 25% uses absolute to_part.value
		var p25: float = abs(to_val) * 0.25
		var inst: float = 0.0
		if not removable:
			inst = _round_install(v10 + p25)
		print("  pre=", running, " delta=", delta_val, " 10%=", v10, " 25%=", p25, " install=", inst, " post=", running + delta_val)
		running += delta_val

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
	comp_header.add_theme_color_override("font_color", Color.YELLOW)
	comp_header.add_theme_font_size_override("font_size", 16)
	compatible_box.add_child(comp_header)

	var incompatible_box = VBoxContainer.new()
	incompatible_box.add_theme_constant_override("separation", 6)
	var incomp_header = Label.new()
	incomp_header.text = "Not compatible"
	incomp_header.add_theme_color_override("font_color", Color.YELLOW)
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

	# Stash containers for dynamic re-parenting when backend results arrive
	_current_swap_ctx["compatible_box"] = compatible_box
	_current_swap_ctx["incompatible_box"] = incompatible_box

	var all_candidates: Array = []
	for c in _collect_candidate_parts_for_slot(slot_name):
		var disp := _resolve_display_part_for_item(c)
		if not disp.is_empty():
			all_candidates.append({"part": disp, "source": "inventory", "price": 0.0})
	for v in _collect_vendor_parts_for_slot(slot_name):
		all_candidates.append(v) # expects {part, source:"vendor", price, vendor_id?}

	# Kick off compatibility checks for each candidate using backend, log responses when they arrive
	var vehicle_id: String = str(vehicle.get("vehicle_id", ""))
	if is_instance_valid(_mechanics_service) and _mechanics_service.has_method("check_part_compatibility") and not vehicle_id.is_empty():
		for entry in all_candidates:
			var cand: Dictionary = entry.get("part", {})
			# Prefer cargo_id for compatibility endpoint; fall back to part_id
			var cid_req: String = str(cand.get("cargo_id", ""))
			if cid_req == "":
				cid_req = str(cand.get("part_id", ""))
			if cid_req == "":
				continue
			# Use per-vehicle cache key
			var ck := "%s||%s" % [vehicle_id, cid_req]
			if not _compat_cache.has(ck):
				_mechanics_service.check_part_compatibility(vehicle_id, cid_req)

	if all_candidates.is_empty():
		var none = Label.new()
		none.text = "No parts found for this slot in convoy inventory or shop."
		root.add_child(none)
	else:
		for entry in all_candidates:
			var cand: Dictionary = entry.get("part", {})
			var source: String = String(entry.get("source", "inventory"))
			var price: float = float(entry.get("price", 0.0))
			var vendor_id_for_entry: String = String(entry.get("vendor_id", ""))
			# Seed from backend cache if available for this vehicle+part
			# Start with a light local check: slot match only; backend refines
			var comp_ok := (_detect_slot_for_item(cand) == slot_name)
			var row = _make_candidate_row(cand, source, price, comp_ok)
			var id2: String = str(cand.get("cargo_id", ""))
			if id2 == "":
				id2 = str(cand.get("part_id", ""))
			if id2 != "":
				_current_swap_ctx["row_map"][id2] = row
				var cache_key := "%s||%s" % [str(vehicle.get("vehicle_id", "")), id2]
				if _compat_cache.has(cache_key):
					_update_row_from_compat_payload(_compat_cache[cache_key])
				# Attach context for dynamic price updates and refresh price
				# Guard: vehicle must be a Dictionary; otherwise diagnose why
				var _veh_id_val := ""
				if typeof(vehicle) == TYPE_DICTIONARY:
					_veh_id_val = str(vehicle.get("vehicle_id", ""))
				else:
					print("[MechanicsMenu][Diag] Unexpected vehicle type when setting meta. typeof=", typeof(vehicle), " value=", vehicle)
				row.set_meta("vehicle_id", _veh_id_val)
				row.set_meta("part_uid", id2)
				# Set delta label vs current part
				var delta_lbl: Label = row.get_node_or_null("DeltaLabel")
				if is_instance_valid(delta_lbl):
					var delta_txt = _part_delta_summary(current_part, cand)
					delta_lbl.text = delta_txt
				_update_row_price_from_cache(row)
				# If already pending in cart, reflect that in UI and disable selection
				if _is_part_id_already_pending(id2):
					var compat_lbl_pending: Label = row.get_node_or_null("CompatLabel")
					if is_instance_valid(compat_lbl_pending):
						compat_lbl_pending.text = "In cart"
						compat_lbl_pending.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
						compat_lbl_pending.tooltip_text = "This item is already in the pending changes."
					var select_btn_pending: Button = row.get_node_or_null("SelectBtn")
					if is_instance_valid(select_btn_pending):
						select_btn_pending.text = "In Cart"
						select_btn_pending.disabled = true
			if comp_ok:
				# attach select handler
				var select_btn: Button = row.get_node_or_null("SelectBtn")
				if is_instance_valid(select_btn) and not _is_part_id_already_pending(id2):
					select_btn.pressed.connect(func():
						_add_pending_swap(slot_name, current_part, cand, source, price, vendor_id_for_entry)
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
	# Hide incompatible list if empty
	if incompatible_box.get_child_count() <= 1:
		incompatible_box.visible = false

func _collect_candidate_parts_for_slot(slot_name: String) -> Array:
	var out: Array = []
	# Collect from all vehicles' cargo for now (convoy-wide)
	for v in _vehicles:
		var cargo: Array = v.get("cargo", [])
		for item in cargo:
			if not (item is Dictionary):
				continue
			# Only loose cargo parts
			if item.get("intrinsic_part_id") != null:
				continue
			var s := _detect_slot_for_item(item)
			if s == slot_name:
				out.append(item)
	return out

func _collect_vendor_parts_for_slot(slot_name: String) -> Array:
	# Filtered view over all vendor candidates for a specific slot
	var out: Array = []
	if _all_vendor_candidates_cache.is_empty():
		_all_vendor_candidates_cache = _collect_all_vendor_part_candidates()
	for entry in _all_vendor_candidates_cache:
		var p: Dictionary = entry.get("part", {})
		var s := _get_slot_from_item(p)
		if s == slot_name:
			out.append(entry)
	if out.is_empty():
		var sx := int(roundf(float(_convoy.get("x", -99999.0))))
		var sy := int(roundf(float(_convoy.get("y", -99999.0))))
		print("[PartCompatUI] No vendor parts found for slot=", slot_name, " at (", sx, ",", sy, ")")
	return out

func _collect_all_vendor_part_candidates() -> Array:
	# Return items as [{ part: Dictionary, source: "vendor", price: float, vendor_id: String }]
	var results: Array = []
	var settlement_match: Dictionary = _get_settlement_at_convoy_coords()
	if settlement_match.is_empty():
		var sx := int(roundf(float(_convoy.get("x", -99999.0))))
		var sy := int(roundf(float(_convoy.get("y", -99999.0))))
		print("[PartCompatUI] No settlement match at (", sx, ", ", sy, ") while collecting vendor parts")
		return results

	var vendors: Array = settlement_match.get("vendors", [])
	for vendor in vendors:
		if not (vendor is Dictionary):
			continue
		var vendor_id_local := String(vendor.get("vendor_id", ""))
		var cargo_inv: Array = vendor.get("cargo_inventory", [])
		for item in cargo_inv:
			if not (item is Dictionary):
				continue
			if item.get("intrinsic_part_id") != null:
				continue # skip intrinsic-installed markers

			var price_f := _extract_price_from_dict(item)
			var cid_any: String = str(item.get("cargo_id", ""))
			var source_item: Dictionary = item
			# Case 1: top-level part with slot on source_item
			var slot_detected := _get_slot_from_item(source_item)
			if slot_detected != "":
				# Duplicate so we can inject price metadata for robust fallback rendering
				var part_for_row: Dictionary = source_item.duplicate(true)
				if (not part_for_row.has("unit_price")) and price_f > 0.0:
					part_for_row["unit_price"] = price_f
				results.append({"part": part_for_row, "source": "vendor", "price": price_f, "vendor_id": vendor_id_local})
				continue
			# Case 2: container with nested parts[] (on source_item)
			if source_item.has("parts") and (source_item.get("parts") is Array) and not ((source_item.get("parts") as Array).is_empty()):
				var nested_parts: Array = source_item.get("parts")
				var first_part: Dictionary = nested_parts[0]
				var pslot: String = _get_slot_from_item(first_part)
				if pslot != "":
					var display_part: Dictionary = first_part.duplicate(true)
					var cont_id_val: String = cid_any
					if cont_id_val == "":
						cont_id_val = str(first_part.get("part_id", ""))
					if cont_id_val != "":
						display_part["cargo_id"] = cont_id_val
					# Also carry a price on the displayed part for robust fallback
					if price_f > 0.0 and not display_part.has("unit_price"):
						display_part["unit_price"] = price_f
					results.append({"part": display_part, "source": "vendor", "price": price_f, "vendor_id": vendor_id_local})
					continue
			# Case 3: no slot/parts — skip

	if results.is_empty():
		var sx2 := int(roundf(float(_convoy.get("x", -99999.0))))
		var sy2 := int(roundf(float(_convoy.get("y", -99999.0))))
		print("[PartCompatUI] No vendor part candidates found at (", sx2, ", ", sy2, ")")
	else:
		print("[PartCompatUI] Found ", results.size(), " vendor part candidate(s)")
	return results

func _get_settlement_at_convoy_coords() -> Dictionary:
	var sx := int(roundf(float(_convoy.get("x", -99999.0))))
	var sy := int(roundf(float(_convoy.get("y", -99999.0))))
	var settlements: Array = []
	if is_instance_valid(_store) and _store.has_method("get_settlements"):
		settlements = _store.get_settlements()
	for s in settlements:
		if not (s is Dictionary):
			continue
		if int(s.get("x", 123456)) == sx and int(s.get("y", 123456)) == sy:
			return s
	# Fallback: use tile-attached settlements if present
	var tiles: Array = []
	if is_instance_valid(_store) and _store.has_method("get_tiles"):
		tiles = _store.get_tiles()
	for t in tiles:
		if not (t is Dictionary):
			continue
		if int(t.get("x", 123456)) == sx and int(t.get("y", 123456)) == sy:
			var st: Array = t.get("settlements", [])
			if not st.is_empty() and (st[0] is Dictionary):
				return st[0]
	return {}

func _get_vendor_id_at_convoy_location() -> String:
	var settlement := _get_settlement_at_convoy_coords()
	if settlement.is_empty():
		return ""
	var vendors: Array = settlement.get("vendors", [])
	if vendors.is_empty() or not (vendors[0] is Dictionary):
		return ""
	return String((vendors[0] as Dictionary).get("vendor_id", ""))

func _ensure_slot_row(slot_name: String) -> void:
	# If the UI has no row for this slot, create a placeholder row to enable swapping
	var has_any := false
	for child in parts_vbox.get_children():
		if child is HBoxContainer and child.has_meta("slot_name") and String(child.get_meta("slot_name")) == slot_name:
			has_any = true
			break
	if has_any:
		return
	# Insert a header if missing
	var header_present := false
	for child in parts_vbox.get_children():
		if child is Label and String(child.text).to_lower() == slot_name.replace("_", " ").to_lower():
			header_present = true
			break
	if not header_present:
		var header = Label.new()
		header.text = slot_name.capitalize().replace("_", " ")
		header.add_theme_font_size_override("font_size", 16)
		header.add_theme_color_override("font_color", Color.YELLOW)
		parts_vbox.add_child(header)
	# Add placeholder row
	var current_part := {"name": "None", "slot": slot_name}
	# Find the current total number of rows to get the correct index for styling
	var current_row_count = 0
	for child in parts_vbox.get_children():
		# Only count actual part rows, not headers or separators
		if child is HBoxContainer:
			current_row_count += 1
	
	var row = _create_styled_part_row(current_part, slot_name, current_row_count)
	parts_vbox.add_child(row)

func _extract_unit_price(d: Dictionary) -> float:
	# Mirrors Vendor panel logic to derive a per-unit price
	if d.has("unit_price") and d.unit_price != null:
		return float(d.unit_price)
	if d.has("base_unit_price") and d.base_unit_price != null:
		return float(d.base_unit_price)
	if d.has("price"):
		var p: Variant = d.get("price")
		if (p is float or p is int):
			var q: Variant = d.get("quantity", 1)
			var qf := float(q) if (q is float or q is int) else 1.0
			if qf > 0.0:
				return float(p) / qf
			return float(p)
	if d.has("container_price") and (d.container_price is float or d.container_price is int):
		# Fallback: container price treated as unit when no quantity context
		return float(d.container_price)
	return 0.0

func _extract_price_from_dict(d: Dictionary) -> float:
	return _extract_unit_price(d)

func _add_pending_swap(slot_name: String, from_part: Dictionary, to_part: Dictionary, source: String, price: float, vendor_id: String = ""):
	# Prevent adding the same cargo item twice across vehicles/slots
	if _is_part_already_pending(to_part):
		print("[MechanicsMenu] Skipping add: part already in cart ", _get_part_unique_id(to_part))
		return
	var vehicle_id := ""
	if _selected_vehicle_idx >= 0 and _selected_vehicle_idx < _vehicles.size():
		vehicle_id = String(_vehicles[_selected_vehicle_idx].get("vehicle_id", ""))
	_pending_swaps.append({
		"slot": slot_name,
		"from_part": from_part.duplicate(true),
		"to_part": to_part.duplicate(true),
		"source": source,
		"price": price,
	"vendor_id": vendor_id,
		"vehicle_id": vehicle_id,
	})
	# Ensure install price will be available in totals; request compat if not cached
	var uid := _get_part_unique_id(to_part)
	if vehicle_id != "" and uid != "" and is_instance_valid(_mechanics_service) and _mechanics_service.has_method("check_part_compatibility"):
		var key := _install_cache_key(vehicle_id, uid)
		if not _install_price_cache.has(key):
			_mechanics_service.check_part_compatibility(vehicle_id, uid)

func _on_apply_pressed():
	if _pending_swaps.is_empty():
		return
	if _selected_vehicle_idx < 0 or _selected_vehicle_idx >= _vehicles.size():
		return
	var vehicle_id = String(_vehicles[_selected_vehicle_idx].get("vehicle_id", ""))
	var convoy_id = String(_convoy.get("convoy_id", ""))
	# Build schedule using the same rules as the pending view
	var schedules := _compute_pending_schedules()
	var schedule_for_vehicle: Array = schedules.get(vehicle_id, [])
	# Extract the ordered swaps in schedule order
	var ordered_swaps: Array = []
	var total_cost: float = 0.0
	for e in schedule_for_vehicle:
		var s = e.get("swap_ref")
		ordered_swaps.append(s)
		var part_cost := _effective_part_cost_for_entry(e)
		total_cost += part_cost + float(e.get("install_cost", 0.0))
	# Keep swaps for other vehicles in their original order at the end
	for s in _pending_swaps:
		if String(s.get("vehicle_id", "")) != vehicle_id:
			ordered_swaps.append(s)
	# Try to discover vendor_id at the current settlement for mechanic work
	var vendor_id := _get_vendor_id_at_convoy_location()

	# Emit for observers
	emit_signal("changes_committed", convoy_id, vehicle_id, ordered_swaps, total_cost)
	# Fire backend API calls now via MechanicsService
	if is_instance_valid(_mechanics_service) and _mechanics_service.has_method("apply_swaps"):
		print("[MechanicsMenu][Apply] Applying ", ordered_swaps.size(), " swap(s) vend=", vendor_id, " vehicle=", vehicle_id, " convoy=", convoy_id, " total=$", "%.2f" % total_cost)
		_mechanics_service.apply_swaps(convoy_id, vehicle_id, ordered_swaps, vendor_id)
		# Ensure authoritative refresh after operations are queued.
		if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single") and convoy_id != "":
			_convoy_service.refresh_single(convoy_id)
	else:
		printerr("[MechanicsMenu][Apply] MechanicsService missing apply_swaps; cannot apply.")
	# Prototype: just clear changes after emit
	_pending_swaps.clear()
	_rebuild_pending_tab()

func _make_candidate_row(part: Dictionary, source: String, _price: float, compatible: bool) -> HBoxContainer:
	var hb = HBoxContainer.new()
	hb.name = "Row"
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 8)
	# Track cargo id on the row for later updates
	var mid_val = part.get("cargo_id", null)
	if typeof(mid_val) == TYPE_STRING and mid_val != "":
		var cargo_id_row: String = mid_val
		hb.set_meta("cargo_id", cargo_id_row)
	# Store full part dict for later use (deltas/price fallback)
	hb.set_meta("part_dict", part)

	# Source badge
	var badge = Label.new()
	badge.text = "Vendor" if source == "vendor" else "Inventory"
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.35, 0.15, 1.0) if source == "vendor" else Color(0.15, 0.25, 0.38, 1.0)
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
	badge.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
	badge.custom_minimum_size = Vector2(80, 26)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(badge)

	# Name + summary (two-line)
	var name_vb = VBoxContainer.new()
	name_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_vb.add_theme_constant_override("separation", 2)
	var name_lbl = Label.new()
	name_lbl.text = String(part.get("name", "Part")) + " " + _part_summary(part)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_vb.add_child(name_lbl)
	# Delta vs current is unknown here; show intrinsic summary only
	var delta_lbl = Label.new()
	delta_lbl.name = "DeltaLabel"
	delta_lbl.text = ""
	delta_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	name_vb.add_child(delta_lbl)
	hb.add_child(name_vb)

	# Compatibility status label (updated asynchronously from backend)
	var compat_lbl = Label.new()
	compat_lbl.name = "CompatLabel"
	compat_lbl.text = "Checking…"
	compat_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	compat_lbl.tooltip_text = "Awaiting backend check"
	hb.add_child(compat_lbl)

	# Price label for both vendor and inventory (inventory vendor_price is 0)
	var price_lbl = Label.new()
	price_lbl.name = "PriceLabel"
	# Store metas so we can update when install price arrives from compat
	var part_price := float(_price)
	if part_price <= 0.0:
		# Attempt to derive a vendor-listed price first
		part_price = _extract_price_from_dict(part)
	# If still zero and this is a vendor-sourced item, fall back to intrinsic value for display
	if part_price <= 0.0 and source == "vendor":
		part_price = _get_part_value(part)
	hb.set_meta("vendor_price", part_price)
	hb.set_meta("source", source)
	var veh_ctx := ""
	if not _current_swap_ctx.is_empty():
		veh_ctx = String(_current_swap_ctx.get("vehicle_id", ""))
	hb.set_meta("vehicle_id", veh_ctx)
	var uid_ctx := _get_part_unique_id(part)
	hb.set_meta("part_uid", uid_ctx)
	var install_price := _get_install_price_from_cache(veh_ctx, uid_ctx)
	if install_price <= 0.0:
		var removable := _is_part_removable(part)
		install_price = 0.0 if removable else _estimate_install_price(veh_ctx, part)
	# Cost audit for initial row render
	_log_cost_audit("row_init", {
		"phase": "init",
		"vehicle_id": veh_ctx,
		"part_uid": uid_ctx,
		"vendor_price": part_price,
		"install_price": install_price,
		"removable": _is_part_removable(part),
		"vehicle_value": _get_vehicle_value(veh_ctx),
		"part_value": _get_part_value(part),
	})
	var price_text := ""
	if source == "vendor":
		price_text = _format_price_label(part_price, install_price)
	else:
		# Inventory: only installation is charged
		price_text = "Installation $%s" % ["%.2f" % install_price]
	price_lbl.text = price_text
	price_lbl.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	hb.add_child(price_lbl)
	if part_price <= 0.0:
		_log_cost_audit("vendor_price_zero_row_init", {
			"part_uid": uid_ctx,
			"vehicle_id": veh_ctx,
			"price_fields_present": [
				part.has("unit_price"), part.has("base_unit_price"), part.has("price"), part.has("container_price")
			],
			"raw_price_fields": {
				"unit_price": part.get("unit_price", null),
				"base_unit_price": part.get("base_unit_price", null),
				"price": part.get("price", null),
				"container_price": part.get("container_price", null),
			}
		})

	# Optional cost breakdown label (developer toggle)
	var use_server_init := _get_install_price_from_cache(veh_ctx, uid_ctx) > 0.0
	var breakdown_txt := _make_breakdown_text(veh_ctx, part, install_price, use_server_init)
	_attach_or_update_breakdown_label(hb, breakdown_txt)

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
	var status_code := int(payload.get("status", 0))
	var compatible := false
	var reason := ""
	if data.has("compatible"):
		compatible = bool(data.get("compatible"))
	elif data.has("fitment") and data.get("fitment") is Dictionary and data.fitment.has("compatible"):
		compatible = bool(data.fitment.get("compatible"))
		reason = String(data.fitment.get("reason", ""))
	else:
		# Treat HTTP 2xx with array payload as compatible (backend returns list of matching part(s))
		if status_code >= 200 and status_code < 300:
			var any_data = payload.get("data")
			if any_data is Array and (any_data as Array).size() > 0:
				compatible = true
	# Special-case common 400 responses for better UX labeling
	if status_code >= 400:
		var detail_text := String(data.get("detail", ""))
		var dl := detail_text.to_lower()
		if is_instance_valid(compat_lbl):
			if dl.find("already installed") != -1:
				compat_lbl.text = "Already installed"
				compat_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4)) # amber
				compat_lbl.tooltip_text = detail_text
			elif dl.find("does not contain a part") != -1:
				compat_lbl.text = "Not a vehicle part"
				compat_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
				compat_lbl.tooltip_text = detail_text
			else:
				compat_lbl.text = "Not compatible"
				compat_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
				compat_lbl.tooltip_text = detail_text if detail_text != "" else ""
		if is_instance_valid(btn):
			btn.text = "Already installed" if dl.find("already installed") != -1 else "Incompatible"
			btn.disabled = true
		return
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

	# Move the row to the appropriate container based on final backend decision
	var compat_box: VBoxContainer = _current_swap_ctx.get("compatible_box", null)
	var incomp_box: VBoxContainer = _current_swap_ctx.get("incompatible_box", null)
	if is_instance_valid(compat_box) and is_instance_valid(incomp_box) and is_instance_valid(row):
		var parent := row.get_parent()
		if compatible and parent != compat_box:
			if is_instance_valid(parent):
				parent.remove_child(row)
			compat_box.add_child(row)
		elif (not compatible) and parent != incomp_box:
			if is_instance_valid(parent):
				parent.remove_child(row)
			incomp_box.add_child(row)
		# Hide incompatible section if it only has its header
		if incomp_box.get_child_count() <= 1:
			incomp_box.visible = false
		else:
			incomp_box.visible = true

	# Final override: if this item is already in the cart, mark accordingly regardless of compat
	if _is_part_id_already_pending(cid):
		if is_instance_valid(compat_lbl):
			compat_lbl.text = "In cart"
			compat_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
			compat_lbl.tooltip_text = "This item is already in the pending changes."
		if is_instance_valid(btn):
			btn.text = "In Cart"
			btn.disabled = true

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
	# Baseline rule: slot must match (be robust to alternative keys)
	var pslot := _get_slot_from_item(part)
	if pslot != slot_name:
		return false
	# If part has explicit requirements, attempt a naive check
	if part.has("requirements") and part.requirements is Array and not (part.requirements as Array).is_empty():
		# Look for simple string requirements that match vehicle fields (model/class) if present
		var reqs: Array = part.requirements
		# Guard vehicle dictionary before casting; diagnose abnormal types to catch the 'String constructor: vehicle' error.
		var vmodel := ""
		if typeof(vehicle) == TYPE_DICTIONARY:
			var _mm = vehicle.get("make_model", null)
			var _model = vehicle.get("model", "")
			# Use str() instead of String() to avoid constructor issues if values are unexpected types.
			if _mm != null and str(_mm) != "":
				vmodel = str(_mm).to_lower()
			else:
				vmodel = str(_model).to_lower()
		else:
			print("[MechanicsMenu][Diag] vehicle not Dictionary in _is_part_compatible typeof=", typeof(vehicle), " value=", vehicle)
			vmodel = str(vehicle).to_lower()
		for r in reqs:
			if r is String and not r.is_empty():
				var rlow = r.to_lower()
				if vmodel.find(rlow) == -1:
					return false
	return true

func _compat_reason(_vehicle: Dictionary, slot_name: String, part: Dictionary) -> String:
	if _get_slot_from_item(part) != slot_name:
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

				# (removed stray duplicate price update lines)
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
	var vehicle_id_cache := str(payload.get("vehicle_id", ""))
	if part_cargo_id != "" and vehicle_id_cache != "":
		var cache_key := "%s||%s" % [vehicle_id_cache, part_cargo_id]
		_compat_cache[cache_key] = payload
	# Installation price may be present; cache and update UI
	_maybe_cache_install_price_from_payload(payload)
	# Dual logs: concise keyword + structured snippet
	print("[PartCompatUI] payload=", payload)
	_debug_snippet(payload, "PartCompatUI.payload")
	# Update any open chooser rows
	_update_row_from_compat_payload(payload)
	# Also update slot highlights based on backend result
	var vid_ctx := ""
	if _selected_vehicle_idx >= 0 and _selected_vehicle_idx < _vehicles.size():
		vid_ctx = str(_vehicles[_selected_vehicle_idx].get("vehicle_id", ""))
	var vid: String = str(payload.get("vehicle_id", ""))
	if vid_ctx != "" and vid == vid_ctx:
		var data: Dictionary = payload.get("data", {}) if payload.get("data") is Dictionary else {}
		var ok := false
		var slot_name := ""
		if data.has("fitment") and data.get("fitment") is Dictionary:
			var fit: Dictionary = data.get("fitment")
			ok = bool(fit.get("compatible", false))
			slot_name = String(fit.get("slot", ""))
		elif data.has("compatible"):
			ok = bool(data.get("compatible"))
			# fallback slot field directly on data
			if data.has("slot"):
				slot_name = String(data.get("slot", ""))
			if slot_name == "":
				# fallback: try local id->slot map (cargo_id)
				var cidl: String = str(payload.get("part_cargo_id", ""))
				slot_name = String(_cargo_to_slot.get(cidl, ""))
		else:
			# If payload is HTTP 200 but data is an Array of part details, treat as compatible
			var status_code := int(payload.get("status", 0))
			if status_code >= 200 and status_code < 300:
				ok = true
				var d_any = payload.get("data")
				if d_any is Array and (d_any as Array).size() > 0 and (d_any[0] is Dictionary) and d_any[0].has("slot"):
					slot_name = String(d_any[0].get("slot", ""))
				if slot_name == "":
					var cidl2: String = str(payload.get("part_cargo_id", ""))
					slot_name = String(_cargo_to_slot.get(cidl2, ""))
		if ok and slot_name != "":
			# Ensure a UI row exists for slots that aren't currently present on the vehicle
			_ensure_slot_row(slot_name)
			if not bool(_slot_vendor_availability.get(slot_name, false)):
				_slot_vendor_availability[slot_name] = true
				_restyle_swap_buttons_for_slot(slot_name)
				# Ensure the hint label shows now that at least one slot is available
				if is_instance_valid(vendor_hint_label): vendor_hint_label.visible = true
			# Also refresh inventory-based highlights in case this payload pertains to a convoy cargo item
			_refresh_slot_inventory_availability()

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
		if flag:
			# Ensure a row exists even if the slot wasn't present before (e.g., skidplate/underside)
			_ensure_slot_row(s)
			if not bool(_slot_vendor_availability.get(s, false)):
				_slot_vendor_availability[s] = true
				_restyle_swap_buttons_for_slot(s)
