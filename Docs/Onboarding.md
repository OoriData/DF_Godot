# Onboarding Tutorial & Coach System

This document describes how the tutorial steps are orchestrated, how the coach UI is rendered, and how to extend the tutorial with new steps.

## Overview

- Scripts/UI/tutorial_director.gd
  - A small state machine that owns the ordered list of tutorial steps.
  - Supports next, prev, and goto(step_id) so the UI can fluidly move forward or backward.
  - Emits step_changed(step_id, index, total) whenever the current step changes.

- Scripts/UI/onboarding_coach.gd
  - A lightweight overlay UI that shows the step message in a left-side panel.
  - Provides highlight_control and highlight_global_rect to call out specific UI elements.
  - Doesn’t decide the step order; it only renders.

- Scripts/UI/main_screen.gd
  - Mediates between game UI state and the tutorial.
  - Creates the OnboardingLayer, the Coach, and the TutorialDirector.
  - Subscribes to UI/game events (menu opened, closed, tab changes, purchases) and calls the director.goto(step_id) accordingly.
  - Renders the current step by calling coach.show_step_message(...) and placing highlights.

- Scenes/OnboardingLayer.tscn and Scripts/UI/onboarding_overlay_root.gd
  - A simple overlay Control that hosts the coach and director.
  - Clipped to the map area so the side panel doesn’t cover menus.

## Flow and Backward Navigation

- The director holds an ordered list of step ids:
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

## Rendering a Step

The director emits step_changed(step_id, index, total). main_screen.gd handles this by:
- Hiding the coach’s central modal (so the compact left panel shows step text).
- Calling coach.show_step_message(index, total, message).
- Highlighting the appropriate UI element for that step via coach.highlight_control(...) or coach.highlight_global_rect(...).

The coach side panel is positioned within the map’s bounds and avoids overlapping menus/popups using set_side_panel_bounds_by_global_rect(...) and set_side_panel_avoid_rects_global(...), updated whenever layout changes.

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

## Guard Conditions and Exit

- If a vehicle gets purchased, main_screen.gd dismisses the coach and clears the walkthrough.
- When menus fully close, the tutorial resets to the first step unless the user dismissed it.

You can also listen to director.finished if you want to record completion or start a second tutorial track.

## Common Highlights

- Top bar controls (convoy button, dropdown): Use highlight_global_rect on the union of their global rects.
- Settlement submenu buttons (e.g., the Settlement button): Use highlight_control to follow the control precisely.
- Tab headers (Dealership): Prefer tutorial_build_dealership_tab_highlight_proxy() proxy control for robust highlighting; fallback to tutorial_get_dealership_tab_rect_global().
- Vendor panel buttons (Buy): Prefer tutorial_get_buy_button_control() for precise control highlighting; fallback to tutorial_get_buy_button_global_rect().

## Troubleshooting

- Blank coach window: The coach center panel is hidden during steps; the left side panel shows step text. If you see nothing, ensure that:
  - coach.show_step_message(...) is getting called (watch logs).
  - OnboardingLayer is parented under the Map view and is visible.
  - _update_coach_bounds_and_avoid() is called after layout changes so the side panel is inside the map area.
- Highlight not appearing: Ensure highlight_host is set (main_screen ensures this), and that the target Control is valid/inside_tree.

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
