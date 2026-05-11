# Autoload Order

Recommended order in [project.godot](../project.godot) under `[autoload]` to ensure proper dependency resolution:

### 1) Core Utilities & Transport
- **Tools**: `res://Scripts/System/tools.gd`
- **DateTimeUtils**: `res://Scripts/System/date_time_util.gd`
- **ErrorTranslator**: `res://Scripts/System/error_translator.gd`
- **SettingsManager**: `res://Scripts/System/settings_manager.gd`
- **Logger**: `res://Scripts/System/logger.gd`
- **APICalls**: `res://Scripts/System/api_calls.gd`

### 2) Events & State (The "Hub")
- **SignalHub**: `res://Scripts/System/Services/signal_hub.gd`
- **GameStore**: `res://Scripts/System/Services/game_store.gd`

### 3) Domain Services (Data Fetching)
- **MapService**, **ConvoyService**, **UserService**, **VendorService**, **MechanicsService**, **RouteService**, **WarehouseService**, **AutoSellService**.
- **RefreshScheduler**: Orchestrates service refreshes.

### 4) UI & Device Managers
- **MenuManager**: Central navigation hub.
- **ui_scale_manager**: Global viewport scaling.
- **DeviceStateManager**: Orientation and platform tracking.
- **TutorialManager**: Overlay management.
- **PushNotificationManager**: Deep-linking.

### 5) Identity Providers
- **SteamManager**, **GoogleAuthService**.
