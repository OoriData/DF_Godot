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

### Sprint 2 — Map camera & overlay subsystem ✅ DONE 2026-06-26
All in `map_camera_controller.gd` + `map_overlay_settings_panel.gd` + safe-area plumbing. ⚠️ **All four need on-device verification** (notch behavior, font sizing, label headroom, close animation can't be confirmed off-device).
- ✅ **Notch / Dynamic Island safe area** — overlay panel now queries `ui_scale_manager.get_logical_safe_margins()` (new `_get_logical_safe_margins()` helper). Portrait top cutout: `safe.position.y` added to the content panel's `content_margin_top` in `_build_ui`. Landscape side cutout: panel + collapsed gear tab shifted right by `safe.position.x` in `_update_layout` (both expanded and collapsed targets). `safe_left ≈ 0` on non-notched layouts → no regression. `map_overlay_settings_panel.gd`.
- ✅ **Map overlay panel double-scaling** — `_get_font_size()` flattened to `return base` (dropped the 2.6× portrait / 1.35× landscape / 1.6× desktop boost). Fonts now ride `content_scale_factor` like the migrated menus. `map_overlay_settings_panel.gd:39-43`.
- ✅ **Fit Convoy Route clips city labels** — labels are screen-stable, so room is reserved in **screen space**: `_estimate_fit_zoom()` predicts the fit zoom, then the route bounds grow by `route_fit_label_padding_px / zoom` (new export, default `Vector2(110, 80)` px/side) before `smooth_fit_world_rect`. `map_camera_controller.gd` (`smooth_fit_route_preview`). ⚠️ tune `route_fit_label_padding_px` on device if labels still clip / route reads too small.
- ✅ **Menu close renders off-map then snaps back (portrait)** — `set_overlay_occlusion()` now enforces `_clamp_camera_position()` every frame while the overlay is **shrinking** (menu closing) even with the convoy-recenter focus tween active; the growing/opening case keeps the old no-snap behavior. The clamp acts as a moving ceiling the camera follows in smoothly instead of snapping at the end. `map_camera_controller.gd` (`set_overlay_occlusion`).

### Sprint 3 — Baby-blue → Oori token sweep
Mechanical, reviewable-as-one-diff. The brand palette has **no blue** by design; each blue must be *mapped* to a token (decision baked in below, adjustable). Do this before Sprint 4 layout reworks so layout happens on already-themed code.
- Journey progress fill `#29b6f6` → `UITheme.ACCENT_VERDIGRIS` (progress/resource signal). `convoy_menu.gd:39`, `convoy_journey_menu.gd:361,366`.
- Convoy-list destination text `#29b6f6` + active `LIGHT_SKY_BLUE` → `ACCENT_BRASS` (active) / `TEXT_MUTED` (dest). `convoy_list_panel.gd:483,507`.
- Vehicle tappable-stat button navy (`0.18,0.22,0.32` / border `0.35,0.48,0.72`) → `METAL_BASE` + `ACCENT_BRASS` accent. `convoy_vehicle_menu.gd:849-863` (semi-intentional — tokenize, don't delete).
- Tokens live in `ui_theme.gd:15-41`. Heaviest remaining raw-color menus: `convoy_journey_menu` (73), `warehouse_menu` (68), `convoy_cargo_menu` (58) — fold their token adoption into Sprints 3/4.

### Sprint 4 — Per-menu layout bundles
Each menu is self-contained; do layout + remaining token adoption in one pass per file.
- **Cargo (portrait)** — item-card reorg (tighter vertical rhythm, kill mid-card dead space), spread cramped top buttons, cap/right-align the sort control. Overlaps UIAudit Visual **P3** (sparse cards) + **P7** (oversized sort dropdown). `convoy_cargo_menu.gd`.
- **Convoy stats → tap-to-breakdown modal** — reuse the vehicle menu's pattern verbatim. `convoy_vehicle_menu.gd:1291` (`_on_inspect_stat_pressed`) + helpers `_make_inspect_overlay` / `_make_inspect_panel` / `_add_kv_row`. Wire convoy stat boxes (`convoy_menu.gd:971-995`). Overlaps UIAudit Visual **P4** (stat hierarchy).
- **Journey loading bar** — upgrade the existing text indicator into an animated bar during route plotting. Hook `route_choices_request_started` → `route_choices_ready`/`error`. `convoy_journey_menu.gd` (`_show_loading_indicator`, signals at :121-126). Reuse the animated `ProgressBar` from `login_screen.gd:152-154`.
- **Journey confirmation label/value gap (landscape)** — tighten the resource table column gap. `convoy_journey_menu.gd` confirmation panel.
- **Select Convoy drawer (portrait)** — widen the popup beyond button width, scrollable card list. `convoy_list_panel.gd` (`ConvoyPopup`); also fixes the `DisplayServer.window_get_size()` logical-pixel bug at :92 while in here.

### Sprint 5 — Vendor menu restructure (design-heavy, cross-file)
Moves controls across three surfaces; do last.
- **Warehouse** button → bottom nav bar (`menu_manager.gd` `_setup_static_bottom_nav` / StaticBottomNav).
- **Top Up** button → Base Convoy Menu (`convoy_menu.gd`).
- **Settings** → expandable side **drawer** (`vendor_trade_panel.gd`).
- While here: verify/remove the legacy `BottomBarPanel` duplicate nav (UIAudit Visual **P2**, Cross-Cutting #3).

### Parallel investigation — Settlement menu open lag (iOS)
Profile `convoy_settlement_menu.gd` open path (`_ready` / first-open layout build vs data fetch). Likely synchronous layout/tab construction on open. Confirm on device before optimizing (defer heavy build, or pre-warm).

---

# Code Map (resources per task)

| Task | Primary file:line | Reuse / Notes |
|---|---|---|
| Settings emoji (mobile) | `map_overlay_settings_panel.gd:166` | `"⚙"`→`"⚙️"` or texture icon |
| Map overlay double-scaling | `map_overlay_settings_panel.gd:39-42` | flatten boost → `return base` |
| Notch / safe area | `safe_area_handler.gd`, `UI_scale_manager.gd:109-121` | `DisplayServer.get_display_safe_area()` |
| Portrait zoom-out ×3 | `map_camera_controller.gd:8,281-294` | relax `auto_limit_zoom_out` floor in portrait |
| Fit-route clips labels | `map_camera_controller.gd:360` + route-fit | pad fit rect for world-space label extents |
| Close shows off-map | `map_camera_controller.gd:544` | enforce clamp through close tween |
| Settlement Preview counts | `convoy_menu.gd:1407,1409,1411` | ✅ done — labels are now plain, no `(%d)` |
| Convoy stats modal | `convoy_vehicle_menu.gd:1291` | reuse `_on_inspect_stat_pressed` + `_make_inspect_*` |
| Cargo cards / buttons / sort | `convoy_cargo_menu.gd` `_update_organize_button_text` | ✅ done — state label + tint; not on UITheme yet (58 raw colors) |
| Journey loading bar | `convoy_journey_menu.gd:121-126` | reuse `login_screen.gd:152-154` ProgressBar |
| Journey confirmation gap | `convoy_journey_menu.gd` confirm panel | landscape resource table |
| Select Convoy drawer | `convoy_list_panel.gd:92` | widen `ConvoyPopup`; fix logical-pixel bug |
| Vendor restructure | `vendor_trade_panel.gd`, `menu_manager.gd`, `convoy_menu.gd` | warehouse→nav, topup→convoy, settings→drawer |
| Settlement lag | `convoy_settlement_menu.gd` `_ready` | profile on iOS first |
| Baby-blue sweep | `ui_theme.gd:15-41` (tokens) | map per-use; no blue token exists |

**Migration status (UITheme adoption):** ✅ `convoy_menu`, `convoy_vehicle_menu`, `mechanics_menu`, `vendor_trade_panel` · ⚠️ `convoy_settlement_menu` (partial) · ❌ `convoy_cargo_menu`, `convoy_journey_menu`, `warehouse_menu` (raw colors).

---

# UIAudit Reconciliation

[`docs/02_UI_UX/UIAudit.md`](02_UI_UX/UIAudit.md) was the prior workstream. Verified against current code:
- **Visual P3** (sparse cargo cards), **P4** (stat label/value hierarchy), **P7** (oversized sort dropdown) → **folded into the new TODOs** (Sprint 4).
- **Visual P2** (legacy `BottomBarPanel` dup nav) → handled in Sprint 5.
- **Double-scaling "complete" claim (UIAudit:209)** → **inaccurate**: menus migrated, `map_overlay_settings_panel` fixed 2026-06-26. **Remaining modals still boost**: `auto_sell_receipt_modal.gd`, `returning_player_tips_modal.gd`, `discord_link_popup.gd`, `account_links_popup.gd` — see Sprint 2.
- **Visual P1** (tab active state) → verify during Sprint 4 (convoy_menu is now heavily themed; may already be addressed).
- **Visual P1** (tab active state) → verify during Sprint 4 (convoy_menu is now heavily themed; may already be addressed).

---

# Tech-Debt & Polish Backlog

Relocated from UIAudit (2026-06-25) so the audit stays a structural map. Not blocking the sprints above; pull into a sprint when a relevant file is open. Verify each against current code before acting — these are point-in-time.

**Visual polish (UIAudit Visual Audit P5/P6/P8/P9):**
- P5 — convoy name label floats unanchored above the panel; integrate as a styled header. `convoy_menu.gd` TitleLabel.
- P6 — resource-bar text contrast low at high fill; add outline / bump font. `convoy_menu.gd` ResourceStatsHBox.
- P8 — `HSeparator`s near-invisible on dark bg; theme or replace with section labels.
- P9 — global spacing consistency; **partly solved** — `UITheme.SPACE_*` tokens now exist, adoption incomplete.

**Cross-cutting tech debt (UIAudit Cross-Cutting Summary):**
- Duplicate Oori palette `const`s still in `user_info_display.gd`, `convoy_settlement_menu.gd`, `convoy_list_panel.gd` — migrate to `UITheme.*`.
- `DisplayServer.window_get_size()` (logical-pixel violation) in `convoy_list_panel.gd:92` — fix during the Select Convoy drawer sprint.
- Legacy `BottomBarPanel` dup nav in `ConvoyMenu.tscn` — remove during vendor restructure sprint.
- Modals use hardcoded absolute center offsets (not `CenterContainer`) — `auto_sell_receipt_modal`, `returning_player_tips_modal`, `premium_upgrade_modal`.
- `SettingsMenu` opened outside `MenuManager` (CanvasLayer layer=100) — lifecycle inconsistency.
- `UserInfoDisplay` height changes not signaled → stale `offset_top` on submenus.
- `main_screen.gd` wires convoy button via fragile `find_child()`.
- S/M/L UI-scale preference silently overridden in portrait.
- Modals not styled with Oori theme (folds into the baby-blue / theming sweep).
- Floating panels/modals still double-scale fonts (see Sprint 2 + font-scale note).

**Docs needing a standalone page (if they become a change target):** `UserInfoDisplay`+`ConvoyListPanel`, `SettingsMenu`, `RouteSelectionMenu`.

---

# Item Detail

## Bugs

### Settings emoji not rendering on map overlay options tab (mobile)
The settings icon/emoji on the map overlay options tab fails to render on mobile (portrait and landscape). Desktop appears unaffected. Root cause: the tab button uses bare `"⚙"` (U+2699, no U+FE0F emoji-presentation selector), which Lexend renders as a missing glyph on mobile; the toggle-row icons (🎯📦🚚) are true emoji and fall back fine. Fix: append the variation selector or use a texture-based icon.

### Auto zoom (Fit Convoy Route) clips city labels
When Fit Convoy Route auto-zoom triggers, city labels are visible but clipped at the edges of the viewport. Labels exist, they're just cut off. The fit math frames the route/tilemap geometry but ignores world-space label extents that overflow node bounds — add padding to the fit rect so labels have room.

### Settlement menu lag on open (iOS)
Noticeable hitch when opening the settlement menu on iOS. First noticed on device but may affect other platforms. Investigate whether the lag is in layout building (node instantiation/resizing on open) or data fetching. Likely candidate: synchronous layout/tab construction on first open — profile before optimizing.

### Menu close animation shows outside map bounds (portrait)
When closing a menu in portrait, the camera briefly renders outside the map bounds during the closing animation, then snaps back once the animation completes. The clamp is re-applied at the end of the transition but not enforced mid-animation.

### Dynamic Island / notch safe area not respected
UI elements (including map options overlay) render underneath the Dynamic Island or notch on devices where it's open. Reserve that space using iOS safe-area insets so nothing interactive or informational sits beneath the cutout.

---

## Improvements

### Increase portrait map zoom-out limit (~3x current max)
The current maximum zoom-out in portrait is too restrictive. Increase it to ~3× current. Note the floor is governed by `auto_limit_zoom_out` (keeps the map filling the viewport) — achieving 3× more zoom-out means relaxing that in portrait (accepting letterbox / edge exposure), not just lowering the raw `min_camera_zoom_level`.

### Cargo menu portrait layout — item card reorganization
In portrait, item cards are wide and flat with excessive vertical padding and small text, leaving dead space in the middle of each card. Tighten into a more information-dense layout (tighter vertical rhythm, better horizontal use). Overlaps UIAudit Visual P3.

### Cargo menu top buttons cramped in portrait
The action buttons at the top of the cargo menu are stacked too tightly in portrait. Spread them out or rearrange for portrait widths.

### ✅ Cargo menu sort toggle labels — DONE 2026-06-26
The toggle is now a state label: "Sort by: Vehicle" / "Sort by: Type" with a per-mode tint (teal/brass). Tapping switches to the other mode.

### Vendor menu — restructure top controls
The vendor settings panel is proportionally fluid and visually inconsistent with the other controls. Restructure:
- **Warehouse button** → move into the bottom nav bar alongside the other menu-switching buttons
- **Top Up button** → move to the Base Convoy Menu (main convoy overview screen)
- **Settings** → replace the inline settings panel with an expandable side drawer

Clears the top of the vendor menu and makes settings feel intentional rather than crammed in.

### Select Convoy dropdown too small in portrait (top nav bar)
The Select Convoy control is currently a small dropdown roughly the button's width. Expand into a wider panel so the full convoy card is visible — scrollable list of cards stacked vertically.

### Settlement Preview — remove item count from tab labels
The Settlement Preview tabs show a count in parentheses e.g. "(10)". Remove these entirely — noise without value at that point in the flow.

### Convoy menu stats — tap to open breakdown modal
Convoy menu stats should be tappable, opening the same breakdown modal that already exists for parts and vehicles. Reuse the vehicle menu's inspect pattern.

### Parts/service cards — horizontal scroll in landscape
When viewing vehicle parts or service options in landscape, cards don't fit cleanly in the vertical layout. Convert the parts/service card list to horizontal scrolling (pan side to side) in landscape so cards have room.

### Journey plotting — add loading bar while API works
While the API plots the journey route there's no feedback. Add an animated loading bar during the wait. A text indicator already exists (`_show_loading_indicator`); upgrade it to a bar driven off the `route_choices_request_started`/`ready` signals. Reuse the login screen's animated ProgressBar.

### Journey confirmation screen — resource label/value gap (landscape)
In the journey confirmation screen on landscape, resource labels and their stat values are far apart with dead space between. Tighten the table so labels and values feel connected.

### Replace Godot default baby blue with Oori theme colors
Buttons and modals render with a baby-blue (`#29b6f6` / `LIGHT_SKY_BLUE` / navy stat-button styling) instead of brand colors. Replace with Oori tokens from `ui_theme.gd:15-41`. Note the brand has no blue — each use must be mapped to a token (see Sprint 3 for recommended mappings). Symptom of incomplete theme migration in `convoy_journey_menu`, `warehouse_menu`, `convoy_cargo_menu`.
