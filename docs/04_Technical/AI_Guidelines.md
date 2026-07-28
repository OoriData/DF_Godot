---
type: technical
tags:
  - layer/autoload
  - kind/process
  - status/unverified
aliases:
  - "AI Agent Coding Guidelines"
created: 2026-05-18
updated: 2026-05-21
status: unverified
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
- **Font sizing — do NOT scale at runtime**:
  > [!WARNING]
  > **Corrected 2026-07-28.** This section previously prescribed a `_get_font_size(base)` helper that
  > multiplied by a per-orientation `boost`. That pattern is **forbidden** by the Law of Logical Pixels —
  > it double-scales on top of `content_scale_factor` and is the documented cause of the
  > "oversized / cramped / scrolling menu" class of bugs. Canonical rule:
  > [AI_ONBOARDING § The Law of Logical Pixels](../AI_ONBOARDING.md) — **that page wins on conflict.**

  - Set font sizes **once**, as fixed logical values: `add_theme_font_size_override("font_size", 16)`.
    `UIScaleManager.content_scale_factor` handles every device. Never multiply a font size at runtime.
  - Logical base sizes: Title `22`–`24`, Row Header `16`–`18`, Description Subtext `12`–`14`.
  - For heavier text, use a `FontVariation` with `variation_embolden`, not a larger size.
  - Panel widths must be responsive rather than hardcoded — and on desktop, express them as a **fraction
    of `get_viewport_rect().size`**, not fixed logical px. A fixed-px panel grows as a share of the screen
    as `ui.scale` rises, because `ui.scale` *shrinks the logical viewport*. See
    [ui_system.md § Desktop scaling contract](../02_UI_UX/ui_system.md#desktop-scaling-contract-and-why-fixed-width-panels-drift).
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
- **MSDF Fonts**: **Not** required for ordinary UI — `content_scale_factor` handles crispness at every
  window size. MSDF matters only for **map labels**, which zoom with `Camera2D` across a large range.
  *Verified 2026-07-28:* the project font (`Assets/Lexend Light.ttf`) currently imports with
  `multichannel_signed_distance_field=false`, so nothing in the project is MSDF today — treat the
  map-label recommendation in [AI_ONBOARDING](../AI_ONBOARDING.md) as aspirational until that changes.

## 4. Signal Conventions

- **Domain Signals**: Defined in `SignalHub.gd`. These represent state changes (e.g., `convoys_changed`).
- **Transport Signals**: Defined in `api_calls.gd`. These represent raw HTTP completion.
- **Naming**: Use the `_changed` or `_updated` suffix for domain signals.

## 5. Coding Style

- **Strict Typing**: Use GDScript 2.0 static typing wherever possible.
- **ID Suffix**: Use the `_id` suffix for UUID strings (e.g., `convoy_id`, `settlement_id`).
- **Node Access**: Prefer unique names (`%NodeName`) or assigned variables over long absolute paths (`$VBox/Margin/Panel/Button`).

## 6. Documentation Standards

**CI enforces these.** `tools/docs_check.py` runs on every push and PR touching `docs/`; errors fail the
build. Run it locally before committing:

```bash
python3 tools/docs_check.py
```

### Frontmatter — required on every doc

```yaml
---
type: technical                    # architecture | ui-ux | system | technical | reference | note
tags:
  - layer/autoload                 # approved vocabulary only — see APPROVED_TAGS in docs_check.py
  - kind/deep-dive
  - status/unverified
created: 2026-05-18
updated: 2026-07-28                # maintained by the pre-commit hook
verified_against_code: 2026-07-28  # ONLY when you actually re-read the source — never automate
status: unverified                 # current | unverified | drifting | archive
---
```

- **`updated` vs `verified_against_code`.** The first tracks edits; the second tracks whether a human
  confirmed the doc still matches the code. Editing prose is *not* verification. Set
  `verified_against_code` (and `status: current`) only when you have actually checked, and never
  backfill it in bulk — that destroys the only signal the field carries.
- **`status: drifting`** is the right answer when you notice a doc is wrong but can't fix it now. It is
  more useful than silence.

### Tags

Use the approved facets only — `layer/`, `platform/`, `concept/`, `status/`, `kind/`. The list lives in
`APPROVED_TAGS` in `tools/docs_check.py`; adding a tag means editing that set deliberately. Per-file
singleton tags (the retired `codex/*` scheme) are what this replaced — don't reintroduce them.

### Links and structure

- **Every doc belongs to its section index**, directly or via a sub-overview the index links to.
  The five indexes are `ArchitectureIndex`, `UIAudit` (for `02_UI_UX/`), `GameSystemsIndex`,
  `TechnicalReference`, and `Glossary` (for `99_Reference/`).
- **Relative markdown links only** — no `[[wikilinks]]`; they break outside Obsidian.
- **Anchors are checked.** A `#fragment` must match a real heading. If you want to link to something,
  make it a heading — don't cite bold text.
- **Add a `## Related` footer** with typed edges (`Constrained by:`, `Implemented in:`, `See also:`,
  `Live status:`). Dead-end docs are the graph's biggest structural weakness.
- **Citing a path that is deliberately wrong or not yet written?** Wrap it:
  `<!-- docs-check:ignore-codepaths start -->` … `<!-- docs-check:ignore-codepaths end -->`.

### Status belongs in `TODO.md`

Reference docs describe *how things work*. Bugs, in-flight work, and polish items live in
[TODO.md](../TODO.md) with a stable ID (`S12-4`, `BUG-07`). Cite the ID from a reference doc rather than
restating the issue — duplicated status is duplicated staleness.

Rationale and the full structural review: [DocumentationAudit.md](../DocumentationAudit.md).
