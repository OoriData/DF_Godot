# Tutorial System

The tutorial system in *Desolate Frontiers* is designed to be event-driven and responsive, guiding the user through core gameplay loops using dynamic UI highlights and instructional overlays.

## Core Components

### 1. `TutorialManager`
The central coordinator (Autoload) that manages the tutorial lifecycle. It listens to domain events from `SignalHub` and `MenuManager` to advance steps.

### 2. `TutorialTargetResolver`
A specialized helper that finds UI nodes at runtime using various strategies (e.g., searching for buttons by text or finding specific tabs). This allows the tutorial to work even as the UI layout changes.

### 3. `TutorialOverlay`
A full-screen layer that dims the screen and creates "holes" (highlights) around target UI elements, allowing the user to interact only with the relevant parts of the interface.

---

## Tutorial Step Schema

Each tutorial level is an `Array` of step `Dictionaries`. A typical step looks like this:

```gdscript
{
    "id": "l1_open_settlement",
    "copy": "Click the Settlement button to view available vendors.",
    "action": "await_settlement_menu",
    "target": { 
        "resolver": "button_with_text", 
        "text_contains": "Settlement" 
    },
    "lock": "soft"
}
```

### Fields:
- **`id`**: Unique identifier for the step.
- **`copy`**: The instructional text shown to the user.
- **`action`**: The logic that determines when the step is complete (e.g., `message`, `await_menu_open`, `await_vehicle_purchase`).
- **`target`**: A dictionary passed to the `TutorialTargetResolver` to find the UI element to highlight.
- **`lock`**: Gating mode:
  - `none`: No restriction.
  - `soft`: Blocks input outside the highlight but allows interaction within it.
  - `hard`: Blocks all input except for a "Continue" button (used for pure messages).

---

## Adding a New Tutorial Level

To add a new tutorial level, follow these steps:

1. **Define Steps**: Add a new branch to the `match level:` statement in `TutorialManager._build_level_steps(level)`.
2. **Implement Actions**: If your step requires a new completion trigger, add a corresponding `match action:` case in `_run_current_step()` and implement a "watcher" function (e.g., `_watch_for_my_event()`).
3. **Connect Signals**: Ensure the `TutorialManager` is listening to the necessary signals (from `SignalHub`, `MenuManager`, etc.) to detect user actions.
4. **Update Max Level**: Update the `MAX_TUTORIAL_LEVEL` constant in `TutorialManager.gd`.

---

## Persistence & Syncing

- **Local Persistence**: Progress is saved to `user://tutorial_progress.json`.
- **Server Sync**: The current tutorial level is synced to the backend via the `user_metadata.tutorial` field.
- **Warp Trigger**: The backend may use specific tutorial levels (e.g., Level 6) to trigger events like warping the player's convoy to a new location.

---

## Debugging Tips

- Set `profiling_enabled = true` in `TutorialManager.gd` to see detailed logs of step transitions and target resolution.
- Use `TutorialManager.fast_mode = true` to speed up transitions during testing.
- The `_diag_overlay_state()` function can be called to log the current visibility and parentage of the tutorial overlay.
