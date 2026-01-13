# Testing

Headless smoke test:
- Script: [Scripts/Debug/wiring_smoke_test.gd](../Scripts/Debug/wiring_smoke_test.gd)
- Example (macOS):

```
Godot.app/Contents/MacOS/Godot --headless --path . -s res://Scripts/Debug/wiring_smoke_test.gd
```

GUT addon:
- Location: [addons/gut](../addons/gut)
- Headless runner: [Tests/run_all_tests.gd](../Tests/run_all_tests.gd)
- Example:

```
Godot.app/Contents/MacOS/Godot --headless --path . -s res://Tests/run_all_tests.gd
```

Unit suites:
- APICalls: [Tests/test_api_calls.gd](../Tests/test_api_calls.gd)
- ErrorTranslator: [Tests/test_error_translator.gd](../Tests/test_error_translator.gd)
- Settings: [Tests/test_settings_manager.gd](../Tests/test_settings_manager.gd)
- Tools: [Tests/test_tools.gd](../Tests/test_tools.gd)
- Util: [Tests/test_util.gd](../Tests/test_util.gd)
