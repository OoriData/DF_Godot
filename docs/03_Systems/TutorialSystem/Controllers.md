# Level Controllers: Custom Logic

While simple steps (like "Click a Button") can be handled by the generic Engine, complex steps (like "Buy exactly 2 MREs") require a **Level Controller**.

## Responsibilities
A Level Controller is a small script responsible for a single tutorial level. It:
1.  **Registers Watchers**: Connects to `SignalHub` signals when a step starts.
2.  **Validates Progress**: Checks if the player's action matches the tutorial requirements.
3.  **Signals Completion**: Calls `manager.step_completed()` to advance the engine.

## Example: Level 2 Resource Controller

```gdscript
extends TutorialLevelController

func _on_step_started(step_id: String):
    match step_id:
        "l2_buy_supplies":
            SignalHub.vendor_transaction_completed.connect(_check_cargo)

func _check_cargo(transaction_data: Dictionary):
    if transaction_data.item_id == "mre" and transaction_data.quantity >= 2:
        advance_step()
```

## Adding a New Level
1.  **Create JSON**: Add the step definitions to `tutorial_steps.json`.
2.  **Create Controller**: Create a new script in `Scripts/UI/TutorialLevels/`.
3.  **Register**: Add the controller to the `TutorialManager` factory logic.

## Best Practices
- **Cleanup**: Always disconnect signals in `_on_step_finished` to prevent memory leaks or double-advancement.
- **Fail-Safes**: If a user is already in the correct state (e.g., they already have the item), the controller should immediately trigger `advance_step()`.
- **UI State Check**: Use `MenuManager` to verify the user is in the correct menu before showing a highlight.
