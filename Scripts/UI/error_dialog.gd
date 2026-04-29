# /Users/aidan/Work/DF_Godot/Scripts/UI/ErrorDialog.gd
extends AcceptDialog

var _report_btn: Button
var _raw_error_text: String = ""

func _ready() -> void:
	# Ensure the dialog remains active even if the tree is paused or parent is disabled.
	process_mode = PROCESS_MODE_ALWAYS
	
	# When the dialog is confirmed (OK button) or closed (X button), it should free itself.
	confirmed.connect(queue_free)
	canceled.connect(queue_free)
	custom_action.connect(_on_custom_action)
	
	_report_btn = add_button("Report Bug", false, "report_bug")

	# Ensure the label inside the dialog can wrap long text.
	var label = get_label()
	if is_instance_valid(label):
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		
	var _dsm = get_node_or_null("/root/DeviceStateManager")
	if is_instance_valid(_dsm):
		_dsm.layout_mode_changed.connect(_on_layout_mode_changed)
		
	_apply_layout()

func _on_layout_mode_changed(_mode: int, _screen_size: Vector2, _is_mobile: bool) -> void:
	_apply_layout()

func _apply_layout() -> void:
	var _dsm = get_node_or_null("/root/DeviceStateManager")
	if not is_instance_valid(_dsm):
		return
		
	var mode = _dsm.get_layout_mode()
	var vp_size = get_viewport().get_visible_rect().size
	var avail_w = int(vp_size.x)
	var avail_h = int(vp_size.y)
	
	var target_w = 500
	var target_h = 300
	
	if mode == 2: # MOBILE_PORTRAIT
		target_w = int(avail_w * 0.9)
		target_h = int(avail_h * 0.6)
	elif mode == 1: # MOBILE_LANDSCAPE
		target_w = int(avail_w * 0.7)
		target_h = int(avail_h * 0.6)
		
	min_size = Vector2i(target_w, target_h)
	
	# Apply font scaling
	var dyn_font_sz = _dsm.get_scaled_base_font_size(16)
	var curr_theme = theme
	if curr_theme == null:
		curr_theme = Theme.new()
		theme = curr_theme
	curr_theme.default_font_size = dyn_font_sz

func show_message(message: String, raw_message: String = "") -> void:
	dialog_text = message
	_raw_error_text = raw_message
	
	# Keep layout fresh just before popup
	_apply_layout()
	
	# Popup in the center of the screen.
	# Using call_deferred ensures it happens after the node is ready and sizes are calculated.
	call_deferred("popup_centered")

func _on_custom_action(action: StringName) -> void:
	if action == &"report_bug":
		_submit_quick_bug_report()

func _submit_quick_bug_report() -> void:
	if not is_instance_valid(_report_btn):
		return
		
	_report_btn.disabled = true
	_report_btn.text = "Reporting..."
	
	var api = get_node_or_null("/root/APICalls")
	if not is_instance_valid(api):
		_report_btn.text = "Failed"
		return
		
	# Build payload
	var title: String = dialog_text.get_slice("\n", 0)
	if title.length() > 50:
		title = title.substr(0, 50) + "..."
		
	var payload: Dictionary = {
		"title": "[Auto] " + title,
		"summary": "Automated report from Error Dialog",
		"description": "User clicked Report Bug from an error dialog.\n\n## Error Message (Friendly)\n" + dialog_text + "\n\n## Technical Detail (Raw)\n" + _raw_error_text,
		"consent": true
	}
	
	# Collect logs (last 200 lines max chars 25000)
	var logger = get_node_or_null("/root/Logger")
	if is_instance_valid(logger) and logger.has_method("get_recent_lines"):
		var raw = logger.get_recent_lines(200)
		var out_logs: Array[String] = []
		var total_chars := 0
		for line_any in raw:
			var line := str(line_any)
			if line.length() > 500:
				line = line.substr(0, 500) + "…"
			if total_chars + line.length() > 25000:
				break
			total_chars += line.length()
			out_logs.append(line)
		payload["logs"] = {"recent_lines": out_logs}
		
	# Metadata
	var store = get_node_or_null("/root/GameStore")
	var user: Dictionary = {}
	if is_instance_valid(store) and store.has_method("get_user"):
		user = store.get_user()
		
	payload["meta"] = {
		"client_time_unix": Time.get_unix_time_from_system(),
		"os": {"name": OS.get_name(), "version": OS.get_version()},
		"user": {"id": str(user.get("id", ""))}
	}
	
	if api.has_signal("bug_report_submitted") and not api.bug_report_submitted.is_connected(_on_bug_report_submitted):
		api.bug_report_submitted.connect(_on_bug_report_submitted)
	if api.has_signal("fetch_error") and not api.fetch_error.is_connected(_on_bug_report_error):
		api.fetch_error.connect(_on_bug_report_error)
		
	api.submit_bug_report(payload)

func _disconnect_api_signals() -> void:
	var api = get_node_or_null("/root/APICalls")
	if is_instance_valid(api):
		if api.has_signal("bug_report_submitted") and api.bug_report_submitted.is_connected(_on_bug_report_submitted):
			api.bug_report_submitted.disconnect(_on_bug_report_submitted)
		if api.has_signal("fetch_error") and api.fetch_error.is_connected(_on_bug_report_error):
			api.fetch_error.disconnect(_on_bug_report_error)

func _on_bug_report_submitted(_result: Variant) -> void:
	_disconnect_api_signals()
	if is_instance_valid(_report_btn):
		_report_btn.text = "Sent!"

func _on_bug_report_error(_msg: String) -> void:
	_disconnect_api_signals()
	if is_instance_valid(_report_btn):
		_report_btn.text = "Failed to Send"
		_report_btn.disabled = false
