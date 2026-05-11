# UI Design System

*Desolate Frontiers* uses a "premium-utilitarian" aesthetic, combining rugged, industrial elements with clean, modern digital overlays.

## Color Palette

### Core Colors
- **Oori Dark Grey** (`#25282a`): Used for backgrounds and primary containers. Often applied with an alpha of `0.85 - 0.95`.
- **Oori Blue** (`#00aaff`): The primary accent color for active states, selection highlights, and progress bars.
- **Status Green** (`#44ff44`): Success states, full capacity.
- **Warning Yellow** (`#ffff44`): High capacity, low resources.
- **Danger Red** (`#ff4444`): Critical errors, empty resources, damage.

### Text Colors
- **Primary**: `Color.WHITE` (with 6px black outline for readability on map).
- **Secondary**: `Color(0.8, 0.8, 0.8)` (for descriptions and auxiliary info).

---

## Typography

- **Primary Font**: `res://Assets/main_font.tres` (Outfit/Inter).
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

---

## Animation & Transitions

- **Slide Transitions**: Handled by `MenuManager`.
  - **Sub-menus**: Slide horizontally (Left/Right).
  - **Overview**: Swipes vertically (Down to open, Up to close).
- **Hover Effects**: All interactive buttons should have a subtle scale up (`1.05x`) or color shift on hover.
- **Micro-interactions**: Use `Tween` for smooth opacity fades when UI elements appear/disappear.
