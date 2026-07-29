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

> **Status (2026-07-28):** Sprints 1–10 are complete / code-complete. Outstanding work is now three
> buckets: (1) the **device-test round 2** pass (checklist below), (2) **Sprint 11 — QOL bug batch**
> (2026-07-22, mostly uncoded), and (3) **Sprint 12 — Steam beta batch** (NEW, 2026-07-28) covering
> desktop/PC layout ratios, vendor-panel widescreen fit, always-available feedback, a fullscreen
> shortcut, and a "connect an existing account" branch at first Steam launch. After those, the project
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
  **Suggested shape (confirm ceiling with the user before hard-coding):** add a real `DESKTOP` branch to
  `_get_menu_ratios()` plus an **absolute** max width in logical px, and let the vendor columns rebalance
  (or cap total content width and centre it) above that width.
  `Scripts/UI/main_screen.gd`, `Scripts/Menus/vendor_trade_panel.gd`, `Scenes/VendorTradePanel.tscn`.

- [ ] **S12-4 · Overlay options panel eats a large proportion of the screen on PC** *(P1 — PC only; Mac
  and mobile "fine for the most part")* — the gear-tab map-overlay panel
  (`Scripts/UI/map_overlay_settings_panel.gd`). Two verified causes: a **flat `440.0` desktop width** with
  no viewport-fraction cap (`_get_panel_width()`, line 46 — the only branch not expressed as a fraction),
  and **`ui.scale` shrinking the logical viewport out from under it** (23 % of width at `ui.scale 1.0`,
  ≈46 % at 2.0). Compounded by `_content_panel.size_flags_vertical = SIZE_EXPAND_FILL` (line 219), so it's
  always full screen height. Full mechanism + math:
  [ui_system § Desktop scaling contract](02_UI_UX/ui_system.md#desktop-scaling-contract-and-why-fixed-width-panels-drift).
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
  `/user/get` and re-lays-out the modal every time. Make the prompt idempotent — no-op when the dialog
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
    `WINDOW_MODE_EXCLUSIVE_FULLSCREEN`'s borderless sibling — worth confirming which the beta wants on
    Windows, since exclusive mode is the harder one to escape from if the UI is mis-laid-out.
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
  path. **Open question for the user:** should this *link Steam onto the existing account* (merge, keeping
  the old progress) or *log in as the existing account* (discard the just-created Steam account)? The
  merge path is the one that already exists in code.
  `Scripts/UI/login_screen.gd`, `Scripts/UI/account_links_popup.gd`, `Scripts/UI/account_merge_modal.gd`,
  `Scripts/UI/tutorial_manager.gd`.
  (Docs: [Identity.md § First launch on Steam](04_Technical/Identity.md#first-launch-on-steam--the-missing-i-already-have-an-account-branch),
  [TutorialSystemOverview.md](03_Systems/TutorialSystem/TutorialSystemOverview.md).)

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
