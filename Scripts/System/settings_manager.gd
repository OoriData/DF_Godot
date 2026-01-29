extends Node

signal setting_changed(key: String, value: Variant)

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"

var _save_path: String = SAVE_PATH

var data := {
	"ui.scale": 1.4,
	"ui.menu_open_ratio": 0.5, # Midpoint of the 25%-75% range


	"access.high_contrast": false,

	"display.fullscreen": false,
	"display.resolution": Vector2i(1280, 720),

	"controls.invert_pan": false,
	"controls.invert_zoom": false,
	"controls.gestures_enabled": true,
}

func _ready() -> void:
	load_settings()
	_apply_boot_settings()

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

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_save_path) == OK:
		for k in data.keys():
			if cfg.has_section_key(SECTION, k):
				data[k] = cfg.get_value(SECTION, k, data[k])

func _apply_boot_settings() -> void:
	var sm := get_node_or_null("/root/ui_scale_manager")
	if is_instance_valid(sm) and sm.has_method("set_global_ui_scale"):
		sm.set_global_ui_scale(float(data["ui.scale"]))
	_apply_runtime_side_effect("display.fullscreen", data["display.fullscreen"])
	_apply_runtime_side_effect("display.resolution", data["display.resolution"])

func _apply_runtime_side_effect(key: String, value: Variant) -> void:
	if DisplayServer.get_name() == "headless":
		return
	match key:
		"display.fullscreen":
			var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(value) else DisplayServer.WINDOW_MODE_WINDOWED
			DisplayServer.window_set_mode(mode, 0)
		"display.resolution":
			var size: Vector2i
			if value is Vector2i:
				size = value
			elif value is Vector2:
				size = Vector2i(int(value.x), int(value.y))
			elif value is String and value.find("x") != -1:
				var parts = value.split("x")
				if parts.size() == 2:
					size = Vector2i(int(parts[0]), int(parts[1]))
			if size.x > 0 and size.y > 0:
				DisplayServer.window_set_size(size, 0)
		"ui.scale":
			var sm := get_node_or_null("/root/ui_scale_manager")
			if is_instance_valid(sm) and sm.has_method("set_global_ui_scale"):
				sm.set_global_ui_scale(float(value))
		_:
			pass
