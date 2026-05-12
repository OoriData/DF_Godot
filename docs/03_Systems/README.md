# Game Systems

This section covers the core simulation and gameplay mechanics of *Desolate Frontiers*.

## Key Systems
- [**Game Lifecycle**](GameLifecycle.md): Visualized state machines for Auth, Journeys, and Mechanics.
- [**Items & Missions**](ItemsAndMissions.md): Unified item model and mission detection logic.
- [**Map System**](MapSystem/README.md): Detailed reference for rendering, camera, and interactions.
- [**Mechanics & Parts**](Mechanics.md): Vehicle customization and part compatibility.
- [**Tutorial System**](TutorialSystem/README.md): Event-driven onboarding, highlights, and level controllers.

---

## Technical Mapping

### Map & Navigation
- **Visuals**: [convoy_visuals_manager.gd](../../../Scripts/Map/convoy_visuals_manager.gd), [ConvoyNode.tscn](../../../Scenes/ConvoyNode.tscn)
- **Input & Interaction**: [map_interaction_manager.gd](../../../Scripts/Map/map_interaction_manager.gd), [map_camera_controller.gd](../../../Scripts/Map/map_camera_controller.gd)
- **Primary Scene**: [MapView.tscn](../../../Scenes/MapView.tscn)

### Simulation & Mechanics
- **Mechanics Service**: [mechanics_service.gd](../../../Scripts/System/Services/mechanics_service.gd)
- **Convoy Service**: [convoy_service.gd](../../../Scripts/System/Services/convoy_service.gd)
- **Route Service**: [route_service.gd](../../../Scripts/System/Services/route_service.gd)

### Onboarding
- **Tutorial Manager**: [tutorial_manager.gd](../../../Scripts/UI/tutorial_manager.gd)
- **Target Resolver**: [tutorial_target_resolver.gd](../../../Scripts/UI/target_resolver.gd)
