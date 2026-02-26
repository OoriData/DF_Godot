extends CanvasLayer
class_name SteamLinkPopup

signal closed

# Steam colour palette
const _STEAM_BLUE   := Color("#1b2838")
const _STEAM_LIGHT  := Color("#c6d4df")
const _STEAM_ACCENT := Color("#66c0f4")
const _STEAM_GREEN  := Color("#4c6b22")
const _STEAM_GREEN_HL := Color("#a4d007")
const _ERROR_RED    := Color("#c73232")

var _overlay: Control
var _root: VBoxContainer
var _steam_id_input: LineEdit
var _status_label: Label
var _link_button: Button
var _close_button: Button

var _api: Node
var _steam_mgr: Node

func _ready() -> void:
	_api = get_node_or_null("/root/APICalls")
	_steam_mgr = get_node_or_null("/root/SteamManager")
	layer = 101 # Same as AccountMergeModal
	visible = false
	_build_ui()

func open_centered() -> void:
	show()
	call_deferred("_on_opened")

func _on_opened() -> void:
	# Try to auto-populate from SteamManager
	_status_label.text = ""
	if is_instance_valid(_steam_mgr) and _steam_mgr.has_method("get_steam_id"):
		var sid: String = _steam_mgr.get_steam_id()
		if sid != "":
			_steam_id_input.text = sid
			var persona := ""
			if _steam_mgr.has_method("get_steam_username"):
				persona = _steam_mgr.get_steam_username()
			var hint := "Detected Steam ID: %s" % sid
			if persona != "":
				hint = "Detected Steam Account: '%s'" % persona
			_status_label.add_theme_color_override("font_color", _STEAM_ACCENT)
			_status_label.text = hint
	_link_button.disabled = false

# ── Build UI ─────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen overlay
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var panel := PanelContainer.new()
	# Panel background
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _STEAM_BLUE
	panel_style.border_color = _STEAM_ACCENT
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left    = 10
	panel_style.corner_radius_top_right   = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", panel_style)
	
	_overlay.add_child(panel)
	panel.custom_minimum_size = Vector2(380, 180)
	panel.layout_mode = 1 # Anchors
	panel.anchors_preset = Control.PRESET_CENTER
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)
	_root = root

	# Title row
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	root.add_child(title_row)

	var title_lbl := Label.new()
	title_lbl.text = "🎮  Link Steam Account"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", _STEAM_LIGHT)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_lbl)

	# Description
	var desc := Label.new()
	desc.text = "Link your Steam account to your DF profile."
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", _STEAM_LIGHT.darkened(0.25))
	root.add_child(desc)

	# Input row
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	root.add_child(input_row)

	var input_lbl := Label.new()
	input_lbl.text = "Steam ID:"
	input_lbl.add_theme_color_override("font_color", _STEAM_LIGHT)
	input_lbl.add_theme_font_size_override("font_size", 13)
	input_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	input_row.add_child(input_lbl)

	_steam_id_input = LineEdit.new()
	_steam_id_input.placeholder_text = "e.g. 76561198012345678"
	_steam_id_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_steam_id_input.add_theme_color_override("font_color", _STEAM_LIGHT)
	input_row.add_child(_steam_id_input)

	# Status label (success / error messages)
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status_label)

	# Button row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	root.add_child(btn_row)

	_link_button = Button.new()
	_link_button.text = "Link Account"
	_link_button.custom_minimum_size = Vector2(130, 34)
	_apply_steam_button_style(_link_button)
	_link_button.pressed.connect(_on_link_pressed)
	btn_row.add_child(_link_button)

	_close_button = Button.new()
	_close_button.text = "Cancel"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(_on_close_pressed)
	btn_row.add_child(_close_button)

# ── Button handlers ───────────────────────────────────────────────────────────

func _on_close_pressed() -> void:
	hide()
	closed.emit()

func _on_link_pressed() -> void:
	var sid := _steam_id_input.text.strip_edges()
	if sid.is_empty():
		_show_error("Please enter a Steam ID.")
		return

	if not is_instance_valid(_api):
		_show_error("API not available. Please try again.")
		return

	_link_button.disabled = true
	_set_status("Linking…", _STEAM_ACCENT)

	# Grab persona if SteamManager is live
	var persona := ""
	if is_instance_valid(_steam_mgr) and _steam_mgr.has_method("get_steam_username"):
		persona = _steam_mgr.get_steam_username()

	# Connect one-shot to the signal before calling
	if not _api.steam_account_linked.is_connected(_on_steam_link_result):
		_api.steam_account_linked.connect(_on_steam_link_result)

	_api.link_steam_account(sid, persona)

func _on_steam_link_result(result: Dictionary) -> void:
	# Disconnect so we don't accumulate connections on retries
	if _api.steam_account_linked.is_connected(_on_steam_link_result):
		_api.steam_account_linked.disconnect(_on_steam_link_result)

	_link_button.disabled = false

	if result.get("ok", false):
		var linked_id := String(result.get("steam_id", ""))
		_set_status("✅  Linked! Steam ID: %s" % linked_id, _STEAM_GREEN_HL)
		
		# Proactively alert other systems (like AccountLinksPopup) that user identity changed
		var hub := get_node_or_null("/root/SignalHub")
		if is_instance_valid(hub) and hub.has_signal("user_refresh_requested"):
			hub.user_refresh_requested.emit()

		# Auto-close after 2 seconds
		await get_tree().create_timer(2.0).timeout
		if is_inside_tree():
			hide()
			closed.emit()
	else:
		var code: int = result.get("error_code", 0)
		var msg: String = result.get("message", "Unknown error.")
		match code:
			400:
				_show_error("Invalid Steam ID or already linked to this account.")
			409:
				# Pass conflict data to the merge modal
				_open_merge_modal(result.get("conflict", {}))
			_:
				_show_error("Error %d: %s" % [code, msg])


func _open_merge_modal(conflict: Dictionary) -> void:
	_set_status("Account conflict detected — merge required.", _STEAM_ACCENT)
	# Hide this popup while merge modal is open
	hide()
	var script := load("res://Scripts/UI/account_merge_modal.gd")
	if script == null:
		push_error("[SteamLinkPopup] Failed to load account_merge_modal.gd")
		_show_error("This Steam account is already linked to another DF profile.")
		show()
		return
	var modal = script.new()
	get_tree().root.add_child(modal)
	if modal.has_signal("merge_done"):
		modal.merge_done.connect(_on_merge_done)
	if modal.has_signal("cancelled"):
		modal.cancelled.connect(_on_merge_cancelled)
	if modal.has_method("open_with_conflict"):
		modal.open_with_conflict(conflict)
	else:
		modal.popup_centered(Vector2i(400, 300))


func _on_merge_done(user_id: String) -> void:
	# Merge committed — refresh session then close this popup
	var hub := get_node_or_null("/root/SignalHub")
	if is_instance_valid(hub) and hub.has_signal("user_refresh_requested"):
		hub.user_refresh_requested.emit()
	_set_status("✅  Accounts merged! Refreshing…", _STEAM_GREEN_HL)
	show()
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree():
		hide()
		closed.emit()


func _on_merge_cancelled() -> void:
	# User cancelled merge — re-show link popup so they can try again or close
	show()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _set_status(text: String, color: Color) -> void:
	_status_label.add_theme_color_override("font_color", color)
	_status_label.text = text

func _show_error(text: String) -> void:
	_set_status(text, _ERROR_RED)

func _apply_steam_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = _STEAM_ACCENT
	normal.set_corner_radius_all(7)
	normal.content_margin_left  = 16
	normal.content_margin_right = 16

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = _STEAM_ACCENT.lightened(0.15)

	var pressed_sb := normal.duplicate() as StyleBoxFlat
	pressed_sb.bg_color = _STEAM_ACCENT.darkened(0.2)

	var disabled_sb := normal.duplicate() as StyleBoxFlat
	disabled_sb.bg_color = _STEAM_ACCENT.darkened(0.45)

	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  pressed_sb)
	btn.add_theme_stylebox_override("disabled", disabled_sb)
	btn.add_theme_color_override("font_color",          Color("#1b2838"))
	btn.add_theme_color_override("font_disabled_color", Color("#1b2838").lightened(0.3))
