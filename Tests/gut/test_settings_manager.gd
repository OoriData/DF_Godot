extends "res://addons/gut/test.gd"

const SettingsManagerScript = preload("res://Scripts/System/settings_manager.gd")

func test_settings_round_trip_ui_scale() -> void:
	var path := "user://settings_test.cfg"

	var sm := SettingsManagerScript.new()
	if sm.has_method("set_save_path_for_tests"):
		sm.set_save_path_for_tests(path)
	sm.set_and_save("ui.scale", 1.7)

	var sm2 := SettingsManagerScript.new()
	if sm2.has_method("set_save_path_for_tests"):
		sm2.set_save_path_for_tests(path)
	sm2.load_settings()
	assert_eq(float(sm2.get_value("ui.scale", 0.0)), 1.7)
