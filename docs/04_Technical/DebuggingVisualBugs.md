---
type: technical
tags:
  - layer/ui
  - kind/process
  - concept/scaling
  - status/current
aliases:
  - "Debugging a Visual/Layout Bug"
created: 2026-07-28
updated: 2026-07-29
verified_against_code: 2026-07-28
status: current
---

# Debugging a Visual/Layout Bug

**Read this before instrumenting anything.**

A multi-session bug hunt — *"the warehouse crams and breaks in portrait"* — turned out to be a single
stray back button, after hours spent chasing horizontal width and then vertical height. This protocol
exists so that never happens again.

---

## 1. Make the user pinpoint the defect first

Words like *crammed · breaks · readjusts · clipping · colliding* identify neither the **element** nor the
**axis**. Before building any diagnostic, ask which specific element is wrong and what it should look
like — offer a numbered menu (e.g. *cut off at top/bottom · rows overlapping · jumps on open · a specific
widget is oversized*). A screenshot with the bad element called out beats any amount of size-dumping.

**Guessing the axis costs whole rebuild-and-redeploy cycles.**

## 2. Reproduce in the editor, not only on device

Editor Play (F5) recompiles current source every run. An exported/on-device build is a **frozen
snapshot** — your edits do not appear until you **re-export _and_ re-deploy**, and only after **Save
All**, since unsaved editor buffers aren't on disk.

> If a diagnostic's *value* contradicts the source you just wrote, you are running a stale build.

A "canary" banner proves nothing about freshness unless it carries a per-build stamp
(e.g. `git rev-parse --short HEAD`).

## 3. Measure only after open/slide animations settle

Menus slide in via [`MenuManager`](../02_UI_UX/MenuManager.md). A readout taken 1–2 frames after `_ready`
captures a mid-slide layout and prints impossible, self-contradictory numbers — a real example logged a
3300px child inside a 1000px parent.

Wait until the menu's `global_position` stops changing before trusting any `size` or
`get_combined_minimum_size()` value.

## 4. Rule out structure before tuning numbers

Two recurring root causes, both cheap to check:

- **A stray per-menu `BackButton`** instead of the shared nav bar. Convoy/settlement-flow menus must call
  `setup_convoy_navigation_bar(back_button)` in `_ready()` and register their `menu_type` in
  `MenuManager._update_static_nav_bar_ui()`. A stray button stacks at the bottom of `MainVBox` and clips
  off the sheet edge.
- **A missing `ScrollContainer`**, so content clips silently once it exceeds the sheet.
  `clip_contents` slices the top and bottom off with **no error**.

Confirm both before touching fonts, margins, or min-sizes.

---

## Scaling-specific traps

If the symptom is *oversized / cramped / forces scrolling*, suspect double-scaling before layout:

- **A runtime font multiplier.** `_get_font_size(base)` must be a flat `return base`. Any
  `int(base * boost)` double-scales on top of `content_scale_factor`. Known un-migrated call sites are
  tracked in [TODO.md](../TODO.md).
- **A fixed-px panel on desktop.** `ui.scale` *shrinks the logical viewport*, so a fixed logical-px panel
  grows as a share of the screen as the slider rises. Size share-of-screen panels as a fraction of
  `get_viewport_rect().size`. Full contract:
  [ui_system § Desktop scaling contract](../02_UI_UX/ui_system.md#desktop-scaling-contract-and-why-fixed-width-panels-drift).
- **A latched boot value.** `UIScaleManager.content_scale_factor` can sit at the `_MIN_SAFE_FACTOR`
  (`0.05`) floor for a frame during boot. Anything that *divides* by it and caches the result latches a
  garbage value forever — the cause of the blank-screen bug (S12-7). Consumers must re-read on
  `ui_scale_changed`, never latch.

---

## Related

- **Constrained by:** [AI_ONBOARDING](../AI_ONBOARDING.md) — the Five Laws this protocol enforces
- **See also:** [ui_system](../02_UI_UX/ui_system.md) — the scaling model · [UIAudit](../02_UI_UX/UIAudit.md) — per-element inventory and layer map · [Diagnostics](Diagnostics.md) — logging and network debugging
- **Live status:** [TODO.md](../TODO.md)
