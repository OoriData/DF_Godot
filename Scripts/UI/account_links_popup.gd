extends CanvasLayer
class_name AccountLinksPopup

signal closed

const _BG_COLOR         := Color("#161616")
const _BORDER_COLOR     := Color("#2e2e2e")
const _TEXT_LIGHT       := Color("#eaeaea")
const _TEXT_DIM         := Color("#9a9ab0")
const _ACCENT_PRIMARY   := Color("#5865F2") # Discord Blurple
const _ACCENT_SECONDARY := Color("#66c0f4") # Steam Light Blue
const _GREEN_SUCCESS    := Color("#a4d007")
const _RED_ERROR        := Color("#e94560")

var _overlay: Control
var _root: VBoxContainer
var _steam_id_label: Label
var _discord_id_label: Label
var _status_label: Label

var _steam_connect_btn: Button
var _discord_connect_btn: Button

var _api: Node
var _hub: Node

func _ready() -> void:
	layer = 100 # High layer to be above other UI
	visible = false
	_api = get_node_or_null("/root/APICalls")
	_hub = get_node_or_null("/root/SignalHub")
	_build_ui()
	_connect_signals()

func open_centered() -> void:
	show()
	_refresh_data()

func _connect_signals() -> void:
	if not is_instance_valid(_api):
		return
	_api.auth_links_received.connect(_on_auth_links_received)
	_api.discord_account_linked.connect(_on_discord_link_result)
	_api.steam_account_linked.connect(_on_steam_link_result)
	_api.discord_link_url_received.connect(_on_discord_url_received)
	
	if not _api.user_data_received.is_connected(_on_user_data_refreshed):
		_api.user_data_received.connect(_on_user_data_refreshed)

func _refresh_data() -> void:
	_set_status("Refreshing linked accounts...", _TEXT_DIM)
	if is_instance_valid(_api):
		var uid: String = ""
		if is_instance_valid(_hub) and _hub.has_method("get_current_user_id"):
			uid = _hub.get_current_user_id()
		elif _api.has_method("get_current_user_id"):
			uid = _api.call("get_current_user_id")
		elif "current_user_id" in _api:
			uid = _api.current_user_id
			
		if uid != "":
			_api.get_user_data(uid, true)
		else:
			_api.get_auth_links()

func _on_user_data_refreshed(_user_data: Dictionary) -> void:
	if is_instance_valid(_api):
		_api.get_auth_links()

# ── API Handlers ─────────────────────────────────────────────────────────────

func _on_auth_links_received(links: Array) -> void:
	var steam_linked := "Not Linked"
	var discord_linked := "Not Linked"
	
	for link in links:
		var provider = link.get("provider", "")
		var pid = link.get("provider_id", "")
		if provider == "steam":
			steam_linked = pid
		elif provider == "discord":
			discord_linked = pid
			
	# Verify against the user object to ensure the backend actually has the ID bound
	var user_data: Dictionary = {}
	var store := get_node_or_null("/root/GameStore")
	if is_instance_valid(store) and store.has_method("get_user"):
		user_data = store.get_user()
	
	var raw_steam = user_data.get("steam_id")
	var raw_discord = user_data.get("discord_id")
	var actual_steam_id := "" if raw_steam == null else str(raw_steam)
	var actual_discord_id := "" if raw_discord == null else str(raw_discord)
	
	if actual_steam_id == "<null>":
		actual_steam_id = ""
	if actual_discord_id == "<null>":
		actual_discord_id = ""
	
	if steam_linked != "Not Linked" and actual_steam_id != "":
		_steam_id_label.text = "✅ Connected"
		_steam_id_label.add_theme_color_override("font_color", _GREEN_SUCCESS)
	else:
		steam_linked = "Not Linked"
		_steam_id_label.text = "Not Linked"
		_steam_id_label.add_theme_color_override("font_color", _TEXT_DIM)
	
	if discord_linked != "Not Linked" and actual_discord_id != "":
		_discord_id_label.text = "✅ Connected"
		_discord_id_label.add_theme_color_override("font_color", _GREEN_SUCCESS)
	else:
		discord_linked = "Not Linked"
		_discord_id_label.text = "Not Linked"
		_discord_id_label.add_theme_color_override("font_color", _TEXT_DIM)
	
	_steam_connect_btn.disabled = (steam_linked != "Not Linked")
	_discord_connect_btn.disabled = (discord_linked != "Not Linked")
	
	_set_status("Accounts updated.", _GREEN_SUCCESS)
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree() and _status_label.text == "Accounts updated.":
		_set_status("", _TEXT_DIM)

func _on_discord_url_received(url: String, state: String) -> void:
	if url == "" or state == "":
		_set_status("Failed to get linking URL.", _RED_ERROR)
		_discord_connect_btn.disabled = false
		return
		
	_set_status("Opening browser... Poll started.", _ACCENT_PRIMARY)
	OS.shell_open(url)
	_api.start_auth_poll(state)

func _on_discord_link_result(result: Dictionary) -> void:
	_discord_connect_btn.disabled = false
	if result.get("ok", false):
		_set_status("✅ Discord linked!", _GREEN_SUCCESS)
		_refresh_data()
	else:
		var code = result.get("error_code", 0)
		if code == 409:
			_open_merge_modal(result.get("conflict", {}))
		else:
			_set_status("Error: %s" % result.get("message", "Link failed"), _RED_ERROR)

func _on_steam_link_result(result: Dictionary) -> void:
	if result.get("ok", false):
		_set_status("✅ Steam linked!", _GREEN_SUCCESS)
		_refresh_data()
	else:
		var code = result.get("error_code", 0)
		if code == 409:
			_open_merge_modal(result.get("conflict", {}))
		else:
			_set_status("Error: %s" % result.get("message", "Link failed"), _RED_ERROR)

# ── UI Actions ───────────────────────────────────────────────────────────────

func _on_connect_discord_pressed() -> void:
	# Open confirmation popup before starting browser flow
	var script := load("res://Scripts/UI/discord_link_popup.gd")
	if script:
		var popup = script.new()
		get_tree().root.add_child(popup)
		popup.open_centered()
		popup.closed.connect(func(): _refresh_data())
	else:
		# Fallback if script missing
		_discord_connect_btn.disabled = true
		_api.get_discord_link_url()

func _on_connect_steam_pressed() -> void:
	# Reuse SteamLinkPopup for the actual Steam ID input
	var script := load("res://Scripts/UI/steam_link_popup.gd")
	if script:
		var popup = script.new()
		get_tree().root.add_child(popup)
		popup.open_centered()
		popup.closed.connect(func(): _refresh_data())

func _open_merge_modal(conflict: Dictionary) -> void:
	hide()
	var script := load("res://Scripts/UI/account_merge_modal.gd")
	if script == null:
		_set_status("Conflict detected but merge modal missing.", _RED_ERROR)
		show()
		return
	var modal = script.new()
	get_tree().root.add_child(modal)
	modal.merge_done.connect(func(_uid):
		_refresh_data()
		show()
	)
	modal.cancelled.connect(func(): show())
	modal.open_with_conflict(conflict)

# ── Build UI ─────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen overlay to block input and stay open
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _BG_COLOR
	panel_style.border_color = _BORDER_COLOR
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", panel_style)
	
	panel.custom_minimum_size = Vector2(420, 260)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	_root = root

	# Title
	var title := Label.new()
	title.text = "Connected Accounts"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", _TEXT_LIGHT)
	root.add_child(title)

	# Divider
	root.add_child(HSeparator.new())

	# Rows Container (with ScrollContainer if it gets long)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 16)
	scroll.add_child(rows)

	# Steam Row
	_steam_id_label = Label.new()
	rows.add_child(_create_row("Steam", _ACCENT_SECONDARY, _steam_id_label, _on_connect_steam_pressed, "SteamRow"))
	_steam_connect_btn = rows.get_node("SteamRow/ConnectBtn")

	# Discord Row
	_discord_id_label = Label.new()
	rows.add_child(_create_row("Discord", _ACCENT_PRIMARY, _discord_id_label, _on_connect_discord_pressed, "DiscordRow"))
	_discord_connect_btn = rows.get_node("DiscordRow/ConnectBtn")

	# Status Label
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	# Close Button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(100, 32)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(func(): hide(); closed.emit())
	root.add_child(close_btn)

func _create_row(label_text: String, accent_color: Color, id_val_label: Label, on_pressed: Callable, node_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var icon_placeholder := ColorRect.new()
	icon_placeholder.custom_minimum_size = Vector2(32, 32)
	icon_placeholder.color = accent_color.darkened(0.5)
	row.add_child(icon_placeholder)
	
	var text_stack := VBoxContainer.new()
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_stack)
	
	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", accent_color)
	text_stack.add_child(name_lbl)
	
	id_val_label.text = "Loading..."
	id_val_label.add_theme_font_size_override("font_size", 11)
	id_val_label.add_theme_color_override("font_color", _TEXT_DIM)
	text_stack.add_child(id_val_label)
	
	var connect_btn := Button.new()
	connect_btn.name = "ConnectBtn"
	connect_btn.text = "Connect"
	connect_btn.custom_minimum_size = Vector2(80, 28)
	connect_btn.pressed.connect(on_pressed)
	row.add_child(connect_btn)
	
	return row

func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
