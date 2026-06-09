extends ScrollContainer
class_name VendorItemList
# Custom replacement for the vendor/convoy `Tree`. Renders category headers + selectable
# item rows as real Controls so a selected row can host an inline-expanding inspector
# (Concept A — mirrors convoy_cargo_menu's inline inspect panel).
#
# Consumes the same agg buckets the TreeBuilder used. Each row stores its agg_data as
# metadata, exactly like the Tree's get_metadata(0), so the panel's selection / restore /
# matching logic is reused unchanged (data-level _matches_restore_key).
#
# Selection emits item_selected(agg_data). The pinned transaction footer (RightPanel) keeps
# driving the real purchase; the inline body only shows a compact stats summary.

signal item_selected(agg_data)

const _HEADER_COLOR := Color(0.952941, 0.835294, 0.305882, 1.0) # Oori gold
const _ROW_BORDER := Color(0.224, 0.239, 0.278, 1.0)            # #393d47
const _ROW_BG := Color(0.122, 0.133, 0.157, 1.0)               # #1f2228
const _ROW_BG_ALT := Color(0.094, 0.102, 0.125, 1.0)
const _ROW_SEL := Color(0.149, 0.157, 0.165, 1.0)              # selected fill
const _NAME_COLOR := Color(0.90, 0.92, 0.96, 1.0)
const _VALUE_COLOR := Color(0.952941, 0.835294, 0.305882, 1.0)
const _STAT_COLOR := Color(0.62, 0.66, 0.72, 1.0)
const _STAT_HL := Color(0.88, 0.91, 0.95, 1.0)

const _CargoSorter = preload("res://Scripts/System/cargo_sorter.gd")

var _vbox: VBoxContainer
var _selected_panel: PanelContainer = null
var _selected_key: String = ""
var row_min_height: float = 52.0
var name_font_size: int = 18
var inline_expand_enabled: bool = true # portrait shows the inline body; desktop/landscape may disable
var list_mode: String = "buy" # "buy" (vendor wares) or "sell" (convoy cargo) — drives priced stats

# Tap-vs-drag tracking so touch scrolling isn't hijacked by row selection.
const _TAP_SLOP := 12.0
var _press_panel: PanelContainer = null
var _press_pos: Vector2 = Vector2.ZERO
var _press_moved: bool = false

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED # never scroll sideways
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 4)
	add_child(_vbox)

# --- public API (mirrors the panel's Tree call sites) ---

func clear_items() -> void:
	for c in _vbox.get_children():
		c.queue_free()
	_selected_panel = null

# Add one category section. sort_metric>=0 + title "Delivery Cargo" uses CargoSorter,
# matching VendorTreeBuilder.populate_category.
func add_category(title: String, agg_dict: Dictionary, sort_metric: int = -1) -> void:
	if agg_dict == null or agg_dict.is_empty():
		return
	var header := Label.new()
	header.text = title
	header.add_theme_color_override("font_color", _HEADER_COLOR)
	header.add_theme_font_size_override("font_size", max(14, name_font_size - 2))
	header.add_theme_constant_override("outline_size", 1)
	_vbox.add_child(header)

	var ordered: Array = _ordered_keys(agg_dict, title, sort_metric)
	var idx := 0
	for k in ordered:
		_add_row(String(k), agg_dict[k], idx)
		idx += 1

func get_selected_data() -> Variant:
	if _selected_panel != null and is_instance_valid(_selected_panel) and _selected_panel.has_meta("agg_data"):
		return _selected_panel.get_meta("agg_data")
	return null

func get_selected_key() -> String:
	return _selected_key

# Select by stable key after a rebuild (mirrors the Tree's selection-restore by exact key).
func select_key(key: String) -> bool:
	for child in _vbox.get_children():
		if child is PanelContainer and child.has_meta("agg_key") and String(child.get_meta("agg_key")) == key:
			_select_panel(child, true)
			return true
	return false

# Restore by an arbitrary matcher (panel supplies _matches_restore_key). on_select(agg_data)
# is invoked exactly like the Tree path so downstream behavior is identical.
func restore_by_match(item_id, match_fn: Callable, on_select: Callable) -> bool:
	for child in _vbox.get_children():
		if not (child is PanelContainer) or not child.has_meta("agg_data"):
			continue
		var agg: Variant = child.get_meta("agg_data")
		if agg is Dictionary and match_fn.is_valid() and bool(match_fn.call(agg, str(item_id))):
			_apply_selection(child)
			if on_select.is_valid():
				on_select.call(agg)
			return true
	return false

func deselect_all() -> void:
	if _selected_panel != null and is_instance_valid(_selected_panel):
		_selected_panel.add_theme_stylebox_override("panel", _row_style(false, _selected_panel.get_meta("row_alt", false)))
		_set_body_visible(_selected_panel, false)
	_selected_panel = null
	_selected_key = ""

func set_name_font_size(sz: int) -> void:
	name_font_size = sz

# Tutorial targeting: global rect of the first row whose name contains substr (case-insensitive).
func find_row_rect_by_text(substr: String) -> Rect2:
	var needle := substr.to_lower()
	for child in _vbox.get_children():
		if child is PanelContainer and child.has_meta("row_name"):
			if String(child.get_meta("row_name")).to_lower().find(needle) != -1:
				return Rect2(child.get_global_position(), child.size)
	return Rect2()

# --- internals ---

func _ordered_keys(agg_dict: Dictionary, title: String, sort_metric: int) -> Array:
	var keys: Array = agg_dict.keys()
	# CargoSorter path for Delivery Cargo (matches VendorTreeBuilder.populate_category).
	if sort_metric >= 0 and title == "Delivery Cargo":
		var items_to_sort: Array = []
		var item_to_key: Array = [] # parallel: [ {item:.., key:..}, ... ]
		for k in keys:
			var data: Variant = agg_dict[k]
			var item: Variant = data.get("item_data", data) if data is Dictionary else data
			items_to_sort.append(item)
			item_to_key.append({"item": item, "key": k})
		var sorted_items: Array = _CargoSorter.sort_cargo(items_to_sort, sort_metric, false)
		var out: Array = []
		var used: Dictionary = {}
		for si in sorted_items:
			for entry in item_to_key:
				if used.has(entry["key"]):
					continue
				if entry["item"] == si:
					out.append(entry["key"])
					used[entry["key"]] = true
					break
		for k in keys: # leftovers, stable
			if not used.has(k):
				out.append(k)
		return out
	# Default: case-insensitive by display name.
	keys.sort_custom(func(a, b): return _display_name(agg_dict[a]).to_lower() < _display_name(agg_dict[b]).to_lower())
	return keys

func _add_row(key: String, agg_data: Variant, index: int) -> void:
	var alt := (index % 2) == 1
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = row_min_height
	# PASS (not STOP): the row still receives gui_input for tap selection, but the event also
	# bubbles to the parent ScrollContainer so touch-drag scrolling keeps working. A tap-vs-drag
	# guard in _on_row_input prevents a scroll gesture from accidentally selecting a row.
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", _row_style(false, alt))

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE # let the row panel own all pointer input
	panel.add_child(body)

	# Header line: name + secondary value.
	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 8)
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(header_row)

	var nm := _display_name(agg_data)
	var name_lbl := Label.new()
	name_lbl.text = nm
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_lbl.add_theme_font_size_override("font_size", name_font_size)
	name_lbl.add_theme_color_override("font_color", _NAME_COLOR)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _is_raw_resource(agg_data):
		name_lbl.add_theme_color_override("font_color", _VALUE_COLOR)
	header_row.add_child(name_lbl)

	var secondary := _row_secondary_text(agg_data)
	if secondary != "":
		var val_lbl := Label.new()
		val_lbl.text = secondary
		val_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		val_lbl.add_theme_color_override("font_color", _VALUE_COLOR)
		val_lbl.add_theme_font_size_override("font_size", max(13, name_font_size - 3))
		val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_row.add_child(val_lbl)

	# Inline-expand body (compact stats), hidden until selected.
	var detail := _build_row_body(agg_data)
	if detail != null:
		detail.visible = false
		body.add_child(detail)
		panel.set_meta("detail", detail)

	panel.set_meta("agg_key", key)
	panel.set_meta("agg_data", agg_data)
	panel.set_meta("row_name", nm)
	panel.set_meta("row_alt", alt)
	panel.gui_input.connect(_on_row_input.bind(panel))
	_vbox.add_child(panel)

	if key == _selected_key:
		_apply_selection(panel)

func _on_row_input(event: InputEvent, panel: PanelContainer) -> void:
	# Tap-vs-drag: select only on a release that didn't travel far from the press (a tap).
	# A drag that exceeds the slop is a scroll gesture — leave it for the ScrollContainer.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_panel = panel
			_press_pos = event.position
			_press_moved = false
		elif _press_panel == panel and not _press_moved:
			_select_panel(panel, false)
			_press_panel = null
	elif event is InputEventScreenTouch:
		if event.pressed:
			_press_panel = panel
			_press_pos = event.position
			_press_moved = false
		elif _press_panel == panel and not _press_moved:
			_select_panel(panel, false)
			_press_panel = null
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		if _press_panel != null and event.position.distance_to(_press_pos) > _TAP_SLOP:
			_press_moved = true # this gesture is a scroll, not a tap

func _select_panel(panel: PanelContainer, _silent: bool) -> void:
	_apply_selection(panel)
	var agg_data: Variant = panel.get_meta("agg_data") if panel.has_meta("agg_data") else null
	emit_signal("item_selected", agg_data)

func _apply_selection(panel: PanelContainer) -> void:
	if _selected_panel != null and is_instance_valid(_selected_panel) and _selected_panel != panel:
		_selected_panel.add_theme_stylebox_override("panel", _row_style(false, _selected_panel.get_meta("row_alt", false)))
		_set_body_visible(_selected_panel, false)
	_selected_panel = panel
	_selected_key = String(panel.get_meta("agg_key")) if panel.has_meta("agg_key") else ""
	panel.add_theme_stylebox_override("panel", _row_style(true, panel.get_meta("row_alt", false)))
	_set_body_visible(panel, true)
	_ensure_row_visible(panel)

func _set_body_visible(panel: PanelContainer, vis: bool) -> void:
	if inline_expand_enabled and panel.has_meta("detail"):
		var detail: Variant = panel.get_meta("detail")
		if is_instance_valid(detail):
			detail.visible = vis

func _ensure_row_visible(panel: Control) -> void:
	# Scroll the expanded row into view next frame (after the body lays out).
	await get_tree().process_frame
	if not is_instance_valid(panel) or not is_instance_valid(self):
		return
	ensure_control_visible(panel)

# --- Inline detail body: compact stats line(s) from agg_data ---
func _build_row_body(agg_data: Variant) -> Control:
	if not (agg_data is Dictionary):
		return null
	var stats := _stat_pairs(agg_data, list_mode)
	if stats.is_empty():
		return null
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 3)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sep := HSeparator.new()
	wrap.add_child(sep)
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_font_size_override("normal_font_size", max(12, name_font_size - 4))
	line.text = _stat_pairs_to_bbcode(stats)
	wrap.add_child(line)
	return wrap

# Public/static: the compact "Label value • Label value" stat line for an agg item. Reused by the
# landscape inspector so its summary matches the inline row body exactly.
static func stat_line_bbcode(agg_data: Variant, mode: String = "buy") -> String:
	if not (agg_data is Dictionary):
		return ""
	return _stat_pairs_to_bbcode(_stat_pairs(agg_data, mode))

static func _stat_pairs_to_bbcode(stats: Array) -> String:
	# Muted small label + bold value; money values pick up the gold price accent; stats are
	# divided by a dim middot so the line reads as discrete data points.
	var parts: Array = []
	for p in stats:
		var label: String = str(p[0])
		var value: String = str(p[1])
		var vcol: String = "#eef1f6"
		if p.size() >= 3 and str(p[2]) != "":
			vcol = str(p[2]) # explicit color hint (e.g. profit green/red)
		elif value.begins_with("$"):
			vcol = "#f3d54e" # gold — matches the row price accent
		parts.append("[color=#7f8794]%s[/color] [color=%s][b]%s[/b][/color]" % [label, vcol, value])
	return "[color=#454b57]   ·   [/color]".join(parts)

# Comprehensive stat extraction — surfaces every data field the old verbose inspector exposed
# (Per Unit + Total Order + Pricing + stats + destination), so no buyable item loses information.
# Per-unit weight/volume/resource content are derived from the aggregate totals (matching the old
# "Per Unit" math) and fall back to the item's own unit fields.
static func _stat_pairs(agg_data: Dictionary, mode: String = "buy") -> Array:
	var item: Dictionary = agg_data.get("item_data", agg_data) if agg_data is Dictionary else {}
	if not (item is Dictionary):
		return []
	var tq: int = int(agg_data.get("total_quantity", 0)) if agg_data is Dictionary else 0
	var out: Array = []
	var is_vehicle: bool = VendorTradeVM.is_vehicle_item(item)

	if is_vehicle:
		# Vehicle capabilities + capacities (labels match the mockup: Cargo=weight cap, Volume=cargo cap).
		_push_num(out, item, "Off-road", ["offroad_capability", "off_road"], "")
		_push_num(out, item, "Top spd", ["top_speed"], "")
		_push_num(out, item, "Eff", ["fuel_efficiency", "efficiency"], "")
		_push_num(out, item, "Cargo", ["weight_capacity"], " kg")
		_push_num(out, item, "Volume", ["cargo_capacity"], " m³")
		_push_num(out, item, "Fuel cap", ["fuel_capacity", "kwh_capacity"], "")
		# Money via the VM (raw fields aren't reliably present).
		var vp: float = VendorTradeVM.vehicle_price(item)
		if vp > 0.0:
			out.append(["Value", NumberFormat.format_money(vp)])
	else:
		# Cargo / parts / resources — pricing computed by the VM (same source the old inspector used).
		var cup: float = VendorTradeVM.contextual_unit_price(item, mode)
		if cup > 0.0:
			out.append([("Sell price" if mode == "sell" else "Price"), NumberFormat.format_money(cup)])
		# Per-unit physicals derived from aggregate totals (matches the old Per Unit math).
		var uw := _unit_from_totals(agg_data, item, "total_weight", ["unit_weight", "weight"], tq)
		if uw > 0.0:
			out.append(["Weight", _fmt_stat(uw) + " kg"])
		var uv := _unit_from_totals(agg_data, item, "total_volume", ["unit_volume", "volume"], tq)
		if uv > 0.0:
			out.append(["Volume", _fmt_stat(uv) + " m³"])
		var dr: float = VendorTradeVM.get_unit_delivery_reward(item, agg_data)
		if dr > 0.0:
			out.append(["Delivery", NumberFormat.format_money(dr)])
			# Per-unit profit = reward − cost (same margin the sort uses). Green when it pays off.
			var profit: float = dr - cup
			var psign: String = "+" if profit >= 0.0 else "-"
			var pcol: String = "#7fd08a" if profit >= 0.0 else "#e3736b"
			out.append(["Profit/unit", "%s%s" % [psign, NumberFormat.format_money(absf(profit))], pcol])
		# Resource content (food / water / fuel) carried per unit.
		var uf := _unit_from_totals(agg_data, item, "total_food", ["food"], tq)
		if uf > 0.0:
			out.append(["Food", _fmt_stat(uf)])
		var uwa := _unit_from_totals(agg_data, item, "total_water", ["water"], tq)
		if uwa > 0.0:
			out.append(["Water", _fmt_stat(uwa)])
		var ufu := _unit_from_totals(agg_data, item, "total_fuel", ["fuel"], tq)
		if ufu > 0.0:
			out.append(["Fuel", _fmt_stat(ufu)])
		_push_num(out, item, "Slot", ["slot"], "")
		# Arbitrary part/modifier stats.
		if item.has("stats") and item["stats"] is Dictionary:
			for sk in (item["stats"] as Dictionary):
				var sv = (item["stats"] as Dictionary)[sk]
				if sv != null and str(sv) != "" and not (sv is float and float(sv) == 0.0):
					out.append([str(sk).capitalize().replace("_", " "), _fmt_stat(sv)])

	# Stock count, common to all buyables.
	if tq > 0:
		out.append(["Available", str(tq)])
	# Delivery destination, when present.
	var dest := _destination_name(agg_data, item)
	if dest != "":
		out.append(["Dest", dest])
	return out

# Per-unit value: prefer aggregate total / quantity (matches the old Per Unit math), else the item's
# own unit field.
static func _unit_from_totals(agg_data: Dictionary, item: Dictionary, total_key: String, unit_keys: Array, tq: int) -> float:
	if agg_data is Dictionary and tq > 0 and agg_data.has(total_key):
		var tot := float(agg_data.get(total_key, 0.0))
		if tot > 0.0:
			return tot / float(tq)
	for k in unit_keys:
		if item.has(k) and item.get(k) != null:
			var v = item.get(k)
			if (v is float or v is int) and float(v) > 0.0:
				return float(v)
	return 0.0

static func _push_num(out: Array, item: Dictionary, label: String, keys: Array, unit: String) -> void:
	for k in keys:
		if item.has(k) and item.get(k) != null:
			var v = item.get(k)
			if (v is float or v is int) and float(v) == 0.0:
				return
			out.append([label, _fmt_stat(v) + unit])
			return

static func _push_money(out: Array, item: Dictionary, label: String, keys: Array) -> void:
	for k in keys:
		if item.has(k) and item.get(k) != null:
			var v = item.get(k)
			if (v is float or v is int) and float(v) <= 0.0:
				return
			out.append([label, "$%s" % NumberFormat.fmt_qty(v)])
			return

static func _destination_name(agg_data: Dictionary, item: Dictionary) -> String:
	for src in [agg_data, item]:
		if not (src is Dictionary):
			continue
		for k in ["mission_vendor_name", "recipient_settlement_name", "destination_settlement_name", "destination_name", "dest_settlement"]:
			var v = (src as Dictionary).get(k)
			if v != null:
				var s := str(v).strip_edges()
				if s != "" and s != "Unknown Vendor" and not ("00000000" in s):
					return s
	return ""

static func _fmt_stat(v: Variant) -> String:
	if v is float:
		return NumberFormat.fmt_float(v, 2)
	return str(v)

static func _fmt_stat_unit(v: Variant, unit: String) -> String:
	if unit == "$":
		return "$%s" % NumberFormat.fmt_qty(v)
	return _fmt_stat(v) + unit

# --- helpers ---
func _row_style(selected: bool, alt: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _ROW_SEL if selected else (_ROW_BG_ALT if alt else _ROW_BG)
	s.set_border_width_all(1)
	s.border_color = _VALUE_COLOR if selected else _ROW_BORDER
	if selected:
		s.border_width_left = 3
	s.set_corner_radius_all(6)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _display_name(agg_data: Variant) -> String:
	if agg_data is Dictionary:
		var d: Dictionary = agg_data
		if d.has("display_name") and str(d.get("display_name")) != "":
			return String(d.get("display_name"))
		if d.has("item_data") and d["item_data"] is Dictionary and (d["item_data"] as Dictionary).has("name"):
			return String((d["item_data"] as Dictionary).get("name"))
	return str(agg_data)

func _is_raw_resource(agg_data: Variant) -> bool:
	if agg_data is Dictionary and (agg_data as Dictionary).has("item_data"):
		var idata: Variant = (agg_data as Dictionary).get("item_data")
		if idata is Dictionary:
			return bool((idata as Dictionary).get("is_raw_resource", false))
	return false

func _row_secondary_text(agg_data: Variant) -> String:
	if agg_data is Dictionary:
		var d: Dictionary = agg_data
		var item: Variant = d.get("item_data", d)
		if item is Dictionary:
			for f in ["price", "base_price", "value"]:
				if (item as Dictionary).has(f) and (item as Dictionary).get(f) != null:
					return "$%s" % NumberFormat.fmt_qty((item as Dictionary).get(f))
		if d.has("total_quantity") and int(d.get("total_quantity")) > 0:
			return "x%s" % str(int(d.get("total_quantity")))
	return ""
