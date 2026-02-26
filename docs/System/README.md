# System Modules

Transport & Utilities underpinning services and UI.

- APICalls: [Scripts/System/api_calls.gd](../../Scripts/System/api_calls.gd)
  - Role: HTTP transport + request queue; emits data/auth/errors.
  - Public API: auth, user/convoys, map, vendors, mechanics, routing, warehouse.
  - Testing: queue ordering, timeouts, auth using stubbed HTTPRequest.
  - Identity: See [Identity.md](Identity.md) for auth/linking/merging deep-dive.

- SettingsManager: [Scripts/System/settings_manager.gd](../../Scripts/System/settings_manager.gd)
  - Role: persistent settings; emits `setting_changed(key, value)`; applies display/UI side effects.
  - Headless guards for DisplayServer in tests.

- ErrorTranslator: [Scripts/System/error_translator.gd](../../Scripts/System/error_translator.gd)
  - Role: map raw errors to friendly messages and inline vs blocking.

- Tools (binary): [Scripts/System/tools.gd](../../Scripts/System/tools.gd)
  - Role: big-endian deserialization for cargo, vehicles, vendors, settlements, map.

- DateTimeUtils: [Scripts/System/date_time_util.gd](../../Scripts/System/date_time_util.gd)
  - Role: ETA/timestamp formatting and ISO parsing.

- Main (MapView bootstrap): [Scripts/System/main.gd](../../Scripts/System/main.gd)
  - Target wiring: subscribe to `GameStore`; remove `GameDataManager` dependencies.

- GameDataManager (legacy adapter): [Scripts/System/game_data_manager.gd](../../Scripts/System/game_data_manager.gd)
  - Deprecated; services + store replace this.
