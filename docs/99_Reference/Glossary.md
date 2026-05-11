# Project Glossary

A central reference for domain-specific and technical terminology used in *Desolate Frontiers*. This document is intended for both humans and AI agents to quickly locate relevant logic.

## Domain Terms

- **Convoy**: The primary player-controlled entity. 
  - *Logic*: `Scripts/System/Services/convoy_service.gd`
  - *Data*: `convoy_id` (String UUID)
- **Settlement**: Static map locations.
  - *Logic*: `Scripts/System/Services/map_service.gd`
  - *Data*: `settlement_id`, `sett_type`
- **Journey**: traversal between settlements.
  - *Logic*: `Scripts/System/Services/route_service.gd`
  - *UI*: `Scripts/Menus/convoy_journey_menu.gd`
- **Oori**: The "Old World" corporate aesthetic.
  - *Visuals*: `Assets/Themes/Oori Backround.png`
- **Warehouse**: Persistent storage at a settlement.
  - *Logic*: `Scripts/System/Services/warehouse_service.gd`
- **CargoItem**: The unified data model for all physical goods.
  - *Data*: `Scripts/Data/Items.gd`
- **MissionItem**: A specialized `CargoItem` representing a delivery contract.
  - *Logic*: Detected via `recipient_vendor_id` or `delivery_reward`.

## Technical Infrastructure

- **SignalHub**: The global event bus.
  - *File*: `Scripts/System/Services/signal_hub.gd` (Autoload)
- **GameStore**: The local "Source of Truth".
  - *File*: `Scripts/System/Services/game_store.gd` (Autoload)
- **APICalls**: The transport layer.
  - *File*: `Scripts/System/api_calls.gd` (Autoload)
- **Logical Pixels**: Resolution-independent UI units.
  - *Logic*: `Scripts/UI/UI_scale_manager.gd`
- **Occlusion Width**: Map space covered by menus.
  - *Logic*: `Scripts/UI/main_screen.gd` (see `_current_menu_occlusion_px`)
- **Safe Area**: Screen zones safe from hardware notches/islands.
  - *Component*: `Scripts/UI/safe_area_handler.gd` (see `SafeRegionContainer`)
- **Bootstrap Handshake**: The startup sequence after successful auth.
  - *Logic*: `Scripts/UI/game_screen_manager.gd`
- **Queue Watchdog**: Self-healing for the HTTP request queue.
  - *Logic*: `Scripts/System/api_calls.gd` (see `QueueWatchdogTimer`)
- **HTTP Trace**: Debug mode for logging raw network payloads.
  - *Config*: Set `http_trace = true` in `app_config.cfg`.

## UI System Components

- **MenuManager**: Navigation and transition hub.
  - *File*: `Scripts/Menus/menu_manager.gd` (Autoload)
- **MenuBase**: The standard contract for all sub-menus.
  - *File*: `Scripts/Menus/MenuBase.gd`
- **MainScreen**: The root UI mediator.
  - *File*: `Scripts/UI/main_screen.gd`
- **Top Bar**: Global navigation banner.
  - *Scene*: Part of `MainScreen.tscn` (see `TopBar` node)
- **MSDF Fonts**: Resolution-independent font scaling.
  - *Asset*: `Assets/main_font.tres` (must have MSDF enabled)
