---
type: technical
tags:
  - layer/protocol
  - kind/reference
  - concept/binary-protocol
  - status/current
aliases:
  - "Data Boundaries: Which Fields Cross Where"
created: 2026-07-28
updated: 2026-08-06
verified_against_code: 2026-08-06
status: current
---

# Data Boundaries: Which Fields Cross Where

**The same game object reaches the client through two different pipes, carrying different field names.**
This page maps that seam. It exists because the project's most expensive bug class lives here — a value
that is wrong everywhere while both the backend and the client are individually correct.

That wrongness is usually a blank or `0`, but **not always**: it can be a fully plausible number that
only reveals itself when the server rejects the action the client offered
([`base_value` vs `value`](#base_value-vs-value--the-under-quoted-vehicle-price)).

> [!IMPORTANT]
> **Read this before concluding "not a backend issue" or "not a frontend issue."** Both can be true at
> once. The bug is in the *third* repo, or in the hand-written mirror of it.

Companion docs: [DF_Lib](DF_Lib.md) explains the *mechanism* and the version/publish workflow;
[MapSystem/Data](../03_Systems/MapSystem/Data.md) covers the client-side parsing pipeline. This page is
the **field-level map** neither of those provides.

**If your question is "which endpoint should I read?" rather than "which fields cross?", you want
[The Index and the Record](IndexAndRecord.md)** — the usage contract for `/map` vs `/vendor/get`, and the
rule that keeps this bug class from reaching players: *display from the index, act on the record*.

---

## The three repos

| Repo | Owns | Local path |
|---|---|---|
| **DF_Godot** (this one) | The client. Hand-written binary decoder in `Scripts/System/tools.gd`. | — |
| **desolate_frontiers** | The backend. JSON serializers (`to_JSONable_dict()`), the `/map` endpoint. | `~/Work/desolate_frontiers` |
| **DF_Lib** | The **binary wire format** (`pylib/map_struct.py`). Published to PyPI, pinned by the backend. | `~/Work/DF_Lib` |

**There is no codegen and no shared schema file.** `map_struct.py` defines the byte layout; `tools.gd`
mirrors it by eye. Keeping them in sync is manual.

---

## The two paths

| | JSON path | Binary path |
|---|---|---|
| **Endpoint** | `GET /vendor/get`, `/user/get`, `/convoy/…` | `GET /map/get` |
| **Produced by** | backend `to_JSONable_dict()` — serializes whatever is on the object | `df_lib.map_struct.serialize_*` — only fields **explicitly packed** |
| **Consumed by** | `VendorService`, `ConvoyService`, `UserService` → `GameStore` | `Tools.deserialize_map_data()` → `GameStore.set_map()` |
| **Picks up a backend rename automatically?** | ✅ Yes | ❌ **No** — `map_struct.py` reads a hardcoded key name |
| **Fails loudly on rename?** | n/a | ❌ No — `dict.get(old_key, 0)` silently packs `0` |

**The vendor panel's vehicle stats come from the binary path**, not the rich JSON one
(`vendor_trade_panel.gd` reads `_vendors_from_settlements_by_id`, populated from
`GameStore.get_settlements()`). That is why a field can be perfect in `/vendor/get` and still render
blank in the vendor panel.

---

## What actually crosses the binary boundary

Field lists below are the **client decoder's** ground truth (`Scripts/System/tools.gd`, verified
2026-07-28). If `map_struct.py` packs a different order or width, every field after the divergence reads
garbage — see [Diagnosing](#diagnosing-a-suspect-field).

### Vehicle — `deserialize_vehicle()`

`vehicle_id`(36s) · `name`(64s) · `base_desc`(512s) · `wear`(f32) · **`base_fuel_efficiency`**(u16) ·
`base_top_speed`(u16) · `base_offroad_capability`(u16) · `base_cargo_capacity`(u32) ·
`base_weight_capacity`(u32) · `base_towing_capacity`(u32) · `ap`(u16) · `base_max_ap`(u16) ·
`base_value`(u32) · `vendor_id`(36s) · `warehouse_id`(36s)

> **Slot 12 is the bare chassis `base_value`, NOT the price the server charges.** `/vendor/vehicle/buy`
> charges `Vehicle.value` = `base_value + total_part_value`, and installed parts often outweigh the
> chassis — a listed $23k vehicle was refused at $45,750 (`S15-1`). A df_lib fix to pack `value` into
> this same slot was written and tested, then **reverted**: it needed a publish + backend redeploy, and
> the client compensates instead. **Do not treat this slot as a purchase price.** Contract:
> [The Index and the Record](IndexAndRecord.md).

### Cargo — `deserialize_cargo()`

`cargo_id`(36s) · `name`(64s) · `base_desc`(512s) · `quantity`(u32) · `volume`(u32) · `weight`(u32) ·
`capacity`(f32) · `fuel`(f32) · `water`(f32) · `food`(f32) · **`base_price`**(u32) · `delivery_reward`(u32) ·
**`distributor`**(36s) · `vehicle_id`(36s) · `warehouse_id`(36s) · `vendor_id`(36s) · `recipient`(36s)

> [!WARNING]
> **`base_price` and `distributor` are always `0` / `null` on this path** — see
> [the cargo case below](#base_price-and-distributor--cargo-has-no-price-on-the-binary-path) (`S15-2`).

### Vendor — `deserialize_vendor()`

`vendor_id`(36s) · `name`(64s) · `base_desc`(512s) · `money`(u32) · `fuel`(u32) · `fuel_price`(s16) ·
`water`(u32) · `water_price`(s16) · `food`(u32) · `food_price`(s16) · `repair_price`(s16) ·
then nested `cargo_inventory[]` + `vehicle_inventory[]`

### Settlement — `deserialize_settlement()`

`sett_id`(36s) · `name`(64s) · `base_desc`(1024s) · `sett_type`(u8 enum) · imports_count(u8, **discarded**) ·
exports_count(u8, **discarded**) · vendor_count(u8) · then nested `vendors[]`

> [!WARNING]
> **`sett_type` is an integer decoded by a hardcoded client-side table** (`tools.gd:130`):
> `1:tutorial · 2:dome · 3:city · 4:town · 5:city-state · 6:military_base · 7:village`.
> If the backend adds a settlement type, the client silently renders it as `'unknown'` — no error. This
> table must be updated by hand alongside any backend enum change.

---

## Known divergences

### `base_fuel_efficiency` — the vanishing-efficiency case

The one that cost multiple debugging sessions. Full narrative in
[DF_Lib § case study](DF_Lib.md#case-study-the-vanishing-vehicle-efficiency-stat). The field-level state:

| Path | Key emitted | Value |
|---|---|---|
| Binary `/map` → `tools.gd` | `base_fuel_efficiency` | **`0` for every vehicle** |
| JSON `/vendor/get`, owned vehicles | `efficiency` / `base_efficiency` | correct |

The client decoder **still uses the old key name** — `tools.gd:72` reads the u16 slot into
`base_fuel_efficiency`. That's fine (it's just a label for a byte slot), but it means consumers must
handle both names. The established pattern is a **first-non-zero fallback chain**:

```gdscript
# vendor_item_list.gd:499 and inspector_builder.gd:402
["efficiency", "base_efficiency", "fuel_efficiency", "base_fuel_efficiency"]
```

Order matters and **zero must fall through rather than win** — the legacy binary key is present on every
vendor vehicle carrying `0`, so a naive `has()` check picks it up and shadows the real value. Both call
sites document this in-line; don't "simplify" either into a plain `get()`.

### `base_value` vs `value` — the under-quoted vehicle price

**The case that broke the "blank or `0`" heuristic.** The packer read the bare chassis `base_value`
while `/vendor/vehicle/buy` charges `Vehicle.value` = `base_value + total_part_value`. The number on
screen was neither blank nor zero — it was a *believable smaller* price, so it looked like working
software until the purchase came back `400`. Narrative:
[DF_Lib § case study 2](DF_Lib.md#case-study-2-the-under-quoted-vehicle-price). Status: `S15-1`.

| Path | Key emitted | Value |
|---|---|---|
| Binary `/map` → `tools.gd` | `base_value` | chassis only — **under-quotes by the worth of installed parts** |
| JSON `/vendor/get`, owned vehicles | `value` | correct — what the buy endpoint charges |

Parts are not a rounding error: the sample vehicle in `docs/99_Reference/data_dumps/vehicle_example.json`
carries **$116,600** of them against a far smaller chassis.

**This divergence is live and deliberate.** The client compensates rather than the wire being fixed:
the vendor panel retains `/vendor/get` detail and blocks Buy until it has it (`S15-7`). The same is
true of the cargo case below. If you are writing a *new* consumer of map data, that compensation is
not automatic — read [The Index and the Record](IndexAndRecord.md) first.

### `base_price` and `distributor` — cargo has no price on the binary path

**Open (`S15-2`), same class as the two above.** `serialize_cargo` reads `base_price` and `distributor`;
`Cargo.to_JSONable_dict()` emits **`base_unit_price` / `unit_price` / `price`** and **`distributor_id`**.
Neither key exists, so both pack as defaults on every cargo item ever sent. Confirmed in the captured
payload `docs/99_Reference/data_dumps/vendor_example.json`:

```
{'name': 'Jerry Cans', 'base_price': 0, 'delivery_reward': 0, 'distributor': None}
```

`PriceUtil`'s key chain ends at `base_price`, so a binary-derived cargo dict yields **no usable price**.
Expect this to be masked whenever the authoritative `/vendor/get` payload is what the panel currently
holds — the same masking that hid the vehicle price bug. Fixing it means first deciding which key is
canonical; that is a semantic choice, not a rename.

### Structurally-dead vehicle fields

`wear`, `ap`, `base_max_ap`, `base_towing_capacity` are packed and decoded, and **`Vehicle` has no such
attributes at all** — they have never carried a value. 12 bytes per vehicle. `tools.gd:71` decodes `wear`;
no client code reads it. Don't spend debugging time on "why is wear always 0" — nothing produces it
(`S15-3`).

---

## Diagnosing a suspect field

**Not just blank or `0`.** The original heuristic for this page was "a stat reads blank or zero
everywhere". The vehicle-price bug (`S15-1`) shipped *because* it didn't look like that: the packer read
a real, populated, adjacent field and produced a smaller but entirely believable number. Widen the
trigger to **any value the binary path disagrees with the JSON path about** — especially a number the
server later rejects (a price, a capacity, a limit). If the client offers an action and the server
refuses it, suspect this seam before suspecting the server's rules.

When a stat is blank, `0`, or plausibly wrong **everywhere**, in order:

1. **Which path feeds this UI?** Vendor panel vehicle stats and anything from `GameStore.get_settlements()`
   = **binary**. Transaction calls and owned-convoy detail = **JSON**. Getting this wrong sends you to the
   wrong repo.
2. **Compare the live key set** against both schemas. If the dict's keys match the binary decoder's field
   list above (rather than the backend's JSON output), you are on the binary path — go to step 3.
3. **Grep `~/Work/DF_Lib/pylib/map_struct.py` for the old key name.** If `serialize_vehicle` still reads
   a renamed key, it packs the `0`/default and nothing anywhere raises.
4. **Only then** suspect `tools.gd`. A *rename* needs no client change (same byte slot, same width). A
   **layout change** — field added, removed, or resized — breaks every offset after it and requires
   updating `tools.gd` in lockstep.

The tell for a layout desync is *garbage in every field after a certain point*, not a single blank stat.

**Shortcut — run the contract test first.** Steps 2–3 are now automated in the backend repo:

```bash
cd ~/Work/desolate_frontiers && python3 -m pytest test/test_map_serialization_contract.py -q
```

`test_producer_emits_every_key_the_packer_reads` derives the packer's expected input keys from
`map_struct.py`'s own source (AST) and diffs them against the live `to_JSONable_dict()`, naming any key
the packer reads that the model doesn't emit. That is the whole bug class in one assertion. Known,
accepted gaps live in its `KNOWN_GAPS` table, which fails in both directions so they can't rot.

> [!NOTE]
> **This still can't catch a `tools.gd` divergence.** Both that test and `df_lib`'s own suite are
> Python↔Python; production decoding is the hand-written GDScript mirror. A golden-bytes fixture shared
> by both repos — decode the same bytes in Python and in GDScript, assert the same values — is the
> open proposal for closing it (`S15-5`).

---

## When you rename or add a field

Checklist for a backend field change on `Vehicle`, `Cargo`, `Vendor`, or `Settlement`:

- [ ] Does anything else in the backend read the old key? (grep `~/Work/desolate_frontiers`)
- [ ] **Does `df_lib/pylib/map_struct.py` pack this field?** If yes and it reads the old key, the binary
      path silently degrades. Update it, then follow the full
      [version → publish → pin → redeploy chain](DF_Lib.md#version--publish--deploy-workflow) — a local
      edit alone changes nothing.
- [ ] Did the **byte layout** change (not just the name)? Then `tools.gd` must be updated too, or every
      subsequent field reads garbage.
- [ ] Is there a client-side **enum table** for it (like `sett_type`)? Update by hand.
- [ ] Add a fallback chain at the consumer if both key names will coexist in the wild.
- [ ] **Run the contract test** (`~/Work/desolate_frontiers`, `test/test_map_serialization_contract.py`).
      It derives the packer's key list from source, so a rename fails it immediately with the key named.
      If you deliberately leave a gap, add it to `KNOWN_GAPS` **with the reason** — the test also fails
      when a listed gap is closed, so the list can't quietly go stale.
- [ ] Is the field a **number the server validates** (price, capacity, limit)? Then a silent `0` or a
      stale value doesn't just render wrong — it makes the client offer an action the server will
      refuse. Treat those as P1, not cosmetic.

---

## Related

- **See also:** [DF_Lib](DF_Lib.md) — the mechanism, and the publish/deploy chain a fix must go through
- **See also:** [MapSystem/Data](../03_Systems/MapSystem/Data.md) — client-side parse pipeline and header layout
- **See also:** [API_Reference](API_Reference.md) — the JSON-path endpoints
- **Implemented in:** [AutoloadOrder](AutoloadOrder.md) — `Tools` (binary decoder), `GameStore` (both paths land here)
- **Live status:** [TODO.md](../TODO.md) — Systems Audit initiative, backend/DF_Lib contract re-verification
