---
type: ui-ux
tags:
  - ui
  - ux
  - ui/vendor
  - codex/refactor
aliases:
  - "Vendor Menu Responsive Refactor: Audit & Requirements"
created: 2026-06-05
---

# Vendor Menu Responsive Refactor — Audit & Requirements

> Companion to [VendorPanelOverview](VendorPanelOverview.md). This doc captures the **screenshot audit**, the **locked-in requirements**, and the **chosen responsive design** for the vendor/settlement trade screen. It is the source of truth for the in-progress refactor (mirrors the Convoy menu refactor approach).
>
> Interactive mockups: [`docs/_mockups/vendor_portrait_concepts.html`](../../_mockups/vendor_portrait_concepts.html)

## 1. What this screen actually is

All audited screenshots are the **Settlement submenu** (`convoy_settlement_menu.gd` + `ConvoySettlementMenu.tscn`), which embeds the **Vendor Trade Panel** (`vendor_trade_panel.gd` + `VendorTradePanel.tscn`) once per vendor type. The runtime tree is a **nested container stack**:

```
MainVBox (VBox)
├─ TopBarHBox            ← TitleLabel + "Top Up" + "Warehouse"  (all size_flags_horizontal=EXPAND → equal width)
├─ VendorTabContainer (TabContainer, clip_tabs=false, tab_alignment=center)
│   └─ VendorTradePanel  (instanced per vendor type: Mega-Dealership | Gasoline Refinery | Depot | Water Reclamation Plant)
│       └─ HBoxContainer  (fixed desktop 3-column)
│           ├─ LeftPanel   0.30  → Sort MenuButton + Buy/Sell TabContainer + item Tree ("Vendor's Wares")
│           ├─ MiddlePanel 0.35  → ItemName + preview + Fitment/Info/Description scroll
│           └─ RightPanel  320px → Transaction / Money / qty −/+ / Max / Volume+Mass bars / Buy
└─ BackButton
```

**Two nested `TabContainer`s** (vendor-type → Buy/Sell) wrapping a **fixed 3-column `HBoxContainer`** that never reflows for orientation. That single fact drives nearly every defect.

## 2. Audit — issues by viewport

### Portrait (worst case)
| # | Issue | Root cause |
|---|---|---|
| P1 | Text clipped both edges: `dor's Wares`, `ega-Dealership`, `cles`, `M…` (Max) | 3 columns @ 0.3/0.35/320px crammed into ~800 logical px; no reflow |
| P2 | Vendor-type tab strip overflows screen width, clipped L & R | `VendorTabContainer` `clip_tabs=false` + 4 long names; TabBars don't wrap |
| P3 | Right transaction column jammed against right edge, "Max" cut to "M…" | `RightPanel` 320px min can't coexist with the other two columns |
| P4 | TopBar Title/Top Up/Warehouse render as 3 oversized equal buttons | equal `size_flags_horizontal=3` |
| P5 | Middle inspector effectively empty while map-area space is wasted | column squeeze |

### Mobile Landscape
| # | Issue | Root cause |
|---|---|---|
| L1 | **Element overlap** — Buy/Sell toggle renders on top of the vendor-type tab row | inner Buy/Sell TabBar + outer VendorTab TabBar occupy the same vertical band |
| L2 | Vendor-type tabs overflow horizontally into the transaction panel | same as P2 |
| L3 | Large wasted dead zones while controls are squeezed into a thin strip | content not using vertical space; fixed column heights |
| L4 | Top Up / Warehouse span full width, dwarfing the trade content | P4 |

### Desktop (the "works" reference)
- 3-column layout is legible only because there's horizontal room — this is the only viewport the current design was built for.
- Residual: vendor-type tabs are still a flat overflow-prone strip; Buy/Sell tabs sit cramped under the Sort row.

### Cross-cutting
1. **No responsive reflow** — one fixed desktop layout for all three viewports (same root issue the Convoy refactor addressed).
2. **Nested TabContainers** collide/overflow; `VendorTabContainer` text can never fit on mobile.
3. **TopBarHBox equal-expand** wastes mobile width on Top Up / Warehouse.
4. **No horizontal-scroll guardrail** — overflow just clips today.

## 3. Locked-in requirements

| # | Requirement | Notes |
|---|---|---|
| R1 | **No horizontal scrolling, ever** | Hard rule. Overflow must wrap, reflow, or move into a dropdown. |
| R2 | **Map stays visible** | Vendor panel lives in the **bottom region only** — never a full-screen takeover. Player keeps the route/map in view while trading. |
| R3 | **Fast item swapping** | Switching between vendor items must be ≤1 tap and keep the transaction reachable. |
| R4 | **Full responsive rebuild** | Structural reflow, **mirroring the Convoy menu refactor** patterns/components/breakpoints for consistency. |
| R5 | **Vendor-type selector = orientation-aware** | **Dropdown** (OptionButton) on mobile; keep the **tab strip** on desktop where it fits. |
| R6 | **Responsive ladder = 1 → 2 → 3 columns by width** | Portrait 1 region · Landscape 2-pane · Desktop 3-column. |

## 4. Chosen design — the responsive ladder

### Portrait — **Concept A: List + sticky transaction footer**
- Panel is a **single scrolling item list**; tapping a row expands its inspector **inline** (mirrors the Convoy Cargo inline-inspector pattern).
- A **slim transaction bar is pinned to the bottom** of the panel: selected item · qty −/+ · Max · total price · Volume/Mass thin bars · **Buy**. Always visible, always retargets to the selected item — Buy never scrolls off.
- Vendor-type **dropdown** + Buy/Sell segmented toggle in a compact header row. Top Up / Warehouse / Sort as a secondary utility row (not equal-expand).

### Mobile Landscape — **2-column hybrid**
- Left ~40%: vertical item list. Right ~60%: inspector **+** transaction merged into one pane.
- One tap swaps the right pane. Fixes the L1 overlap by removing the nested-TabBar collision (Buy/Sell becomes a segmented control, not a TabContainer).

### Desktop — **keep 3-column**
- List · inspector · transaction, as today, but with the vendor-type tab strip de-overflowed and Buy/Sell as a segmented control rather than a nested TabContainer.

> Mockup of all three portrait concepts (A chosen): [`docs/_mockups/vendor_portrait_concepts.html`](../../_mockups/vendor_portrait_concepts.html)

## 5. Structural implications for implementation
- **Replace the nested Buy/Sell `TabContainer`** with a segmented toggle (resolves L1 overlap and the cramped Sort/tab stacking).
- **Vendor-type `VendorTabContainer`** → orientation-aware: OptionButton dropdown on mobile, tab strip on desktop. Stop relying on `clip_tabs=false` overflow.
- **`TopBarHBox`** → drop equal `size_flags_horizontal=3`; Top Up / Warehouse become right-sized utility buttons.
- **The fixed 3-column `HBoxContainer`** → driven by the layout mode (`DeviceStateManager.get_layout_mode()`), reflowing 1/2/3 columns. Reuse the Convoy refactor's responsive container/breakpoint helpers rather than new ad-hoc code.
- **Transaction controls** → extracted so they can render as a pinned portrait footer, a right-pane block (landscape), or the right column (desktop) from the same builder.

## 6. Reuse inventory (what "mirror Convoy" means here)
There is **no shared responsive-column framework** — the Convoy refactor was incremental per-menu `layout_mode` branching, not a reusable system. Concrete pieces to reuse:
- `Scripts/UI/responsive_list_adapter.gd` — touch row-height adapter (already wired into `VendorTradePanel.tscn`).
- `convoy_cargo_menu.gd::_build_inline_inspect_panel()` — the model for Concept A's inline-expand inspector rows (custom VBox list, **not** a `Tree`).
- `DeviceStateManager.get_layout_mode()` branching — `0` desktop, `1` mobile landscape, `2` mobile portrait.

> ⚠️ **Cleanup obligation:** `vendor_trade_panel.gd` lines ~640–925 contain ~20 runtime font-size overrides (`38 if is_portrait else 30`). This is the deleted pre-June-2026 multiplier pattern and **violates the Law of Logical Pixels** (`AI_ONBOARDING.md`). The rebuild must flatten these to fixed logical sizes.

## 7. Phase 0 decisions (locked)
- **Sort control**: compact, right-aligned dropdown on a thin row directly above the list (capped width). Sorts the list only; kept separate from Top Up/Warehouse. Same node in every mode, reparented into the list header.
- **Parts / Install**: footer stays uniform (primary **Buy/Sell** for all vendor types). The **Install** action lives in the inline-expanded inspector's **Fitment** section, shown only when compatible — next to existing fitment info.
- **Item list widget**: replace the Godot `Tree` (`VendorItemTree` / `ConvoyItemTree`) with a **custom VBox-of-rows list** in all modes (mirrors `convoy_cargo_menu.gd`). Required because `Tree` can't host inline-expanding inspector rows. **Largest change in the refactor.**

## 8. Implementation plan

**Shared scaffolding**
- Add `_apply_layout()` driven by `get_layout_mode()`, run on `_ready` and `layout_mode_changed`. Single switch: PORTRAIT(2) / LANDSCAPE(1) / DESKTOP(0).
- Extract three builders whose outputs get **reparented** per mode (build widgets once, place them differently):
  - `_build_item_list()` — custom VBox list (replaces the Trees).
  - `_build_inspector(item)` — current MiddlePanel content.
  - `_build_transaction_block()` — current RightPanel content (qty/Max/price/Volume+Mass/Buy).

**Build order (low-risk → core):**
1. ✅ **Buy/Sell segmented toggle** *(done)* — `TradeModeTabContainer` set `tabs_visible=false`; an external `ModeToggle` (ButtonGroup) drives `current_tab` with two-way sync and a styled active state. Fixes the L1 landscape overlap.
2. ✅ **Vendor-type selector orientation-aware** *(done — `convoy_settlement_menu.gd`)* — DESKTOP keeps the `VendorTabContainer` strip; MOBILE hides the tab bar and drives the same tab content from a styled `VendorSelector` `OptionButton`, kept in two-way sync via `_sync_vendor_selector()` / `_on_vendor_tab_changed`.
3. ✅ **`TopBarHBox` right-size** *(done — `convoy_settlement_menu.gd::_apply_top_bar_sizing`)* — Title keeps `EXPAND_FILL` + `clip_text` (breadcrumb truncates gracefully); Top Up / Warehouse switched to `SHRINK_END` so they size to their own text. Fixes the "Top Up (Fu…" truncation (P4/L4) on every viewport. Re-applied on layout-mode change.
4. 🚧 **Custom list widget** *(in progress)* — new `Scripts/Menus/VendorPanel/vendor_item_list.gd` (`VendorItemList`, extends `ScrollContainer`) replaces the `Tree`: category headers + selectable Control rows, `item_selected(agg_data)` mirroring the Tree's `get_metadata(0)`, `select_key()` for selection-restore, `_build_row_body()` hook for the Step-6 inline inspector. **Built & isolation-verified** via mock-data render (headers, alpha sort, selection highlight, prices). **Not yet wired** into `vendor_trade_panel.gd` — that's the next chunk (swap `VendorItemTree`/`ConvoyItemTree`, rewire `_on_vendor_item_selected`/`_on_convoy_item_selected` + `_populate_category`, preserve `_last_selected_*` restore for both Buy & Sell). ⚠️ Note: this Godot 4.6 build errors on `get_meta(name, null)` when the key is absent — use `has_meta()` guards.
5. **Column reflow ladder** — `_apply_layout()` reparents the three builders:
   - DESKTOP: 3-col HBox (list 0.3 | inspector 0.35 | txn 320px) — as today.
   - LANDSCAPE: 2-col HBox — list (~0.4) | right VBox (inspector scroll + transaction block).
   - PORTRAIT: single VBox — header (vendor dropdown + Buy/Sell toggle) / Sort row / list with inline-expand inspector / **transaction block pinned as a non-scrolling footer**.
6. **Inline-expand inspector (portrait)** — mirror `_build_inline_inspect_panel`; tapping a row expands its inspector inline, footer retargets to the selection.
7. **Install affordance** — render the Install button inside the expanded Fitment section when compatible (per §7).
8. **Flatten font scaling** — remove the ~20 runtime font overrides; set fixed logical sizes once.

**Verify** — portrait, landscape, desktop against R1–R6 (no horizontal scroll, map visible, ≤1-tap swap, Buy always reachable).

## 9. Risks
- **Tree → custom list** touches selection restore, sort, and the Sell-mode (convoy cargo) path — regress-test selection persistence across refreshes (the debounce/baseline-guard logic in `vendor_trade_panel.gd`).
- Reparenting builders on `layout_mode_changed` mid-session must not drop in-progress transaction state (`_pending_tx`, `_committed_projection`).
