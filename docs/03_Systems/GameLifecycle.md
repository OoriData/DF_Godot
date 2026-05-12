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
graph TD
    Select[User Selects Slot + Part] --> CompReq[MechanicsService: check_compatibility]
    CompReq --> API[Backend: Validate]
    API --> Result{Compatible?}
    
    Result -->|No| Block[UI: Disable Button + Show Reason]
    Result -->|Yes| Enable[UI: Enable Install Button]
    
    Enable --> Click[User Clicks Install]
    Click --> Attach[MechanicsService: attach_part]
    Attach --> Store[Update GameStore & SignalHub]
    Store --> Redraw[UI Redraw]
```

---

## 4. Onboarding & Tutorial Lifecycle

The tutorial is gated by the `metadata.tutorial` field on the user object.

```mermaid
graph TD
    Boot[Wait for initial_data_ready] --> Eval[Check user.metadata.tutorial]
    Eval --> NeedTut{Level < MAX?}
    
    NeedTut -->|No| Done[Exit Tutorial System]
    NeedTut -->|Yes| Build[Build Step List]
    
    Build --> Step[Run Next Step]
    Step --> Action{Requires UI Action?}
    
    Action -->|Yes| Block[Wait for UI Signal]
    Action -->|No| Exec[Apply Highlight/Pointer]
    
    Block --> Exec
    Exec --> Last{Last Step?}
    
    Last -->|No| Step
    Last -->|Yes| Persist[APICalls: Update level on Server]
    Persist --> Eval
```

