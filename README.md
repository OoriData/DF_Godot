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
