extends ResponsiveModalPanel
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
var _scroll_container: ScrollContainer

# Scaling references
var _title_lbl: Label
var _close_btn: Button
var _statement_lbl: Label
var _preview_label: Label
var _cancel_btn: Button
var _collapsible_headers: Array[Button] = []
var _text_edits: Array[TextEdit] = []
var _check_boxes: Array[CheckBox] = []
var _flow_container: FlowContainer
var _content_vbox: VBoxContainer
var _btn_row: HBoxContainer

func _ready() -> void:
	super._ready() # Important for ResponsiveModalPanel
	_api = get_node_or_null("/root/APICalls")
	_store = get_node_or_null("/root/GameStore")
	_logger = get_node_or_null("/root/Logger")
	_convoy_selection_service = get_node_or_null("/root/ConvoySelectionService")
	_vendor_service = get_node_or_null("/root/VendorService")

	max_desktop_width = 1400 # Increased from 1100
	max_desktop_height = 1000 # Increased from 950

	_build_ui()
	_update_submit_enabled()
	
	var dsm = get_node_or_null("/root/DeviceStateManager")
	if is_instance_valid(dsm):
		if not dsm.layout_mode_changed.is_connected(_on_layout_mode_changed):
			dsm.layout_mode_changed.connect(_on_layout_mode_changed)
		_apply_scaling(dsm.get_layout_mode())

func _on_layout_mode_changed(mode: int, _screen_size: Vector2, _is_mobile: bool) -> void:
	_apply_scaling(mode)

func _apply_scaling(mode: int) -> void:
	var is_portrait = (mode == 2) # MOBILE_PORTRAIT
	
	# Font sizes
	var title_size = 40 if is_portrait else 32
	var base_size = 30 if is_portrait else 22
	var small_size = 26 if is_portrait else 18
	
	# Dimensions
	var btn_h = 100 if is_portrait else 64
	var input_h = 80 if is_portrait else 60
	var text_edit_min_h = 300 if is_portrait else 200
	var separation = 32 if is_portrait else 24
	var header_btn_h = 80 if is_portrait else 56
	
	if is_instance_valid(_title_lbl):
		_title_lbl.add_theme_font_size_override("font_size", title_size)
	
	if is_instance_valid(_close_btn):
		_close_btn.custom_minimum_size = Vector2(header_btn_h, header_btn_h)
		_close_btn.add_theme_font_size_override("font_size", title_size)
		
	if is_instance_valid(_statement_lbl):
		_statement_lbl.add_theme_font_size_override("font_size", base_size)
		
	if is_instance_valid(_preview_label):
		_preview_label.add_theme_font_size_override("font_size", base_size)
		
	if is_instance_valid(_status_label):
		_status_label.add_theme_font_size_override("font_size", small_size)
		
	if is_instance_valid(_summary):
		_summary.custom_minimum_size.y = input_h
		_summary.add_theme_font_size_override("font_size", base_size)
		
	if is_instance_valid(_cancel_btn):
		_cancel_btn.custom_minimum_size = Vector2(200 if is_portrait else 140, btn_h)
		_cancel_btn.add_theme_font_size_override("font_size", base_size)
		
	if is_instance_valid(_submit_button):
		_submit_button.custom_minimum_size = Vector2(240 if is_portrait else 180, btn_h)
		_submit_button.add_theme_font_size_override("font_size", base_size)
		
	for btn in _collapsible_headers:
		if is_instance_valid(btn):
			btn.custom_minimum_size.y = header_btn_h
			btn.add_theme_font_size_override("font_size", base_size)
			
	for te in _text_edits:
		if is_instance_valid(te):
			te.custom_minimum_size.y = text_edit_min_h
			te.add_theme_font_size_override("font_size", base_size)
			
	for cb in _check_boxes:
		if is_instance_valid(cb):
			cb.add_theme_font_size_override("font_size", base_size)
			# Godot CheckBox icon doesn't scale easily with font, 
			# but we can try to increase separation
			cb.add_theme_constant_override("h_separation", 20 if is_portrait else 12)

	if is_instance_valid(_content_vbox):
		_content_vbox.add_theme_constant_override("separation", separation)
		
	if is_instance_valid(_root):
		_root.add_theme_constant_override("separation", separation)
		
	if is_instance_valid(_flow_container):
		_flow_container.add_theme_constant_override("h_separation", separation)
		_flow_container.add_theme_constant_override("v_separation", separation)

	if is_instance_valid(_btn_row):
		_btn_row.add_theme_constant_override("separation", separation)

func set_screenshot_png_bytes(png_bytes: PackedByteArray) -> void:
	_screenshot_png_bytes = png_bytes if png_bytes != null else PackedByteArray()
	_update_preview()

func open_centered() -> void:
	_status("", false)
	_pending = false
	_update_submit_enabled()
	# Call base class to handle open smartly based on device
	open_modal()

func _on_close_pressed() -> void:
	close_modal()
	closed.emit()

func _build_ui() -> void:
	var margin := ResponsiveMarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mobile_portrait_margins = 16
	margin.desktop_margins = 32
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	add_content(margin)

	# Root content
	var root := VBoxContainer.new()
	root.name = "Root"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 16)
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
	header.add_child(title_lbl)
	_title_lbl = title_lbl

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_on_close_pressed)
	close_btn.custom_minimum_size = Vector2(40, 40)
	header.add_child(close_btn)
	_close_btn = close_btn

	# Scrollable content (form fields + screenshot preview)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.0
	var scroll_style := StyleBoxFlat.new()
	scroll_style.bg_color = Color("#25282a") # Oori Dark Grey
	scroll_style.border_color = Color("#393d47") # Oori Grey
	scroll_style.set_border_width_all(1)
	scroll_style.corner_radius_top_left = 10
	scroll_style.corner_radius_top_right = 10
	scroll_style.corner_radius_bottom_left = 10
	scroll_style.corner_radius_bottom_right = 10
	scroll.add_theme_stylebox_override("panel", scroll_style)
	root.add_child(scroll)

	var content_margin := ResponsiveMarginContainer.new()
	content_margin.name = "ContentMargin"
	content_margin.mobile_portrait_margins = 16
	content_margin.desktop_margins = 24
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(content_margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.add_theme_constant_override("separation", 24)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content_margin.add_child(content)
	_content_vbox = content

	# Statement
	var stmt := Label.new()
	stmt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stmt.text = "Submitting sends the information you select (screenshot, logs, game/account metadata) to the developers to help debug. Do not include passwords or secrets."
	content.add_child(stmt)
	_statement_lbl = stmt

	# Toggles row (Wrapped in FlowContainer for automatic responsiveness)
	var toggles := FlowContainer.new()
	toggles.add_theme_constant_override("h_separation", 16)
	toggles.add_theme_constant_override("v_separation", 16)
	toggles.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(toggles)
	_flow_container = toggles

	_include_screenshot = CheckBox.new()
	_include_screenshot.text = "Include screenshot"
	_include_screenshot.button_pressed = true
	_include_screenshot.toggled.connect(func(_v): _update_submit_enabled())
	toggles.add_child(_include_screenshot)

	_include_logs = CheckBox.new()
	_include_logs.text = "Include logs"
	_include_logs.button_pressed = true
	_include_logs.toggled.connect(func(_v): _update_submit_enabled())
	toggles.add_child(_include_logs)

	_include_metadata = CheckBox.new()
	_include_metadata.text = "Include metadata"
	_include_metadata.button_pressed = true
	_include_metadata.toggled.connect(func(_v): _update_submit_enabled())
	toggles.add_child(_include_metadata)
	
	_check_boxes.append(_include_screenshot)
	_check_boxes.append(_include_logs)
	_check_boxes.append(_include_metadata)

	# Consent
	_consent = CheckBox.new()
	_consent.text = "I understand and consent to sending data"
	_consent.button_pressed = false
	_consent.toggled.connect(func(_v): _update_submit_enabled())
	content.add_child(_consent)
	_check_boxes.append(_consent)

	_summary = LineEdit.new()
	_summary.placeholder_text = "Summary (required)"
	_summary.custom_minimum_size = Vector2(0, 50)
	_summary.text_changed.connect(func(_t): _update_submit_enabled())
	content.add_child(_summary)

	_steps = _add_collapsible_text_block(content, "Steps to reproduce", false)
	_context = _add_collapsible_text_block(content, "Additional context", false)

	var preview_label := Label.new()
	preview_label.text = "Screenshot preview"
	content.add_child(preview_label)
	_preview_label = preview_label

	_screenshot_preview = TextureRect.new()
	_screenshot_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screenshot_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_screenshot_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screenshot_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_screenshot_preview.custom_minimum_size = Vector2(0, 250)
	content.add_child(_screenshot_preview)

	_update_preview()

	# Status
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = ""
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_status_label)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_theme_constant_override("separation", 16)
	root.add_child(btn_row)
	_btn_row = btn_row

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 50)
	cancel_btn.pressed.connect(_on_close_pressed)
	btn_row.add_child(cancel_btn)
	_cancel_btn = cancel_btn

	_submit_button = Button.new()
	_submit_button.text = "Submit"
	_submit_button.custom_minimum_size = Vector2(140, 50)
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
	header_btn.custom_minimum_size = Vector2(0, 45)
	box.add_child(header_btn)
	_collapsible_headers.append(header_btn)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.visible = expanded_by_default
	box.add_child(inner)

	var te := TextEdit.new()
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	te.custom_minimum_size = Vector2(0, 150)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.scroll_fit_content_height = true
	te.text_changed.connect(func(): _update_submit_enabled())
	inner.add_child(te)
	_text_edits.append(te)

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
