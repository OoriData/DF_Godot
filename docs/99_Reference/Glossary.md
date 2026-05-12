# Project Glossary

A central reference for domain-specific and technical terminology used in *Desolate Frontiers*. This document is intended for both humans and AI agents to quickly locate relevant logic.

- [**AI Agent Guidelines**](file:///Users/aidan/Work/DF_Godot/docs/04_Technical/AI_Guidelines.md): Essential standards for AI-assisted coding.

## Domain Terms

- **Convoy**: The primary player-controlled entity. 
  - *Logic*: `Scripts/System/Services/convoy_service.gd`
  - *Data*: `convoy_id` (String UUID)
- **Settlement**: Static map locations.
  - *Logic*: `Scripts/System/Services/map_service.gd`
  - *Data*: `settlement_id`, `sett_type`
- **Journey**: Traversal between settlements.
  - *Logic*: `Scripts/System/Services/route_service.gd`
  - *UI*: `Scripts/Menus/convoy_journey_menu.gd`
- **Vehicle**: A unit within a Convoy that can have parts attached.
  - *Logic*: `Scripts/System/Services/mechanics_service.gd`
  - *Doc*: [Mechanics](file:///Users/aidan/Work/DF_Godot/docs/03_Systems/Mechanics.md)
- **Oori**: The "Old World" corporate aesthetic.
  - *Visuals*: `Assets/Themes/Oori Backround.png`
- **Warehouse**: Persistent storage at a settlement.
  - *Logic*: `Scripts/System/Services/warehouse_service.gd`

## Items & Mechanics

- **Unified Item Model**: The standard data structure for all physical goods.
  - *Logic*: `Scripts/Data/Items.gd`
  - *Doc*: [Items & Missions](file:///Users/aidan/Work/DF_Godot/docs/03_Systems/ItemsAndMissions.md)
- **CargoItem**: The base class for all items in the unified model.
- **MissionItem**: A specialized `CargoItem` representing a delivery contract.
  - *Logic*: Detected via `recipient_vendor_id` or `delivery_reward`.
- **PartItem**: A `CargoItem` that can be installed on a vehicle slot.
  - *Logic*: `Scripts/System/Services/mechanics_service.gd`
- **ResourceItem**: Consumables like fuel, water, and food.

## Technical Infrastructure

- **SignalHub**: The global event bus.
  - *File*: `Scripts/System/Services/signal_hub.gd` (Autoload)
- **GameStore**: The local "Source of Truth".
  - *File*: `Scripts/System/Services/game_store.gd` (Autoload)
- **APICalls**: The transport layer and network manager.
  - *File*: `Scripts/System/api_calls.gd` (Autoload)
- **Logger**: Centralized logging system with ring-buffer support.
  - *File*: `Scripts/System/Logger.gd` (Autoload)
  - *Doc*: [Diagnostics](file:///Users/aidan/Work/DF_Godot/docs/04_Technical/Diagnostics.md)
- **Logical Pixels**: Resolution-independent UI units.
  - *Logic*: `Scripts/UI/UI_scale_manager.gd`
- **DeviceStateManager**: Detects hardware orientation and triggers UI scaling.
  - *Logic*: `Scripts/System/device_state_manager.gd`
  - *Doc*: [Device State](file:///Users/aidan/Work/DF_Godot/docs/02_UI_UX/DeviceState.md)
- **Occlusion Width**: Map space covered by menus.
  - *Logic*: `Scripts/UI/main_screen.gd` (see `_current_menu_occlusion_px`)
- **Safe Area**: Screen zones safe from hardware notches/islands.
  - *Component*: `Scripts/UI/safe_area_handler.gd` (see `SafeRegionContainer`)
- **Queue Watchdog**: Self-healing for the HTTP request queue.
  - *Logic*: `Scripts/System/api_calls.gd` (see `QueueWatchdogTimer`)

## Identity & Authentication

- **Identity System**: Manages user authentication and session persistence.
  - *Doc*: [Identity](file:///Users/aidan/Work/DF_Godot/docs/04_Technical/Identity.md)
- **JWT (JSON Web Token)**: The security token for server communication.
  - *Logic*: `Scripts/System/api_calls.gd` (see `_auth_bearer_token`)
- **Account Merging**: Consolidating multiple social identities into one account.
  - *Logic*: `Scripts/System/api_calls.gd` (see `commit_merge`)

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

