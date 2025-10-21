# Scripts/UI/tutorial_overlay.gd
# Simple fullscreen overlay with a message panel and optional highlight rectangle.
extends Control

# Appearance
const OVERLAY_COLOR := Color(0, 0, 0, 0.35)
const PANEL_BG := Color(0.1, 0.1, 0.1, 0.95)
const PANEL_PAD := 16

var _message_label: RichTextLabel
var _continue_button: Button
var _on_continue_cb: Callable = Callable()
var _highlight_rect: Rect2 = Rect2()
var _has_highlight: bool = false
var _safe_top_inset: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP # block clicks behind
	visible = false # hidden until explicitly shown
	_set_full_rect()
	# Semi-transparent dark backdrop
	var bg := ColorRect.new()
	bg.color = OVERLAY_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Message panel centered
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 160)
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top =  _safe_top_inset
	panel.offset_left = 0
	panel.offset_right = 0
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(420, 0)
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	_message_label = RichTextLabel.new()
	_message_label.bbcode_enabled = true
	_message_label.fit_content = true
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_message_label)
	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.pressed.connect(_on_continue_pressed)
	vb.add_child(_continue_button)

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
	_message_label.text = text
	_continue_button.visible = show_continue
	_on_continue_cb = on_continue
	visible = true

# Set a highlight rectangle in global coordinates; overlay will draw a ring
func set_highlight_rect(rect: Rect2) -> void:
	_highlight_rect = rect
	_has_highlight = rect.size.length() > 0.0
	queue_redraw()

func clear_highlight() -> void:
	_has_highlight = false
	queue_redraw()

# Allow host to push safe-area insets (e.g., keep panel below top bar)
func set_safe_area_insets(top_inset: int) -> void:
	_safe_top_inset = max(0, top_inset)
	# Adjust any top-anchored children (message panel)
	for c in get_children():
		if c is PanelContainer:
			c.offset_top = _safe_top_inset
	queue_redraw()

func _on_continue_pressed() -> void:
	if _on_continue_cb.is_valid():
		_on_continue_cb.call()

func _draw() -> void:
	if not _has_highlight:
		return
	# Convert global rect to local space if parent is not root
	var top_left := get_global_transform().affine_inverse() * _highlight_rect.position
	var r := Rect2(top_left, _highlight_rect.size)
	# Draw outline rectangle highlight
	var color := Color(1, 0.8, 0.2, 0.9)
	draw_rect(r.grow(4), color, false, 3)
	draw_rect(r, Color(1, 1, 1, 0.9), false, 2)
