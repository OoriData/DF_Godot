This document will serve as a flowing state of things needed in the project, what resources are needed for each task.

> **Status:** Items audited against current code 2026-06-25. File:line pointers and reuse targets captured in the **Code Map** below. Work is sequenced into Sprints for locality/efficiency.

---

# Action Plan (Sprints)

Ordered for efficiency: quick isolated wins first, then by code locality (one subsystem per sprint so each file is opened/tested once), heavier design work last. Settlement-lag investigation can run in parallel.

### Sprint 1 — Quick wins (isolated, low-risk, ship immediately) ✅ DONE 2026-06-26
One-liners and tiny changes with no shared surface. Knocks out 4 items fast.
- ✅ **Settings emoji** — U+FE0F alone was insufficient (⚙ U+2699 doesn't reach the emoji-font fallback on mobile). Replaced with a **texture icon** `Assets/Icons/gear.svg` (white-fill, matches `warehouse.svg` precedent), assigned via `_tab_button.icon`. `map_overlay_settings_panel.gd:165`.
- ✅ **Settlement Preview tab counts** — dropped the `(%d)` suffix from all 3 tab labels. `convoy_menu.gd:1407,1409,1411`.
- ✅ **Cargo sort/group label clarity** — now a **state-label toggle**: shows current grouping ("Sort by: Vehicle" / "Sort by: Type") with a per-mode tint (teal vs brass) so the two positions read as distinct. `convoy_cargo_menu.gd` `_update_organize_button_text` / `_apply_organize_button_style`.
- ↩️ **Portrait zoom-out limit (~3×)** — **REVERSED 2026-06-26 after on-device review.** The 3× relaxation worked but exposed empty space beyond the map edges (letterbox), which the player rejected: requirement is now **map must always fully cover the screen — no empty space ever**. `portrait_extra_zoom_out` is kept as an export but **locked at `1.0`** (zoom-out floor stays at the COVER fill). The `_update_camera_limits` relaxation block is now a no-op. `map_camera_controller.gd:35,309-311`.
- ✅ **Journey route fit zoom locked at cover floor** — `smooth_fit_world_rect` was capping the route-preview zoom at `min_camera_zoom_level` (the COVER fill floor), preventing long routes from fitting both endpoints on screen. Added `route_fit_allow_zoom_past_cover: bool = true` export; when true the cap is bypassed for route fits. The cover floor is still enforced for normal pan/zoom and menu close. `map_camera_controller.gd` (`smooth_fit_world_rect`, ~line 727).

### Sprint 2 — Map camera & overlay subsystem ✅ DONE 2026-06-26
All in `map_camera_controller.gd` + `map_overlay_settings_panel.gd` + safe-area plumbing. ⚠️ **All four need on-device verification** (notch behavior, font sizing, label headroom, close animation can't be confirmed off-device).
- ✅ **Notch / Dynamic Island safe area** — overlay panel now queries `ui_scale_manager.get_logical_safe_margins()` (new `_get_logical_safe_margins()` helper). Portrait top cutout: `safe.position.y` added to the content panel's `content_margin_top` in `_build_ui`. Landscape side cutout: panel + collapsed gear tab shifted right by `safe.position.x` in `_update_layout` (both expanded and collapsed targets). `safe_left ≈ 0` on non-notched layouts → no regression. `map_overlay_settings_panel.gd`.
- ✅ **Map overlay panel double-scaling** — `_get_font_size()` flattened to `return base` (dropped the 2.6× portrait / 1.35× landscape / 1.6× desktop boost). Fonts now ride `content_scale_factor` like the migrated menus. `map_overlay_settings_panel.gd:39-43`.
- ✅ **Fit Convoy Route clips city labels** — labels are screen-stable, so room is reserved in **screen space**: `_estimate_fit_zoom()` predicts the fit zoom, then the route bounds grow by `route_fit_label_padding_px / zoom` (new export, default `Vector2(110, 80)` px/side) before `smooth_fit_world_rect`. `map_camera_controller.gd` (`smooth_fit_route_preview`). ⚠️ tune `route_fit_label_padding_px` on device if labels still clip / route reads too small.
- ✅ **Menu close renders off-map then snaps back (portrait)** — `set_overlay_occlusion()` now enforces `_clamp_camera_position()` every frame while the overlay is **shrinking** (menu closing) even with the convoy-recenter focus tween active; the growing/opening case keeps the old no-snap behavior. The clamp acts as a moving ceiling the camera follows in smoothly instead of snapping at the end. `map_camera_controller.gd` (`set_overlay_occlusion`).

### Sprint 3 — Baby-blue → Oori token sweep ✅ DONE 2026-06-26
Mechanical, reviewable-as-one-diff. The brand palette has **no blue** by design; each blue must be *mapped* to a token (decision baked in below, adjustable). Do this before Sprint 4 layout reworks so layout happens on already-themed code.
- ✅ **Journey progress fill** `#29b6f6` → `UITheme.ACCENT_VERDIGRIS`. `convoy_menu.gd` (const dropped — autoload tokens aren't compile-time consts; applied inline at the fill StyleBox ~:2876) and `convoy_journey_menu.gd:361,366`.
- ✅ **Convoy-list destination text** `#29b6f6` → `TEXT_MUTED` (dropdown items :248, toggle-button BBCode :483 via `TEXT_MUTED.to_html()`, plus matching strip at :494); active highlight `LIGHT_SKY_BLUE` → `ACCENT_BRASS` modulate :507. `convoy_list_panel.gd`.
- ✅ **Vehicle tappable-stat button** navy → `METAL_BASE` fill + `ACCENT_BRASS` border; hover/pressed → `METAL_HOVER`/`METAL_ACTIVE`. `convoy_vehicle_menu.gd:849-863`.
- ✅ **Extended navy sweep (vehicle + journey + MenuBase)** — the initial 3 bullets only caught the brightest blues; a follow-up pass found the full **navy-chrome family** (dark navy container fills, steel-blue borders, light-blue label/value text) the user was seeing as "baby-blue boxes." Mapped via `Color(token, alpha)` (alpha preserved): fills→`METAL_BASE`/`METAL_DARK`, borders→`METAL_EDGE` (subtle) or `ACCENT_BRASS` (active/action edges, e.g. Top Up button, selected tab), hover/pressed→`METAL_HOVER`/`METAL_ACTIVE`, label text→`TEXT_PRIMARY`/`TEXT_MUTED`, interactive text→`ACCENT_BRASS`. **73 replacements** across `convoy_vehicle_menu.gd`, `convoy_journey_menu.gd`, `MenuBase.gd` (incl. the shared `style_back_button` navy). **Intentionally preserved:** `MenuBase._slot_accent` categorical palette (blue=transmission, purple=tires, etc. — encodes part category, not chrome). ⚠️ Not yet swept: `warehouse_menu`, `mechanics_menu`, `convoy_cargo_menu`, `inspector_builder`, `map_overlay_settings_panel`, plus the cyan accents (`0.0,0.66,1.0` / `0.35,0.8,0.95`) — Sprint 4.
- Tokens live in `ui_theme.gd:15-41`. Heaviest remaining raw-color menus: `warehouse_menu` (68), `convoy_cargo_menu` (58) — fold their token adoption into Sprint 4.

### Sprint 4 — Per-menu layout bundles
Each menu is self-contained; do layout + remaining token adoption in one pass per file.
- **Cargo (portrait)** — item-card reorg (tighter vertical rhythm, kill mid-card dead space), spread cramped top buttons, cap/right-align the sort control. Overlaps UIAudit Visual **P3** (sparse cards) + **P7** (oversized sort dropdown). `convoy_cargo_menu.gd`.
- **Cargo single-expand on mobile** — only one cargo item may be expanded at a time on mobile; tapping a second collapses the first. Desktop can keep multiple open simultaneously. `convoy_cargo_menu.gd`.
- **Cargo touch-highlight stuck** — dragging a finger across cargo cards sometimes leaves a hover highlight permanently visible even when the card isn't selected. Fix touch-enter/touch-exit event handling so highlights clear on finger lift/leave. `convoy_cargo_menu.gd`.
- **Mechanics Parts/Cart tabs** — tab strip needs Oori token colors (currently unstyled/default), taller hit targets for mobile tap comfort. `mechanics_menu.gd` tab container.
- **Convoy stats → tap-to-breakdown modal** — reuse the vehicle menu's pattern verbatim. `convoy_vehicle_menu.gd:1291` (`_on_inspect_stat_pressed`) + helpers `_make_inspect_overlay` / `_make_inspect_panel` / `_add_kv_row`. Wire convoy stat boxes (`convoy_menu.gd:971-995`). Overlaps UIAudit Visual **P4** (stat hierarchy).
- **Journey loading bar** — upgrade the existing text indicator into an animated bar during route plotting. Hook `route_choices_request_started` → `route_choices_ready`/`error`. `convoy_journey_menu.gd` (`_show_loading_indicator`, signals at :121-126). Reuse the animated `ProgressBar` from `login_screen.gd:152-154`.
- **Journey route line — faint while on other menu, hidden when menus closed** — the route preview line should be semi-transparent/faint when the journey is still being plotted but the user has navigated to a different menu tab (not fully closed); it should disappear entirely only when all menus are fully closed. ⚠️ May interact with map overlay options toggle — verify the overlay layer visibility doesn't fight this. `convoy_journey_menu.gd`; check `map_overlay_settings_panel.gd` layer interaction.
- **Journey confirmation label/value gap (landscape)** — tighten the resource table column gap. `convoy_journey_menu.gd` confirmation panel.
- **Select Convoy drawer (portrait)** — widen the popup beyond button width, scrollable card list. `convoy_list_panel.gd` (`ConvoyPopup`); also fixes the `DisplayServer.window_get_size()` logical-pixel bug at :92 while in here.

### Sprint 5 — Vendor menu restructure (design-heavy, cross-file)
Moves controls across three surfaces; do last.
- **Warehouse** button → bottom nav bar (`menu_manager.gd` `_setup_static_bottom_nav` / StaticBottomNav).
- **Top Up** button → Base Convoy Menu (`convoy_menu.gd`).
- **Settings** → expandable side **drawer** (`vendor_trade_panel.gd`).
- **Warehouse access without convoy in settlement** — players currently can't open the warehouse if no convoy is present at the settlement. Add a path to reach the warehouse menu independent of convoy presence (e.g. via the bottom nav or a settlement overview screen). `menu_manager.gd`, `vendor_trade_panel.gd` / `warehouse_menu.gd`.
- While here: verify/remove the legacy `BottomBarPanel` duplicate nav (UIAudit Visual **P2**, Cross-Cutting #3).

### Parallel investigation — Settlement menu open lag (iOS)
Profile `convoy_settlement_menu.gd` open path (`_ready` / first-open layout build vs data fetch). Likely synchronous layout/tab construction on open. Confirm on device before optimizing (defer heavy build, or pre-warm).

---

# Code Map (resources per task)

| Task | Primary file:line | Reuse / Notes |
|---|---|---|
| Settings emoji (mobile) | `map_overlay_settings_panel.gd:166` | ✅ done — texture icon |
| Map overlay double-scaling | `map_overlay_settings_panel.gd:39-42` | ✅ done — flattened boost |
| Notch / safe area | `safe_area_handler.gd`, `UI_scale_manager.gd:109-121` | ✅ done — `get_logical_safe_margins()` |
| Fit-route clips labels | `map_camera_controller.gd` `smooth_fit_route_preview` | ✅ done — `route_fit_label_padding_px` export |
| Close shows off-map | `map_camera_controller.gd` `set_overlay_occlusion` | ✅ done — clamp enforced during shrink |
| Settlement Preview counts | `convoy_menu.gd:1407,1409,1411` | ✅ done — no `(%d)` |
| Cargo sort label | `convoy_cargo_menu.gd` `_update_organize_button_text` | ✅ done — state label + tint |
| Baby-blue sweep | `ui_theme.gd:15-41` (tokens) | map per-use; no blue token exists |
| Journey route line (faint/hidden) | `convoy_journey_menu.gd`, `map_overlay_settings_panel.gd` | faint when on other menu tab; hidden when menus closed |
| Journey loading bar | `convoy_journey_menu.gd:121-126` | reuse `login_screen.gd:152-154` ProgressBar |
| Journey confirmation gap | `convoy_journey_menu.gd` confirm panel | landscape resource table |
| Convoy stats modal | `convoy_vehicle_menu.gd:1291` | reuse `_on_inspect_stat_pressed` + `_make_inspect_*` |
| Cargo cards / buttons | `convoy_cargo_menu.gd` | portrait layout; 58 raw colors |
| Cargo single-expand (mobile) | `convoy_cargo_menu.gd` | collapse previous on new expand; mobile-only |
| Cargo touch-highlight stuck | `convoy_cargo_menu.gd` | fix touch-enter/exit; clear on finger lift |
| Mechanics Parts/Cart tabs | `mechanics_menu.gd` tab container | Oori token colors; taller tap targets |
| Select Convoy drawer | `convoy_list_panel.gd:92` | widen `ConvoyPopup`; fix logical-pixel bug |
| Vendor restructure | `vendor_trade_panel.gd`, `menu_manager.gd`, `convoy_menu.gd` | warehouse→nav, topup→convoy, settings→drawer |
| Warehouse without convoy | `menu_manager.gd`, `warehouse_menu.gd` | access warehouse independent of convoy presence |
| Settlement lag | `convoy_settlement_menu.gd` `_ready` | profile on iOS first |
| Settlement labels — touch only | map settlement label script | mobile: tap-to-show only; desktop: keep hover |
| Landscape nav fill | `menu_manager.gd` StaticBottomNav | expand buttons to fill bar width in landscape |
| Landscape zoom unlock | `map_camera_controller.gd` | same zoom-past-cover unlock as portrait |
| Menu button mashing / stuck state | `menu_manager.gd` transition logic | guard transitions; ignore input while animating |
| Cart slot conflict error | `mechanics_menu.gd` / cart system | error on install when slot already occupied in cart |
| Compatibility preloading | `mechanics_menu.gd`, cart system | preload all convoy vehicles on menu open; show "N upgrades available" per vehicle; cart must handle multi-vehicle multi-upgrade |

**Migration status (UITheme adoption):** ✅ `convoy_menu`, `convoy_vehicle_menu`, `mechanics_menu`, `vendor_trade_panel`, `MenuBase` · ⚠️ `convoy_journey_menu` (navy chrome tokenized Sprint 3; other raw colors remain), `convoy_settlement_menu` (partial) · ❌ `convoy_cargo_menu`, `warehouse_menu` (raw colors).

---

# Backlog

Not blocking the sprints above. Pull into a sprint when the relevant file is already open, or batch into a future sprint. Verify each against current code before acting — these are point-in-time.

## Bugs

- **Settlement labels appear during pan (mobile)** — Labels currently trigger during pan gestures; they should only appear on explicit tap/touch. Desktop retains the hover mechanic. Investigate the label display trigger in the settlement label script (likely tied to `InputEventScreenTouch` vs `InputEventMouseMotion`). Mobile-only change — guard behind `OS.has_feature("mobile")` or equivalent.
- **Orientation change doesn't reflow layout** — Switching between portrait and landscape mid-session can leave menus in the wrong layout mode (e.g. parts cards stay in horizontal-scroll after rotating back to portrait) until the menu is closed and reopened. Layout rebuild must be triggered on orientation change, not only on open. Affects any menu with orientation-branched layout; `mechanics_menu.gd` parts scroll is the confirmed case. Check `_notification(NOTIFICATION_WM_SIZE_CHANGED)` / `get_viewport().size_changed` handling in each affected menu.
- **Menu button mashing — UI duplication / stuck state** — Tapping nav buttons rapidly can cause menus to duplicate on screen or get stuck mid-transition (partially on/off screen). Transition logic needs to guard against input while a tween is already running; buffer or ignore subsequent taps until the current transition completes. `menu_manager.gd`.
- **Cart slot conflict on part install** — Selecting a part to install when that vehicle slot already has a pending item in the cart throws an error instead of prompting to replace. Handle gracefully: either swap the pending item or surface a clear "replace?" confirmation. `mechanics_menu.gd` / cart system.
- **Modals still double-scale fonts** — `auto_sell_receipt_modal.gd`, `returning_player_tips_modal.gd`, `discord_link_popup.gd`, `account_links_popup.gd` still use the `_get_font_size()` boost pattern. Flatten to `return base` like the migrated menus.

## Polish / UX

- **Landscape zoom unlock** — Portrait mode now allows zooming past the cover floor for route fits (`route_fit_allow_zoom_past_cover`). Apply the same unlock in landscape so long routes also fit on screen without clipping. `map_camera_controller.gd`.
- **Mechanics compatibility preloading** — Currently the menu makes an API call per vehicle when checking compatible parts, requiring a loading state. Instead: preload compatibility data for all convoy vehicles when the mechanics menu first opens, then show "N upgrades available" on each vehicle card before the user taps in. Requires the cart system to be extended to handle multiple vehicles and multiple pending upgrades simultaneously. `mechanics_menu.gd`, cart system.
- **Landscape nav buttons — fill width** — Bottom nav bar buttons in landscape don't utilize available horizontal space. Expand them to fill or evenly distribute across the bar. `menu_manager.gd` StaticBottomNav.
- **Parts/service cards — horizontal scroll in landscape** — Cards don't fit cleanly in vertical layout in landscape. Convert to horizontal scrolling (pan side to side) so cards have room.
- **Convoy name label (P5)** — floats unanchored above the panel; integrate as a styled header. `convoy_menu.gd` TitleLabel.
- **Resource-bar text contrast (P6)** — low contrast at high fill; add outline or bump font weight. `convoy_menu.gd` ResourceStatsHBox.
- **HSeparators near-invisible (P8)** — on dark bg, replace with section labels or themed dividers.
- **Global spacing consistency (P9)** — `UITheme.SPACE_*` tokens exist but adoption is incomplete across menus.

## Tech Debt

- Duplicate Oori palette `const`s in `user_info_display.gd`, `convoy_settlement_menu.gd`, `convoy_list_panel.gd` — migrate to `UITheme.*`.
- Modals use hardcoded absolute center offsets — `auto_sell_receipt_modal`, `returning_player_tips_modal`, `premium_upgrade_modal`; replace with `CenterContainer`.
- `SettingsMenu` opened outside `MenuManager` (CanvasLayer layer=100) — lifecycle inconsistency.
- `UserInfoDisplay` height changes not signaled → stale `offset_top` on submenus.
- `main_screen.gd` wires convoy button via fragile `find_child()`.
- S/M/L UI-scale preference silently overridden in portrait.
