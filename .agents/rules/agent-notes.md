---
trigger: always_on
---

# Agent Notes — Desolate Frontiers (Godot 4.6)

Notes and instructions for AI coding agents working on this project.

## Running Godot from the Terminal

The Godot binary is located at:
```
/Applications/Godot.app/Contents/MacOS/Godot
```

### Critical: Always Use `--log-file`

Godot 4.6 has a bug where `RotatedFileLogger` crashes with a segfault (signal 11) in headless mode.
**Always** pass `--log-file /tmp/godot.log` (or similar) when running headlessly:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --path /Users/choccy/dev/DF_Godot \
  --log-file /tmp/godot.log \
  --quit
```

## Run Unit Tests

```bash
// turbo
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --path /Users/choccy/dev/DF_Godot \
  --log-file /tmp/godot_test.log \
  --scene res://Tests/TestRunner.tscn \
  --quit-after 600
```

> [!IMPORTANT]
> Because `class_name` resolution is unreliable in headless mode, always use `preload()` in your test scripts for any non-autoloaded classes or utilities.

- Exit code `0` = all tests passed
- Exit code `1` = test failures
- `--quit-after 600` is a safety timeout (10 seconds at 60fps)

### Running a Specific Scene

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --path /Users/choccy/dev/DF_Godot \
  --log-file /tmp/godot_scene.log \
  --scene res://path/to/YourScene.tscn \
  --quit-after 300
```

### Reimporting the Project

If font or asset imports are stale/broken, rebuild the import cache:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --path /Users/choccy/dev/DF_Godot \
  --log-file /tmp/godot_import.log \
  --import
```

If that doesn't fix it, delete `.godot/imported/` first, then run `--import`.

## Known Headless Gotchas

| Issue | Details |
|-------|---------|
| **`class_name` not found** | **CRITICAL**: Godot's script class cache often fails to build/read in headless mode. Avoid relying on global class names in test scripts. Use `preload()` for all scripts and utilities. |
| **`content_scale_factor <= 0`** | `UI_scale_manager.gd` has headless guards to prevent this. If you add new display-dependent code, check `DisplayServer.get_name() == "headless"` first. |
| **Autoloads fire in headless** | All autoloads (including `APICalls`) initialize normally in headless mode. `APICalls` has a persisted session token and will auto-login against the production API. Keep this in mind when running tests. |
| **Font import failures** | The emoji/math fonts may show import errors if the `.godot/imported/` cache is stale. These are non-fatal warnings; tests still run. |

## Project Structure Quick Reference

| Path | Purpose |
|------|---------|
| `Scripts/System/` | Core autoloads (Tools, APICalls, Logger, SettingsManager, etc.) |
| `Scripts/System/Services/` | Service layer (GameStore, ConvoyService, VendorService, etc.) |
| `Scripts/Menus/` | Menu UI scripts |
| `Scripts/UI/` | UI components (tutorial, scale manager, etc.) |
| `Scripts/Data/` | Data models (Convoy, Vehicle, CargoItem, Settlement, etc.) |
| `Scenes/` | `.tscn` scene files |
| `Tests/` | Unit tests (run via `TestRunner.tscn`) |
| `Debug/` | Debug/test scenes |
| `.github/workflows/` | CI/CD pipelines |
| `docs/` | Documentation |

## API Configuration

The API base URL is configured in `app_config.cfg` under `[api]`. The `active_env` key determines which URL to use:
- `dev` → `base_url_dev`
- `prod` → `base_url_prod`

Can also be overridden with the `DF_API_BASE_URL` environment variable.

## Workflow Available

There's a workflow at `.agent/workflows/godot_run.md` with ready-to-use commands for running Godot.
