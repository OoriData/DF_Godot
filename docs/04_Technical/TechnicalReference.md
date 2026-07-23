---
type: technical
tags:
  - technical
  - codex/readme
aliases:
  - "Technical Reference"
created: 2026-05-18
---

# Technical Reference

This section covers the underlying infrastructure, identity management, and quality assurance patterns of the project.

## Core Infrastructure
- **[SignalHub Event Bus](SignalHub.md)**: Canonical domain event catalogue, emitters, and listeners.
- **[Network Layer](NetworkLayer.md)**: APICalls queuing, watchdogs, and auth bypass.
- **[Push Notifications](PushNotifications.md)**: Cross-platform messaging and deep-linking.
- **[Multi-Provider Auth](MultiProviderAuth.md)**: Google Auth, Steam Ticket login, and merging.
- **[User Settings](UserSettings.md)**: SettingsManager, config persistence, and text scaling.
- **[Autoload Order](AutoloadOrder.md)**: Dependency management and initialization sequence.
- **[Diagnostics & Troubleshooting](Diagnostics.md)**: Logging, watchdogs, and network debugging.
- **[Refresh Scheduler](RefreshScheduler.md)**: Polling heartbeat — interval, suspend/resume, and how to add a new service.
- **[Error Handling System](ErrorSystem.md)**: ErrorTranslator pipeline, inline vs. modal errors, and how to add new translations.
- **[Dependency Graph](Dependencies.md)**: Visual mapping of singleton relationships.
- **[API Reference](API_Reference.md)**: Backend endpoints and JSON contracts.
- **[DF_Lib: Shared Binary Protocol Library](DF_Lib.md)**: The separate repo/package that defines the `/map` binary wire format — versioning, publish/deploy workflow, and why a backend field rename can silently break the client without touching either repo's "obviously relevant" code.
- **[Deployment & Environment](Deployment.md)**: Build targets and CI/CD pipelines.
- **[Identity & Auth](Identity.md)**: Account linking, merging, and session management.
- **[Apple Auth](AppleAuth.md)**: Specific notes on iOS/macOS authentication providers.
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

---

## 🚧 In-Progress Implementation Plans

Active feature work lives here. Once a feature is shipped and stable, the implementation plan doc should be **archived** (move to `05_Archive/`) or **converted** into a stable reference doc in the appropriate section.

> [!IMPORTANT]
> Do not reference these docs as ground truth for how the system works — they describe *intended* behaviour, not necessarily the current state. Check the actual source file first.

- [**Cargo Destination Button**](CargoDestinationButtonImplementation.md): Adding a clickable destination button in the convoy cargo inspector that pans the map camera to the delivery settlement.

