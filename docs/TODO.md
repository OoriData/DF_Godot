This document serves as the flowing state of things needed in the project, and what resources are needed for each task.

> **Status (2026-07-22):** Sprints 1–10 are complete / code-complete. The long-running QOL bug-fix
> program is **nearly finished** — the last coded items (sold-out vendor filter, Cancel-Journey
> persistence, map-label edge clamp A5) landed on `main` (`b5f591c`/`4c70729`). **Two things remain
> from that program:** (1) the **device-test round 2** pass (checklist below), and (2) a fresh
> **Sprint 11 — QOL bug batch** of newly-reported issues (below). After that, the project pivots to a
> **systems audit & research initiative** (below) to re-baseline the docs against the current code.
>
> **Full completed-sprint detail** (Sprints 1–10, all root-cause narratives, device round 1 results,
> closed backlog items) now lives in **[SprintHistory.md](SprintHistory.md)** — moved out of this file
> 2026-07-22 to keep the TODO forward-looking. This file keeps only the summary table + active/pending work.

---

# Completed Sprint Summary

| Sprint | Theme | Done |
|---|---|---|
| 1 | Quick wins (settings icon, tab counts, cargo sort label, zoom) | ✅ 2026-06-26 |
| 2 | Map camera & overlay (notch, double-scale fix, route fit, close-off-map) | ✅ 2026-06-26 |
| 3 | Baby-blue → Oori token sweep | ✅ 2026-06-26 |
| 4 | Per-menu layout bundles | ✅ 2026-06-29 |
| 5 / 5.5 | Vendor restructure + settlement-hub pivot | ✅ 2026-06-30 |
| 6 | Bug fixes + full mechanic-apply repair | ✅ 2026-07-06 (`54d5493`) |
| 7 | Mobile/landscape polish + warehouse portrait rebuild | ✅ 2026-07-10, device-verified |
| 8 | Tutorial re-fit to settlement-hub UI (10 polish rounds) | ✅ 2026-07-16, device-verified stable |
| 9 | Map/route + vendor/mechanics polish (labels, `[N ↑]` counts, compat prefetch) | ✅ code-complete 2026-07-21 |
| 10 | Closeout QOL (discord flatten, dead-tab removal, Cancel-Journey, sold-out filter) | ✅ code-complete 2026-07-22 |

→ **Detailed narratives, root causes, and file lists for every sprint are in [SprintHistory.md](SprintHistory.md).**

---

# Sprint 11 — QOL bug batch (NEW, 2026-07-22)

Newly-reported issues from continued play-testing. Each entry has a suspected root cause + primary file
so the fix can start with the right file open. **None are coded yet.** Verify each in portrait, landscape,
and desktop where relevant, per the project's device-test rule.

## Client (Godot)

- [x] **Delivery receipt lists non-delivery items** *(P1 — ✅ CODE-COMPLETE 2026-07-22, pending device test)* — the
  "Delivery Receipt" auto-sell modal listed items that were **not** deliveries: rows showed
  `To: Unknown Recipient | Reward: <null> $` (screenshot: *Fuel Tank ×1*, *MRE Boxes ×2*, *Water Jerry
  Cans ×2* alongside the real *Mountain Urchins → Madison, 2880$* delivery). **Root cause:**
  `auto_sell_service.gd::_compare_and_notify` built `sold_items` from `_find_missing_items(last, current)`
  — *every* item that left the inventory — with no delivery filter (consumed fuel/water/food and
  installed/removed parts carry a **null** `delivery_reward` + no recipient, which is exactly the
  `<null>` / "Unknown Recipient" rows). **Fix:** the diff loop now keeps an item only if it has a real
  reward (`delivery_reward != null`) **or** a resolvable recipient (`_resolve_recipient_name() != "Unknown
  Recipient"`) — either signal alone keeps a genuine delivery, so none are dropped; non-deliveries are
  filtered (with a `[AutoSell]` count log for device verification). `Scripts/System/Services/auto_sell_service.gd`.
  (Docs: `03_Systems/AutoSellSystem.md`.)

- [x] **No real "upgrade to DF+" popup — warehouse purchase threw a raw error** *(P1 — ✅ CODE-COMPLETE 2026-07-22, pending device test)* — buying a
  warehouse without DF+ surfaced the **generic error modal** ("An unexpected error occurred. Details:
  POST 'warehouse_created' failed: … upgrade to DF+ …"). Two root causes: `error_translator.gd` only
  mapped the **`PATCH`** verb (device sends **`POST`**), so it fell through to the scary unknown-error
  fallback; and no path routed DF+-gated failures to the existing `PremiumUpgradeModal`. **Fix:** (1)
  `error_translator.gd` warehouse mapping is now **verb-agnostic** (`'warehouse_created' failed:`) with a
  clean full-replacement message, plus a new phrasing-tolerant `is_premium_required()` helper (also
  catches the future vehicle-cap message). (2) `main_screen._on_signal_hub_error_occurred` routes
  premium-gated failures to `PremiumUpgradeModal` **when a live purchase flow exists (Steam)**, else shows
  the clean DF+ message (never the raw modal). (3) `warehouse_menu` defers premium errors to that central
  handler so no second dialog stacks. `Scripts/System/error_translator.gd`, `Scripts/UI/main_screen.gd`,
  `Scripts/Menus/warehouse_menu.gd`. (Docs: `04_Technical/ErrorSystem.md`.)
  - ⚠️ **Cross-platform gap (product decision, not a bug):** `PremiumUpgradeModal` is a **Steam-only**
    microtransaction flow (`create_premium_order` → Steam Overlay). On iOS/Android/Web there is **no
    DF+ purchase path in code** — those platforms now get the clean "Warehouses require DF+" message but
    no buy button. Wiring an off-Steam upgrade path (App Store / Play IAP, or a web/Discord link) is a
    separate product+backend task, in the same bucket as the vehicle-cap enforcement below.

- [ ] **Settlement warehouse inspection broken (regression)** — the ability to **inspect a settlement
  for warehouses** no longer works. Was functional previously; something in the Sprint 5.5 hub pivot or a
  later menu refactor likely broke the entry point. Needs a pinpoint: which control/flow used to open the
  warehouse view from a settlement, and what now no-ops. `Scripts/Menus/warehouse_menu.gd`,
  `Scripts/System/Services/warehouse_service.gd`, `settlement_overview_menu.gd` /
  `convoy_settlement_menu.gd`.

- [ ] **Convoy icon ↔ convoy label anti-collision** — the convoy **label** can overlap the convoy
  **icon** on the map; add anti-collision so the label offsets clear of its own icon (analogous to the
  A5 edge/gear clamp and A4 route-nudge already in `UI_manager`/`convoy_label_manager`). Distinct from A5
  (edge/gear clamp) and A4 (route nudge). `Scripts/UI/convoy_label_manager.gd`.

- [ ] **UI-scale slider: drop the top ~90% of the range** — the desktop UI-scale slider goes far too high;
  the top of the range produces broken/oversized UI. Cap the usable maximum much lower. Today
  `settings_menu.gd:243` sets `s_ui_scale.max_value = get_max_safe_scale()` (which is
  `window_width / MIN_LOGICAL_WIDTH` — very large on desktop) and `UI_scale_manager.gd` clamps to
  `0.5..4.0`. Reduce the effective max (e.g. cap the slider well below `get_max_safe_scale()`, or lower
  the `4.0` clamp) so only the useful low band is reachable. Confirm the exact desired ceiling with the
  user before hard-coding. `Scripts/UI/UI_scale_manager.gd`, `Scripts/Menus/settings_menu.gd`.

- [ ] **Pan direction (invert-pan) inconsistent across sessions** — panning feels like it flips between
  normal and inverted between sessions. Suspect the `controls.invert_pan` setting isn't persisting
  reliably, or `main_screen._apply_settings_snapshot()` reads it before `SettingsManager` has loaded from
  disk (default fallback races the load). Check the save path in `settings_manager.gd` (key
  `controls.invert_pan`, default `false`) and the read at `main_screen.gd:1635`
  (`_opt_invert_pan = bool(sm.get_value("controls.invert_pan", _opt_invert_pan))`) — confirm the value is
  written to disk on toggle and re-read after load, not left at a stale in-memory default.
  `Scripts/System/settings_manager.gd`, `Scripts/UI/main_screen.gd`, `Scripts/Menus/settings_menu.gd`.

## Backend (Python — `~/Work/desolate_frontiers`)

- [ ] **Enforce the free-tier vehicle cap** — the backend does **not** currently check how many vehicles
  a user may own without DF+. Add the cap check server-side (mirror the warehouse DF+ gate) so exceeding
  the free limit returns the same DF+-gated failure the client can route to the premium-upsell popup
  (client side above). Backend repo `~/Work/desolate_frontiers`; verify field/limit names against the
  live schema, not the stale Godot data dumps (see [[reference_backend_repo_and_stale_dumps]]).

---

# Device-test round 2 — the closeout gate

Run on a **touch device** (behaviors marked *touch* can't be proven in the editor). For each row: set the
orientation, do the gesture, confirm **new** vs **old**. Round 1 results (2026-07-21) are archived in
[SprintHistory.md](SprintHistory.md); these are the still-unchecked / re-test rows.

**Batch A — map / route** *(during a live convoy on the map)*
- [ ] **A1 · Labels tap-only** *(touch; portrait + landscape)* — pan-drag across settlements: labels must **not** flash under the finger; a settlement label reveals **only on an explicit tap**.
- [ ] **A3 · Hub vendor cards fit** *(mobile-landscape only)* — open a settlement with 3–4 vendors: all cards pack into one row, shorter, **no clip below the nav bar**, no scroll. (Re-check portrait/desktop unchanged.)
- [ ] **A4 · Labels dodge the route** *(portrait + landscape)* — start journey planning near labeled settlements: labels **nudge vertically off** the route line; topmost labels stay on-screen. *Known limit:* nudge is vertical-only.
- [x] **A5 · Map labels clip the side edges / hide behind the gear box** — ✅ device-verified 2026-07-21 (`4c70729`). Detail in [SprintHistory.md](SprintHistory.md).

**Batch B — vendor / mechanics**
- [ ] **Vendor vehicle inspector parity** *(portrait + landscape + desktop)* — open the vehicle **inspector**: shows **Seats / Make-Model / Color / Shape** when present, plus a working **Description popup** button.
- [ ] **Mechanics `[N ↑]` upgrade count + swap glow** *(re-test — root-caused + fixed 2026-07-21)* — the parent convoy-vehicle dropdown shows `[N ↑]` per vehicle and Swap buttons for an upgradable slot glow green.
- [ ] **Available Parts "Fits:" preview** *(portrait + landscape + desktop)* — parts that fit ≥1 vehicle show a **green highlight + "Fits: …" line**, sorted most-compatible first.
- [ ] **Sold-out items drop from the vendor list** *(portrait + landscape)* — buy out a cargo/resource stack **and** a vehicle: the row **disappears immediately** and does **not** reappear after the authoritative refresh (vehicle stays gone even across a `/map` re-aggregation, via the session sold-guard).

**Sprint 10 re-tests**
- [ ] **Cancel Journey button always present** *(portrait + landscape + desktop)* — with a convoy in transit, the **Cancel Journey** button shows and works even if the snapshot omits `journey_id`.
- [ ] **Discord popup sizing / no debug text** *(portrait + landscape)* — text is normal-sized and the leftover debug label is gone.

**Sprint 11 fixes (new, 2026-07-22)**
- [ ] **Delivery receipt = deliveries only** — complete a journey that both **delivers** a mission cargo (has a recipient + reward) **and** consumes supplies (fuel/water/food) and/or installs a part. The auto-sell receipt must list **only the delivered mission cargo** (with its recipient + reward), **not** the consumed/used items. *Old:* consumed items showed as `To: Unknown Recipient | Reward: <null>` rows. Check the `[AutoSell]` log line reports the filtered count.
- [ ] **DF+ upsell instead of raw error** — as a **non-DF+** account, try to **buy a warehouse**. *(Steam build)* the `PremiumUpgradeModal` opens (not the "unexpected error" modal); *(iOS/Android/Web)* a **clean "Warehouses require DF+"** message shows (no raw `POST 'warehouse_created'` detail). Confirm **only one** dialog appears (no double-pop from the warehouse menu).

---

# Backlog

Not blocking the sprints above. Pull into a sprint when the relevant file is open.

## Bugs

- **Right-side map panel clips off the screen edge (landscape)** — a settlement-preview / vendor **UI panel** (rows like `S / Wa / Cargo…`, with green category buttons) that floats on the right of the map clips off the **right** screen edge. Distinct from the map-label clipping fixed in Sprint 9 A5 (that was *labels*; this is a screen-space panel). Needs a pinpoint of which panel it is (tap it — vendor vs settlement preview) and then a safe-area / max-width fit. Spotted during the 2026-07-21 device pass.
- **Convoy name label (P5)** — floats unanchored above the panel; integrate as a styled header. `convoy_menu.gd` TitleLabel.
- **Resource-bar text contrast (P6)** — low contrast at high fill; add outline or bump font weight. `convoy_menu.gd` ResourceStatsHBox.
- **HSeparators near-invisible (P8)** — on dark bg, replace with section labels or themed dividers.

## Polish / UX

- **Vendor action buttons live on the selected item** — move all action buttons (buy / sell / etc.) into the selected item's row/inspector in the vendor menu, rather than a separate/global control area. `vendor_trade_panel.gd` / `vendor_item_list.gd`.
- **Global spacing consistency (P9)** — `UITheme.SPACE_*` tokens exist but adoption is incomplete.
- **Settlement vendor browse (map preview)** — full read-only inventory list when viewing a settlement without a convoy. Currently shows name + "deals in" summary only. Follow-up to Sprint 5.5.
- **Convoy stats backend verification** — breakdown modal (`convoy_menu.gd`) shows computed aggregate (min for speed/offroad, average for efficiency) alongside the backend total. Backend formula not yet confirmed — verify on device.

## Tech Debt

- Duplicate Oori palette `const`s in `user_info_display.gd`, `convoy_settlement_menu.gd`, `convoy_list_panel.gd` — migrate to `UITheme.*`.
- Modals use hardcoded absolute center offsets — `auto_sell_receipt_modal`, `returning_player_tips_modal`, `premium_upgrade_modal`; replace with `CenterContainer`.
- `SettingsMenu` opened outside `MenuManager` (CanvasLayer layer=100) — lifecycle inconsistency.
- `UserInfoDisplay` height changes not signaled → stale `offset_top` on submenus.
- `main_screen.gd` wires convoy button via fragile `find_child()`.
- S/M/L UI-scale preference silently overridden in portrait.

## Testing

- **Tutorial-flow smoke coverage** — `Scripts/Debug/wiring_smoke_test.gd` only asserts autoload wiring today. Extend it toward tutorial-flow coverage (step build, resolver resolution per level) so a hub/menu rename can't silently break onboarding. Sprint 8 shipped on a manual portrait/landscape/desktop pass instead.

## Docs / data hygiene

- **Data dumps are stale but intentionally kept — do NOT purge.** Reviewed 2026-07-21: `docs/99_Reference/data_dumps/{cargo,vendor,vehicle,part}_example.json` are point-in-time (Feb 2026, pre-`base_efficiency` rename), but the README already caveats them, they're indexed, and they still document object **shape** correctly. `tutorial_steps.json` is likewise explicitly documented as "shape only." The lightweight improvement, if desired, is to **regenerate** the four stale JSONs from prod (needs `~/Work/desolate_frontiers` + adminer tunnel), not delete them. `dump_3920_convoy_…json` is the only deletion candidate, and only once the vendor-efficiency investigation is fully closed.

## Migration Status (UITheme adoption)

✅ `convoy_menu`, `convoy_vehicle_menu`, `mechanics_menu`, `vendor_trade_panel`, `MenuBase`, `convoy_journey_menu` (navy chrome Sprint 3)
✅ `warehouse_menu`, `warehouse_item_card` (Oori sweep 2026-07-01)
⚠️ `convoy_settlement_menu` (partial) · `settlement_overview_menu` (new — check token use)
❌ `convoy_cargo_menu` (raw colors remain)

---

# Systems Audit & Research Initiative (NEXT MAJOR MOVEMENT)

With the QOL bug-fix program wrapping up, the next major effort is a **full audit and research pass** to
re-baseline the project against its current state — the docs have accreted point-in-time snapshots across
10 sprints and some now lag the code (the project's own "Verify, don't trust" rule exists because of this).

**Goal:** get the docs, data references, and system maps back in sync with what the code actually does
today, and surface the accumulated "old stuff" (dead code, retired flows, stale contracts) for removal.

Scope to define, but the known threads:
- **Doc ⇄ code drift audit** — walk `PROJECT_MAP.md`, `UIAudit.md`, and the `03_Systems/*` deep-dives
  against current code; correct stale `file:line` refs and status claims. Prioritize the docs agents read
  first (onboarding, project map, UI audit).
- **Dead-code / retired-flow sweep** — the tutorial-tab cleanup (Sprint 10) showed how much orphaned
  machinery accumulates; do a systematic pass for other retired paths (legacy settlement menu vs hub,
  old vendor flows, disabled loaders like the tutorial JSON path).
- **Backend / DF_Lib contract re-verification** — regenerate the stale data dumps from prod and confirm
  the binary `/map` wire format (DF_Lib) still matches the backend serializers; the efficiency and
  sold-vehicle sagas both trace to `/map` snapshot lag. See [[reference_backend_repo_and_stale_dumps]]
  and [[reference_vendor_efficiency_binary_serializer]].
- **System inventory** — enumerate the current live systems (menus, services, autoloads) and mark which
  are current, which are transitional, and which are candidates for retirement.

*(This section is a placeholder for the initiative's plan — expand into concrete work items before starting.)*
