This document will serve as a flowing state of things needed in the project, what resources are needed for each task.

> **Status:** Sprints 1–8 complete. Sprint 8 (tutorial re-fit to the settlement-**hub** UI) is committed and device-verified stable — `725c42f` ("Tutorial stable") plus the `511d2d5` flashing-panel fix — and plays end-to-end in portrait, landscape, and desktop. Two non-blocking closeout items (delete the dead vendor-tab handlers, add tutorial smoke-test coverage) were reclassified out of the sprint — see the Sprint 8 section and Tech Debt / Testing below. **Sprint 9 (map & misc polish + vendor/mechanics polish) is code-complete and compile-clean; the only thing gating closeout is a batched portrait/landscape/desktop device-test pass** (plus the externally-blocked vendor-efficiency backend deploy). See the trimmed Sprint 9 section below.

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

Full detail for each sprint is preserved in git history (`725c42f`/`511d2d5` Sprint 8, `2dc42bf`/`fe10261` Sprint 7, `54d5493` Sprint 6, `600a06b` Sprint 4, `ec0dcdb` Sprint 3, `5498ad0` Sprint 1&2). Sprint 6's commit message is terse ("bug fixes and Journey QOL"), so its detailed breakdown is kept in the Action Plan below; Sprint 7's and Sprint 8's follow it.

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
`settlement_overview_menu.gd:210/509`. Every new highlight must resolve by **content identity** (vendor
name label, button text), never a fixed rect/index, and re-resolve on `layout_mode_changed` rebuilds.
**Verify every fixed step in portrait, landscape, AND desktop.**

Tutorial-city vendor card labels (match by substring): `Tutorial City Dealership`,
`Tutorial City Market`, `Tutorial City Gas Station`.

**Status (final, 2026-07-16):** ✅ All levels (L1, L2, L4, L5) reworked/verified and playing end-to-end on
device in portrait, landscape, and desktop. Ten rounds of device-feedback polish landed (rounds 1–9 below
+ round 10 flashing-panel fix). Compile-clean (standard + warnings-as-errors). **Reclassified out of the
sprint (non-blocking):** deleting the dead `await_dealership_tab`/`await_market_tab` handlers → Tech Debt
(scope corrected — see that item); tutorial-flow smoke-test coverage → Testing backlog. The doc fix landed.

- [x] **L1 — settlement entry + vendor card (softlock fix)** — `await_settlement_hub` (waits for
  `menu_opened("settlement_hub")`) + `await_vendor_open` (waits for `menu_opened("convoy_settlement_submenu")`),
  new `settlement_hub_vendor_card` resolver matching the card by `vendor_name` meta (hub tags cards +
  `get_vendor_card_node_by_name_contains()`). Device-verified through buy. `tutorial_manager.gd`,
  `target_resolver.gd`, `settlement_overview_menu.gd`.
- [x] **Retarget Top Up** — resolver + `_watch_for_top_up` now prefer the hub's resources-card Top Up button
  (tagged `is_top_up_button`, exposed via `get_top_up_button_node()`); legacy settlement-menu path kept as
  fallback. Already-full guard handles the hub's "Topped Up" label.
- [x] **L2 — hub flow, both supply beats kept** — back to hub → tap Market card → buy 2 MRE + 2 Water → back
  to hub → Top Up. Compile-clean; **pending device test.**
- [x] **L4 — first delivery, hub flow** — reworked: (user is in the hub after the L2 top-up) tap Market card →
  buy Mountain Urchins → **straight to the Journey menu** (round 3: dropped the L4 top-up / return-to-settlement
  steps; resources were filled in L2 and `l5_open_journey_menu` forces stage 6 → warp). **Pending device test**
  (esp. the warp actually firing without an L4 top-up).
- [x] **L5 — journey (verify only)** — verified on device; the warp race (convoy at 0,0 → `l5_pick_destination`
  suspends) resolves cleanly and the route confirms. Camera-focus stale-snapshot fix (round 9) also covers this.
- [→] **Remove now-dead tab machinery** — **moved to Tech Debt, scope corrected.** Audit finding: only
  `await_dealership_tab`/`await_market_tab` (match arms `tutorial_manager.gd:793`/`821`) + `_hint_dealership_tab`
  are truly dead — no step in `_build_level_steps()` emits those actions. **`_lock_vendor_tabs`/
  `_watch_for_tab_selected`/`_on_vendor_tab_selected` are still live** — the `lock_tabs_for_actions` list
  (`tutorial_manager.gd:693`) wires them to the live `await_vehicle_purchase`/`await_supply_purchase`/
  `await_urchin_purchase` steps. Deleting the whole set as the earlier note claimed would break tab-locking
  during purchases. (First verify the hub's single-vendor menu even has a `TabContainer` — if not, the lock is
  already a no-op and the whole block can go.)
- [→] **Smoke-test full flow** — **moved to Testing backlog.** `Scripts/Debug/wiring_smoke_test.gd` still only
  asserts autoload wiring (zero tutorial references); tutorial-flow coverage never landed. The manual
  portrait/landscape/desktop pass was done instead (device-verified stable). Automated coverage is a follow-up.
- [x] **Docs** — corrected the "steps are JSON" claim in `TutorialSystemOverview.md` (with a follow-up doc-sync
  pass 2026-07-16 fixing the residual JSON framing in the mermaid diagram, `StepSchema.md`, and `Controllers.md`).

**Device-feedback polish (round 1) — 2026-07-10:**
- [x] **Highlight fired before the card settled** — `settlement_hub_vendor_card` resolver waits until the card's
  rect is stable across two frames before measuring (`target_resolver.gd`), so it no longer flashes at the
  card's pre-slide position.
- [x] **First-convoy modal fit + keyboard** — `NewConvoyDialog` was a fixed 1000×480 panel; now sizes to the
  viewport, wraps the title, compacts fonts/heights in landscape, and is top-anchored. (Refined in round 2.)
- [~] **Tutorial text overlapped the menu** — first attempt capped the panel + scrolled; reverted in round 2
  (see below) because scrolling was unwanted.

**Device-feedback polish (round 2, from L1/L2 pass) — 2026-07-10, pending re-verify:**
- [x] **Modal hidden behind the top bar** — round-1 top-anchor tucked the card under the top bar.
  `_update_new_convoy_dialog_layout` now offsets it below the top bar's bottom edge (measured relative to the
  dialog's parent), so the title is fully visible while staying clear of the keyboard.
- [x] **No more scrolling in the tutorial text box** — reverted the ScrollContainer/height-cap in
  `tutorial_overlay.gd`; the panel sizes to content (no scroll), stays width-bounded and below the top bar, and
  the landscape side-menu right-inset is kept. Per-step copy must stay short enough to fit the map strip — long
  copy is split across steps or trimmed (e.g. the L1 buy-vehicle copy was shortened).
- [x] **Back-to-hub uses the vendor menu's top-left button** — the L2 "return to settlement" steps use the
  `convoy_return_button` resolver → `back_requested` → `go_back()` reopens the hub and re-emits
  `menu_opened("settlement_hub")`, instead of pressing the Settlement nav twice. (Resolver target corrected in
  round 3 — see below.)

**Device-feedback polish (round 3, from L1–L4 pass) — 2026-07-10, pending re-verify:**
- [x] **Back button wasn't highlighting** — the real top-left back control is a `PanelContainer` named
  `BackToSettlementButton` ("‹ <settlement> / <vendor>") mounted *inside the vendor panel's control row*, not
  `MainVBox/TopBarHBox/TitleLabel`. `_resolve_convoy_return_button` now finds `BackToSettlementButton` first
  (`target_resolver.gd`). It doesn't read as a button, so highlighting it is what makes the back path findable.
- [x] **Top Up highlight blended in** — the hub Top Up button was brass (gold), the same as the gold highlight.
  Recolored to `UITheme.STATUS_GOOD` (green) in `settlement_overview_menu.gd::_make_top_up_button`.
- [x] **After urchins: go to Journey, not Settlement** — L4 now ends at the urchin purchase and L5 sends the
  player straight to the Journey menu (see L4 item above). ✅ *The "vendor menu blanks after purchase" bug is now
  root-caused and fixed — see round 5 below (it was a vendor-tree crash, not a `convoy_settlement_menu` issue).*
- [x] **Confirm Journey wasn't clickable** — the highlight hole excluded the dynamically-built Confirm button,
  and the shield blocked the tap. `l5_embark` is now ungated (`lock = "none"`, no target); the whole screen is
  interactive and the watcher still advances on journey start. Added an empty-target guard in
  `_resolve_and_highlight` so ungated steps don't spin the resolver retry loop.

**Device-feedback polish (round 4, from L1–L2 landscape pass) — 2026-07-10, pending re-verify:**
- [x] **Text box overlapped the vendor menu (landscape)** — two root causes: (1) the inset heuristic missed a
  side menu whose left edge sat below the 40% threshold; (2) the message `RichTextLabel` has `fit_content = true`,
  so it sized to the **unwrapped** text width and forced the panel wider than any width cap (a `custom_minimum_size.x`
  floor can't cap it). `tutorial_overlay.gd::_relayout_panel` now: clamps the panel's right edge directly against
  the live `MenuContainer` rect (no threshold, 16px gap); **bounds the label's `custom_minimum_size.x`** so it
  wraps to the panel width instead of spilling; drops the VBox's 380px min width; and uses a smaller landscape
  left margin (`_safe_left_inset + 16`) so the panel uses the empty strip left of the map. No scroll; copy stays short.
- [x] **Supply step "not updating" — kept the strict Water-Jerry-Cans match** — the vendor stocks BOTH plain
  `Jerry Cans` (fuel) and `Water Jerry Cans` (water); the water total must require **both** `water` AND `jerry`
  (never bare `jerry`) so a plain-jerry-can purchase doesn't wrongly satisfy the step. See
  [[reference_jerry_cans_vs_water]] and the TutorialSystem "Content gotcha" note. Added `[Tutorial][DIAG] supply
  cargo item=…` logging in `_on_supply_check` so a wrong-item purchase is obvious in the logs. *If a genuine
  `Water Jerry Cans` buy still doesn't count, those logs will show whether `_on_supply_check` fires and what
  cargo it sees — root-cause from there.*

**Device-feedback polish (round 5) — 2026-07-10, pending re-verify:**
- [x] **Vendor menu crashed/blanked after a purchase** — root cause: `VendorTreeBuilder.make_display_agg_with_parts_rebucket`
  pre-seeded a `"missions"` bucket, but the aggregator (`cargo_aggregator.gd`) emits delivery cargo under `"delivery"`
  (stale rename). Copying agg's `"delivery"` bucket into a display_agg that lacked it threw *"Invalid access to key
  'delivery'"* (`tree_builder.gd:52`) during the post-purchase tree rebuild → blank menu. Fix: pre-seed `"delivery"`
  + defensively create any missing bucket during the copy (`tree_builder.gd`); and the caller's category map now keys
  on `"delivery"` (`vendor_trade_panel.gd::_populate_list_from_agg`) so **Delivery Cargo (e.g. Mountain Urchins) also
  renders** instead of silently vanishing. `"missions"` kept as a legacy title alias.
- [x] **Crash re-entering the Market vendor** — `vendor_item_list.gd::_ensure_row_visible` did `await
  get_tree().process_frame`, but on re-entry `populate` re-selects the previous row while the list is still
  **detached from the tree**, so `get_tree()` was null → *"Invalid access to 'process_frame' on a null instance"*.
  Now guards `get_tree()` and skips the scroll-into-view (a nicety) when detached. (No other unguarded
  `await get_tree()` in the vendor/settlement rebuild paths.)
- [x] **Text box still grazed the menu (landscape)** — see round-4 update: the `fit_content` label was the real
  culprit; now width-bounded so it wraps within the clamped panel.

**Device-feedback polish (round 6) — 2026-07-10, pending re-verify:**
- [x] **Confirm Journey still un-tappable (round-3 fix incomplete)** — `lock = "none"` hid the shield ring, but
  the overlay **Control itself** kept `mouse_filter = STOP`: `tutorial_overlay.gd::clear_highlight` set STOP for
  any non-SOFT gating, so the ungated full-screen overlay silently ate the tap. Now only **HARD** blocks; NONE
  (ungated) and SOFT (hole) pass input through. Message steps are unaffected (they don't call `clear_highlight`).
- [x] **Vendor disappears after buying Mountain Urchins** — a `map_changed` right after a mission-item purchase
  ran `_display_settlement_info`, which `_clear_tabs()` then rebuilt nothing when the fresh snapshot momentarily
  lacked the vendor → blank. Added a single-vendor guard (`convoy_settlement_menu.gd`): if a tab is already shown
  and the incoming snapshot doesn't contain `_single_vendor_id`, skip the destructive rebuild and keep the tab.
  *Hypothesis-based (couldn't repro locally); the existing `[DIAGNOSTIC] _display_settlement_info called` +
  new skip log will confirm the trigger on device.*

**Device-feedback polish (round 7) — 2026-07-10, pending re-verify:**
- [x] **Convoy journey route line not showing on selection** — the route LINE and the delivery-destination
  ARCS were both gated by the same `active_delivery_destinations` ("Delivery Targets") toggle, which defaults
  off. Per design intent, decoupled them: the focused/selected convoy's **journey line always draws** now
  (`UI_manager.gd::_on_connector_lines_container_draw` — removed the `show_active_lines` gate on the focused
  convoy; `all_convoy_destinations` still shows every convoy's line). The **"Delivery Targets" toggle now only
  gates the curved destination arcs/markers**, which is what it should do. Not a regression from the tutorial
  work — no map code had been touched; the toggle was simply off (likely reset with the test account).

**Device-feedback polish (round 8, restart softlock) — 2026-07-14, pending device test:**
- [x] **Softlock when resuming a level from the map root** — the tutorial always resumes at `_step = 0`
  (`tutorial_manager.gd::_maybe_start` forces it), but several levels' first step assumed the player was
  already deep in a menu. On a fresh restart the game reopens at the map root with **no menu**, so the
  shared bottom nav bar (Vehicles / Journey / Settlement / Cargo) doesn't exist — L5's `l5_open_journey_menu`
  highlighted a "Journey" button that wasn't there, and L2's `l2_return_to_hub` a vendor back button that
  wasn't there. The instruction pointed at nothing → softlock (reported at the Journey screen). Fix: a
  **resume anchor** (`await_convoy_menu` action) prepended to L2 and L5. It auto-advances with no prompt when
  a convoy submenu is already active (continuous path — zero disruption), and on a restart highlights the
  always-present **convoy dropdown** and waits for any convoy menu to open (which brings the nav bar up).
  `CONVOY_SUBMENU_TYPES` + `_is_convoy_submenu_active()` gate the fail-safe (kept in sync with
  `menu_manager.gd::_update_static_nav_bar_ui`). Also made `target_resolver.gd::_resolve_convoy_return_button`
  adaptive: when there's no vendor back button but a convoy submenu is open, it highlights the **Settlement
  nav button** (not the convoy dropdown), so L2's return-to-hub step guides Convoy dropdown → Settlement → hub
  on the restart path. Compile-clean (standard + warnings-as-errors).

**Device-feedback polish (round 9, camera focuses old convoy spot) — 2026-07-14, pending device test:**
- [x] **Camera pans to the pre-warp location on tutorial exit** — when the tutorial's final menu closes, the
  camera focuses on the convoy using `_last_focused_convoy_data`, a snapshot captured at **menu-open**. During
  L5 the backend warps the convoy from (0,0) to its start city, so that snapshot's top-level `x`/`y` are stale
  and the close tween (`main_screen.gd::_slide_menu_close` → `smooth_focus_on_convoy_with_final_occlusion`)
  panned to the old tile. Root cause is general: the menu's `menu_data` meta and `_last_focused_convoy_data`
  are never refreshed after open, and `map_camera_controller.get_convoy_world_position()` reads `x`/`y` from
  the passed dict. Fix: new `main_screen.gd::_refresh_convoy_data_from_store()` re-resolves the convoy by
  `convoy_id` from GameStore (live coords) right before every camera-focus call — menu open, menu close, the
  layout-reposition path, and `_get_primary_convoy_data` (return-to-convoy). Safe because both the snapshot
  and the store dict lack the runtime interpolation fields, so only the coordinates change. Compile-clean
  (standard + warnings-as-errors).

**Device-feedback polish (round 10, flashing panel) — 2026-07-16 (`511d2d5`), device-verified:**
- [x] **Tutorial text box flashed to near-full-screen for one frame** — two independent root causes in
  `tutorial_overlay.gd`, both timing-related and only visible during polled updates (checklist rebuilds on every
  `convoys_changed`): (1) `_update_checklist` recreated **autowrapping** `Label`s each update; a fresh autowrap
  label shapes its text at width 0 for one frame → reports a wrapped-at-zero-width min HEIGHT of hundreds of px,
  which the panel adopts as its minimum and flashes tall. Fixed by making checklist rows **single-line +
  ellipsis** (`AUTOWRAP_OFF` + `OVERRUN_TRIM_ELLIPSIS`, zero min-width, FILL) so row height is deterministic and
  width still can't inflate the panel. (2) In portrait, `_relayout_panel` clamped the panel's right edge to the
  menu's left edge, but portrait menus are full-width **bottom sheets** that slide in **horizontally** (left edge
  sweeps 800→0) — tracking that sweep shrank the box 600→120 frame-by-frame then snapped back. Fixed by skipping
  the menu-edge clamp entirely in portrait (only landscape has a real right-anchored side menu to dodge). Panel
  height (`size.y`) was also added to the layout-change diagnostic trigger (top-anchored growth is invisible to
  the width/position checks).

> **Dropped from scope:** the map-pin teaching step. The tutorial keeps its current entry flow (convoy
> dropdown → Settlement nav); it does not teach map-label pinning.

### Sprint 9 — Map & misc polish + vendor/mechanics polish — 🎯 WRAPPING UP (code-complete; batched device test pending)

All items are code-complete and compile-clean (standard + warnings-as-errors). Full root-cause
narratives live in git history and agent memory; only status + primary file are kept here. **Verify
each in portrait, landscape, AND desktop where relevant.**

**Batch A — map / route polish**
- [x] **A1 · Settlement labels tap-only (mobile)** — gated the three `_update_hover()` calls in
  `_handle_touch_input` so pan-drag no longer flashes labels under the finger; on touch, labels reveal
  only via an explicit tap. `map_interaction_manager.gd`. *Pending device test.*
- [~] **A2 · Map overlay notch clearance** — **deferred, not reproduced.** Panel already applies
  safe-area insets on both axes, ungated. Revisit only with a concrete device repro (element +
  orientation). `map_overlay_settings_panel.gd`.
- [x] **A3 · Vendor cards clip below nav (mobile-landscape hub)** — hub is no-scroll by design, so fixed
  by fit-to-height: pack ≤4 vendors into one row + shorter cards, mobile-landscape only (portrait/desktop
  untouched). `settlement_overview_menu.gd`. *Pending device test.*
- [x] **A4 · Map labels occlude route line** — extended the existing anti-collision loop to nudge
  settlement labels off the active preview route (`_settlement_panel_overlaps_route` + a segment-vs-AABB
  test), plus a route-fit top-headroom knob (`route_fit_label_top_extra_px`) that drives both the bounds
  pad and the focus lift so the topmost labels stay on-screen. `UI_manager.gd`, `map_camera_controller.gd`.
  *Pending device test.* Known limit: nudge is vertical-only.

**Batch B — vendor / mechanics polish**
- [x] **Vehicle stats in vendor menu** — list rows now fall back to `base_*` keys (vendor payloads null
  the plain `top_speed`/`cargo_capacity`/… keys). `vendor_item_list.gd`. *Pending device test.*
- [x] **Vehicle inspector parity + description popup** — vendor vehicle inspector now matches the convoy
  summary page (Seats / Make-Model / Color / Shape shown when present) plus a Description popup button,
  surfaced across desktop, mobile-landscape, and portrait. `inspector_builder.gd`, `vendor_trade_panel.gd`,
  `vendor_item_list.gd`. *Pending device test.*
- [x] **Mechanics dropdown — upgrade count per vehicle** — vehicle selector shows `[N ↑]` = slots with a
  compatible upgrade available (convoy cargo + vendor stock), same criterion as the Parts-tab rows;
  prefixed so it survives OptionButton clipping; refreshes in place on select / vendor-load / compat-ready.
  `mechanics_menu.gd`. *Compile-verified; pending device test.* (Docs: `03_Systems/Mechanics.md`.)
- [x] **Available Parts preview — compatible vehicles** — each part lists which convoy vehicles can use it
  (slot match), with a **green highlight + "Fits:" line** for parts that fit ≥1 vehicle, sorted
  most-compatible first. `convoy_menu.gd`. *Device-confirmed (preview visible).* (Docs: `02_UI_UX/ConvoyMenu.md`.)
- [→] **Mechanics compatibility preloading** — **partially delivered** by the per-vehicle upgrade count
  above. Remaining scope: eager pre-fetch of backend compat for **all** vehicles on open (non-selected
  vehicles currently use the local slot heuristic until selected), and a multi-vehicle / multi-upgrade
  cart. `mechanics_menu.gd`, cart system.

**Blocked externally:**
- [x] **Vendor efficiency = 0** — client fallback is fixed; **blocked on a deploy of the `/map` payload.**
  Production's `/map/get` serves a lean vehicle dict that omits real efficiency (the binary packer reads a
  renamed key). See the [DF_Lib case study](04_Technical/DF_Lib.md#case-study-the-vanishing-vehicle-efficiency-stat)
  and memory [[reference_vendor_efficiency_binary_serializer]]. Once the payload serves efficiency, the
  client fix renders it (plus Seats/Make/Model/Color for vendor vehicles).

---

# Code Map (active tasks)

Sprint 6/7/8 rows removed — all complete. Sprint 9's coded items are also removed (all code-complete;
they now only need the device-test pass tracked in the Sprint 9 section above). Remaining rows are the
one open follow-up + reclassified cleanup.

| Task | Primary file:line | Notes |
|---|---|---|
| Mechanics compat preload (remaining) | `mechanics_menu.gd`, cart system | Per-vehicle upgrade count shipped; remaining = eager all-vehicle compat pre-fetch + multi-vehicle/multi-upgrade cart |
| (Tech debt) Delete dead tutorial tab handlers | `tutorial_manager.gd:793`/`821`, `_hint_dealership_tab` | Only the `await_*_tab` arms are dead; keep `_lock_vendor_tabs`/`_on_vendor_tab_selected` (live for purchase steps) |

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
- **Dead tutorial tab handlers** — `await_dealership_tab`/`await_market_tab` match arms (`tutorial_manager.gd:793`/`821`) + `_hint_dealership_tab` are no longer emitted by any step after the Sprint 8 hub rework. Safe to delete. **Do not** delete `_lock_vendor_tabs`/`_watch_for_tab_selected`/`_on_vendor_tab_selected` — the `lock_tabs_for_actions` list (`tutorial_manager.gd:693`) still wires them to the live `await_vehicle_purchase`/`await_supply_purchase`/`await_urchin_purchase` steps. First confirm the hub's single-vendor menu still has a `TabContainer` (`_get_vendor_tab_container()`); if it doesn't, the lock is already a no-op and the whole block can go.

## Testing

- **Tutorial-flow smoke coverage** — `Scripts/Debug/wiring_smoke_test.gd` only asserts autoload wiring today. Extend it toward tutorial-flow coverage (step build, resolver resolution per level) so a hub/menu rename can't silently break onboarding. Sprint 8 shipped on a manual portrait/landscape/desktop pass instead.

## Migration Status (UITheme adoption)

✅ `convoy_menu`, `convoy_vehicle_menu`, `mechanics_menu`, `vendor_trade_panel`, `MenuBase`, `convoy_journey_menu` (navy chrome Sprint 3)
✅ `warehouse_menu`, `warehouse_item_card` (Oori sweep 2026-07-01)
⚠️ `convoy_settlement_menu` (partial) · `settlement_overview_menu` (new — check token use)
❌ `convoy_cargo_menu` (raw colors remain)
