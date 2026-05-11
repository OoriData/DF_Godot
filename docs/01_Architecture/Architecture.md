# Architecture Overview

## Core Systems Overview

- **APICalls (Transport)**: Handles the low-level HTTP queue, request deduplication, and auth headers.
- **Services (Domain Logic)**: High-level singletons (e.g., `ConvoyService`, `MapService`) that use `APICalls` to fetch data.
- **GameStore (State Management)**: The local snapshot of the game world. Services update the Store, and the Store emits signals when data changes.
- **SignalHub (Event Bus)**: Decouples UI from logic. UI listens to `SignalHub` for domain events (e.g., `convoys_changed`).

---

## 2. The Bootstrap Sequence

Understanding how the application starts is critical for debugging initialization and authentication.

### Startup Flow (Mobile/Desktop)
1.  **Autoload Initialization**: Godot loads singletons in order (see [Autoload Order](../04_Technical/AutoloadOrder.md)).
2.  **`GameScreenManager` Setup**: Pauses the game tree and shows the `LoginScreen`.
3.  **Authentication**:
    - `APICalls` attempts to load a persisted session from `user://session.cfg`.
    - If valid, it triggers `/auth/me` to resolve the user identity.
    - If invalid, the user must log in via the `LoginScreen`.
4.  **The Handshake (`_on_login_successful`)**:
    - Once authenticated, `GameScreenManager` triggers the parallel bootstrap:
        - `UserService.refresh_user()` -> Fetches profile and convoy IDs.
        - `MapService.request_map()` -> Fetches binary tile data.
    - `ConvoyService` waits for the User profile to land in the `GameStore`, then triggers `refresh_all()`.
5.  **Activation**:
    - When all core data (Map, User, Convoys) has arrived, `SignalHub` emits `initial_data_ready`.
    - `GameScreenManager` frees the login UI, un-pauses the tree, and enables the `MainScreen`.

---

## 3. Data Freshness & Polling

The project uses a hybrid approach to maintain state:
- **Reactive Updates**: Any user action (e.g., "Buy Fuel") triggers a `PATCH` request. The successful response immediately updates the `GameStore`, which notifies the UI.
- **Background Polling**: The `RefreshScheduler` autoload triggers periodic updates (every ~10s) for moving convoys and map state while the game is active.
- **Transactional Consistency**: PATCH responses often return the "post-action" state of a convoy. The system "unwraps" these responses and updates the local store instantly, ensuring the UI feels responsive without waiting for the next poll cycle.

## Autoloads

The system relies on several global Autoloads for cross-cutting concerns and service management:

### Utilities & Transport
- **Tools**: `res://Scripts/System/tools.gd` - Serialization and helper functions.
- **DateTimeUtils**: `res://Scripts/System/date_time_util.gd` - Formatting and time math.
- **ErrorTranslator**: `res://Scripts/System/error_translator.gd` - Mapping backend errors to UI.
- **SettingsManager**: `res://Scripts/System/settings_manager.gd` - Persistent local settings.
- **Logger**: `res://Scripts/System/logger.gd` - Level-gated console logging.
- **APICalls**: `res://Scripts/System/api_calls.gd` - Low-level HTTP/JWT transport.

### Events & State
- **SignalHub (Hub)**: `res://Scripts/System/Services/signal_hub.gd` - Canonical domain event emitter.
- **GameStore (Store)**: `res://Scripts/System/Services/game_store.gd` - Snapshot storage and state signals.

### Domain Services
Thin, domain-focused wrappers for API calls and state management:
- **MapService**, **ConvoyService**, **UserService**, **VendorService**, **MechanicsService**, **RouteService**, **WarehouseService**, **AutoSellService**.
- **RefreshScheduler**: Orchestrates periodic polling.
- **ConvoySelectionService**: Manages selection state logic.

### Managers
- **MenuManager**: `res://Scripts/Menus/menu_manager.gd` - Navigation hub for all sub-menus.
- **ui_scale_manager**: `res://Scripts/UI/UI_scale_manager.gd` - Authority on logical resolution and scaling.
- **DeviceStateManager**: `res://Scripts/System/device_state_manager.gd` - Tracks portrait/landscape and platform.
- **TutorialManager**: `res://Scripts/UI/tutorial_manager.gd` - Controls tutorial overlays and steps.
- **SteamManager**, **GoogleAuthService**: Identity provider integration.
- **PushNotificationManager**: Handles deep-linking from notifications.

---

## Canonical Domain Events (SignalHub)

- **Map**: `map_changed(tiles, settlements)`
- **Convoys**: `convoys_changed(convoys)`, `convoy_updated(convoy)`
- **Selection**: `convoy_selection_requested(id)`, `convoy_selection_changed(data)`, `selected_convoy_ids_changed(ids)`
- **User/Auth**: `user_changed(user)`, `auth_state_changed(state)`, `user_refresh_requested`
- **Vendors**: `vendor_updated(vendor)`, `vendor_panel_ready(data)`, `vendor_preview_ready(data)`
- **Routing**: `route_choices_request_started`, `route_choices_ready`, `route_choices_error`
- **Warehouses**: `warehouse_updated(warehouse)`, `warehouse_cargo_stored(result)`, etc.
- **Errors**: `error_occurred(domain, code, message, inline)`
- **Lifecycle**: `initial_data_ready()`

---

## UI Architecture

The UI is built on a **Responsive Scaling System** and a **Centralized Navigation Hub**.

### 1. Scaling & Orientation
- **UIScaleManager** enforces a logical width (e.g., 800px for Mobile Portrait) to ensure readability without manual font overrides.
- **SafeAreaHandler** ensures UI elements don't overlap with physical screen cutouts (notches, islands).
- **DeviceStateManager** provides orientation-aware flags for layout branching.

### 2. Menu Management
- **MenuManager** handles preloading, instantiating, and animating transitions between menus.
- It maintains a **Navigation Stack** (for "back" functionality) and a **Persistent Cache** (for keeping heavy menu states alive).
- Menus extend **MenuBase**, providing a standard contract for data initialization and lifecycle hooks.

---

## Identity & Auth

The system supports multiple providers (Steam, Discord, Google) with a unified session model. Detailed documentation is in [Identity.md](../04_Technical/Identity.md).

- **Persistence**: Token stored in `user://session.cfg` for auto-login.
- **Linking**: Accounts can be linked to a single profile via respective auth services.

---

## Logging & Monitoring
- **Logger** gates debug/info/warn/error levels.
- **ErrorTranslator** ensures backend technical errors are presented as friendly messages to the user.
