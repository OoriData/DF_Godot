extends Node
## Scene-based test runner for headless execution.
## Uses --scene mode so all class_name types are properly registered.
##
## Usage:
##   godot --headless --path . --log-file /tmp/godot_test.log \
##         --scene res://Tests/TestRunner.tscn --quit-after 600

const TestErrorTranslator = preload("res://Tests/test_error_translator.gd")
const TestTools = preload("res://Tests/test_tools.gd")
const TestSettings = preload("res://Tests/test_settings_manager.gd")
const TestAPICalls = preload("res://Tests/test_api_calls.gd")
const TestUtils = preload("res://Tests/test_util.gd")

func _ready() -> void:
	# Wait one frame so autoloads are fully initialized
	await get_tree().process_frame
	_run_all_tests()

func _run_all_tests() -> void:
	TestUtils.reset()
	var tests: Array = [
		{"name": "ErrorTranslator", "t": TestErrorTranslator.new()},
		{"name": "Tools", "t": TestTools.new()},
		{"name": "SettingsManager", "t": TestSettings.new()},
		{"name": "APICalls", "t": TestAPICalls.new()},
	]
	for entry in tests:
		var nm := String(entry.get("name", ""))
		var t = entry.get("t")
		print("[UnitTests] Running ", nm)
		if t and t.has_method("run"):
			t.run()
		else:
			push_error("[UnitTests] Missing run() for suite: %s" % nm)
			TestUtils.failures += 1

	print("[UnitTests] Done. failures=", TestUtils.failures)
	get_tree().quit(0 if TestUtils.failures == 0 else 1)
