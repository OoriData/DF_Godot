---
type: technical
tags:
  - layer/protocol
  - kind/deep-dive
  - concept/binary-protocol
  - status/current
aliases:
  - "DF_Lib: Shared Binary Protocol Library"
created: 2026-07-17
updated: 2026-08-06
verified_against_code: 2026-08-06
status: current
---

# DF_Lib: Shared Binary Protocol Library

> [!WARNING]
> **A field rename in the backend's JSON schema does NOT automatically reach the binary map wire format.** The two are hand-synced across three separate repos. See the [Case Study](#case-study-the-vanishing-vehicle-efficiency-stat) below before assuming "the JSON looks right" means a stat will render correctly everywhere.
>
> **This has now happened three times** (efficiency → `0`, vehicle price → chassis-only, cargo price →
> `0`). The failure is silent by construction: `dict.get(missing_key, 0)` raises nothing. Before editing
> any `to_JSONable_dict()`, read [Testing the contract](#testing-the-contract-added-2026-08-06) — there is
> now a test that names the offending key for you.

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

## Case study 2: the under-quoted vehicle price

**Symptom (reported by players, 2026-08-06):** *"users do not have the money to purchase a vehicle."* The
vendor panel listed a vehicle at a price the player could afford; the purchase came back `400` —
`Convoy does not have enough money ($23362) to buy the vehicle ($45750)`. The player retried five times.

**Root cause:** the same mechanism as the efficiency case, but with a *different signature*. `serialize_vehicle`
packed `base_value` — the bare chassis price — while the server charges the computed
`Vehicle.value = base_value + part_modifiers['total_part_value']`
(`chassis/df_obj/vehicle_cls.py:430`, enforced in `vendor_cls.py:694`). Installed parts routinely exceed
the chassis price, so the quote was roughly half the real one.

**Why it survived so long:** the efficiency bug produced a **`0`**, which reads as obviously broken. This
one produced a **plausible smaller number**. There is no visual tell — the panel, the inspector and the
confirm dialog all agreed with each other, because they all read the same wrong field. The only
disagreement was with the server, and only at purchase time. Note also that
`VendorTradeVM.vehicle_price()` *prefers* a `value` key and only falls back to `base_value`, so the code
was already written for the correct field — the binary payload simply never carried it.

**Resolution — fixed in the client, NOT in df_lib.** A one-line packer change was written and tested:

```python
int(vehicle.get('value', vehicle.get('base_value', 0)) or 0),   # written, tested, REVERTED
```

Same slot, same width, so it needed no Godot change and would have fixed every already-shipped build
via the deploy alone. It was **reverted anyway**, deliberately: it required publishing df_lib and
redeploying the backend, and the client can compensate without either. `df_lib` remains at **0.3.3**
packing `base_value`.

The client fix instead prices vehicles from `/vendor/get` and refuses to enable Buy until it has —
*display from the index, act on the record* ([The Index and the Record](IndexAndRecord.md), `S15-7`).
That fix is strictly more general: it also covers the index simply being **stale**, which no packer
change can address.

**The trade, recorded so it isn't rediscovered:** a df_lib deploy reaches players already on a shipped
build with no app update; the client fix reaches them only on the next release. If this bug class ever
needs a same-day hotfix, the packer route is the fast one. Status: `S15-1` in [TODO.md](../TODO.md).

## Testing the contract (added 2026-08-06)

Both bugs above shipped because **nothing tested the producer against the packer**. `df_lib`'s own
round-trip test fed the packer hand-written dicts that used *stale key names*, so it exercised the
fallback branches — a backend rename could not fail it. Two suites now close that:

| Suite | Repo | What it pins |
|---|---|---|
| `test/test_map_serialization_contract.py` | `~/Work/desolate_frontiers` | Starts from **real model objects**. Derives the packer's expected input keys from `map_struct.py`'s own source via AST, then diffs against the live `to_JSONable_dict()`. |

It also pins the `base_value` / `value` divergence as a *deliberate* one, so that making the packer
write `value` fails the suite — the signal to tell the client side its compensation is now redundant,
rather than a test to quietly delete.

The second is the one that matters for this bug class. Because the key list is derived from source rather
than hand-maintained, **new fields are covered the day they are added**. Run it after any change to a
`to_JSONable_dict()`:

```bash
cd ~/Work/desolate_frontiers && python3 -m pytest test/test_map_serialization_contract.py -q
```

It was mutation-verified — reverting each historical bug makes it fail — rather than assumed to work
because it was green. Two gaps it surfaced are recorded as `S15-2` (cargo carries no price on the binary
path) and `S15-3` (four vehicle fields no model attribute ever produces).

> [!WARNING]
> **Neither suite can catch a `tools.gd` divergence.** Both are Python↔Python; production decoding is the
> hand-written GDScript mirror, an independent second implementation of the same layout. A layout error
> introduced there would leave every test green. Closing that needs a golden-bytes fixture decoded by
> both — see `S15-5`.

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
- **Field-level boundary map**: [Data Boundaries](DataBoundaries.md) — which fields cross which pipe, and the known key-name divergences
- **Usage contract**: [The Index and the Record](IndexAndRecord.md) — when to read `/map` vs `/vendor/get`, and why a correct packer still isn't enough to make the index safe to transact against
