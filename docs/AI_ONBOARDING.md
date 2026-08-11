---
type: note
tags:
  - kind/process
  - concept/scaling
  - status/current
aliases:
  - "AI Agent Onboarding: Quick-Start Guide"
created: 2026-05-18
updated: 2026-08-06
verified_against_code: 2026-07-28
status: current
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
    - **Corollary — `ui.scale` shrinks the logical viewport, it does not magnify content.** `target_w = 1920 / ui.scale`, so at `ui.scale = 2.0` a 1920px desktop window is only **960 logical px wide**. A panel sized in **fixed logical px** therefore grows as a *share of the screen* as the slider rises — the cause of several PC-only "this panel eats the screen" reports. Size share-of-screen panels as a fraction of `get_viewport_rect().size`, or give fixed-px panels a max-fraction cap. Mobile/portrait are immune (`ui.scale` is ignored there), which is why these bugs look PC-only. Full contract: [ui_system.md § Desktop scaling contract](02_UI_UX/ui_system.md#desktop-scaling-contract-and-why-fixed-width-panels-drift).
2.  **The Law of Unidirectional Data**:
    - Data flows: `API → Service → GameStore → SignalHub → UI`.
    - The UI **never** calls `APICalls` directly. It only listens to the `SignalHub` and reads from the `GameStore` snapshots.
    - **Corollary — display from the index, act on the record.** The same object reaches the client from **two** sources: the binary `/map` payload (an *index* — the whole world in one request, thin, and **stale by design**) and the per-object JSON endpoints like `/vendor/get` (the *record* — live and complete). Rendering a list from the index is correct. Letting a player **transact** against an index number is not: the index lags legitimately, *and* its packer has three times carried a different number than the transaction endpoint. Any value the server validates — a price, a capacity, a limit — must be confirmed against the record before the action is offered, or the UI will promise something that cannot happen (`S15-1`: a $23,000 vehicle the server refused at $45,750). Full contract, including the three-state trust gate and the two traps that cost real debugging time: [The Index and the Record](04_Technical/IndexAndRecord.md).
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
- **Prove your edit compiles**: [GDScript Verification](04_Technical/GDScriptVerification.md) — **run this
  before saying "compile-clean".** Two checks that do not substitute for each other: the editor pass
  (resolves autoloads and `class_name`, but only sees scripts something loads — a brand-new file is
  invisible to it) and the targeted load probe (sees exactly the files you name). Note `inference_on_variant`
  defaults to **Error**, so `var x := <something Variant>` is a hard parse error, not a warning.
- **Which service/autoload owns this?**: [Autoload Register](04_Technical/AutoloadOrder.md) — all 27, CI-checked against `project.godot`. A lookup, not a grep.
- **Understand an Object**: Check the [Data Schema](01_Architecture/Schema.md) — includes User, Settlement, Vendor, and Journey objects.
- **A layout looks broken**: [Debugging a Visual/Layout Bug](04_Technical/DebuggingVisualBugs.md) — **read before instrumenting**.
- **A stat reads blank, 0, or plausibly wrong everywhere** — or **the server refuses an action the UI offered**: [Data Boundaries](04_Technical/DataBoundaries.md) — likely the JSON-vs-binary seam, i.e. a *third* repo.
- **Which endpoint should this screen read — `/map` or `/vendor/get`?**: [The Index and the Record](04_Technical/IndexAndRecord.md) — the usage contract, and why acting on the index is never safe.
- **Debug a Request**: Check [Diagnostics](04_Technical/Diagnostics.md).
- **Debug a Signal**: Check the "Debug a Missing Signal" recipe in [Cookbook](01_Architecture/Cookbook.md).
- **Understand the Error Pipeline**: Check [ErrorSystem](04_Technical/ErrorSystem.md).
- **Definitions**: Check the [Glossary](99_Reference/Glossary.md).

---

## 📋 Working With These Docs

**Docs here are CI-validated, and they tell you how much to trust them. Read the frontmatter first.**

| `status:` | Means |
|---|---|
| `current` + recent `verified_against_code:` | Someone checked it against source. Trust it. |
| `unverified` | Not checked lately. Default suspicion applies. |
| `drifting` | **Known wrong.** Read the code, not the doc. |
| `archive` | Retired stub, kept so old links resolve. |

Three rules, in priority order:

1. **Code wins.** Every claim here is a point-in-time snapshot. Confirm `file:line` refs against source
   before relying on them — this doc set had five *fabricated* pages (a hex grid, a Fog of War system)
   that read completely plausibly. Verify, don't trust.
2. **If you change code and know its doc is now wrong, set that doc to `status: drifting`** — both the
   `status:` field and the `- status/drifting` tag. Five seconds, and it converts silent rot into a
   tracked item. This is the single highest-value habit in this repo.
3. **Status lives in [TODO.md](TODO.md), not in reference docs.** Bugs and in-flight work have stable IDs
   (`BUG-01`, `TD-04`, `S12-4`). Cite the ID; never restate the issue. Duplicated status is duplicated
   staleness — two `UIAudit` blocks were found describing bugs that had already been fixed.

Before committing any doc edit:

```bash
python3 tools/docs_check.py            # errors fail; also run by the pre-commit hook
python3 tools/docs_check.py --backlog  # what most needs re-verification, worst first
```

`--backlog` ranks **code-drift first** — docs whose cited source files were committed *after* the doc was
last verified — then by how many other docs depend on them. Worth running at the start of a session.

Full authoring contract (frontmatter, approved tags, index coverage, suppression markers):
[AI_Guidelines § 6](04_Technical/AI_Guidelines.md). Rationale and the structural review:
[DocumentationAudit](DocumentationAudit.md).

---

## 🚀 Pro Tips
- Before writing any code, check the **[Developer Cookbook](01_Architecture/Cookbook.md)** for a recipe. If a recipe exists, follow it strictly.
- When a menu isn't updating, check its `_debug_*` flag first. 9 times out of 10 the `process_mode` or a missed `is_connected` guard is the root cause.
- `money` from the API can be a `String`. Always read user money from `GameStore.get_user()["money"]` which is normalised to `int`.
- **Item names — "Jerry Cans" ≠ "Water Jerry Cans".** These are **two distinct cargo types**: plain *Jerry Cans* hold **fuel**, *Water Jerry Cans* hold **water**. The Level 2 tutorial supply step must ask for **Water Jerry Cans** specifically — never write bare "Jerry Cans" there, and never loosen a match to just `jerry` (require both `water` and `jerry`). Details in [Tutorial System](03_Systems/TutorialSystem/TutorialSystemOverview.md#content-gotcha-jerry-cans--water-jerry-cans) and the [Glossary](99_Reference/Glossary.md#items--cargo).
- **The tree is PAUSED during login, and `MainScreen` is disabled.** `GameScreenManager._ready()` sets
  `get_tree().paused = true`, `main_screen.visible = false`, **and**
  `main_screen.process_mode = PROCESS_MODE_DISABLED`, all held until `initial_data_ready`. So anything
  that must work before sign-in has **two** requirements: it needs `PROCESS_MODE_ALWAYS` (the default
  `INHERIT` is frozen by that pause, which silently kills `_process`, `_input`, **and**
  `_unhandled_key_input`), and it must not live under `MainScreen`. This caught both halves of S12-5 and
  S12-6 — in each case the code was correct and simply never ran. If a pre-login feature "does nothing",
  check these two before debugging its logic.
- **`NOTIFICATION_VISIBILITY_CHANGED` does not exist on `CanvasLayer`.** It is a `CanvasItem` constant,
  so using it in a `CanvasLayer` script (`SettingsMenu`, `ResponsiveModalPanel`, and every modal that
  extends it) is a **hard parse error**, not a silent no-op. `CanvasLayer` exposes a
  `visibility_changed` **signal** instead — connect that.
- **Map hit-tests have TWO call sites, and they drift.** `map_interaction_manager.gd` handles touch
  (`_handle_tap_interaction`) and mouse (`_handle_lmb_interactions`) in **separate branches** that
  independently call the same `_get_*_at_screen_pos()` helpers. Behavior added to one is **not** inherited
  by the other, and the result is a bug that reproduces on exactly one input method — the desktop
  pinned-label preview was live for months because only the touch branch checked the pin state. When you
  change what a map click *does*, grep for both branches and update them together.
- **A vendor/vehicle value that's wrong everywhere may be a third-repo bug, not this repo.**
  The vendor panel reads stats from the **binary `/map` payload**, whose wire format lives in a
  separate package — so the JSON API can be perfectly correct while the binary packer silently packs
  a default. `dict.get(renamed_key, 0)` raises nothing, anywhere. Field-level map + diagnosis steps:
  [Data Boundaries](04_Technical/DataBoundaries.md). Mechanism: [DF_Lib](04_Technical/DF_Lib.md).
  - **Don't screen for "blank or 0" alone.** That heuristic missed the vendor-price bug (`S15-1`), where
    the packer read a real neighbouring field and produced a *believable* smaller number. Every surface
    agreed with every other surface, because they all read the same wrong field; only the **server**
    disagreed, and only at purchase time.
  - **So: if the client offers an action and the server refuses it, suspect this seam before suspecting
    the server's rules.** A price, capacity, or limit that the server validates is P1 here, not cosmetic —
    it doesn't merely render wrong, it makes the UI promise something that cannot happen. The standing
    rule that prevents it: [display from the index, act on the record](04_Technical/IndexAndRecord.md).
  - **`value=<none>` on a vendor item, with a believable price on screen, IS the bug.** That price is
    `base_value` — the index number, not the charged one. Turn on the panel's `perf_log_enabled` and read
    the `[VendorPanel][S15-7]` line before theorising.
  - **Before editing any backend `to_JSONable_dict()`**, run the contract test — it names the offending
    key rather than making you find it:
    ```bash
    cd ~/Work/desolate_frontiers && python3 -m pytest test/test_map_serialization_contract.py -q
    ```
- **iPhone missing from the remote-deploy device list is almost always the Steam plugin, not
  hardware.** GodotSteam ships no iOS library, and a Godot restart silently re-enables it, so this
  recurs after *every* restart. Confirm the OS side first
  (`xcrun devicectl list devices` → `tunnelState=connected transport=wired`), then quit the editor
  and run `tools/steam_disable.sh`. Full rule + helper-script table:
  [Deployment § GodotSteam disabled-at-rest](04_Technical/Deployment.md).

---

## 🐛 Debugging a Visual/Layout Bug

**Read [Debugging a Visual/Layout Bug](04_Technical/DebuggingVisualBugs.md) BEFORE instrumenting.**
Four steps, in order: **(1)** make the user pinpoint the exact element and axis; **(2)** reproduce in the
editor — on-device builds are frozen until re-exported; **(3)** measure only *after* slide animations
settle; **(4)** rule out structure (stray `BackButton`, missing `ScrollContainer`) before tuning numbers.
