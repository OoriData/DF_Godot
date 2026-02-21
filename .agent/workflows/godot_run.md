---
description: How to run Godot engine from the terminal for testing, exporting, and importing
---

# Running Godot from the Terminal

The Godot binary is at `/Applications/Godot.app/Contents/MacOS/Godot`.

## Important: Log File Workaround

Godot 4.6 has a bug where `RotatedFileLogger` segfaults in headless mode. **Always** pass `--log-file /tmp/godot.log` when running headlessly.

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

Exit code 0 = all tests passed, 1 = failures.

## Run a Specific Scene

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --path /Users/choccy/dev/DF_Godot \
  --log-file /tmp/godot_scene.log \
  --scene res://path/to/Scene.tscn \
  --quit-after 300
```

## Reimport Project (Rebuild .godot/imported/ Cache)

```bash
// turbo
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --path /Users/choccy/dev/DF_Godot \
  --log-file /tmp/godot_import.log \
  --import
```

## Export (used in CI, shown for reference)

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --export-release "Web" build/web/index.html
```
