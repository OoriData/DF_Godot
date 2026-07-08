This document will serve as a flowing state of things needed in the project, what resources are needed for each task.

> **Status:** Sprints 1–6 complete as of 2026-07-06 (Sprint 6 committed as `54d5493`). Code-verified (compiles clean under warnings-as-errors); the mechanic-apply repair was verified live on-device, but the mobile/visual items (account popup, journey ETA/manifest, map-overlay-during-planning) still want an on-device check. Sprint 7 is the active plan.

---

# Completed Sprint Summary

| Sprint | Theme | Done |
|---|---|---|
| 1 | Quick wins (settings icon, tab counts, cargo sort label, zoom) | ✅ 2026-06-26 |
| 2 | Map camera & overlay (notch, double-scale fix, route fit, close-off-map) | ✅ 2026-06-26 |
| 3 | Baby-blue → Oori token sweep (73 replacements across vehicle/journey/MenuBase) | ✅ 2026-06-26 |
| 4 | Per-menu layout bundles (cargo, mechanics, journey, convoy stats modal, route line) | ✅ 2026-06-29 |
| 5 | Vendor restructure (Top Up → convoy menu, warehouse without convoy, legacy nav cleanup) | ✅ 2026-06-30 |
| 5.5 | Settlement hub pivot (overview hub → single-vendor flow, settings drawer removed, map pin preview) | ✅ 2026-06-30 |
| 6 | Bug fixes — cargo reward, popup fonts, menu-mash guard, **full mechanic-apply repair**, journey ETA/manifest, account popup, map-overlay-during-planning | ✅ 2026-07-06 (`54d5493`) |

Full detail for each sprint is preserved in git history (`54d5493` Sprint 6, `600a06b` Sprint 4, `ec0dcdb` Sprint 3, `5498ad0` Sprint 1&2). Sprint 6's commit message is terse ("bug fixes and Journey QOL"), so the detailed breakdown is kept in the Action Plan below.

---

# Action Plan (Sprints)

### Sprint 6 — Bug fixes (isolated, compile-safe) — ✅ COMPLETE (`54d5493`, 2026-07-06)
Self-contained bug fixes; each file opened once. All items landed, compile-verified, and committed. Detail
kept here because the commit message is terse — note the cart ticket ballooned into a full rebuild of the
mechanic part-install flow.

- ✅ **Cargo delivery reward total** — inspect panel now shows `unit_delivery_reward × quantity` (derived from the per-unit field × aggregated qty, correct across multi-stack aggregation). `convoy_cargo_menu.gd` (2026-07-01).
- ✅ **Modals double-scale fonts (receipt + tips)** — `auto_sell_receipt_modal.gd` and `returning_player_tips_modal.gd` flattened to `return base` (2026-07-01).
- ✅ **Modals double-scale fonts (popups)** — `discord_link_popup.gd` and `account_links_popup.gd` flattened to `return base` (2026-07-01).
- ✅ **Menu button mashing / stuck state** — `menu_manager.gd` now sets `_is_switching` when a switch tween starts and ignores new open/switch requests until it completes (guard at top of `_show_menu`). (2026-07-01).
- ✅ **Hide map overlay during journey planning** — during route preview, `main_screen` hides the overlay panel (`set_planning_active`) and applies a non-persisting marker override in `MapSettingsService` (`set_planning_override`) that reports all marker layers off; `UI_manager` now reads effective settings so settlements/warehouses/other convoy lines suppress, leaving the convoy + previewed route/destination. Restored on preview end/menu close. `main_screen.gd`, `map_overlay_settings_panel.gd`, `map_settings_service.gd`, `UI_manager.gd` (2026-07-06).
- ✅ **Journey ETA shows no date for long trips** — trips over 24h (departure→ETA) now force the arrival date via a new `DateTimeUtil.to_unix_utc` + `omit_date_if_today=false`. `convoy_journey_menu.gd`, `date_time_util.gd` (2026-07-06).
- ✅ **Journey delivery preview shows all cargo** — `_is_for_destination` now guards the empty-string match (an unresolved `dest_name` no longer matches every recipient-less item), so the manifest shows only this stop's deliveries. `convoy_journey_menu.gd` (2026-07-06).
- ✅ **Connected account page fills screen on mobile** — panel sized from the LOGICAL viewport (`get_visible_rect().size`) instead of physical `DisplayServer.window_get_size()`, which was ~2× the viewport on high-DPI and pushed content off-screen. `account_links_popup.gd` (2026-07-06).
- ✅ **Cart slot conflict → FULL mechanic-apply repair** — the cart ticket exposed a completely non-functional part-install flow; the whole path was rebuilt and verified live on-device (parts install, money deducts). `mechanics_menu.gd`, `mechanics_service.gd`, `api_calls.gd` (2026-07-01→07-06):
  - **Cart keying** per (vehicle, slot) — re-picking a slot replaces its pending part; vendor parts may repeat across vehicles (cart totals per vehicle), inventory parts stay single-use (`_is_candidate_in_cart_for_context`).
  - **Apply crash** — Godot's `String()` constructor threw on a non-String `cargo_id`; added `_safe_str` (→`str()`) in `apply_swaps`. (See memory: *Godot String() constructor*.)
  - **Multi-vehicle apply** — `_on_apply_pressed` gathers every carted vehicle's schedule and calls `apply_swaps` with an empty vehicle filter (was only applying the selected vehicle).
  - **Wrong part id (root cause of "nothing installs")** — the compat merge (`_update_row_from_compat_payload`) overwrote the candidate's cargo INSTANCE id with the definition's `cargo_id:null`; now re-asserts `cargo_id = cid` (the server-recognized id). `apply_swaps` also resolves `cargo_id → part_id` fallback.
  - **Routing** — inventory → `attach_vehicle_part` (owned), vendor → `add_vehicle_part` (buy+install); removed the stale `removable` gate.
  - **Non-removable inventory parts hidden** from the swap chooser (`_is_item_non_removable` in `_collect_candidate_parts_for_slot`) — the attach endpoint only accepts removable parts; non-removable ones must be bought from a vendor.
  - **Purchase cost** now uses the vendor `unit_price` (not intrinsic `value`) in `_effective_part_cost_for_entry`; install still uses `value×25% + vehicle_value×10%`.
  - **Empty turbo slot** — `_ensure_slot_row` gated on `_slot_has_swappable_candidate(vehicle, slot)` so vendor stock alone no longer forces incompatible slots (e.g. turbo→ICE) onto every vehicle.
  - **Instant money** — `api_calls._on_request_completed` merges the purchase response's `money` into the store immediately (no wait for the follow-up `/user/get`).

### Sprint 7 — Mobile / landscape polish
All layout work; open each file once. ⚠️ Needs on-device verification for all items.

- [ ] **Login screen status messages too large on mobile** — status/error messages on the login screen are oversized on mobile; scale font down for portrait/mobile. Check for `_get_font_size` boost or hardcoded large font sizes. Login screen script / `Scripts/UI/` login-related file.
- [ ] **Landscape nav buttons fill width** — Nav bar buttons don't fill available horizontal space in landscape. Expand to fill/evenly distribute. `menu_manager.gd` `StaticBottomNav`.
- [ ] **Landscape zoom unlock** — Apply the same `route_fit_allow_zoom_past_cover` bypass in landscape so long routes fit without clipping. `map_camera_controller.gd`.
- [ ] **Warehouse menu mobile layout** — Portrait layout cramped/buggy; landscape one-sided with deadspace. Full layout pass. `warehouse_menu.gd`.
- [ ] **Parts/service cards horizontal scroll in landscape** — Cards don't fit in vertical layout in landscape. Convert to horizontal scroll. `convoy_vehicle_menu.gd` (Parts tab), `mechanics_menu.gd`.
- [ ] **Edge buffer on mobile** — all menus and panels should have a consistent minimum side margin so content never touches the screen edge. Audit portrait and landscape on device; enforce `UITheme.SPACE_LG` (16px) minimum horizontal padding in any menu missing it.
- [ ] **Orientation change reflow** — Switching portrait↔landscape mid-session leaves menus in wrong layout mode until closed/reopened. Trigger layout rebuild on `NOTIFICATION_WM_SIZE_CHANGED` / `get_viewport().size_changed` in affected menus. Confirmed case: `mechanics_menu.gd` parts scroll. Audit all orientation-branched menus.

### Sprint 8 — Tutorial update
Update the tutorial system to match the new UI navigation flow introduced in Sprints 5–5.5.

- [ ] **Audit existing tutorial steps** — Review `res://Data/tutorial_steps.json` for any steps that reference the old settlement flow (multi-vendor list, single settlement screen, Top Up location, vendor selector). Identify all broken node paths and copy. `tutorial_steps.json`, `Scripts/UI/tutorial_manager.gd`.
- [ ] **Update settlement hub tutorial steps** — Rewrite/add steps that walk the player through: Settlement nav → hub overview → vendor card tap → single-vendor trade → "‹ Settlement" back. Update target node paths in `target_resolver.gd` patterns as needed.
- [ ] **Update Top Up tutorial step** — Top Up moved from settlement menu to the convoy overview `TopBarHBox`. Update the step target and instructional copy.
- [ ] **Map pin tutorial** — Add or update the step that teaches pinning a settlement label and tapping the `›` chevron to open the overview. The old "tap settlement on map" behavior has changed.
- [ ] **Smoke-test full tutorial flow** — Run `wiring_smoke_test.gd` and do a manual pass through the entire tutorial on device. Verify the highlight overlay hits the correct nodes at each step.

### Sprint 9 — Map & misc polish
- [ ] **Settlement labels tap-only (mobile)** — Labels currently fire on pan gestures. Guard behind `OS.has_feature("mobile")`; show only on explicit `InputEventScreenTouch`, not `InputEventMouseMotion`. Desktop retains hover. Settlement label script / `map_interaction_manager.gd`.
- [ ] **Map overlay notch clearance** — Gear tab and expanded overlay should always clear the Dynamic Island / notch safe area on all devices, not just when `safe.position.y > 0`. When a menu panel sits under the notch, add a breathing gap between the notch floor and menu content. `map_overlay_settings_panel.gd` `_build_ui` / `_update_layout`.
- [ ] **Mechanics compatibility preloading** — Pre-fetch compatibility data for all convoy vehicles when the mechanics menu opens; show "N upgrades available" per vehicle card before the user taps in. Requires the cart to handle multi-vehicle, multi-upgrade state. `mechanics_menu.gd`, cart system.

---

# Code Map (active tasks)

Sprint 6 rows removed — all complete (see the Sprint 6 section above). Remaining rows are Sprint 7+.

| Task | Primary file:line | Notes |
|---|---|---|
| Landscape nav fill | `menu_manager.gd` `StaticBottomNav` | `SIZE_EXPAND_FILL` on buttons |
| Landscape zoom unlock | `map_camera_controller.gd` | Match portrait `route_fit_allow_zoom_past_cover` |
| Warehouse mobile layout | `warehouse_menu.gd` | Portrait + landscape pass |
| Parts horizontal scroll | `convoy_vehicle_menu.gd` Parts tab, `mechanics_menu.gd` | `HBoxContainer` + outer `PartsScroll` |
| Orientation reflow | `mechanics_menu.gd` (confirmed), audit others | `NOTIFICATION_WM_SIZE_CHANGED` handler |
| Tutorial — settlement flow | `res://Data/tutorial_steps.json`, `tutorial_manager.gd` | Hub → vendor → back flow |
| Tutorial — Top Up | `tutorial_steps.json` | Target moved to convoy overview `TopBarHBox` |
| Tutorial — map pin | `tutorial_steps.json` | Pinned label `›` chevron as the affordance |
| Settlement labels mobile | settlement label script, `map_interaction_manager.gd` | Touch-only on mobile |
| Map overlay notch | `map_overlay_settings_panel.gd` | All-devices clearance + menu breathing gap |
| Mechanics compat preload | `mechanics_menu.gd`, cart system | Multi-vehicle, multi-upgrade cart |

---

# Backlog

Not blocking the sprints above. Pull into a sprint when the relevant file is open.

## Bugs

- **Convoy name label (P5)** — floats unanchored above the panel; integrate as a styled header. `convoy_menu.gd` TitleLabel.
- **Resource-bar text contrast (P6)** — low contrast at high fill; add outline or bump font weight. `convoy_menu.gd` ResourceStatsHBox.
- **HSeparators near-invisible (P8)** — on dark bg, replace with section labels or themed dividers.
- **`discord_popup.gd` font double-scale** — the `DiscordPopup` PopupPanel (loaded by `user_info_display.gd:445`; distinct from the already-migrated `discord_link_popup.gd`) still boosts in `_get_font_size` (`int(effective_base * boost)`). Flatten to `return base` like the other popups. Found 2026-07-06 while auditing the font migration.

## Polish / UX

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

## Migration Status (UITheme adoption)

✅ `convoy_menu`, `convoy_vehicle_menu`, `mechanics_menu`, `vendor_trade_panel`, `MenuBase`, `convoy_journey_menu` (navy chrome Sprint 3)
✅ `warehouse_menu`, `warehouse_item_card` (Oori sweep 2026-07-01)
⚠️ `convoy_settlement_menu` (partial) · `settlement_overview_menu` (new — check token use)
❌ `convoy_cargo_menu` (raw colors remain)
