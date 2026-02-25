extends CanvasLayer
class_name AccountMergeModal

signal merge_done(user_id: String)
signal cancelled

# Palette — neutral warning theme
const _BG_COLOR     := Color("#1a1a2e")
const _BORDER_COLOR := Color("#e94560")
const _TEXT_LIGHT   := Color("#eaeaea")
const _TEXT_DIM     := Color("#9a9ab0")
const _ACCENT       := Color("#e94560")
const _GREEN        := Color("#a4d007")
const _ERROR_RED    := Color("#c73232")

var _merge_token: String = ""
var _source_id: String = ""
var _target_id: String = ""
var _preview_loaded: bool = false

var _overlay: Control
var _summary_label: RichTextLabel
var _status_label: Label
var _preview_btn: Button
var _confirm_btn: Button
var _cancel_btn: Button
var _confirm_dialog: ConfirmationDialog

var _api: Node

func _ready() -> void:
	_api = get_node_or_null("/root/APICalls")
	layer = 101 # Above AccountLinksPopup
	visible = false
	_build_ui()

# Called by steam_link_popup with the conflict dict from the 409 payload.
func open_with_conflict(conflict: Dictionary) -> void:
	show()
	_merge_token = String(conflict.get("merge_token", ""))
	_target_id = String(conflict.get("existing_user_id", ""))
	_source_id = ""
	if is_instance_valid(_api) and _api.has_method("get_current_user_id"):
		_source_id = _api.call("get_current_user_id")
	elif is_instance_valid(_api) and "current_user_id" in _api:
		_source_id = _api.current_user_id
	
	_preview_loaded = false
	_confirm_btn.disabled = true

	# Pre-populate any summary text the backend already sent
	var existing_summary = conflict.get("summary", conflict.get("description", ""))
	if existing_summary is Array and (existing_summary as Array).size() > 0:
		_render_summary(existing_summary as Array)
	elif existing_summary is String and existing_summary != "":
		_summary_label.text = "[color=#9a9ab0]%s[/color]" % existing_summary
	else:
		_summary_label.text = "[color=#9a9ab0]Click Preview to see which data will be merged.[/color]"

# ── Build UI ─────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen overlay
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
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
	
	panel.custom_minimum_size = Vector2(400, 320)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# Title
	var title := Label.new()
	title.text = "⚠  Account Conflict — Merge Required"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", _ACCENT)
	root.add_child(title)

	# Explanation
	var info := Label.new()
	info.text = "This account is already linked to another DF profile.\n\nThe more recently created account will be deleted, and your login will be permanently tied to the older account. This cannot be undone."
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", _TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info)

	# Divider
	var sep := HSeparator.new()
	root.add_child(sep)

	# Summary area (scrollable rich text)
	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = false
	_summary_label.custom_minimum_size = Vector2(0, 80)
	_summary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary_label.add_theme_font_size_override("normal_font_size", 12)
	_summary_label.text = "[color=#9a9ab0]Click Preview to see which data will be merged.[/color]"
	root.add_child(_summary_label)

	# Status label
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status_label)

	# Button row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	root.add_child(btn_row)

	_preview_btn = Button.new()
	_preview_btn.text = "Preview Merge"
	_preview_btn.custom_minimum_size = Vector2(120, 32)
	_apply_button_style(_preview_btn, Color("#3a7bd5"))
	_preview_btn.pressed.connect(_on_preview_pressed)
	btn_row.add_child(_preview_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm Merge"
	_confirm_btn.custom_minimum_size = Vector2(120, 32)
	_confirm_btn.disabled = true
	_apply_button_style(_confirm_btn, _ACCENT)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	btn_row.add_child(_confirm_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.focus_mode = Control.FOCUS_NONE
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(_cancel_btn)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Confirm Account Deletion"
	_confirm_dialog.dialog_text = "The more recently created account will be DELETED.\nYour login will be permanently tied to the older account.\nThis CANNOT be undone.\n\nAre you absolutely sure you want to proceed?"
	_confirm_dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_dialog.confirmed.connect(_on_real_confirm_pressed)
	_confirm_dialog.get_ok_button().focus_mode = Control.FOCUS_NONE
	add_child(_confirm_dialog)

# ── Button handlers ───────────────────────────────────────────────────────────

func _on_cancel_pressed() -> void:
	hide()
	cancelled.emit()
	queue_free()

func _on_preview_pressed() -> void:
	if _merge_token.is_empty():
		_show_status("No merge token available — cannot preview.", _ERROR_RED)
		return
	if not is_instance_valid(_api):
		_show_status("API unavailable. Please try again.", _ERROR_RED)
		return

	_preview_btn.disabled = true
	_show_status("Loading preview…", Color("#9a9ab0"))

	if not _api.merge_preview_received.is_connected(_on_preview_result):
		_api.merge_preview_received.connect(_on_preview_result)
	_api.preview_merge(_merge_token, _source_id, _target_id)

func _on_preview_result(result: Dictionary) -> void:
	if _api.merge_preview_received.is_connected(_on_preview_result):
		_api.merge_preview_received.disconnect(_on_preview_result)

	_preview_btn.disabled = false

	if result.get("ok", false):
		# Refresh token in case backend rotated it
		var new_token := String(result.get("merge_token", _merge_token))
		if new_token != "":
			_merge_token = new_token

		var summary = result.get("summary", [])
		_render_summary(summary)
		_preview_loaded = true
		_confirm_btn.disabled = false
		_show_status("Review the merge summary above, then confirm.", _TEXT_DIM)
	else:
		var msg := String(result.get("message", "Preview failed."))
		_show_status("Preview failed: %s" % msg, _ERROR_RED)

func _on_confirm_pressed() -> void:
	if not _preview_loaded:
		_show_status("Please preview before confirming.", _ERROR_RED)
		return
	if _merge_token.is_empty():
		_show_status("No merge token — cannot commit.", _ERROR_RED)
		return
	if not is_instance_valid(_api):
		_show_status("API unavailable.", _ERROR_RED)
		return

	_confirm_dialog.popup_centered()

func _on_real_confirm_pressed() -> void:
	_confirm_btn.disabled = true
	_preview_btn.disabled = true
	_cancel_btn.disabled  = true
	_show_status("Committing merge…", Color("#9a9ab0"))

	if not _api.merge_committed.is_connected(_on_commit_result):
		_api.merge_committed.connect(_on_commit_result)
	_api.commit_merge(_merge_token, _source_id, _target_id)

func _on_commit_result(result: Dictionary) -> void:
	if _api.merge_committed.is_connected(_on_commit_result):
		_api.merge_committed.disconnect(_on_commit_result)

	if result.get("ok", false):
		var uid := String(result.get("user_id", ""))
		_show_status("✅  Merge complete!", _GREEN)
		await get_tree().create_timer(1.5).timeout
		hide()
		merge_done.emit(uid)
		queue_free()
	else:
		_confirm_btn.disabled = false
		_preview_btn.disabled = false
		_cancel_btn.disabled  = false
		var msg := String(result.get("message", "Merge failed."))
		var code: int = result.get("error_code", 0)
		match code:
			401, 403:
				_show_status("Invalid or expired merge token. Please re-link to get a fresh token.", _ERROR_RED)
			409:
				_show_status("Ownership mismatch — merge cannot proceed.", _ERROR_RED)
			_:
				_show_status("Merge failed (%d): %s" % [code, msg], _ERROR_RED)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _render_summary(items: Array) -> void:
	if items.is_empty():
		_summary_label.text = "[color=#9a9ab0]No detailed summary provided by server.[/color]"
		return
	var lines := PackedStringArray()
	for item in items:
		if item is String:
			lines.append("[color=#c6d4df]• %s[/color]" % item)
		elif item is Dictionary:
			var label_str := String(item.get("label", item.get("key", "")))
			var value_str := String(item.get("value", ""))
			if label_str != "":
				lines.append("[color=#66c0f4]%s:[/color] [color=#c6d4df]%s[/color]" % [label_str, value_str])
	_summary_label.text = "\n".join(lines)

func _show_status(text: String, color: Color) -> void:
	_status_label.add_theme_color_override("font_color", color)
	_status_label.text = text

func _apply_button_style(btn: Button, base_color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = base_color
	normal.set_corner_radius_all(7)
	normal.content_margin_left  = 14
	normal.content_margin_right = 14

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = base_color.lightened(0.15)

	var pressed_sb := normal.duplicate() as StyleBoxFlat
	pressed_sb.bg_color = base_color.darkened(0.2)

	var disabled_sb := normal.duplicate() as StyleBoxFlat
	disabled_sb.bg_color = base_color.darkened(0.45)

	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  pressed_sb)
	btn.add_theme_stylebox_override("disabled", disabled_sb)
	btn.add_theme_color_override("font_color",          Color("#ffffff"))
	btn.add_theme_color_override("font_disabled_color", Color("#ffffff").darkened(0.5))
