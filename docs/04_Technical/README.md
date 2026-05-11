# Technical Reference

This section covers the underlying infrastructure, identity management, and quality assurance patterns of the project.

## Core Infrastructure
- [**Autoload Order**](AutoloadOrder.md): Dependency management and initialization sequence.
- [**Diagnostics & Troubleshooting**](Diagnostics.md): Logging, watchdogs, and network debugging.
- [**Dependency Graph**](Dependencies.md): Visual mapping of singleton relationships.
- [**API Reference**](API_Reference.md): Backend endpoints and JSON contracts.
- [**Deployment & Environment**](Deployment.md): Build targets and CI/CD pipelines.
- [**Identity & Auth**](Identity.md): Account linking, merging, and session management.
- [**Apple Auth**](AppleAuth.md): Specific notes on iOS/macOS authentication providers.

---

## Testing & QA

### Headless Smoke Test
- **Script**: [wiring_smoke_test.gd](../../../Scripts/Debug/wiring_smoke_test.gd)
- **Execution**:
  ```bash
  Godot.app/Contents/MacOS/Godot --headless --path . -s res://Scripts/Debug/wiring_smoke_test.gd
  ```

### GUT Unit Testing
- **Addon**: [addons/gut](../../../addons/gut)
- **Headless Runner**: [run_all_tests.gd](../../../Tests/run_all_tests.gd)
- **Unit Suites**:
  - [test_api_calls.gd](../../../Tests/test_api_calls.gd)
  - [test_error_translator.gd](../../../Tests/test_error_translator.gd)
  - [test_settings_manager.gd](../../../Tests/test_settings_manager.gd)
  - [test_tools.gd](../../../Tests/test_tools.gd)
  - [test_util.gd](../../../Tests/test_util.gd)

### CI/CD
The project is configured to run these tests automatically in the pipeline to prevent regressions in core transport and utility logic.
