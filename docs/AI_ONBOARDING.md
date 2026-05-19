---
type: note
tags:
  - codex/ai_onboarding
aliases:
  - "AI Agent Onboarding: Quick-Start Guide"
created: 2026-05-18
---

# AI Agent Onboarding: Quick-Start Guide

Welcome, Agent. To maintain the architectural integrity and visual standards of *Desolate Frontiers*, you **must** adhere to the following core laws.

## ⚖️ The Five Laws of Development

1.  **The Law of Logical Pixels**: 
    - Always target an **800px width** for Portrait and **1600px width** for Landscape. 
    - Use `UIScaleManager` to handle scaling; never hardcode physical pixel sizes for UI elements.
2.  **The Law of Unidirectional Data**:
    - Data flows: `API → Service → GameStore → SignalHub → UI`.
    - The UI **never** calls `APICalls` directly. It only listens to the `SignalHub` and reads from the `GameStore` snapshots.
3.  **The Law of Thin Panels**:
    - Complex UI logic must live in a **Controller** (e.g., `Scripts/Menus/VendorPanel/`).
    - The `.gd` script attached to a Scene should only handle wiring and signal redirection.
4.  **The Law of Diagnostic Flags**:
    - Every major menu script declares a `var _debug_<menu_name>: bool = true` flag at the top.
    - All verbose `print()` calls are gated behind this flag: `if _debug_my_menu: print(...)`.
    - When you see unexpected behavior in a menu, flip its flag to `true` and read the output before adding new code.
    - For heavy wiring checks, use a separate `_diag_*` method connected as a secondary signal handler (see `WarehouseMenu` for examples).
5.  **The Law of Debounced Updates**:
    - Menus that react to multiple signals (e.g., `vendor_updated` + `convoys_changed`) use a short `Timer` (typically 100ms) to collapse simultaneous signal bursts into a single redraw.
    - Pattern: check `if not _timer.is_stopped(): return` — if the timer is already running, the update is already queued.
    - Do **not** add synchronous redraw calls inside signal handlers in these menus. Always go through `_queue_*_update()`.

---

## 🛠️ Visual Standards
- **Fonts**: Use **MSDF** versions of fonts for map labels and scaling UI.
- **Buttons**: Minimum **70px height** for mobile touch targets.
- **Layouts**: Use `SafeRegionContainer` for any element that might be clipped by a camera notch.
- **DeviceStateManager**: Query `DeviceStateManager.get_is_portrait()` and `get_layout_mode()` for orientation-aware branching. Don't use raw viewport size comparisons.

---

## 🗺️ Navigation Map
- **Find a Feature**: Check the [Project Map](PROJECT_MAP.md).
- **Understand an Object**: Check the [Data Schema](01_Architecture/Schema.md) — includes User, Settlement, Vendor, and Journey objects.
- **Debug a Request**: Check [Diagnostics](04_Technical/Diagnostics.md).
- **Debug a Signal**: Check the "Debug a Missing Signal" recipe in [Cookbook](01_Architecture/Cookbook.md).
- **Understand the Error Pipeline**: Check [ErrorSystem](04_Technical/ErrorSystem.md).
- **Definitions**: Check the [Glossary](99_Reference/Glossary.md).

---

## 🚀 Pro Tips
- Before writing any code, check the **[Developer Cookbook](01_Architecture/Cookbook.md)** for a recipe. If a recipe exists, follow it strictly.
- When a menu isn't updating, check its `_debug_*` flag first. 9 times out of 10 the `process_mode` or a missed `is_connected` guard is the root cause.
- `money` from the API can be a `String`. Always read user money from `GameStore.get_user()["money"]` which is normalised to `int`.

