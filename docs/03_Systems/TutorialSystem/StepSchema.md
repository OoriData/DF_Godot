# Step Schema: The Tutorial Contract

Tutorial steps are defined in a JSON array. Each step is a dictionary that tells the Engine what to show, what to highlight, and what to wait for.

## JSON Structure

```json
{
  "id": "l1_open_dealership",
  "copy": "Go to the [b]Dealership[/b] tab.",
  "action": "await_dealership_tab",
  "lock": "soft",
  "target": { 
    "resolver": "tab_title_contains", 
    "token": "Dealership" 
  }
}
```

## Field Definitions

| Field | Type | Description |
| :--- | :--- | :--- |
| **`id`** | `string` | Unique identifier (e.g., `l1_intro`). |
| **`copy`** | `string` | The message shown to the player (supports BBCode). |
| **`action`** | `string` | The completion trigger. Handled by the `LevelController`. |
| **`lock`** | `string` | `none`, `soft`, or `hard`. Controls input gating. |
| **`target`** | `object` | Parameters for the `TargetResolver`. |

## Resolver Strategies
The `target` object can use several strategies to find UI elements:

- **`button_with_text`**: Searches for a button containing a specific `token`.
- **`tab_title_contains`**: Finds a tab in the current `TabContainer` by name.
- **`vendor_trade_panel`**: Highlights the entire active trading area.
- **`node_path`**: (Avoid if possible) Finds a node by an absolute Godot path.
- **`convoy_return_button`**: Specialized resolver for the top-bar navigation.

## Advanced Actions
Some actions require additional data in the `target` object:
- **`await_supply_purchase`**: May include a `checklist` of items the player needs to buy.
- **`set_stage_and_finish`**: Tells the backend to advance the player's account to the next global level.
