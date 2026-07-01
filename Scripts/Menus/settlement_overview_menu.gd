extends MenuBase
## SettlementOverviewMenu — the settlement HUB (Sprint 5.5).
##
## Primary intermediary between the convoy menu and the single-vendor trade menu:
## Settlement nav → this hub (vendors + warehouse) → pick a vendor → trade menu.
## Also opened convoy-independently from the map (tap a pinned label) for a browse-only preview.
##
## Extends MenuBase so it behaves like the other convoy submenus — store-driven refresh (so late
## settlement/convoy data fills in instead of showing a blank first open), the shared bottom nav, and
## the standard menu-switch transitions. UI is built in code; the .tscn is just a root Control.

## open_warehouse_menu_requested / open_vendor_requested are forwarded by MenuManager. back_requested is
## inherited from MenuBase (do NOT redeclare it).
signal open_warehouse_menu_requested(payload: Dictionary)
signal open_vendor_requested(convoy_data: Dictionary, vendor_id: String)

var _debug_settlement_overview: bool = false

## When opened from the Settlement nav this holds the convoy; from the map preview it stays empty and
## vendor rows render browse-only.
var _convoy_data: Dictionary = {}
var _settlement: Dictionary = {}

@onready var _store: Node = get_node_or_null("/root/GameStore")
@onready var _api: Node = get_node_or_null("/root/APICalls")
@onready var _convoy_service: Node = get_node_or_null("/root/ConvoyService")
@onready var _user_service: Node = get_node_or_null("/root/UserService")

const TopUpPlanner = preload("res://Scripts/Menus/VendorPanel/top_up_planner.gd")
const _RESOURCE_KEYS := ["fuel", "water", "food"]
# Gauge accent per resource for the readiness strip.
const _RESOURCE_COLORS := {
	"fuel": Color(0.85, 0.62, 0.27),
	"water": Color(0.36, 0.62, 0.86),
	"food": Color(0.52, 0.76, 0.42),
}

var _top_up_plan: Dictionary = {}

func initialize_with_data(data: Variant, extra_arg: Variant = null) -> void:
	# Map-preview entry: a settlement snapshot (no convoy) — build directly, no store/convoy wiring.
	if data is Dictionary and String((data as Dictionary).get("convoy_id", "")) == "" \
			and ((data as Dictionary).has("sett_id") or (data as Dictionary).has("vendors")):
		_convoy_data = {}
		_settlement = (data as Dictionary).duplicate(true)
		if _debug_settlement_overview:
			print("[SettlementOverview] init (map preview) — sett=", _settlement.get("name", "?"))
		if is_node_ready():
			_rebuild()
		return
	# Hub entry: a convoy (dict or id) — let MenuBase wire store subscriptions and drive _update_ui so
	# late convoy/settlement data refreshes the screen instead of leaving it blank.
	super.initialize_with_data(data, extra_arg)

## MenuBase hands us the authoritative convoy snapshot here (on init and on every relevant change).
func _update_ui(convoy: Dictionary) -> void:
	_convoy_data = convoy.duplicate(true)
	_settlement = _resolve_settlement_from_convoy(_convoy_data)
	if _debug_settlement_overview:
		print("[SettlementOverview] _update_ui — convoy=", String(_convoy_data.get("convoy_id", "")), " sett=", _settlement.get("name", "?"))
	_rebuild()

func reset_view() -> void:
	_convoy_data = {}
	_settlement = {}
	_rebuild()

func _has_convoy() -> bool:
	return String(_convoy_data.get("convoy_id", "")) != ""

## Find the settlement sitting on the convoy's tile. Prefer the authoritative tile snapshot, then fall
## back to matching the settlements list by rounded coords.
func _resolve_settlement_from_convoy(convoy: Dictionary) -> Dictionary:
	if not is_instance_valid(_store) or String(convoy.get("convoy_id", "")) == "":
		return {}
	var cx: int = int(roundf(float(convoy.get("x", -9999.0))))
	var cy: int = int(roundf(float(convoy.get("y", -9999.0))))
	if cx < 0 or cy < 0:
		return {}
	if _store.has_method("get_tiles"):
		var tiles: Array = _store.get_tiles()
		if cy >= 0 and cy < tiles.size():
			var row: Variant = tiles[cy]
			if row is Array and cx >= 0 and cx < (row as Array).size():
				var tile: Variant = (row as Array)[cx]
				if tile is Dictionary and tile.has("settlements") and tile.settlements is Array and not (tile.settlements as Array).is_empty():
					var s0: Variant = (tile.settlements as Array)[0]
					if s0 is Dictionary:
						return (s0 as Dictionary).duplicate(true)
	if _store.has_method("get_settlements"):
		for s in _store.get_settlements():
			if s is Dictionary:
				var sx: int = int(roundf(float(s.get("x", -9999.0))))
				var sy: int = int(roundf(float(s.get("y", -9999.0))))
				if sx == cx and sy == cy:
					return (s as Dictionary).duplicate(true)
	return {}

func _ready() -> void:
	# Our _rebuild() clears all children, so MenuBase's OoriBackground would be wiped each rebuild —
	# we paint our own METAL_DARK background instead.
	auto_apply_oori_background = false
	super._ready()
	# Settlement data arrives via map_changed (tiles + settlements), which MenuBase doesn't watch.
	if is_instance_valid(_store) and _store.has_signal("map_changed") and not _store.map_changed.is_connected(_on_store_map_changed):
		_store.map_changed.connect(_on_store_map_changed)
	_rebuild()

func _on_store_map_changed(_tiles: Array, _settlements: Array) -> void:
	if _has_convoy():
		_settlement = _resolve_settlement_from_convoy(_convoy_data)
		_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = UITheme.METAL_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# The "Back / Settlement" banner is redundant with a convoy present (the bottom nav owns navigation),
	# so only the convoy-independent map preview keeps it.
	if not _has_convoy():
		root.add_child(_build_banner())

	# No ScrollContainer by design (user: "I never want to scroll"). Content sits in a padded column;
	# vendors render as a compact card grid so they fit without scrolling.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, UITheme.SPACE_XL)
	pad.add_theme_constant_override("margin_top", UITheme.SPACE_LG)
	pad.add_theme_constant_override("margin_bottom", UITheme.SPACE_LG)
	root.add_child(pad)

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", UITheme.SPACE_MD)
	pad.add_child(outer)

	# Flow: WHO/WHERE (identity) → WHAT YOU HAVE (resources + storage, side by side) → WHAT YOU CAN DO
	# (vendors). The redundant info chips (vendor count, type) are dropped — the subtitle already names
	# the type and the vendors section shows the count.
	_build_header(outer)
	_build_resources_and_warehouse_row(outer, _is_portrait())
	_build_vendors_section(outer, _is_portrait())

func _build_banner() -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.METAL_BASE
	style.border_width_bottom = 3
	style.border_color = UITheme.ACCENT_VERDIGRIS
	style.content_margin_top = UITheme.SPACE_MD
	style.content_margin_bottom = UITheme.SPACE_MD
	style.content_margin_left = UITheme.SPACE_LG
	style.content_margin_right = UITheme.SPACE_LG
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UITheme.SPACE_MD)
	panel.add_child(hbox)

	var back := Button.new()
	back.text = "Back"
	back.focus_mode = Control.FOCUS_NONE
	if _is_mobile():
		back.custom_minimum_size.y = 60.0
	_style_metal_button(back, false)
	back.pressed.connect(func(): emit_signal("back_requested"))
	hbox.add_child(back)

	var title := Label.new()
	title.text = "Settlement"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	hbox.add_child(title)

	# Right-side spacer to keep the title visually centred against the back button.
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 90.0
	hbox.add_child(spacer)
	return panel

# --- Resources + Warehouse (side by side) ---

## Their own section, side by side: Resources (convoy gauges + Top Up) on the left, Warehouse on the
## right. With no convoy present there's nothing to gauge, so only the Warehouse card shows (full width).
func _build_resources_and_warehouse_row(parent: VBoxContainer, portrait: bool) -> void:
	var card_h := 200.0 if portrait else 176.0
	if not _has_convoy():
		parent.add_child(_make_warehouse_card(card_h))
		return

	var row: Container = HBoxContainer.new() if not portrait else VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UITheme.SPACE_MD)
	parent.add_child(row)

	var res_card := _build_resources_card(card_h)
	res_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not portrait:
		res_card.size_flags_stretch_ratio = 1.6
	row.add_child(res_card)

	var wh_card := _make_warehouse_card(110.0 if portrait else card_h)
	if not portrait:
		wh_card.size_flags_stretch_ratio = 1.0
	row.add_child(wh_card)

## The resources card: deeper shadowed panel (matches the Warehouse/vendor card language instead of a
## flat strip), each resource as its own raised tile with an icon + big number + a taller gauge bar.
func _build_resources_card(card_h: float) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = card_h
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.METAL_BASE
	style.set_border_width_all(2)
	style.border_color = UITheme.ACCENT_VERDIGRIS
	style.set_corner_radius_all(UITheme.RADIUS_LG)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 4
	style.content_margin_left = UITheme.SPACE_MD + 2
	style.content_margin_right = UITheme.SPACE_MD + 2
	style.content_margin_top = UITheme.SPACE_MD
	style.content_margin_bottom = UITheme.SPACE_MD
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.SPACE_SM)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(box)

	var head := Label.new()
	head.text = "RESOURCES"
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	box.add_child(head)

	var tiles := HBoxContainer.new()
	tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tiles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tiles.add_theme_constant_override("separation", UITheme.SPACE_SM)
	box.add_child(tiles)
	for res in _RESOURCE_KEYS:
		tiles.add_child(_make_gauge(res))

	var top_up := _make_top_up_button()
	top_up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_up.custom_minimum_size.y = 40.0
	box.add_child(top_up)
	return panel

const _RESOURCE_ICONS := {"fuel": "⛽", "water": "💧", "food": "🍖"}

## A raised tile (its own recessed background) rather than bars floating directly on the card — gives
## the resources section depth instead of reading as one flat surface.
func _make_gauge(res: String) -> Control:
	var cur := float(_convoy_data.get(res, 0.0))
	var maxv := float(_convoy_data.get("max_" + res, 0.0))
	var accent: Color = _RESOURCE_COLORS.get(res, UITheme.ACCENT_BRASS)

	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size.x = 88.0
	var tstyle := StyleBoxFlat.new()
	tstyle.bg_color = UITheme.METAL_DARK
	tstyle.set_corner_radius_all(UITheme.RADIUS_MD)
	tstyle.content_margin_left = UITheme.SPACE_SM + 2
	tstyle.content_margin_right = UITheme.SPACE_SM + 2
	tstyle.content_margin_top = UITheme.SPACE_SM + 2
	tstyle.content_margin_bottom = UITheme.SPACE_SM + 2
	tile.add_theme_stylebox_override("panel", tstyle)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.add_child(vb)

	var icon_l := Label.new()
	icon_l.text = "%s  %s" % [_RESOURCE_ICONS.get(res, ""), res.capitalize()]
	icon_l.add_theme_font_size_override("font_size", 12)
	icon_l.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	vb.add_child(icon_l)

	var val_l := Label.new()
	val_l.text = "%d" % int(round(cur))
	val_l.add_theme_font_size_override("font_size", 22)
	val_l.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	vb.add_child(val_l)

	var of_l := Label.new()
	of_l.text = "/ %d" % int(round(maxv))
	of_l.add_theme_font_size_override("font_size", 11)
	of_l.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	vb.add_child(of_l)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 10.0
	bar.min_value = 0.0
	bar.max_value = maxv if maxv > 0.0 else 1.0
	bar.value = clampf(cur, 0.0, bar.max_value)
	var bg := StyleBoxFlat.new()
	bg.bg_color = UITheme.METAL_EDGE.lerp(UITheme.METAL_DARK, 0.5)
	bg.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	vb.add_child(bar)
	return tile

func _make_money_tile() -> Control:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size.x = 96.0
	var tstyle := StyleBoxFlat.new()
	tstyle.bg_color = UITheme.METAL_DARK
	tstyle.set_corner_radius_all(UITheme.RADIUS_MD)
	tstyle.content_margin_left = UITheme.SPACE_SM + 2
	tstyle.content_margin_right = UITheme.SPACE_SM + 2
	tstyle.content_margin_top = UITheme.SPACE_SM + 2
	tstyle.content_margin_bottom = UITheme.SPACE_SM + 2
	tile.add_theme_stylebox_override("panel", tstyle)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.add_child(vb)

	var l := Label.new()
	l.text = "MONEY"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	vb.add_child(l)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)

	var v := Label.new()
	v.text = "$%s" % _format_money(float(_convoy_data.get("money", 0.0)))
	v.add_theme_font_size_override("font_size", 20)
	v.add_theme_color_override("font_color", UITheme.ACCENT_BRASS)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.clip_text = true
	vb.add_child(v)
	return tile

func _make_top_up_button() -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_top_up_plan = TopUpPlanner.calculate_plan(_convoy_data, _settlement, float(_convoy_data.get("money", 0.0)))
	var cost := float(_top_up_plan.get("total_cost", 0.0))
	var has_plan := not (_top_up_plan.get("resources", {}) as Dictionary).is_empty() and cost > 0.0

	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.ACCENT_BRASS if has_plan else UITheme.METAL_BASE
	normal.set_border_width_all(2)
	normal.border_color = UITheme.ACCENT_BRASS if has_plan else UITheme.METAL_EDGE
	normal.set_corner_radius_all(UITheme.RADIUS_MD)
	normal.content_margin_left = UITheme.SPACE_LG
	normal.content_margin_right = UITheme.SPACE_LG
	normal.content_margin_top = UITheme.SPACE_SM + 2
	normal.content_margin_bottom = UITheme.SPACE_SM + 2
	var hover := normal.duplicate()
	hover.bg_color = UITheme.ACCENT_BRASS.lerp(Color.WHITE, 0.12) if has_plan else UITheme.METAL_HOVER
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, hover if st == "hover" else normal)
	btn.add_theme_color_override("font_color", UITheme.METAL_DARK if has_plan else UITheme.TEXT_MUTED)
	btn.add_theme_color_override("font_color_disabled", UITheme.TEXT_MUTED)
	btn.add_theme_font_size_override("font_size", 14)

	if has_plan:
		btn.text = "Top Up · $%s" % _format_money(cost)
		btn.tooltip_text = _top_up_tooltip()
		btn.pressed.connect(_on_top_up_pressed)
	else:
		btn.text = "Topped Up"
		btn.disabled = true
	return btn

func _top_up_tooltip() -> String:
	var parts: Array[String] = []
	var resources: Dictionary = _top_up_plan.get("resources", {})
	for res in _RESOURCE_KEYS:
		var r: Dictionary = resources.get(res, {})
		if int(r.get("total_quantity", 0)) > 0:
			parts.append("%s +%d  ($%s)" % [res.capitalize(), int(r.get("total_quantity", 0)), _format_money(float(r.get("total_cost", 0.0)))])
	return "\n".join(parts) if not parts.is_empty() else "Top up fuel, water, and food"

func _on_top_up_pressed() -> void:
	if _top_up_plan.is_empty() or (_top_up_plan.get("resources", {}) as Dictionary).is_empty():
		return
	var convoy_uuid := String(_convoy_data.get("convoy_id", _convoy_data.get("id", "")))
	if convoy_uuid == "" or not is_instance_valid(_api):
		return
	for alloc in _top_up_plan.get("allocations", []):
		var res := String(alloc.get("res", ""))
		var vendor_id := String(alloc.get("vendor_id", ""))
		var qty := int(alloc.get("quantity", 0))
		if res == "" or vendor_id == "" or qty <= 0:
			continue
		_api.buy_resource(vendor_id, convoy_uuid, res, float(qty))
	# Authoritative refreshes; the new levels flow back via convoys_changed → _update_ui → _rebuild.
	if is_instance_valid(_convoy_service) and _convoy_service.has_method("refresh_single"):
		_convoy_service.refresh_single(convoy_uuid)
	if is_instance_valid(_user_service) and _user_service.has_method("refresh_user"):
		_user_service.refresh_user()

func _format_money(v: float) -> String:
	var n := int(round(absf(v)))
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if v < 0.0 else "") + out

func _build_header(col: VBoxContainer) -> void:
	var name_label := Label.new()
	name_label.text = String(_settlement.get("name", "Settlement"))
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	col.add_child(name_label)

	var sub := Label.new()
	sub.text = _subtitle_text()
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	col.add_child(sub)

func _subtitle_text() -> String:
	var parts: Array[String] = []
	var stype := _settlement_type_label()
	if stype != "":
		parts.append(stype)
	if _settlement.has("x") and _settlement.has("y"):
		parts.append("%d, %d" % [int(roundf(float(_settlement.get("x", 0)))), int(roundf(float(_settlement.get("y", 0))))])
	return " · ".join(parts)

func _settlement_type_label() -> String:
	var t := String(_settlement.get("sett_type", _settlement.get("type", "")))
	return t.capitalize() if t != "" else ""

func _build_vendors_section(col: VBoxContainer, portrait: bool) -> void:
	var vendors := _vendor_list()

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", UITheme.SPACE_SM)
	var h := Label.new()
	h.text = "VENDORS"
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_theme_font_size_override("font_size", 12)
	h.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	header.add_child(h)
	var note := Label.new()
	note.text = "Tap a vendor to trade" if _has_convoy() else "Browse only · convoy needed to trade"
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	header.add_child(note)
	col.add_child(header)

	if vendors.is_empty():
		var empty := Label.new()
		# A blank-but-present settlement usually means data is still loading.
		empty.text = "Loading vendors…" if (_has_convoy() and _settlement.is_empty()) else "No vendors here."
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		col.add_child(empty)
		return

	# Big side-by-side vendor cards (no scroll).
	var grid := GridContainer.new()
	var card_h := 132.0 if portrait else 120.0
	if portrait:
		grid.columns = 2
	else:
		grid.columns = clampi(int(ceil(vendors.size() / 2.0)), 2, 4)
	grid.add_theme_constant_override("h_separation", UITheme.SPACE_MD)
	grid.add_theme_constant_override("v_separation", UITheme.SPACE_MD)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(grid)

	for v_any in vendors:
		if v_any is Dictionary:
			grid.add_child(_make_vendor_card(v_any, card_h))

func _make_warehouse_card(card_h: float) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = card_h
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.METAL_BASE
	style.set_border_width_all(2)
	style.border_color = UITheme.ACCENT_BRASS
	style.set_corner_radius_all(UITheme.RADIUS_LG)
	style.content_margin_left = UITheme.SPACE_MD + 2
	style.content_margin_right = UITheme.SPACE_MD + 2
	style.content_margin_top = UITheme.SPACE_MD
	style.content_margin_bottom = UITheme.SPACE_MD
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		var hit := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
		hit = hit or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
		if hit:
			_on_warehouse_pressed()
	)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", UITheme.SPACE_SM)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITheme.SPACE_SM)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wh_icon := load("res://Assets/Icons/warehouse.svg")
	if wh_icon != null:
		var icon := TextureRect.new()
		icon.texture = wh_icon
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = UITheme.ACCENT_BRASS
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(icon)
	var name_l := Label.new()
	name_l.text = "Warehouse"
	name_l.add_theme_font_size_override("font_size", 17)
	name_l.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(name_l)
	vb.add_child(head)

	var hint := Label.new()
	hint.text = "Store cargo and vehicles here" if _has_convoy() else "Browse storage · bring a convoy to retrieve"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hint)

	var foot := Label.new()
	foot.text = "Open ›"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.add_theme_font_size_override("font_size", 13)
	foot.add_theme_color_override("font_color", UITheme.ACCENT_BRASS)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(foot)
	return panel

func _make_vendor_card(vendor: Dictionary, card_h: float = 96.0) -> Control:
	var tappable := _has_convoy()
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = card_h
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.METAL_BASE
	style.set_border_width_all(2 if tappable else UITheme.BORDER_THIN)
	# Tappable cards wear the brass owned-action accent; browse-only cards keep the muted metal edge.
	style.border_color = UITheme.ACCENT_BRASS if tappable else UITheme.METAL_EDGE
	style.set_corner_radius_all(UITheme.RADIUS_LG)
	style.content_margin_left = UITheme.SPACE_MD + 2
	style.content_margin_right = UITheme.SPACE_MD + 2
	style.content_margin_top = UITheme.SPACE_MD
	style.content_margin_bottom = UITheme.SPACE_MD
	panel.add_theme_stylebox_override("panel", style)

	if tappable:
		var vid := String(vendor.get("vendor_id", ""))
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(func(ev: InputEvent) -> void:
			var hit := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
			hit = hit or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
			if hit:
				_on_vendor_row_pressed(vid)
		)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", UITheme.SPACE_SM)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)

	var name_l := Label.new()
	name_l.text = String(vendor.get("name", "Vendor"))
	name_l.add_theme_font_size_override("font_size", 17)
	name_l.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_l)

	var deals := _vendor_deals_summary(vendor)
	if deals != "":
		var deals_l := Label.new()
		deals_l.text = deals
		deals_l.add_theme_font_size_override("font_size", 12)
		deals_l.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		deals_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		deals_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		deals_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(deals_l)

	if tappable:
		var foot := Label.new()
		foot.text = "Trade ›"
		foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		foot.add_theme_font_size_override("font_size", 13)
		foot.add_theme_color_override("font_color", UITheme.ACCENT_BRASS)
		foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(foot)
	return panel

func _on_vendor_row_pressed(vendor_id: String) -> void:
	if not _has_convoy() or vendor_id == "":
		return
	emit_signal("open_vendor_requested", _convoy_data.duplicate(true), vendor_id)

## A short "what this vendor deals in" summary built from the snapshot dict — no async load needed.
func _vendor_deals_summary(vendor: Dictionary) -> String:
	var tags: Array[String] = []
	var resources: Array[String] = []
	for r in _RESOURCE_KEYS:
		if float(vendor.get(r + "_price", 0.0)) > 0.0 or float(vendor.get(r, 0.0)) > 0.0:
			resources.append(r.capitalize())
	if not resources.is_empty():
		tags.append(", ".join(resources))
	if _array_has_items(vendor.get("vehicle_inventory", [])):
		tags.append("Vehicles")
	var cargo: Variant = vendor.get("cargo_inventory", vendor.get("inventory", []))
	if _array_has_items(cargo):
		tags.append("Goods")
	return " · ".join(tags)

func _array_has_items(v: Variant) -> bool:
	return v is Array and not (v as Array).is_empty()

func _vendor_list() -> Array:
	var v: Variant = _settlement.get("vendors", [])
	return v if v is Array else []

func _on_warehouse_pressed() -> void:
	# Carry the convoy when present so the warehouse menu enables retrieve-into-convoy; otherwise the
	# warehouse opens in browse/deposit-disabled mode (it gates on convoy_id itself).
	var payload: Dictionary = _convoy_data.duplicate(true) if _has_convoy() else {}
	payload["settlement"] = _settlement.duplicate(true)
	var sid := String(_settlement.get("sett_id", _settlement.get("id", "")))
	if sid != "":
		payload["sett_id"] = sid
	var sname := String(_settlement.get("name", ""))
	if sname != "":
		payload["settlement_name"] = sname
	emit_signal("open_warehouse_menu_requested", payload)

# --- small helpers ---

func _is_mobile() -> bool:
	var dsm = get_node_or_null("/root/DeviceStateManager")
	return is_instance_valid(dsm) and bool(dsm.is_mobile)

func _is_portrait() -> bool:
	var dsm = get_node_or_null("/root/DeviceStateManager")
	if is_instance_valid(dsm) and dsm.has_method("get_is_portrait"):
		return bool(dsm.get_is_portrait())
	if is_inside_tree():
		var s := get_viewport_rect().size
		return s.y > s.x
	return false

func _style_metal_button(b: Button, accent: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.METAL_BASE
	normal.set_border_width_all(UITheme.BORDER_THIN)
	normal.border_color = UITheme.ACCENT_BRASS if accent else UITheme.METAL_EDGE
	normal.set_corner_radius_all(UITheme.RADIUS_MD)
	normal.content_margin_left = UITheme.SPACE_MD
	normal.content_margin_right = UITheme.SPACE_MD
	normal.content_margin_top = UITheme.SPACE_SM
	normal.content_margin_bottom = UITheme.SPACE_SM
	var hover := normal.duplicate(); hover.bg_color = UITheme.METAL_HOVER
	var pressed := normal.duplicate(); pressed.bg_color = UITheme.METAL_ACTIVE
	for st in [["normal", normal], ["hover", hover], ["pressed", pressed], ["focus", hover]]:
		b.add_theme_stylebox_override(st[0], st[1])
	b.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
