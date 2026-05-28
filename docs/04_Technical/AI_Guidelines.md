---
type: technical
tags:
  - technical
  - codex/ai_guidelines
aliases:
  - "AI Agent Coding Guidelines"
created: 2026-05-18
---

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
- **Label Wrapping**: Text-heavy labels must use `AUTOWRAP_WORD` and `SIZE_EXPAND_FILL` to prevent them from pushing their parent containers off-screen.
- **Dynamic Font & Responsive Panel Sizing**:
  - Always implement a dynamic font-scaling helper in programmatic controls to ensure legibility on both mobile (high-DPI) and desktop landscape:
    ```gdscript
    func _get_font_size(base: int) -> int:
        var boost = 2.6 if _is_portrait() else (2.0 if _is_mobile() else 1.6)
        return int(base * boost)
    ```
  - Base sizes must be large enough: Title (Base `22`–`24`), Row Header (Base `16`–`18`), Description Subtext (Base `12`–`14`).
  - Panel widths must be responsive rather than hardcoded. For floating slide-out panels, use screen width percentages in portrait (e.g., `win_size.x * 0.75`) and ample horizontal width in landscape (e.g., `440px`) to let large text wrap beautifully with sufficient padding.
  - Wrap custom toggle items and lists inside individual **glassmorphic containers** (`StyleBoxFlat` with thin border accents) and supply helper subtext descriptions to fill out space and make the UI look complete.

### Viewport & Rendering Standards (GL Compatibility / Cross-Platform)
- **No Dynamic Every-Frame Texture Re-assignments**: Never call `viewport.get_texture()` and re-assign it to a `TextureRect.texture` inside a `_process()` loop. Doing so breaks texture caching and triggers severe GPU state-transition thrashing under the OpenGL Compatibility renderer (especially on macOS Apple Silicon), leading to pitch-black rendering.
- **No Programmatic `ViewportTexture.new()` instantiation**: In Godot 4.x, instantiating `ViewportTexture.new()` programmatically at runtime fails to resolve local-to-scene relative paths correctly on many stable versions, resulting in a persistent black texture.
- **The Correct Pattern**: Get the pre-resolved texture reference via `viewport.get_texture()` and assign it **only once** (e.g., in `_ready()` or during layout setup):
  ```gdscript
  if is_instance_valid(viewport):
      texture_rect.texture = viewport.get_texture()
  ```
  This is 100% stable, resolves instantly without path-lookup bugs, and avoids all GPU state-transition thrashing.

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
