# Onboarding Tutorial & Coach System

This document describes how the tutorial steps are orchestrated, how the coach UI is rendered, and how to extend the tutorial with new steps.

## Overview

- Scripts/UI/tutorial_director.gd
  - A small state machine that owns the ordered list of tutorial steps.
  - Supports next, prev, and goto(step_id) so the UI can fluidly move forward or backward.
  - Debounced emissions (to avoid flicker): step changed signals are throttled to a safe cadence.
  - Immediate jump APIs for critical transitions: force_start(step_id?) and force_goto(step_id) emit without debounce.
  - Emits step_changed(step_id, index, total) whenever the current step changes.

- Scripts/UI/onboarding_coach.gd
  - A lightweight overlay UI that shows the step message in a left-side panel.
  - Provides highlight_control and highlight_global_rect to call out specific UI elements.
  - Doesn’t decide the step order; it only renders.

- Scripts/UI/main_screen.gd
  - Mediates between game UI state and the tutorial.
  - Creates the OnboardingLayer, the Coach, and the TutorialDirector.
  - Subscribes to UI/game events (menu opened, closed, tab changes, purchases) and calls the director to advance steps.
  - Renders the current step via coach.show_step_message(...) and highlight functions.
  - Bridges Stage 1 → Stage 2 using a transition guard that prevents non-target steps from flashing during the handoff.
  - Stage 2 (Resources) flow is orchestrated here; when user.metadata.tutorial == 2 and at least one vehicle exists, it installs a Stage 2 step list and uses immediate step start to avoid cycling.

- Scenes/OnboardingLayer.tscn and Scripts/UI/onboarding_overlay_root.gd
  - A simple overlay Control that hosts the coach and director.
  - Clipped to the map area so the side panel doesn’t cover menus.

- Scripts/Menus/vendor_trade_panel.gd
  - Provides UI helpers for highlighting/selecting vendor rows and transaction controls used by the tutorial.
  - Notable helpers for Stage 2: tutorial_select_item_by_prefix(prefix), tutorial_get_item_row_rect_global(display_text), tutorial_get_quantity_spinbox_rect_global().

## Flow and Backward Navigation

- Stage 1 (Buy First Vehicle) step ids:
  1. hint_convoy_button
  2. hint_settlement_button
  3. hint_vendor_tab
  4. hint_vendor_vehicles

- main_screen.gd listens for UI transitions and invokes director.goto(...) to set the appropriate step based on where the user currently is:
  - When Convoy Overview opens → goto("hint_settlement_button").
  - When Settlement submenu opens → goto("hint_vendor_tab").
  - When user selects the dealership tab → goto("hint_vendor_vehicles").
  - When menus are closed (back to the map) → goto("hint_convoy_button").
  - When user navigates away from dealership tab → goto("hint_vendor_tab").

Because we always set the step based on actual UI context, the tutorial naturally moves forward or backward without breaking or going blank.

- Stage 2 (Buy Water and Food) step ids (activated when user.metadata.tutorial == 2 and the player has at least one vehicle):
  1. s2_hint_convoy_button
  2. s2_hint_settlement_button
  3. s2_hint_market_tab
  4. s2_hint_select_water
  5. s2_hint_buy_water
  6. s2_hint_select_food
  7. s2_hint_buy_food

- Stage 2 transitions (with a smooth bridge from Stage 1):
  - When Convoy Overview opens → goto("s2_hint_settlement_button").
  - When Settlement submenu opens → goto("s2_hint_market_tab").
  - When Stage 2 starts (after buying a vehicle), we begin at "s2_hint_market_tab" using an immediate (non-throttled) start; this avoids cycling through earlier steps.
  - When user selects the Market tab → goto("s2_hint_select_water").
  - When “Water Jerry Cans” selected → goto("s2_hint_buy_water").
  - On a successful water purchase → goto("s2_hint_select_food").
  - When “MRE Boxes” selected → goto("s2_hint_buy_food").
  - On a successful food purchase (quantity ≥ 2) → Stage 2 completes and user.metadata.tutorial is advanced to 3.

## Rendering a Step

The director emits step_changed(step_id, index, total). main_screen.gd handles this by:
- Hiding the coach’s central modal (so the compact left panel shows step text).
- Calling coach.show_step_message(index, total, message).
- Highlighting the appropriate UI element for that step via coach.highlight_control(...) or coach.highlight_global_rect(...).

The coach side panel is positioned within the map’s bounds and avoids overlapping menus/popups using set_side_panel_bounds_by_global_rect(...) and set_side_panel_avoid_rects_global(...), updated whenever layout changes.

- Stage 2 rendering uses the same pattern. Main targets:
- Top bar controls (convoy button / dropdown) for s2_hint_convoy_button.
- Convoy menu Settlement button for s2_hint_settlement_button.
- Market tab header for s2_hint_market_tab. Highlight is computed via ConvoySettlementMenu.tutorial_get_vendor_tab_headers_info() by picking the tab with category_idx == 4 (Resources). Fallbacks compute a global rect from the TabBar if needed.
- “Water Jerry Cans” and “MRE Boxes” rows highlighted via vendor_trade_panel.gd helper tutorial_get_item_row_rect_global(), optionally auto-selected via tutorial_select_item_by_prefix().
- Quantity SpinBox + Buy button highlighted together for the buy steps using the union of tutorial_get_quantity_spinbox_rect_global() and tutorial_get_buy_button_global_rect() (or the control itself via tutorial_get_buy_button_control()).

Stage 1 rendering tweak:
- In the Dealership step, we expand Vehicles and highlight the vehicles list area to make the target obvious. Implementation prefers a single union rect over the first 3 rows (or a helper union) via vendor_trade_panel.gd: tutorial_get_vehicle_row_rects_global(3) → union, fallback tutorial_get_vehicles_union_rect_global(3).

Highlight lifecycle and stability:
- Highlights are not blanket-cleared at the start of a render; we clear only immediately before applying a new highlight. This keeps persistent callouts visible between steps/ticks.
- The highlight overlay is hosted on a top-level global layer so it can sit above menus and remains attached to controls across layout changes.

## Adding or Reordering Steps

1) Define the step ids and their order in _ensure_tutorial_director() in main_screen.gd:

```
var steps := [
  {"id": "hint_convoy_button"},
  {"id": "hint_settlement_button"},
  {"id": "hint_vendor_tab"},
  {"id": "hint_vendor_vehicles"},
  # Add more steps here, e.g. {"id": "hint_mechanics_vendor"}
]
_tutorial_director.set_steps(steps)
```

2) Provide a message for the new step id in _walkthrough_messages.

3) Update _maybe_run_vendor_walkthrough() to handle the new step. Typically:
- show the step text: coach.show_step_message(step_index, total_steps, message)
- compute and place a highlight for the UI element relevant to this step
- connect to any needed signals (e.g., a button or tab change) and call director.goto("next_step_id") as appropriate

4) Hook the step into UI transitions via _on_menu_opened_for_walkthrough, _on_vendor_tab_changed_for_walkthrough, or other relevant handlers by calling director.goto("step_id") when those transitions happen.

Tip: Prefer using director.goto(...) over manual state variables; it ensures the director re-emits step_changed so the coach refreshes reliably.

Instant transitions:
- For critical UX jumps (like Stage 1 → Stage 2), use director.force_start(step_id?) or director.force_goto(step_id) to bypass debounce and render the intended step immediately without cycling.

Stage 2 (Resources) specifics:
- Steps are set on the director when entering Stage 2 (user.metadata.tutorial == 2 and at least one vehicle), e.g., in main_screen.gd via a helper like _maybe_start_stage2_walkthrough().
- Messages for s2_* step ids must exist in _walkthrough_messages.
- Highlights are placed using:
  - ConvoySettlementMenu.tutorial_get_vendor_tab_headers_info() (pick category_idx == 4 for Market/Resources tab)
  - vendor_trade_panel.gd helpers: tutorial_select_item_by_prefix(), tutorial_get_item_row_rect_global(), tutorial_get_quantity_spinbox_rect_global(), tutorial_get_buy_button_global_rect()/tutorial_get_buy_button_control().
- For purchase-driven advancement, connect the vendor panel’s item_purchased and/or listen for global APICalls signals (resource_bought, cargo_bought) to move forward or complete the stage.

## Guard Conditions and Exit

- When a vehicle is purchased, we transition directly into Stage 2. The coach stays visible, Stage 1 listeners are cleaned up, and a transition guard prevents non-target steps from flashing.
- When menus fully close, the tutorial resets to the first step unless the user dismissed it (outside transitions).

You can also listen to director.finished if you want to record completion or start a second tutorial track.

Stage 2 completion and guards:
- After buying water (any positive quantity), advance to s2_hint_select_food.
- After buying food (any positive quantity), dismiss the coach and update user.metadata.tutorial to 3 via APICalls.update_user_metadata.
- If the user uses “Top Up” or alternate flows, global signals (resource_bought/cargo_bought) are used to coarsely advance the stage so the tutorial doesn’t stall.

## Common Highlights

- Top bar controls (convoy button, dropdown): Use highlight_global_rect on the union of their global rects.
- Settlement submenu buttons (e.g., the Settlement button): Use highlight_control to follow the control precisely.
- Tab headers (Dealership): Prefer tutorial_build_dealership_tab_highlight_proxy() proxy control for robust highlighting; fallback to tutorial_get_dealership_tab_rect_global().
- Vendor panel buttons (Buy): Prefer tutorial_get_buy_button_control() for precise control highlighting; fallback to tutorial_get_buy_button_global_rect().

Stage 2 additions:
- Market/Resources tab header: Use ConvoySettlementMenu.tutorial_get_vendor_tab_headers_info() to find the tab whose category_idx == 4, then highlight its rect.
- Resources category header: Use vendor panel tutorial_get_category_header_rect_global("Resources").
- Row highlights: Use vendor panel tutorial_get_item_row_rect_global("Water Jerry Cans") or ("MRE Boxes") to highlight and/or tutorial_select_item_by_prefix to auto-select the row.
- Quantity + Buy controls: Union of tutorial_get_quantity_spinbox_rect_global() and tutorial_get_buy_button_global_rect() (or highlight the Buy control directly via tutorial_get_buy_button_control()).

## Troubleshooting

- Blank coach window: The coach center panel is hidden during steps; the left side panel shows step text. If you see nothing, ensure that:
  - coach.show_step_message(...) is getting called (watch logs).
  - OnboardingLayer is parented under the Map view and is visible.
  - _update_coach_bounds_and_avoid() is called after layout changes so the side panel is inside the map area.
- Highlight not appearing: Ensure highlight_host is set (main_screen ensures this), and that the target Control is valid/inside_tree.

Stage 1 → Stage 2 transition polish:
- If you observe a rare highlight “pop” due to late layout reflows, add a one-frame keep-alive to re-apply the final highlight after the UI settles.
- Menu/tab handlers are temporarily gated during the handoff to avoid step churn; ensure your custom code paths respect the _transitioning_to_stage2 guard.

Stage 2 tips:
- If the Market/Resources tab rect is not available on first frame, wait for ConvoySettlementMenu.tabs_ready and re-query tutorial_get_vendor_tab_headers_info().
- If rows include quantities in display names, prefer starts-with matching when selecting (tutorial_select_item_by_prefix("Water (Bulk)")).
- When relying on global APICalls signals for coarse advancement, note that you won’t know which resource was bought—advance sequentially (water → food → done).

## Extending Beyond Buying a Vehicle

To add advanced tutorials (e.g., Mechanics, Warehouse):
- Add new step ids to the director’s order.
- Bind to GameDataManager signals (e.g., mechanic_vendor_slot_availability, vendor_panel_data_ready) and call director.goto(...) when conditions change.
- Render each new step in _maybe_run_vendor_walkthrough() or split into a new renderer function to keep things tidy.

```gdscript
# Example: advance to mechanics step when the Mechanics tab is available
if menu.has_method("tutorial_get_mechanics_tab_index") and int(tabs.current_tab) == int(menu.call("tutorial_get_mechanics_tab_index")):
    _tutorial_director.goto("hint_mechanics_vendor")
```

That’s it—steps remain data-driven, and the UI stays fluid both forward and backward based on where the user goes.
