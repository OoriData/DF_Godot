extends RefCounted

const TestUtil = preload("res://Tests/test_util.gd")
const SettingsManagerScript = preload("res://Scripts/System/settings_manager.gd")

func run() -> void:
	var sm := SettingsManagerScript.new()
	# Use a test-specific save path to avoid clobbering real settings.
	if sm.has_method("set_save_path_for_tests"):
		sm.set_save_path_for_tests("user://settings_test.cfg")
	# mutate + save
	sm.set_and_save("ui.scale", 1.7)
	# new instance loads
	var sm2 := SettingsManagerScript.new()
	if sm2.has_method("set_save_path_for_tests"):
		sm2.set_save_path_for_tests("user://settings_test.cfg")
	sm2.load_settings()
	TestUtil.assert_eq(float(sm2.get_value("ui.scale", 0.0)), 1.7, "round-trip ui.scale")
