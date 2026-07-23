---
type: system
tags:
  - system
  - system/tutorial
  - codex/target-resolution
aliases:
  - "Tutorial Target Resolution"
created: 2026-05-19
---

# Tutorial Target Resolution

The `TargetResolver` translates abstract step definitions into precise UI nodes in the active SceneTree, enabling the `TutorialManager` to highlight elements and gate input.

## Core Features
1. **Node Path Mapping**:
   - Resolves string identifiers (e.g., `"ConvoyNavButton"`) to actual Control nodes.
   - Heavily relies on strict, predictable naming conventions in the UI hierarchy.
2. **Input Gating**:
   - `HARD` gating: Blocks all clicks except the exact target rectangle.
   - `SOFT` gating: Allows interaction while displaying the tutorial text.
3. **Resilience**:
   - Handles dynamic viewport scaling (`UIScaleManager`) and mobile Safe Regions to prevent highlight clipping.
   - Recalculates bounding boxes during screen rotation.

## Key Files
- **Resolver**: `Scripts/UI/target_resolver.gd`
- **Manager**: `Scripts/UI/tutorial_manager.gd`
- **Overlay**: `Scripts/UI/tutorial_overlay.gd`

## Connected Systems
- [Step Schema](StepSchema.md)
