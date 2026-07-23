---
type: system
tags:
  - system
  - system/tutorial
  - codex/controllers
aliases:
  - "Level Controllers: Custom Logic"
created: 2026-05-18
---

# Level Logic: Actions & Watchers

> [!IMPORTANT]
> **There is no separate `LevelController` class or `Scripts/UI/TutorialLevels/` directory** — this doc previously
> described an architecture that was never built. All tutorial logic lives in **`tutorial_manager.gd`**: steps are
> built in `_build_level_steps()`, dispatched by a `match action:` block, and each action registers a
> `_watch_for_*` / `_on_*_check` method that listens on `SignalHub` and calls the manager's advance path. The
> pattern below is the **real** one.

While simple steps (like "open this menu") complete when a `menu_opened` signal fires, complex steps (like "buy
exactly 2 MREs and 2 Water Jerry Cans") need a **watcher** — a method that validates the player's action against
the step's requirements before advancing.

## Responsibilities
For each `action`, the manager:
1.  **Registers a Watcher**: Connects to the relevant `SignalHub` signal (`convoys_changed`, `menu_opened`,
    `route_preview_started`, …) when the step starts, inside the `match action:` dispatch.
2.  **Validates Progress**: The `_on_*_check` / `_watch_for_*` callback checks whether the player's state now
    satisfies the step (e.g. cargo counts for a supply purchase).
3.  **Signals Completion**: Advances the engine and disconnects its own signal so it fires once.

## Example: the Level 2 supply-purchase watcher (real pattern)

```gdscript
# In _build_level_steps(): the step just names the action + target.
{ "id": "l2_buy_supplies", "action": "await_supply_purchase", "lock": "soft",
  "target": { "resolver": "vendor_trade_panel" },
  "checklist": ["2 MRE Boxes", "2 Water Jerry Cans"] }

# In the `match action:` dispatch, the action wires its watcher:
"await_supply_purchase":
    if not SignalHub.convoys_changed.is_connected(_on_supply_check):
        SignalHub.convoys_changed.connect(_on_supply_check)

# The watcher validates and advances. Note the strict water match:
func _on_supply_check(_all_convoys: Array) -> void:
    # count "water" only when the name has BOTH "water" AND "jerry" — never bare "jerry"
    # (plain fuel Jerry Cans must not satisfy the water requirement). See the Content gotcha.
    ...
```

## Adding a New Level / Step
1.  **Define the step**: Add the step dictionary to the level's array in `_build_level_steps()`.
2.  **Add the action**: If the `action` is new, add a `match action:` arm that registers its watcher.
3.  **Write the watcher**: Add a `_watch_for_*` / `_on_*_check` method that validates and advances, and add a
    `settlement_hub_vendor_card` / `button_with_text` target so the highlight resolves by content identity.

## Best Practices
- **Cleanup**: Disconnect the watcher's signal once it advances, to prevent double-advancement.
- **Fail-Safes**: If the player is already in the correct state (already owns the item, menu already open), advance
    immediately — restart always resumes at `_step = 0`, so a level's first step must be reachable from the map root.
- **Content identity, not indices**: Resolve highlights by vendor name / button text, never a fixed rect or tab
    index — the hub reflows hard between portrait, landscape, and desktop and rebuilds on `layout_mode_changed`.
