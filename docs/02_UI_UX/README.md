# UI & UX System

The *Desolate Frontiers* UI is built on a service-backed architecture that ensures data consistency and responsive layout across all devices.

## Core Architecture
- [**Scene Architecture**](SceneArchitecture.md): Viewport layering, MainScreen hierarchy, and menu composition.
- [**Responsive UI System**](ui_system.md): Logical scaling, orientation handling, and mobile design patterns.
- [**Design System**](DesignSystem.md): Visual tokens, typography, and component standards.
- [**Asset Pipeline**](AssetPipeline.md): Standards for textures, fonts, and map tiles.
- [**MenuManager**](MenuManager.md): Navigation hub, transition logic, and state persistence.
- [**MenuBase Contract**](MenuBase.md): Standardizing menu initialization and lifecycle.

---

## Technical Mapping (Scripts)

- **Main (MapView)**: [main.gd](../../../Scripts/System/main.gd)
- **MapInteractionManager**: [map_interaction_manager.gd](../../../Scripts/Map/map_interaction_manager.gd)
- **ConvoyVisualsManager**: [convoy_visuals_manager.gd](../../../Scripts/Map/convoy_visuals_manager.gd)
- **UIManager**: [UI_manager.gd](../../../Scripts/UI/UI_manager.gd)
- **ScaleManager**: [UI_scale_manager.gd](../../../Scripts/UI/UI_scale_manager.gd)

---

## Available Menus
- [**Convoy Overview**](../../../Scripts/Menus/convoy_menu.gd): The landing page for a specific convoy.
- [**Vehicle Sub-menu**](../../../Scripts/Menus/convoy_vehicle_menu.gd): Vehicle stats, parts, and damage.
- [**Journey Sub-menu**](../../../Scripts/Menus/convoy_journey_menu.gd): Navigation, route selection, and progress.
- [**Settlement Sub-menu**](../../../Scripts/Menus/convoy_settlement_menu.gd): Local services and info.
- [**Cargo Sub-menu**](../../../Scripts/Menus/convoy_cargo_menu.gd): Full manifest and item inspection.
- [**Warehouse Menu**](../../../Scripts/Menus/warehouse_menu.gd): Storing and retrieving cargo/vehicles.
- [**Mechanics Menu**](../../../Scripts/Menus/mechanics_menu.gd): Complex part repairs and swaps.
- [**Vendor Panel**](VendorPanel/README.md): Detailed reference for the complex trading and inventory system.

---

## Implementation Patterns

### 1. Convoy Context
Most menus operate on a "Convoy Context". They are initialized with a `convoy_id` and subscribe to `GameStore.convoys_changed`. This allows the UI to stay perfectly in sync with backend updates without manual polling.

### 2. Mobile-First Standard
- **Touch Targets**: Minimum 70px height for buttons in portrait.
- **Safe Areas**: Use `SafeRegionContainer` to prevent notch clipping.
- **Fluid Layouts**: Labels must have `SIZE_EXPAND_FILL` and `AUTOWRAP` to prevent horizontal clipping.
