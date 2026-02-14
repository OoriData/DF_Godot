extends PopupPanel
class_name BugReportWindow

signal closed

var _api: Node
var _store: Node
var _logger: Node
var _convoy_selection_service: Node
var _vendor_service: Node

var _screenshot_png_bytes: PackedByteArray = PackedByteArray()

const MAX_SCREENSHOT_BYTES: int = 1_500_000
const MAX_SCREENSHOT_DIM: int = 1600
const MAX_LOG_LINES: int = 200
const MAX_LOG_CHARS_TOTAL: int = 25_000
const MAX_LOG_LINE_CHARS: int = 500

# UI refs
var _summary: LineEdit
var _steps: TextEdit
var _context: TextEdit

var _include_screenshot: CheckBox
var _include_logs: CheckBox
var _include_metadata: CheckBox
var _consent: CheckBox

var _screenshot_preview: TextureRect
var _status_label: Label
var _submit_button: Button

var _pending: bool = false

var _root: Control

func _ready() -> void:
	_api = get_node_or_null("/root/APICalls")
	_store = get_node_or_null("/root/GameStore")
	_logger = get_node_or_null("/root/Logger")
	_convoy_selection_service = get_node_or_null("/root/ConvoySelectionService")
	_vendor_service = get_node_or_null("/root/VendorService")

	_build_ui()
	_update_submit_enabled()

func set_screenshot_png_bytes(png_bytes: PackedByteArray) -> void:
	_screenshot_png_bytes = png_bytes if png_bytes != null else PackedByteArray()
	_update_preview()

func open_centered() -> void:
	_status("", false)
	_pending = false
	_update_submit_enabled()
	popup_centered(Vector2i(820, 700))
	call_deferred("_refresh_layout")

func _refresh_layout() -> void:
	# Ensure controls compute minimum sizes and lay out on first popup.
	if is_instance_valid(_root):
		_root.queue_sort()
		_root.queue_redraw()
	# Run again next frame; some themes finalize sizes late.
	call_deferred("_refresh_layout_once_more")

func _refresh_layout_once_more() -> void:
	if is_instance_valid(_root):
		_root.queue_sort()
		_root.queue_redraw()

func _on_close_pressed() -> void:
	hide()
	closed.emit()

func _build_ui() -> void:
	# Style the popup panel itself
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#1E1E1E")
	panel_style.border_color = Color("#2E2E2E")
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	# Root content
	var root := VBoxContainer.new()
	root.name = "Root"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)
	_root = root

	# Header row
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "Report Bug"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_color", Color("#FFFFFF"))
	header.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_on_close_pressed)
	header.add_child(close_btn)

	var sep := HSeparator.new()
	root.add_child(sep)

	# Scrollable content (form fields + screenshot preview)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.0
	var scroll_style := StyleBoxFlat.new()
	scroll_style.bg_color = Color("#151515")
	scroll_style.border_color = Color("#2A2A2A")
	scroll_style.set_border_width_all(1)
	scroll_style.corner_radius_top_left = 10
	scroll_style.corner_radius_top_right = 10
	scroll_style.corner_radius_bottom_left = 10
	scroll_style.corner_radius_bottom_right = 10
	scroll.add_theme_stylebox_override("panel", scroll_style)
	root.add_child(scroll)

	# Inner panel so the form is clearly separated from the popup background.
	var content_panel := PanelContainer.new()
	content_panel.name = "ContentPanel"
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content_style := StyleBoxFlat.new()
	content_style.bg_color = Color("#232323")
	content_style.border_color = Color("#3A3A3A")
	content_style.set_border_width_all(1)
	content_style.corner_radius_top_left = 10
	content_style.corner_radius_top_right = 10
	content_style.corner_radius_bottom_left = 10
	content_style.corner_radius_bottom_right = 10
	content_panel.add_theme_stylebox_override("panel", content_style)
	scroll.add_child(content_panel)

	var content_margin := MarginContainer.new()
	content_margin.name = "ContentMargin"
	content_margin.add_theme_constant_override("margin_left", 12)
	content_margin.add_theme_constant_override("margin_right", 12)
	content_margin.add_theme_constant_override("margin_top", 12)
	content_margin.add_theme_constant_override("margin_bottom", 12)
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_panel.add_child(content_margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_child(content)

	# Statement
	var stmt := Label.new()
	stmt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stmt.text = "Submitting sends the information you select (screenshot, logs, game/account metadata) to the developers to help debug. Do not include passwords or secrets."
	content.add_child(stmt)

	# Toggles row
	var toggles := HBoxContainer.new()
	content.add_child(toggles)

	_include_screenshot = CheckBox.new()
	_include_screenshot.text = "Include screenshot"
	_include_screenshot.button_pressed = true
	_include_screenshot.toggled.connect(func(_v): _update_submit_enabled())
	toggles.add_child(_include_screenshot)

	_include_logs = CheckBox.new()
	_include_logs.text = "Include recent logs"
	_include_logs.button_pressed = true
	_include_logs.toggled.connect(func(_v): _update_submit_enabled())
	toggles.add_child(_include_logs)

	_include_metadata = CheckBox.new()
	_include_metadata.text = "Include metadata"
	_include_metadata.button_pressed = true
	_include_metadata.toggled.connect(func(_v): _update_submit_enabled())
	toggles.add_child(_include_metadata)

	# Consent
	_consent = CheckBox.new()
	_consent.text = "I understand and consent to sending the selected data"
	_consent.button_pressed = false
	_consent.toggled.connect(func(_v): _update_submit_enabled())
	content.add_child(_consent)

	_summary = LineEdit.new()
	_summary.placeholder_text = "Summary (required)"
	_summary.text_changed.connect(func(_t): _update_submit_enabled())
	var line_style := StyleBoxFlat.new()
	line_style.bg_color = Color("#121212")
	line_style.border_color = Color("#444444")
	line_style.set_border_width_all(1)
	line_style.corner_radius_top_left = 8
	line_style.corner_radius_top_right = 8
	line_style.corner_radius_bottom_left = 8
	line_style.corner_radius_bottom_right = 8
	line_style.content_margin_left = 10
	line_style.content_margin_right = 10
	line_style.content_margin_top = 8
	line_style.content_margin_bottom = 8
	_summary.add_theme_stylebox_override("normal", line_style)
	content.add_child(_summary)

	_steps = _add_collapsible_text_block(content, "Steps to reproduce", false)
	_context = _add_collapsible_text_block(content, "Additional context", false)

	var preview_label := Label.new()
	preview_label.text = "Screenshot preview"
	content.add_child(preview_label)

	_screenshot_preview = TextureRect.new()
	_screenshot_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screenshot_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_screenshot_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Keep preview from pushing buttons offscreen; content scrolls instead.
	_screenshot_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_screenshot_preview.custom_minimum_size = Vector2(0, 240)
	content.add_child(_screenshot_preview)

	_update_preview()

	var action_sep := HSeparator.new()
	root.add_child(action_sep)

	# Status (fixed below scroll)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = ""
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_status_label)

	# Buttons (fixed below scroll)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_close_pressed)
	btn_row.add_child(cancel_btn)

	_submit_button = Button.new()
	_submit_button.text = "Submit"
	_submit_button.pressed.connect(_on_submit_pressed)
	btn_row.add_child(_submit_button)

func _add_collapsible_text_block(parent: Control, title_text: String, expanded_by_default: bool) -> TextEdit:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)

	var header_btn := Button.new()
	header_btn.toggle_mode = true
	header_btn.button_pressed = expanded_by_default
	header_btn.focus_mode = Control.FOCUS_NONE
	header_btn.text = ("▾  " if expanded_by_default else "▸  ") + title_text
	header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var header_normal := StyleBoxFlat.new()
	header_normal.bg_color = Color("#2B2B2B")
	header_normal.border_color = Color("#3E3E3E")
	header_normal.set_border_width_all(1)
	header_normal.corner_radius_top_left = 8
	header_normal.corner_radius_top_right = 8
	header_normal.corner_radius_bottom_left = 8
	header_normal.corner_radius_bottom_right = 8
	header_normal.content_margin_left = 10
	header_normal.content_margin_right = 10
	header_normal.content_margin_top = 6
	header_normal.content_margin_bottom = 6
	var header_hover := header_normal.duplicate() as StyleBoxFlat
	header_hover.bg_color = Color("#333333")
	var header_pressed := header_normal.duplicate() as StyleBoxFlat
	header_pressed.bg_color = Color("#262626")
	header_btn.add_theme_stylebox_override("normal", header_normal)
	header_btn.add_theme_stylebox_override("hover", header_hover)
	header_btn.add_theme_stylebox_override("pressed", header_pressed)
	header_btn.add_theme_color_override("font_color", Color("#FFFFFF"))
	box.add_child(header_btn)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.visible = expanded_by_default
	box.add_child(inner)

	var te := TextEdit.new()
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	te.custom_minimum_size = Vector2(0, 90)
	var te_style := StyleBoxFlat.new()
	te_style.bg_color = Color("#101010")
	te_style.border_color = Color("#3E3E3E")
	te_style.set_border_width_all(1)
	te_style.corner_radius_top_left = 8
	te_style.corner_radius_top_right = 8
	te_style.corner_radius_bottom_left = 8
	te_style.corner_radius_bottom_right = 8
	te_style.content_margin_left = 10
	te_style.content_margin_right = 10
	te_style.content_margin_top = 10
	te_style.content_margin_bottom = 10
	te.add_theme_stylebox_override("normal", te_style)
	te.text_changed.connect(func(): _update_submit_enabled())
	inner.add_child(te)

	header_btn.toggled.connect(func(on: bool):
		inner.visible = on
		header_btn.text = ("▾  " if on else "▸  ") + title_text
		if is_instance_valid(_root):
			_root.queue_sort()
			_root.queue_redraw()
	)

	return te

func _update_preview() -> void:
	if not is_instance_valid(_screenshot_preview):
		return
	if _screenshot_png_bytes.is_empty():
		_screenshot_preview.texture = null
		return
	var img := Image.new()	
	var err := img.load_png_from_buffer(_screenshot_png_bytes)
	if err != OK:
		_screenshot_preview.texture = null
		return
	var tex := ImageTexture.create_from_image(img)
	_screenshot_preview.texture = tex

func _update_submit_enabled() -> void:
	if not is_instance_valid(_submit_button):
		return
	var summary_ok := _summary != null and _summary.text.strip_edges() != ""
	_submit_button.disabled = _pending or (not summary_ok) or (not _consent.button_pressed)

func _status(msg: String, is_error: bool) -> void:
	if not is_instance_valid(_status_label):
		return
	_status_label.text = msg
	_status_label.modulate = Color(1, 0.35, 0.35) if is_error else Color(1, 1, 1)

func _on_submit_pressed() -> void:
	if _pending:
		return
	if not is_instance_valid(_api) or not _api.has_method("submit_bug_report"):
		_status("Bug report submission unavailable (APICalls.submit_bug_report missing).", true)
		return
	if _summary.text.strip_edges() == "":
		_status("Summary is required.", true)
		return
	if not _consent.button_pressed:
		_status("Consent is required to submit.", true)
		return

	_pending = true
	_update_submit_enabled()
	_status("Submitting...", false)

	# Connect once for completion
	if _api.has_signal("bug_report_submitted"):
		if not _api.bug_report_submitted.is_connected(_on_bug_report_submitted):
			_api.bug_report_submitted.connect(_on_bug_report_submitted)
	if _api.has_signal("fetch_error"):
		if not _api.fetch_error.is_connected(_on_bug_report_error):
			_api.fetch_error.connect(_on_bug_report_error)

	var payload := _build_payload()
	_api.submit_bug_report(payload)

func _disconnect_api_signals() -> void:
	if not is_instance_valid(_api):
		return
	if _api.has_signal("bug_report_submitted") and _api.bug_report_submitted.is_connected(_on_bug_report_submitted):
		_api.bug_report_submitted.disconnect(_on_bug_report_submitted)
	if _api.has_signal("fetch_error") and _api.fetch_error.is_connected(_on_bug_report_error):
		_api.fetch_error.disconnect(_on_bug_report_error)

func _build_payload() -> Dictionary:
	var warnings: Array[String] = []
	var summary_text := _summary.text.strip_edges()
	var steps_text := _steps.text.strip_edges()
	var context_text := _context.text.strip_edges()

	var desc_parts: Array[String] = []
	desc_parts.append("## Summary\n" + summary_text)
	if steps_text != "":
		desc_parts.append("## Steps to reproduce\n" + steps_text)
	if context_text != "":
		desc_parts.append("## Additional context\n" + context_text)
	var payload: Dictionary = {
		# Backend currently validates `title` (see FastAPI 422 error). Keep `summary` for client readability.
		"title": summary_text,
		"summary": summary_text,
		# Backend also validates `description`; provide a GitHub-issue-friendly markdown body.
		"description": "\n\n".join(desc_parts),
		# Provide a couple of common variants so server-side models can evolve without breaking clients.
		"steps_to_repro": steps_text,
		"steps_to_reproduce": steps_text,
		"steps": steps_text,
		"additional_context": context_text,
		"consent": true,
	}

	if _include_screenshot.button_pressed and not _screenshot_png_bytes.is_empty():
		var s := _build_screenshot_payload(warnings)
		if not s.is_empty():
			payload["screenshot"] = s

	if _include_logs.button_pressed:
		var recent := _get_recent_logs()
		payload["logs"] = {
			"recent_lines": recent,
		}
		if recent.size() > 0:
			payload["description"] += "\n\n## Logs (recent)\n```\n" + "\n".join(recent) + "\n```"

	if _include_metadata.button_pressed:
		var meta := _collect_metadata()
		payload["meta"] = meta
		if not meta.is_empty():
			payload["description"] += "\n\n## Metadata\n```json\n" + JSON.stringify(meta, "\t") + "\n```"

	if not warnings.is_empty():
		payload["client_warnings"] = warnings

	return payload

func _build_screenshot_payload(warnings: Array[String]) -> Dictionary:
	# Ensure screenshot is below MAX_SCREENSHOT_BYTES. Attempt a resize if too large.
	var bytes := _screenshot_png_bytes
	if bytes.is_empty():
		return {}
	if bytes.size() <= MAX_SCREENSHOT_BYTES:
		return {"mime": "image/png", "base64": Marshalls.raw_to_base64(bytes)}

	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		warnings.append("Screenshot too large and could not be re-encoded; omitted.")
		return {}

	var w: int = int(img.get_width())
	var h: int = int(img.get_height())
	var max_dim: int = (w if w > h else h)
	if max_dim > MAX_SCREENSHOT_DIM:
		var scale := float(MAX_SCREENSHOT_DIM) / float(max_dim)
		var nw: int = int(round(float(w) * scale))
		var nh: int = int(round(float(h) * scale))
		if nw < 1:
			nw = 1
		if nh < 1:
			nh = 1
		img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	else:
		# Already within dim; try re-encoding as-is.
		pass

	var resized_bytes := img.save_png_to_buffer()
	if resized_bytes.size() > MAX_SCREENSHOT_BYTES:
		warnings.append("Screenshot exceeded size limit; omitted.")
		return {}
	warnings.append("Screenshot was resized to fit upload limits.")
	return {"mime": "image/png", "base64": Marshalls.raw_to_base64(resized_bytes)}

func _get_recent_logs() -> Array:
	if is_instance_valid(_logger) and (_logger.has_method("get_recent_lines_since") or _logger.has_method("get_recent_lines")):
		var raw: Array = []
		# Prefer a small time window to keep payloads bounded.
		if _logger.has_method("get_recent_lines_since"):
			raw = _logger.get_recent_lines_since(20.0, MAX_LOG_LINES)
		else:
			raw = _logger.get_recent_lines(MAX_LOG_LINES)
		var out: Array[String] = []
		var total_chars := 0
		for line_any in raw:
			var line := str(line_any)
			if line.length() > MAX_LOG_LINE_CHARS:
				line = line.substr(0, MAX_LOG_LINE_CHARS) + "…"
			if total_chars + line.length() > MAX_LOG_CHARS_TOTAL:
				break
			total_chars += line.length()
			out.append(line)
		return out
	return []

func _trim_dict(d: Dictionary, keys: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	for k in keys:
		if d.has(k):
			out[k] = d.get(k)
	return out

func _collect_metadata() -> Dictionary:
	var user: Dictionary = {}
	if is_instance_valid(_store) and _store.has_method("get_user"):
		user = _store.get_user()

	var convoys: Array = []
	if is_instance_valid(_store) and _store.has_method("get_convoys"):
		convoys = _store.get_convoys()

	var selected_convoy: Variant = null
	if is_instance_valid(_convoy_selection_service) and _convoy_selection_service.has_method("get_selected_convoy"):
		selected_convoy = _convoy_selection_service.get_selected_convoy()
	var selected_convoy_trimmed: Variant = null
	var selected_convoy_id := ""
	var selected_settlement_id := ""
	if selected_convoy is Dictionary:
		var scd := selected_convoy as Dictionary
		selected_convoy_id = str(scd.get("convoy_id", scd.get("id", "")))
		selected_settlement_id = str(scd.get("settlement_id", scd.get("sett_id", "")))
		selected_convoy_trimmed = _trim_dict(scd, [
			"convoy_id",
			"id",
			"convoy_name",
			"name",
			"status",
			"state",
			"x",
			"y",
			"sett_id",
			"settlement_id",
		])

	var last_vendor_id := ""
	var last_vendor_trimmed: Variant = null
	if is_instance_valid(_vendor_service):
		if _vendor_service.has_method("get_last_vendor_id"):
			last_vendor_id = str(_vendor_service.get_last_vendor_id())
		if _vendor_service.has_method("get_last_vendor_data"):
			var vd_any: Variant = _vendor_service.get_last_vendor_data()
			if vd_any is Dictionary and not (vd_any as Dictionary).is_empty():
				last_vendor_trimmed = _trim_dict((vd_any as Dictionary), [
					"vendor_id",
					"id",
					"name",
					"vendor_name",
					"settlement_id",
					"sett_id",
				])

	var ver_info := Engine.get_version_info()
	var godot_ver := str(ver_info.get("string", ""))

	var project_name := str(ProjectSettings.get_setting("application/config/name", ""))
	var project_ver := str(ProjectSettings.get_setting("application/config/version", ""))

	var current_scene_name := ""
	if get_tree() != null and get_tree().current_scene != null:
		current_scene_name = str(get_tree().current_scene.name)

	return {
		"client_time_unix": Time.get_unix_time_from_system(),
		"context": {
			"convoy_id": selected_convoy_id,
			"settlement_id": selected_settlement_id,
			"vendor_id": last_vendor_id,
		},
		"os": {
			"name": OS.get_name(),
			"version": OS.get_version(),
			"locale": OS.get_locale(),
		},
		"engine": {
			"godot": godot_ver,
			"features": {
				"editor": OS.has_feature("editor"),
				"standalone": OS.has_feature("standalone"),
				"debug": OS.has_feature("debug"),
			},
		},
		"game": {
			"project": project_name,
			"version": project_ver,
		},
		"scene": {
			"current": current_scene_name,
		},
		"user": {
			"id": str(user.get("user_id", user.get("id", ""))),
			"username": str(user.get("username", "")),
		},
		"convoys": {
			"count": convoys.size(),
			"selected_id": selected_convoy_id,
			"selected": selected_convoy_trimmed,
		},
		"vendor": {
			"last_id": last_vendor_id,
			"last": last_vendor_trimmed,
		}
	}

func _on_bug_report_submitted(result: Variant) -> void:
	if not _pending:
		return
	_pending = false
	_update_submit_enabled()
	_disconnect_api_signals()

	var issue_url := ""
	var msg := "Bug report submitted. Thanks!"
	if result is Dictionary:
		issue_url = str((result as Dictionary).get("issue_url", ""))
		if issue_url != "":
			msg = "Bug report submitted. Issue: %s" % issue_url
	_status(msg, false)

func _on_bug_report_error(err_msg: String) -> void:
	if not _pending:
		return
	var dbg: Dictionary = {}
	if is_instance_valid(_api) and _api.has_method("get_last_request_debug"):
		dbg = _api.get_last_request_debug()
		if not dbg.is_empty() and String(dbg.get("tag", "")) != "bug_report":
			return
	_pending = false
	_update_submit_enabled()
	_disconnect_api_signals()
	if is_instance_valid(_logger) and _logger.has_method("error"):
		_logger.error("Bug report submit failed: %s dbg=%s", err_msg, dbg)
	_status("Submit failed: %s" % err_msg, true)
