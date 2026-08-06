---
type: technical
tags:
  - layer/protocol
  - kind/reference
  - concept/binary-protocol
  - status/current
aliases:
  - "The Index and the Record"
  - "Map API vs Vendor API"
created: 2026-08-06
updated: 2026-08-06
verified_against_code: 2026-08-06
status: current
---

# The Index and the Record: `/map` vs `/vendor/get`

**The same vendor reaches the client twice, from two endpoints, carrying different numbers.** This page
is the usage contract for choosing between them. [DataBoundaries](DataBoundaries.md) maps *which fields*
cross the binary wire; this page answers *which source you are allowed to act on*.

> [!IMPORTANT]
> **Display from the index. Act on the record.**
>
> Rendering a list from `/map` is correct and fast. Letting a player *transact* against a `/map` number
> is how the panel came to offer a $23,000 vehicle that the server refused at $45,750 (`S15-1`).

---

## The two sources

| | **The index** — `GET /map/get` | **The record** — `GET /vendor/get` |
|---|---|---|
| Format | Binary, fixed byte layout | JSON |
| Contains | Only fields **explicitly packed** — a thin subset | Everything, including computed properties |
| Scope | The **whole world**, one request | One vendor |
| Freshness | A cached snapshot. Stale **by design** | Live, read at request time |
| Cost | ~1.4 MB, ~15 ms to serialize | Small |
| Reaches the client as | `Tools.deserialize_map_data()` → `GameStore.set_map()` → `get_settlements()` | `VendorService` → `SignalHub.vendor_panel_ready` |
| Use it for | Names, positions, stock counts, a price to **sort and display** by | Any number the server will **validate**: price, capacity, limits |

## Why the index cannot be trusted for actions

Two independent reasons, and fixing one does not fix the other:

1. **It is a snapshot.** Another player buys the vehicle; a vendor restocks; a part is installed. The
   index lags by design — that is what makes one request for the whole world affordable. Even a
   *perfectly correct* packer cannot fix this.
2. **It can carry different numbers than the transaction endpoint.** The packer reads keys by name from
   the backend's `to_JSONable_dict()`. When a key is renamed or was never emitted, `dict.get(key, 0)`
   packs a plausible default and **nothing raises anywhere**. This has happened three times — see
   [DataBoundaries § Known divergences](DataBoundaries.md#known-divergences).

The second is the nastier one, because the failure is *invisible on screen*. Every surface — the row,
the inspector, the confirm footer — agreed with every other surface, because they all read the same
wrong field. Only the server disagreed, and only at purchase time.

---

## The rule, concretely

### Reading

- **Vendor lists, map labels, settlement previews** → index. Correct, and the only affordable option.
- **A price, capacity, or limit you are about to act on** → record.

### Acting

`VendorTradeVM.price_trust()` classifies every buy-mode item before the action button is enabled:

| State | Meaning | Button |
|---|---|---|
| `PENDING` | No `/vendor/get` for this vendor yet | disabled — *"Confirming price…"* |
| `TRUSTED` | Priced from `/vendor/get`, or a vendor-level field the binary carries correctly | enabled |
| `STALE` | The payload landed and this row was **not** in it | disabled — *"No longer available"* |

Three states, not a boolean: collapsing `PENDING` and `STALE` leaves a row that vanished server-side
stuck on "Confirming price…" forever, because nothing will ever arrive to confirm it.

Raw resources (fuel/water/food) are exempt — they price off vendor-level fields (`fuel_price` and
friends) that the binary payload **does** carry correctly, so there is nothing to wait for.

### Keeping the record alive

The settlement menu re-feeds the panel from the `/map` snapshot on **every** store update
(`convoy_settlement_menu.gd` `_refresh_active_vendor_panel` → `_vendor_data_for_panel`), which in a live
session is roughly once a second. Left alone, that discards the authoritative payload seconds after it
arrives. [`VendorAuthoritativeCache`](../../Scripts/System/vendor_authoritative_cache.gd) retains it and
refills the gaps on each rebuild.

**Hydration only ever ADDS keys the incoming record is missing — it never overwrites one it has.** The
index is the *fresher* source for stock counts, and `VendorOptimisticStock` deltas are applied
downstream. Filling gaps is safe; taking sides on a field both sources carry is not.

---

## Two traps this cost real time to learn

### Capture at the service, not at the panel

The cache is filled by `VendorService._on_vendor_data_received`, **not** by a panel signal handler.

A settlement with several vendors has **one `VendorTradePanel` instance per tab**, each guarding on its
own `_active_vendor_id`. Whether any given instance records an arriving payload depends on which tab is
active and where each panel sits in its lifecycle. On device this showed up as `/vendor/get` returning
correctly for the right vendor while the cache stayed empty and the buy gate hung.

**Capture belongs where the data provably lands** — the service — which is also why the cache lives in
`Scripts/System/`, not under `Menus/`. A service reaching into the UI layer would invert
Law 2, [The Law of Unidirectional Data](../AI_ONBOARDING.md).

### `_update_transaction_panel()` owns the action button

It evaluates every guard — affordability, quantity, per-vehicle fit, price trust — and sets
`disabled = not can_transact`. `vendor_panel_selection_controller.gd` used to re-enable the button
unconditionally a few lines after calling it, silently undoing **all** of them, including guards that
predated the price work (S13-7's "Only N fit", S13-15's quantity ≤ 0).

**Selecting an item is not a reason to believe it can be bought.** Do not set
`action_button.disabled = false` outside that function.

---

## Diagnosing

`perf_log_enabled` on the panel prints one line per state transition:

```
[VendorPanel][S15-7] trust=PENDING vid='1104…' item='BXR' has_flag=false has_vendor=false value=<none> base_value=5000
```

| Reading | Means |
|---|---|
| `has_vendor=false` | No `/vendor/get` captured for this vendor. The panel re-requests on a 4 s debounce; if that never resolves, check the request is going out **and** coming back |
| `has_vendor=true, has_flag=false` | Payload arrived, this row isn't in it → `STALE`, surfaced as "No longer available" |
| `value=<none>` | **The displayed price is `base_value`** — the index number, not the charged one |

That last row is the one to internalise. `value=<none>` with a believable price on screen is this bug
class in its natural habitat.

---

## Related

- **See also:** [DataBoundaries](DataBoundaries.md) — which fields cross the binary wire, and the known key divergences
- **See also:** [DF_Lib](DF_Lib.md) — the packer itself, the case studies, and the publish/deploy chain
- **See also:** [VendorPanel Overview](../02_UI_UX/VendorPanel/VendorPanelOverview.md) — the panel's structure
- **Implemented in:** [AutoloadOrder](AutoloadOrder.md) — `VendorService` (capture), `GameStore` (both paths land here)
- **Live status:** [TODO.md](../TODO.md) — Sprint 15
