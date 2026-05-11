# Scene & Layer Architecture

The *Desolate Frontiers* UI is built as a stacked series of layers, managed primarily by the `MainScreen.tscn` and orchestrated by `MenuManager` and `UIManager`.

## Root Scene: `MainScreen.tscn`

The `MainScreen` is the master container for the entire game session. It acts as a mediator between the 3D/Map view and the 2D UI elements.

### Layer Hierarchy (Z-Order)

1. **MapView (Bottom)**: 
   - Contains the `SubViewport` where the map, terrain, and convoys are rendered.
   - Includes the `ConvoyLabelContainer` (managed by `ConvoyLabelManager`) for in-world UI labels.
2. **OnboardingLayer**:
   - Parented to `MapView`.
   - Used by the `TutorialManager` for highlighting UI elements and showing onboarding modals (like the `NewConvoyDialog`).
3. **SafeRegionContainer**:
   - A logic-heavy container that applies margins based on the `UIScaleManager` safe-area calculations (for mobile notches).
   - **MainContainer**: Holds the `TopBar` and the `MenuContainer`.
4. **ModalLayer (Top)**:
   - Contains the `Scrim` (a full-screen dimming layer).
   - Used for high-priority popups and blocking interactions during critical states.

---

## Menu Composition

Menus are not fixed scenes; they are dynamically instanced and animated into the `MenuContainer`.

- **Persistent Top Bar**: The `TopBar` stays visible even when a menu is open, providing breadcrumbs and global stats.
- **Slide-in Animation**: 
  - On **Landscape/Desktop**, the menu slides in from the **Right**.
  - On **Portrait/Mobile**, the menu slides up from the **Bottom**.
- **Camera Interaction**: When a menu opens, it informs the `CameraController` of its "occlusion width". The camera then smoothly shifts the world-view center to keep the selected convoy visible in the remaining screen space.

---

## Best Practices for New UI

1. **Use `SafeRegionContainer`**: Always place new full-screen UI elements inside a container that respects logical safe margins.
2. **Inherit from `MenuBase`**: Any full-screen menu must extend `MenuBase` to get standard transition support and automatic background styling.
3. **Don't Hardcode Z-Index**: Use the established layer hierarchy in `MainScreen` to ensure your UI doesn't appear under the map or over critical tutorial highlights.
4. **Mouse Filters**: Root UI nodes should generally have `Mouse Filter = Stop`, while decorative or pass-through layers should be set to `Ignore`.
