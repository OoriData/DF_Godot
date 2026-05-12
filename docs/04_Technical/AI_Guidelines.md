# AI Agent Coding Guidelines

This document provides specific instructions and constraints for AI agents (like Antigravity) working on the *Desolate Frontiers* codebase. Adhering to these patterns ensures consistency, performance, and UI responsiveness.

## 1. UI & Layout Principles

### The "Logical Pixel" Law
- **Target Resolution**: All UI layouts should be designed for a logical width of **800px** (Portrait) or **1600px** (Landscape).
- **No Hardcoded Sizes**: Never use `DisplayServer.window_get_size()` or raw screen pixels for layout math. 
- **Authority**: Use the `UIScaleManager` for scaling and `DeviceStateManager` for orientation detection.

### Responsive Design Standards
- **Safe Areas**: All critical UI elements must be children of a `SafeRegionContainer` to avoid hardware notches.
- **Fluid Containers**: Avoid rigid `custom_minimum_size`. If a container is clipping on mobile, check for nested `HBoxContainers` or `GridContainers` that are forcing a width larger than the 800px logical target.
- **Label Wrapping**: text-heavy labels must use `AUTOWRAP_WORD_SMART` and `SIZE_EXPAND_FILL` to prevent them from pushing their parent containers off-screen.

## 2. Data Flow & State Management

### The Unidirectional Pipeline
Follow the strict flow: `APICalls` → `Service` → `GameStore` → `SignalHub` → `UI`.
- **UI Independence**: UI components should **never** listen to `APICalls` directly. They must listen to `SignalHub` domain signals.
- **State Source**: Always fetch data from the `GameStore` snapshot during a UI redraw.

### The "Warming" Pattern
- **Requirement**: Before opening a menu that requires rich data (like Mechanics or Vendors), you must call the service's "Warmup" method (e.g., `mechanics_service.warm_mechanics_data_for_convoy()`).
- **Rationale**: Map snapshots often contain minimal data; warming ensures the UI has access to full metadata (stats, compatibility, etc.) immediately upon opening.

## 3. Component & Styling Standards

### Premium Aesthetics
- **Standard Styling**: Use `MenuBase` methods for consistent, premium UI styling:
    - `style_convoy_nav_button(button)`
    - `setup_convoy_top_banner(title)`
    - `_apply_standard_margins()`
- **MSDF Fonts**: Ensure all `Label` nodes use MSDF-enabled fonts for crisp scaling at different resolutions.

## 4. Signal Conventions

- **Domain Signals**: Defined in `SignalHub.gd`. These represent state changes (e.g., `convoys_changed`).
- **Transport Signals**: Defined in `api_calls.gd`. These represent raw HTTP completion.
- **Naming**: Use the `_changed` or `_updated` suffix for domain signals.

## 5. Coding Style

- **Strict Typing**: Use GDScript 2.0 static typing wherever possible.
- **ID Suffix**: Use the `_id` suffix for UUID strings (e.g., `convoy_id`, `settlement_id`).
- **Node Access**: Prefer unique names (`%NodeName`) or assigned variables over long absolute paths (`$VBox/Margin/Panel/Button`).
