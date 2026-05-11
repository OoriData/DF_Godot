# Game Lifecycle & State Machines

This document visualizes the high-level logic flows for the most critical systems in *Desolate Frontiers*.

## 1. Authentication & Session Lifecycle

The authentication system handles silent login, multi-provider linking, and account merging.

```mermaid
graph TD
    A[App Start] --> B{Stored Token?}
    B -- Yes --> C[Validate JWT]
    B -- No --> D[Show Login Screen]
    
    C -- Valid --> E[Enter Game]
    C -- Invalid/Expired --> D
    
    D -- Steam/Discord --> F[Auth Callback]
    F -- New User --> G[Create Account]
    F -- Existing User --> E
    
    G --> E
    
    E -- Link Account --> H{Conflict?}
    H -- No --> I[Link Success]
    H -- Yes (409) --> J[Show Merge Preview]
    J -- User Confirms --> K[Commit Merge]
    K -- Resync Session --> E
```

---

## 2. Convoy Journey Lifecycle

Convoys transition through several states during a journey. Because this is an idle game, transitions often occur on the backend while the client is offline.

```mermaid
graph TD
    Idle[Settlement: Idle] --> Selection[Journey Menu: Route Selection]
    Selection -- Confirm --> Embarked[Embarked: Moving on Map]
    
    Embarked -- Background Polling --> Progress[Update % Progress]
    Progress -- Check for Completion --> Arrived{Arrived?}
    
    Arrived -- No --> Progress
    Arrived -- Yes --> Process[Auto-Sell Logic]
    
    Process --> Notification[Show Arrival Receipt]
    Notification --> Idle
```

---

## 3. Part Installation Flow (Mechanics)

The mechanics system uses a request-response pattern to ensure part compatibility.

```mermaid
sequenceDiagram
    participant UI as Mechanics Menu
    participant MS as MechanicsService
    participant API as Backend API
    participant Store as GameStore

    UI->>MS: Select Slot + Part
    MS->>API: check_compatibility(part_id, vehicle_id)
    API-->>MS: can_install (bool) + reason (string)
    MS-->>UI: Update Install Button State
    
    UI->>MS: Click Install
    MS->>API: attach_part(...)
    API-->>Store: Updated Convoy JSON
    Store-->>UI: Redraw (SignalHub: convoys_changed)
```

---

## 4. Onboarding & Tutorial Lifecycle

The tutorial is gated by the `metadata.tutorial` field on the user object.

1. **Bootstrap**: `TutorialManager` waits for `initial_data_ready`.
2. **Evaluation**: Checks `user.metadata.tutorial`. If level is < `MAX_TUTORIAL_LEVEL`, it builds the step list.
3. **Execution**: Runs steps sequentially. If a step requires a UI action (e.g., `await_menu_open`), it blocks progress until the signal is received.
4. **Completion**: After the final step of a level, it calls `APICalls.update_user_metadata` to persist the next level to the server.
