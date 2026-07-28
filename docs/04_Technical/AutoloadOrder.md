---
type: technical
tags:
  - layer/autoload
  - kind/reference
  - status/current
aliases:
  - "Autoload Order"
  - "Autoload Register"
created: 2026-05-18
updated: 2026-07-28
verified_against_code: 2026-07-28
status: current
---

# Autoload Register & Init Order

**The complete list of every global singleton, what it actually owns, and which doc covers it.**
This is the "which service owns this?" lookup — start here before grepping.

> [!IMPORTANT]
> **This table must list every entry in `project.godot`'s `[autoload]` block, in the same order.**
> `tools/docs_check.py` fails the build if the two drift apart, so this page cannot silently fall behind
> the code the way a hand-maintained list does.

> [!NOTE]
> **Verified against source 2026-07-28.** Every "Owns" cell below was written from the script's actual
> public API, not from its name. Line counts are a deliberate signal: several of these are thin
> passthroughs, and prior docs described them as if they held substantial logic. See
> [DocumentationAudit § F11](../DocumentationAudit.md#f11--autoload-coverage-is-inverse-to-importance).

---

## The register

Order below **is** the load order in `project.godot`. Later entries may depend on earlier ones; the
reverse is not safe.

### 1 · Core utilities & transport

| # | Autoload | Script | Lines | Owns | Doc |
|---|---|---|---|---|---|
| 1 | `Tools` | `Scripts/System/tools.gd` | 186 | **Binary `/map` decoding.** All-static big-endian readers (`_read_u16_be`, `_read_f32_be`) plus `deserialize_cargo` / vehicle / settlement. Hand-mirrors the DF_Lib wire format byte-for-byte. | [DF_Lib](DF_Lib.md) |
| 2 | `DateTimeUtils` | `Scripts/System/date_time_util.gd` | 179 | **Static time formatting.** `format_eta_string`, `parse_iso_to_utc_dict`, `to_unix_utc`, `format_timestamp_display`. No state. | — |
| 3 | `ErrorTranslator` | `Scripts/System/error_translator.gd` | 161 | **Raw API error → player-facing text.** `translate()`, plus routing predicates `is_inline_error()` and `is_premium_required()`. | [ErrorSystem](ErrorSystem.md) |
| 4 | `SettingsManager` | `Scripts/System/settings_manager.gd` | 86 | **Config persistence.** `get_value` / `set_and_save` / `save_settings` / `load_settings`. Owns the `display.fullscreen` contract — window mode changes route through here, never `DisplayServer`. | [UserSettings](UserSettings.md) |
| 5 | `Logger` | `Scripts/System/logger.gd` | 143 | **Levelled logging + in-memory ring buffer.** `debug/info/warn/error`, and `get_recent_lines[_since]()` — the buffer the bug reporter attaches. | [Diagnostics](Diagnostics.md) · [BugReporting](BugReporting.md) |
| 6 | `APICalls` | `Scripts/System/api_calls.gd` | **3209** | **All HTTP.** Request queue + parallel GET pool, watchdogs, auth header injection, session token, per-endpoint request/response signals. The largest single file in the project. | [NetworkLayer](NetworkLayer.md) · [API_Reference](API_Reference.md) |

### 2 · Events & state

| # | Autoload | Script | Lines | Owns | Doc |
|---|---|---|---|---|---|
| 7 | `SignalHub` | `Scripts/System/Services/signal_hub.gd` | 79 | **The event bus.** ~30 domain signals and nothing else — no logic, no state. Every UI update flows through here. | [SignalHub](SignalHub.md) |
| 8 | `GameStore` | `Scripts/System/Services/game_store.gd` | 167 | **The single state snapshot.** `set_map/set_convoys/set_user/set_session_token` writers, `get_tiles/get_settlements/get_convoys/get_user` readers. Normalises `user["money"]` to `int`. | [DataFlow](../01_Architecture/DataFlow.md) |

### 3 · Domain services

> These sit between `APICalls` and `GameStore`. Several are **thin passthroughs** — they translate a UI
> intent into a request and let the response land in the store. Depth of file ≠ depth of concept.

| # | Autoload | Script | Lines | Owns | Doc |
|---|---|---|---|---|---|
| 9 | `MapService` | `…/Services/map_service.gd` | 37 | `request_map()` + tile/settlement readers. Passthrough. | [MapSystem](../03_Systems/MapSystem/MapSystemOverview.md) |
| 10 | `MapSettingsService` | `…/Services/map_settings_service.gd` | 107 | **Map overlay toggles.** `update_setting()`, `set_planning_override()`, `get_settings_dict()` — the gear-panel state. | [MapMenuSystem](../03_Systems/MapSystem/MapMenuSystem.md) |
| 11 | `ConvoyService` | `…/Services/convoy_service.gd` | 163 | `refresh_all()` / `refresh_single()` / `create_new_convoy()`, convoy model conversion, and the **per-convoy colour map** (`get_color_for`). *No rename or disband — those do not exist.* | — |
| 12 | `UserService` | `…/Services/user_service.gd` | 52 | `request_user()` / `refresh_user()` / `get_user()`. Passthrough. | [Identity](Identity.md) |
| 13 | `VendorService` | `…/Services/vendor_service.gd` | 115 | `request_vendor` / `request_vendor_panel` / `request_vendor_preview` / `request_vehicle`, plus last-vendor caching and `to_model()`. *No bulk-fuel logic.* | [VendorPanel](../02_UI_UX/VendorPanel/VendorPanelOverview.md) |
| 14 | `MechanicsService` | `…/Services/mechanics_service.gd` | 448 | **Part-compatibility prefetch.** Probe sessions (`start/end_mechanics_probe_session`), `warm_mechanics_data_for_convoy()`, vendor cache, cargo enrichment. *No durability or repair math.* | [Mechanics](../03_Systems/Mechanics.md) |
| 15 | `RouteService` | `…/Services/route_service.gd` | **59** | `request_choices()` / `start_journey()` / `cancel_journey()` / `to_models()`. **Pure passthrough** — all pathfinding, ETA, and consumption maths are **server-side**. | [JourneyMenu](../02_UI_UX/JourneyMenu.md) |
| 16 | `RefreshScheduler` | `…/Services/refresh_scheduler.gd` | 88 | **Polling heartbeat.** `enable_polling()` and the interval timer that drives periodic refreshes. | [RefreshScheduler](RefreshScheduler.md) |
| 17 | `WarehouseService` | `…/Services/warehouse_service.gd` | 112 | `request_new/get/expand`, `store_/retrieve_cargo`, `store_/retrieve_vehicle`. | [WarehouseMenu](../02_UI_UX/WarehouseMenu.md) |
| 18 | `ConvoySelectionService` | `…/Services/convoy_selection_service.gd` | 95 | **The global cursor** — which convoy the UI is currently showing. `select_convoy_by_id()`, `get_selected_convoy()`. | [StateManagement](../03_Systems/StateManagement.md) |

### 4 · UI & device

| # | Autoload | Script | Lines | Owns | Doc |
|---|---|---|---|---|---|
| 19 | `MenuManager` | `Scripts/Menus/menu_manager.gd` | **1077** | **Navigation.** `MENU_ORDER`, slide transitions, the shared bottom nav bar, menu container registration, z-index `150` when active. | [MenuManager](../02_UI_UX/MenuManager.md) |
| 20 | `ui_scale_manager` | `Scripts/UI/UI_scale_manager.gd` | 242 | **The single scaling authority.** Target widths (portrait `800`, mobile-landscape `1600`, desktop `1920`/`1200`), `MIN_LOGICAL_WIDTH 1150`, the `_MIN_SAFE_FACTOR 0.05` boot floor, and safe-area margins. | [ui_system](../02_UI_UX/ui_system.md) |
| 21 | `TutorialManager` | `Scripts/UI/tutorial_manager.gd` | **2121** | **Onboarding.** Levels 1–8 (`MAX_TUTORIAL_LEVEL`), gating modes, progress at `user://tutorial_progress.json`. **Steps are hardcoded in `_build_level_steps()` — not loaded from JSON.** | [TutorialSystem](../03_Systems/TutorialSystem/TutorialSystemOverview.md) |
| 22 | `PushNotificationManager` | `…/Services/push_notification_manager.gd` | 142 | Per-platform token setup (`_setup_ios` / `_setup_android`) and token registration on `user_changed`. | [PushNotifications](PushNotifications.md) |
| 23 | `DeviceStateManager` | `Scripts/System/device_state_manager.gd` | 60 | **Orientation/platform queries only** — `get_layout_mode()`, `get_is_portrait()`. Has **no** font-scaling role. | [DeviceState](../02_UI_UX/DeviceState.md) |
| 24 | `UITheme` | `Scripts/System/ui_theme.gd` | 126 | **The authoritative colour + spacing tokens** (`METAL_*`, `SURFACE_WARM`, `TEXT_*`, `SPACE_*`). Rationale lives in DesignSystem; the constants live here. | [DesignSystem](../02_UI_UX/DesignSystem.md) |

### 5 · Platform & identity

| # | Autoload | Script | Lines | Owns | Doc |
|---|---|---|---|---|---|
| 25 | `SteamManager` | `Scripts/System/steam_manager.gd` | 92 | `is_steam_running()`, `get_steam_id()`, `get_steam_username()`. Gates the desktop Steam login button. | [Identity](Identity.md) · [Deployment](Deployment.md) |
| 26 | `AutoSellService` | `…/Services/auto_sell_service.gd` | 362 | **Post-journey cargo diffing.** Snapshot at `user://cargo_snapshot.json`, delivery detection, receipt modal payload. `simulate_autosell()` for testing. | [AutoSellSystem](../03_Systems/AutoSellSystem.md) |
| 27 | `GoogleAuthService` | `…/Services/google_auth_service.gd` | 125 | `is_available()`, `sign_in()`, `silent_sign_in()`, `connect_account()`, `sign_out()`. | [MultiProviderAuth](MultiProviderAuth.md) |

---

## Load-order rules

1. **`Tools` → `DateTimeUtils` → `ErrorTranslator` → `SettingsManager` → `Logger` → `APICalls`.**
   Pure utilities first; `APICalls` needs `SettingsManager` (environment) and `Logger`.
2. **`SignalHub` before `GameStore`, and both before every service.** A service that emits during
   `_ready()` on a not-yet-registered hub silently drops the event.
3. **Services before UI.** `MenuManager` and `TutorialManager` resolve services at `_ready()`.
4. **`ui_scale_manager` before anything that reads safe-area margins.** Its `content_scale_factor` can
   be pinned at the `0.05` floor for a frame during boot — consumers must re-read on
   `ui_scale_changed`, not latch the boot value. This caused the blank-screen bug (S12-7).

## When you add an autoload

1. Add it to `project.godot` `[autoload]` **in the correct band** above.
2. Add a row here — script path, real line count, what it actually owns, and its doc (`—` if none yet).
3. Run `python3 tools/docs_check.py`. It will fail if the register and `project.godot` disagree.

## Related

- **Constrained by:** [Architecture](../01_Architecture/Architecture.md) — service-oriented, event-driven design
- **See also:** [Dependencies](Dependencies.md) — singleton relationship graph · [SignalHub](SignalHub.md) — the event catalogue · [DataFlow](../01_Architecture/DataFlow.md) — `API → Service → GameStore → SignalHub → UI`
- **Live status:** [TODO.md](../TODO.md)
