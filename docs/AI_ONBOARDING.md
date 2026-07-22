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
    - `UIScaleManager` is the **single authority** on all UI scaling. It sets `content_scale_factor` — a pure float multiplier applied to the entire rendered canvas. Every Control, Label, and Button scales together automatically.
    - Target logical widths: **800px** Portrait · **1600px** Mobile Landscape · **1920px** Desktop (÷ `ui.scale` user preference). Desktop users can adjust zoom via the Settings slider.
    - Font sizes are **fixed logical values** set once (e.g. `add_theme_font_size_override("font_size", 16)`). **Never** multiply a font size at runtime. `TextScale` and `DeviceStateManager.get_scaled_base_font_size()` are **deleted** — do not recreate them.
    - For heavier-weight text, use `FontVariation.variation_embolden` on a `FontVariation` resource. Do not import a separate bold font file.
    - `DeviceStateManager` is for orientation/platform queries only (`get_is_portrait()`, `get_layout_mode()`, `is_mobile`). It no longer has any font-scaling role.
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
- **Fonts**: **MSDF** is required for **map labels** only — they zoom with `Camera2D` and need to stay sharp across a large zoom range. Regular UI Controls (`Label`, `Button`, etc.) do **not** need MSDF; `content_scale_factor` handles crispness at all window sizes.
- **Font weight**: `Lexend Light` is the project font. To increase weight, create a `FontVariation` with `variation_embolden = 0.8` and apply it via `add_theme_font_override("font", ...)`. See `convoy_menu.gd:_make_bold_font()` for the pattern.
- **Buttons**: Minimum **70px height** for mobile touch targets.
- **Layouts**: Use `SafeRegionContainer` for any element that might be clipped by a camera notch.
- **Orientation branching**: Query `DeviceStateManager.get_is_portrait()` and `get_layout_mode()` for orientation-aware branching. Never compare raw viewport sizes directly.
- **Navigation bar (no per-menu back buttons)**: Convoy/settlement-flow menus must **not** show their own `BackButton`. In `_ready()`, call `setup_convoy_navigation_bar(back_button)` to hide it, and add the menu's `menu_type` to the visibility list in `MenuManager._update_static_nav_bar_ui()` so the shared bottom bar (Vehicles / Journey / Settlement / Cargo) appears. A stray back button stacks at the bottom of `MainVBox` and clips off the sheet edge.
- **Containment (no clipping)**: A menu body that can grow taller than its sheet must live inside a `ScrollContainer` (see `ConvoyMenu.tscn`'s `MainVBox/ScrollContainer`) so overflow **scrolls** instead of clipping. Do **not** build a `SIZE_EXPAND_FILL` "fill-the-sheet" layout that assumes everything fits — when content exceeds the sheet height, `clip_contents` silently slices the top and bottom off with no error.

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
- **Item names — "Jerry Cans" ≠ "Water Jerry Cans".** These are **two distinct cargo types**: plain *Jerry Cans* hold **fuel**, *Water Jerry Cans* hold **water**. The Level 2 tutorial supply step must ask for **Water Jerry Cans** specifically — never write bare "Jerry Cans" there, and never loosen a match to just `jerry` (require both `water` and `jerry`). Details in [Tutorial System](03_Systems/TutorialSystem/TutorialSystemOverview.md#content-gotcha-jerry-cans--water-jerry-cans) and the [Glossary](99_Reference/Glossary.md#items--cargo).
- **A vendor/vehicle stat that's blank or 0 everywhere may be a third-repo bug, not this repo.** The vendor panel and map read vehicle/settlement stats from the **binary `/map` payload**, whose wire format is defined in a separate package ([DF_Lib](04_Technical/DF_Lib.md), not this repo, not the backend repo) and hand-mirrored byte-for-byte in `tools.gd`. A backend field rename can leave the JSON API (`/vendor/get`) fully correct while `df_lib`'s binary packer still reads the old key and silently packs `0` — so "not a backend issue" and "not a frontend issue" can both be true and the bug still unfixed. Check `df_lib/pylib/map_struct.py` for the old key name before concluding it's unfixable. See [DF_Lib](04_Technical/DF_Lib.md).
- **iPhone missing from the one-click / remote-deploy device list is almost always the Steam plugin, not hardware.** `addons/godotsteam` ships **no iOS library**, and in Godot 4.6 the old `ios.arm64 = ""` suppression no longer works, so a loaded GodotSteam extension blocks the iOS export platform and the device silently drops out of the deploy dropdown. A Godot/Mac **restart re-enables Steam** — the editor regenerates `.godot/extension_list.cfg` from the `.gdextension` files present at launch — so this recurs after *every* restart. Before chasing cables, Wi‑Fi, or sleep, confirm the OS side is healthy: `xcrun devicectl list devices --json-output <file>` should show the phone `tunnelState=connected transport=wired`. If it does, **quit the editor**, run `tools/steam_disable.sh`, reopen, and the device returns; reverse with `tools/steam_enable.sh` (editor closed) for desktop/Steam work. (A *separately* stuck CoreDevice tunnel — `tunnelState=disconnected`, `transport=localNetwork`, flapping — is a different failure, cleared with `sudo killall usbmuxd remoted`.) Full mechanism (why the `ios.arm64=""` trick broke in 4.6, the `apple_embedded` tag, and the `extension_list.cfg` regeneration) is documented in `tools/steam_disable.sh`'s header comment.

---

## 🐛 Debugging a Visual/Layout Bug (read BEFORE instrumenting)

A multi-session bug hunt — "the warehouse crams and breaks in portrait" — turned out to be a single stray back button, *after* hours spent chasing horizontal width and then vertical height. This protocol exists so it never happens again:

1. **Make the user pinpoint the defect first.** Words like *crammed · breaks · readjusts · clipping · colliding* identify neither the **element** nor the **axis**. Before building any diagnostic, ask which specific element is wrong and what it should look like — offer a numbered menu (e.g. *cut off at top/bottom · rows overlapping · jumps on open · a specific widget is oversized*). A screenshot with the bad element called out beats any amount of size-dumping. Guessing the axis costs whole rebuild-and-redeploy cycles.
2. **Reproduce in the editor, not only on device.** Editor Play (F5) recompiles current source every run; an exported/on-device build is a **frozen snapshot** — your edits do not appear until you **re-export _and_ re-deploy** (and only after **Save All**, since unsaved editor buffers aren't on disk). If a diagnostic's *value* contradicts the source you just wrote, you are running a stale build. A "canary" banner proves nothing about freshness unless it carries a per-build stamp (e.g. `git rev-parse --short HEAD`).
3. **Measure only after open/slide animations settle.** Menus slide in via `MenuManager`. A readout taken 1–2 frames after `_ready` captures a mid-slide layout and prints impossible, self-contradictory numbers (real example: a 3300px child reported inside a 1000px parent). Wait until the menu's `global_position` stops changing before trusting any `size` or `get_combined_minimum_size()` value.
4. **Rule out structure before tuning numbers.** Two recurring root causes, both cheap to check: **(a)** a stray per-menu `BackButton` instead of the shared nav bar, and **(b)** a missing `ScrollContainer`, so content clips once it exceeds the sheet (see *Navigation bar* and *Containment* under Visual Standards). Confirm these before touching fonts, margins, or min-sizes.

