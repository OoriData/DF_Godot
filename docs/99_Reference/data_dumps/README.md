# Data Examples — Reference Payloads

Real snapshots of common backend payloads and in-game data structures, captured for understanding object **shapes** when working on services, models, or UI.

> [!NOTE]
> These are **reference dumps, not fixtures** — no code loads them at runtime. They are point-in-time captures; fields drift as the backend (`DF_Lib`) evolves, so **verify against live data** before relying on exact keys. Regenerate when in doubt (see below).

## Index

| File | Domain object | Shape | Related doc |
|---|---|---|---|
| [`Map_example.md`](Map_example.md) + [`Map_example.json`](Map_example.json) | Full world map (tiles → settlements → vendors → cargo) | summary note + raw `.json` attachment | [MapSystem/Data](../../03_Systems/MapSystem/Data.md) · [Schema](../../01_Architecture/Schema.md) |
| [`convoy_data_example.json`](convoy_data_example.json) | Convoy (processed) | `list[1]` dict | [Schema](../../01_Architecture/Schema.md) · [ConvoyService](../../03_Systems/ConvoyService.md) |
| [`raw_convoy_data.json`](raw_convoy_data.json) | Convoy (raw, pre-processing) | `list[1]` dict | [DataFlow](../../01_Architecture/DataFlow.md) |
| [`vehicle_example.json`](vehicle_example.json) | Vehicle (parts, cargo, make_model) | dict | [VehicleMenu](../../02_UI_UX/VehicleMenu.md) |
| [`cargo_example.json`](cargo_example.json) | Cargo items | `list[6]` dicts | [ItemsAndMissions](../../03_Systems/ItemsAndMissions.md) |
| [`part_example.json`](part_example.json) | Vehicle parts | `list[15]` dicts | [Mechanics](../../03_Systems/Mechanics.md) |
| [`part_compat_example.txt`](part_compat_example.txt) | Part-compatibility output | text | [Mechanics](../../03_Systems/Mechanics.md) |
| [`vendor_example.json`](vendor_example.json) | Vendors | `list[4]` dicts | [VendorPanel/Data](../../02_UI_UX/VendorPanel/Data.md) |
| [`tutorial_steps.json`](tutorial_steps.json) | Tutorial step schema | dict, keyed by level | [TutorialSystem/StepSchema](../../03_Systems/TutorialSystem/StepSchema.md) |
| [`dump_3920_convoy_c2092202-…json`](dump_3920_convoy_c2092202-e2eb-484c-a4b9-38706f8a5ed5.json) | Diagnostic snapshot (one convoy + settlements sample) | dict | one-off debug capture |

## Regenerating

- **Map** — `Map_example.json` (raw payload) + `Map_example.md` (light summary note) are auto-written **together, once per session** by `APICalls._debug_dump_map_to_file()` ([`Scripts/System/api_calls.gd`](../../../Scripts/System/api_calls.gd)) on the first map load in dev. The note carries tile dimensions, total vendor-cargo count, and a `recipient`-field sanity check.
- The other dumps were captured manually from live API responses.

## Notes

- The map example is **split** for the Obsidian graph: `Map_example.md` is a light summary note (~0.5 KB, a healthy graph node), and the full payload is the linked `Map_example.json` attachment (~4.4 MB, not graphed while `showAttachments` is off). The dumper writes both as a pair — keep them together.
- `dump_3920_convoy_…json` is a one-off diagnostic capture — safe to delete once that investigation is closed.
