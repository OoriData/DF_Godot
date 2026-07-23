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

	# Map overlay toggles must persist across sessions. This only works if each
	# "map.*" key is present in the SettingsManager defaults (load_settings only
	# restores keys it already knows about).
	var sm3 := SettingsManagerScript.new()
	if sm3.has_method("set_save_path_for_tests"):
		sm3.set_save_path_for_tests("user://settings_map_test.cfg")
	var map_keys := [
		"map.active_delivery_destinations",
		"map.settlement_delivery_destinations",
		"map.settlement_labels",
		"map.warehouse_labels",
		"map.all_convoy_destinations",
		"map.grid_lines",
	]
	for key in map_keys:
		sm3.set_and_save(key, true)
	var sm4 := SettingsManagerScript.new()
	if sm4.has_method("set_save_path_for_tests"):
		sm4.set_save_path_for_tests("user://settings_map_test.cfg")
	sm4.load_settings()
	for key in map_keys:
		TestUtil.assert_eq(bool(sm4.get_value(key, false)), true, "round-trip " + key)
