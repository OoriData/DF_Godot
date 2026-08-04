---
type: note
tags:
  - kind/process
  - status/unverified
aliases:
  - "TODO — Active Work"
created: 2026-05-21
updated: 2026-08-04
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
> **Update 2026-07-31 — eight items coded in one pass, none device-verified.** Closed: **S12-5**
> (feedback everywhere), **S12-6** (fullscreen shortcut), **S12-8** (onboarding loop + the
> `ResponsiveListAdapter` defect), **S13-1** (login-screen viewport cost), **S13-2** (stale settings
> menu), **S13-12** (`HTTPRequest` result codes), the **desktop pinned-label preview arrow** (which is
> what the mis-titled "settlement warehouse inspection" entry actually was — the warehouse path was
> never broken), and Sprint 11's **pan-invert** item (a duplicate of S13-2).
> ⚠️ **All eight are compile-checked and headless-tested only.** Four carry named, unmet verification
> requirements — the S12-6 window-mode switch, S12-5's placement/hit-testing, and S12-8 + S13-1, which
> both need a **0-convoy account**. S13-1's FPS measurement remains untaken, so how much pre-login lag
> S12-8 accounted for is still unknown. Read each entry's ⚠️ block before assuming any of them is done.
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

- [x] **Pinned map label → settlement preview arrow does nothing on desktop (label just vanishes)**
  *(P1 — ✅ CODE-COMPLETE 2026-07-31, compile-checked, pending desktop verification. ⚠️ **RE-SCOPED
  2026-07-31: this entry previously described the wrong bug** — see the closed warehouse entry below.)* —
  **Reporter description:** *"After a settlement gets pinned, we should be able to hit an arrow that opens
  the settlement preview page. This works on mobile but on desktop the label just disappears."*
  **Verified root cause — one missing branch, in the mouse path only.** The "arrow" is not a Button: it is
  a trailing `"  ›"` appended to the pinned label's text (`UI_manager.gd:1532-1536`), and the panel is
  `MOUSE_FILTER_IGNORE` (`:997-999`), so the whole panel is hit-tested manually by
  `_get_settlement_panel_at_screen_pos()` (`map_interaction_manager.gd:390-434`). **Two call sites hit-test
  it; only the touch one checked the pin state:**
  - **Touch** — `_handle_tap_interaction()` (`:365-375`): pinned → `settlement_preview_requested`,
    otherwise → `settlement_clicked` (which pins it). Correct.
  - **Mouse** — `_handle_lmb_interactions()` (`:777-782`): emitted `settlement_clicked`
    **unconditionally**. That routes to `UI_manager::toggle_settlement_pin()` (`:570-582`), so clicking the
    chevron on an already-pinned label **un-pinned it** — and since the label was only being drawn
    *because* it was pinned, it vanished on the next `_draw_interactive_labels()` pass. Exactly the
    reported symptom. `settlement_preview_requested` was emitted from **one** line in the whole repo
    (`:372`), so no mouse path could ever open the preview.
  **✅ Fix 2026-07-31** — mirrored the pinned check into the LMB branch, so both input paths share the
  same two-state behaviour (unpinned click pins; pinned click previews).
  **Ruled out during the investigation** (recorded so it isn't re-derived): no mouse-motion/exit handler
  clears pins (`handle_map_input:214-219` only stores the motion event; `_update_hover:535` never touches
  `_pinned_settlement_coords`); the hover-clear at `:344-346` is inside the touch path and clears
  `_current_hover_info`, not pins; and hit-test sizing is identical for both paths (same 12-world-unit
  grow at `:423`) — the mobile radius bump at `:108-110` affects tile/convoy hover, not the panel rect.
  `Scripts/Map/map_interaction_manager.gd`, `Scripts/UI/UI_manager.gd`, `Scripts/UI/main_screen.gd`.
  (Related: **UX-03** — the settlement preview's read-only vendor browse.)

- [x] **Settlement warehouse inspection broken (regression)** — *(✅ **CLOSED 2026-07-31 — NOT A CODE BUG.**
  The original premise was wrong; the reporter's actual symptom is the pinned-label item directly above.
  Kept per the never-delete-an-ID rule.)* — the ability to **inspect a settlement for warehouses** was
  reported as no longer working, presumed broken by the Sprint 5.5 hub pivot.
  **What the research actually found:**
  - **The canonical path is wired end-to-end.** Convoy overview → Settlement nav → **Settlement Overview
    Hub** → **Warehouse card** (`settlement_overview_menu.gd::_make_warehouse_card`, built in
    `_build_resources_and_warehouse_row`, `:540-606`) → `_on_warehouse_pressed()` (`:728-739`) emits
    `open_warehouse_menu_requested` → `menu_manager.gd:696-698` connects it (for both `settlement_overview`
    **and** `settlement_hub` menu types) → `open_warehouse_menu()` (`:352-355`) → `WarehouseMenu.tscn`.
    The card's `gui_input` is connected unconditionally — not gated behind a dead condition.
  - `warehouse_menu.gd`'s `@onready` node paths all resolve against `Scenes/WarehouseMenu.tscn`, and the
    `WarehouseService` autoload (`project.godot:39`) exposes every method the menu calls.
  - **No commit since 2026-07-28 touched** `menu_manager.gd`, `settlement_overview_menu.gd`, or
    `warehouse_menu.gd` — `ddb9ba0` and `4ca65a6` only touched `convoy_settlement_menu.gd` / vendor files.
  - **✅ A real stale doc was found and fixed** (2026-07-31): [UIAudit § Warehouse Menu](02_UI_UX/UIAudit.md)
    said *"Opens from: Settlement menu → 'Warehouse' button"* — the **pre-Sprint-5** button, deliberately
    removed (`convoy_settlement_menu.gd:134-135`, *"Warehouse button removed in Sprint 5"*). Anyone
    following that line would look for a control that no longer exists and reasonably call it broken.
    **This is the leading explanation for the report.**
  **✅ Resolved by asking, not by coding.** The pinpoint-first question ("which control, and did it not
  appear / not respond / open empty?") returned a description of an entirely different screen — the map's
  pinned settlement label, not the hub's warehouse card. **The hub warehouse path was never broken.** Worth
  recording as a cheap win for the pinpoint-first rule: the research below would have been wasted effort
  had it been followed by a speculative fix.
  **If a warehouse-specific failure ever does surface**, the next suspect is not the wiring but
  `_resolve_settlement_from_convoy()` (`settlement_overview_menu.gd:74-98`) failing to resolve
  `_settlement` for a particular convoy/tile shape — set `_debug_settlement_overview = true` (`:17`) and
  capture the log. `Scripts/Menus/warehouse_menu.gd`,
  `Scripts/System/Services/warehouse_service.gd`, `settlement_overview_menu.gd` /
  `convoy_settlement_menu.gd`.
  - **Cleanup noticed alongside (not the bug):** `convoy_settlement_menu.gd` still declares and emits
    `open_warehouse_menu_requested` (`:3`, `:730-744`) and `menu_manager.gd:692-693` still wires it, but
    `warehouse_button` is permanently `null` (`:29`), so nothing can ever trigger it. Dead path — fold
    into the **dead-code sweep** in the systems-audit initiative.

- [ ] **Convoy icon ↔ convoy label anti-collision** — the convoy **label** can overlap the convoy
  **icon** on the map; add anti-collision so the label offsets clear of its own icon (analogous to the
  A5 edge/gear clamp and A4 route-nudge already in `UI_manager`/`convoy_label_manager`). Distinct from A5
  (edge/gear clamp) and A4 (route nudge). `Scripts/UI/convoy_label_manager.gd`.
  - ⚠️ **Superseded by research — see S13-17.** The premise "add anti-collision" is wrong: the icon
    keepout already exists (`convoy_label_manager.gd:530-561`, radius `:62`). It under-covers the arrow
    and the escape search is too weak. Fix both label systems in one pass under **S13-17**, not here.

- [x] **UI-scale slider: drop the top ~90% of the range** *(✅ CODE-COMPLETE 2026-08-04, 17/17 headless,
  pending an on-screen look)* — **bounds set on screen by the reporter: min `0.75`, max `1.30`.** Now
  `UITheme`-adjacent constants `MIN_USER_SCALE` / `MAX_USER_SCALE` on `UI_scale_manager.gd`, with a single
  `get_effective_max_scale()` feeding **both** the slider range and `set_global_ui_scale()`'s clamp — the
  old `0.5 … 4.0` clamp is gone. Deriving those two independently is what allowed S13-23.
  - **A real bug was found in `get_max_safe_scale()` while doing this.** It returned
    `window_width / MIN_LOGICAL_WIDTH`, but the logical viewport width after a scale is
    `base_target_width / _user_scale` — the window width **cancels out** of `factor = win.x / target_w`.
    So the ceiling grew without bound on wide monitors (**~3.0 on a 3440px display, where the honest
    limit is `1920/1150 ≈ 1.67` on any monitor**). That is a direct cause of this item's own "the top of
    the range produces broken/oversized UI" report — the slider was offering scales that could never have
    been safe. Now derived from `_base_target_width()`.
  - A stored value outside the product bounds is normalised **once** on the next Settings open, against
    `MIN_USER_SCALE … MAX_USER_SCALE` only — never against the window-derived ceiling, which would destroy
    a legitimate `1.30` preference just for opening Settings on a narrow window.
  (Docs: [ui_system § The slider's own ceiling](02_UI_UX/ui_system.md#the-sliders-own-ceiling--and-two-constants-that-look-alike) — rewritten; the old description was wrong on both counts.)

- [x] ~~**UI-scale slider: drop the top ~90% of the range**~~ *(original text retained below for the
  `file:line` references)* — the desktop UI-scale slider goes far too high;
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

- [x] **Pan direction (invert-pan) inconsistent across sessions** *(✅ DUPLICATE of **S13-2** — both
  suspicions here were investigated 2026-07-31 and **ruled out**; fixed by S13-2's change, pending the
  same device test)* — panning felt like it flipped between normal and inverted between sessions.
  - **Persistence is fine.** `settings_manager.gd::set_and_save()` (`:37-41`) writes to
    `user://settings.cfg` **synchronously on every toggle**, and `load_settings()` (`:55-60`) runs from
    `_ready()` (`:30-32`). Nothing is left in a stale in-memory default.
  - **There is no load race.** `SettingsManager` is an autoload, so its `_ready()` — and therefore the
    disk load — completes before the main scene's `_apply_settings_snapshot()` ever runs.
  - **The real mechanism was the display, not the value**, which is exactly S13-2: the settings panel was
    built once and never re-synced, so its checkbox could disagree with the stored setting, and the next
    click wrote that *stale checkbox state* back through `set_and_save()`. That is the "flips on its own"
    both reports describe. Fixed by S13-2's `visibility_changed` → `_init_values()` re-read.
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

- [x] **S12-8 · `_show_new_convoy_dialog()` runs in an unbounded loop for a 0-convoy account**
  *(P2 — ✅ CODE-COMPLETE 2026-07-31, compile-checked; ⚠️ needs a 0-convoy account to verify — see below)* —
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
      Backend repo `~/Work/desolate_frontiers`. **⏳ Still open — backend, not touched in this pass.**
  **✅ Implemented 2026-07-31 (client half):**
  - **The prompt is idempotent.** New `_new_convoy_dialog_open` flag on `main_screen.gd`;
    `_show_new_convoy_dialog()` returns early when it is already set, and `_hide_new_convoy_dialog()`
    clears it (both the create and cancel handlers route through that function, so a later legitimate
    prompt still opens).
  - **The guard is a flag, not `_new_convoy_dialog.visible`** — which would not have worked. `open` is
    invoked via `call_deferred`, so `visible` stays false for the remainder of the current frame, and a
    visibility check would have let every *same-frame* repeat through. Same-frame bursts are exactly the
    shape the captured log shows, so the obvious version of this fix would have looked correct and
    stopped almost nothing. The flag is set **before** the deferred open for the same reason.
  - The flag is cleared **unconditionally** at the top of `_hide_new_convoy_dialog()`, outside the
    `is_instance_valid()` check, so a freed dialog cannot strand it `true` and permanently suppress the
    prompt — a worse failure than the loop it replaces.
  - **`ResponsiveListAdapter` is no longer destroyed.** `convoy_list_panel.gd::populate_convoy_list()`
    now frees only `Control` children. The adapter ships in `ConvoyListPanel.tscn` as a plain `Node`
    child of `ConvoyItemsContainer`, and list items are all `Control`s, so the type test cleanly
    separates them — no name matching needed. Nothing in the script ever recreated it (grep finds **zero**
    references to it anywhere in `convoy_list_panel.gd`), which is why the loss was permanent.
  ⚠️ **Verification needs a 0-convoy account** — this whole entry only manifests in that state, which is
  neither reproducible headless nor on an account with convoys. **Pass:** `[Onboarding]
  _show_new_convoy_dialog invoked.` appears **once**, followed by any number of the new
  `already open — ignoring repeat.` lines, instead of hundreds of full invocations.
  ⚠️ **Re-measure S13-1 after this lands.** That entry names this loop as contributor (2) and asks for a
  re-measure once it is fixed; the two were implemented in the same session but **the measurement has not
  been taken**, so how much of the pre-login lag this accounts for is still unknown.

## Beta support / platform

- [x] **S12-5 · Feedback / Report-Bug must be reachable at ALL times during beta** *(P1 — ✅ CODE-COMPLETE
  2026-07-31, compile-checked + headless smoke-tested; ⚠️ **interaction/placement NOT yet verified on a
  real screen** — see the caveats at the end of this entry)* — today it is
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
  **✅ Implemented 2026-07-31** — new `Scripts/UI/global_feedback_overlay.gd` (`GlobalFeedbackOverlay`),
  a `CanvasLayer` at **`layer = 200`** with `PROCESS_MODE_ALWAYS`, owning a small bottom-left "Feedback"
  button and the single shared `BugReportWindow`. One node answers all four blockers:
  - **(1) Login** — solved *without* touching `login_screen.gd`, contrary to the suggested shape. The
    overlay is owned by **`GameScreenManager`** (`_ensure_feedback_overlay()`, called immediately after
    it sets `get_tree().paused = true`), not by `MainScreen` — which is the whole problem, since
    MainScreen is `visible = false` **and** `PROCESS_MODE_DISABLED` for the entire login. A global
    overlay covers the login screen for free, so no second button is needed there.
  - **(2) Paused tree** — `PROCESS_MODE_ALWAYS` on the overlay, the button, **and** the lazily-created
    `BugReportWindow`. The old window took the default `PROCESS_MODE_INHERIT`, which is exactly why it
    would have opened frozen.
  - **(3) Tutorial** — `layer = 200` beats `ResponsiveModalPanel`'s `100` and the link popups' `101`, and
    the tutorial overlay is parented into MainScreen's onboarding layer (a plain `Control`), so it draws
    on canvas layer **0**. Godot delivers GUI input to CanvasLayers in **decreasing layer order**, so this
    button is hit-tested *before* the tutorial's `MOUSE_FILTER_STOP` shields — no hole needs punching in
    `tutorial_overlay.gd`, which is therefore untouched.
  - **(4) Modal/error states** — same mechanism as (3).
  - **The top-bar button still works and is unchanged visually.** `user_info_display._on_bug_report_pressed()`
    now **delegates** to the overlay via `GameScreenManager.get_feedback_overlay()`, so both entry points
    drive **one** window instead of two independently-owned ones. Its original local path is retained as a
    fallback (with a `push_warning`) for the case where this display is hosted outside `GameScreenManager`
    — reporting a bug must never itself fail.
  - The floating button hides itself while the report window is open, since layer 200 would otherwise
    float it over the very dialog it opened.
  ⚠️ **What is NOT verified.** Headless proves it constructs with zero script errors and that all touched
  files compile (probe + editor pass). It cannot prove **placement or hit-testing**. Specifically unproven:
  that the bottom-left position clears the mobile bottom nav bar and the map's gear tab at every
  orientation; that `get_logical_safe_margins()` is non-zero by the time `_reposition()` first runs (it
  returns **zero margins until the scale settles** — the S12-7 hardening — so a first-frame call gets no
  inset, which is safe but unpadded); and that input genuinely reaches the button through a tutorial
  shield. **Run the S12-5 recipe below before closing.**
  ⚠️ **Redundant entry point on the main screen** — there are now two Feedback affordances there (top bar
  + floating). Deliberate, to avoid changing the familiar top bar unprompted. If that reads as clutter,
  the cheap follow-up is hiding `%ReportBugButton` and letting the floating one be the sole entry point.
  `Scripts/UI/global_feedback_overlay.gd` (new), `Scripts/UI/game_screen_manager.gd`,
  `Scripts/UI/user_info_display.gd`, `Scripts/UI/bug_report_window.gd`, `Scripts/UI/login_screen.gd`,
  `Scripts/UI/tutorial_overlay.gd`.
  (Docs: [BugReporting.md](04_Technical/BugReporting.md) — written 2026-07-28 for this item.)

- [x] **S12-6 · Easy enter/exit fullscreen on PC** *(P2 — ✅ CODE-COMPLETE 2026-07-31, shortcut matching
  unit-tested headless (11/11); ⚠️ **the actual mode switch + re-layout is NOT verified on a real
  window** — see caveats)* — there was **no keyboard shortcut**. Confirmed:
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
  **✅ Implemented 2026-07-31**, with one deliberate deviation from the suggested shape:
  - **No `[input]` action; `project.godot` is untouched.** `_unhandled_key_input()` on
    `SettingsManager` matches the keys directly. Hand-authored `InputEventKey` resource literals in
    `project.godot` are fragile, and the binding set is platform-conditional. The trade-off is that the
    shortcut does **not** appear in the editor's Input Map panel — recorded here so it is findable.
  - **Handled on `SettingsManager`, not `main_screen.gd`**, because that node is
    `PROCESS_MODE_DISABLED` during login; this autoload already owns `display.fullscreen` and its side
    effect. It needed **`process_mode = PROCESS_MODE_ALWAYS`** or the login-time pause would have gated
    its input callback (same trap as S12-5 blocker 2). Safe — it has no `_process`/`_physics_process`.
  - **Routes through `set_and_save()`** as the entry required, so persistence and the deferred
    `reapply_scale()` are inherited rather than reimplemented. `DisplayServer` is never touched here.
  - **Bindings:** `F11` (all platforms), `Alt+Enter` / `Alt+KP_Enter` (Windows/Linux), `Cmd+Ctrl+F`
    (macOS). Exclusive fullscreen is retained per the 2026-07-29 answer.
  - **The checkbox now tracks the shortcut live.** `settings_menu.gd` subscribes to
    `SettingsManager.setting_changed` and updates via `set_pressed_no_signal()` (so the
    `toggled` → `set_and_save` path cannot re-enter). Without this, S13-2's fix would only have
    resynced on *reopen*, leaving the checkbox stale while the menu sat open.
  **✅ Verified headless — 11/11** on the matching logic, including the four that must fire and, more
  importantly, the six that must **not**: plain `Enter`, plain `F`, `F10`, `Shift+Enter`, and both
  `Cmd+F` and `Ctrl+F` alone (each is *Find* — only the combination is the toggle). Plus a round-trip
  asserting `toggle_fullscreen()` flips and restores the stored value.
  ⚠️ **NOT verified: the actual window-mode switch and the re-layout after it.** `_apply_runtime_side_effect()`
  early-returns on headless (`settings_manager.gd:69-70`), so the `DisplayServer` call and the
  `reapply_scale()` that follows it were never exercised — and that re-layout is precisely the failure
  mode the entry warns about. **Also still unverified: whether the existing `FullscreenCheck` checkbox
  works**, which the entry asks to confirm *before* trusting the shortcut. Its wiring reads correctly and
  S13-2 removed the stale-display explanation for "a click that appears to do nothing", but that is
  reasoning, not a test. Both need the S12-6 recipe below on a real window.
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
> **⭐ Then a captured diagnostic log (2026-07-29) turned up S13-13, which was not in the original
> report:** the vendor panel is destroyed and re-instantiated on *every map snapshot*, including while a
> purchase is in flight — two of three logged buys never received their API result at all. It is the
> parent cause of S13-5 and of the worst S13-6 variant, so **fix S13-13 first**; the two may partly
> resolve with it.
>
> **Still worth reading before triaging:** S13-5 and S13-7 are the cargo twins of two already-solved
> vehicle bugs. The "sold vehicle reappears" saga was fixed with a re-strip list (`_sold_vehicle_ids` /
> `_strip_sold_vehicles`, `vendor_trade_panel.gd:2547-2585`) and per-item capacity has never been
> modelled. Reuse those shapes rather than inventing new ones.

## Performance

- [x] **S13-1 · Fullscreen lag while stuck pre-login / in the background-art limbo** *(P1 — ✅ CODE-COMPLETE
  2026-07-31, compile-checked; ⚠️ **the fullscreen-vs-windowed FPS measurement was NOT taken** — see below;
  **macOS**, confirmed 2026-07-29: severe enough to stutter unrelated video playback on the same machine)* — reported
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
  **✅ Implemented 2026-07-31** — all three GPU-side changes to `_setup_map_background()`, targeting
  contributor (1), which the macOS "stutters other applications" symptom pointed at:
  - **`UPDATE_ALWAYS` → `UPDATE_WHEN_VISIBLE`** (`:697`), and `set_loading_mode(true, …)` now sets
    **`UPDATE_DISABLED`** outright (restoring `UPDATE_WHEN_VISIBLE` on `false`). This is the part that
    addresses the *limbo* case specifically: the entry's own diagnosis is that the screen is never
    `queue_free()`d when `initial_data_ready` never arrives, so tearing down on that signal was never
    going to help. The backdrop now stops rendering the moment the screen goes into loading state.
  - **MSAA removed** (was `MSAA_2X`) — a full-screen-sized multisample buffer bought nothing on a
    backdrop already modulated to 26 % alpha at `:691`.
  - **Render resolution capped** — new `_compute_bg_viewport_size()` renders at `_BG_RENDER_SCALE = 0.5`
    of the window (floor `480×270`) and lets the existing `STRETCH_KEEP_ASPECT_COVERED` upscale it, so
    cost no longer scales with full window area. Applied at both creation and `_on_viewport_size_changed()`.
  ⚠️ **`Engine.max_fps` was deliberately NOT capped.** The entry floats it as "the single change most
  likely to stop the machine-wide stutter", but it is a **global** engine setting; setting it from the
  login screen means owning a restore on every exit path from a screen this entry says can be left in
  limbo. Worth doing if the above proves insufficient — as a deliberate decision, not a silent omission.
  ⚠️ **Unverified: the actual FPS gap.** The prescribed measurement (fullscreen vs. windowed FPS on the
  login screen, to confirm the gap tracks window area) **was not taken** — it needs a live macOS
  fullscreen session, which the headless compile-check cannot provide. The fix is reasoned from the
  entry's verified mechanism, not measured. **Take that measurement before closing**, and note that
  contributors (2) (the S12-8 request loop) and (3) remain untouched, so a residual CPU-side stutter
  would point there rather than at this change being wrong.
  `Scripts/UI/login_screen.gd`, `Scripts/UI/game_screen_manager.gd`.

## Input / settings

- [x] **S13-2 · Settings menu shows stale control values after a logout/login — pan toggle "flips on its
  own"** *(P2 — ✅ CODE-COMPLETE 2026-07-31, compile-checked, pending device test)* — reported as the panning setting changing periodically, "the setting
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
  **✅ Implemented 2026-07-31** — `settings_menu.gd` connects its own `visibility_changed` in `_ready()`
  to `_on_visibility_changed()`, which re-runs `_init_values()` whenever the panel becomes visible. Chosen
  over patching `_on_settings_button_pressed()` so every caller benefits, per the entry's own preference.
  - ⚠️ **`NOTIFICATION_VISIBILITY_CHANGED` does not exist here** — this entry (and the obvious instinct)
    suggested it, but `SettingsMenu` extends **`CanvasLayer`**, and that constant belongs to `CanvasItem`.
    Using it is a hard parse error (`Identifier "NOTIFICATION_VISIBILITY_CHANGED" not declared in the
    current scope`), caught by the load probe. `CanvasLayer` exposes a `visibility_changed` **signal**
    instead, which is what the fix uses.
  - **The dead `1.4` fallback is reconciled** (was flagged under S12-4's cleanup note): `_init_values()`
    read `SM.get_value("ui.scale", 1.4)` while `settings_manager.gd:11` defaults to `1.0`. Now `1.0`.
  - **Not done in this pass:** the Reset-Defaults scoping question and the four-pan-path sign convention
    normalisation. Both are listed above and remain open; neither is implicated in the reported symptom.
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
  - Default: **off** for all-convoys (confirmed 2026-07-29), matching the other six overlays, which all
    default `false`. The selected convoy's line still appears regardless.
  `Scripts/System/Services/map_settings_service.gd`, `Scripts/UI/map_overlay_settings_panel.gd`,
  `Scripts/System/settings_manager.gd`, `Scripts/UI/UI_manager.gd`.

## Vendor / trading

- [x] **S13-5 · Vendor stock doesn't decrement *immediately* after a purchase** *(P2 — **DONE, VERIFIED
  ON DEVICE 2026-07-30** by the reporter after the successive-purchase fix below; downgraded
  2026-07-29: reporter confirmed it corrects on leaving and re-entering the vendor, so this is a
  **responsiveness** bug, not data loss. "I just want it responsive.")* — bought 7 × Industrial Robotic
  Arms; the vendor's quantity did not go down until the panel was reopened. **That the reopen fixes it is
  diagnostic:** the authoritative `/vendor/get` refresh is correct, so the defect is entirely in the
  optimistic path — and it narrows the two candidates below to whichever fails *before* the refresh lands.
  **🔬 DIAGNOSED 2026-07-29 from a captured `[VendorPanel][DIAG]` log — one of the two suspected causes is
  now RULED OUT and the other is CONFIRMED:**
  - **Name lookup works — not the problem.** The log shows
    `SUCCESS: updated 'Industrial Bio-Lubricants' in bucket 'delivery': 300 -> 155`. The decrement fires
    and lands. Ignore the "lookup miss" theory.
  - **Re-aggregation resurrection — confirmed, and worse than assumed.** A later sell of 30 on the *same*
    item in the *same* vendor session logged `SUCCESS: … 'delivery': 300 -> 330`. The baseline is **300
    both times** — the panel had thrown away the 155 and gone back to the stale `/map` value. Expected
    after a 145 buy and a 30 sell: 185. The panel is not merely failing to refresh; it is **rebuilt from
    scratch between transactions** (see S13-13 — the `_ready` line prints ten times in this one log).
  **Mechanism:** `_optimistically_update_vendor_stock()` (`vendor_trade_panel.gd:2501-2545`) writes **only**
  `entry["total_quantity"]` on the in-memory bucket, leaving `vendor_data.cargo_inventory` and
  `entry["items"]` untouched. That edit lives on **the panel instance**, so when S13-13 destroys and
  recreates the panel, the decrement dies with it and re-aggregation restores the stale `/map` number.
  This is precisely the sold-vehicle saga, fixed there by remembering the id and re-stripping on every
  rebuild (`_sold_vehicle_ids` / `_strip_sold_vehicles`, `:2547-2585`); cargo has **no** equivalent.
  **Suggested shape:** fix **S13-13 first** — if the panel stops being recreated, this may resolve on its
  own and the rest becomes belt-and-braces. Then: key the decrement off `cargo_id` (which `dispatch_buy`
  already has — `vendor_panel_transaction_controller.gd:264-266`) rather than the display name, mutate the
  underlying inventory rows too, and add a cargo counterpart to `_strip_sold_vehicles` **stored outside the
  panel instance** (the panel is not a safe place to keep state that must survive a rebuild).
  **✅ Implemented 2026-07-30** — new `Scripts/Menus/VendorPanel/vendor_optimistic_stock.gd`
  (`VendorOptimisticStock`), a `static` registry keyed by `vendor_id` that lives **outside every panel
  instance**, so a rebuild cannot take the decrement with it:
  - `record_cargo(vendor_id, cargo_id, name, delta)` on each transaction result; deltas **accumulate**,
    so two buys before the refresh lands are both reflected. Matching is by **`cargo_id` first**
    (the same handle `dispatch_buy` uses), display name only as a fallback — needed anyway for the
    virtual `Fuel/Water/Food (Bulk)` rows, which carry no `cargo_id`.
  - `apply_to_buckets()` is called from `_populate_vendor_list()`, the one choke point every refresh path
    funnels through — so a re-aggregation off the lagging `/map` snapshot can no longer restore the
    pre-transaction number. Logged as `[VendorPanel][DIAG] optimistic REAPPLY …`.
  - `clear_vendor()` fires the moment authoritative `/vendor/get` data lands (both the
    `vendor_panel_ready` hub path and `on_vendor_panel_data_ready`), so a delta is never double-counted;
    a 30 s TTL is the backstop if that payload never arrives.
  - `_sold_vehicle_ids` / `_strip_sold_vehicles` were the panel-local version of exactly this and are now
    folded into the same registry — the vehicle case had the identical rebuild-loses-it flaw.
  **🐛 Follow-up fix 2026-07-30 — successive purchases double-counted.** First on-device pass: the vendor
  updated, but buying 5 of 120 gave 115 and then buying 4 more gave **106, not 111**. Cause was in the new
  code, not the old: `apply_to_buckets()` applies the **running total**, which is right for a freshly
  aggregated bucket set but wrong immediately after a transaction — `_update_vendor_ui()` re-renders the
  **cached** buckets (`_populate_list_from_agg`, `:1739`) instead of re-aggregating, so those buckets
  already carry every earlier delta. Applying −9 to a row already showing 115 gives 106. Split into two
  entry points: `apply_single_delta()` (one increment, used by `_optimistically_update_vendor_stock`) and
  `apply_to_buckets()` (running total, used only by `_populate_vendor_list`). Both share `_apply_delta()`;
  the only difference is which number they hand it.
  `Scripts/Menus/VendorPanel/vendor_optimistic_stock.gd` (new),
  `Scripts/Menus/vendor_trade_panel.gd`, `Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd`,
  `Scripts/Menus/VendorPanel/vendor_panel_refresh_controller.gd`,
  `Scripts/Menus/VendorPanel/cargo_aggregator.gd`.
  (Related: the `/map`-snapshot-lag mechanism is [DataBoundaries.md](04_Technical/DataBoundaries.md).)

- [x] **S13-6 · Buy button stuck on "Processing…" after a failed purchase** *(P1 — **DONE, confirmed
  improved on device 2026-07-30**; the stuck button no longer reproduces. A separate friction the reporter
  noticed in the same pass — having to reselect the item to buy again — is deliberate existing behavior,
  split out as **S13-15**)* — the button text and
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
  - **A third variant, confirmed in the 2026-07-29 log: the panel is gone before the reply lands.** Two of
    three purchases never reached `_on_api_transaction_result` at all because the panel was `queue_free()`d
    mid-flight — see **S13-13**. The button isn't stuck in that case (the whole panel is replaced), but the
    outcome is worse: the purchase succeeds server-side with no acknowledgement anywhere in the UI. The
    watchdog belongs somewhere that **survives the panel** for this reason.
  **Suggested shape:** move the button/flag restore **above** the visibility guard (state repair must be
  unconditional; only the *toast* should be visibility-gated), and add a timeout using the already-recorded
  `started_ms` that reverts the projection and re-enables the button. `_pending_tx.started_ms` becoming a
  live field is the point of the fix, not incidental.
  **✅ Implemented 2026-07-30:**
  - **The visibility guard moved.** `on_api_transaction_error()` now repairs state — projection revert,
    `_transaction_in_progress = false`, button text/`disabled`, loading overlay — **unconditionally**, and
    only the toast is wrapped in `is_visible_in_tree()`. A panel hidden when the error landed no longer
    comes back stuck.
  - **The watchdog lives outside the panel**, in new
    `Scripts/Menus/VendorPanel/vendor_transaction_watchdog.gd` (`VendorTransactionWatchdog`, `static`
    registry) — exactly because the worst variant is the panel being freed before the reply.
    `begin()` on dispatch stores the token in `_pending_tx.watchdog_token`; `resolve()` runs on result,
    on error, and from `_clear_pending_tx()`. A 2 s `Timer` on each live panel drives `sweep()`, which
    returns anything unresolved past **20 s**. Because the registry is global, a panel that never
    dispatched the transaction still reports an entry **orphaned by a freed panel**.
  - On timeout the owning panel reverts the projection, re-enables Buy/Max, clears `_transaction_in_progress`,
    toasts, and requests authoritative data; an orphan toasts *"Couldn't confirm the last transaction —
    refreshing"* and pulls `/vendor/get` rather than guessing the outcome.
  `Scripts/Menus/VendorPanel/vendor_transaction_watchdog.gd` (new),
  `Scripts/Menus/VendorPanel/vendor_panel_refresh_controller.gd`,
  `Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd`, `Scripts/Menus/vendor_trade_panel.gd`.

- [x] **S13-7 · "Max" over-buys because it models the convoy as one pooled container** *(P1 — **CODED
  both sides 2026-07-30; backend deployed, client awaiting on-device verification**; design settled
  2026-07-29)* — reported as the purchase overflow not working: maxing out an item sometimes won't
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
  **✅ Open question ANSWERED 2026-07-30 — the server had no fill order at all.** The player's "buy" is
  `PATCH /vendor/cargo/buy` → `vendor_api.py:363` → **`Vendor.sell_cargo()`**
  (`chassis/df_obj/vendor_cls.py:444-548`, note the inverted naming: the *vendor* sells). Its distribution
  loop was a plain `for vehicle in convoy.vehicles`, and `Convoy.vehicles` (`convoy_cls.py:105-108`) is
  just `[v for v in self._vehicles]` — **raw DB row order, never sorted**. So "match the server's order"
  was not an option: there was no order to match. Two further findings that reshaped the fix:
  - **Its admission check is pooled too** (`:478-481`, `convoy.total_free_space` /
    `total_remaining_capacity`) — the *same* pooled arithmetic this entry faults the client for. The
    client was not disagreeing with the server; both were wrong in the same way.
  - **It never actually rejected the indivisible case — it overfilled.** Split out as **S13-16**.
    This is why simulating the old server faithfully would have meant shipping a preview that advertised
    the overfill as capacity.
  **✅ Backend half implemented 2026-07-30** (`chassis/df_obj/vendor_cls.py:505-541`): the loop now runs
  `sorted(convoy.vehicles, key=lambda v: v.free_space, reverse=True)` and allocates with a floor
  (`vehicle.free_space // unit_volume`, `vehicle.remaining_capacity // unit_weight`) instead of
  `max(1, int(estimated_quantity))`, so a vehicle is never handed a unit that does not fit. The
  pre-existing post-loop `remaining_quantity > 0` check now does real work: the indivisible case raises
  `Not enough space or weight capacity across all vehicles…` → HTTP 400, inside the endpoint's DB
  transaction, so no money is deducted. Verified by executing the loop's **extracted source text**
  against duck-typed vehicles (the backend's own import chain needs container-only deps and cannot be
  imported on the dev Mac): 4×10 L free buying 2×15 L → cleanly rejected, zero overfill (previously
  accepted, two vehicles driven negative); a 100 L vehicle listed *after* a 20 L one is still filled
  first; ordinary single-vehicle buys unchanged. **Not yet run against the backend's own test suite or
  deployed.**
  **✅ Backend deployed 2026-07-30** by the reporter.
  **✅ Client half implemented 2026-07-30**, once the deploy made a capacity-truthful preview correct:
  - New `Scripts/Menus/VendorPanel/cargo_fill_planner.gd` (`CargoFillPlanner`) — `build_vehicle_spaces()`
    reads per-vehicle room off `convoy_data.vehicle_details_list` using the same field precedence as the
    per-vehicle capacity bars (`convoy_menu.gd:2862-2867`: prefer `total_cargo_volume` /
    `total_cargo_weight`, fall back to the server's `free_space` / `remaining_capacity`), and `plan()`
    walks vehicles **largest-free-volume first**, each taking
    `min(floor(free_vol / unit_vol), floor(free_wt / unit_wt), still needed)` — a line-for-line mirror of
    the deployed allocator. Free space is clamped at 0 so a vehicle left over-filled by the old code
    (**S13-16**) contributes nothing instead of a negative.
  - `on_max_button_pressed()` now treats stock / money / bulk-resource headroom as **ceilings** and runs
    the plan to get what actually fits. Logged as
    `[VendorPanel][DIAG] max plan: ceiling=N fits=M across K vehicle(s) -> [...]`.
  - **`max(1, max_quantity)` is gone.** When nothing fits, Max reports **0** and toasts the reason
    (*"No single vehicle has room for one of these."*, or the distinct stock/money/resource cases);
    Buy disables itself at 0 via the S13-15 change rather than offering a quantity the server refuses.
  - **Bulk resources keep the pooled path** — a litre of fuel *is* divisible across containers, so
    per-vehicle packing would be wrong for them.
  - The silent `0.0` fallbacks for `unit_weight` / `unit_volume` no longer disappear: the constraint is
    still skipped, but `explain_unknowns()` logs `max plan: unit volume unknown — that constraint was
    NOT applied`. A convoy with no `vehicle_details_list` logs `max plan SKIPPED` and falls through on
    the ceilings rather than claiming nothing fits.
  Verified headless against the **same three scenarios the backend allocator was checked with**, plus
  three client-specific ones (weight-bound, legacy over-filled vehicle, unknown unit volume) — six of six
  agree, including the two that matter most: 4×10 L free with a 15 L item → **0**, and a large vehicle
  listed *second* still filled first.
  `Scripts/Menus/VendorPanel/cargo_fill_planner.gd` (new),
  `Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd`,
  backend `chassis/df_obj/vendor_cls.py`.

- [x] **S13-13 · The vendor panel is destroyed and rebuilt constantly — including mid-transaction, losing
  the result** *(P1 — **DONE, VERIFIED ON DEVICE 2026-07-30**; found 2026-07-29 in the
  `[VendorPanel][DIAG]` log; **parent cause of S13-5 and of one S13-6 variant**)* — the log shows
  `[VendorPanel][DIAG] _ready instance_id=…` **ten times** in a
  single vendor session, and — the damning part — **three `Action Button Pressed: buy` lines but only one
  `_on_api_transaction_result`**:

  ```
  Action Button Pressed: buy on instance_id=459209185875 for 156 x Industrial Bio-Lubricants
  _ready instance_id=753011788863          ← panel replaced; 156-unit buy has no owner
  _ready instance_id=791582607749
  Action Button Pressed: buy on instance_id=791582607749 for 154 x Industrial Bio-Lubricants
  _ready instance_id=877515511484          ← replaced again; 154-unit buy has no owner
  ```

  Two of the three purchases dispatched their API call and then had their panel `queue_free()`d before the
  response arrived. The result signal lands on a dead node: **no optimistic stock update, no success toast,
  no button restore, no error path** — the request itself still hits the server, so the player is left with
  a purchase that happened and a UI that never acknowledged it.
  **Verified cause — vendor tabs are rebuilt wholesale on two unconditional triggers:**
  - `convoy_settlement_menu.gd::_on_store_map_changed()` (`:371-374`) calls
    `call_deferred("_display_settlement_info")` on **every** map snapshot, with no check for whether
    anything relevant actually changed. `_display_settlement_info()` (`:205-225`) calls `_clear_tabs()`
    (`:523-537`, which `queue_free()`s every tab control) and then re-runs `_create_vendor_tab()` (`:376-410`,
    a fresh `VendorTradePanel.instantiate()`). A map refresh is requested after **every transaction**
    (`vendor_trade_panel.gd` emits `user_refresh_requested` at the end of `_on_api_transaction_result`), so
    trading is itself what triggers the rebuild that discards the trade's own optimistic state.
  - The layout-change path does the same: `:172` `call_deferred("_display_settlement_info")` with the
    comment *"Regenerate UI completely on layout change"* — so every resize/rotation also destroys the panel.
  There is already a **narrow** guard for a related symptom — `:215-217` skips the rebuild when the incoming
  snapshot is missing the single vendor (the "vendor disappears" bug) — which shows the rebuild-on-snapshot
  pattern has bitten before and was patched at the symptom rather than the cause.
  **Suggested shape:** stop rebuilding on data updates. `_refresh_all_vendor_panels()` already exists and is
  the correct path — `_display_settlement_info()` should only run when the **set of vendors actually
  changes** (compare vendor ids against the current tabs and no-op when equal), not on every snapshot.
  Additionally, **never destroy a panel with a transaction in flight**: `_transaction_in_progress` is
  already tracked (`vendor_trade_panel.gd:76`), so `_clear_tabs()` can defer, and the S13-6 watchdog gives a
  bounded worst case. The layout-change rebuild should become a re-layout, not a re-instantiate.
  **✅ Open question ANSWERED 2026-07-30 from the captured log itself** (still on disk at
  `~/Library/Application Support/Godot/app_userdata/Desolate Frontiers/logs/godot.log`) — **one vendor,
  each rebuild ran twice.** Every one of the ten `_ready` lines is preceded by
  `building vendor tab for: 99abc0ac-46bd-4e3e-8961-b3eee769cbf3` and
  `_create_vendor_tab created tab with title: 'Depot'` — the same single Dallas Depot vendor, never a
  second one. **The second trigger was `initialize_with_data()`**: `super.initialize_with_data()` runs
  `MenuBase._refresh_from_store` → `_update_ui` → `call_deferred("_display_settlement_info")`, and then
  the very next line called `_display_settlement_info()` **synchronously**. `call_deferred` does not
  de-duplicate, so both ran — one pass building a panel and the next immediately freeing it and building
  another. That also corrects the entry's premise: in this log the rebuild trigger was **menu open /
  navigation** (5 opens × 2), not `map_changed` — every `_display_settlement_info` call correlates with a
  `MenuManager` cached-menu restore, not a snapshot.
  **✅ Implemented 2026-07-30** in `convoy_settlement_menu.gd`:
  - All five call sites now go through `_queue_display_settlement_info()`, which coalesces a same-frame
    burst into one pass — this alone halves the rebuilds.
  - `_display_settlement_info()` no longer calls `_clear_tabs()` up-front. It compares
    `_desired_vendor_ids()` against `_mounted_vendor_ids()` (read from each tab's `vendor_id` meta) and,
    when equal, refreshes in place and returns — logging
    `[VendorPanel][DIAG] settlement rebuild SKIPPED — vendor set unchanged`.
  - `_defer_rebuild_for_active_transaction()` holds a genuine rebuild off while any mounted panel has
    `_transaction_in_progress`, capped at 10 s so a lost reply can't wedge the menu.
  - `_refresh_active_vendor_panel()` no-ops during an in-flight transaction (a `/map`-sourced
    re-aggregation would discard the optimistic projection).
  - The rotation path is now a re-layout: each `VendorTradePanel` already re-applies its own orientation
    sizing from its own `layout_mode_changed` handler.
  **✅ On-device result 2026-07-30:** one `_ready instance_id=` for the whole vendor session, followed by
  seven `settlement rebuild SKIPPED — vendor set unchanged (1 tab(s): 75f17dd0-…)` across hub round-trips
  and rotations, and **zero** further `_ready` lines. Was ten `_ready` lines in the same flow.
  `Scripts/Menus/convoy_settlement_menu.gd`, `Scripts/Menus/vendor_trade_panel.gd`.

- [x] **S13-14 · The settlement menu still resolves vendor panels by *node name*, not `vendor_id`**
  *(P3 — NEW, noticed 2026-07-30 while implementing S13-13; deliberately left out of that change to keep
  its scope to lifecycle)* — `_create_vendor_tab()` stores the id as a node meta
  (`vendor_panel_instance.set_meta("vendor_id", …)`), but two consumers still round-trip through the
  display name instead: `_refresh_active_vendor_panel()` and `_on_vendor_tab_changed()` both do
  `_find_vendor_by_name(String(panel.name))`, and `_find_vendor_by_name()` matches `vendor.name` exactly.
  Two failure modes: Godot **uniquifies duplicate sibling node names** (a settlement with two identically
  named vendors gets a panel called `Depot2`, which matches no vendor and silently returns `{}` → that
  tab never refreshes); and any server-side rename of a vendor breaks the lookup until the tab is rebuilt.
  Neither is hit by the single-vendor Dallas Depot flow that S13-13 was verified against, which is why it
  isn't urgent. **Shape:** read `panel.get_meta("vendor_id")` and add `_find_vendor_by_id()`; the meta is
  already populated and S13-13's `_mounted_vendor_ids()` now depends on it, so the two would agree.
  **✅ Implemented 2026-07-30** — new `_find_vendor_by_id()` plus a `_vendor_data_for_panel(panel)` helper
  that reads the `vendor_id` meta and falls back to `_find_vendor_by_name(panel.name)` only when the meta
  is absent or the id is missing from the snapshot (logged as
  `[VendorPanel][DIAG] vendor_id '…' not in snapshot — falling back to name '…'`). Both consumers —
  `_refresh_active_vendor_panel()` and `_on_vendor_tab_changed()` — now go through it, so they agree with
  `_mounted_vendor_ids()`. `_find_vendor_by_name()` is retained solely as that fallback.
  Behaviour-identical in the single-vendor Dallas Depot flow (panel name == vendor name there), so this
  cannot perturb the S13-5 retest.
  `Scripts/Menus/convoy_settlement_menu.gd`.

- [x] **S13-15 · Buying clears the selection, so buying the same item twice needs a reselect**
  *(P3 — NEW, reported 2026-07-30 while verifying S13-6: "I just have to reselect the item if I want to
  buy more." Not a regression — this is **deliberate existing behavior**, so it needs a design call, not
  a bug fix)* — `show_transaction_feedback()` (`vendor_trade_panel.gd`) ends with
  `_last_selected_restore_id = ""` and `selected_item = null`, commented *"Clear selection to fulfill
  user's 'clear panel' request"*. It runs on **success as well as error**, so every completed purchase
  drops the selection and the quantity spinbox, and buying 5 more of the same item costs two extra taps.
  Note the refresh path deliberately does the opposite — `process_panel_payload_ready()` goes to real
  trouble to *restore* selection across a rebuild (`_restore_selection`, refresh controller `:207-218`),
  so the two behaviors currently disagree about whether selection should survive a transaction.
  **Options, cheapest first:** (a) clear on error only — one-line change, keeps the "panel resets after a
  failure" intent; (b) keep the selection and reset only the quantity to 1; (c) keep both and rely on the
  optimistic stock number (now correct after S13-5) to show the purchase landed. Worth deciding against
  the original "clear panel" request before changing it — someone asked for this.
  **✅ Decided and implemented 2026-07-30** — the reporter's call was a variant of (b): *"we probably
  don't need to clear… after a failure don't change the quantity so the user can adjust if needed."*
  So **selection is never cleared for cargo**, and the two paths that disagreed now agree:
  - **Success** → selection kept, quantity reset to the widget's `min_value` (**0**, per the scene;
    `quantity_widget.gd` exposes `min_value = 0.0` and the `.tscn` keeps it). Buying 5 more is one tap on
    the quantity box, not a reselect.
  - **Failure** → **nothing is touched at all**: selection *and* the typed quantity both survive, so the
    player can adjust down and retry. This also covers the watchdog's error toasts
    (`vendor_trade_panel.gd:1098`, `:1119`), which route through the same function.
  - **Vehicles are the one exception** and still clear — a bought vehicle is gone from the vendor, so
    there is nothing left to stay selected on.
  Two supporting changes were required for the reset to actually hold:
  - `vendor_panel_selection_controller.gd:117` clamped a same-selection quantity to a hard floor of
    **1**, which sprang the box straight back to 1 on the refresh that follows a purchase. It now clamps
    to the widget's own `min_value`.
  - `_update_transaction_panel()` now clears `can_transact` when a non-vehicle quantity is `<= 0`, so
    Buy **disables visibly** at 0 instead of silently no-opping (`on_action_button_pressed()` already
    returned early at `<= 0`, so this is presentation, not a new guard).
  `Scripts/Menus/vendor_trade_panel.gd` (`show_transaction_feedback`, `_update_transaction_panel`),
  `Scripts/Menus/VendorPanel/vendor_panel_selection_controller.gd`.

- [x] **S13-16 · 🐍 BACKEND — the server silently over-fills vehicles past their cargo capacity**
  *(P2 — NEW, found 2026-07-30 while researching S13-7's fill order; **fixed in the same pass as S13-7's
  backend half, NOT yet deployed**. Backend repo `~/Work/desolate_frontiers`, not this one)* — in
  `sell_cargo()` (vendor→convoy, i.e. the player buying),
  the per-vehicle allocation is
  `quantity_for_vehicle = max(1, int(estimated_quantity)) if estimated_quantity > 0 else 0`
  (`chassis/df_obj/vendor_cls.py:526`). The `max(1, …)` forces **at least one unit** into any vehicle with
  *any* free space at all, however small — a vehicle with 1 L free is handed a 15 L item because
  `estimated_quantity = 0.067 > 0`. `Vehicle.add_cargo()` (`chassis/df_obj/vehicle_cls.py:620`) performs
  **no capacity validation whatsoever**, so the unit is accepted and `free_space`
  (`cargo_capacity - total_cargo_volume`, `:466`) goes **negative**. The admission check at `:478-481` is
  pooled (`convoy.total_free_space`, `convoy.total_remaining_capacity`), so it cannot catch this either.
  Net effect: the indivisible-item case is not rejected, it is *absorbed* — the convoy ends up over
  capacity and the discrepancy only surfaces later as impossible-looking vehicle stats. This is a
  correctness bug in its own right and it is also **why S13-7's preview cannot be made truthful by
  simulation alone**: any client model that respects per-vehicle capacity will predict *fewer* units than
  the server actually accepts. Fixing S13-7 properly likely means fixing this first.
  **✅ Fixed 2026-07-30** alongside S13-7's backend half — the allocation is now a floor
  (`free_space // unit_volume`, `remaining_capacity // unit_weight`) rather than
  `max(1, int(estimated_quantity))`, so no vehicle is handed a unit that does not fit and the post-loop
  `remaining_quantity > 0` check raises a clean 400 instead. `Vehicle.add_cargo()` was left as-is (still
  no validation of its own) — the caller is now the guard. **Adding a defensive capacity check inside
  `add_cargo()` is deliberately NOT done here** (every other caller would need auditing first); worth its
  own item if this class of bug recurs. **Deployed to production 2026-07-30** and confirmed in the
  running container (`docker exec df-api grep -c "sorted(convoy.vehicles" …` → `1`). Still not run
  against the backend's own test suite.
  `chassis/df_obj/vendor_cls.py:505-546`, `chassis/df_obj/vehicle_cls.py:620`.

- [x] **S13-18 · Convoys already over-filled by the old server code will refuse new cargo after the
  S13-16 deploy** *(P3 — NEW, noticed 2026-07-30 while writing up S13-16's deploy risk. Pre-deploy
  check, not a code defect. **Checked and closed 2026-07-31, no migration.**)* — S13-16's old
  `max(1, int(...))` allocation drove `free_space` **negative** on real vehicles, and that state is
  **persisted** (`free_space` is derived from `cargo_capacity - total_cargo_volume`, `vehicle_cls.py:466`,
  so an over-stuffed vehicle stays over-stuffed in the DB). After the fix, such a vehicle is correctly
  skipped by the distribution loop (`int(negative // unit_volume)` is negative → `quantity_for_vehicle` is
  not `> 0`), so a player holding one may see purchases refused with *"Not enough space or weight capacity
  across all vehicles"* until they unload it — even though the vendor and the convoy's pooled numbers look
  fine. This is correct behaviour meeting bad legacy data, and it is **player-visible**, so it wanted a
  decision before deploy, not after.
  **✅ Checked 2026-07-31** — queried prod (via Adminer through `adminer-tunnel.sh`, `df_v0_6_0_*` tables;
  direct `asyncpg` from a laptop can't reach the DO-managed Postgres instance, it's firewalled to trusted
  sources) for `total_cargo_volume > cargo_capacity` / `total_cargo_weight > weight_capacity`, reproducing
  the derived properties by hand since neither is a stored column. Of 557 vehicles, 24 are over capacity
  (15 by volume, 13 by weight); 21 belong to real convoys, across **11 convoys and 10 users** — the other
  3 are vendor-held or orphaned and unrelated to this bug (tracked separately, see **S13-21**). Hand-checked
  the worst offenders' cargo manifests: fully explained by the known mechanism, nothing new. `Harpuji`,
  `Xplore`, and `Voyage` (one convoy) each got handed a single whole Water IBC (2100 L / 2208 kg) despite
  having only 700–1000 L of total capacity — a direct instance of the bug's own "15 L item forced into 1 L
  of free space" example, just with a bigger indivisible unit. `BULL REX` and `Dragoon Strix` show the same
  mechanism compounded across many water-cargo purchases over time. **Decision: leave the data as-is.** 10
  affected users — largely from the pre-release testing period — is a small enough blast radius that
  migrating live player cargo isn't worth the risk, especially since S13-19's client-side clamp already
  makes the resulting error message explain itself (`describe_shortfall()`), and the condition self-heals
  the moment the player unloads anything from the affected vehicle. No migration planned.
  Backend repo `~/Work/desolate_frontiers`.

- [x] **S13-17 · The GDScript compile-check recipe was undocumented (and half-understood)** *(P3 — NEW,
  found 2026-07-30 while compile-checking S13-14)* — nothing in `docs/` recorded how a "compile-clean"
  claim is actually produced; `SprintHistory.md:110` just asserts "Compile-clean (standard +
  warnings-as-errors)" with no method. **✅ Written up 2026-07-30 in
  [GDScript Verification](04_Technical/GDScriptVerification.md)** (linked from
  [TechnicalReference § Testing & QA](04_Technical/TechnicalReference.md#testing--qa) and
  [PROJECT_MAP](PROJECT_MAP.md)). Re-measuring against Godot `4.6.stable` **corrected the original
  diagnosis** — worth knowing, because the wrong version is intuitive:
  - `debug/gdscript/warnings/treat_warnings_as_errors` **is not a Godot 4.6 setting at all**. It reads
    back as absent, and an A/B run with it set to `true` behaved identically. Severity is per-warning
    (`0`/`1`/`2`); the repo ships no `[debug]` section, so engine defaults apply.
  - The `:=`-from-Variant canary fires because **`inference_on_variant` defaults to `2` (Error)** — a
    plain parse error, unrelated to any warnings-as-errors mechanism. `inferred_declaration` defaults to
    `0` (Ignore) and never fires.
  - The editor pass **does** catch that canary — the original "zero output" reading was a coverage gap,
    not a mode difference. The pass sees the autoload dependency graph plus scenes the editor happens to
    reopen; a file nothing references (e.g. `Scripts/Debug/wiring_smoke_test.gd`) is invisible to it even
    with `class_name` and `--quit-after 1000`. That is the real reason the targeted probe is still
    needed.
  - Load the probe's targets on the **first frame** (`_process`), not in `_init()` — autoload identifiers
    are not compiler-visible that early, and `_init()` yields false `Identifier not found:
    ErrorTranslator` failures on healthy scripts. Fixed, the probe runs in ~2 s and the editor pass in
    ~15 s warm.
  - Confirmed as first written: `load()` returns a **non-null placeholder** for a failed script, so a
    null check is not a pass/fail signal; and `unused_variable` (default `1`) never fails a load, with
    `_`-prefixing suppressing it outright.

- [x] **S13-19 · Pooled capacity bar says "fits at 96%", server refuses the purchase** *(P1 — NEW,
  reported from a live bug report 2026-07-30 (GitHub issue #90): 13 × Bauxite Ore rejected with
  `Not enough space or weight capacity across all vehicles`, while the panel showed the convoy at 96%.
  **Directly caused by S13-7's backend half landing without a complete client guard**)* — two separate
  gaps, both mine:
  - **The S13-7 planner was wired to the Max button only.** `CargoFillPlanner` was called from
    `on_max_button_pressed()` and nowhere else, so a **manually typed** quantity was never checked
    against per-vehicle packing. Buy stayed enabled and the server rejected it.
  - **The capacity bars are pooled** (`total_free_space / total_cargo_capacity`,
    `vendor_panel_convoy_stats_controller.gd:22-28`), so they report a reassuring percentage in exactly
    the cases where indivisibility makes the purchase impossible.
  Before S13-16 the server silently over-filled and accepted these, so the mismatch was invisible; the
  (correct) new allocator turned every latent pooled-vs-per-vehicle disagreement into a user-facing
  error dialog. **✅ Implemented 2026-07-30 — option (a), client-side prevention:**
  - `plan_fit(panel, wanted)` and `selection_unit_dims(panel)` extracted in
    `vendor_panel_transaction_controller.gd` so Max, the spinbox cap and the footer all plan through
    **one** code path. Returns `{}` for un-plannable cases (vehicles, bulk resources, missing
    per-vehicle data) and callers then fall back to the pooled ceilings rather than blocking a buy on
    absent data.
  - `_update_transaction_panel()` validates the **typed** quantity every time it changes, disables Buy,
    and replaces the price line with the reason.
  - The spinbox `max_value` is capped at what fits (`vendor_panel_selection_controller.gd`), so the
    impossible number can't be entered in the first place. Floor of 1, never 0, so the box stays usable.
  - `CargoFillPlanner.plan()` now also reports `blocked_by` (`"volume"` / `"weight"`),
    `best_free_volume` and `best_free_weight`; `describe_shortfall()` turns those into
    *"Only 3 of 13 fit — only 10 kg spare in any vehicle"*. **Naming the binding dimension matters
    here**: ore is dense, so the Bauxite case is almost certainly weight-bound while the player is
    reading a volume bar.
  - The Buy button shows `Only N fit` / `Won't fit` when disabled. It previously read `"Sell"`
    unconditionally when disabled, which was simply wrong in buy mode.
  **🐛 Follow-up fix 2026-07-30 — the whole guard was inert on first test ("Max still puts the whole
  order in").** `build_vehicle_spaces()` read **only** `convoy_data["vehicle_details_list"]`, but the API
  emits **`vehicles`** (backend `Convoy.to_JSONable_dict`, `convoy_cls.py:244`). Missing key → no spaces →
  `plan_fit()` returned `{}` → every caller fell back to the pooled ceilings, so Max, the spinbox cap and
  the footer warning were *all* silently disabled at once. Every other consumer in this repo already used
  the fallback chain (`mechanics_menu.gd:102`, `convoy_menu.gd:2653`,
  `warehouse_menu.gd:2732-2750`); this one didn't. Fixed with a shared `vehicle_rows()` helper
  (`vehicle_details_list` → `vehicles` → `vehicle_list`), and per-vehicle room now prefers the server's
  **own** `free_space` / `remaining_capacity` — the exact values `Vendor.sell_cargo()` allocates against —
  falling back to capacity-minus-used only when those are absent. The abort path now **logs loudly**
  (`plan_fit ABORTED — no per-vehicle rows in convoy_data (keys: …)`) because a silent empty plan is not
  a safe failure: it reverts to the over-offering behaviour this item exists to fix.
  Verified headless on four shapes (volume-bound none-fit, partial fit, weight-bound "Bauxite shape",
  and all-fit → blank message), plus five data-shape cases: the raw API `vehicles` shape, the augmented
  `vehicle_details_list` shape, weight-bound via `remaining_capacity`, a negative `free_space` (S13-16
  legacy) clamped to 0, and a convoy with no vehicle rows at all. **Still pooled and unaddressed: the capacity bars themselves** — they
  remain a whole-convoy percentage. The footer now contradicts them when packing fails, which is the
  cheap fix; making the bars per-vehicle is a separate design question.
  **✅ Cap explanation added 2026-07-30** — capping `max_value` made the ceiling *silent*: tapping `+`
  past it simply did nothing. `QuantityWidget` now emits `clamped_at_max(requested, applied)` whenever a
  request exceeds `max_value` — deliberately fired **even when the number doesn't move**, since "already
  at the ceiling" is exactly the case needing an explanation. The panel answers with a 3 s line in place
  of the price: *"Cargo can't be split across vehicles — 3 is all that fits."*, or *"The vendor only has
  N."* when stock rather than packing is the binding limit. A token supersedes stale hint timers so
  repeated taps don't let an old timer wipe a newer message. Only programmatic writes that are already
  ≤ max exist elsewhere (Max, the S13-15 reset, the selection clamp), so the signal never fires
  spuriously.
  `Scripts/Menus/VendorPanel/cargo_fill_planner.gd`,
  `Scripts/Menus/VendorPanel/vendor_panel_transaction_controller.gd`,
  `Scripts/Menus/VendorPanel/vendor_panel_selection_controller.gd`,
  `Scripts/Menus/vendor_trade_panel.gd`, `Scripts/UI/quantity_widget.gd`.

- [x] **S13-20 · A purchase that doesn't fit now offers the quantity that does** *(P3 — design question
  raised 2026-07-30 alongside S13-19; **decided and implemented 2026-07-30**, backend NOT yet deployed)* —
  S13-19 prevents the impossible purchase client-side, which was option (a). Option (b) was **silent
  server-side partial fulfilment**: ask for 13, receive the 9 that fit, pay for 9.
  **✅ Decided: option (c) — keep all-or-nothing, but make the refusal actionable.** The server reports
  how many units *would* have fitted; the client turns that into a one-tap retry at that quantity. "Buy"
  still means "buy" — the player confirms the smaller order at its real price instead of it being
  substituted behind their back.
  **Why silent partial fulfilment was rejected** (recorded so it isn't re-litigated cold):
  - **It is not a server-only change.** Four client sites assume received == requested:
    the success toast is built from `_pending_tx`, not the response (`vendor_trade_panel.gd`
    `_on_api_transaction_result`); the optimistic vendor-stock decrement; the projection commit; and
    `item_purchased`, which is emitted **at dispatch** (`vendor_panel_transaction_controller.gd:327`)
    and gates the **L2 tutorial supply step** (`tutorial_manager.gd:1599-1612`). Ask for 2 Water Jerry
    Cans, receive 1, and the tutorial advances on cargo the player does not have.
  - **The window it would cover is narrow.** `vendor_interaction_validation` requires the convoy to be
    on the vendor's tile, so no journey progress can change it mid-trade; the buy response *is* the
    authoritative post-transaction convoy and is applied directly; and `_should_accept_convoy_snapshot`
    rejects a late poll snapshot that would reinstate stale free space. What actually over-offers is the
    client guard's own escape hatches — `plan_fit()` returning `{}` when per-vehicle rows are missing,
    unknown unit dims, and unit-dimension derivation drift — i.e. cases where the panel is *already*
    misinforming the player. Silently substituting a different order on top of a wrong preview is worse
    than a clean 400, which at least forces a refresh.
  - Money would also have had to move: pricing must happen after placement, `Cargo.split` re-rounds
    resource contents (`round(resource * proportion)`) so the price of 3-split-from-13 is not 3/13 of the
    whole, and it opens a second product question (is *affordability* partial too?).
  **✅ Backend implemented 2026-07-30** (`chassis/df_obj/vendor_cls.py`): the distribution loop was
  lifted out of `sell_cargo()` into module-level **`plan_cargo_placement()`**, which returns
  `(placement, fittable)` and mutates nothing. `sell_cargo()` plans **before** any check can refuse the
  sale and appends a ` [fits:N/M]` marker to all three refusals (pooled volume, pooled weight,
  per-vehicle). Deciding and doing share one function on purpose: `fittable` is a *promise* — the player
  is offered it as a retry quantity — so a separately-derived estimate would be free to drift and
  promise a number the retry then refuses. Placement now executes from the plan, after the
  `fittable < quantity` raise, so nothing is half-placed on the way out; the money deduction above it is
  still rolled back by the endpoint's DB transaction (`vendor_api.py`), which the refactor does not touch.
  Verified by executing the extracted function's **source text** against duck-typed vehicles (the
  backend's import chain needs container-only deps and cannot be imported on the dev Mac) side-by-side
  with a re-implementation of the previously-deployed inline loop: **8 shapes, placement-for-placement
  identical**, including the S13-7 case (4×10 L free, 15 L item → 0), the weight-bound Bauxite shape
  (→ 4 of 13), a legacy negative-`free_space` vehicle (**S13-18**), and large-vehicle-listed-second.
  Plus a check that planning mutates nothing. **Not run against the backend's own test suite.**
  **✅ Client implemented 2026-07-30:**
  - `CargoFillPlanner.parse_server_fit_marker()` reads the marker and **strips it** — `ErrorTranslator`
    matches on substrings, so the raw text survives translation. It lives beside the allocator mirror
    because it is the other half of the same wire contract. The strip happens **before**
    `VendorPanelRefreshController.on_api_transaction_error()`, not after: that function toasts the
    message too, so stripping later would still have shown `[fits:3/13]` to the player from there. It
    gained a `suppress_toast` flag (default `false`) so the offer's own line replaces that toast rather
    than stacking with it — state repair stays unconditional (**S13-6**).
  - `vendor_trade_panel.gd` gained `_server_fit` — `{cargo_id, convoy_id, fits, requested}`. On a refusal
    with `0 < fits < requested` the spinbox cap is raised to `fits`, the value is set to `fits`, and the
    footer reads *"Only 3 of 13 fit — tap Buy to take 3."* Buy re-enables showing the real price for 3.
  - **The server's number outranks the local planner.** `_update_transaction_panel()` skips the S13-19
    fit block at or below the vouched quantity, and the spinbox cap in
    `vendor_panel_selection_controller.gd` never drops below it — otherwise the refresh that follows a
    refusal would let the same wrong local plan clamp the offer away before the player could tap it.
    That precedence is the point: the server measured freshly-read convoy state, this panel's copy is the
    likelier stale party. Scoped to one cargo_id **and** one convoy, and spent on the next success.
  Verified headless on 14 cases: all three backend refusal strings verbatim, marker-strip, that each
  stripped message still maps to its existing `ErrorTranslator` entry, un-marked and unrelated errors
  passed through untouched, the two shapes the offer must decline (`fits:0`, `fits==requested`), and a
  malformed marker.
  ⚠️ **Deploy ordering is safe either way** — an un-marked refusal is passed straight through to the old
  behaviour, and the marker is inert on an old client (it would only appear in the message text).
  Backend `chassis/df_obj/vendor_cls.py` (`plan_cargo_placement`, `sell_cargo`),
  `Scripts/Menus/VendorPanel/cargo_fill_planner.gd`, `Scripts/Menus/vendor_trade_panel.gd`,
  `Scripts/Menus/VendorPanel/vendor_panel_selection_controller.gd`,
  `Scripts/Menus/VendorPanel/vendor_panel_refresh_controller.gd`.

- [ ] **S13-21 · `Vehicle.add_cargo()` still has no capacity validation outside the (now-fixed) vendor
  purchase path** *(P3 — NEW, found 2026-07-31 while auditing S13-18's legacy over-capacity data)* —
  S13-16 fixed the allocator in `Vendor.sell_cargo()` so a purchase can no longer force cargo into a
  vehicle without room, but `Vehicle.add_cargo()` itself (`vehicle_cls.py:620`) still performs **no
  validation of its own** — it never did; that was always the caller's job, and S13-16 only fixed one
  caller. At least three other call sites still hand it cargo unchecked and are reachable by normal
  play today: manually moving cargo between vehicles in a convoy (`convoy_cls.py:320`, a routine
  player-facing action), redistributing a scrapped vehicle's salvaged parts onto whichever remaining
  vehicle has the lightest load (`vendor_cls.py:854-855` —
  `min(receiving_vehicles, key=lambda v: (v.load_percentage, v.free_space))`, no capacity check on the
  result), and part install/removal cargo (`vendor_cls.py:780`, `vendor_cls.py:823`,
  `engine/routers/vehicle_api.py:227`). S13-18's audit turned up 2 of its 24 over-capacity vehicles
  (a vendor-held one and an orphaned one) sitting **outside** `sell_cargo()`'s reach entirely, meaning
  something already exercises this gap, though which path (or something else) produced those two specific
  vehicles wasn't investigated. Same fix shape as S13-16 would apply — skip/clamp when the destination
  can't take the whole unit — but this is a live, player-triggerable way to recreate the exact class of bug
  S13-18 was just cleaned up for, not stale data.
  `chassis/df_obj/vehicle_cls.py:620`, `chassis/df_obj/convoy_cls.py:320`,
  `chassis/df_obj/vendor_cls.py:780,823,854-855`, `engine/routers/vehicle_api.py:227`.
  Backend repo `~/Work/desolate_frontiers`.

- [x] **S13-22 · Neither settings slider has a numeric readout — "the values don't show up as I adjust
  them"** *(P2 — NEW, reported 2026-08-04; ✅ CODE-COMPLETE 2026-08-04, compile-checked + load-probed,
  pending an on-screen look)* — reported while running verification recipe ④. **Not** the S13-2 stale-value
  bug that recipe describes; a separate, previously unrecorded defect.
  **Verified root cause — the readout was never built.** `SettingsMenu.tscn` composes both rows as
  exactly two children: `UIScaleRow` = `[Label "UI Scale"][UIScaleSlider]` (`:224-238`) and
  `MenuWidthRow` = `[Label "Menu Width Ratio"][MenuWidthRatioSlider]` (`:240-254`). **No node in the
  scene displays either value**, and `settings_menu.gd` never wrote a number anywhere. So the slider
  handle moved and nothing else changed — exactly as reported.
  **Compounded on UI Scale by there being no visual effect either:** `_on_ui_scale_value_changed()` was
  a bare `pass` (`settings_menu.gd:325`) because `content_scale_factor` is too heavy to apply per-frame,
  so the scale only lands on `drag_ended`. Mid-drag there was neither a number nor a re-layout — nothing
  at all to indicate the control was live.
  **✅ Fix 2026-08-04, then REVERTED the same day — see the closing note.** Added `UIScaleValue` /
  `MenuWidthValue` Labels to the two rows and a `_update_slider_readouts()` driven from both sliders'
  `value_changed` plus `_init_values()`, so the number tracked the handle live.
  - **Second defect fixed in the same pass:** `_init_values()` assigned `s_ui_scale.value` /
    `s_menu_ratio.value` directly. Since S13-2 made that function re-run on **every** menu open, each
    open fired `value_changed` → `set_and_save`, writing the stored value back to disk. Worse, the
    assignment happens *after* `max_value` is narrowed to `get_max_safe_scale()`, so on a window small
    enough to clamp the stored scale, the **clamped value was silently persisted** — a real setting loss.
    Both assignments are now `set_value_no_signal()`. **This half is permanent** and outlived the
    readout — it is a real setting-loss bug, unrelated to display.
  **🔄 Readouts REMOVED 2026-08-04 at the reporter's request, once they had served their purpose.** They
  were the instrument used to calibrate the UI-scale and menu-width bands (S13-24, and the Sprint 11
  slider item); with those bands now set the numbers were clutter. **Removing them does *not* reinstate
  any bug** — verified 13/13 headless: the S13-23 commit paths, the `0.75 … 1.30` bounds and the
  out-of-bounds normalisation all still hold with the Labels gone. What remains from this entry is the
  `set_value_no_signal()` fix above and the knowledge, now documented, that the slider value is a lerp
  position.
  ⚠️ **The lerp-position trap outlived the readout.** `main_screen.gd:374,737` lerp
  `_opt_menu_ratio_open` between `_get_menu_ratios()`'s ends, so the stored `0..1` is **not** a screen
  fraction. **Any figure quoted from a screenshot of the old readout is a lerp position** and needs
  converting. Bands are now `UITheme.MENU_RATIO_*`; see the doc link on S13-24.
  `Scenes/SettingsMenu.tscn`, `Scripts/Menus/settings_menu.gd`.

- [x] **S13-23 · UI Scale slider silently discards most changes, and can't represent a scale above the
  window's ceiling — the "bar resets but the scale never changed, so I kept cranking it" bug**
  *(P1 — NEW, reported 2026-08-04; ✅ CODE-COMPLETE 2026-08-04, 10/10 headless regression tests, pending
  an on-screen look)* — reported as: *"after adjusting the UI scale and returning to the settings, the bar
  resets to its position but the UI scale didn't change. Allowing the user to further increase the scale
  and break the game."* **Two independent root causes, both verified.**
  **(1) `drag_ended`'s `changed` flag was the only commit gate.** `_on_ui_scale_drag_ended(changed)` ran
  `if changed: set_and_save(...)`. Godot's `Slider` computes that argument as *"did the value move between
  `drag_started` and `drag_ended`"* — and a **click on the track jumps the value on the press**, i.e.
  *before* the baseline (`grab.uvalue`) is captured. So a click-to-set reports **`changed == false`** and
  the new value was **thrown away**. Arrow keys and the mouse wheel are worse: they emit `value_changed`
  and **no `drag_ended` at all**, so they never had a commit path either. Only a grabber drag that
  physically moved ever persisted. On the next open `_init_values()` re-read the stored value and the
  handle snapped back — precisely "the bar resets and the scale never changed."
  **(2) The slider could not represent a stored scale above `get_max_safe_scale()`.** That ceiling is
  `window_width / 1150` — **1.67 on a 1920 window**, 2.23 at 2560, 2.99 at 3440 — recomputed from the
  *current* window on every open. **The reporter's live `user://settings.cfg` holds `ui.scale=3.65`**
  (read 2026-08-04; `ui_scale_manager` clamps to 4.0, so it was in force). The handle therefore pinned to
  max — a far lower position than the scale actually running — and dragging "up" from there committed a
  value *smaller* than 3.65, shrinking the UI. That is the mechanism behind "further increase the scale
  and break the game": the control could neither show the truth nor walk it back.
  **✅ Fix 2026-08-04:**
  - New `_commit_ui_scale()` is the single commit point. It compares against the **stored** value instead
    of trusting any signal argument, so every input path — grabber drag, track click, arrow keys, wheel —
    persists exactly once, and a genuine no-op still skips the heavy re-layout.
  - `drag_ended`'s `changed` argument is now **explicitly ignored** (commented as to why, so it doesn't
    get "tidied" back in). A new `_ui_scale_dragging` flag, set on `drag_started`, keeps `value_changed`
    from applying `content_scale_factor` on every frame of a drag — the reason the deferred-commit design
    existed in the first place.
  - `max_value` is now `maxf(get_max_safe_scale(), stored_scale)`. A slider that cannot display the scale
    in force is worse than one showing an out-of-range number: admitting the real value keeps it honest
    and, when the scale is already too large, **always draggable back down**. That is the recovery path
    out of a broken-scale state, which previously did not exist short of editing `settings.cfg`.
  ⚠️ **Not yet confirmed on a real screen.** Headless covers the commit matrix, not whether the re-layout
  after a commit looks right. **Note the reporter's saved scale is still `3.65`** — first launch after
  this lands should show the slider reading `3.65x` with room to drag down.
  🔗 **This gated the Sprint 11 "UI-scale slider" item — now unblocked and closed** (bounds `0.75`/`1.30`
  set 2026-08-04). Any ceiling chosen before this fix would have been tuned against a control that
  discarded most inputs. S12-1/S12-4 remain open.
  `Scripts/Menus/settings_menu.gd`, `Scripts/UI/UI_scale_manager.gd`.

- [x] **S13-24 · Menu-width slider band narrowed to the calibrated range** *(P2 — NEW,
  2026-08-04; ✅ CODE-COMPLETE, 12/12 headless, pending an on-screen look)* — follow-on from S13-22. The
  reporter calibrated on screen and asked for **min 15%, max 80%** — read off the then-new readout, which
  displayed the raw **lerp position**, not the screen fraction. Converted:
  `lerp(0.35, 0.85, 0.15) = 0.425` and `lerp(0.35, 0.85, 0.80) = 0.75`.
  - **Landscape band `0.35 … 0.85` → `0.425 … 0.75`** of viewport width. **Portrait deliberately
    unchanged** (`0.55 … 0.72` of *height*) — the calibration came from a desktop landscape session, and
    a bottom sheet at 42.5% of height would be too short to be useful.
  - **Bands moved to `UITheme` (`MENU_RATIO_*`)**, read by both `main_screen.gd::_get_menu_ratios()` and
    `settings_menu.gd`, so the control and the layout cannot drift apart.
  - The readout was briefly changed to resolve the true screen fraction, then **removed entirely later
    the same day** along with the UI-scale one (see S13-22). Showing the lerp position had meant a
    displayed "50%" was really 60% of the screen — which is exactly why the reporter could not say
    whether their numbers were screen fractions or slider positions when asked. Net effect on their saved
    `0.47`: **58.5% → 57.8%** of width, i.e. visually unchanged; only the *ends* of the range moved.
  - `main_screen.gd:379`'s hard `full_w * 0.85` backstop no longer binds at a 0.75 max; kept as a net.
  ⚠️ **Calibrated while `ui.scale` was 3.65** (logical viewport ≈ 526px), so the proportions may read
  differently now that the scale is capped at 1.30. Re-check on screen and adjust the two `UITheme`
  constants — it is a one-line edit each, by design.
  `Scripts/System/ui_theme.gd`, `Scripts/UI/main_screen.gd`, `Scripts/Menus/settings_menu.gd`.
  (Docs: [ui_system § `ui.menu_open_ratio` is a lerp position](02_UI_UX/ui_system.md#uimenu_open_ratio-is-a-lerp-position-not-a-screen-fraction).)

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

- [x] **S13-12 · `HTTPRequest` result codes are missing from `ErrorTranslator`** *(P2 — ✅ CODE-COMPLETE
  2026-07-31, compile-checked; split out of S13-8, 2026-07-29)* — a network-level failure
  currently surfaces to the player as raw internals. Every line in the Android log read
  `Unhandled API Error (add to ErrorTranslator): … Request failed with HTTPRequest result code: 3`, and
  the bug-report path produced `Bug report submit failed (HTTP 0): Unknown error.` The result codes are a
  small fixed enum and the messages write themselves — `RESULT_CANT_RESOLVE` / `RESULT_CANT_CONNECT` /
  `RESULT_CONNECTION_ERROR` / `RESULT_TIMEOUT` all collapse to "Can't reach the server — check your
  connection", and `RESULT_TLS_HANDSHAKE_ERROR` deserves its own message. This is the highest
  value-per-line item in the sprint: it turns every future network outage — on any platform — from an
  unhandled-error log line into a sentence the player understands.
  **✅ Implemented 2026-07-31.** Four new `ERROR_MAP` entries matching the substring `api_calls.gd:2542`
  already embeds (`"...Request failed with HTTPRequest result code: %s. URL: ..."`).
  - ⚠️ **The enum is not numbered the way it looks.** `RESULT_CHUNKED_BODY_SIZE_MISMATCH = 1` sits between
    `RESULT_SUCCESS` and `RESULT_CANT_CONNECT`, shifting everything after it. Verified against Godot 4.6:
    `CANT_CONNECT=2`, `CANT_RESOLVE=3`, `CONNECTION_ERROR=4`, `TLS_HANDSHAKE_ERROR=5`, `TIMEOUT=10`.
    2/3/4 collapse to *"Can't reach the server — check your internet connection."*; 10 gets its own
    timeout message; **5 was already mapped and its message was already right** — by luck, not by
    derivation (see the corrected comment below).
  - **Keys carry a trailing period** (`"result code: 2."`) because `translate()` matches by substring:
    without it, `"result code: 1"` would also match `10`. Code 5's pre-existing key is left un-suffixed to
    avoid perturbing a mapping already in the field.
  - **Corrected a wrong enum comment** at `api_calls.gd:2357`: `result == 5 # 5 = RESULT_SSL_HANDSHAKE_ERROR`
    — that name does not exist in Godot 4.x (it is `RESULT_TLS_HANDSHAKE_ERROR`) though `5` happened to be
    the right integer. Now written as the named constant, so the transient-retry set is legible and can't
    drift from the enum.
  - **The bug-report path reported nothing usable.** `api_calls.gd:2519-2520` produced
    `Bug report submit failed (HTTP 0): Unknown error.` — a network failure has no response body to parse,
    so `_get_error_message()` had nothing to work with. It now substitutes the result-code string when
    `response_code == 0`, which routes it through the same four new mappings.
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

- [ ] **S13-17 · Map labels layer over the convoy icon — the anti-collision exists but under-covers**
  *(P2 — reported 2026-08-04 with a screenshot: a settlement label ("Chicago" + `📦 Mail`) sits under a
  convoy arrow. **Researched against current code 2026-08-04, nothing coded.** Absorbs the Sprint 11
  "Convoy icon ↔ convoy label anti-collision" bullet and the *"nudge is vertical-only"* caveat on
  device-test **A4**.)*

  **The feature is not missing.** Both label systems already run an icon/route keepout every draw. This
  is a coverage + search-quality bug in code that is already there, so the fix is tuning and structure,
  not new machinery:

  | System | Placement + escape search | Icon keepout |
  |---|---|---|
  | Settlement labels | `UI_manager.gd::_position_settlement_panel` `:1612-1678` (loop `:1646-1674`) | `_settlement_panel_overlaps_convoy` `:1687-1707`, radius `settlement_convoy_keepout_radius = 24.0` (`:89`) |
  | Convoy labels | `convoy_label_manager.gd::_position_convoy_panel` `:411-524` (loop `:499-524`) | `_panel_overlaps_icon_or_route` `:530-561`, radius `_icon_keepout_radius_px = 18.0` (`:62`) |

  Five defects found, roughly in order of how much each explains the screenshot. **(1)–(3) are the
  headline; (4)–(5) are cheap fixes worth folding into the same pass.**

  1. **The escape search is vertical-only, fixed-step, and its exhaustion state is the *worst* position.**
     `UI_manager.gd:1646-1674` tries ≤20 offsets of `±label_anti_collision_y_shift` (`= 5.0`, `:87`),
     escalating by `ceil((attempt+1)/2)` — so the whole search covers **±50 world px** and never moves the
     label sideways (the convoy-label version at least flips sides every 4 attempts,
     `convoy_label_manager.gd:518-523`). Clearing a 24px keepout circle from a label whose half-height is
     already ~25 world px needs ~49px — the search range is *marginal at zoom 1 and insufficient below
     it*, because the panel is counter-scaled (`panel.scale = label_scale / zoom`, `:1513`) so its
     **world** height grows as you zoom out while the 5px step stays constant. Worse: the last iteration
     *sets* `attempt 19`'s position and exits without testing it, so an exhausted search leaves the label
     **50px below its desired spot — pushed down onto the tile and the icon**, i.e. the failure mode makes
     the collision worse than doing nothing. Same shape in `convoy_label_manager.gd:503-524`, which
     additionally uses `position.y += sign * shift` with an alternating sign, so it oscillates between
     **two** Y values per side instead of escalating.
  2. **The keepout circle is smaller than the arrow it is supposed to model.** The convoy icon is a
     world-space rotated triangle (`convoy_node.gd:14-18`, `:180-221`): tip at
     `(30 + 4.5) × 0.7 = 24.15` px from center, rear `9.45`, half-width `13.65` — then multiplied by a
     **throb of 1.0–1.2** every frame (`:22`, `:175-176`). So the true reach is **~24–29 px forward** and
     ~16px sideways, against a `24.0` keepout for settlement labels and `18.0` for convoy labels. The
     forward tip is outside the keepout circle *whenever the throb is above ~1.0*, and the convoy-label
     radius under-covers in every direction. A single symmetric radius also can't express the arrow's
     forward bias — an oriented capsule/AABB along `icon_sprite.rotation` would.
  3. **The two label systems are blind to each other.** `_draw_interactive_labels` seeds
     `all_drawn_label_rects_this_update` empty (`:607`) and fills it with **settlement panels only**
     (`:858`, `:866`); convoy labels are positioned afterwards (`:447` → `:456-466`) against their own
     separate rect list. So a settlement label and a convoy label can land on top of each other and
     neither loop will ever see it. **This is cheap to fix**: `SettlementLabelContainer`,
     `ConvoyLabelContainer` and `ConvoyIconContainer` are identity-transform siblings under
     `MapContainer/SubViewport` (`Scenes/MapView.tscn:47-58`), so all three coordinate spaces are already
     the same — the rects can be shared as-is, no transform needed.
  4. **The horizontal clamp runs *after* collision resolution and can push the label back into one.**
     `_clamp_settlement_panel_x()` is the last call in `_position_settlement_panel` (`:1678`), and
     `ConvoyLabelManager._clamp_label_within_bounds_if_convoy_visible()` is likewise applied post-hoc.
     Neither re-tests. The A5 edge/gear clamp (Sprint 9) can therefore silently undo the A4 nudge.
  5. **The "convoy parked here" clearance bump is exact-tile-match only.** `:1630-1637` adds `45.0` px of
     lift only when `cx == tile_x and cy == tile_y`. A convoy on an **adjacent** tile — which is what the
     screenshot shows — gets nothing, even though at the tileset's tile size one tile is smaller than the
     arrow's own length.

  **Suggested shape** (one pass over both systems):
  - Extract the keepout into one shared helper that models the icon as an **oriented** shape at max throb
    (or simply raise both radii to ≥30 and accept the slack), and feed it the same
    `_all_convoy_data_cache` both systems already hold.
  - Replace both escape searches with a **scored candidate list** — N/NE/E/SE/S/SW/W/NW at 2–3 distances,
    stepped in units of the panel's *own scaled height* rather than a constant world px — and **keep the
    best-scoring candidate** when nothing is fully clear, instead of falling out of the loop at the last
    tried offset.
  - Share one rect list across settlement + convoy labels for the frame (see (3)).
  - Re-test the collision **after** the X clamp, or clamp first and search within the clamped band.

  **Verify before coding** (two cheap checks that change the fix):
  - `Assets/tiles/tile_set.tres` declares **no** `tile_size`, so Godot's **16×16** default applies. If
    that holds, the arrow is ~1.5 tiles long and `base_settlement_offset_above_tile_center = 13.0`
    (`:50`) puts the label less than one tile above the tile centre — the geometry is inherently tight and
    the radii in (2) matter more than they look. Confirm the effective tile size in-editor first.
  - Convoy icons draw at `z_index = 10` (`convoy_visuals_manager.gd:5`) while both label containers sit at
    `LABEL_CONTAINER_Z_INDEX = 2` (`UI_manager.gd:149`), so the icon always paints **over** the label.
    That is why the overlap reads as "the arrow is on top of the text" and not as a hidden convoy. If
    perfect avoidance proves impossible at tight zooms, restacking is the fallback lever — but fix the
    search first; z-order only decides who wins the overlap, not whether it happens.

  **Repro / device test:** on the map with `settlement_labels` on, put a convoy on a tile **adjacent to**
  (not on) a labelled settlement that is also a cargo destination, so the label carries the extra `📦`
  line and is at its tallest. Zoom out one or two steps. Expected after the fix: the label dodges — up,
  down **or sideways** — and never sits under the arrow; the label must also still clear the screen edges
  and the gear box (A5) and stay off the route line during planning (A4), which are the two behaviors most
  at risk of regressing.

  `Scripts/UI/UI_manager.gd`, `Scripts/UI/convoy_label_manager.gd`, `Scripts/Map/convoy_node.gd`
  (icon geometry constants, read-only).

  - **Noticed while researching, not part of this bug — the convoy icon's runtime interpolation is dead
    code.** `_current_segment_start_idx` / `_progress_in_segment` are **read** in four places
    (`convoy_node.gd:99-100`, `map_camera_controller.gd:496-497`, `convoy_label_manager.gd:544`,
    `convoy_visuals_manager.gd:165`) and **written nowhere in the repo**. So `ConvoyNode._update_visuals()`
    always takes its fallback branch (`:135-139`), and `augment_convoy_data_with_offsets()`'s lane
    separation for convoys sharing a route segment (`convoy_visuals_manager.gd:164-211`) always resolves
    to `Vector2.ZERO` — that feature has never run. Harmless for S13-17 (the backend snaps convoys to
    integer route waypoints — `chassis/df_obj/convoy_cls.py:715` — so tile-centre math is correct today),
    but it means `convoy_label_manager.gd:548-552` always falls through to
    `_infer_route_segment_index_near_convoy()`. Fold into the **dead-code sweep** in the systems-audit
    initiative, or resurrect deliberately if smooth convoy movement is wanted.

---

# Device-test round 2 — the closeout gate

Run on a **touch device** (behaviors marked *touch* can't be proven in the editor). For each row: set the
orientation, do the gesture, confirm **new** vs **old**. Round 1 results (2026-07-21) are archived in
[SprintHistory.md](SprintHistory.md); these are the still-unchecked / re-test rows.

**Batch A — map / route** *(during a live convoy on the map)*
- [ ] **A1 · Labels tap-only** *(touch; portrait + landscape)* — pan-drag across settlements: labels must **not** flash under the finger; a settlement label reveals **only on an explicit tap**.
- [ ] **A3 · Hub vendor cards fit** *(mobile-landscape only)* — open a settlement with 3–4 vendors: all cards pack into one row, shorter, **no clip below the nav bar**, no scroll. (Re-check portrait/desktop unchanged.)
- [ ] **A4 · Labels dodge the route** *(portrait + landscape)* — start journey planning near labeled settlements: labels **nudge vertically off** the route line; topmost labels stay on-screen. *Known limit:* nudge is vertical-only — root-caused under **S13-17**, which also covers labels landing on the convoy icon.
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
- [ ] **S12-6 · Fullscreen shortcut** *(Windows + Mac)* — **the bindings are `F11` (both platforms),
  `Alt+Enter` on Windows/Linux, and `Cmd+Ctrl+F` on macOS.** Press to enter fullscreen and again to
  leave. The UI must re-lay-out correctly both ways (no offset — this is the failure mode
  `reapply_scale()` exists to prevent), the settings-menu checkbox must reflect the new state, and the
  state must survive a restart. **Also check the negatives:** plain `Enter` in a text field must not
  toggle, and `Cmd+F` / `Ctrl+F` alone must not either (both are Find). Matching logic is unit-tested
  11/11 headless; what is **untested** is the `DisplayServer` switch and the `reapply_scale()` after it.
- [ ] **S12-7 · Blank screen on first Steam launch** *(EXPORTED STEAM BUILD ONLY — the editor cannot
  prove this)* — export, launch via Steam with a Steam account **not** linked to a DF account. The top
  bar and map must render normally. Then check `user://logs/godot*.log`: `[RESIZE] map_rect` must have a
  **non-zero height** with y ≈ the top-bar height (80–160), and there must be **no `[MAP-RECT-DIAG]`
  block**. *Old:* `map_rect=[P: (0.0, 1610.136), S: (2133.0, 0.0)]` — zero height, pushed below a
  1338-tall viewport, leaving only the top bar's Oori tile on screen. If it still fails, the new
  `[MAP-RECT-DIAG]` dump names the control claiming the height — paste it into the issue.

**2026-07-31 batch — verification recipes** *(written with the code; none of these have been run)*

Ordered by risk. The first four are a ~5-minute desktop pass and cover the changes most likely to be
wrong; the rest need specific setup and can wait.

> **Results of the first pass — 2026-08-04.** ① and ③ **pass, device-verified.** ② is **blocked on
> Windows access** (the fullscreen problem was reported there and the reporter cannot test Windows at
> present) — the **macOS half is still runnable** and remains the open half of S12-6. ④ turned up a
> **different, previously unrecorded defect** — the two sliders have no numeric readout at all — logged
> and fixed as **S13-22** below; the S13-2 stale-value check that ④ actually describes is **still
> unrun.** ⑤–⑧ not yet attempted.

- [x] **① Feedback button placement + reachability (S12-5)** — ✅ **DEVICE-VERIFIED 2026-08-04.** Reporter
  confirms the button works. Closes the placement/hit-testing gap S12-5 flagged as its unproven half.
  Original recipe retained below.
  **highest blast radius: this button now renders on *every* screen in the game**, so a placement
  mistake is visible everywhere. Launch and look at the login screen **before signing in**: a small
  "Feedback" button sits bottom-left. Tap it — the window must **open and be interactive** (typing works;
  it is not frozen by `get_tree().paused`) and submit without error (it arrives with no user metadata,
  which is expected). Then in-game check it does **not** cover the mobile bottom nav bar, the map's gear
  tab, or a menu's own controls, in **both orientations**. Then mid-tutorial on a step with a highlight,
  and again with a menu open and with an error modal up — it must stay clickable in all of them.
  *Old:* no feedback affordance existed at login, and the window would have opened frozen.
  **Known-and-accepted:** two Feedback affordances now exist on the main screen (top bar + floating).
  Say so if that reads as clutter — hiding `%ReportBugButton` is a one-line follow-up.
- [ ] **② Fullscreen shortcut (S12-6)** — 🚧 **BLOCKED ON WINDOWS 2026-08-04.** The reporter has no
  Windows machine available to test against, and that is where the fullscreen problem was seen. **The
  macOS half is not blocked** and is the runnable part: press `F11` / `Cmd+Ctrl+F`, confirm the mode
  switches, **the UI does not lay out offset afterwards** (the untested half — this is what
  `reapply_scale()` exists to prevent), the settings checkbox flips **while the menu is open**, and the
  state survives a restart. Do the Mac pass now; hold the Windows pass until a machine is available.
- [x] **③ Pinned map label → preview arrow, on DESKTOP** — ✅ **DEVICE-VERIFIED 2026-08-04.** Reporter
  confirms the pinned label behaves correctly. Closes the originally-reported Sprint 11 bug.
- [ ] **④ Settings menu shows live values (S13-2)** — ⚠️ **STILL UNRUN 2026-08-04.** The 2026-08-04 pass
  reported *"the settings values are not showing up as I adjust the numbers"*, which is **the sliders
  having no readout** (now S13-22), **not** the stale-checkbox behaviour this recipe tests. The
  invert-pan re-read below has still never been exercised — run it. Steps:
  open Settings, note **Invert Pan**; close it;
  **log out and back in** (or change the setting elsewhere); reopen Settings. The checkbox must match the
  **stored** value, not the one captured when the menu was first built. Then toggle it once and confirm
  panning direction actually changes and **survives a restart**. *Old:* the stale checkbox wrote its own
  wrong value back on the next click — the "it flipped on its own" report.
  `_debug_settings_menu` is `true`, so `[SettingsMenu] _init_values: invert_pan loaded as …` prints on
  **every** open — use it as the proof, then consider flipping the flag off.
- [ ] **⑤ Onboarding loop (S12-8)** *(needs a **0-convoy account** — will not reproduce otherwise)* —
  sign in and read `user://logs/`. **Pass:** `[Onboarding] _show_new_convoy_dialog invoked.` appears
  **once**, followed by any number of `already open — ignoring repeat.` lines. *Old:* hundreds of full
  invocations, each costing a `/user/get`. Confirm the dialog still opens normally, and that cancelling
  and re-triggering it **opens again** (the guard must not latch).
- [ ] **⑥ Pre-login lag (S13-1)** *(macOS, fullscreen, same 0-convoy account)* — **take the measurement
  the entry asks for and never got:** compare login-screen FPS fullscreen vs. windowed. The original
  symptom was severe enough to stutter unrelated video playback, so check that too. Because ⑤ landed in
  the same session, attribute carefully — remaining CPU-side stutter points at the request loop,
  remaining GPU-side at the viewport.
- [ ] **⑦ Network error messages (S13-12)** *(airplane mode / Wi-Fi off)* — with the app running, kill
  connectivity and trigger any request. The player must see **"Can't reach the server — check your
  internet connection."**, not `Unhandled API Error (add to ErrorTranslator)`. Then submit a bug report
  while offline: it must report the same, not `Bug report submit failed (HTTP 0): Unknown error.`
- [ ] **⑧ Convoy list touch targets (S12-8, second defect)** *(mobile)* — open the convoy list, close and
  reopen it **several times**. Row touch-target sizing must stay correct on every open. *Old:* the
  `ResponsiveListAdapter` was destroyed on the first populate and never recreated, so sizing silently
  stopped being applied for the rest of the session.

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

- **TEST-02 · ~31 pre-existing `unused_variable` violations block a warnings gate** *(NEW, 2026-07-30,
  measured while writing [GDScript Verification](04_Technical/GDScriptVerification.md))* — promoting
  `debug/gdscript/warnings/unused_variable` to `2` for one probe run produced 31 `SCRIPT ERROR` lines
  from **existing** unused locals, several of them in autoloads, which breaks compilation before the
  probe reaches its targets. Files seen: `convoy_menu.gd`, `mechanics_menu.gd`, `warehouse_menu.gd`
  (5 sites), `tutorial_manager.gd`, `premium_upgrade_modal.gd`, `vendor_trade_panel.gd`. Until these are
  cleaned (delete or `_`-prefix), a repo-wide warnings gate — in CI or locally — cannot be turned on.
  Low priority; the cleanup is mechanical and each site is named in the probe output.

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
