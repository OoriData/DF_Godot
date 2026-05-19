---
type: technical
tags:
  - technical
  - codex/text-scale
aliases:
  - "TextScale Manager"
created: 2026-05-19
---

# TextScale Manager

`TextScale` (`text_scale.gd`) is an Autoload singleton that handles dynamic typography scaling for High-DPI screens and diverse device form factors.

## Key Files
- **Script**: `Scripts/System/text_scale.gd`

## Core Responsibilities
- **Resolution Independence**: Normalizes text sizes across desktop and mobile screens, ensuring legibility without breaking layouts.
- **Dynamic Binding**: UI components register with `TextScale` (e.g., `TextScale.register(node)`) to automatically adjust their fonts when the window is resized or orientation changes.
- **Viewport Coordination**: Operates alongside `UI_scale_manager` and `DeviceStateManager`.

## Connected Systems
- [Responsive UI System](../02_UI_UX/ui_system.md)
