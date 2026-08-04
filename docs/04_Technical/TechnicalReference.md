---
type: technical
tags:
  - layer/autoload
  - kind/index
  - status/current
aliases:
  - "Technical Reference"
created: 2026-05-18
updated: 2026-07-31
verified_against_code: 2026-07-30
status: current
---

# Technical Reference

This section covers the underlying infrastructure, identity management, and quality assurance patterns of the project.

> [!NOTE]
> **This is the section index for `04_Technical/`.** Every doc in the folder must appear below.
> CI enforces it — `tools/docs_check.py`.

## Core Infrastructure
- **[SignalHub Event Bus](SignalHub.md)**: Canonical domain event catalogue, emitters, and listeners.
- **[AI Agent Guidelines](AI_Guidelines.md)**: Standards for AI-assisted development in this repo.
- **[Network Layer](NetworkLayer.md)**: APICalls queuing, watchdogs, and auth bypass.
- **[Push Notifications](PushNotifications.md)**: Cross-platform messaging and deep-linking.
- **[Multi-Provider Auth](MultiProviderAuth.md)**: Google Auth, Steam Ticket login, and merging.
- **[User Settings](UserSettings.md)**: SettingsManager, config persistence, and text scaling.
- **[Autoload Order](AutoloadOrder.md)**: Dependency management and initialization sequence.
- **[Diagnostics & Troubleshooting](Diagnostics.md)**: Logging, watchdogs, and network debugging.
- **[Debugging a Visual/Layout Bug](DebuggingVisualBugs.md)**: The four-step protocol for layout bugs — pinpoint, reproduce in-editor, measure after animations settle, rule out structure. Plus the scaling-specific traps.
- **[Refresh Scheduler](RefreshScheduler.md)**: Polling heartbeat — interval, suspend/resume, and how to add a new service.
- **[Error Handling System](ErrorSystem.md)**: ErrorTranslator pipeline, inline vs. modal errors, and how to add new translations.
- **[Bug Reporting & Feedback](BugReporting.md)**: Feedback button → screenshot + log capture → `POST /bug-report`; payload contract and the current availability gaps (login screen, tutorial overlay).
- **[Dependency Graph](Dependencies.md)**: Visual mapping of singleton relationships.
- **[API Reference](API_Reference.md)**: Backend endpoints and JSON contracts.
- **[DF_Lib: Shared Binary Protocol Library](DF_Lib.md)**: The separate repo/package that defines the `/map` binary wire format — versioning, publish/deploy workflow, and why a backend field rename can silently break the client without touching either repo's "obviously relevant" code.
- **[Data Boundaries](DataBoundaries.md)**: Field-level map of the JSON-vs-binary seam — exactly which fields cross which boundary, the known key-name divergences, and how to diagnose a stat that reads blank or `0` everywhere.
- **[Deployment & Environment](Deployment.md)**: Build targets and CI/CD pipelines.
- **[Identity & Auth](Identity.md)**: Account linking, merging, and session management.
- **[Apple Auth](AppleAuth.md)**: Specific notes on iOS/macOS authentication providers.
---

## Testing & QA

### Verifying GDScript Changes
- **Doc**: [GDScript Verification](GDScriptVerification.md) — the two-check recipe behind any
  "compile-clean" claim, and why one check is not enough.
- **Execution**:
  ```bash
  GODOT=/Users/aidan/Applications/Godot.app/Contents/MacOS/Godot
  "$GODOT" --headless --editor --quit-after 250 > /tmp/ed.log 2>&1   # structural, ~15 s warm
  grep -inE "parse error|compile error|could not resolve|failed to load script" /tmp/ed.log
  ```
- The editor pass only sees scripts something loads (autoload graph + reopened scenes) — a new,
  unreferenced file is invisible to it. Name your edited files explicitly in the load probe instead.
- `treat_warnings_as_errors` **is not a Godot 4.6 setting**; warning severity is per-warning
  (`0`/`1`/`2`). Promoting one for a run, plus the canary and cleanup discipline, is in the doc.

### Headless Smoke Test
- **Script**: [wiring_smoke_test.gd](../../Scripts/Debug/wiring_smoke_test.gd)
- **Execution**:
  ```bash
  Godot.app/Contents/MacOS/Godot --headless --path . -s res://Scripts/Debug/wiring_smoke_test.gd
  ```

### GUT Unit Testing
- **Addon**: [addons/gut](../../addons/gut)
- **Headless Runner**: [run_all_tests.gd](../../Tests/run_all_tests.gd)
- **Unit Suites**:
  - [test_api_calls.gd](../../Tests/test_api_calls.gd)
  - [test_error_translator.gd](../../Tests/test_error_translator.gd)
  - [test_settings_manager.gd](../../Tests/test_settings_manager.gd)
  - [test_tools.gd](../../Tests/test_tools.gd)
  - [test_util.gd](../../Tests/test_util.gd)

### Documentation Graph Check
- **Script**: [docs_check.py](../../tools/docs_check.py) · **Hook**: [docs_bump_updated.py](../../tools/docs_bump_updated.py)
- **Workflow**: [.github/workflows/docs-check.yml](../../.github/workflows/docs-check.yml) — runs on any push/PR touching `docs/`
- **Execution**:
  ```bash
  python3 tools/docs_check.py            # errors fail (exit 1)
  python3 tools/docs_check.py --backlog  # docs most in need of re-verification
  ```
- Validates link + anchor resolution, code-path existence, frontmatter, tag vocabulary, and section-index
  coverage. Also flags **code drift** — docs whose cited source files were committed *after* the doc's
  `verified_against_code` date — and staleness past 30 days. Rules: [AI_Guidelines § 6](AI_Guidelines.md). Rationale: [DocumentationAudit](../DocumentationAudit.md).

### CI/CD
The project is configured to run these tests automatically in the pipeline to prevent regressions in core transport and utility logic.

---

## 🚧 In-Progress Implementation Plans

Active feature work lives here. Once a feature is shipped and stable, the implementation plan doc should be **archived** (move to `05_Archive/`) or **converted** into a stable reference doc in the appropriate section.

> [!IMPORTANT]
> Do not reference these docs as ground truth for how the system works — they describe *intended* behaviour, not necessarily the current state. Check the actual source file first.

*(Empty as of 2026-07-28.)* [**Cargo Destination Button**](CargoDestinationButtonImplementation.md) was
verified fully shipped this session — every function, signal, and state var it describes matches source
exactly (`inspector_builder.gd`, `vendor_trade_panel.gd`, `main_screen.gd`, `UI_manager.gd`). Removed from
this list per the policy above; the doc itself is unmoved and now reads as a stable reference, not a
plan.

