---
type: reference
tags:
  - reference
  - codex/glossary
aliases:
  - "Project Glossary"
created: 2026-05-18
---

# Project Glossary

A central reference for domain-specific and technical terminology used in *Desolate Frontiers*. This document is intended for both humans and AI agents to quickly locate relevant logic.

- [**AI Agent Guidelines**](../04_Technical/AI_Guidelines.md): Essential standards for AI-assisted coding.

## Domain Terms

- **Convoy**: The primary player-controlled entity — a named group of vehicles with shared resources and cargo.
  - *Schema*: [Schema.md §1](../01_Architecture/Schema.md)
  - *Service*: `Scripts/System/Services/convoy_service.gd`
  - *Key*: `convoy_id` (String UUID)
- **Settlement**: A static named location on the map where the player can trade, refuel, and store goods.
  - *Schema*: [Schema.md §6](../01_Architecture/Schema.md)
  - *Service*: `Scripts/System/Services/map_service.gd`
  - *Key*: `sett_id` (not `settlement_id` — common mistake)
  - *Types*: `village` → `town` → `city` → `city-state` → `dome` / `military_base`
- **Vendor**: A merchant embedded inside a Settlement. Has its own `cargo_inventory` and `vehicle_inventory`.
  - *Schema*: [Schema.md §7](../01_Architecture/Schema.md)
  - *Key*: `vendor_id`
- **Journey**: An active route traversal from one settlement to another.
  - *Schema*: [Schema.md §8](../01_Architecture/Schema.md)
  - *Service*: `Scripts/System/Services/route_service.gd`
  - *UI*: `Scripts/Menus/convoy_journey_menu.gd`
- **Vehicle**: A unit within a Convoy. Carries cargo and has part slots.
  - *Schema*: [Schema.md §2](../01_Architecture/Schema.md)
  - *Service*: `Scripts/System/Services/mechanics_service.gd`
  - *Doc*: [Mechanics](../03_Systems/Mechanics.md)
- **Warehouse**: Persistent storage at a specific settlement. Requires purchase and can be upgraded.
  - *Service*: `Scripts/System/Services/warehouse_service.gd`
  - *UI*: [WarehouseMenu](../02_UI_UX/WarehouseMenu.md)
- **Oori**: The post-apocalyptic corporate aesthetic of the game world. Affects theming decisions.
  - *Visuals*: `Assets/Themes/`

---

## Items & Cargo

- **Unified Item Model**: All cargo in the game (convoy, vendor, warehouse) is parsed into typed `CargoItem` objects for consistent unit handling.
  - *Logic*: `Scripts/Data/Items.gd`
  - *Doc*: [Items & Missions](../03_Systems/ItemsAndMissions.md)
- **CargoItem**: Base class for all items. Has `cargo_id`, `quantity`, `unit_volume`, `unit_weight`.
- **DeliveryCargoItem**: A `CargoItem` representing a delivery obligation. Primary detection field is `recipient` (UUID). `MissionItem` is a deprecated alias.
  - *Doc*: [Items & Missions §2](../03_Systems/ItemsAndMissions.md)
- **PartItem**: A `CargoItem` with a `slot` field (e.g., `"engine"`, `"tires"`). Installed into vehicle slots via MechanicsService.
- **ResourceItem**: Consumable `CargoItem` (fuel, water, food).
- **Jerry Cans** vs **Water Jerry Cans** — ⚠️ **two distinct cargo types, not the same item.** *Jerry Cans* are a **fuel** container (carry a `fuel` field); *Water Jerry Cans* are a **water** container (carry a `water` field). They read almost identically in the vendor list, so any step/logic that means one must never match the other. The Level 2 tutorial supply step asks for **Water Jerry Cans** specifically — see [Tutorial System](../03_Systems/TutorialSystem/TutorialSystemOverview.md#content-gotcha-jerry-cans--water-jerry-cans). Match on names containing **both** `water` and `jerry`; never loosen to bare `jerry`.
- **VehicleItem**: A complete vehicle record found in vendor inventories.
- **delivery_reward**: Credits awarded when a `DeliveryCargoItem` is delivered. On the cargo dict. Can be `null` — always guard before summing. `unit_delivery_reward` is also checked as a detection signal.
- **Auto-Sell**: The client-side process that detects cargo items that disappeared between sessions (delivered by the backend) and shows the player a receipt.
  - *Doc*: [AutoSellSystem](../03_Systems/AutoSellSystem.md)
- **cargo snapshot**: The local file (`user://cargo_snapshot.json`) containing the last-known cargo state. Used by `AutoSellService` to diff against current state.

---

## Data & API Patterns

- **Shallow Payload**: A convoy or vendor dictionary that omits computed or secondary fields. Common in map snapshot data. Identified by the absence of keys like `max_fuel`, `total_cargo_capacity`, or `cargo_inventory` items.
- **Full Payload / Full Snapshot**: A complete dictionary including all computed fields. Obtained via a dedicated API call (e.g., `ConvoyService.refresh_single()` or `VendorService.request_vendor()`).
- **Completeness Heuristic**: Code that checks whether a payload is shallow or full before rendering. Pattern: `if not c.has("max_fuel"): request_full_snapshot()`.
- **stable_key**: A client-side derived identifier for a cargo stack: `class_id + metadata`. Used to preserve UI selection state across refreshes when `cargo_id` changes.
- **`cargo_id`**: Ephemeral UUID for a cargo stack. **Can change** when the backend splits or merges stacks. Never use as a permanent reference.
- **`sett_id`**: The canonical settlement identifier. Note: raw API payloads sometimes use `"id"` as a fallback — always read via `Settlement.sett_id` which handles both.

---

## Technical Infrastructure

- **SignalHub**: The global event bus. All cross-system communication goes through here. Never connect UI directly to Services — always via SignalHub.
  - *File*: `Scripts/System/Services/signal_hub.gd` (Autoload)
- **GameStore**: The canonical in-memory state. Holds the latest snapshots of user, convoys, map, and settlements. Emits `*_changed` signals on update.
  - *File*: `Scripts/System/Services/game_store.gd` (Autoload)
- **APICalls**: The transport layer. Makes HTTP requests and emits result signals. **UI never calls this directly.**
  - *File*: `Scripts/System/api_calls.gd` (Autoload)
- **RefreshScheduler**: Periodic polling heartbeat. Calls `ConvoyService.refresh_all()` every N seconds (default: 10s). Starts after `initial_data_ready`, stops on `logged_out`.
  - *Doc*: [RefreshScheduler](../04_Technical/RefreshScheduler.md)
- **initial_data_ready**: A `SignalHub` signal emitted once per session, after both map data and convoy data have loaded into `GameStore`. The canonical "game is ready" event.
- **ErrorTranslator**: Autoload that maps raw API error strings to user-friendly messages. Three modes: ignore, inline (toast), or modal dialog.
  - *Doc*: [ErrorSystem](../04_Technical/ErrorSystem.md)
- **Logger**: Centralised logging with ring-buffer support.
  - *File*: `Scripts/System/Logger.gd` (Autoload)
  - *Doc*: [Diagnostics](../04_Technical/Diagnostics.md)
- **Queue Watchdog**: A self-healing timer inside `APICalls` that unsticks the HTTP request queue if it freezes.
  - *Logic*: `Scripts/System/api_calls.gd` → `QueueWatchdogTimer`

---

## UI System

- **MenuManager**: Navigation and transition hub. Manages menu stack, open/close animations, and passes convoy data to menus.
  - *File*: `Scripts/Menus/menu_manager.gd` (Autoload)
  - *Doc*: [MenuManager](../02_UI_UX/MenuManager.md)
- **MenuBase**: The contract all sub-menus inherit from. Provides `initialize_with_data()`, convoy banner setup, and navigation bar wiring.
  - *File*: `Scripts/Menus/MenuBase.gd`
  - *Doc*: [MenuBase Contract](../02_UI_UX/MenuBase.md)
- **MainScreen**: The root UI mediator. Hosts the map, menu container, modal layer, and the tutorial overlay.
  - *File*: `Scripts/UI/main_screen.gd`
- **Logical Pixels**: Resolution-independent UI units. Target 800px portrait width, 1600px landscape. `UIScaleManager` converts these to physical pixels at runtime.
  - *Logic*: `Scripts/UI/UI_scale_manager.gd`
- **DeviceStateManager**: Detects hardware orientation and emits `layout_mode_changed`. Query `get_is_portrait()` and `get_layout_mode()` — never use raw viewport size comparisons.
  - *Logic*: `Scripts/System/device_state_manager.gd`
  - *Doc*: [Device State](../02_UI_UX/DeviceState.md)
- **Occlusion Width**: The pixel width of map space covered by an open menu. Passed to `MapCameraController` so the camera centres the convoy in the *visible* portion of the map.
  - *Logic*: `MainScreen._current_menu_occlusion_px`
- **Safe Area / SafeRegionContainer**: Screen zones that avoid hardware notches and rounded corners. All top-level UI elements must be descendants of `SafeRegionContainer`.
  - *Component*: `Scripts/UI/safe_area_handler.gd`
- **MSDF Fonts**: Multi-channel Signed Distance Field font rendering. Stays sharp at any zoom. Required for all map labels and scaling UI.
  - *Asset*: `Assets/main_font.tres` (MSDF must be enabled in import settings)
- **Debounce Timer**: A short `Timer` (typically 100ms) used to collapse multiple simultaneous signal firings into a single redraw. Pattern: `if not _timer.is_stopped(): return`.
- **`_debug_*` Flag**: A per-menu boolean (`var _debug_convoy_menu: bool = true`) that gates all verbose `print()` calls. Flip to `false` to silence. See [Cookbook](../01_Architecture/Cookbook.md) for full pattern.
- **`_diag_*` Method**: A secondary diagnostic signal handler connected alongside the real one. Used for heavy wiring verification. Example: `WarehouseMenu._diag_expand_cargo_pressed()`.
- **`process_mode = PROCESS_MODE_ALWAYS`**: Node flag required for signals and timers that must fire even when the scene tree is paused (e.g. during modals). Missing this is the #1 cause of "silent signal" bugs.

---

## Identity & Authentication

- **Identity System**: Manages user authentication and session persistence.
  - *Doc*: [Identity](../04_Technical/Identity.md)
- **JWT (JSON Web Token)**: The security token for server communication.
  - *Logic*: `Scripts/System/api_calls.gd` → `_auth_bearer_token`
- **Account Merging**: Consolidating multiple social identities (Google, Apple, etc.) into one account.
  - *Logic*: `Scripts/System/api_calls.gd` → `commit_merge`
- **`metadata.tutorial`**: A field on the User object (`user.metadata.tutorial`) indicating tutorial progress. `1`–`7` = active. `8` = complete. Absent = complete (for users who pre-date the tutorial system).

---

## Tutorial System

- **TutorialManager**: The central engine managing the sequential step loop.
  - *Logic*: `Scripts/UI/tutorial_manager.gd`
  - *Doc*: [Tutorial System](../03_Systems/TutorialSystem/TutorialSystemOverview.md)
- **TargetResolver**: Finds specific UI nodes by text, name, or specialized logic for tutorial highlighting.
  - *Logic*: `Scripts/UI/target_resolver.gd`
- **TutorialOverlay**: The "hole-punch" mask providing visual highlights and input gating.
  - *Logic*: `Scripts/UI/tutorial_overlay.gd`
- **GatingMode**: Dictates overlay input handling.
  - `NONE`: Visual only — no input blocking.
  - `SOFT`: Blocks all input except through the highlighted "hole".
  - `HARD`: Blocks all input (fully modal).
