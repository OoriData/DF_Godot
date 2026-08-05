extends Node

signal setting_changed(key: String, value: Variant)

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"

var _save_path: String = SAVE_PATH

var data := {
	"ui.scale": 1.0,
	# LERP POSITION in the orientation's band (UITheme.MENU_RATIO_*), NOT a screen fraction.
	# 0.81 → landscape/desktop lerp(0.425, 0.75) = 0.688 of viewport WIDTH (≈1321 logical px at
	# ui.scale 1.0); portrait lerp(0.55, 0.72) = 0.688 of viewport HEIGHT. Calibrated on screen
	# 2026-08-05 against desktop landscape. See docs/02_UI_UX/ui_system.md § ui.menu_open_ratio.
	"ui.menu_open_ratio": 0.81,
	"ui.cargo_sort_metric": 0, # Default cargo sort mode

	"access.high_contrast": false,

	"display.fullscreen": false,

	"controls.invert_pan": false,
	"controls.invert_zoom": false,
	
	"map.active_delivery_destinations": false,
	"map.settlement_delivery_destinations": false,
	"map.settlement_labels": false,
	"map.warehouse_labels": false,
	"map.all_convoy_destinations": false,
	"map.grid_lines": false,
}

func _ready() -> void:
	# S12-6: the fullscreen shortcut must work on the login screen too, and GameScreenManager holds
	# `get_tree().paused = true` for the whole of login — which would otherwise gate _unhandled_key_input
	# on this autoload. Safe to set: this node has no _process/_physics_process.
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	_apply_boot_settings()


## S12-6 — global fullscreen shortcut.
##
## Handled here rather than in `main_screen.gd` because that node is `PROCESS_MODE_DISABLED` during
## login, and this autoload already owns `display.fullscreen` and its runtime side effect.
##
## Deliberately raw key matching rather than an InputMap action: `project.godot` ships no `[input]`
## section, and hand-authored InputEventKey resource literals there are fragile and invisible to
## platform conditionals. Everything routes through `set_and_save()` so persistence **and** the
## deferred `reapply_scale()` in `_apply_runtime_side_effect()` come for free — calling
## `DisplayServer` directly here would leave the UI laid out at the previous mode's scale.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if not _is_fullscreen_shortcut(key_event):
		return
	toggle_fullscreen()
	get_viewport().set_input_as_handled()


func _is_fullscreen_shortcut(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_F11:
			return true
		KEY_ENTER, KEY_KP_ENTER:
			return event.alt_pressed # Windows/Linux convention
		KEY_F:
			return event.meta_pressed and event.ctrl_pressed # macOS convention (Cmd+Ctrl+F)
	return false


func toggle_fullscreen() -> void:
	set_and_save("display.fullscreen", not bool(get_value("display.fullscreen", false)))

func get_value(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)

func set_and_save(key: String, value: Variant) -> void:
	data[key] = value
	save_settings()
	setting_changed.emit(key, value)
	_apply_runtime_side_effect(key, value)


func set_save_path_for_tests(path: String) -> void:
	# Used by headless/unit tests to avoid clobbering real user settings.
	if path.strip_edges() != "":
		_save_path = path

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in data.keys():
		cfg.set_value(SECTION, k, data[k])
	cfg.save(_save_path)

## Keys PINNED to their `data` defaults for this release — never restored from disk.
##
## Their controls are hidden (the `UISec` section in `SettingsMenu.tscn`), but **hiding a control
## does not neutralise a value already saved in `user://settings.cfg`.** An existing install with
## `ui.scale = 3.65` (a real reported case — S13-23) would keep the broken scale *and* lose the only
## control that could correct it, which is strictly worse than shipping the sliders. Skipping the
## disk restore here is what actually pins them; the hidden UI is just cosmetic.
##
## Stored values are left on disk untouched, so removing a key here restores that user's preference
## exactly as it was. Un-pin once TODO S13-26 gives the layout a real content floor.
const PINNED_KEYS: PackedStringArray = ["ui.scale", "ui.menu_open_ratio"]

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_save_path) == OK:
		for k in data.keys():
			if k in PINNED_KEYS:
				continue
			if cfg.has_section_key(SECTION, k):
				data[k] = cfg.get_value(SECTION, k, data[k])

func _apply_boot_settings() -> void:
	var sm := get_node_or_null("/root/ui_scale_manager")
	if is_instance_valid(sm) and sm.has_method("set_global_ui_scale"):
		sm.set_global_ui_scale(float(data["ui.scale"]))
	_apply_runtime_side_effect("display.fullscreen", data["display.fullscreen"])

func _apply_runtime_side_effect(key: String, value: Variant) -> void:
	if DisplayServer.get_name() == "headless":
		return
	match key:
		"display.fullscreen":
			var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(value) else DisplayServer.WINDOW_MODE_WINDOWED
			DisplayServer.window_set_mode(mode, 0)
			# The logical scale is derived from the window size, which just changed. Recompute
			# it (deferred, so the new window geometry has settled) — otherwise the UI keeps the
			# previous mode's scale and lays out offset after toggling fullscreen.
			var usm := get_node_or_null("/root/ui_scale_manager")
			if is_instance_valid(usm) and usm.has_method("reapply_scale"):
				usm.call_deferred("reapply_scale")
		"ui.scale":
			var sm := get_node_or_null("/root/ui_scale_manager")
			if is_instance_valid(sm) and sm.has_method("set_global_ui_scale"):
				sm.set_global_ui_scale(float(value))
		_:
			pass
