extends CanvasLayer
class_name GlobalFeedbackOverlay

## Always-available Feedback / Report-Bug entry point (S12-5).
##
## During beta the bug reporter must be reachable in exactly the places bugs are found, which is
## where the old top-bar button could not go:
##   1. Login / pre-auth — `MainScreen` (and its top bar) is hidden, disabled, and the tree is paused.
##   2. A paused tree — anything with the default PROCESS_MODE_INHERIT is frozen.
##   3. Mid-tutorial — `tutorial_overlay` shields the screen with MOUSE_FILTER_STOP Controls.
##   4. Modal / error states — same shape as (3).
##
## This node answers all four by living above everything and never pausing:
##   * `layer = _OVERLAY_LAYER` (200) is above `ResponsiveModalPanel` (100) and the link popups (101),
##     and far above the tutorial overlay, which is parented into MainScreen's onboarding layer and so
##     draws on canvas layer 0. Godot delivers GUI input to CanvasLayers in decreasing layer order, so
##     this button is hit-tested *before* the tutorial's full-screen shields.
##   * `PROCESS_MODE_ALWAYS` on both this layer and the report window, so `get_tree().paused` — which
##     `GameScreenManager` holds true for the whole of login — cannot freeze them.
##
## The submit pipeline itself was already global: `APICalls.submit_bug_report()` applies an auth header
## that no-ops when no token exists, and `bug_report_window._collect_metadata()` reads the user
## best-effort. A pre-login report submits fine, just without user metadata. Only this entry point was
## missing.

const _OVERLAY_LAYER := 200
const _EDGE_PAD := 12.0

var _button: Button
var _bug_report_window: Node
var _ui_scale_manager: Node


func _ready() -> void:
	layer = _OVERLAY_LAYER
	# Must outlive get_tree().paused — see the class docs above.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_ui_scale_manager = get_node_or_null("/root/ui_scale_manager")

	_build_button()
	_reposition()

	get_viewport().size_changed.connect(_reposition)
	# `scale_changed(new_scale)` carries an argument; _reposition() takes none.
	if is_instance_valid(_ui_scale_manager) and _ui_scale_manager.has_signal("scale_changed"):
		_ui_scale_manager.scale_changed.connect(func(_new_scale): _reposition())


func _build_button() -> void:
	_button = Button.new()
	_button.name = "GlobalFeedbackButton"
	_button.text = "Feedback"
	_button.tooltip_text = "Report a bug or send feedback"
	_button.focus_mode = Control.FOCUS_NONE
	_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	# Deliberately understated: this sits on top of every screen in the game, so it must read as a
	# utility affordance rather than compete with whatever it is floating over.
	_button.modulate = Color(1, 1, 1, 0.82)
	_button.pressed.connect(_on_pressed)
	add_child(_button)


func _reposition() -> void:
	if not is_instance_valid(_button):
		return
	var safe := Rect2()
	if is_instance_valid(_ui_scale_manager) and _ui_scale_manager.has_method("get_logical_safe_margins"):
		safe = _ui_scale_manager.get_logical_safe_margins()

	# Sized from get_combined_minimum_size() rather than `size` so the rect doesn't depend on whatever
	# this function set last time. (Measured: `size` is already correct here — Godot applies the
	# minimum size on add_child for a Control with no container parent — so the two agree today. This
	# is the more deterministic of the two, not a fix for a live bug.)
	var btn_size := _button.get_combined_minimum_size()

	# Bottom-left: clear of the top bar, the notch, and the map's gear tab (top-right).
	_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_button.offset_left = _EDGE_PAD + safe.position.x
	_button.offset_right = _button.offset_left + btn_size.x
	_button.offset_bottom = -(_EDGE_PAD + safe.size.y)
	_button.offset_top = _button.offset_bottom - btn_size.y


## Opens the shared report window. Public so the existing top-bar button can delegate here instead of
## building a second, independently-owned window (which would be the one frozen by a paused tree).
func open_bug_report() -> void:
	# Capture the screenshot BEFORE the window is shown, or the report pictures the reporter.
	var png_bytes := PackedByteArray()
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if is_instance_valid(vp) and is_instance_valid(vp.get_texture()):
		var img := vp.get_texture().get_image()
		if img:
			png_bytes = img.save_png_to_buffer()

	if not is_instance_valid(_bug_report_window):
		var script: Script = load("res://Scripts/UI/bug_report_window.gd")
		if script == null:
			push_error("GlobalFeedbackOverlay: failed to load bug_report_window.gd")
			return
		_bug_report_window = script.new()
		# Without this the window inherits the paused tree and opens frozen (S12-5 blocker 2).
		_bug_report_window.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child(_bug_report_window)
		if _bug_report_window.has_signal("visibility_changed"):
			_bug_report_window.visibility_changed.connect(_on_window_visibility_changed)

	if _bug_report_window.has_method("set_screenshot_png_bytes"):
		_bug_report_window.set_screenshot_png_bytes(png_bytes)
	if _bug_report_window.has_method("open_centered"):
		_bug_report_window.open_centered()
	else:
		_bug_report_window.show()

	_sync_button_visibility()


func _on_pressed() -> void:
	open_bug_report()


func _on_window_visibility_changed() -> void:
	_sync_button_visibility()


# This layer outranks the report window (200 vs its 100), so without this the button would float on
# top of the very dialog it opened.
func _sync_button_visibility() -> void:
	if not is_instance_valid(_button):
		return
	# Explicitly typed: `_bug_report_window` is a `Node`, so `.visible` reads back as Variant and
	# `:=` here is a hard parse error under Godot 4.6's inference_on_variant=Error default.
	var window_open: bool = is_instance_valid(_bug_report_window) and bool(_bug_report_window.visible)
	_button.visible = not window_open
