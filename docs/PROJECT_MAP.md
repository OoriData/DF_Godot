# Project Map (Feature to File)

Use this map to quickly find where specific features or behaviors are implemented.

## 🚀 Navigation & UI
| Feature | File / Directory |
| :--- | :--- |
| **Adding a new Menu** | `Scripts/Menus/`, register in `menu_manager.gd` |
| **Menu Animations** | `menu_manager.gd` (`_slide_menu_open`) |
| **Top Bar / Breadcrumbs** | `MenuBase.gd` (`setup_convoy_top_banner`) |
| **UI Scaling / Notches** | `Scripts/UI/UI_scale_manager.gd`, `safe_area_handler.gd` |
| **Convoy Labels (on Map)** | `Scripts/UI/convoy_label_manager.gd` |

## 🗺️ Map & Gameplay
| Feature | File / Directory |
| :--- | :--- |
| **Map Rendering** | `Scripts/Map/map_camera_controller.gd`, `convoy_visuals_manager.gd` |
| **Settlement Logic** | `Scripts/System/Services/map_service.gd` |
| **Journey Planning** | `Scripts/Menus/convoy_journey_menu.gd`, `route_service.gd` |
| **Part Compatibility** | `Scripts/System/Services/mechanics_service.gd` |
| **Tutorial Steps** | `Scripts/UI/tutorial_manager.gd`, `docs/System/Tutorials.md` |

## ⚙️ Core Infrastructure
| Feature | File / Directory |
| :--- | :--- |
| **Network Requests** | `Scripts/System/api_calls.gd` |
| **State Persistence** | `Scripts/System/Services/game_store.gd` |
| **Background Polling** | `Scripts/System/Services/refresh_scheduler.gd` |
| **Authentication** | `Scripts/System/Services/user_service.gd`, `api_calls.gd` |
| **Error Messages** | `Scripts/System/error_translator.gd` |

## 🛠️ Maintenance
| Task | File / Directory |
| :--- | :--- |
| **Updating Autoloads** | `project.godot` (Autoload section) |
| **Running Tests** | `Tests/`, `Scripts/Debug/wiring_smoke_test.gd` |
| **Visual Styling** | `Assets/Themes/`, `DesignSystem.md` |
