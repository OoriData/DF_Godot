# Scripts/UI/tutorial_manager.gd
# High-level tutorial coordinator. Lightweight first pass per tutorial_plan.md
extends Node

# --- Signals ---
signal tutorial_started(level: int, step: int)
signal tutorial_step_changed(level: int, step: int)
signal tutorial_finished

# Public toggles
@export var enabled: bool = true
@export var start_level: int = 1

# Node references
var _main_screen: Node = null
var _overlay: Node = null # Scripts/UI/tutorial_overlay.gd instance
var _gdm: Node = null

# Internal state
var _level: int = 0
var _step: int = 0
var _steps: Array = [] # Array of Dictionaries defining steps for current level
var _started: bool = false

# Simple contract (kept tiny for first pass):
# Step schema: { id: String, copy: String, action: String, target: Dictionary }
# action: "message" | "navigate" | "highlight" (future)

func _ready() -> void:
	if not enabled:
		return
	# Cache references
	_main_screen = get_node_or_null("/root/GameRoot/MainScreen")
	_gdm = get_node_or_null("/root/GameDataManager")
	if _gdm:
		if _gdm.has_signal("initial_data_ready"):
			_gdm.connect("initial_data_ready", Callable(self, "_on_initial_data_ready"))
		if _gdm.has_signal("convoy_data_updated"):
			_gdm.connect("convoy_data_updated", Callable(self, "_on_convoy_data_updated"))
	# Do not create overlay yet; only when the tutorial actually starts
	# Try starting after a short defer so MainScreen can show onboarding modal first
	_try_start_deferred()

func _on_initial_data_ready() -> void:
	_maybe_start()

func _on_convoy_data_updated(_all: Array) -> void:
	_maybe_start()

func _emit_started() -> void:
	emit_signal("tutorial_started", _level, _step)

func _emit_changed() -> void:
	emit_signal("tutorial_step_changed", _level, _step)
	if _step >= 0 and _step < _steps.size():
		var step: Dictionary = _steps[_step]
		print("[Tutorial] Advancing to step ", step.get("id", str(_step)), " (action=", step.get("action", "message"), ")")

func _try_start_deferred():
	call_deferred("_maybe_start")

func _maybe_start() -> void:
	if _started or not enabled:
		return
	# Do not start while the first-convoy modal is visible
	if _is_new_convoy_dialog_visible():
		# print("[Tutorial] Waiting for NewConvoyDialog to close before starting…")
		return
	# Start only when the user has at least one convoy
	var has_any_convoys := false
	if _gdm and _gdm.has_method("get_all_convoy_data"):
		var conv = _gdm.get_all_convoy_data()
		has_any_convoys = (conv is Array) and (conv.size() > 0)
	if not has_any_convoys:
		return
	# Initialize and run
	_level = start_level
	_steps = _build_level_steps(_level)
	_step = 0
	_started = true
	_emit_started()
	_run_current_step()

func _is_new_convoy_dialog_visible() -> bool:
	if _main_screen == null:
		return false
	var dlg := _main_screen.get_node_or_null("OnboardingLayer/NewConvoyDialog")
	return is_instance_valid(dlg) and dlg.visible

func _build_level_steps(level: int) -> Array:
	match level:
		1:
			return [
				{
					id = "l1_intro",
					copy = "Welcome to Desolate Frontiers! This is the very start of your journey.",
					action = "message",
					target = {}
				},
				# placeholders for upcoming steps defined in tutorial_docs.md
				{
					id = "l1_open_convoy_menu",
					copy = "Open the convoy menu using the convoy dropdown in the top bar.",
					action = "highlight",
					target = { hint = "topbar_convoy_button" }
				},
			]
		_:
			return []

func _ensure_overlay() -> Node:
	if _overlay != null and is_instance_valid(_overlay):
		return _overlay
	# Ask main_screen for its onboarding layer if available
	var layer: Node = null
	if _main_screen and _main_screen.has_method("get_onboarding_layer"):
		layer = _main_screen.call("get_onboarding_layer")
	else:
		layer = _main_screen
	if layer == null:
		push_warning("[Tutorial] No host layer for overlay; creating under root")
		layer = get_tree().get_root()
	_overlay = preload("res://Scripts/UI/tutorial_overlay.gd").new()
	layer.add_child(_overlay)
	# Ensure it spans full screen
	if _overlay is Control:
		_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Configure safe-area inset based on TopBar height if available
		var top_h := 0
		if _main_screen:
			var top_bar: Control = _main_screen.get_node_or_null("MainContainer/TopBar")
			if is_instance_valid(top_bar):
				top_h = int(top_bar.size.y)
		if _overlay.has_method("set_safe_area_insets"):
			_overlay.call("set_safe_area_insets", top_h + 10)
	return _overlay

func _configure_overlay_insets_deferred() -> void:
	call_deferred("_configure_overlay_insets")

func _configure_overlay_insets() -> void:
	var ov = _ensure_overlay()
	if ov and ov.has_method("set_safe_area_insets") and _main_screen:
		var top_bar: Control = _main_screen.get_node_or_null("MainContainer/TopBar")
		var top_h := 0
		if is_instance_valid(top_bar):
			top_h = int(top_bar.size.y)
		ov.call("set_safe_area_insets", top_h + 10)

func _run_current_step() -> void:
	if _step < 0 or _step >= _steps.size():
		_emit_finished()
		return
	var step: Dictionary = _steps[_step]
	var action := String(step.get("action", "message"))
	match action:
		"message":
			_show_message(step.get("copy", ""))
		"highlight":
			# For first pass, just show the copy with a subtle hint.
			_show_message(step.get("copy", ""))
			# Future: resolve target and call _overlay.highlight_rect(rect)
		_:
			_show_message(step.get("copy", ""))

func _show_message(text: String) -> void:
	var ov = _ensure_overlay()
	if ov and ov.has_method("show_message"):
		ov.call("show_message", text, true, func(): _advance())
	else:
		# Fallback if overlay not loaded
		print("[Tutorial] ", text, " [Click to continue]")

func _advance() -> void:
	_step += 1
	_emit_changed()
	_run_current_step()

func _emit_finished() -> void:
	emit_signal("tutorial_finished")
	# Hide overlay when done (first pass behavior)
	if _overlay and is_instance_valid(_overlay):
		_overlay.call_deferred("queue_free")
		_overlay = null
