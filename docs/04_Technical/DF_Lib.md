---
type: technical
tags:
  - technical
  - codex/df_lib
  - codex/deployment
aliases:
  - "DF_Lib: Shared Binary Protocol Library"
created: 2026-07-17
---

# DF_Lib: Shared Binary Protocol Library

> [!WARNING]
> **A field rename in the backend's JSON schema does NOT automatically reach the binary map wire format.** The two are hand-synced across three separate repos. See the [Case Study](#case-study-the-vanishing-vehicle-efficiency-stat) below before assuming "the JSON looks right" means a stat will render correctly everywhere.

## What it is

`df_lib` is a small **standalone Python package** — repo `github.com/OoriData/DF_Lib`, local checkout at `~/Work/DF_Lib` (pylib source lives under `pylib/`, published to PyPI as `df_lib`). It defines the **binary wire format** for the `/map` endpoint: `pylib/map_struct.py` has `serialize_*`/`deserialize_*` functions that pack tiles → settlements → vendors → vehicles/cargo into a fixed-layout byte stream (see [struct.pack format strings], big-endian, fixed-width strings).

It is a **separate dependency**, not part of either the backend or the Godot client:
- The backend (`~/Work/desolate_frontiers`) imports it as a normal pip package. `requirements.txt` lists it unpinned (`df_lib`); **`constraints.txt` pins the exact version** actually installed (e.g. `df_lib==0.3.3`). `engine/routers/map_api.py` calls `serialize_map(df_map.to_JSONable_dict())` from it to build the `/map` response bytes.
- The Godot client does **not** import `df_lib` (GDScript can't). Instead, [tools.gd](../../Scripts/System/tools.gd) contains a **hand-written mirror** of the same byte layout (`deserialize_vehicle`, `deserialize_vendor`, `deserialize_settlement`, `deserialize_map_data`). See [Map System: Data (Payload & Parsing)](../03_Systems/MapSystem/Data.md) for the client-side parsing pipeline.

**There is no codegen or shared schema file.** The byte layout is defined once in `df_lib`, and mirrored by eye in `tools.gd`. Keeping them in sync is a manual, easy-to-miss step.

## Why the vendor panel matters here specifically

Vehicle/vendor data reaches the Godot client through **two independent paths** that carry different (and driftable) schemas:

| Path | Source | Format | Used by |
| :--- | :--- | :--- | :--- |
| `GET /vendor/get` | `Vendor.to_JSONable_dict()` (backend, live Python object) | Full JSON — every field, including computed properties (`efficiency`, `top_speed`, etc.) | Vendor buy/sell transaction calls |
| `GET /map` | `serialize_map()` → `df_lib.map_struct.serialize_vehicle` | Binary, fixed byte layout, **only the fields explicitly packed** | `GameStore.set_map()` → **vendor panel's stat display** reads vehicles from here (`_store.get_settlements()` → `_vendors_from_settlements_by_id`), not from `/vendor/get` |

The vendor panel's vehicle stats come from the **binary map path**, not the rich JSON path. A field can be present, correct, and fully computed in the backend's JSON serialization and still show as blank/zero in the vendor panel, because `df_lib`'s binary packer never learned about the rename/field.

## Case study: the vanishing vehicle efficiency stat

**Symptom:** every vendor vehicle showed off-road capability, top speed, cargo/weight capacity — but efficiency was always blank or 0. Multiple prior debugging sessions concluded "not a backend issue" and "not a frontend issue" and left it unresolved because each *individually correct* observation was about the wrong data path.

**Root cause:** the backend renamed the vehicle efficiency field `base_fuel_efficiency` → `base_efficiency` in `Vehicle.to_JSONable_dict()` (`desolate_frontiers/chassis/df_obj/vehicle_cls.py`). The JSON path (`/vendor/get`) picked up the rename automatically — it just serializes whatever's on the object. **`df_lib/pylib/map_struct.py::serialize_vehicle` did not** — it still read the old key:
```python
int(vehicle.get('base_fuel_efficiency', 0) or 0),   # key no longer exists on the dict → always packs 0
```
Every other stat in that same struct (`base_top_speed`, `base_offroad_capability`, …) wasn't renamed, so they kept working — which is exactly why the bug looked efficiency-specific rather than systemic, and why "check the backend" / "check the frontend" each came back clean.

**How it was actually found:** compare the *live* key-set of a vehicle dict as rendered in the vendor panel against (a) the backend's current `to_JSONable_dict()` output and (b) the binary decoder's field list in `tools.gd`. The panel's vehicle keys were an exact match for the **binary decoder's 14-field layout**, not the JSON schema — that's what pointed at `df_lib` instead of either the Godot code or the backend JSON code, both of which were already correct.

**Fix:** `map_struct.py`'s pack/unpack keep the same byte slot (so the Godot mirror in `tools.gd` needs no change) but read the current key with a fallback:
```python
int(vehicle.get('base_efficiency', vehicle.get('base_fuel_efficiency', 0)) or 0),
```

## The lesson: when a backend field is renamed

If a field on `Vehicle`, `Cargo`, `Vendor`, or `Settlement` is renamed/added/removed in the backend's `to_JSONable_dict()`, check **both**:
1. Does anything read the old key name elsewhere in the backend? (grep the backend repo)
2. **Does `df_lib/pylib/map_struct.py` pack/unpack that field, and does it use the old key?** (grep `~/Work/DF_Lib/pylib/map_struct.py`) If yes, the client's binary path silently gets a stale/zero value even though the JSON path is fine — and no error is raised anywhere, because `dict.get(old_key, 0)` just quietly returns the fallback.

If the byte layout itself changes (a field added/removed/resized, not just renamed), `tools.gd`'s hand-written decoder in the Godot client **must be updated to match**, or every offset after that field will read garbage. Renames alone (same size, e.g. int16 base_efficiency in the same slot as int16 base_fuel_efficiency) don't require a Godot change — only a `df_lib` source-key update.

## Version / publish / deploy workflow

`df_lib` is versioned and published independently; a fix in the local checkout does **nothing** until it goes through this full chain:

1. **Bump the version** — `~/Work/DF_Lib/pylib/__about__.py`, `__version__ = 'X.Y.Z'`. Required even for a one-line fix: PyPI never lets you re-upload an existing version number.
2. **Build** — `cd ~/Work/DF_Lib && hatch build` → wheel + sdist land in `dist/`. Sanity-check the fix landed: `unzip -p dist/df_lib-X.Y.Z-py3-none-any.whl df_lib/map_struct.py | grep <the fix>`.
3. **Publish to PyPI** ⚠️ public, irreversible — `hatch publish`.
   - **Known `hatch` bug**: the username prompt shows a `[__token__]` default, but `hatch`'s prompt call doesn't pass that default through to `click.prompt`, so pressing Enter on an empty username **loops forever** instead of falling back. You must type the literal text `__token__`, then paste the API token as the password.
   - **API tokens are shown once at creation** — if lost, there's no recovery, only revoke-and-reissue from `pypi.org/manage/account/token/`. A token must either be scoped to the `df_lib` project (requires already being a listed owner/maintainer) or be account-wide.
4. **Bump the pin** — `desolate_frontiers/constraints.txt`: `df_lib==X.Y.Z`. (`requirements.txt` itself is unpinned; `constraints.txt` is what actually locks the installed version.)
5. **Rebuild & redeploy the backend container** ⚠️ touches the live server —
   ```sh
   op run --env-file op_prod.env --no-masking -- docker compose -f containerization/compose.df_api.yml up -d --build
   ```
6. **Verify** — no DB migration/regen is needed: `serialize_map()` re-packs live DB values fresh on every `/map` request. Just re-fetch the map in the client after the redeploy.

## Related Files
- **Wire format source of truth**: `~/Work/DF_Lib/pylib/map_struct.py` (separate repo — not inside `DF_Godot`)
- **Godot binary mirror**: [tools.gd](../../Scripts/System/tools.gd)
- **Backend consumer**: `~/Work/desolate_frontiers/engine/routers/map_api.py`, `~/Work/desolate_frontiers/chassis/df_obj/vehicle_cls.py` (separate repo)
- **Client parsing pipeline doc**: [Map System: Data (Payload & Parsing)](../03_Systems/MapSystem/Data.md)
