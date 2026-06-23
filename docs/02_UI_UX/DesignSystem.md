---
type: ui-ux
tags:
  - ui
  - ux
  - codex/designsystem
aliases:
  - "UI Design System"
created: 2026-05-18
---

# UI Design System

*Desolate Frontiers* uses a **rugged-rusted industrial aesthetic being reclaimed by life** — a solarpunk hybrid. Dark weathered-metal structure, warm brass/cappuccino accents, and verdigris as the "living growth" signal, finished with clean glowing HUD overlays.

> [!IMPORTANT]
> Colors and spacing are **not** declared ad-hoc. The single source of truth is the `UITheme` autoload (`Scripts/System/ui_theme.gd`) for tokens, and the global `Assets/df_theme.tres` for control styling (wired via `gui/theme/custom` in `project.godot`). Do not re-declare palette `const`s in individual scripts — reference `UITheme.*`.

## Color Palette

### Core Oori Brand
- **Oori Dark Grey** (`#25282a`) → `UITheme.METAL_BASE`: primary container fill (alpha `0.85–0.95`).
- **Oori Grey** (`#393d47`) → `UITheme.METAL_EDGE`: borders, bevels, dividers.
- **Oori White** (`#dbe2e9`) → `UITheme.TEXT_PRIMARY`: primary text + light elements (replaces pure white).
- **Oori Yellow** (`#f3d54e`) → `UITheme.ACCENT_BRASS`: primary accent, currency, active-state glow.
- **Oori Red** (`#8a2b2b`) → `UITheme.DANGER`: critical errors, empty resources, damage.
- **Cappuccino** (`#633f33`) → `UITheme.SURFACE_WARM`: warm rugged surfaces (leather/wood/rust tone).

### Extensions (solarpunk half — not core Oori brand)
- **Verdigris** (`#5aa192`) → `UITheme.ACCENT_VERDIGRIS`: the only sanctioned non-brand accent. Living/growth/resource signal, active-tab tint, progress-bar fill.
- **Metal Dark** (`#1a1a1f`) → `UITheme.METAL_DARK`: deepest shadow / recessed wells.

### Accent Temperature Rule
Two temperatures, never muddied on the same element: **warm** (brass / cappuccino) = industrial & economic; **cool** (verdigris) = living & digital.

### Status Thresholds (resource/capacity bars)
- Good/full → verdigris `#5aa192`; Caution/low → brass `#f3d54e`; Critical/empty → red `#8a2b2b`. Use `UITheme.status_for_ratio(ratio)`.

### Text Colors
- **Primary**: `UITheme.TEXT_PRIMARY` (`#dbe2e9`) — with outline for readability on the map.
- **Secondary/Muted**: `UITheme.TEXT_MUTED` (`#8b929c`) — descriptions, captions, auxiliary info.

## Spacing System
Base unit **8px**. Allowed steps via `UITheme`: `SPACE_XS` 4, `SPACE_SM` 8, `SPACE_MD` 12, `SPACE_LG` 16, `SPACE_XL` 24, `SPACE_XXL` 32. Corner radii: `RADIUS_SM` 4, `RADIUS_MD` 6, `RADIUS_LG` 8.

---

## Typography

- **Primary Font**: `res://Assets/main_font.tres` (Lexend Light base, with math + emoji fallbacks). Set as the theme `default_font` in `df_theme.tres`.
- **MSDF Enabled**: All UI fonts must use Multi-channel Signed Distance Field (MSDF) for crisp scaling at any resolution.
- **Standard Sizes (Logical 800px width)**:
  - **Headers**: 36pt - 42pt.
  - **Body**: 24pt - 28pt.
  - **Small/Captions**: 18pt - 20pt.

---

## Standard Components

### 1. Convoy Top Banner
Every full-screen menu should have a standard top banner generated via `MenuBase.setup_convoy_top_banner()`.
- **Structure**: `[Back Button] [Title] > [Subtitle]`.
- **Interactive**: The Title is often a breadcrumb that returns the user to the Convoy Overview.

### 2. Touch Targets
To ensure mobile friendliness, adhere to these minimum logical sizes:
- **Primary Buttons**: 70px height (Portrait), 50px height (Landscape).
- **Gaps/Margins**: 14px logical buffer between interactive elements.

### 3. Backgrounds
- **The "Oori" Background**: A tiled, dark textured background applied via `MenuBase.auto_apply_oori_background`.
- **Transparency**: High-level containers should use `_maximize_transparency_recursive` to ensure the Oori background isn't obscured by redundant panel styles.

### 4. Button / Control Hierarchy

Three visual tiers distinguish how interactive controls behave. Never style them identically — a filter control that looks like a primary action button destroys affordance.

| Tier | Style function | Tokens | Used for |
|------|---------------|--------|----------|
| **Primary action** | `_style_primary_button()` | Deep verdigris fill + `ACCENT_VERDIGRIS` border | The single commit button (Buy / Sell). |
| **Neutral action** | `_style_neutral_button()` | `METAL_BASE` fill + `METAL_EDGE` border | Utility actions that execute immediately: Max, steppers. |
| **Filter / parameter** | `_style_filter_control(b, active)` | `METAL_DARK` (recessed) fill + verdigris-tinted border (`METAL_EDGE` lerped 55 % toward `ACCENT_VERDIGRIS`) | Controls that **set state** rather than commit an action: vendor-type dropdown, Buy/Sell mode toggle, Sort selector. The `active=true` variant (current trade direction) promotes to full `ACCENT_VERDIGRIS` border + darker verdigris fill + light verdigris text. |

**Key implementation notes for filter controls:**
- Set `b.flat = false` — Godot `MenuButton` defaults to `flat = true`, which suppresses the `normal` stylebox and makes the border invisible.
- In a mixed control row, let the always-visible element use `SIZE_EXPAND_FILL` to absorb slack; controls that can hide should use `SIZE_SHRINK_BEGIN` / `SIZE_SHRINK_END` so disappearing doesn't leave a gap.

---

## Animation & Transitions

- **Slide Transitions**: Handled by `MenuManager`.
  - **Sub-menus**: Slide horizontally (Left/Right).
  - **Overview**: Swipes vertically (Down to open, Up to close).
- **Hover Effects**: All interactive buttons should have a subtle scale up (`1.05x`) or color shift on hover.
- **Micro-interactions**: Use `Tween` for smooth opacity fades when UI elements appear/disappear.
