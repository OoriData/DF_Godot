---
type: note
tags:
  - codex/project_map
aliases:
  - "Project Map (Feature to File)"
created: 2026-05-18
---

# Project Map (Feature to File)

Use this map to quickly find where specific features or behaviors are implemented.

## 🚀 Navigation & UI
| Feature | File / Directory |
| :--- | :--- |
| **Adding a new Menu** | `Scripts/Menus/`, register in `menu_manager.gd` |
| **Trading / Inventory** | `Scripts/Menus/VendorPanel/`, [Vendor Panel](02_UI_UX/VendorPanel/VendorPanelOverview.md) |
| **Menu Animations** | `menu_manager.gd` (`_slide_menu_open`) |
| **Top Bar / Breadcrumbs** | `MenuBase.gd` (`setup_convoy_top_banner`) |
| **UI Scaling / Notches** | `UIScaleManager`, [Device State](02_UI_UX/DeviceState.md) |
| **Convoy Labels (on Map)** | `Scripts/UI/convoy_label_manager.gd` |

## 🗺️ Map & Gameplay
| Feature | File / Directory |
| :--- | :--- |
| **Map Rendering** | `Scripts/Map/`, [Map System](03_Systems/MapSystem/MapSystemOverview.md) |
| **Settlement Logic** | `Scripts/System/Services/map_service.gd` |
| **Journey Planning** | `Scripts/Menus/convoy_journey_menu.gd`, `route_service.gd` |
| **Part Compatibility** | `mechanics_service.gd`, [Mechanics](03_Systems/Mechanics.md) |
| **Tutorials** | `Scripts/UI/tutorial_manager.gd`, [Tutorial System](03_Systems/TutorialSystem/TutorialSystemOverview.md) |

## ⚙️ Core Infrastructure
| Feature | File / Directory |
| :--- | :--- |
| **Network Requests** | `api_calls.gd`, [Diagnostics](04_Technical/Diagnostics.md) |
| **State Persistence** | `Scripts/System/Services/game_store.gd` |
| **Background Polling** | `Scripts/System/Services/refresh_scheduler.gd` |
| **Authentication** | `user_service.gd`, [Identity](04_Technical/Identity.md) |
| **Item Classification** | `Items.gd`, [Items & Missions](03_Systems/ItemsAndMissions.md) |
| **Error Messages** | `Scripts/System/error_translator.gd` |

## 🛠️ Maintenance
| Task | File / Directory |
| :--- | :--- |
| **Updating Autoloads** | `project.godot` (Autoload section) |
| **Running Tests** | `Tests/`, `Scripts/Debug/wiring_smoke_test.gd` |
| **Visual Styling** | `Assets/Themes/`, `DesignSystem.md` |
| **AI Standards** | `docs/04_Technical/AI_Guidelines.md` |
