# Desolate Frontiers — Godot 4 Project

This project uses an event-driven architecture: transport-only APICalls, thin domain services, a snapshot GameStore, and a canonical SignalHub. UI and Map consume store snapshots and hub events.

## Quick Start (macOS)

- Headless wiring smoke test:
Godot.app/Contents/MacOS/Godot --headless --path . -s res://Scripts/Debug/wiring_smoke_test.gd

- Run unit tests (GUT):
Godot.app/Contents/MacOS/Godot --headless --path . -s res://Tests/run_all_tests.gd

## Architecture Overview

Event flow:
- APICalls → Services → GameStore/SignalHub → UI
- UI → Services → APICalls

Autoload order guidance: see docs below.

## Data Item Refactor

Standardized cargo data classes are defined in Scripts/Data/Items.gd:

- CargoItem base (name, quantity, unit_weight/unit_volume, quality, condition, tags)
- PartItem, MissionItem, ResourceItem, VehicleItem subclasses with extra typed fields and helper summaries.

Factory: var typed = CargoItem.from_dict(raw_dict) decides the correct subclass. Existing raw dictionaries remain accessible via typed.raw for legacy fallback.

GameDataManager (legacy) attached a `cargo_items_typed` array to each vehicle inside `vehicle_details_list`. UI menus prefer these typed objects and gracefully fall back to legacy cargo arrays if absent.

Advantages:

- Centralized parsing / numeric coercion
- Predictable properties for UI (no repeated guesswork)
- Easy future extension (add new subclass + detection heuristics in one place)

Migration path: Gradually replace dictionary-specific logic with if item is PartItem: style checks and method calls (e.g., get_modifier_summary()).

## Project Docs

Centralized documentation lives under docs/README.md:
- Architecture: docs/Architecture.md
- System modules: docs/System/README.md
- Services: docs/Services/README.md
- UI/Map: docs/UI/README.md
- Menus: docs/Menus/README.md (see MenuBase contract; menus accept a `Variant` initializer — `Dictionary` or `String convoy_id`)
- Vendor Panel: docs/Menus/VendorTradePanel.md
- Map Layer: docs/Map/README.md
- Testing: docs/Testing/README.md
- Autoload Order: docs/AutoloadOrder.md

## iOS Push Notifications (APNs) – Build Notes

The iOS push notification plugin is built from the upstream `godot-ios-plugins` APN plugin and compiled against Godot 4.6 engine headers. This section documents the exact steps to rebuild the xcframework if we ever need to regenerate it.

### 1. Prerequisites

- macOS with Xcode + iOS SDK installed.
- SCons available on `PATH`:
  - `python3 -m pip install --user scons`
  - Ensure `$HOME/Library/Python/3.12/bin` (or your Python version) is in `PATH`.
- Godot 4.6 engine source (used only as a header source, not fully built):

```bash
cd ~/dev
git clone https://github.com/godotengine/godot.git godot-4.6
cd godot-4.6
git checkout 4.6-stable
```

### 2. Generate engine headers for iOS

From the Godot 4.6 engine root:

```bash
cd ~/dev/godot-4.6
scons platform=ios target=template_debug -j4
```

This produces the headers the APN plugin needs (`core/`, `platform/`, drivers for Apple, etc.).

Stage the headers into a separate folder (header-only engine tree):

```bash
mkdir -p ~/dev/godot-4.6-headers
cp -R core ~/dev/godot-4.6-headers/
cp -R platform ~/dev/godot-4.6-headers/

# Apple/iOS-specific driver headers required by the APN plugin:
mkdir -p ~/dev/godot-4.6-headers/drivers
cp -R drivers/apple ~/dev/godot-4.6-headers/drivers/
cp -R drivers/apple_embedded ~/dev/godot-4.6-headers/drivers/
```

(If future builds complain about other Godot headers, mirror the same pattern and copy only the needed header subtrees into `godot-4.6-headers/`.)

### 3. Prepare `godot-ios-plugins` with header-only engine

Clone the iOS plugins repo and point it at the header tree instead of building the embedded submodule:

```bash
cd ~/dev
git clone https://github.com/godot-sdk-integrations/godot-ios-plugins.git
cd godot-ios-plugins

# Replace any existing 'godot' submodule directory with our header-only tree
rm -rf godot
cp -R ~/dev/godot-4.6-headers godot
```

At this point `godot-ios-plugins/godot/` contains only headers (no thirdparty libs or compiled objects).

### 4. Build the APN static library / xcframework

From the `godot-ios-plugins` root:

```bash
# Build static library for device (arm64)
scons target=release_debug arch=arm64 simulator=no plugin=apn version=4.0

# Build xcframework (device + simulator) using the helper script
./scripts/generate_xcframework.sh apn release 4.0
```

On success, the output will be under `bin/`, e.g.:

- `bin/libapn.arm64-ios.release_debug.a`
- `bin/apn.release.xcframework/`

The xcframework folder contains:

- `Info.plist`
- `ios-arm64/libapn.arm64-ios.release.a`
- `ios-arm64_x86_64-simulator/libapn-simulator.release.a`

### 5. Install into this project

From the `godot-ios-plugins` repo:

```bash
# Copy plugin binary + descriptor into the game repo
cp -R bin/apn.release.xcframework /path/to/DF_Godot/ios/plugins/apn.xcframework
cp plugins/apn/apn.gdip /path/to/DF_Godot/ios/plugins/apn.gdip
```

Final layout in this project:

```text
DF_Godot/
  ios/
    plugins/
      apn.gdip
      apn.xcframework/
        Info.plist
        ios-arm64/
          libapn.arm64-ios.release.a
        ios-arm64_x86_64-simulator/
          libapn-simulator.release.a
```

When exporting for iOS, Godot detects `apn.gdip`, links `apn.xcframework`, and exposes the `APN` singleton so game code can call `register_push_notifications()` and listen for the `device_address_changed` signal to receive the raw APNs device token.
