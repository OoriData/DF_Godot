---
type: note
tags:
  - kind/process
  - status/unverified
aliases:
  - "TODO — Active Work"
created: 2026-05-21
updated: 2026-07-29
status: unverified
---

This document serves as the flowing state of things needed in the project, and what resources are needed for each task.

> **Status (2026-07-29):** Sprints 1–10 are complete / code-complete. Outstanding work is now four
> buckets: (1) the **device-test round 2** pass (checklist below), (2) **Sprint 11 — QOL bug batch**
> (2026-07-22, mostly uncoded), (3) **Sprint 12 — Steam beta batch** (2026-07-28) covering
> desktop/PC layout ratios, vendor-panel widescreen fit, always-available feedback, a fullscreen
> shortcut, and a "connect an existing account" branch at first Steam launch, and (4) **Sprint 13 —
> play-test batch** (NEW, 2026-07-29): pre-login performance, the vendor buy/stock/"Processing" trio,
> input-settings gaps, and a total Android login failure. After those, the project
> pivots to the **systems audit & research initiative** (below) to re-baseline the docs against the code.
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
  - 🔗 **Same root cause family as Sprint 12 · S12-4** (overlay options panel eats the screen on PC).
    `ui.scale` divides the *logical viewport width*, so every fixed-logical-px panel grows as a
    **fraction of the screen** as the slider rises. Fix the slider ceiling and the fixed-width panels
    together, or one will keep re-breaking the other. See
    [ui_system.md § Desktop scaling contract](02_UI_UX/ui_system.md#desktop-scaling-contract-and-why-fixed-width-panels-drift).

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
  live schema, not the stale Godot data dumps (see [data_dumps README](99_Reference/data_dumps/README.md) *(agent memory: `reference_backend_repo_and_stale_dumps`)*).

---

# Sprint 12 — Steam beta batch (NEW, 2026-07-28)

Reported from Steam/PC beta play-testing. Every entry below was **researched against current code**
before being written down — each carries the verified root cause, the exact files, and the doc that
now backs it. **None are coded yet.** IDs (`S12-n`) are for cross-referencing from commits/docs.

> **Read first for the three layout items (S12-1, S12-4, and the Sprint 11 UI-scale slider):** they all
> share one mechanism, now documented in
> [ui_system.md § Desktop scaling contract](02_UI_UX/ui_system.md#desktop-scaling-contract-and-why-fixed-width-panels-drift).
> Fixing them in isolation will re-break each other.

## Layout / desktop ratios

- [ ] **S12-1 · Vendor page doesn't use a big desktop screen well** *(P1)* — on a wide monitor the vendor
  page is simultaneously **too wide overall** and **badly proportioned inside**. Three verified causes
  (menu sheet has no desktop branch / no absolute max width · the 3-column split can't rebalance ·
  `_make_panels_responsive()` has no desktop path) are documented in full, with file:line, as **D1–D3** in
  [VendorPanel/ResponsiveRefactor § Desktop](02_UI_UX/VendorPanel/ResponsiveRefactor.md). The shared
  scaling mechanism is [ui_system § Desktop scaling contract](02_UI_UX/ui_system.md#desktop-scaling-contract-and-why-fixed-width-panels-drift).
  **Proposed numbers (2026-07-29 — reporter delegated the call: "propose these changes, I trust your
  judgement and I'll give feedback as needed"). These are a starting point to react to on screen, not a
  finished spec:**
  - `_get_menu_ratios()` (`main_screen.gd:648-656`) currently has **only** a portrait and a landscape
    branch — desktop silently takes the landscape `Vector2(0.35, 0.85)`, i.e. up to **85 % of a 21:9
    monitor**. Add a third branch: **`Vector2(0.35, 0.62)`** for desktop. 62 % keeps the map meaningfully
    visible (the stated goal of the whole layout system) while still giving the vendor panel more absolute
    width than it has on any mobile device.
  - Add an **absolute ceiling of ~1100 logical px** on the open menu width, applied *after* the ratio. Past
    that, extra monitor width goes to the map, not the panel. Rationale: at `ui.scale 1.0` a 1920-wide
    desktop is 1920 logical px, so 1100 ≈ 57 % — a comfortable reading measure — and because the cap is
    absolute it cannot be re-broken by the `ui.scale` mechanism described in the § Desktop scaling
    contract (which is what makes the *ratio* alone insufficient).
  - Inside the panel, **cap total content width and centre it** rather than letting three columns stretch.
    Long label/value rows past ~1100 px read as two disconnected halves.
  All three numbers should be single named constants, not inline literals, so feedback is a one-line edit.
  `Scripts/UI/main_screen.gd`, `Scripts/Menus/vendor_trade_panel.gd`, `Scenes/VendorTradePanel.tscn`.

- [ ] **S12-4 · Overlay options panel eats a large proportion of the screen on PC** *(P1 — PC only; Mac
  and mobile "fine for the most part")* — the gear-tab map-overlay panel
  (`Scripts/UI/map_overlay_settings_panel.gd`). Two verified causes: a **flat `440.0` desktop width** with
  no viewport-fraction cap (`_get_panel_width()`, line 46 — the only branch not expressed as a fraction),
  and **`ui.scale` shrinking the logical viewport out from under it** (23 % of width at `ui.scale 1.0`,
  ≈46 % at 2.0). Compounded by `_content_panel.size_flags_vertical = SIZE_EXPAND_FILL` (line 219), so it's
  always full screen height. Full mechanism + math:
  [ui_system § Desktop scaling contract](02_UI_UX/ui_system.md#desktop-scaling-contract-and-why-fixed-width-panels-drift).
  **Proposed numbers (2026-07-29 — reporter delegated the call; react on screen and I'll adjust):**
  - Replace the flat `440.0` desktop return in `_get_panel_width()` (`:46-53`) with
    **`clamp(win_size.x * 0.24, 380.0, 520.0)`** — expressed as a fraction like every other branch, so
    `ui.scale` shrinking the logical viewport can no longer turn it into ~46 % of the screen, with a floor
    so it stays usable and a ceiling so it never dominates a wide monitor.
  - Drop `_content_panel.size_flags_vertical = SIZE_EXPAND_FILL` (`:219`) in favour of
    **`SIZE_SHRINK_CENTER` with a max height of ~70 % of the viewport**. Six toggle rows do not need full
    screen height, and full-height is most of what makes the panel feel like it "eats the screen."
  **Before coding, capture the PC numbers** — `UI_scale_manager.gd:143` prints
  `[UIScale] win=… factor=… target_w=… vp=…` on every apply and `main_screen.gd:696` prints
  `[LAYOUT-OVERFLOW]`. Those two lines from the Windows build identify which cause dominates without guessing.
  `Scripts/UI/map_overlay_settings_panel.gd`, `Scripts/UI/UI_scale_manager.gd`.
  (Docs: [UIAudit § 9 Map Overlay Settings Panel](02_UI_UX/UIAudit.md#9-map-overlay-settings-panel).)
  - ⚠️ **Fix alongside — physical-vs-logical split brain:** `device_state_manager.gd:28` reads
    `DisplayServer.window_get_size()` (physical) while `main_screen.gd` / `map_overlay_settings_panel.gd`
    `_is_portrait()` use `get_viewport_rect().size` (logical). Documented at
    [ui_system § Known violation](02_UI_UX/ui_system.md#never-latch-a-value-you-derived-by-dividing-by-the-scale).
  - ⚠️ **Code cleanup:** the dead `ui.scale` fallback of `1.4` at `settings_menu.gd:247` should be
    reconciled to the real default `1.0`. Detail: [ui_system](02_UI_UX/ui_system.md).

## Vendor menu

- [ ] **S12-2 · Empty slot at the top of the vendor sort options** *(P3 — needs a pinpoint before coding)* —
  reported as "there is a space for another option at the top but nothing is there." Research found the
  sort popup is fully populated, so this is **one of two different things** and the fix differs:
  - **(a) A missing neutral/default sort entry.** `vendor_trade_panel.gd:944-950` builds exactly five
    radio items, one per `CargoSorter.SortMetric` (`Scripts/System/cargo_sorter.gd:5-11`). There is **no
    "Name (A–Z)" / "Default" entry**, yet name-order *is* a real state the list can be in: both
    `vendor_item_list.gd:147-174` and `tree_builder.gd:173-230` apply `CargoSorter` **only** to the
    `"Delivery Cargo"` category and fall back to case-insensitive display-name order everywhere else.
    So the current sort is unrepresented in the menu — the plausible "space with nothing in it."
    Fix = add the entry + honour it (it becomes index 0, so bump the persisted `ui.cargo_sort_metric`
    mapping carefully — `settings_manager.gd` stores it as a raw int and `vendor_trade_panel.gd:979`
    clamps to `item_count - 1`, so a naive insert silently re-labels every existing player's saved sort).
  - **(b) A literal blank gap in the control row.** The row is assembled at runtime by
    `_consolidate_control_row()` (`vendor_trade_panel.gd:1063-1085`) as `[Buy|Sell segments][Sort ▾]`,
    and on **mobile only** `mount_external_vendor_selector()` (line 1087) injects the vendor dropdown at
    index 0 → `[Vendor ▾][Buy ⇄][Sort ▾]`. Desktop never gets that third control. Also note
    `_set_cargo_sort_ui_visible()` (line 175) hides the **Sort button itself** when the vendor has no
    delivery cargo, leaving the segments alone on the row.
  **Action:** ask which one it is (screenshot of the open popup vs. the closed row) before touching code,
  per the project's pinpoint-first rule. `Scripts/Menus/vendor_trade_panel.gd`,
  `Scripts/System/cargo_sorter.gd`, `Scripts/Menus/VendorPanel/vendor_item_list.gd`.

## Blank screen on Steam

- [x] **S12-7 · First Steam launch shows only the background art** *(P0 — 🔧 FIX CODED 2026-07-28,
  ⚠️ NOT YET VERIFIED AGAINST AN EXPORTED STEAM BUILD)* — reported as: logging in with Steam for the
  first time (no Steam account associated with a DF account) leaves the screen blank apart from the
  tiled background pattern. **Exported build only — does not reproduce in the editor** (confirmed: a
  local windowed run against the same 0-convoy account produced a healthy
  `map_rect=[P: (0.0, 152.0), S: (2133.0, 1181.0)]`).
  - **Evidence** — three logs in `user://logs/` from the Steam runs all end with
    `map_rect=[P: (0.0, 1610.136), S: (2133.0, 0.0)]` (and `[P: (0.0, 1541.0), S: (2133.0, 0.0)]` at
    a smaller viewport) — **zero height**, positioned *below* a viewport only 1200–1338 tall. The
    healthy run: `[P: (0.0, 80.0), S: (2133.0, 1056.0)]`. Since `MapDisplay` is full-rect inside
    `Main → MapAndMenuContainer → MainContent` (HBox, expand) → `MainContainer` (VBox), a
    `MainContent` at y≈1610 with height 0 means **the TopBar claimed ~1610 logical px of minimum
    height** — which is precisely what the screenshot shows: the top bar's own darkened Oori tile
    filling the screen, nothing else.
  - **Root cause.** `UIScaleManager.get_logical_safe_margins()` converts a **physical** safe-area
    inset to logical px by **dividing by `content_scale_factor`**. In exported/Steam builds the
    window can report a bogus size for a frame, pinning that factor at the `_MIN_SAFE_FACTOR`
    (`0.05`) floor — a documented boot state (`UI_scale_manager.gd:31-35`, the same family as the
    previously-fixed blank *login* screen). A ~47px macOS menu-bar/notch inset then becomes **~940
    logical px**. `UserInfoDisplay._update_safe_margins()` writes that straight into its panel
    stylebox (`content_margin_top = 4.0 + safe.position.y`), which feeds the bar's **minimum
    height** — and its only recompute trigger was `NOTIFICATION_RESIZED`, because
    `_on_ui_scale_changed()` (the handler for exactly the event that invalidates the value) was an
    empty `pass`. So the bad boot value was **latched forever**. `UIScaleManager` had been hardened
    against the bogus-boot-size problem; **its consumers had not**.
    *(The ~940 figure is a fit against the two broken logs — the top-bar height tracked
    `viewport/2 + 941` — matched to `47 / 0.05`. Strong circumstantial agreement, not yet proven on
    device; see verification below.)*
  - **Fix (3 parts).** (1) `UI_scale_manager.gd` — new `_scale_settled` flag: a factor rescued by the
    floor is not a real scale, so `get_logical_safe_margins()` returns **zero margins until settled**
    and additionally **clamps every inset to ≤ 20 % of the logical viewport** (a safe area is a
    notch, never a third of the screen). (2) `user_info_display.gd` — `_on_ui_scale_changed()` is no
    longer a `pass`; it re-runs `_update_mobile_sizing()` + `_update_safe_margins()`, so a bad boot
    value can never stick. (3) `user_info_display.gd` — `_update_safe_margins()` now bails unless
    `has_theme_stylebox_override("panel")`, so a call landing before `_apply_base_styling()` can't
    mutate the **shared theme stylebox** and apply this bar's notch inset to every `PanelContainer`
    in the app.
  - **Diagnostic added:** `main_screen.gd::_diag_dump_map_ancestor_sizes()` — when a degenerate map
    rect survives the existing one-frame retry, it dumps the `MapDisplay → root` ancestor chain with
    each control's `combined_minimum_size`, so the offending control is named from a log alone
    instead of inferred. Gated on the existing `_debug_layout_overflow` flag.
  - ⚠️ **VERIFY ON AN EXPORTED STEAM BUILD before closing** — this cannot be proven in the editor,
    which is the whole reason it shipped. Export, run via Steam with a Steam account **not** linked
    to a DF account, and check `user://logs/godot*.log`:
    **pass** = `[RESIZE] map_rect` has a non-zero height with y ≈ the top-bar height (80–160), and no
    `[MAP-RECT-DIAG]` block; **fail** = height 0 / y beyond the viewport, and the new
    `[MAP-RECT-DIAG]` dump names the control still claiming the height.
  - **Related, found in the same logs, still open** — see S12-8 below.

- [ ] **S12-8 · `_show_new_convoy_dialog()` runs in an unbounded loop for a 0-convoy account** *(P2)* —
  the same Steam logs show `[Onboarding] _show_new_convoy_dialog invoked.` **hundreds of times**, each
  one calling `modal_layer.show()`, `_update_new_convoy_dialog_layout()` and
  `_new_convoy_dialog.call_deferred("open")`. The loop: `ConvoyService.refresh_all()` → `USER_CONVOYS`
  → the response sets **both** user and convoys → `user_changed` **and** `convoys_changed` fire →
  `_check_or_prompt_new_convoy_from_store()` → `_show_new_convoy_dialog()`; meanwhile
  `GameScreenManager` re-triggers `refresh_all()` on `user_changed`. Independent of S12-7 (the bad map
  rect appears *before* the first dialog call), but it burns a request per iteration against
  `/user/get` and re-lays-out the modal every time. **Likely the main driver of S13-1's pre-login lag —
  fix this first and re-measure before touching the login background viewport.** Make the prompt idempotent — no-op when the dialog
  is already open. `Scripts/UI/main_screen.gd`, `Scripts/UI/game_screen_manager.gd`,
  `Scripts/System/Services/convoy_service.gd`.
  - Two smaller defects found alongside, same file family:
    - `convoy_list_panel.gd::populate_convoy_list()` (`:172-173`) `queue_free()`s **all** children of
      `ConvoyItemsContainer` — including the `ResponsiveListAdapter` node that ships with the scene.
      The logs show it present on the first populate and **gone** on every later one. It never comes
      back, so mobile touch-target sizing silently stops being applied to that list.
    - Backend: `/user/get` for a 0-convoy account returns **no convoy-list key at all**, producing
      `[WARN] APICalls USER_CONVOYS: user payload missing convoy list keys` on every poll. The client
      already treats it as "no convoys", but the shape should be an empty array, not a missing key.
      Backend repo `~/Work/desolate_frontiers`.

## Beta support / platform

- [ ] **S12-5 · Feedback / Report-Bug must be reachable at ALL times during beta** *(P1)* — today it is
  reachable only from the main game screen, and it is blocked in exactly the two places bugs are most
  likely to be found. Four verified blockers:
  1. **Login.** The button lives in `UserInfoDisplay` (`Scenes/UserInfoDisplay.tscn:58 ReportBugButton`),
     which is inside `MainScreen`. `game_screen_manager.gd:26-29` sets `main_screen.visible = false`,
     `process_mode = PROCESS_MODE_DISABLED`, **and** `get_tree().paused = true` until
     `_on_initial_data_ready()`. There is no feedback affordance on `LoginScreen` at all.
  2. **Paused tree.** `_on_bug_report_pressed()` (`user_info_display.gd:483-508`) lazily creates
     `BugReportWindow` as a child of `get_tree().root` with the **default `PROCESS_MODE_INHERIT`**, so
     even if it were opened pre-login it would be frozen. It needs `PROCESS_MODE_ALWAYS`
     (the login screen already uses that pattern — `game_screen_manager.gd:28`).
  3. **Tutorial.** `tutorial_overlay.gd` gates input with full-screen shield Controls at
     `MOUSE_FILTER_STOP` (lines 138-157, 822-825) and sets itself to `STOP` in HARD mode (line 441),
     so every step blocks the top bar. Needs either a hole punched for the Feedback button or a separate
     always-on-top entry point above the overlay.
  4. **Modal/error states.** Same shape as (3) — anything that dims and captures input hides the button.
  **Good news from the research — the submit path itself is already global:** `submit_bug_report()`
  (`api_calls.gd:1164-1188`) POSTs to `/bug-report` with `_apply_auth_header()`, which is a **no-op when
  no token exists** (`api_calls.gd:458-468`), and `_collect_metadata()` (`bug_report_window.gd:518`)
  reads the user from the store **best-effort**. So a pre-login report will submit; it just arrives
  without user metadata. Only the *entry point* needs work, not the pipeline.
  **Suggested shape:** promote the button to a small always-on-top `CanvasLayer` above the tutorial
  overlay (and add it to `LoginScreen`), with `PROCESS_MODE_ALWAYS` on both the button and the window.
  `Scripts/UI/user_info_display.gd`, `Scripts/UI/bug_report_window.gd`, `Scripts/UI/login_screen.gd`,
  `Scripts/UI/game_screen_manager.gd`, `Scripts/UI/tutorial_overlay.gd`.
  (Docs: [BugReporting.md](04_Technical/BugReporting.md) — written 2026-07-28 for this item.)

- [ ] **S12-6 · Easy enter/exit fullscreen on PC** *(P2)* — there is **no keyboard shortcut**. Confirmed:
  `project.godot` has **no `[input]` section at all**, so no custom action exists, and a repo-wide search
  finds no `KEY_F11` / `KEY_ESCAPE` handler. The only control is the `FullscreenCheck` checkbox in the
  settings menu (`settings_menu.gd:4, 247, 258`), which writes `display.fullscreen` and lands in
  `settings_manager.gd:72-79`. Two further notes from the research:
  - It uses `DisplayServer.WINDOW_MODE_FULLSCREEN` (**exclusive**), not
    `WINDOW_MODE_EXCLUSIVE_FULLSCREEN`'s borderless sibling. **✅ Answered 2026-07-29: keep exclusive
    fullscreen** — but the reporter added *"we don't even have a way to toggle/change it,"* so **verify the
    existing `FullscreenCheck` checkbox actually works before adding the shortcut.** The wiring looks
    correct on paper (`settings_menu.gd:258` → `settings_manager.gd:72-79`), but S13-2 found that this
    panel is **built once and never re-synced** — so the checkbox can display the wrong state, and a click
    that appears to do nothing is the expected symptom of that bug. **Fix S13-2 first**, then re-test the
    checkbox; the shortcut may be the only thing genuinely missing.
  - The handler already calls `ui_scale_manager.reapply_scale()` **deferred** after the mode switch
    (`settings_manager.gd:76-79`) because the logical scale is derived from window size; **any new
    shortcut must route through the same setting**, not call `DisplayServer` directly, or the UI will
    keep the previous mode's scale and lay out offset.
  **Suggested shape:** add an `[input]` action (F11 + Alt+Enter on Windows/Linux, Cmd+Ctrl+F on macOS)
  handled once at a global level, which flips `display.fullscreen` via `SettingsManager.set_and_save()`
  so persistence and `reapply_scale()` come for free. `project.godot`,
  `Scripts/System/settings_manager.gd`, `Scripts/Menus/settings_menu.gd`.
  (Docs: [UserSettings.md § Display & fullscreen](04_Technical/UserSettings.md).)

- [ ] **S12-3 · Offer "connect an existing account" at the start of the tutorial (Steam)** *(P2)* — a new
  Steam player is currently forced through onboarding with no way to say "I already play this on
  Discord/mobile." Verified current flow and what exists to build on:
  - `login_screen.gd:282-306` offers **Continue with Steam** (desktop only, disabled when the Steam
    client isn't running). A first-time Steam login creates a fresh backend account.
  - The tutorial then auto-starts from `tutorial_manager.gd:187 _maybe_start()`. The gate is
    **server-side**: `metadata.tutorial` on the user. If that key is **missing**, the tutorial starts only
    when the convoy is at the `(0,0)` Tutorial City spawn (`_is_convoy_at_zero()`, line 160); if present,
    the server level wins. There is **no skip/opt-out branch** anywhere in `tutorial_manager.gd`.
  - **The linking machinery already exists** and is reusable — it is just buried post-login under
    Options → Connect Accounts (`user_info_display.gd:386, 437`), which opens `AccountLinksPopup`
    (`Scripts/UI/account_links_popup.gd`, a `CanvasLayer` at `layer = 100`). The 409-conflict merge path
    (`AccountMergeModal` → merge preview → `commit_merge` → session resync) is documented in
    [Identity.md § Account Linking & Merging](04_Technical/Identity.md).
  **Suggested shape:** surface an "I already have an account" branch at the point of first Steam sign-in
  (or as step 0 of the tutorial), reusing `AccountLinksPopup` / the merge flow rather than building a new
  path.
  **✅ Answered 2026-07-29 — use the merge path.** The reporter confirms *"we have extensive account
  consolidation that's already set up"* and asked that the existing machinery be used rather than a new
  flow. So: **link Steam onto the existing account, keeping the old progress** — the 409-conflict merge
  path that already exists, not a "log in as the other account and discard" branch.
  ⚠️ **Do a read-the-code pass on consolidation before designing the UI.** The reporter's instruction was
  *"check the docs for info on this, or start a research sprint to see how we do it and update the docs."*
  [Identity.md § Account Linking & Merging](04_Technical/Identity.md) is the doc of record and is
  `status: unverified` — so verify it against `account_links_popup.gd` / `account_merge_modal.gd` /
  `api_calls.gd`'s `/auth/merge/preview` + `/auth/merge/commit` (`:1044`, `:1094`) and set
  `verified_against_code:` as part of this item. That verification is a prerequisite for the UI work, and
  it feeds the **systems audit initiative** below rather than being throwaway effort.
  `Scripts/UI/login_screen.gd`, `Scripts/UI/account_links_popup.gd`, `Scripts/UI/account_merge_modal.gd`,
  `Scripts/UI/tutorial_manager.gd`.
  (Docs: [Identity.md § First launch on Steam](04_Technical/Identity.md#first-launch-on-steam--the-missing-i-already-have-an-account-branch),
  [TutorialSystemOverview.md](03_Systems/TutorialSystem/TutorialSystemOverview.md).)

---

# Sprint 13 — play-test batch (NEW, 2026-07-29)

From a desktop + Android play-test pass. Every entry was **researched against current code** before
being written down; each carries the verified mechanism (or the specific unknown to measure first), the
files, and — where the report and the code disagree — what the code actually says. **None are coded yet.**
IDs are `S13-n`.

> **Answers from the reporter (2026-07-29) are folded into each entry below.** Three items changed shape
> as a result: **S13-8 is shelved** (the test phone was offline — not a code bug), **S13-5 is a
> responsiveness item, not a data bug** (stock corrects on reopening the vendor), and **S13-7's design is
> now settled** — the backend auto-fills vehicles, so the client only needs a truthful *preview*, and it
> should fill **large vehicles first**.
>
> **Still worth reading before triaging:** S13-5 and S13-7 are the cargo twins of two already-solved
> vehicle bugs. The "sold vehicle reappears" saga was fixed with a re-strip list (`_sold_vehicle_ids` /
> `_strip_sold_vehicles`, `vendor_trade_panel.gd:2547-2585`) and per-item capacity has never been
> modelled. Reuse those shapes rather than inventing new ones.

## Performance

- [ ] **S13-1 · Fullscreen lag while stuck pre-login / in the background-art limbo** *(P1 — **macOS**,
  confirmed 2026-07-29: severe enough to stutter unrelated video playback on the same machine)* — reported
  as: in fullscreen, before login completes (or in the "only the background art" state), the machine lags
  badly. **The macOS confirmation reorders the suspects** — S12-7's blank screen is Windows-only and
  S12-8's request loop burns network, not GPU, so a symptom that degrades *other applications'* rendering
  points squarely at cause (1) below: a second full-screen render target with MSAA, redrawn every frame.
  Treat (1) as the fix and (2)/(3) as contributors. Three verified contributors:
  1. **The login screen renders a second full-screen viewport every frame, forever.**
     `login_screen.gd::_setup_map_background()` (`:694-700`) creates a `SubViewport` with
     `render_target_update_mode = UPDATE_ALWAYS`, `msaa_2d = MSAA_2X`, sized to the **whole viewport**
     (`:700`, re-synced on resize at `:746`), containing a 140×90 `TileMapLayer` (`_bg_map_size`, `:67`).
     `_update_map_background()` (`:869-890`) moves the camera **every frame** (drift + wobble), so nothing
     can ever be cached or culled. Cost scales with window area — which is exactly why it only bites in
     fullscreen. It is only torn down at `game_screen_manager.gd:75-76` (`login_screen.queue_free()` on
     `initial_data_ready`), so in the limbo state where that signal never arrives, it renders indefinitely
     **on top of** MainScreen's own map viewport.
  2. **The S12-8 request loop.** `_show_new_convoy_dialog()` firing hundreds of times per session —
     each iteration a `/user/get` request plus a full modal re-layout — is the same 0-convoy state being
     described here. It costs network and CPU, not GPU, so it can't be the whole story on macOS.
  3. **S12-7 (blank screen)** is the *Windows* form of the same limbo. On macOS the login screen simply
     never gets torn down because `initial_data_ready` never fires, which is enough to reproduce (1)
     indefinitely without S12-7 being involved at all.
  **Suggested shape:** drop the login background to `UPDATE_WHEN_VISIBLE`, cap `_bg_viewport.size` (render
  at a fraction of the window and let `STRETCH_KEEP_ASPECT_COVERED` upscale — it is already modulated to
  26 % alpha at `:690`, so resolution is nearly free to lose), drop `msaa_2d` entirely (MSAA on a 26 %-alpha
  blurred backdrop buys nothing), and set `render_target_update_mode = UPDATE_DISABLED` the moment
  `set_loading_mode(true, …)` is called rather than waiting for `queue_free()`. Consider also capping the
  frame rate on the login screen (`Engine.max_fps`) — a drifting backdrop does not need 120 Hz, and a cap
  is the single change most likely to stop the machine-wide stutter.
  **Measure first (macOS, fullscreen):** compare fullscreen vs. windowed FPS on the login screen. If the
  gap tracks window area, it is the viewport and the size cap alone fixes it.
  `Scripts/UI/login_screen.gd`, `Scripts/UI/game_screen_manager.gd`.

## Input / settings

- [ ] **S13-2 · Settings menu shows stale control values after a logout/login — pan toggle "flips on its
  own"** *(P2 — root cause found)* — reported as the panning setting changing periodically, "the setting
  isn't incorrect, it just flips between logging in and such." Reporter confirmed 2026-07-29 that the
  **displayed value** is what moves, which rules out the input-path sign theory and points at the menu.
  **Verified root cause — the settings panel is built once and never re-synced:**
  - `user_info_display.gd::_on_settings_button_pressed()` (`:541-556`) lazily instantiates
    `SettingsMenu.tscn` **once**, stores it in `_settings_menu_instance`, and parents it to
    `get_tree().root`. Every later open calls only `.show()` plus `_apply_mobile_optimizations()` — it
    refreshes **layout** but never **values**.
  - `settings_menu.gd` reads `SettingsManager` exactly once, in `_ready()` → `_init_values()` (`:27`,
    `:235-251`). There is **no** `visibility_changed` handler and no re-read on show (grep confirms
    neither exists).
  - The instance survives logout: `game_screen_manager.gd::logout_to_login()` (`:108-140`) recreates
    `LoginScreen` but **never frees `MainScreen`** — so `UserInfoDisplay` and its settings-menu instance
    persist across accounts, still displaying the values captured when it was first opened.
  So after a logout/login (or any change made while the menu was closed) the checkboxes can disagree with
  the stored settings — and the first click then writes the *checkbox's* stale-derived value back through
  `set_and_save()` (`:259-264`), which is the "it flipped by itself" the reporter is seeing.
  **Fix:** call `_init_values()` on show — either from `_on_settings_button_pressed()` before `.show()`, or
  (better, so every caller benefits) from a `NOTIFICATION_VISIBILITY_CHANGED` handler in
  `settings_menu.gd`. Small and self-contained.
  **Two related defects to fix in the same pass:**
  - **Reset Defaults silently clears pan/zoom inversion.** `_on_reset_defaults()` (`:294-307`) writes
    `controls.invert_pan = false`; a user resetting to fix UI scale loses their pan preference with no
    warning. Consider scoping Reset to the section, or confirming first.
  - **The four pan paths don't share a sign convention** — worth normalising while the file is open, even
    though it is no longer the suspected cause here. `main_screen.gd` inverts `delta` in four places
    (screen-drag `:571-577`, mouse-motion `:619-625`, `InputEventPanGesture` `:634-638`, plus the
    wheel/magnify zoom pair at `:606-616` and `:626-632`), and a macOS trackpad `InputEventPanGesture`
    does **not** carry the same sign convention as `InputEventMouseMotion.relative`. If direction ever
    differs between trackpad and mouse with the checkbox unchanged, this is why.
  `Scripts/UI/user_info_display.gd`, `Scripts/Menus/settings_menu.gd`, `Scripts/UI/main_screen.gd`.
  (Related: **TD-03** — `SettingsMenu` living outside `MenuManager` is what makes this lifecycle possible.)

- [ ] **S13-3 · Zoom sensitivity setting — desktop only** *(P3, new feature)* — **scope locked
  2026-07-29: desktop only; mobile pinch is explicitly out of scope for now.** Zoom step is a single
  hard-coded `@export var camera_zoom_factor_increment: float = 1.1` (`map_camera_controller.gd:11`),
  consumed by the wheel handlers in `main_screen.gd:606-616`. Note that on desktop **two** paths matter:
  the mouse wheel (`:606-616`, which uses the increment) and `InputEventMagnifyGesture` (`:626-632`, the
  macOS trackpad pinch, which passes the OS factor straight through and would ignore an increment-only
  setting). Both must honour the slider or it will read as broken on a MacBook. Touch pinch (`:555-566`)
  is left alone per the scope decision.
  **Suggested shape:** add `controls.zoom_sensitivity` (float, default `1.0`, range ~0.25–3.0) to
  `settings_manager.gd`'s `data` dict, cache it in `main_screen.gd::_apply_settings_snapshot()`
  (`:1655-1662`) alongside `_opt_invert_zoom`, add its key to the `_on_setting_changed()` match
  (`:1664-1670`), and apply it as an **exponent** — `pow(factor, sensitivity)` — so wheel and magnify
  scale consistently and `1.0` is exactly today's behaviour. Slider goes in the Controls section of
  `SettingsMenu.tscn` next to Invert Zoom; hide the row on mobile (`DeviceStateManager.is_mobile`) so a
  no-op control never ships to phones. **Whatever value it lands on must be re-read on menu reopen — see
  S13-2**, or the new slider inherits the same stale-display bug on day one.
  `Scripts/System/settings_manager.gd`, `Scripts/Menus/settings_menu.gd`, `Scenes/SettingsMenu.tscn`,
  `Scripts/UI/main_screen.gd`, `Scripts/Map/map_camera_controller.gd`.

- [ ] **S13-4 · "Toggle journey lines" should be a persisted setting** *(P3)* — the convoy route/connector
  polylines are drawn unconditionally in `UI_manager.gd` (`:2049-2051` for real journeys, `:2150-2152` for
  the route preview); there is **no** toggle for them today. The six existing map overlays all go through
  one well-formed pipeline that this should join, not bypass: a field + `update_setting()` case in
  `map_settings_service.gd` (`:12-17`, `:43-66` — which persists via `SettingsManager` as
  `map.<name>` and broadcasts `map_overlay_settings_changed`), a default in `settings_manager.gd:22-27`,
  a `_add_toggle_row()` + `toggled` connection in `map_overlay_settings_panel.gd` (`:265-301`), a line in
  `_sync_toggles_with_service()` (`:360-367`), and consumption in
  `UI_manager.gd::_on_map_overlay_settings_changed`.
  **Design locked 2026-07-29:** the toggle lives in the **map overlay gear panel** (not Settings) and
  governs **all convoys' journey lines**; the **selected convoy's** line shows **automatically** while it
  is on a journey, regardless of the toggle. So this is not a global on/off — it is
  `show_all_journey_lines`, with the selected/active convoy's route unconditionally drawn. Consequences
  for implementation:
  - The consumer in `UI_manager.gd` (`:2049-2051`) must branch per convoy: draw if
    `setting == true` **or** the convoy is the selected one. The selection state is already available —
    the same function tests `p_selected_convoy_ids` / `_pinned_convoy_ids` for label visibility
    (`convoy_label_manager.gd:429`), so reuse that notion of "selected" rather than inventing a second one.
  - Because the selected convoy is always drawn, `set_planning_override()` (`:80-88`) should **pass these
    through** like `grid_lines` rather than suppressing them — the route preview lines (`:2150-2152`) are
    a separate path and already handled.
  - Default: recommend **off** for all-convoys (matching the other six overlays, which all default
    `false`), since the selected convoy's line still appears. Confirm if you'd rather it default on.
  `Scripts/System/Services/map_settings_service.gd`, `Scripts/UI/map_overlay_settings_panel.gd`,
  `Scripts/System/settings_manager.gd`, `Scripts/UI/UI_manager.gd`.

## Vendor / trading

- [ ] **S13-5 · Vendor stock doesn't decrement *immediately* after a purchase** *(P2 — downgraded
  2026-07-29: reporter confirmed it corrects on leaving and re-entering the vendor, so this is a
  **responsiveness** bug, not data loss. "I just want it responsive.")* — bought 7 × Industrial Robotic
  Arms; the vendor's quantity did not go down until the panel was reopened. **That the reopen fixes it is
  diagnostic:** the authoritative `/vendor/get` refresh is correct, so the defect is entirely in the
  optimistic path — and it narrows the two candidates below to whichever fails *before* the refresh lands.
  The optimistic path exists but is **shallow and name-keyed**:
  `_optimistically_update_vendor_stock(item_name, delta)`
  (`vendor_trade_panel.gd:2501-2545`) looks the item up by its **display name** across the `vendor_items`
  buckets and writes **only** `entry["total_quantity"]`. Two independent failure modes, and the existing
  diagnostics tell you which:
  - **Lookup miss** — the name in `_pending_tx.item.name` doesn't match the bucket key (aggregated rows
    are keyed by display name, which the aggregator can decorate). The function already prints
    `[VendorPanel][DIAG] FAILED: item '…' not found in any bucket. Buckets searched: …` (`:2545`) —
    that line settles it in one purchase.
  - **Re-aggregation resurrects it** — even on a successful decrement, the underlying
    `vendor_data.cargo_inventory` and `entry["items"]` are left untouched, so any rebuild off the
    **lagging `/map` snapshot** restores the original quantity. This is precisely the sold-vehicle saga,
    which was fixed by remembering the id and re-stripping on every rebuild
    (`_sold_vehicle_ids` / `_strip_sold_vehicles`, `:2547-2585`); cargo has **no** equivalent.
  **Suggested shape:** switch the decrement to key off `cargo_id` (which `dispatch_buy` already has —
  `vendor_panel_transaction_controller.gd:264-266`) rather than the display name, mutate the underlying
  inventory rows too, and add a cargo counterpart to `_strip_sold_vehicles` so a `/map`-driven rebuild
  can't undo it before the authoritative `/vendor/get` lands.
  `Scripts/Menus/vendor_trade_panel.gd`, `Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd`,
  `Scripts/Menus/VendorPanel/cargo_aggregator.gd`.
  (Related: the `/map`-snapshot-lag mechanism is [DataBoundaries.md](04_Technical/DataBoundaries.md).)

- [ ] **S13-6 · Buy button stuck on "Processing…" after a failed purchase** *(P1)* — the button text and
  `disabled` state are set in `vendor_panel_transaction_controller.gd:200-204` and restored **only** by
  `VendorPanelRefreshController.on_api_transaction_error()` (`:78-115`) or a successful result. Two
  verified holes:
  - **The error handler early-returns before restoring the button.** `:80-81` is
    `if not panel.is_visible_in_tree(): return` — placed *above* the money/capacity revert and the
    button restore at `:96-101`. Any panel that isn't visible when the error lands (orientation change,
    menu swap, tutorial overlay) keeps `disabled = true` and `"Processing…"` when it comes back.
  - **There is no watchdog.** `_pending_tx.started_ms` is written (`:190`) and **never read anywhere in
    the repo** — grep confirms exactly one occurrence. So a request that errors without emitting, times
    out, or returns a 200 with a failure body leaves `_transaction_in_progress = true` forever, and
    `on_action_button_pressed()` (`:120-121`) then rejects every subsequent press silently.
  **Suggested shape:** move the button/flag restore **above** the visibility guard (state repair must be
  unconditional; only the *toast* should be visibility-gated), and add a timeout using the already-recorded
  `started_ms` that reverts the projection and re-enables the button. `_pending_tx.started_ms` becoming a
  live field is the point of the fix, not incidental.
  `Scripts/Menus/VendorPanel/vendor_panel_refresh_controller.gd`,
  `Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd`, `Scripts/Menus/vendor_trade_panel.gd`.

- [ ] **S13-7 · "Max" over-buys because it models the convoy as one pooled container** *(P1 — design
  settled 2026-07-29)* — reported as the purchase overflow not working: maxing out an item sometimes won't
  split across the vehicles.
  **Division of responsibility (confirmed by the reporter):** the **backend already auto-fills vehicles**
  as much as they can hold. The client is not responsible for placing cargo — only for **predicting how
  much will actually fit**, and today it does that with pooled arithmetic. So this is a *preview accuracy*
  fix, not a packing feature.
  **Verified cause:** `on_max_button_pressed()` (`vendor_panel_transaction_controller.gd:9-116`) computes
  its weight/volume ceilings from **convoy aggregates** —
  `remaining_volume = _convoy_total_volume - _convoy_used_volume` (`:103-108`), themselves derived from
  `total_cargo_capacity` / `total_free_space` (`vendor_panel_convoy_stats_controller.gd:22-36`). Pooled
  capacity is a fine approximation **only while items are small relative to a vehicle** — which is exactly
  the reporter's observation: *"a lot of times they are aligned, but with big items and multi-vehicle
  convoys it won't."* The unit that breaks it is **indivisibility**: a single item cannot be split across
  two vehicles, so 40 m³ of free space spread over four vehicles cannot accept one 15 m³ item.
  Two aggravators in the same function: `max_quantity = max(1, max_quantity)` (`:115`) forces a quantity of
  **1 even when nothing fits at all**, and both `unit_weight` and `unit_volume` silently fall back to `0.0`
  (`:80-101`), which disables that constraint entirely (`:105-108` guard on `> 0.0`) rather than failing loud.
  **Suggested shape — greedy simulation, large vehicles first** (the reporter's stated priority: *"we should
  prioritize large vehicles being filled first"*):
  1. Build a per-vehicle free-space list from `convoy_data.vehicle_details_list` — per-vehicle
     `cargo_capacity` / `weight_capacity` are already read in `inspector_builder.gd:379-412`, and the
     per-vehicle used totals are already summed at `vendor_panel_convoy_stats_controller.gd:47-54`.
  2. Sort **descending by free volume** and place units one at a time into the first vehicle that fits
     (first-fit over a largest-first ordering). Count how many placed → that is the true max.
  3. When the answer is 0, **disable Buy with a reason** ("no single vehicle has room for this item")
     instead of offering a quantity of 1 that the server will reject.
  ⚠️ **Backend alignment is part of this item, not a prerequisite.** The client simulation and the server's
  auto-fill must use the **same ordering**, or the preview will still disagree at the margin — and the
  reporter has asked for largest-first, which may mean changing the *server's* order too, not just
  matching it. Confirm the server's current fill order and align both to largest-free-first.
  Backend repo `~/Work/desolate_frontiers`.
  `Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd`,
  `Scripts/Menus/VendorPanel/vendor_panel_convoy_stats_controller.gd`.

## Android

- [ ] **S13-8 · 🅿️ SHELVED — Android "can't log in" was almost certainly an offline test device**
  *(shelved 2026-07-29 by the reporter: "I think I'm offline on this new testing phone — we can shelf this
  until I re-test." Re-open only if it reproduces on a device with confirmed connectivity.)* — kept because
  the diagnosis is worth not re-deriving: every request failed with `HTTPRequest` **result code 3 =
  `RESULT_CANT_RESOLVE`** — `/auth/me`, `/map/get`, `/auth/discord/url` (×4) **and** the `/bug-report`
  POST (`HTTP 0`). A resolve failure across *every* endpoint means the device never reached a TCP
  connection, so no auth code was ever implicated, and `permissions/internet=true` is set on **both**
  Android presets (`export_presets.cfg`, Android preset line 834 / Play Store line 1060) — never the
  manifest. **On re-test:** load `https://df-api.oori.dev:1337/auth/me` in the device's own browser first.
  If that fails too, it is the device's network; nothing in the game is broken.
  - ✅ **Split out and still worth doing regardless — see S13-12.** The real client-side defect the logs
    exposed was not the network failure but that every one of those lines printed as
    `Unhandled API Error (add to ErrorTranslator)`.

- [ ] **S13-12 · `HTTPRequest` result codes are missing from `ErrorTranslator`** *(P2 — split out of
  S13-8, 2026-07-29; independent of whether the Android device was offline)* — a network-level failure
  currently surfaces to the player as raw internals. Every line in the Android log read
  `Unhandled API Error (add to ErrorTranslator): … Request failed with HTTPRequest result code: 3`, and
  the bug-report path produced `Bug report submit failed (HTTP 0): Unknown error.` The result codes are a
  small fixed enum and the messages write themselves — `RESULT_CANT_RESOLVE` / `RESULT_CANT_CONNECT` /
  `RESULT_CONNECTION_ERROR` / `RESULT_TIMEOUT` all collapse to "Can't reach the server — check your
  connection", and `RESULT_TLS_HANDSHAKE_ERROR` deserves its own message. This is the highest
  value-per-line item in the sprint: it turns every future network outage — on any platform — from an
  unhandled-error log line into a sentence the player understands.
  `Scripts/System/error_translator.gd`, `Scripts/System/api_calls.gd`.
  (Docs: [ErrorSystem.md](04_Technical/ErrorSystem.md), [Diagnostics.md](04_Technical/Diagnostics.md).)

- [ ] **S13-9 · Android export config noise: Apple plugin + Steam both load on Android** *(P3 — not the
  cause of S13-8, but it pollutes every Android log)* — two startup errors precede the network failures
  and neither should occur on Android:
  - `GDExtension: No "arm64" library found for … GodotApplePlugins/godot_apple_plugins.gdextension` —
    the Apple plugin has no Android library and shouldn't be loaded there. Fix in the `.gdextension`
    (platform-scoped entries) or exclude the addon from the Android presets' export filter.
  - `[SteamManager] steam_appid.txt not found` → `Steam failed to initialize: steamInit returned false`.
    Harmless (it fails closed) but it means `SteamManager` runs its init on mobile at all. It should
    no-op behind an `OS.has_feature("pc")`-style guard so the errors stop being logged as errors.
    Note this interacts with the existing Steam-vs-iOS rule — see
    [Deployment § GodotSteam disabled-at-rest](04_Technical/Deployment.md) before touching the plugin's
    enabled state (a Godot restart silently re-enables GodotSteam).
  `export_presets.cfg`, `addons/GodotApplePlugins/godot_apple_plugins.gdextension`,
  `Scripts/System/steam_manager.gd`.

## Polish

- [ ] **S13-10 · Small animation when a settlement label is pinned** *(P4, new feature)* — pinning is a
  pure state flip today: `UI_manager.gd:577-583` toggles membership in `_pinned_settlement_coords` and the
  label simply appears on the next `_draw_interactive_labels()` pass. There is a natural place to hang a
  tween: `UI_manager::_process()` (`:295-320`) **already redraws labels every frame while the camera moves
  or the zoom lerps** and already smooths zoom via `_display_zoom` / `zoom_lerp_speed`. **Suggested shape:**
  store a pin timestamp per coord, drive a short scale/alpha ease from it in the existing draw path, and
  keep `_process` awake while any pin animation is in flight (add the condition to the early-out at
  `:301-302`). Do **not** add a `Tween` on the label node — labels are rebuilt every frame by that draw
  path, so a node tween would be discarded. `Scripts/UI/UI_manager.gd`.

- [ ] **S13-11 · Journey confirmation screen shows a duration but no arrival clock time** *(P3 — screen
  pinpointed 2026-07-29: the **journey confirmation** screen, not the convoy selector)* — **exact
  location found:** `convoy_journey_menu.gd::_show_confirmation_panel()` reads
  `eta_minutes = route_data.get("delta_t", 0.0)` (`:1414`), formats it through `_format_travel_time()`
  (`:1188-1196` → `"18.5 h"` / `"2d 3.5h"`) and passes that single string to `_update_sub_header()`
  (`:1418`). So the sticky sub-header carries **distance + duration** and no wall-clock arrival.
  **Suggested shape:** the journey hasn't departed yet, so arrival = `Time.get_unix_time_from_system() +
  eta_minutes * 60`. Feed that through the existing
  `DateTimeUtil.format_timestamp_display(ts, include_remaining_time)` (`date_time_util.gd:103`) — the same
  helper already used by the active-journey ETA row (`convoy_journey_menu.gd:279`) and the map labels
  (`convoy_label_manager.gd:310-318`), so the confirmation screen will match the wording the player sees
  once the journey starts. Show **both** (`"18.5 h · arrives 4:15 PM"`); the duration is what makes routes
  comparable, the clock time is what makes it plannable. Note `format_timestamp_display` already
  day-qualifies long trips (`omit_date_if_today`), which matters here — a `2d 3.5h` route must not display
  a bare time-of-day. `Scripts/Menus/convoy_journey_menu.gd`, `Scripts/System/date_time_util.gd`.
  - Worth doing in the same pass: `route_selection_menu.gd:98-99` sets
    `eta_value.text = str(_route_data.get("eta", "N/A"))` — a **raw, unformatted** value straight into the
    label, the only ETA display in the project that bypasses `DateTimeUtil`.

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

**Sprint 12 — verification recipes** *(pre-written; check these off as each item lands)*

These are **desktop/PC-first** — S12-1, S12-4 and S12-6 cannot be proven on a phone, and S12-4 is
reported as Windows-specific, so the Mac editor is a smoke test only, not the gate.

- [ ] **S12-1 · Vendor page on a wide monitor** *(desktop, ≥ 2560px wide, and again at 1920)* — open a
  settlement vendor. The menu sheet must stop growing past its new absolute cap (it should **not** keep
  tracking 60 % of the monitor), and the three columns must stay proportionate — the 320px transaction
  column must not read as a thin strip beside a sprawling list. Re-check at `ui.menu_open_ratio`
  min **and** max. *Old:* menu = 0.60 × full width with no absolute cap.
- [ ] **S12-2 · Vendor sort options** *(desktop + portrait)* — open the Sort dropdown on a vendor **with**
  delivery cargo and one **without**. No empty row; the currently-active order is represented by a checked
  entry. If a new entry was added at index 0, confirm a player with a **pre-existing** saved
  `ui.cargo_sort_metric` still gets the sort they had, not a silently shifted one.
- [ ] **S12-3 · Existing-account branch on Steam** *(Steam build, fresh Steam account)* — first sign-in
  offers "I already have an account"; taking it reaches the link/merge flow and the tutorial does **not**
  force-start afterwards. Declining it behaves exactly as today.
- [ ] **S12-4 · Overlay options panel on PC** *(Windows first, then Mac)* — expand the gear panel at
  `ui.scale` **1.0, mid, and max**. It must stay a sane fraction of the width at every scale and must not
  be a full-height slab. Capture the `[UIScale] win=… factor=… target_w=… vp=…` line at each setting and
  paste it into the fix's commit — that line is the before/after proof.
- [ ] **S12-5 · Feedback reachable everywhere** *(all platforms; PC is the priority)* — hit Feedback
  **(a)** on the login screen before signing in, **(b)** mid-tutorial on a step with a highlight, **(c)**
  with a menu open, **(d)** with an error modal up. In each case the window opens, is **interactive**
  (not frozen by `get_tree().paused`), and submits. The pre-login report should arrive with no user
  metadata but must not error.
- [ ] **S12-6 · Fullscreen shortcut** *(Windows + Mac)* — press the shortcut to enter fullscreen and again
  to leave. The UI must re-lay-out correctly both ways (no offset — this is the failure mode
  `reapply_scale()` exists to prevent), the settings-menu checkbox must reflect the new state, and the
  state must survive a restart.
- [ ] **S12-7 · Blank screen on first Steam launch** *(EXPORTED STEAM BUILD ONLY — the editor cannot
  prove this)* — export, launch via Steam with a Steam account **not** linked to a DF account. The top
  bar and map must render normally. Then check `user://logs/godot*.log`: `[RESIZE] map_rect` must have a
  **non-zero height** with y ≈ the top-bar height (80–160), and there must be **no `[MAP-RECT-DIAG]`
  block**. *Old:* `map_rect=[P: (0.0, 1610.136), S: (2133.0, 0.0)]` — zero height, pushed below a
  1338-tall viewport, leaving only the top bar's Oori tile on screen. If it still fails, the new
  `[MAP-RECT-DIAG]` dump names the control claiming the height — paste it into the issue.

---

# Backlog

Not blocking the sprints above. Pull into a sprint when the relevant file is open.

> [!NOTE]
> **IDs are the join key.** Reference docs cite these (`BUG-01`, `TD-04`, …) instead of restating the
> issue — see [AI_Guidelines § 6](04_Technical/AI_Guidelines.md). Duplicated status is duplicated
> staleness: two UIAudit blocks were found describing bugs that had already been fixed. **Never delete
> an ID** — mark it done and leave it, so existing citations keep resolving.

## Bugs

- **BUG-01 · Right-side map panel clips off the screen edge (landscape)** — a settlement-preview / vendor **UI panel** (rows like `S / Wa / Cargo…`, with green category buttons) that floats on the right of the map clips off the **right** screen edge. Distinct from the map-label clipping fixed in Sprint 9 A5 (that was *labels*; this is a screen-space panel). Needs a pinpoint of which panel it is (tap it — vendor vs settlement preview) and then a safe-area / max-width fit. Spotted during the 2026-07-21 device pass.
- **BUG-02 · Convoy name label (P5)** — floats unanchored above the panel; integrate as a styled header. `convoy_menu.gd` TitleLabel.
- **BUG-03 · Resource-bar text contrast (P6)** — low contrast at high fill; add outline or bump font weight. `convoy_menu.gd` ResourceStatsHBox.
- **BUG-04 · HSeparators near-invisible (P8)** — on dark bg, replace with section labels or themed dividers.

## Polish / UX

- **UX-01 · Vendor action buttons live on the selected item** — move all action buttons (buy / sell / etc.) into the selected item's row/inspector in the vendor menu, rather than a separate/global control area. `vendor_trade_panel.gd` / `vendor_item_list.gd`.
- **UX-02 · Global spacing consistency (P9)** — `UITheme.SPACE_*` tokens exist but adoption is incomplete.
- **UX-03 · Settlement vendor browse (map preview)** — full read-only inventory list when viewing a settlement without a convoy. Currently shows name + "deals in" summary only. Follow-up to Sprint 5.5.
- **UX-04 · Convoy stats backend verification** — breakdown modal (`convoy_menu.gd`) shows computed aggregate (min for speed/offroad, average for efficiency) alongside the backend total. Backend formula not yet confirmed — verify on device.

## Tech Debt

- **TD-01** · Duplicate Oori palette `const`s in `user_info_display.gd`, `convoy_settlement_menu.gd`, `convoy_list_panel.gd` — migrate to `UITheme.*`.
- **TD-02** · Modals use hardcoded absolute center offsets — `auto_sell_receipt_modal`, `returning_player_tips_modal`, `premium_upgrade_modal`; replace with `CenterContainer`.
- **TD-03** · `SettingsMenu` opened outside `MenuManager` (CanvasLayer layer=100) — lifecycle inconsistency.
- **TD-04** · `UserInfoDisplay` height changes not signaled → stale `offset_top` on submenus.
- **TD-05** · `main_screen.gd` wires convoy button via fragile `find_child()`.
- **TD-06** · S/M/L UI-scale preference silently overridden in portrait.

## Testing

- **TEST-01 · Tutorial-flow smoke coverage** — `Scripts/Debug/wiring_smoke_test.gd` only asserts autoload wiring today. Extend it toward tutorial-flow coverage (step build, resolver resolution per level) so a hub/menu rename can't silently break onboarding. Sprint 8 shipped on a manual portrait/landscape/desktop pass instead.

## Docs / data hygiene

- **DOC-01 · Data dumps are stale but intentionally kept — do NOT purge.** Reviewed 2026-07-21: `docs/99_Reference/data_dumps/{cargo,vendor,vehicle,part}_example.json` are point-in-time (Feb 2026, pre-`base_efficiency` rename), but the README already caveats them, they're indexed, and they still document object **shape** correctly. `tutorial_steps.json` is likewise explicitly documented as "shape only." The lightweight improvement, if desired, is to **regenerate** the four stale JSONs from prod (needs `~/Work/desolate_frontiers` + adminer tunnel), not delete them. `dump_3920_convoy_…json` is the only deletion candidate, and only once the vendor-efficiency investigation is fully closed.

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

> [!TIP]
> **The doc-side structural work is already done** — see [DocumentationAudit.md](DocumentationAudit.md)
> (2026-07-28). Phase 1 shipped: `tools/docs_check.py` runs in CI, every doc carries `status:` +
> `updated:`, and the tag/index/link contracts are enforced. **The drift audit below now has a concrete,
> ranked worklist instead of "walk everything":**
>
> ```bash
> python3 tools/docs_check.py --backlog
> ```
>
> 75 docs are `status: unverified`, ranked by inbound link count so the most-depended-on get checked
> first. Set `verified_against_code:` + `status: current` as you clear each one.

Scope to define, but the known threads:
- **Doc ⇄ code drift audit** — walk the `--backlog` queue against current code; correct stale `file:line`
  refs and status claims. Prioritize the docs agents read first (onboarding, project map, UI audit).
  - ⚠️ **Already found while wiring up the checker (2026-07-28):** `04_Technical/AI_Guidelines.md`
    prescribed a `_get_font_size()` runtime **boost** multiplier — a pattern the Law of Logical Pixels
    forbids — and claimed all `Label`s should use MSDF fonts, while the project font imports with
    `multichannel_signed_distance_field=false`. Both corrected. This is the shape of drift the sweep
    should expect in the other agent-facing docs.
  - ⚠️ **Related code finding:** the font-scale migration is **less complete than recorded**. Runtime
    `boost` multipliers still exist in `Scripts/UI/convoy_list_panel.gd:359`,
    `Scripts/UI/tutorial_overlay.gd:167`, and `Scripts/UI/responsive_list_adapter.gd:15-16,193`
    (`discord_popup.gd` is already migrated, contrary to earlier notes). Fold into the sweep.
- **Dead-code / retired-flow sweep** — the tutorial-tab cleanup (Sprint 10) showed how much orphaned
  machinery accumulates; do a systematic pass for other retired paths (legacy settlement menu vs hub,
  old vendor flows, disabled loaders like the tutorial JSON path).
- **Backend / DF_Lib contract re-verification** — regenerate the stale data dumps from prod and confirm
  the binary `/map` wire format (DF_Lib) still matches the backend serializers; the efficiency and
  sold-vehicle sagas both trace to `/map` snapshot lag. See [data_dumps README](99_Reference/data_dumps/README.md) *(agent memory: `reference_backend_repo_and_stale_dumps`)*
  and [DF_Lib case study](04_Technical/DF_Lib.md#case-study-the-vanishing-vehicle-efficiency-stat) *(agent memory: `reference_vendor_efficiency_binary_serializer`)*.
- **System inventory** — enumerate the current live systems (menus, services, autoloads) and mark which
  are current, which are transitional, and which are candidates for retirement.

*(This section is a placeholder for the initiative's plan — expand into concrete work items before starting.)*
