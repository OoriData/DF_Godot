This document will serve as a flowing state of things needed in the project, what resources are needed for each task.

> **Status:** Sprints 1–5.5 complete as of 2026-06-30. Code Map below reflects post-sprint state. Sprint 6 is the active plan.

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

Full detail for each sprint is preserved in git history (`600a06b` Sprint 4, `ec0dcdb` Sprint 3, `5498ad0` Sprint 1&2).

---

# Action Plan (Sprints)

### Sprint 6 — Bug fixes (isolated, compile-safe)
Self-contained bug fixes; each file opened once. Ship immediately after verification.

- ✅ **Cargo delivery reward total** — inspect panel now shows `unit_delivery_reward × quantity` (derived from the per-unit field × aggregated qty, correct across multi-stack aggregation). `convoy_cargo_menu.gd` (2026-07-01).
- ✅ **Modals double-scale fonts (receipt + tips)** — `auto_sell_receipt_modal.gd` and `returning_player_tips_modal.gd` flattened to `return base` (2026-07-01).
- ✅ **Modals double-scale fonts (popups)** — `discord_link_popup.gd` and `account_links_popup.gd` flattened to `return base` (2026-07-01).
- ✅ **Menu button mashing / stuck state** — `menu_manager.gd` now sets `_is_switching` when a switch tween starts and ignores new open/switch requests until it completes (guard at top of `_show_menu`). (2026-07-01).
- ✅ **Hide map overlay during journey planning** — during route preview, `main_screen` hides the overlay panel (`set_planning_active`) and applies a non-persisting marker override in `MapSettingsService` (`set_planning_override`) that reports all marker layers off; `UI_manager` now reads effective settings so settlements/warehouses/other convoy lines suppress, leaving the convoy + previewed route/destination. Restored on preview end/menu close. `main_screen.gd`, `map_overlay_settings_panel.gd`, `map_settings_service.gd`, `UI_manager.gd` (2026-07-06).
- ✅ **Journey ETA shows no date for long trips** — trips over 24h (departure→ETA) now force the arrival date via a new `DateTimeUtil.to_unix_utc` + `omit_date_if_today=false`. `convoy_journey_menu.gd`, `date_time_util.gd` (2026-07-06).
- ✅ **Journey delivery preview shows all cargo** — `_is_for_destination` now guards the empty-string match (an unresolved `dest_name` no longer matches every recipient-less item), so the manifest shows only this stop's deliveries. `convoy_journey_menu.gd` (2026-07-06).
- ✅ **Connected account page fills screen on mobile** — panel sized from the LOGICAL viewport (`get_visible_rect().size`) instead of physical `DisplayServer.window_get_size()`, which was ~2× the viewport on high-DPI and pushed content off-screen. `account_links_popup.gd` (2026-07-06).
- ✅ **Cart slot conflict on part install** — cart is now keyed per (vehicle, slot): re-picking a filled slot on a vehicle replaces its pending part. Vendor parts may repeat across vehicles (cart totals per vehicle); inventory parts stay single-use. `mechanics_menu.gd` (2026-07-01).

### Sprint 7 — Mobile / landscape polish
All layout work; open each file once. ⚠️ Needs on-device verification for all items.

- [ ] **Landscape nav buttons fill width** — Nav bar buttons don't fill available horizontal space in landscape. Expand to fill/evenly distribute. `menu_manager.gd` `StaticBottomNav`.
- [ ] **Landscape zoom unlock** — Apply the same `route_fit_allow_zoom_past_cover` bypass in landscape so long routes fit without clipping. `map_camera_controller.gd`.
- [ ] **Warehouse menu mobile layout** — Portrait layout cramped/buggy; landscape one-sided with deadspace. Full layout pass. `warehouse_menu.gd`.
- [ ] **Parts/service cards horizontal scroll in landscape** — Cards don't fit in vertical layout in landscape. Convert to horizontal scroll. `convoy_vehicle_menu.gd` (Parts tab), `mechanics_menu.gd`.
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

| Task | Primary file:line | Notes |
|---|---|---|
| Cargo delivery reward total | `convoy_cargo_menu.gd` | `unit_delivery × quantity`; display only |
| Modal font double-scale | `discord_link_popup.gd`, `account_links_popup.gd` | Flatten `_get_font_size → return base`; receipt + tips ✅ done |
| Menu mashing guard | `menu_manager.gd` `_start_menu_switch_animation` | Ignore input while tween running |
| Cart slot conflict | `mechanics_menu.gd` / cart system | Swap or prompt |
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
