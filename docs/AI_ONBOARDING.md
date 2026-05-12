# AI Agent Onboarding: Quick-Start Guide

Welcome, Agent. To maintain the architectural integrity and visual standards of *Desolate Frontiers*, you **must** adhere to the following core laws.

## ⚖️ The Three Laws of Development

1.  **The Law of Logical Pixels**: 
    - Always target an **800px width** for Portrait and **1600px width** for Landscape. 
    - Use `UIScaleManager` to handle scaling; never hardcode physical pixel sizes for UI elements.
2.  **The Law of Unidirectional Data**:
    - Data flows: `API → Service → GameStore → SignalHub → UI`.
    - The UI **never** calls `APICalls` directly. It only listens to the `SignalHub` and reads from the `GameStore` snapshots.
3.  **The Law of Thin Panels**:
    - Complex UI logic must live in a **Controller** (e.g., `Scripts/Menus/VendorPanel/`).
    - The `.gd` script attached to a Scene should only handle wiring and signal redirection.

## 🛠️ Visual Standards
- **Fonts**: Use **MSDF** versions of fonts for map labels and scaling UI.
- **Buttons**: Minimum **70px height** for mobile touch targets.
- **Layouts**: Use `SafeRegionContainer` for any element that might be clipped by a camera notch.

## 🗺️ Navigation Map
- **Find a Feature**: Check the [Project Map](PROJECT_MAP.md).
- **Understand an Object**: Check the [Data Schema](01_Architecture/Schema.md).
- **Debug a Request**: Check [Diagnostics](04_Technical/Diagnostics.md).
- **Definitions**: Check the [Glossary](99_Reference/Glossary.md).

## 🚀 Pro Tip
Before writing any code, check the **[Developer Cookbook](01_Architecture/Cookbook.md)** for a recipe. If a recipe exists, follow it strictly.
