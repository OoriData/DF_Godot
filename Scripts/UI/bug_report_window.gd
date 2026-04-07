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
	_apply_ui_scaling_recursive(self)

func _is_portrait() -> bool:
	if is_inside_tree():
		var win_size = get_viewport().get_visible_rect().size
		return win_size.y > win_size.x
	return false

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or DisplayServer.get_name() in ["Android", "iOS"] or _is_portrait()

func _get_font_size(base: int) -> int:
	var boost = 7.0 if _is_portrait() else (2.4 if _is_mobile() else 1.2)
	return int(base * boost)

func set_screenshot_png_bytes(png_bytes: PackedByteArray) -> void:
	_screenshot_png_bytes = png_bytes if png_bytes != null else PackedByteArray()
	_update_preview()

func open_centered() -> void:
	_status("", false)
	_pending = false
	_update_submit_enabled()
	# Use the larger of two sources — get_visible_rect() can return stale/small
	# values on first call on mobile before the viewport is fully initialized.
	var ds_size = DisplayServer.window_get_size()
	var vp_size = get_viewport().get_visible_rect().size
	var avail_w = int(max(ds_size.x, vp_size.x))
	var avail_h = int(max(ds_size.y, vp_size.y))

	if _is_portrait():
		popup(Rect2i(Vector2i(0, 0), Vector2i(avail_w, avail_h)))
		call_deferred("_force_size_portrait")
		call_deferred("_refresh_layout")
		return

	var win_w: int
	var win_h: int
	if _is_mobile():
		win_w = min(1200, avail_w - 24)
		win_h = min(1000, avail_h - 48)
	else:
		win_w = min(1100, avail_w - 24)
		win_h = min(950, avail_h - 48)

	popup_centered(Vector2i(win_w, win_h))
	call_deferred("_refresh_layout")

func _force_size_portrait() -> void:
	# Godot's PopupPanel layout pass can shrink the popup back to min_size.
	# Re-apply the full available size one frame later to override that.
	if not visible:
		return
	var ds_size = DisplayServer.window_get_size()
	var vp_size = get_viewport().get_visible_rect().size
	var avail_w = int(max(ds_size.x, vp_size.x))
	var avail_h = int(max(ds_size.y, vp_size.y))
	position = Vector2i(0, 0)
	size = Vector2i(avail_w, avail_h)

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

func _apply_ui_scaling_recursive(node: Node) -> void:
	if node is Control and not node is ScrollContainer:
		# Don't override ScrollContainer — it needs MOUSE_FILTER_STOP to receive scroll/touch events.
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	var is_port = _is_portrait()
	if node is Button:
		node.add_theme_font_size_override("font_size", _get_font_size(14))
		var btn_name: String = node.name.to_lower() if is_instance_valid(node) else ""
		var is_action = btn_name.contains("close") or btn_name.contains("cancel") or btn_name.contains("submit") or btn_name == "" or btn_name.contains(" reproduction")
		var target_h: int
		if is_port:
			target_h = 240 if is_action else 180
		else:
			target_h = (160 if is_action else 130) if _is_mobile() else 56
		if node.custom_minimum_size.y < target_h:
			node.custom_minimum_size.y = target_h
	elif node is Label:
		var current_fs = node.get_theme_font_size("font_size")
		if current_fs <= 1: current_fs = 14
		node.add_theme_font_size_override("font_size", _get_font_size(current_fs))
	elif node is TextEdit or node is LineEdit:
		node.add_theme_font_size_override("font_size", _get_font_size(14))
		if node is TextEdit and is_port:
			node.custom_minimum_size.y = max(node.custom_minimum_size.y, 180)
	
	for child in node.get_children():
		_apply_ui_scaling_recursive(child)

func _build_ui() -> void:
	var is_port = _is_portrait()
	# Style the popup panel itself
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#1E1E1E")
	panel_style.border_color = Color("#2E2E2E")
	panel_style.set_border_width_all(0 if is_port else 1)
	panel_style.corner_radius_top_left = 0 if is_port else 12
	panel_style.corner_radius_top_right = 0 if is_port else 12
	panel_style.corner_radius_bottom_left = 0 if is_port else 12
	panel_style.corner_radius_bottom_right = 0 if is_port else 12
	add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad = 0 if is_port else 20
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(margin)

	# Root content
	var root := VBoxContainer.new()
	root.name = "Root"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 22 if is_port else 12)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
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
	title_lbl.add_theme_font_size_override("font_size", _get_font_size(14))
	header.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_on_close_pressed)
	header.add_child(close_btn)

	# Separator removed to save space.

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
	# MOUSE_FILTER_STOP (default) lets the ScrollContainer intercept touch/scroll events.
	root.add_child(scroll)

	# Note: content_panel was removed to reduce nesting and provide more room.

	var content_margin := MarginContainer.new()
	content_margin.name = "ContentMargin"
	var inner_pad = 12 if is_port else 16
	content_margin.add_theme_constant_override("margin_left", inner_pad)
	content_margin.add_theme_constant_override("margin_right", inner_pad)
	content_margin.add_theme_constant_override("margin_top", inner_pad)
	content_margin.add_theme_constant_override("margin_bottom", inner_pad)
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Do NOT set SIZE_EXPAND_FILL vertically — the child of a ScrollContainer
	# must be allowed to overflow so the scroll actually works.
	content_margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(content_margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Same here: let it grow beyond the scroll container height.
	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.add_theme_constant_override("separation", 34 if is_port else 12)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content_margin.add_child(content)

	# Statement
	var stmt := Label.new()
	stmt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stmt.text = "Submitting sends the information you select (screenshot, logs, game/account metadata) to the developers to help debug. Do not include passwords or secrets."
	content.add_child(stmt)

	# Toggles row
	var toggles: BoxContainer
	if is_port:
		toggles = VBoxContainer.new()
	else:
		toggles = HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 17 if is_port else 12)
	toggles.mouse_filter = Control.MOUSE_FILTER_PASS
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
	_consent.text = "I understand and consent to sending data"
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
	line_style.content_margin_top = 16 if is_port else 12
	line_style.content_margin_bottom = 16 if is_port else 12
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
	_screenshot_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Reasonable preview height; content scrolls so it won't clip anything.
	_screenshot_preview.custom_minimum_size = Vector2(0, 400 if is_port else 400)
	content.add_child(_screenshot_preview)

	_update_preview()

	# Separator removed to save space.

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
	btn_row.add_theme_constant_override("separation", 12 if is_port else 8)
	root.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size.y = 240 if is_port else 50
	cancel_btn.pressed.connect(_on_close_pressed)
	btn_row.add_child(cancel_btn)

	_submit_button = Button.new()
	_submit_button.text = "Submit"
	_submit_button.custom_minimum_size.x = 300 if is_port else 140
	_submit_button.custom_minimum_size.y = 300 if is_port else 60
	_submit_button.pressed.connect(_on_submit_pressed)
	btn_row.add_child(_submit_button)

func _add_collapsible_text_block(parent: Control, title_text: String, expanded_by_default: bool) -> TextEdit:
	var is_port = _is_portrait()
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
	header_normal.content_margin_top = 16 if is_port else 10
	header_normal.content_margin_bottom = 16 if is_port else 10
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
	te.custom_minimum_size = Vector2(0, 480 if is_port else 180)
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
		_status("Bug report submission unavailable.", true)
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
		"title": summary_text,
		"summary": summary_text,
		"description": "\n\n".join(desc_parts),
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

	if _include_metadata.button_pressed:
		var meta := _collect_metadata()
		payload["meta"] = meta

	if not warnings.is_empty():
		payload["client_warnings"] = warnings

	return payload

func _build_screenshot_payload(warnings: Array[String]) -> Dictionary:
	var bytes := _screenshot_png_bytes
	if bytes.is_empty():
		return {}
	if bytes.size() <= MAX_SCREENSHOT_BYTES:
		return {"mime": "image/png", "base64": Marshalls.raw_to_base64(bytes)}

	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		warnings.append("Screenshot too large; omitted.")
		return {}

	var w: int = int(img.get_width())
	var h: int = int(img.get_height())
	var max_dim: int = (w if w > h else h)
	if max_dim > MAX_SCREENSHOT_DIM:
		var scale := float(MAX_SCREENSHOT_DIM) / float(max_dim)
		var nw: int = int(round(float(w) * scale))
		var nh: int = int(round(float(h) * scale))
		img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)

	var resized_bytes := img.save_png_to_buffer()
	if resized_bytes.size() > MAX_SCREENSHOT_BYTES:
		return {}
	return {"mime": "image/png", "base64": Marshalls.raw_to_base64(resized_bytes)}

func _get_recent_logs() -> Array:
	if is_instance_valid(_logger) and _logger.has_method("get_recent_lines"):
		var raw = _logger.get_recent_lines(MAX_LOG_LINES)
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

func _collect_metadata() -> Dictionary:
	var user: Dictionary = {}
	if is_instance_valid(_store) and _store.has_method("get_user"):
		user = _store.get_user()
	return {
		"client_time_unix": Time.get_unix_time_from_system(),
		"os": {"name": OS.get_name(), "version": OS.get_version()},
		"user": {"id": str(user.get("id", ""))}
	}

func _on_bug_report_submitted(result: Variant) -> void:
	if not _pending:
		return
	_pending = false
	_update_submit_enabled()
	_disconnect_api_signals()
	_status("Bug report submitted. Thanks!", false)

func _on_bug_report_error(err_msg: String) -> void:
	if not _pending:
		return
	_pending = false
	_update_submit_enabled()
	_disconnect_api_signals()
	_status("Submit failed: %s" % err_msg, true)
