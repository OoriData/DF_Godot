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

func test_map_overlay_settings_round_trip() -> void:
	# Map overlay toggles must persist across sessions. This only works if each
	# "map.*" key is present in the SettingsManager defaults (load_settings only
	# restores keys it already knows about).
	var path := "user://settings_map_test.cfg"

	var sm := SettingsManagerScript.new()
	if sm.has_method("set_save_path_for_tests"):
		sm.set_save_path_for_tests(path)
	var map_keys := [
		"map.active_delivery_destinations",
		"map.settlement_delivery_destinations",
		"map.settlement_labels",
		"map.warehouse_labels",
		"map.all_convoy_destinations",
		"map.grid_lines",
	]
	for key in map_keys:
		sm.set_and_save(key, true)

	var sm2 := SettingsManagerScript.new()
	if sm2.has_method("set_save_path_for_tests"):
		sm2.set_save_path_for_tests(path)
	sm2.load_settings()
	for key in map_keys:
		assert_true(bool(sm2.get_value(key, false)), "%s should persist across sessions" % key)
