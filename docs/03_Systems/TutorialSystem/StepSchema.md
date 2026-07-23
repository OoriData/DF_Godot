---
type: system
tags:
  - system
  - system/tutorial
  - codex/stepschema
aliases:
  - "Step Schema: The Tutorial Contract"
created: 2026-05-18
---

# Step Schema: The Tutorial Contract

> [!IMPORTANT]
> **Steps are hardcoded GDScript dictionaries, not a JSON file.** They live in
> `tutorial_manager.gd::_build_level_steps()`. The old `res://Data/tutorial_steps.json` loader is disabled and
> `tutorial_steps.json` does not exist. The JSON-style listing below only documents the **shape** of each step
> dictionary — edit the function, not a data file. (Post–Sprint 8 hub rework: the `await_dealership_tab` /
> `await_market_tab` tab actions and the `tab_title_contains` resolver are **retired** — the hub flow resolves
> vendors by content identity, not tab index.)

## Step Dictionary Shape

Each step is a `Dictionary` returned in a level's step array. Shape (shown as JSON for readability):

```json
{
  "id": "l1_open_vendor",
  "copy": "Open the [b]Tutorial City Dealership[/b].",
  "action": "await_vendor_open",
  "lock": "soft",
  "target": {
    "resolver": "settlement_hub_vendor_card",
    "token": "Dealership"
  }
}
```

## Field Definitions

| Field | Type | Description |
| :--- | :--- | :--- |
| **`id`** | `string` | Unique identifier (e.g., `l1_intro`). |
| **`copy`** | `string` | The message shown to the player (supports BBCode). |
| **`action`** | `string` | The completion trigger. Dispatched by the `match action:` block in `tutorial_manager.gd`, which wires the matching `_watch_for_*` watcher. |
| **`lock`** | `string` | `none`, `soft`, or `hard`. Controls input gating. |
| **`target`** | `object` | Parameters for the `TargetResolver`. |

## Resolver Strategies
The `target` object can use several strategies to find UI elements:

- **`button_with_text`**: Searches for a button containing a specific `token`.
- **`settlement_hub_vendor_card`**: Finds a settlement-hub vendor card by its `vendor_name` meta (matches the `token` as a substring, e.g. `Dealership`, `Market`, `Gas Station`). Replaces the retired tab resolver for the hub flow.
- **`vendor_trade_panel`**: Highlights the entire active trading area.
- **`node_path`**: (Avoid if possible) Finds a node by an absolute Godot path.
- **`convoy_return_button`**: Specialized resolver for the top-bar / vendor back navigation (adaptive: falls back to the Settlement nav button when no vendor back button exists).
- **`tab_title_contains`** *(retired)*: Found a tab in a `TabContainer` by name. Unused since the Sprint 8 hub rework — the settlement hub has vendor cards, not vendor tabs.

## Advanced Actions
Some actions require additional data in the `target` object:
- **`await_supply_purchase`**: May include a `checklist` of items the player needs to buy.
- **`set_stage_and_finish`**: Tells the backend to advance the player's account to the next global level.
