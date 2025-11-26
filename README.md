[Godot 4.4](https://godotengine.org/download/archive/4.4-beta1/)

## Data Item Refactor

Standardized cargo data classes are defined in `Scripts/Data/Items.gd`:

- `CargoItem` base (name, quantity, unit_weight/unit_volume, quality, condition, tags)
- `PartItem`, `MissionItem`, `ResourceItem`, `VehicleItem` subclasses with extra typed fields and helper summaries.

Factory: `var typed = CargoItem.from_dict(raw_dict)` decides the correct subclass. Existing raw dictionaries remain accessible via `typed.raw` for legacy fallback.

GameDataManager now attaches a `cargo_items_typed` array to each vehicle inside `vehicle_details_list`. UI menus (`convoy_cargo_menu.gd`, `vendor_trade_panel.gd`) prefer these typed objects and gracefully fall back to legacy `cargo` arrays if absent.

Advantages:

- Centralized parsing / numeric coercion
- Predictable properties for UI (no repeated guesswork)
- Easy future extension (add new subclass + detection heuristics in one place)

Migration path: Gradually replace dictionary-specific logic with `if item is PartItem:` style checks and method calls (e.g., `get_modifier_summary()`).
