---
type: note
tags:
  - codex/history
aliases:
  - "Sprint History"
  - "Completed Sprint Detail"
created: 2026-07-22
---

# Sprint History — Completed Work Archive

This document preserves the **detailed, root-cause-level narrative** for completed sprints and
closed backlog items. It was split out of [TODO.md](TODO.md) on 2026-07-22 so the TODO can stay
lean and forward-looking — the TODO keeps only the compact summary table plus active/pending work.

> **Why this exists:** several commit messages are terse (Sprint 6 = "bug fixes and Journey QOL";
> the misc-QOL passes `b5f591c`/`4c70729`), so the *reasoning* behind a fix — the real root cause,
> which was often external to the obvious file — would be lost if it lived only in the diff. Read
> this when a "fixed" behavior regresses and you need to know how it was fixed the first time.

Full per-sprint git anchors: `725c42f`/`511d2d5` (Sprint 8), `2dc42bf`/`fe10261` (Sprint 7),
`54d5493` (Sprint 6), `600a06b` (Sprint 4), `ec0dcdb` (Sprint 3), `5498ad0` (Sprints 1–2),
`b5f591c`/`4c70729` (Sprint 9/10 misc-QOL passes).

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
| 7 | Mobile/landscape polish — orientation reflow, edge buffer, landscape nav fill, **warehouse portrait rebuild** (+ top-bar overflow root cause), parts scroll, login-screen status font | ✅ 2026-07-10 (`fe10261`/`2dc42bf`), device-verified |
| 8 | Tutorial re-fit to settlement-hub UI — L1/L2/L4 reworked to the hub → vendor-card → single-vendor flow, L5 verified, content-identity resolvers, 10 rounds of device-feedback polish, flashing-panel fix | ✅ 2026-07-16 (`725c42f`/`511d2d5`), device-verified stable |
| 9 | Map & misc polish + vendor/mechanics polish (labels, route, vendor stats, mechanics `[N ↑]` counts, eager compat prefetch) | ✅ code-complete 2026-07-21 |
| 10 | Closeout QOL — discord popup flatten, dead tutorial-tab removal, Cancel-Journey persistence, sold-out vendor filter | ✅ code-complete 2026-07-22 |

---

# Action Plan (Sprints) — full detail

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

### Sprint 7 — Mobile / landscape polish — ✅ COMPLETE (`fe10261`/`2dc42bf`, 2026-07-10, device-verified)
All layout work, verified live on iOS. Detail kept here because the big warehouse item's real root cause
(the top bar, not the warehouse) is not obvious from the diff.

- ✅ **Login screen status messages too large on mobile** — `login_screen.gd::_apply_portrait_layout` derived the `StatusLabel` font from a **52px base × `scale_f`** (≈2.07 → ~108px), 3× the 16px button base and nearly screen-filling. Dropped to a **22px base** (proportionate — slightly larger than the buttons) and the min-height from 96→48. `login_screen.gd`.
- ✅ **Orientation change reflow** — the 5 orientation-branched menus that didn't already handle it now subscribe to `DeviceStateManager.layout_mode_changed` and rebuild in place: `convoy_vehicle_menu`, `mechanics_menu`, `settlement_overview_menu`, `convoy_menu`, `convoy_cargo_menu`. Root cause was that they read orientation only at build time. This also exposed two latent `vendor_trade_panel` crashes on rotation, both fixed: `initialize()` now `await ready` (its `@onready` trees were null when the settlement menu rebuilt tabs while detached), and `_populate_vendor_list`/`_populate_convoy_list` guard their trees before `clear_items()`.
- ✅ **Edge buffer on mobile** — `MenuBase._apply_standard_margins()` now enforces `UITheme.SPACE_LG` (16px) minimum **horizontal** padding in **both** orientations (was 14px portrait / 0 landscape). Vertical insets left exactly as before (portrait 14px, landscape 0) so it only affects side margins and never reduces sheet height.
- ✅ **Landscape nav buttons fill width** — root cause was the safe-area inset: `_update_static_nav_bar_ui` applied the screen's horizontal notch margin to the nav bar even in landscape, where the menu is a side panel nowhere near the notch — squeezing the four (already `SIZE_EXPAND_FILL`) buttons to the centre. The horizontal safe inset now applies in **portrait only**; landscape uses `bar_margin` so the buttons fill the panel. `menu_manager.gd`.
- ✅ **Landscape zoom unlock** — **no code change needed.** `route_fit_allow_zoom_past_cover` is already a global `@export` set `true`, and `smooth_fit_world_rect` honours it in both orientations (the only orientation branch, `portrait_extra_zoom_out`, only relaxes the *manual* zoom floor and defaults to off). The literal task was already satisfied; verified on device. `map_camera_controller.gd` unchanged.
- ✅ **Parts/service cards horizontal scroll in landscape** — was already implemented (outer `PartsScroll` switches to horizontal); it just never re-ran on rotation. Fixed by the reflow item above.
- ✅ **Warehouse menu mobile layout** — full portrait rebuild + landscape deadspace fix. **The real root cause of the "cramps and clips off both edges" was external to the warehouse:** the top bar (`user_info_display.gd`) at font 26 summed to a ~833px min-width, forcing `SafeRegionContainer` — and every menu under it — 33px past the 800px portrait viewport. Fixed there (fonts 26→20, edge paddings halved to 8px). Warehouse-side changes: portrait is a full-width **bottom sheet** so action rows stay on one horizontal line (not stacked); controls shrunk 120→72px; buttons 280×130→140×72; dropdowns set `fit_to_longest_item = false` + `clip_text` (they were growing to their longest cargo name once populated); long labels autowrap; quantity widget buttons 90→64px (`quantity_widget.gd`); tab bar 100→60px. Landscape: `LeftPanel`/`RightColumn` now `SIZE_EXPAND_FILL` with 1:2 stretch ratios to kill the deadspace. `warehouse_menu.gd`, `user_info_display.gd`, `quantity_widget.gd`.
  - **Debugging lesson captured in [AI_ONBOARDING.md](AI_ONBOARDING.md)** — the multi-session hunt (chased warehouse width, then height, before finding the top bar) produced a "Debugging a Visual/Layout Bug" protocol: pinpoint the element+axis first, reproduce in the editor (device builds are frozen snapshots — re-export + redeploy, and a canary needs a build stamp), measure only after slide animations settle, and rule out structure (stray back button, missing `ScrollContainer`) before tuning numbers.

### Sprint 8 — Tutorial update — ✅ COMPLETE (`725c42f`/`511d2d5`, 2026-07-16, device-verified stable)
Re-fit the tutorial's per-step highlights and inter-step flow to the Sprint 5–5.5 settlement-**hub** UI.
**Preserve the checkpoint skeleton** — the server `metadata.tutorial` stages (L1 buy vehicle → L2
supplies+topup → L4 delivery → L5 journey → L6/L7 messages) do **not** change; only the *intra-level*
steps (highlights + the flow between them) get re-fit.

**Where the steps actually live:** hardcoded in `tutorial_manager.gd::_build_level_steps()` — **NOT** a
JSON file. The docs' `res://Data/tutorial_steps.json` doesn't exist and the JSON loader is disabled at
`tutorial_manager.gd:1851` (it drifted out of sync and ran wrong steps). **Decision:** keep steps in
GDScript for this sprint and correct the docs to match; a JSON migration is a separate, later task
(it would only externalize `copy`/`target` — each `action` still needs bespoke watcher code).

**Desktop ⇄ mobile parity is a first-class requirement.** The hub reflows hard between portrait (2-col
card grid, stacked resources/warehouse) and landscape/desktop (N-col grid, side-by-side) —
`settlement_overview_menu.gd:210/509`. Every new highlight resolves by **content identity** (vendor
name label, button text), never a fixed rect/index, and re-resolves on `layout_mode_changed` rebuilds.

Tutorial-city vendor card labels (match by substring): `Tutorial City Dealership`,
`Tutorial City Market`, `Tutorial City Gas Station`.

**Status (final, 2026-07-16):** ✅ All levels (L1, L2, L4, L5) reworked/verified and playing end-to-end on
device in portrait, landscape, and desktop. Ten rounds of device-feedback polish landed (rounds 1–10 below).
Compile-clean (standard + warnings-as-errors).

- [x] **L1 — settlement entry + vendor card (softlock fix)** — `await_settlement_hub` (waits for
  `menu_opened("settlement_hub")`) + `await_vendor_open` (waits for `menu_opened("convoy_settlement_submenu")`),
  new `settlement_hub_vendor_card` resolver matching the card by `vendor_name` meta (hub tags cards +
  `get_vendor_card_node_by_name_contains()`). Device-verified through buy. `tutorial_manager.gd`,
  `target_resolver.gd`, `settlement_overview_menu.gd`.
- [x] **Retarget Top Up** — resolver + `_watch_for_top_up` now prefer the hub's resources-card Top Up button
  (tagged `is_top_up_button`, exposed via `get_top_up_button_node()`); legacy settlement-menu path kept as
  fallback. Already-full guard handles the hub's "Topped Up" label.
- [x] **L2 — hub flow, both supply beats kept** — back to hub → tap Market card → buy 2 MRE + 2 Water → back
  to hub → Top Up.
- [x] **L4 — first delivery, hub flow** — reworked: (user is in the hub after the L2 top-up) tap Market card →
  buy Mountain Urchins → **straight to the Journey menu** (round 3: dropped the L4 top-up / return-to-settlement
  steps; resources were filled in L2 and `l5_open_journey_menu` forces stage 6 → warp).
- [x] **L5 — journey (verify only)** — verified on device; the warp race (convoy at 0,0 → `l5_pick_destination`
  suspends) resolves cleanly and the route confirms. Camera-focus stale-snapshot fix (round 9) also covers this.
- [x] **Docs** — corrected the "steps are JSON" claim in `TutorialSystemOverview.md` (with a follow-up doc-sync
  pass 2026-07-16 fixing the residual JSON framing in the mermaid diagram, `StepSchema.md`, and `Controllers.md`).

**Device-feedback polish (round 1) — 2026-07-10:**
- [x] **Highlight fired before the card settled** — `settlement_hub_vendor_card` resolver waits until the card's
  rect is stable across two frames before measuring (`target_resolver.gd`), so it no longer flashes at the
  card's pre-slide position.
- [x] **First-convoy modal fit + keyboard** — `NewConvoyDialog` was a fixed 1000×480 panel; now sizes to the
  viewport, wraps the title, compacts fonts/heights in landscape, and is top-anchored. (Refined in round 2.)
- [~] **Tutorial text overlapped the menu** — first attempt capped the panel + scrolled; reverted in round 2
  because scrolling was unwanted.

**Device-feedback polish (round 2, from L1/L2 pass) — 2026-07-10:**
- [x] **Modal hidden behind the top bar** — round-1 top-anchor tucked the card under the top bar.
  `_update_new_convoy_dialog_layout` now offsets it below the top bar's bottom edge (measured relative to the
  dialog's parent), so the title is fully visible while staying clear of the keyboard.
- [x] **No more scrolling in the tutorial text box** — reverted the ScrollContainer/height-cap in
  `tutorial_overlay.gd`; the panel sizes to content (no scroll), stays width-bounded and below the top bar, and
  the landscape side-menu right-inset is kept. Per-step copy must stay short enough to fit the map strip.
- [x] **Back-to-hub uses the vendor menu's top-left button** — the L2 "return to settlement" steps use the
  `convoy_return_button` resolver → `back_requested` → `go_back()` reopens the hub and re-emits
  `menu_opened("settlement_hub")`, instead of pressing the Settlement nav twice. (Resolver target corrected in
  round 3.)

**Device-feedback polish (round 3, from L1–L4 pass) — 2026-07-10:**
- [x] **Back button wasn't highlighting** — the real top-left back control is a `PanelContainer` named
  `BackToSettlementButton` ("‹ <settlement> / <vendor>") mounted *inside the vendor panel's control row*, not
  `MainVBox/TopBarHBox/TitleLabel`. `_resolve_convoy_return_button` now finds `BackToSettlementButton` first
  (`target_resolver.gd`). It doesn't read as a button, so highlighting it is what makes the back path findable.
- [x] **Top Up highlight blended in** — the hub Top Up button was brass (gold), the same as the gold highlight.
  Recolored to `UITheme.STATUS_GOOD` (green) in `settlement_overview_menu.gd::_make_top_up_button`.
- [x] **After urchins: go to Journey, not Settlement** — L4 now ends at the urchin purchase and L5 sends the
  player straight to the Journey menu. *The "vendor menu blanks after purchase" bug is root-caused and fixed —
  see round 5 (it was a vendor-tree crash, not a `convoy_settlement_menu` issue).*
- [x] **Confirm Journey wasn't clickable** — the highlight hole excluded the dynamically-built Confirm button,
  and the shield blocked the tap. `l5_embark` is now ungated (`lock = "none"`, no target); the whole screen is
  interactive and the watcher still advances on journey start. Added an empty-target guard in
  `_resolve_and_highlight` so ungated steps don't spin the resolver retry loop.

**Device-feedback polish (round 4, from L1–L2 landscape pass) — 2026-07-10:**
- [x] **Text box overlapped the vendor menu (landscape)** — two root causes: (1) the inset heuristic missed a
  side menu whose left edge sat below the 40% threshold; (2) the message `RichTextLabel` has `fit_content = true`,
  so it sized to the **unwrapped** text width and forced the panel wider than any width cap. `tutorial_overlay.gd::_relayout_panel`
  now clamps the panel's right edge directly against the live `MenuContainer` rect (no threshold, 16px gap);
  **bounds the label's `custom_minimum_size.x`** so it wraps to the panel width; drops the VBox's 380px min width;
  and uses a smaller landscape left margin so the panel uses the empty strip left of the map.
- [x] **Supply step "not updating" — kept the strict Water-Jerry-Cans match** — the vendor stocks BOTH plain
  `Jerry Cans` (fuel) and `Water Jerry Cans` (water); the water total must require **both** `water` AND `jerry`
  (never bare `jerry`). See [[reference_jerry_cans_vs_water]]. Added `[Tutorial][DIAG] supply cargo item=…`
  logging in `_on_supply_check`.

**Device-feedback polish (round 5) — 2026-07-10:**
- [x] **Vendor menu crashed/blanked after a purchase** — root cause: `VendorTreeBuilder.make_display_agg_with_parts_rebucket`
  pre-seeded a `"missions"` bucket, but the aggregator (`cargo_aggregator.gd`) emits delivery cargo under `"delivery"`
  (stale rename). Copying agg's `"delivery"` bucket into a display_agg that lacked it threw *"Invalid access to key
  'delivery'"* (`tree_builder.gd:52`) during the post-purchase tree rebuild → blank menu. Fix: pre-seed `"delivery"`
  + defensively create any missing bucket during the copy (`tree_builder.gd`); and the caller's category map now keys
  on `"delivery"` (`vendor_trade_panel.gd::_populate_list_from_agg`) so **Delivery Cargo (e.g. Mountain Urchins) also
  renders**. `"missions"` kept as a legacy title alias.
- [x] **Crash re-entering the Market vendor** — `vendor_item_list.gd::_ensure_row_visible` did `await
  get_tree().process_frame`, but on re-entry `populate` re-selects the previous row while the list is still
  **detached from the tree**, so `get_tree()` was null. Now guards `get_tree()` and skips the scroll-into-view
  when detached.

**Device-feedback polish (round 6) — 2026-07-10:**
- [x] **Confirm Journey still un-tappable (round-3 fix incomplete)** — `lock = "none"` hid the shield ring, but
  the overlay **Control itself** kept `mouse_filter = STOP`: `tutorial_overlay.gd::clear_highlight` set STOP for
  any non-SOFT gating, so the ungated full-screen overlay silently ate the tap. Now only **HARD** blocks; NONE
  (ungated) and SOFT (hole) pass input through.
- [x] **Vendor disappears after buying Mountain Urchins** — a `map_changed` right after a mission-item purchase
  ran `_display_settlement_info`, which `_clear_tabs()` then rebuilt nothing when the fresh snapshot momentarily
  lacked the vendor → blank. Added a single-vendor guard (`convoy_settlement_menu.gd`): if a tab is already shown
  and the incoming snapshot doesn't contain `_single_vendor_id`, skip the destructive rebuild and keep the tab.

**Device-feedback polish (round 7) — 2026-07-10:**
- [x] **Convoy journey route line not showing on selection** — the route LINE and the delivery-destination
  ARCS were both gated by the same `active_delivery_destinations` ("Delivery Targets") toggle, which defaults
  off. Per design intent, decoupled them: the focused/selected convoy's **journey line always draws** now
  (`UI_manager.gd::_on_connector_lines_container_draw`); the **"Delivery Targets" toggle now only gates the
  curved destination arcs/markers**.

**Device-feedback polish (round 8, restart softlock) — 2026-07-14:**
- [x] **Softlock when resuming a level from the map root** — the tutorial always resumes at `_step = 0`
  (`tutorial_manager.gd::_maybe_start` forces it), but several levels' first step assumed the player was
  already deep in a menu. On a fresh restart the game reopens at the map root with **no menu**, so the
  shared bottom nav bar doesn't exist. Fix: a **resume anchor** (`await_convoy_menu` action) prepended to L2
  and L5. It auto-advances with no prompt when a convoy submenu is already active, and on a restart highlights
  the always-present **convoy dropdown** and waits for any convoy menu to open. See
  [[reference_tutorial_resume_step_zero]].

**Device-feedback polish (round 9, camera focuses old convoy spot) — 2026-07-14:**
- [x] **Camera pans to the pre-warp location on tutorial exit** — the camera focuses on the convoy using
  `_last_focused_convoy_data`, a snapshot captured at **menu-open**. During L5 the backend warps the convoy from
  (0,0) to its start city, so that snapshot's `x`/`y` are stale. Fix: new
  `main_screen.gd::_refresh_convoy_data_from_store()` re-resolves the convoy by `convoy_id` from GameStore (live
  coords) right before every camera-focus call. See [[reference_convoy_focus_stale_snapshot]].

**Device-feedback polish (round 10, flashing panel) — 2026-07-16 (`511d2d5`), device-verified:**
- [x] **Tutorial text box flashed to near-full-screen for one frame** — two root causes in `tutorial_overlay.gd`:
  (1) `_update_checklist` recreated **autowrapping** `Label`s each update; a fresh autowrap label shapes at width 0
  for one frame → reports a wrapped-at-zero-width min HEIGHT of hundreds of px. Fixed by making checklist rows
  **single-line + ellipsis**. (2) In portrait, `_relayout_panel` clamped the panel's right edge to the menu's left
  edge, but portrait menus are full-width **bottom sheets** that slide in **horizontally**. Fixed by skipping the
  menu-edge clamp in portrait. See [[reference_tutorial_overlay_panel_positioning]].

> **Dropped from Sprint 8 scope:** the map-pin teaching step. The tutorial keeps its current entry flow (convoy
> dropdown → Settlement nav); it does not teach map-label pinning.

### Sprint 9 — Map & misc polish + vendor/mechanics polish — ✅ CODE-COMPLETE 2026-07-21

**Batch A — map / route polish**
- [x] **A1 · Settlement labels tap-only (mobile)** — gated the three `_update_hover()` calls in
  `_handle_touch_input` so pan-drag no longer flashes labels under the finger; on touch, labels reveal
  only via an explicit tap. `map_interaction_manager.gd`.
- [~] **A2 · Map overlay notch clearance** — **deferred, not reproduced.** Panel already applies safe-area
  insets on both axes, ungated. Revisit only with a concrete device repro. `map_overlay_settings_panel.gd`.
- [x] **A3 · Vendor cards clip below nav (mobile-landscape hub)** — hub is no-scroll by design, so fixed by
  fit-to-height: pack ≤4 vendors into one row + shorter cards, mobile-landscape only. `settlement_overview_menu.gd`.
- [x] **A4 · Map labels occlude route line** — extended the existing anti-collision loop to nudge settlement
  labels off the active preview route (`_settlement_panel_overlaps_route` + a segment-vs-AABB test), plus a
  route-fit top-headroom knob (`route_fit_label_top_extra_px`). `UI_manager.gd`, `map_camera_controller.gd`.
  Known limit: nudge is vertical-only.
- [x] **A5 · Map labels clip the side edges / hide behind the gear box** — ✅ **DONE + device-verified (2026-07-21).**
  Applied to **all** map labels (convoy **and** settlement). Root cause: clamping was intentionally disabled for
  **both** systems (`convoy_label_manager` line ~776 and `UI_manager` line ~465, "let panels pan off-screen
  naturally"). **Unified fix:** `UI_manager._get_label_safe_screen_rect()` = the map rect with its **left edge
  pushed past the gear box's live screen right edge** (`get_tab_global_rect()` on the cached
  `MapOverlaySettingsPanel`). Both label systems clamp X to it **only when the anchor (convoy icon / settlement
  tile) is on-screen**: convoy via `_clamp_label_within_bounds_if_convoy_visible()`, settlement via new
  `_clamp_settlement_panel_x()` in `_position_settlement_panel`. **Fluid re-clamp:** `UI_manager._process()`
  re-runs the label redraw while the **camera pans** (detected via `terrain_tilemap.get_global_transform_with_canvas()`
  changing frame-to-frame), so labels track smoothly instead of snapping. Landed on `main` 2026-07-22 (`4c70729`).
  *(Two earlier per-element attempts, mis-modeling this as a gear-tab occlusion, were reverted — see git history.)*

**Batch B — vendor / mechanics polish**
- [x] **Vehicle stats in vendor menu** — list rows now fall back to `base_*` keys (vendor payloads null the
  plain `top_speed`/`cargo_capacity`/… keys). `vendor_item_list.gd`. *Device round 1: PASS.*
- [x] **Vehicle inspector parity + description popup** — vendor vehicle inspector now matches the convoy summary
  page (Seats / Make-Model / Color / Shape shown when present) plus a Description popup button, across desktop,
  mobile-landscape, and portrait. `inspector_builder.gd`, `vendor_trade_panel.gd`, `vendor_item_list.gd`.
- [x] **Mechanics dropdown — upgrade count per vehicle** — vehicle selector shows `[N ↑]` = slots with a
  compatible upgrade available (convoy cargo + vendor stock). Because Mechanics runs **embedded** in the convoy
  vehicle menu (which hides Mechanics' own dropdown), the count is propagated to the **parent** menu's dropdown:
  `mechanics_menu` exposes `get_upgrade_count_for_vehicle_id()` + emits `upgrade_counts_changed`;
  `convoy_vehicle_menu` decorates ITS labels and refreshes in place. The swap-button **glow** (a no-op by design
  in `_style_swap_button`) was restored — green (`UITheme.STATUS_GOOD`) on Swap buttons whose slot has an upgrade.
  `mechanics_menu.gd`, `convoy_vehicle_menu.gd`. (Docs: `03_Systems/Mechanics.md`.)
- [x] **Available Parts preview — compatible vehicles** — each part lists which convoy vehicles can use it, with a
  **green highlight + "Fits:" line** for parts that fit ≥1 vehicle, sorted most-compatible first. `convoy_menu.gd`.
  Device-confirmed. (Docs: `02_UI_UX/ConvoyMenu.md`.)
- [x] **Mechanics compatibility preloading** — **code-complete (2026-07-21).** Eager all-vehicle compat pre-fetch
  on open: `_start_vendor_compat_checks_for_all_vehicles()` warms the backend `_compat_cache` for every
  *non-selected* vehicle so the dropdown `[N ↑]` counts firm up on open. Dispatch is **staggered** (one vehicle per
  0.12s tick, guarded by a cancel token) because the compat API creates a fresh HTTPRequest per call with no
  in-flight dedup. Wired into `_update_ui`, `_on_hub_convoy_updated`, `_on_hub_vendor_updated`; cancelled in
  `reset_view()`. The multi-vehicle/multi-upgrade cart already existed (Sprint 6 rebuild). `mechanics_menu.gd`.

**Blocked externally (now resolved):**
- [x] **Vendor efficiency = 0** — ✅ **RESOLVED on device (2026-07-21).** Vendor vehicle stats now show real
  efficiency — the `/map` payload deploy landed. See the
  [DF_Lib case study](04_Technical/DF_Lib.md#case-study-the-vanishing-vehicle-efficiency-stat) and memory
  [[reference_vendor_efficiency_binary_serializer]].

### Sprint 10 — Closeout QOL — ✅ CODE-COMPLETE 2026-07-22

- [x] **`discord_popup.gd` font double-scale** — `_get_font_size` flattened to `return base`
  (`Scripts/UI/discord_popup.gd`), the last holdout of the font-scale migration. Also removed a leftover visible
  `_debug_lbl` (viewport/size diagnostic) + `| LOUD LOG` console prints. Closes [[project_font_scale_migration]].
- [x] **Dead tutorial tab handlers** — removed the `await_dealership_tab`/`await_market_tab` match arms, their two
  entries in `lock_tabs_for_actions`, and `_hint_dealership_tab` (`tutorial_manager.gd`). Kept
  `_lock_vendor_tabs`/`_on_vendor_tab_selected` (still live for `await_vehicle_purchase`/`await_supply_purchase`/
  `await_urchin_purchase`) and the `VendorTabContainer`. See [[reference_tutorial_steps_in_code]].
- [x] **(Follow-up) Second-layer tutorial-tab orphans** — removed the now-dead
  `tutorial_manager.gd::_watch_for_tab_selected` + `_check_for_tab_selected_poll`, the `_is_polling_for_tab`
  polling branch in `_process` (the whole `_process` override went), its resets in `_advance`/`_exit_tree`, the
  polling state members, and `convoy_settlement_menu.gd::get_vendor_tab_rect_by_title_contains`. Compile-clean.
- [x] **Cancel Journey button always present** (`b5f591c`) — with a convoy in transit, the Cancel Journey button
  shows and works even if the convoy snapshot omits `journey_id` (id resolved dict → GameStore at click).
  `convoy_journey_menu.gd`.
- [x] **Sold-out vendor items linger in the list** — **FIXED in three parts (2026-07-22).** The post-transaction
  authoritative refresh already fires (`vendor_panel_refresh_controller.gd::on_api_transaction_result` →
  `request_vendor_panel`).
  - **Cargo / resources** — `VendorItemList.add_category` now skips entries with `total_quantity ≤ 0` (the
    optimistic post-purchase decrement lands the bought item at qty 0, but nothing dropped the zero row). Filters
    *rendering* only. `vendor_item_list.gd`.
  - **Vehicles** — new `vendor_trade_panel._optimistically_remove_vendor_vehicle(vehicle_id)` drops a bought
    vehicle from the cached `"vehicles"` bucket **and** `vendor_data.vehicle_inventory` by id (they're keyed by
    `vehicle_id`, not name, so the name-based optimistic decrement never matched). `vendor_trade_panel.gd`.
  - **Vehicle reappears ~1s after removal** — the vehicle list is sourced from the **lagging binary `/map`
    settlements snapshot** (same source as the efficiency saga); a full re-aggregation right after the buy
    resurrected it. **Fix:** `vendor_trade_panel._sold_vehicle_ids` (a per-panel-session set) records each bought
    vehicle_id and `_strip_sold_vehicles()` re-drops those ids on **every** `_populate_vendor_list` rebuild.
    `vendor_trade_panel.gd`.
  - ⚠️ **Still upstream:** the `/map` snapshot genuinely lagging is the root data problem (the client guard only
    masks it for the current session). The durable fix is the same `/map`-deploy path as the efficiency stat.

---

# Device-test round 1 — 2026-07-21 (iPhone, remote deploy) — results

Kept for provenance. The **round 2** checklist (the live gate) stays in [TODO.md](TODO.md).

- ✅ **Vendor vehicle stats incl. efficiency** — real numbers show (efficiency blocker resolved).
- ✅ **Tutorial tab-lock** — holds; purchases advance. Dead-arm removal safe.
- ✅ **Mechanics eager prefetch (staggering)** — logs confirm one-vehicle-at-a-time `[PartCompatUI] Dispatching`
  bursts (no flood).
- 🔧 **`[N ↑]` count + swap glow not visible → FIXED** — root cause: Mechanics runs **embedded** in the convoy
  vehicle menu, hiding its own counted dropdown; the parent's dropdown never got the prefix. Now propagated to
  the parent + the swap-button glow restored. (See Sprint 9 Batch B.)
- 🔧 **Discord popup logs → FIXED** — removed the leftover visible `_debug_lbl` + `| LOUD LOG` prints.
- ✅ **"Labels clipping the side / hiding behind the gear box" → FIXED + verified** — unified safe-rect clamp for
  both convoy and settlement labels, plus a per-frame re-clamp during pans. User confirmed. (Sprint 9 A5.) A
  separate right-side settlement-preview/vendor **panel** still clips off the right edge — tracked in TODO Backlog.

---

# Closed backlog items (with root-cause detail)

- ✅ **`discord_popup.gd` font double-scale** — Sprint 10. See above.
- ✅ **Dead tutorial tab handlers + second-layer orphans** — Sprint 10. See above.
- ✅ **Sold-out vendor items linger in the list** — Sprint 10. See above.
- ✅ **Vendor efficiency = 0** — Sprint 9 external blocker; resolved via `/map` deploy. See
  [[reference_vendor_efficiency_binary_serializer]].
