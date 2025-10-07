extends Control

# A lightweight overlay coach for onboarding steps.
# Usage: add as a child to an overlay layer and call show_buy_vehicle_step(callback_open_settlement)

signal dismissed

var _panel: Panel = null
var _message_label: Label = null
var _action_button: Button = null
var _secondary_button: Button = null
var _side_panel: Panel = null
var _side_label: RichTextLabel = null
var _side_bounds_global: Rect2 = Rect2()
var _side_total_steps: int = 0
var _side_current_step: int = 0
var _avoid_rects_global: Array = [] # Array of Rect2 in global coords to avoid overlapping
var _highlight_panel: Panel = null
var _highlight_panels: Array = [] # Optional extra panels for multi-rect highlighting
var _highlight_target: WeakRef = null
var _highlight_margin: int = 6
var _highlight_active: bool = false
var _highlight_host: Control = null # Optional external layer to host highlight panel (not clipped)
var _highlight_mode: String = "none" # "control" or "rect"
var _multi_rect_mode: bool = false
var _last_step_index: int = 0
var _last_total_steps: int = 0
var _last_message: String = ""
var _name_box: VBoxContainer = null
var _name_edit: LineEdit = null
var _name_error: Label = null
var _name_min_len: int = 3
var _submit_cb: Callable
var _naming_submit_in_progress: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _ensure_panel() -> void:
	if is_instance_valid(_panel):
		return
	print("[Coach] _ensure_panel: creating coach panel")
	_panel = Panel.new()
	_panel.name = "CoachPanel"
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel.custom_minimum_size = Vector2(560, 160)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	# Style
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.98)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.border_color = Color(0.35, 0.55, 0.90)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	_panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.anchor_left = 0.5
	v.anchor_top = 0.5
	v.anchor_right = 0.5
	v.anchor_bottom = 0.5
	v.offset_left = -260
	v.offset_top = -70
	v.offset_right = 260
	v.offset_bottom = 70
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)

	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_label.text = ""

	# Optional naming UI (hidden by default)
	_name_box = VBoxContainer.new()
	_name_box.visible = false
	_name_box.add_theme_constant_override("separation", 6)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Convoy name"
	_name_edit.max_length = 40
	_name_error = Label.new()
	_name_error.modulate = Color(1, 0.6, 0.6)
	_name_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_error.visible = false
	_name_box.add_child(_name_edit)
	_name_box.add_child(_name_error)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.add_theme_constant_override("separation", 10)

	_action_button = Button.new()
	_action_button.text = "Let's go"
	_action_button.custom_minimum_size = Vector2(140, 34)

	_secondary_button = Button.new()
	_secondary_button.text = "Not now"
	_secondary_button.custom_minimum_size = Vector2(120, 30)

	buttons.add_child(_action_button)
	buttons.add_child(_secondary_button)

	v.add_child(_message_label)
	v.add_child(_name_box)
	v.add_child(buttons)
	_panel.add_child(v)
	# Center the panel within this overlay
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -300
	_panel.offset_top = -100
	_panel.offset_right = 300
	_panel.offset_bottom = 100
	add_child(_panel)

func _wire_buttons(primary_cb: Callable, wire_secondary: bool = true) -> void:
	if is_instance_valid(_action_button):
		for c in _action_button.get_signal_connection_list("pressed"):
			_action_button.disconnect("pressed", c.callable)
		if primary_cb.is_null():
			_action_button.disabled = true
		else:
			_action_button.disabled = false
			_action_button.pressed.connect(func():
				hide()
				if primary_cb and not primary_cb.is_null():
					primary_cb.call()
			)
	if is_instance_valid(_secondary_button):
		# Reset any previous connections
		for c in _secondary_button.get_signal_connection_list("pressed"):
			_secondary_button.disconnect("pressed", c.callable)
		if wire_secondary:
			_secondary_button.show()
			_secondary_button.pressed.connect(func():
				hide()
				dismissed.emit()
			)
		else:
			_secondary_button.hide()

func hide_main_panel() -> void:
	# Hide the central coach panel; side panel can still be used for step-by-step hints
	if is_instance_valid(_panel):
		print("[Coach] hide_main_panel: hiding center panel (side panel unaffected)")
		_panel.hide()

func show_buy_vehicle_step(primary_cb: Callable) -> void:
	_ensure_panel()
	show()
	if is_instance_valid(_panel):
		_panel.show()
	if is_instance_valid(_message_label):
		_message_label.text = "Nice! Your convoy is created. Next, let's buy your first vehicle. We'll open the settlement vendors and go to the dealership."
	# Ensure naming UI is hidden for this mode
	if is_instance_valid(_name_box):
		_name_box.visible = false
	_action_button.text = "Open vendors"
	_secondary_button.text = "Maybe later"
	_wire_buttons(primary_cb, true)

# Show a central welcome panel with custom text and a primary callback
func show_welcome(message: String, primary_cb: Callable, primary_text: String = "Let's go", secondary_text: String = "Not now") -> void:
	_ensure_panel()
	show()
	if is_instance_valid(_panel):
		_panel.show()
	if is_instance_valid(_message_label):
		_message_label.text = message
	# Ensure naming UI is hidden for welcome
	if is_instance_valid(_name_box):
		_name_box.visible = false
	if is_instance_valid(_action_button):
		_action_button.text = primary_text
	var use_secondary := true
	if is_instance_valid(_secondary_button):
		_secondary_button.text = secondary_text
		# If no secondary text provided, hide the secondary button entirely
		if String(secondary_text).strip_edges() == "":
			use_secondary = false
	_wire_buttons(primary_cb, use_secondary)

# Show the convoy naming UI within the central panel. Calls on_submit(name) when valid.
func show_convoy_naming(prompt_text: String, on_submit: Callable, button_text: String = "Create", min_length: int = 3) -> void:
	_ensure_panel()
	show()
	if is_instance_valid(_panel):
		_panel.show()
	if is_instance_valid(_message_label):
		_message_label.text = prompt_text
	_name_min_len = int(min_length)
	_submit_cb = on_submit
	_naming_submit_in_progress = false
	if is_instance_valid(_name_box):
		_name_box.visible = true
	if is_instance_valid(_name_edit):
		_name_edit.text = ""
		_name_edit.editable = true
		_name_edit.grab_focus()
		# Disconnect any prior connections to avoid duplicate handlers
		for c in _name_edit.get_signal_connection_list("text_changed"):
			_name_edit.disconnect("text_changed", c.callable)
		for c in _name_edit.get_signal_connection_list("text_submitted"):
			_name_edit.disconnect("text_submitted", c.callable)
		_name_edit.text_changed.connect(func(_t: String): _validate_name_and_update())
		_name_edit.text_submitted.connect(func(_t: String): _attempt_submit_name())
	if is_instance_valid(_name_error):
		_name_error.visible = false
		_name_error.text = ""
	if is_instance_valid(_action_button):
		_action_button.text = button_text
	# One-button mode
	_wire_buttons(func():
		_attempt_submit_name()
	, false)
	_validate_name_and_update()

func _validate_name_and_update() -> void:
	if not is_instance_valid(_name_edit) or not is_instance_valid(_action_button):
		return
	var nm := String(_name_edit.text).strip_edges()
	var ok := nm.length() >= _name_min_len
	_action_button.disabled = not ok
	if is_instance_valid(_name_error):
		if ok:
			_name_error.visible = false
			_name_error.text = ""
		else:
			_name_error.visible = true
			_name_error.text = "Name must be at least %d characters" % _name_min_len

func _attempt_submit_name() -> void:
	if not is_instance_valid(_name_edit):
		return
	if _naming_submit_in_progress:
		return
	var nm := String(_name_edit.text).strip_edges()
	if nm.length() < _name_min_len:
		_validate_name_and_update()
		return
	# Disable UI briefly
	if is_instance_valid(_action_button):
		_action_button.disabled = true
	_name_edit.editable = false
	_naming_submit_in_progress = true
	# Call submit callback
	if _submit_cb and not _submit_cb.is_null():
		_submit_cb.call(nm)

func _ensure_hint() -> void:
	pass # deprecated

func show_hint_near_control(_target: Control, _message: String, _offset: Vector2 = Vector2(0, -80)) -> void:
	pass # deprecated

func hide_hint() -> void:
	pass # deprecated

func _ensure_side_panel() -> void:
	if is_instance_valid(_side_panel):
		# Keep this noisy to debug lifecycle
		print("[Coach] _ensure_side_panel: already exists; visible=", _side_panel.visible)
		return
	print("[Coach] _ensure_side_panel: creating side panel")
	_side_panel = Panel.new()
	_side_panel.name = "CoachSidePanel"
	_side_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.98)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.border_color = Color(0.40, 0.60, 0.90)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	_side_panel.add_theme_stylebox_override("panel", sb)
	# Allow width to shrink fully with the map area; keep a modest min height
	_side_panel.custom_minimum_size = Vector2(0, 100)
	# Anchor left side, some margin from top/left
	_side_panel.anchor_left = 0.0
	_side_panel.anchor_top = 0.0
	_side_panel.anchor_right = 0.0
	_side_panel.anchor_bottom = 0.0
	# Position will be set by _reposition_side_panel() using bounds
	_side_panel.offset_left = 24
	_side_panel.offset_top = 120

	var vb := VBoxContainer.new()
	vb.anchor_left = 0
	vb.anchor_top = 0
	vb.anchor_right = 1
	vb.anchor_bottom = 1
	vb.offset_left = 16
	vb.offset_top = 12
	vb.offset_right = -16
	vb.offset_bottom = -12
	vb.add_theme_constant_override("separation", 8)

	_side_label = RichTextLabel.new()
	# Disable fit_content so the label doesn't force the panel to grow; we'll manage size and enable scrolling
	_side_label.fit_content = false
	_side_label.bbcode_enabled = true
	_side_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_side_label.scroll_active = false
	vb.add_child(_side_label)

	_side_panel.add_child(vb)
	add_child(_side_panel)
	_side_panel.hide()

func show_left_panel_message(message: String) -> void:
	_ensure_side_panel()
	show()
	_side_panel.show()
	if is_instance_valid(_side_label):
		print("[Coach] show_left_panel_message: len=", message.length(), " visible=", _side_panel.visible)
		# Ensure label is fully visible and ready to draw
		_side_label.visible = true
		_side_label.modulate = Color(1, 1, 1, 1)
		_side_label.bbcode_enabled = true
		# Prefer bbcode_text to ensure correct parsing and content height when bbcode_enabled=true
		if _side_label.bbcode_enabled:
			_side_label.bbcode_text = message
		else:
			_side_label.text = message
		# Make sure all characters are visible (in case a typewriter effect was applied elsewhere)
		if _side_label.has_method("set_visible_characters"):
			_side_label.set_visible_characters(-1)
		elif _side_label.has_variable("visible_characters"):
			_side_label.visible_characters = -1
		# Force reflow and repaint; then finalize on a deferred tick
		if _side_label.has_method("reset_size"):
			_side_label.reset_size()
		_side_label.queue_redraw()
		call_deferred("_reposition_side_panel")

func show_step_message(step_index: int, total_steps: int, message: String) -> void:
	_ensure_side_panel()
	# Ensure the central (modal) coach panel stays hidden during step-by-step walkthrough
	hide_main_panel()
	_side_current_step = step_index
	_side_total_steps = total_steps
	_last_step_index = step_index
	_last_total_steps = total_steps
	_last_message = message
	var header := "[b]Step %d/%d[/b]\n" % [max(1, step_index), max(1, total_steps)]
	print("[Coach] show_step_message: step=", step_index, "/", total_steps, " msgLen=", message.length())
	show_left_panel_message(header + message)
	_reposition_side_panel()
	# Also schedule a deferred reposition to catch any late layout changes (e.g., after menu close)
	call_deferred("_reposition_side_panel")
	# Defensive: on step 1 only, re-apply the text shortly after to avoid any frame-race where bbcode hasn't flushed
	if step_index == 1:
		var tm := Timer.new()
		tm.one_shot = true
		tm.wait_time = 0.05
		add_child(tm)
		tm.timeout.connect(func():
			if is_instance_valid(_side_label):
				var hdr := "[b]Step %d/%d[/b]\n" % [max(1, _last_step_index), max(1, _last_total_steps)]
				show_left_panel_message(hdr + _last_message)
				_reposition_side_panel()
			tm.queue_free()
		)
		tm.start()

func hide_left_panel() -> void:
	if is_instance_valid(_side_panel):
		print("[Coach] hide_left_panel: hiding side panel")
		_side_panel.hide()

# Allow main screen to define the area (in global coords) where the side panel should live (map area),
# to avoid overlapping the right menu panel when it's open.
func set_side_panel_bounds_by_global_rect(bounds: Rect2) -> void:
	_side_bounds_global = bounds
	print("[Coach] set_side_panel_bounds_by_global_rect: pos=", bounds.position, " size=", bounds.size)
	_reposition_side_panel()

func set_side_panel_avoid_rects_global(rects: Array) -> void:
	# rects expected to be Array[Rect2]
	_avoid_rects_global = rects
	print("[Coach] set_side_panel_avoid_rects_global: count=", rects.size())
	_reposition_side_panel()

func _reposition_side_panel() -> void:
	if not is_instance_valid(_side_panel):
		return
	# If no bounds provided, keep default offsets
	if _side_bounds_global.size == Vector2.ZERO:
		print("[Coach] _reposition_side_panel: skipped (no bounds)")
		return
	# Convert global bounds into this overlay's local coordinates
	var inv := get_global_transform().affine_inverse()
	var top_left_local := inv * _side_bounds_global.position
	var size_local := _side_bounds_global.size
	var margin := Vector2(24, 24)
	# Compute the full available space within map bounds (minus margins)
	var available_w: float = max(0.0, size_local.x - (margin.x * 2.0))
	var available_h: float = max(0.0, size_local.y - (margin.y * 2.0))
	# Make a small box: prefer a compact width and never exceed available space
	var preferred_w: float = 360.0
	# Let it shrink as needed: cap only by available space
	var panel_w: float = min(preferred_w, available_w)
	var padding_x: float = 24.0 # VBox left+right offsets (approx)
	var padding_y: float = 20.0 # VBox top+bottom offsets (approx)
	var min_panel_h: float = 100.0
	var max_panel_h: float = available_h
	# Update width immediately so the RichTextLabel can reflow for content height calculation
	_side_panel.size.x = panel_w
	# Estimate content height based on label's content at this width
	var content_h: float = 0.0
	if is_instance_valid(_side_label):
		var label_w: float = max(0.0, panel_w - padding_x)
		_side_label.size.x = label_w
		# Prefer precise API when available
		if _side_label.has_method("get_content_height"):
			content_h = float(_side_label.call("get_content_height"))
		else:
			content_h = _side_label.get_minimum_size().y
	var desired_h: float = content_h + padding_y
	var panel_h: float = clamp(desired_h, min_panel_h, max_panel_h)
	# If content doesn't fit vertically, enable scrolling to avoid overflow
	if is_instance_valid(_side_label):
		_side_label.scroll_active = desired_h > max_panel_h
		_side_label.size = Vector2(max(0.0, panel_w - padding_x), max(0.0, panel_h - padding_y))
	_side_panel.size = Vector2(panel_w, panel_h)
	print("[Coach] _reposition_side_panel: panel_w=", panel_w, " panel_h=", panel_h, " avail=", Vector2(available_w, available_h))

	# Convert avoid rects to local space
	var avoid_local: Array = []
	for r in _avoid_rects_global:
		if r is Rect2:
			var tl: Vector2 = inv * r.position
			avoid_local.append(Rect2(tl, r.size))

	# Candidate Y positions: top, middle, bottom within bounds; prefer left side
	var left_x := top_left_local.x + margin.x
	var top_y := top_left_local.y + margin.y
	var mid_y: float = top_left_local.y + max(margin.y, (size_local.y - panel_h) * 0.5)
	var bot_y: float = top_left_local.y + max(margin.y, size_local.y - panel_h - margin.y)
	# Always keep the panel on the left side of the map to avoid the right menu visually
	var candidates := [Vector2(left_x, top_y), Vector2(left_x, mid_y), Vector2(left_x, bot_y)]

	var chosen: Vector2 = candidates[0]
	for c in candidates:
		var test_rect := Rect2(c, _side_panel.size)
		var hits := false
		for ar in avoid_local:
			if test_rect.intersects(ar):
				hits = true
				break
		if not hits:
			chosen = c
			break
	_side_panel.position = chosen
	print("[Coach] _reposition_side_panel: final pos=", chosen)

# --- Generic highlight overlay ---
func _ensure_highlight_panel() -> void:
	if is_instance_valid(_highlight_panel):
		return
	_highlight_panel = Panel.new()
	_highlight_panel.name = "CoachHighlight"
	_highlight_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight_panel.focus_mode = Control.FOCUS_NONE
	_highlight_panel.z_index = 10000
	# Default to top-level when used with explicit global-rect highlighting.
	_highlight_panel.top_level = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.85, 0.2, 0.10) # subtle translucent fill so it's visible on light/dark
	sb.border_color = Color(1.0, 0.85, 0.2, 1.0)
	sb.border_width_left = 4
	sb.border_width_top = 4
	sb.border_width_right = 4
	sb.border_width_bottom = 4
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	# Add a soft shadow to make the highlight pop above busy UI
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 2)
	_highlight_panel.add_theme_stylebox_override("panel", sb)
	var host: Node = _highlight_host if is_instance_valid(_highlight_host) else self
	host.add_child(_highlight_panel)
	_highlight_panel.hide()
	# Ensure it's tracked for multi-rect usage as panel 0
	if _highlight_panels.is_empty():
		_highlight_panels.append(_highlight_panel)

func _create_extra_highlight_panel() -> Panel:
	var p := Panel.new()
	p.name = "CoachHighlightExtra"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.focus_mode = Control.FOCUS_NONE
	p.z_index = 10000
	p.top_level = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.85, 0.2, 0.10)
	sb.border_color = Color(1.0, 0.85, 0.2, 1.0)
	sb.border_width_left = 4
	sb.border_width_top = 4
	sb.border_width_right = 4
	sb.border_width_bottom = 4
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 2)
	p.add_theme_stylebox_override("panel", sb)
	var host: Node = _highlight_host if is_instance_valid(_highlight_host) else self
	host.add_child(p)
	p.hide()
	return p

func set_highlight_host(host: Control) -> void:
	_highlight_host = host
	# If the panel already exists under old parent, reparent to new host
	if is_instance_valid(_highlight_panel) and _highlight_panel.get_parent() != _highlight_host:
		print("[Coach] set_highlight_host: reparenting highlight panel to new host")
		_highlight_panel.get_parent().remove_child(_highlight_panel)
		_highlight_host.add_child(_highlight_panel)

func highlight_control(target: Control) -> void:
	if not is_instance_valid(target):
		print("[Coach] highlight_control: target invalid; clearing")
		clear_highlight()
		return
	_ensure_highlight_panel()
	# Use a global-rect following highlight to guarantee full click-through on the target.
	_highlight_target = weakref(target)
	_highlight_mode = "rect"  # treat as a rect highlight that follows the control each frame
	_highlight_active = true
	_multi_rect_mode = false
	show()
	# Ensure the highlight panel lives under the overlay host as a top-level control (viewport coords)
	var host: Node = _highlight_host if is_instance_valid(_highlight_host) else self
	if _highlight_panel.get_parent() != host:
		var prev_parent := _highlight_panel.get_parent()
		if prev_parent:
			prev_parent.remove_child(_highlight_panel)
		host.add_child(_highlight_panel)
	_highlight_panel.top_level = true
	# Position/size now based on the target's current global rect
	var grect: Rect2 = target.get_global_rect()
	_highlight_panel.position = grect.position - Vector2(_highlight_margin, _highlight_margin)
	_highlight_panel.size = grect.size + Vector2(_highlight_margin * 2, _highlight_margin * 2)
	_highlight_panel.z_index = max(_highlight_panel.z_index, 10000)
	_highlight_panel.show()
	print("[Coach] highlight_control: following ", target.name, " margin=", _highlight_margin)
	set_process(true)

func clear_highlight() -> void:
	_highlight_active = false
	_highlight_mode = "none"
	_highlight_target = null
	_multi_rect_mode = false
	# Hide all panels if present
	if not _highlight_panels.is_empty():
		for p in _highlight_panels:
			if is_instance_valid(p):
				p.hide()
	# Also keep base panel restored to host for single-rect usage next time
	if is_instance_valid(_highlight_panel):
		var host: Node = _highlight_host if is_instance_valid(_highlight_host) else self
		if _highlight_panel.get_parent() != host:
			var prev_parent := _highlight_panel.get_parent()
			if prev_parent:
				prev_parent.remove_child(_highlight_panel)
			host.add_child(_highlight_panel)
		_highlight_panel.top_level = true
	print("[Coach] clear_highlight: done")
	set_process(false)

func _process(_delta: float) -> void:
	if not _highlight_active:
		return
	_update_highlight_rect()

func _update_highlight_rect() -> void:
	if _highlight_target == null:
		clear_highlight()
		return
	var t: Object = _highlight_target.get_ref()
	if t == null or not (t is Control) or not (t as Control).is_inside_tree():
		clear_highlight()
		return
	# Only used for legacy/global rect following. Control-based highlight uses anchors and needs no updates.
	if _highlight_mode == "control":
		return
	var ctrl := t as Control
	var grect: Rect2 = ctrl.get_global_rect()
	var top_left: Vector2 = grect.position
	var rect_size: Vector2 = grect.size
	if is_instance_valid(_highlight_panel):
		_highlight_panel.position = top_left - Vector2(_highlight_margin, _highlight_margin)
		_highlight_panel.size = rect_size + Vector2(_highlight_margin * 2, _highlight_margin * 2)

# Highlight by explicit global rectangle (for tab buttons, etc.)
func highlight_global_rect(global_rect: Rect2) -> void:
	_ensure_highlight_panel()
	_highlight_target = null
	_highlight_mode = "rect"
	_highlight_active = true
	_multi_rect_mode = false
	show()
	_highlight_panel.show()
	# Convert rect from GLOBAL space to the highlight host's local space (parent of highlight panel)
	# With top-level, directly use global rect coordinates for positioning
	# Ensure the highlight panel is under the overlay host and top-level for viewport coords
	var host: Node = _highlight_host if is_instance_valid(_highlight_host) else self
	if _highlight_panel.get_parent() != host:
		var prev_parent := _highlight_panel.get_parent()
		if prev_parent:
			prev_parent.remove_child(_highlight_panel)
		host.add_child(_highlight_panel)
	_highlight_panel.top_level = true
	var top_left: Vector2 = global_rect.position
	_highlight_panel.position = top_left - Vector2(_highlight_margin, _highlight_margin)
	_highlight_panel.size = global_rect.size + Vector2(_highlight_margin * 2, _highlight_margin * 2)
	print("[Coach] highlight_global_rect: rect=", global_rect, " margin=", _highlight_margin)

# Highlight multiple explicit global rectangles at once (e.g., several list rows)
func highlight_global_rects(global_rects: Array) -> void:
	if global_rects == null or global_rects.size() == 0:
		clear_highlight()
		return
	_ensure_highlight_panel()
	# Ensure we have enough panels
	var needed := int(global_rects.size())
	while _highlight_panels.size() < needed:
		var extra := _create_extra_highlight_panel()
		_highlight_panels.append(extra)
	# Show required count and hide any extras
	_highlight_active = true
	_highlight_mode = "rect"
	_multi_rect_mode = true
	show()
	var host: Node = _highlight_host if is_instance_valid(_highlight_host) else self
	for i in _highlight_panels.size():
		var p: Panel = _highlight_panels[i]
		if not is_instance_valid(p):
			continue
		if i < needed:
			# Ensure under host and top-level
			if p.get_parent() != host:
				var prev_parent := p.get_parent()
				if prev_parent:
					prev_parent.remove_child(p)
				host.add_child(p)
			p.top_level = true
			var r: Rect2 = global_rects[i]
			p.position = r.position - Vector2(_highlight_margin, _highlight_margin)
			p.size = r.size + Vector2(_highlight_margin * 2, _highlight_margin * 2)
			p.z_index = max(p.z_index, 10000)
			p.show()
		else:
			p.hide()
	# When using explicit rects, per-frame following is not required
	set_process(false)
