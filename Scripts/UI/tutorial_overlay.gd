# Scripts/UI/tutorial_overlay.gd
# Simple fullscreen overlay with a message panel and optional highlight rectangle.
extends Control

# Appearance
const OVERLAY_COLOR := Color(0, 0, 0, 0.35)
const PANEL_BG := Color(0.1, 0.1, 0.1, 0.95)
const PANEL_PAD := 16
const PANEL_SIDE_MARGIN := 12
const PANEL_TOP_MARGIN := 12
const PANEL_MAX_WIDTH := 360.0

var _message_label: RichTextLabel = null
var _continue_button: Button = null
var _on_continue_cb: Callable = Callable()
var _highlight_rect: Rect2 = Rect2()
var _has_highlight: bool = false
var _safe_top_inset: int = 0
var _panel: PanelContainer = null

var _managed_node: Control = null
var _managed_node_popup_connection: Dictionary = {} # To store popup signal connections
var _original_state: Dictionary = {} # Store original z_index, top_level, mouse_filter

# --- Input gating state ---
enum GatingMode { NONE, SOFT, HARD }
var _gating_mode: int = GatingMode.NONE

# Transparent blocker controls to gate input around the highlight "hole"
var _shield_top: Control
var _shield_bottom: Control
var _shield_left: Control
var _shield_right: Control
var _shield_center: Control # used only for HARD lock (blocks the hole)

func _ready() -> void:
	# Let input pass through by default; we use blocker children to stop input around the highlight.
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false # hidden until explicitly shown
	# Ensure we render on top of all other UI. The TopBar (UserInfoDisplay) has a z_index of 10.
	z_index = 100
	_set_full_rect()
	_ensure_ui_built()
	# Initial layout sizing within map area
	_relayout_panel()
	_layout_blockers()

# Ensure the UI nodes exist (safe to call multiple times)
func _ensure_ui_built() -> void:
	if _message_label != null and _continue_button != null and _panel != null:
		return
	# Only add background once: check if there's already a ColorRect child
	var has_bg := false
	for c in get_children():
		if c is ColorRect:
			has_bg = true
			break
	if not has_bg:
		var bg := ColorRect.new()
		bg.color = OVERLAY_COLOR
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
	if _panel == null:
		_panel = PanelContainer.new()
		_panel.custom_minimum_size = Vector2(320, 160)
		_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_panel.offset_top =  _safe_top_inset + PANEL_TOP_MARGIN
		_panel.offset_left = PANEL_SIDE_MARGIN
		_panel.add_theme_stylebox_override("panel", _make_panel_style())
		add_child(_panel)
		var vb := VBoxContainer.new()
		vb.custom_minimum_size = Vector2(320, 0)
		vb.add_theme_constant_override("separation", 10)
		_panel.add_child(vb)
		_message_label = RichTextLabel.new()
		_message_label.bbcode_enabled = true
		_message_label.fit_content = true
		_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(_message_label)
		_continue_button = Button.new()
		_continue_button.text = "Continue"
		_continue_button.pressed.connect(_on_continue_pressed)
		vb.add_child(_continue_button)

	# Ensure shield controls exist for input gating
	if _shield_top == null:
		_shield_top = Control.new()
		_shield_top.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_shield_top)
	if _shield_bottom == null:
		_shield_bottom = Control.new()
		_shield_bottom.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_shield_bottom)
	if _shield_left == null:
		_shield_left = Control.new()
		_shield_left.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_shield_left)
	if _shield_right == null:
		_shield_right = Control.new()
		_shield_right.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_shield_right)
	if _shield_center == null:
		_shield_center = Control.new()
		_shield_center.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_shield_center)

func _debug_log_placement() -> void:
	# Called deferred from manager to inspect parent and sizing after layout
	var p := get_parent()
	var p_path := p.get_path() if p else NodePath("<no-parent>")
	var rect := get_global_rect()
	print("[TutorialOverlay] attached under:", p_path, " size=", size, " global_rect=", rect)

func _set_full_rect() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _make_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_content_margin_all(PANEL_PAD)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	return sb

# Public API
# Show a message with optional continue button and callback
func show_message(text: String, show_continue: bool = true, on_continue: Callable = Callable()) -> void:
	_ensure_ui_built()
	if _message_label != null:
		_message_label.text = text
	if _continue_button != null:
		_continue_button.visible = show_continue
	_on_continue_cb = on_continue
	visible = true
	_relayout_panel()
	_layout_blockers()

func _on_managed_node_popup() -> void:
	if not is_instance_valid(_managed_node):
		return

	if _managed_node.has_method("get_popup"):
		var popup: PopupMenu = _managed_node.get_popup()
		if is_instance_valid(popup):
			# Popups are Windows, which are CanvasItems. They have a z_index.
			# Put it on top of everything.
			popup.z_index = self.z_index + 2
			print("[TutorialOverlay] Promoted popup z_index to ", popup.z_index)

# New function to bring a node to the front and handle its popups
func highlight_node(node: Node, rect: Rect2) -> void:
	# First, clear any previously managed node to restore its state
	_reset_managed_node()

	# Set the rect for drawing the visual highlight and positioning blockers
	_highlight_rect = rect
	_has_highlight = rect.has_area()
	queue_redraw()
	_layout_blockers()

	if node is Control:
		_managed_node = node as Control

		# Capture global position BEFORE making it top-level, as setting top_level
		# removes it from the layout, which can cause its position to reset.
		var original_global_position = _managed_node.global_position

		# Store original state
		_original_state = {
			"z_index": _managed_node.z_index,
			"top_level": _managed_node.top_level,
			"mouse_filter": _managed_node.mouse_filter,
		}

		# Promote the node
		_managed_node.z_index = self.z_index + 1
		_managed_node.top_level = true
		# After making it top-level, explicitly restore its global position.
		_managed_node.global_position = original_global_position

		# Ensure it's clickable. STOP is safest as it's now the top interactive element.
		_managed_node.mouse_filter = Control.MOUSE_FILTER_STOP

		print("[TutorialOverlay] Managing node: ", _managed_node.name, " new z_index: ", _managed_node.z_index)

		# --- Special handling for nodes with popups ---
		if _managed_node.has_method("get_popup"):
			var popup: PopupMenu = _managed_node.get_popup()
			if is_instance_valid(popup) and popup.has_signal("about_to_popup"):
				var callable = Callable(self, "_on_managed_node_popup")
				if not popup.is_connected("about_to_popup", callable):
					popup.connect("about_to_popup", callable)
					# Store the connection so we can disconnect it later
					_managed_node_popup_connection = {"popup": popup, "callable": callable}
					print("[TutorialOverlay] Connected to popup signal for ", _managed_node.name)
	else:
		print("[TutorialOverlay] Warning: Highlight target is not a Control node. Cannot use top_level. Node: ", node)


func _reset_managed_node() -> void:
	# Disconnect any popup signals we connected
	if _managed_node_popup_connection.has("popup"):
		var popup: PopupMenu = _managed_node_popup_connection.get("popup")
		var callable: Callable = _managed_node_popup_connection.get("callable")
		if is_instance_valid(popup) and popup.is_connected("about_to_popup", callable):
			popup.disconnect("about_to_popup", callable)
			print("[TutorialOverlay] Disconnected popup signal.")
	_managed_node_popup_connection.clear()

	# Restore the node's original state
	if is_instance_valid(_managed_node) and not _original_state.is_empty():
		print("[TutorialOverlay] Resetting managed node: ", _managed_node.name)
		_managed_node.z_index = _original_state.get("z_index", 0)
		_managed_node.top_level = _original_state.get("top_level", false)
		_managed_node.mouse_filter = _original_state.get("mouse_filter", Control.MOUSE_FILTER_PASS)

	_managed_node = null
	_original_state.clear()

# Convenience helper: set highlight around a specific Control/node (uses its global rect)
func set_highlight_for_node(node: Node, padding: int = 6) -> void:
	if not is_instance_valid(node):
		highlight_node(null, Rect2())
		return

	var r: Rect2
	if node is Control:
		r = (node as Control).get_global_rect()
	elif node.has_method("get_global_position"):
		var p: Vector2 = node.get_global_position()
		r = Rect2(p - Vector2(padding, padding), Vector2(padding * 2.0, padding * 2.0))
	elif "global_position" in node:
		var p: Vector2 = node.global_position
		r = Rect2(p - Vector2(padding, padding), Vector2(padding * 2.0, padding * 2.0))
	else:
		highlight_node(node, Rect2()) # Pass node but no rect
		return

	r = r.grow(padding)
	highlight_node(node, r)

func clear_highlight() -> void:
	_has_highlight = false
	_reset_managed_node()
	queue_redraw()
	_layout_blockers()

# Configure input gating behavior:
# - GatingMode.NONE: no input blocking by the overlay (except panel itself)
# - GatingMode.SOFT: block input everywhere except a "hole" over the highlight
# - GatingMode.HARD: block input everywhere, including the highlighted area
func set_gating_mode(mode: int) -> void:
	_gating_mode = mode
	var label := "NONE" if mode == GatingMode.NONE else ("SOFT" if mode == GatingMode.SOFT else "HARD")
	print("[TutorialOverlay] gating_mode=", label)
	_layout_blockers()

func clear_highlight_and_gating() -> void:
	clear_highlight()
	set_gating_mode(GatingMode.NONE)

# Allow host to push safe-area insets (e.g., keep panel below top bar)
func set_safe_area_insets(top_inset: int) -> void:
	_safe_top_inset = max(0, top_inset)
	# Adjust any top-anchored children (message panel)
	for c in get_children():
		if c is PanelContainer:
			c.offset_top = _safe_top_inset + PANEL_TOP_MARGIN
	queue_redraw()
	_relayout_panel()
	_layout_blockers()

func _on_continue_pressed() -> void:
	if _on_continue_cb.is_valid():
		_on_continue_cb.call()

func _draw() -> void:
	# Debug border to verify overlay visibility and bounds
	if visible:
		var border_col := Color(1, 0, 0, 0.25)
		draw_rect(Rect2(Vector2.ZERO, size), border_col, false, 2.0)
	if not _has_highlight:
		return
	# Convert global rect to local space if parent is not root
	var top_left := get_global_transform().affine_inverse() * _highlight_rect.position
	var r := Rect2(top_left, _highlight_rect.size)
	# Draw outline rectangle highlight
	var color := Color(1, 0.8, 0.2, 0.9)
	draw_rect(r.grow(4), color, false, 3)
	draw_rect(r, Color(1, 1, 1, 0.9), false, 2)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout_panel()
		_layout_blockers()

func _relayout_panel() -> void:
	if _panel == null:
		return
	# Constrain width to fit within the current map view area.
	var avail_w: float = max(0.0, size.x - (PANEL_SIDE_MARGIN * 2.0))
	var target_w: float = min(PANEL_MAX_WIDTH, avail_w)
	_panel.custom_minimum_size.x = target_w
	# Keep it pinned to top-left, below safe area inset.
	_panel.offset_left = PANEL_SIDE_MARGIN
	_panel.offset_top = _safe_top_inset + PANEL_TOP_MARGIN

# Utility: allow host to bring this overlay to the top within its parent
func bring_to_front() -> void:
	var p := get_parent()
	if p:
		p.move_child(self, p.get_child_count() - 1)

# Internal: position blocker controls to enforce the current gating mode
func _layout_blockers() -> void:
	# If shields don't exist yet, ensure they're created
	if _shield_top == null or _shield_bottom == null or _shield_left == null or _shield_right == null or _shield_center == null:
		return

	# Only enable when overlay visible and gating active
	# IMPORTANT: In SOFT mode, do NOT enable blockers until we have a valid highlight rect.
	# Otherwise we'd block the entire screen with no "hole".
	var enable := visible and (
		(_gating_mode == GatingMode.HARD) or
		(_gating_mode == GatingMode.SOFT and _has_highlight)
	)
	for s in [_shield_top, _shield_bottom, _shield_left, _shield_right, _shield_center]:
		if s:
			s.visible = enable
	if not enable:
		return

	# Compute highlight rect in local coordinates
	var r_local := Rect2(Vector2.ZERO, Vector2.ZERO)
	if _has_highlight:
		var top_left := get_global_transform().affine_inverse() * _highlight_rect.position
		r_local = Rect2(top_left, _highlight_rect.size)

	# Clamp to overlay bounds
	var full := Rect2(Vector2.ZERO, size)
	var r := r_local.intersection(full)

	# Lay out perimeter shields creating a "hole" over r
	_shield_top.position = Vector2(0, 0)
	_shield_top.size = Vector2(size.x, max(0.0, r.position.y))

	_shield_bottom.position = Vector2(0, r.position.y + r.size.y)
	_shield_bottom.size = Vector2(size.x, max(0.0, size.y - (r.position.y + r.size.y)))

	_shield_left.position = Vector2(0, r.position.y)
	_shield_left.size = Vector2(max(0.0, r.position.x), max(0.0, r.size.y))

	_shield_right.position = Vector2(r.position.x + r.size.x, r.position.y)
	_shield_right.size = Vector2(max(0.0, size.x - (r.position.x + r.size.x)), max(0.0, r.size.y))

	# Center shield blocks the hole only in HARD mode
	var center_on := (_gating_mode == GatingMode.HARD)
	_shield_center.visible = center_on
	_shield_center.position = r.position
	_shield_center.size = r.size

	# Ensure all shields capture input when visible
	for s2 in [_shield_top, _shield_bottom, _shield_left, _shield_right, _shield_center]:
		if s2:
			s2.mouse_filter = Control.MOUSE_FILTER_STOP
