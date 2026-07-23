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

> [!TIP]
> For UI *structure* (layer map, script mapping, per-element scene trees) start with the [**UI Element Audit**](02_UI_UX/UIAudit.md). For *current state, known issues, and in-flight work*, see [**TODO.md**](TODO.md).

| Task | Where to go |
| :--- | :--- |
| **Any UI change — start here** | [UIAudit.md](02_UI_UX/UIAudit.md) |
| **Adding a new Menu** | [UIAudit → Adding a New Menu](02_UI_UX/UIAudit.md#adding-a-new-menu), then `Scripts/Menus/` extending `MenuBase` |
| **Menu lifecycle / data binding** | [MenuBase.md](02_UI_UX/MenuBase.md) → `initialize_with_data`, `_update_ui`, `reset_view` |
| **Menu navigation / transitions** | [MenuManager.md](02_UI_UX/MenuManager.md), `menu_manager.gd` |
| **UI scaling / safe areas / notches** | [ui_system.md](02_UI_UX/ui_system.md), [DeviceState.md](02_UI_UX/DeviceState.md) |
| **Visual styling / color tokens** | [DesignSystem.md](02_UI_UX/DesignSystem.md), `Assets/Themes/` |
| **TopBar / Navbar** | [UIAudit → §1 TopBar](02_UI_UX/UIAudit.md#1-topbar--navbar--userinfodisplaytscn) |
| **Convoy selector dropdown** | [UIAudit → §2 ConvoyListPanel](02_UI_UX/UIAudit.md#2-convoy-selector--convoylistpaneltscn) |
| **Convoy overview / sub-menus** | [ConvoyMenu.md](02_UI_UX/ConvoyMenu.md), [UIAudit → §4–5](02_UI_UX/UIAudit.md#4-convoy-overview-menu--convoymenutscn) |
| **Cargo menu** | [ConvoyCargoMenu.md](02_UI_UX/ConvoyCargoMenu.md) |
| **Warehouse / Vendor / Mechanics** | [WarehouseMenu.md](02_UI_UX/WarehouseMenu.md), [VendorPanel](02_UI_UX/VendorPanel/VendorPanelOverview.md), [MechanicsMenu.md](02_UI_UX/MechanicsMenu.md) |
| **Modals (receipt, premium, tips)** | [UIAudit → §11](02_UI_UX/UIAudit.md#11-modals-post-journey-premium-tips) |
| **Map labels / overlays** | `Scripts/UI/convoy_label_manager.gd`, `Scripts/UI/UI_manager.gd` |
| **Known UI bugs / in-flight work / tech debt** | [TODO.md](TODO.md) |

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
| **Example payloads / data shapes** | [data_dumps/README.md](99_Reference/data_dumps/README.md) |
| **Error Messages** | `Scripts/System/error_translator.gd` |

## 🛠️ Maintenance
| Task | File / Directory |
| :--- | :--- |
| **Updating Autoloads** | `project.godot` (Autoload section) |
| **Running Tests** | `Tests/`, `Scripts/Debug/wiring_smoke_test.gd` |
| **Visual Styling** | `Assets/Themes/`, [DesignSystem.md](02_UI_UX/DesignSystem.md) |
| **AI Standards** | `docs/04_Technical/AI_Guidelines.md` |
| **Updating the UI Audit** | [UIAudit.md](02_UI_UX/UIAudit.md) — update the structural map after any UI *scene/script* change; log bugs & polish in [TODO.md](TODO.md) |
