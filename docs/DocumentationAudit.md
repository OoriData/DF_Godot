---
type: note
tags:
  - kind/audit
  - status/current
aliases:
  - "Documentation Audit"
created: 2026-07-28
updated: 2026-07-28
verified_against_code: 2026-07-28
status: current
---

# Documentation Audit — Knowledge-Graph Review

A structural audit of `docs/` treated as a **knowledge graph** rather than a folder of files: what
connects to what, what is reachable, what is authoritative, and what has silently drifted from the code.

> [!NOTE]
> This doc audits **structure and connectivity**, not prose quality. Content accuracy is the job of the
> [Systems Audit & Research Initiative](TODO.md#systems-audit--research-initiative-next-major-movement);
> this audit's purpose is to give that initiative a **worklist** instead of an open-ended sweep.

> [!IMPORTANT]
> This file's own frontmatter is written in the **proposed** metadata standard from [F4](#f4--no-staleness-metadata)
> (`updated`, `verified_against_code`, `status`, non-singleton tags). It is the reference example.

**Audited:** 2026-07-28 · **Corpus:** 81 markdown files under `docs/` (excluding `.obsidian/`)

> [!TIP]
> **Phases 1 and 2 are complete (2026-07-28).** Dead ends are at **zero** and CI runs `--strict`, so
> they cannot come back. Only Phase 3 (consolidation) remains.
>
> **Phase 1 detail:** `tools/docs_check.py` ships and runs in CI; all 369 baseline
> errors are cleared and the corpus validates clean. The scorecard and findings below are preserved as
> the **original baseline** — each finding carries a **Status** line recording what changed. Live state
> is always `python3 tools/docs_check.py`.
>
> ```bash
> python3 tools/docs_check.py --backlog
> ```
>
> That command prints the drift queue — the concrete worklist this audit existed to produce.

---

## Method

Every number below is reproducible, not impressionistic. The audit resolved every relative markdown link
in every file into a directed graph, then measured reachability, in/out degree, frontmatter fields, tag
frequency, and the existence of every `` `path.gd` ``-style code reference against the working tree.

The checks are mechanical and should become CI — see [Deliverable: `tools/docs_check.py`](#deliverable-toolsdocs_checkpy--shipped).

---

## Scorecard

| Dimension | Measure | Verdict |
|---|---|---|
| **Link integrity** | 0 broken internal links / 81 files | ✅ Excellent |
| **Graph connectivity** | 33 / 81 files (41 %) have **zero outbound links** | ❌ Star topology, not a graph |
| **Explicit relations** | 4 / 81 files have a `Related` / `See also` section | ❌ Edges are incidental |
| **Hub reachability** | 37 / 81 files (46 %) not linked from `DocumentationHome` | ⚠️ Depends which door you enter |
| **Entry points** | 7 competing indexes | ❌ No single contract |
| **Staleness metadata** | 71 / 81 stuck at `created: 2026-05-18/19`; 6 have `updated:` | ❌ Cannot target a drift sweep |
| **Tag utility** | ~70 tags used exactly once (`codex/<filename>`) | ❌ Namespace is inert |
| **Code-reference accuracy** | 4 in-repo paths wrong, 1 nonexistent test file | ⚠️ Low count, high blast radius |
| **Frontmatter coverage** | 77 / 81 have frontmatter | ⚠️ `TODO.md` is one of the gaps |
| **Orphans** | 1 total orphan (`AssetPipeline.md`) | ⚠️ |
| **Unresolved wikilinks** | 11 pointing outside the vault | ⚠️ |

**Overall:** the corpus is *well-written and well-maintained as documents* and *under-built as a graph*.
Nothing here is rot; it is missing connective tissue and missing the metadata that would let anyone
find the rot.

---

## Findings

Ordered by leverage — impact per hour of work.

### F1 — The graph is a star: 41 % of docs are dead ends

**Evidence.** 33 files have zero outbound links, including the most-cited references in the set:
`MenuBase.md` (295 lines, 9 inbound), `Mechanics.md` (10 inbound), `ItemsAndMissions.md` (8 inbound),
`Diagnostics.md` (8 inbound), `Identity.md` (8 inbound). Only **4 files** in the entire corpus have a
`## Related` or `## See also` section. Full list in [Appendix A](#appendix-a--dead-end-docs).

**Why it matters.** Every traversal is leaf → back to hub → down another branch. An agent that lands in
`MenuBase.md` — a plausible first stop for menu work — gets no signal that `ui_system.md` constrains it,
that `MenuManager.md` owns its lifecycle, or that `UIAudit.md` inventories its instances. The Five Laws
are only enforced if the doc you are reading tells you they apply.

**Fix.** A mandatory footer on every doc, with **typed** edges:

```markdown
## Related
- **Constrained by:** [ui_system.md](../02_UI_UX/ui_system.md) — scaling rules that override layout choices here
- **Implemented in:** `Scripts/Menus/menu_base.gd`
- **See also:** [MenuManager.md](MenuManager.md) — owns open/close lifecycle
- **Live status:** [TODO.md](../TODO.md)
```

Typed edges are the difference between a graph you can query and a pile of hyperlinks. Four relation
types cover essentially everything here: `Constrained by`, `Implemented in`, `See also`, `Live status`.

**Effort.** ~2 hours, mechanical. **Priority: 1.**

**Status (2026-07-28): ✅ done.** All 29 remaining dead ends received typed `## Related` footers —
`Constrained by:` / `Implemented in:` / `See also:` / `Live status:`, written per-doc rather than
boilerplate. **`deadend=0`, `orphan=0`**, and CI now runs `--strict`, which fails the build if either
regresses. (Staleness deliberately does *not* fail `--strict`: a build that breaks by the passage of
time would pressure people to fake the fix.)

---

### F2 — The tag namespace is inert

**Evidence.** Of ~120 distinct tags, roughly **70 appear exactly once** and are of the form
`codex/<filename>` — `codex/menubase`, `codex/camera`, `codex/dataflow`, `codex/stepschema`. They encode
the filename, which the filename already encodes.

The only tags with real frequency are `ui` (25), `system` (23), `technical` (20), `ux` (18),
`ui/vendor` (9), `system/map` (8) — and the top four merely restate the parent folder.

**Why it matters.** In Obsidian's graph view, ~70 single-use tags render as leaf nodes attached to one
file apiece: they inflate the graph, dilute the clusters that mean something, and make tag-based queries
useless. Net information contributed by the tag system today ≈ the directory structure.

**Fix.** Delete the `codex/*` singletons. Replace with a small controlled vocabulary chosen for the one
thing directories *cannot* express — cross-cutting concerns:

| Facet | Values |
|---|---|
| `layer/` | `ui` · `service` · `autoload` · `backend` · `protocol` |
| `platform/` | `steam` · `ios` · `android` · `desktop` · `web` |
| `concept/` | `scaling` · `auth` · `binary-protocol` · `onboarding` · `persistence` |
| `status/` | `current` · `drifting` · `archive` |

Keep it to ~20 tags total. A vocabulary nobody can hold in their head gets ignored.

**Effort.** ~1 hour scripted. **Priority: 2** (pairs with F7 — the tags are what make the MOCs work).

**Status (2026-07-28): ✅ done.** All ~70 `codex/*` singletons removed. The faceted vocabulary is
implemented and **enforced** — `APPROVED_TAGS` in `tools/docs_check.py` fails CI on any tag outside it,
so the namespace cannot silently re-fragment.

---

### F3 — Seven entry points, no contract between them

**Evidence.** Competing indexes: `DocumentationHome.md`, `PROJECT_MAP.md`, `AI_ONBOARDING.md`
(§Navigation Map), `ArchitectureIndex.md`, `UISystemIndex.md`, `GameSystemsIndex.md`, and
`TechnicalReference.md` acting as a seventh.

They disagree about their own job:

| Index | Coverage of its section | Note |
|---|---|---|
| `TechnicalReference.md` | 17 / 18 | Flat and near-complete — misses only `AI_Guidelines.md` |
| `ArchitectureIndex.md` | **2 / 4** | Omits `Schema.md` and `Cookbook.md` — the two `DocumentationHome` calls out as most important |
| `GameSystemsIndex.md` | 11 / 23 | Hub-of-hubs: leaves reachable via `MapSystemOverview` / `TutorialSystemOverview` (acceptable, but a *different model* from 04) |
| `UISystemIndex.md` | 5 / 24 | **Declares itself retired** in its own first callout, then routes 20 more lines of traffic |

And `DocumentationHome.md` links **44 of 81** files: 37 docs are invisible from the recommended front
door, including `SignalHub.md`, `NetworkLayer.md`, `AppleAuth.md`, `MultiProviderAuth.md`,
`PushNotifications.md`, and every `VendorPanel/*` sub-doc. Full list in
[Appendix B](#appendix-b--not-reachable-from-documentationhome).

`GameSystemsIndex.md` is the **only** route to `ConvoyService.md`, `RouteService.md`,
`StateManagement.md`, and `SettlementEconomy.md` — and it is not the recommended entry point.

**Why it matters.** Which docs exist, from a reader's perspective, is a function of which door they
walked through. That is the defining failure of a knowledge graph.

**Fix.** Pick one contract and enforce it in CI:

- **Section indexes own completeness.** Every `.md` in a section appears in that section's index, or in a
  sub-overview the index links to (the `GameSystemsIndex` hub-of-hubs model — adopt it everywhere).
- **`DocumentationHome` becomes curated, not exhaustive.** Four section indexes + the cross-cutting MOCs
  from [F7](#f7--cross-cutting-concerns-have-no-home) + the three project-management docs. Stop trying to
  list every file; it will always lose the race.
- **`PROJECT_MAP.md` stays task-oriented** (`I want to do X → go to Y`). It is genuinely a different
  index type and earns its existence — but it should say so at the top.
- **Delete `UISystemIndex.md`** or reduce it to a two-line redirect to `UIAudit.md`. A tombstone that
  still routes traffic is worse than either a live index or no index.
- **Fix `ArchitectureIndex.md`** to list all four architecture docs.

**Effort.** ~2 hours + CI check. **Priority: 1.**

**Status (2026-07-28): ✅ done.** `UIAudit.md` is now the declared `02_UI_UX/` index (its *Related
Documentation* table), and `UISystemIndex.md` is a redirect stub. `ArchitectureIndex` is 4/4,
`TechnicalReference` 18/18, `Glossary` is the `99_Reference/` index. All five indexes carry a callout
naming them as such, and `docs_check.py` enforces coverage with two-hop closure through sub-overviews.

One correction to the table above: measured against `UIAudit.md` (rather than the retired
`UISystemIndex.md`) with two-hop closure allowed, `02_UI_UX/` was only ever missing **one** doc —
`AssetPipeline.md`. The 5/24 figure reflected the retired index, not the section's real reachability.

---

### F4 — No staleness metadata

**Evidence.** 71 of 81 files carry `created: 2026-05-18` or `2026-05-19` — bulk-stamped and never
touched since. Only **6** files have an `updated:` field at all. No file records when it was last
verified against code.

**Why it matters.** `CLAUDE.md` opens with *"Docs are point-in-time snapshots… confirm against current
code before relying on them."* That is a correct and honest warning, and it is also an admission that
**the graph cannot tell you which docs are suspect**. So the cost falls on every reader, every time,
uniformly — including for the many docs that are perfectly current.

It also means the "Doc ⇄ code drift audit" thread in `TODO.md` has no scope: its worklist is "all 81."

**Fix.** Extend frontmatter on every doc:

```yaml
updated: 2026-07-28              # bumped whenever the file changes (pre-commit hook)
verified_against_code: 2026-07-21 # bumped only when someone actually re-read the source
status: current                   # current | drifting | archive
```

`verified_against_code` is the load-bearing field, and it is deliberately **not** the same as `updated` —
editing prose is not verification. Once it exists:

- `verified_against_code` older than ~60 days → the drift-audit backlog, sorted by inbound link count so
  the most-trusted docs get re-verified first.
- `status: drifting` → renders as a warning banner and tells a reader to check code *for this doc
  specifically*, instead of the blanket distrust the project runs on today.

**Effort.** ~2 hours (scripted backfill + hook). **Priority: 1** — this is the finding that converts the
Systems Audit initiative from a sweep into a burn-down.

**Status (2026-07-28): ✅ done.** All 82 docs carry `updated` + `status`; `updated` was backfilled from
each file's **real git history**, not stamped uniformly. `tools/docs_bump_updated.py` maintains it as a
pre-commit hook.

**`verified_against_code` was deliberately NOT backfilled.** Only 7 docs carry it — those `TODO.md`
documents as having been researched against current code on 2026-07-28. Stamping all 82 would have been
a fabrication that destroyed the field's only purpose. The other 75 are `status: unverified`, which is
the honest state and is exactly what `--backlog` ranks.

---

### F5 — Status lives in two places

**Evidence.** `CLAUDE.md` labels `UIAudit.md` *"structural reference; live status is in TODO.md."*
`UISystemIndex.md` routes known-issues to `TODO.md`. But `UIAudit.md` is 741 lines carrying a
**"Known Issues / Gaps"** block under nearly all 14 of its sections, plus "Open Design Questions"
sections. Three documents, three answers to "what is currently broken."

**Why it matters.** Duplicated status is duplicated *staleness*. A fixed bug gets ticked in `TODO.md` and
lives on forever in `UIAudit.md`, where it will be read as current by the next agent.

**Fix.** You already invented the right primitive: the **`S12-n` IDs** in Sprint 12. Generalise it.

- Every tracked issue gets a stable ID: `S<sprint>-<n>` for sprint work, `BUG-<n>`, `TD-<n>` for backlog
  and tech debt.
- `TODO.md` holds the **body** — one entry per ID, the single source of truth.
- `UIAudit.md`'s per-section issue blocks collapse to citations: `> Known issues: BUG-07, S12-4`.

The ID becomes the join key, so either side can be edited without invalidating the other. This is exactly
the discipline that made the `SprintHistory.md` split work.

**Effort.** ~3 hours. **Priority: 2.**

---

### F6 — `TODO.md` is four documents in a trenchcoat

**Evidence.** 493 lines spanning: completed-sprint summary table · Sprint 11 · Sprint 12 · device-test
gate · backlog · polish/UX · tech debt · testing · docs hygiene · UITheme migration status · the
next-initiative plan. It is also **the only doc with no frontmatter** (invisible to every tag and property
query) while being the 8th most-linked file in the corpus.

The Sprint 12 entries are 30–45-line research essays carrying verified root causes with `file:line`
precision — S12-1, S12-4, S12-5 and S12-7 are among the highest-quality technical writing in the repo.

**Why it matters.** That research is **reference material shaped like a checklist**. `S12-4`'s analysis of
`_get_panel_width()` and the `ui.scale` viewport-division mechanism will still be true long after the
checkbox is ticked — at which point, per the established workflow, it gets archived into
`SprintHistory.md` and is effectively lost to anyone who isn't reading sprint archaeology.

**Fix.** Apply the split that already worked once. `TODO.md` keeps: ID · one-line summary · primary file ·
status · link. The research bodies move to the topical doc that owns them, permanently:

| Item | Research body belongs in |
|---|---|
| S12-1, S12-4, Sprint 11 UI-scale slider | `ui_system.md § Desktop scaling contract` — the anchor already exists, and all three already point at it |
| S12-2 | `02_UI_UX/VendorPanel/ResponsiveRefactor.md` |
| S12-7 | `ui_system.md` (mechanism) + `Diagnostics.md` (the `[MAP-RECT-DIAG]` recipe) |
| S12-8 | `03_Systems/GameLifecycle.md` or a new `Onboarding` topic |
| S12-3 | `04_Technical/Identity.md` — partially done already |
| S12-5 | `04_Technical/BugReporting.md` — already done; use it as the template |

Also: **give `TODO.md` frontmatter.**

**Effort.** ~3 hours. **Priority: 2.**

---

### F7 — Cross-cutting concerns have no home

**Evidence.** The `01`–`04` tree is a good taxonomy for *artifacts* and a poor one for *concerns*. Four
major topics are smeared across it with no node representing them:

| Concern | Currently spread across |
|---|---|
| **Scaling / logical pixels** | `ui_system` · `DeviceState` · `UserSettings` · `AI_ONBOARDING` · `UIAudit` · `MechanicsMenu` · `VehicleMenu` · `DocumentationHome` · `TODO` — **9 files restate the law** |
| **Auth** | `Identity` · `AppleAuth` · `MultiProviderAuth` · `Glossary §Identity` — **4 docs, zero index** |
| **Steam / PC** | `Deployment` · `Identity` · `TODO S12-*` · `tools/steam_disable.sh` header comment |
| **Cross-repo data** | `DF_Lib` · `MapSystem/Data` · `API_Reference` · `Schema` |

**Why it matters.** These are exactly the questions that get asked ("how does scaling work?", "what
happens on first Steam launch?") and exactly the ones with no answer node. The reader has to already know
the answer to find the answer.

**Fix.** Add a small `00_Topics/` folder of **maps of content** — ~30 lines each, links plus one
orientation paragraph, no duplicated content:

- `00_Topics/Scaling.md` — the single canonical statement of the Law of Logical Pixels; all 9 restatements
  become links or marked mirrors (see [F8](#f8--duplicated-law-text-drifts-silently))
- `00_Topics/Auth.md` — the missing index over the four auth docs
- `00_Topics/SteamAndPC.md` — desktop-only behaviour, export quirks, the `ui.scale` family of bugs
- `00_Topics/DataBoundaries.md` — see below

MOCs are the structure that converts a directory tree into a graph, and they are where the cross-cutting
tags from [F2](#f2--the-tag-namespace-is-inert) earn their keep.

**`DataBoundaries.md` deserves special emphasis.** Three repos meet at the `/map` binary format
(`DF_Godot` ⇄ `desolate_frontiers` ⇄ `df_lib`), and that seam produced the project's most expensive bug
class — a field renamed in the backend leaving the JSON API correct while the binary packer silently
packs `0`. `DF_Lib.md` explains the *mechanism* very well. Nothing documents *which fields cross which
boundary in which encoding*, which is what you actually need when a stat reads blank.

**Effort.** ~4 hours. **Priority: 2.**

---

### F8 — Duplicated law text drifts silently

**Evidence.** The scaling law is restated in **9 files**; the "Jerry Cans ≠ Water Jerry Cans" gotcha in
~4; the DF_Lib binary-serializer warning in 3+ (`AI_ONBOARDING`, `DocumentationHome`, `DF_Lib`,
`MapSystem/Data`).

This has already cost you: `TODO.md` records that `ui_system.md` claimed `ui.scale` defaults to **1.4**
when the real default is **1.0** — a divergence caught by accident during unrelated S12-4 research.

**Why it matters.** *n* copies drift at *n* different rates, and a reader cannot tell which copy is
authoritative. Deliberate repetition is good pedagogy (onboarding *should* state the law inline) — but
unmarked repetition is a correctness hazard.

**Fix.** One canonical anchor per law. Everything else either links to it, or — where inline repetition is
deliberate — marks itself as a mirror:

```markdown
> [!NOTE]
> Mirror of [Scaling § The Law of Logical Pixels](../00_Topics/Scaling.md#law) — **that page wins on conflict.**
```

Two words of provenance eliminate the entire class of "which one is right?"

**Effort.** ~2 hours. **Priority: 3.**

---

### F9 — Mixed link syntax, with 11 unresolved wikilinks

**Evidence.** The corpus uses relative markdown links throughout, except for 13 `[[wikilinks]]`:

- **2 resolve** inside the vault: `[[Camera]]` (`MapSystem/Rendering.md`), `[[SettlementOverlay]]`
  (`MapSystem/Visuals.md`)
- **11 do not**: `[[reference_vendor_efficiency_binary_serializer]]`,
  `[[reference_backend_repo_and_stale_dumps]]`, `[[project_font_scale_migration]]`,
  `[[reference_jerry_cans_vs_water]]`, `[[reference_tutorial_steps_in_code]]`,
  `[[reference_tutorial_resume_step_zero]]`, `[[reference_convoy_focus_stale_snapshot]]`,
  `[[reference_tutorial_overlay_panel_positioning]]` — in `TODO.md` and `SprintHistory.md`

The 11 point at **agent-memory notes stored outside `docs/`**, so Obsidian renders them as permanently
unresolved and no human or agent reading the repo can follow them.

**Why it matters.** 11 phantom nodes in the graph, and 11 promises of information the repo cannot deliver.

**Fix.** Decide whether agent memory is part of the vault.
- **If not** (recommended — memory is per-user, docs are shared): convert to prose, or promote the handful
  that are genuinely shared project knowledge into real docs. `reference_vendor_efficiency_binary_serializer`
  in particular is already 90 % duplicated into `DF_Lib.md`'s case study — cite that instead.
- **Either way:** standardise on relative markdown links, and convert the 2 working wikilinks for
  consistency (they break outside Obsidian — e.g. on GitHub).

**Effort.** ~30 min. **Priority: 3.**

**Status (2026-07-28): ✅ done.** The 2 in-vault wikilinks are markdown links (which also closed a
`SettlementOverlay` index gap). The 11 memory references became prose — three now link to the in-repo
doc covering the same ground (`DF_Lib` case study, `data_dumps/README`, the tutorial content gotcha)
with the memory slug retained as an inline note. Zero `[[…]]` remain in `docs/`.

---

### F10 — Concrete code-reference drift

Small in count, but these are the failures that waste an agent's first five minutes:

<!-- docs-check:ignore-codepaths start -->

| Doc | Claims | Actual |
|---|---|---|
| `02_UI_UX/ConvoyMenu.md` | `Scenes/Menus/ConvoyMenu.tscn` | `Scenes/ConvoyMenu.tscn` |
| `02_UI_UX/ConvoyCargoMenu.md` | `Scenes/Menus/ConvoyCargoMenu.tscn` | `Scenes/ConvoyCargoMenu.tscn` |
| `02_UI_UX/WarehouseMenu.md` | `Scenes/Menus/WarehouseMenu.tscn` | `Scenes/WarehouseMenu.tscn` |
| `04_Technical/ErrorSystem.md` | `Scenes/UI/ErrorDialog.tscn` | `Scenes/ErrorDialog.tscn` |
| `02_UI_UX/VendorPanel/Transactions.md` | `Scripts/System/Utils/price_util.gd` | `Scripts/Menus/VendorPanel/price_util.gd` |
| `04_Technical/AppleAuth.md` | `Tests/test_apple_auth.gd` | does not exist |

<!-- docs-check:ignore-codepaths end -->

Cross-repo references (`df_lib/pylib/map_struct.py`, `engine/routers/map_api.py`) are expected to be
unresolvable here and are **not** defects — but they should be visually marked as external so the checker
and the reader both skip them.

Also in this bucket:
- **`02_UI_UX/AssetPipeline.md` is a total orphan** — 0 inbound, 0 outbound, absent from `DocumentationHome`
  and from every index. Either wire it in or archive it.
- **4 files lack frontmatter:** `TODO.md`, `03_Systems/MapSystem/MapMenuSystem.md`,
  `99_Reference/data_dumps/README.md`, `99_Reference/data_dumps/Map_example.md`.

**Effort.** ~30 min. **Priority: 1** (trivial, and CI stops recurrence permanently).

**Status (2026-07-28): ✅ done.** All 6 paths corrected; frontmatter added to the 4 files lacking it
(`created:` backdated from git, not stamped as today); `AssetPipeline.md` wired into the `02_UI_UX`
index, clearing the last orphan. Two anchors cited by `PROJECT_MAP.md` and `UISystemIndex.md`
(`#adding-a-new-menu`, `#layer-map-z-order-top-to-bottom`) **never resolved** — the targets were bold
text and an unlabelled code block, not headings. Both are now real headings. That defect predates this
audit and was found by the checker, not by reading.

---

### F11 — Autoload coverage is inverse to importance

**Evidence.** 27 autoloads registered in `project.godot`. `AutoloadOrder.md` is **39 lines**. Doc mentions
per autoload:

| Mentions | Autoloads |
|---|---|
| 1 doc | `ui_theme` · `vendor_service` · `convoy_selection_service` · `push_notification_manager` · `google_auth_service` |
| 2 docs | `map_settings_service` · `steam_manager` · `auto_sell_service` · `user_service` |

`ui_theme.gd` is the standout: `CLAUDE.md` names it **authoritative** for all colors and spacing tokens,
and it appears in exactly **one** doc.

**Why it matters.** "Which service owns this?" is the single most common orientation question, and today
it is a repo-wide grep rather than a lookup.

**Fix.** An **Autoload Register** in `04_Technical/AutoloadOrder.md` — one table,
`name → script → responsibility → owning doc → init order`, **complete by construction** and CI-checked
against `project.godot`'s `[autoload]` block so it cannot silently fall behind.

For an agent, this single table is plausibly worth more than any three existing docs.

**Effort.** ~2 hours. **Priority: 2.**

**Status (2026-07-28): ✅ done.** [Autoload Register](04_Technical/AutoloadOrder.md) — all 27 autoloads
with real line counts and code-verified responsibilities, CI-checked against `project.godot`. Building
it is what exposed the confabulated docs in [Appendix D](#appendix-d--confabulated-docs-removed-2026-07-28):
writing accurate "Owns" cells meant reading each service, and five did not match their own doc.

---

### F12 — `AI_ONBOARDING.md` is accreting

**Evidence.** The Five Laws are the strongest thing in the corpus — crisp, enforceable, correctly scoped
to override default behaviour. But the surrounding sections have become a landing strip:

- **Pro Tips** now includes an 8-line note on iPhone deploy dropdowns and the GodotSteam iOS library — a
  build-tooling quirk sitting inside an architectural-laws document.
- **Debugging a Visual/Layout Bug** is a genuine 4-step methodology with a real incident behind it. It is
  buried as a trailing section of an onboarding doc, so nothing can cite it — and `DocumentationHome.md`
  consequently *restates it* in a `[!WARNING]` callout, creating a copy with no canonical home.

**Why it matters.** The onboarding doc is the one file guaranteed to be read. Every line that isn't a law
competes with the laws for attention, and length is the enemy of compliance.

**Fix.**
- `AI_ONBOARDING.md` = **laws + visual standards + routing table**, with a defended length cap (~80 lines,
  roughly where it sits now).
- Promote the debugging protocol to `04_Technical/DebuggingVisualBugs.md` so `UIAudit`, `ui_system`,
  `Diagnostics` and TODO items can all cite it; `DocumentationHome`'s callout becomes a link.
- Each Pro Tip moves to its topical doc (iPhone/Steam → `00_Topics/SteamAndPC.md`; Jerry Cans → the
  Tutorial docs, where it already lives; DF_Lib → `00_Topics/DataBoundaries.md`), leaving a one-line
  pointer.

**Effort.** ~2 hours. **Priority: 3.**

---

## Remediation plan

### ✅ Phase 1 — Foundations (complete 2026-07-28)

1. ✅ **F4** — `updated` + `status` backfilled across all 82 files from real git history;
   `verified_against_code` set only where evidence exists (7 docs); pre-commit hook shipped
   (`tools/docs_bump_updated.py`).
2. ✅ **F10** — 6 wrong code paths fixed, frontmatter added to the 4 files lacking it, `AssetPipeline.md`
   wired into the `02_UI_UX` index, and 2 long-broken heading anchors repaired.
3. ✅ **F3** — `ArchitectureIndex` 4/4, `TechnicalReference` 18/18, `Glossary` declared the `99_Reference`
   index, `UIAudit` declared the `02_UI_UX` index, `UISystemIndex` retired to a stub.
4. ✅ **F2** — tag vocabulary migrated and enforced (pulled forward from Phase 2; it was one script pass
   with the F4 backfill).
5. ✅ **F9** — all `[[wikilinks]]` resolved (pulled forward; trivial once the checker flagged them).
6. ✅ **Deliverable** — `tools/docs_check.py` + `.github/workflows/docs-check.yml`.

**Exit criterion met:** 369 baseline errors → **0**. `--backlog` emits the drift queue, ranked by inbound
link count.

### ✅ Phase 2 — Connectivity (complete 2026-07-28)

7. ✅ **F1** — typed `## Related` footers on all 29 dead ends. `deadend=0`, `orphan=0`.
8. ✅ **F11** — [Autoload Register](04_Technical/AutoloadOrder.md) built from source: all 27 autoloads,
   real line counts, verified responsibilities, owning doc. **CI-enforced** against `project.godot`'s
   `[autoload]` block, so it cannot fall behind.
9. ✅ **Confabulated-doc cleanup** (unplanned — surfaced by F11). Four service stubs describing logic
   that does not exist were deleted and folded into the Register; `TerrainMath.md` was rewritten from
   source. See [Appendix D](#appendix-d--confabulated-docs-removed-2026-07-28).
10. ⏳ **F7** — the four MOCs. **Deferred to Phase 3**: the Register absorbed the "which service owns
    this?" need that motivated half of them, so the remaining value is concentrated in
    `DataBoundaries.md`.

**Exit criterion met:** zero dead ends, zero orphans, `--strict` enabled in CI.

### Phase 3 — Consolidation (~8 h, stops future drift)

10. **F7** — `DataBoundaries.md` (highest remaining value), then `Scaling.md` / `Auth.md` / `SteamAndPC.md`.
11. **F5** — issue IDs as the join key; `UIAudit` issue blocks → citations.
12. **F6** — split `TODO.md`; research bodies migrate to topical docs.
13. **F8** — canonical anchors + marked mirrors for the 9 scaling restatements.
14. **F12** — trim `AI_ONBOARDING`; promote the debugging protocol.

**Exit criterion:** exactly one canonical location per law and per issue.

---

## Deliverable: `tools/docs_check.py` ✅ shipped

Runs in CI via [`.github/workflows/docs-check.yml`](../.github/workflows/docs-check.yml) on any push or
PR touching `docs/`. Errors fail the build; warnings are reported.

```bash
python3 tools/docs_check.py              # errors fail (exit 1)
python3 tools/docs_check.py --warnings   # list dead ends and stale docs in full
python3 tools/docs_check.py --backlog    # the drift queue, most-trusted docs first
python3 tools/docs_check.py --strict     # warnings fail too (target state after Phase 2)
```

| Check | Level | Fails when |
|---|---|---|
| **Link resolution** | error | a relative `.md` link does not resolve |
| **Anchors** | error | a `#fragment` does not match a heading in the target |
| **Code paths** | error | a `` `Scripts/…` `` / `` `Scenes/…` `` reference is not in the tree (external repos allowlisted; deliberate citations suppressed with `<!-- docs-check:ignore-codepaths start/end -->`) |
| **Frontmatter** | error | any file lacks `type` / `updated` / `status`, or `status` is outside the vocabulary |
| **Tag vocabulary** | error | a tag is used that is not in `APPROVED_TAGS` |
| **Index coverage** | error | a doc is unreachable from its section index, including two-hop through a sub-overview |
| **Dead ends** | warn | a doc has zero outbound links |
| **Orphans** | warn | a doc has zero inbound links |
| **Staleness** | warn | `verified_against_code` absent or older than 90 days |

Every one of these caught a real defect during this audit, so none are speculative. The anchor check
found two broken citations that had **never** resolved and that manual review had missed twice.

### Companion: `tools/docs_bump_updated.py`

Pre-commit hook. Bumps `updated:` on staged docs and runs the checker, blocking the commit on error.

```bash
ln -sf ../../tools/docs_bump_updated.py .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

It deliberately does **not** touch `verified_against_code` — automating that field would destroy the
only signal it carries.

---

## Appendix A — Dead-end docs

> [!NOTE]
> **Baseline snapshot (2026-07-28).** Live list: `python3 tools/docs_check.py --warnings`.
> Now 31 — `MapSystem/Rendering.md` and `MapSystem/Visuals.md` gained outbound links during the F9 fix.

33 files with zero outbound links, sorted by inbound count (fix the most-trusted first):

| Inbound | Lines | File |
|---|---|---|
| 10 | 93 | `03_Systems/Mechanics.md` |
| 9 | 295 | `02_UI_UX/MenuBase.md` |
| 8 | 135 | `03_Systems/ItemsAndMissions.md` |
| 8 | 93 | `04_Technical/Diagnostics.md` |
| 8 | 111 | `04_Technical/Identity.md` |
| 7 | 119 | `02_UI_UX/MenuManager.md` |
| 4 | 100 | `01_Architecture/DataFlow.md` |
| 4 | 100 | `02_UI_UX/DesignSystem.md` |
| 4 | 58 | `02_UI_UX/DeviceState.md` |
| 4 | 110 | `03_Systems/GameLifecycle.md` |
| 4 | 90 | `04_Technical/API_Reference.md` |
| 4 | 39 | `04_Technical/AutoloadOrder.md` |
| 3 | 92 | `02_UI_UX/VendorPanel/Transactions.md` |
| 3 | 62 | `03_Systems/TutorialSystem/StepSchema.md` |
| 2 | 53 | `02_UI_UX/SceneArchitecture.md` |
| 2 | 39 | `02_UI_UX/VendorPanel/Checklist.md` |
| 2 | 55 | `02_UI_UX/VendorPanel/ConvoyStats.md` |
| 2 | 53 | `02_UI_UX/VendorPanel/Lifecycle.md` |
| 2 | 46 | `02_UI_UX/VendorPanel/Mechanics.md` |
| 2 | 54 | `02_UI_UX/VendorPanel/UI_Inspector.md` |
| 2 | 158 | `03_Systems/MapSystem/MapMenuSystem.md` |
| 2 | 59 | `03_Systems/MapSystem/Rendering.md` |
| 2 | 64 | `03_Systems/TutorialSystem/Controllers.md` |
| 2 | 77 | `04_Technical/AI_Guidelines.md` |
| 2 | 308 | `04_Technical/AppleAuth.md` |
| 2 | 95 | `04_Technical/CargoDestinationButtonImplementation.md` |
| 2 | 86 | `04_Technical/Dependencies.md` |
| 2 | 157 | `04_Technical/Deployment.md` |
| 2 | 205 | `04_Technical/SignalHub.md` |
| 1 | 80 | `03_Systems/MapSystem/Camera.md` |
| 1 | 49 | `03_Systems/MapSystem/Interactions.md` |
| 1 | 61 | `03_Systems/MapSystem/Visuals.md` |
| **0** | 63 | `02_UI_UX/AssetPipeline.md` ← **total orphan** |

---

## Appendix B — Not reachable from `DocumentationHome`

> [!NOTE]
> **Baseline snapshot (2026-07-28).** Under the index contract adopted in F3, `DocumentationHome` is
> curated by design — completeness is the *section indexes'* job and is CI-enforced. This list is
> retained as evidence for the finding, not as a worklist.

37 files. Those marked ✓ are reachable in two hops via a sub-overview (acceptable under the hub-of-hubs
model); the rest are only reachable via a non-recommended index, or not at all.

**01_Architecture** — `ArchitectureIndex.md`

**02_UI_UX** — `AssetPipeline.md` (orphan) · `JourneyMenu.md` · `MechanicsMenu.md` · `SettlementMenu.md` ·
`UISystemIndex.md` · `VehicleMenu.md` · ✓`VendorPanel/{Checklist, ConvoyStats, Data, Lifecycle, Mechanics,
ResponsiveRefactor, Transactions, UI_Inspector}.md`

**03_Systems** — `ConvoyService.md` · `MechanicsService.md` · `RouteService.md` · `SettlementEconomy.md` ·
`StateManagement.md` (all five: `GameSystemsIndex.md` only) · ✓`MapSystem/{Camera, Data, Interactions,
Rendering, TerrainMath, Visuals}.md` · ✓`TutorialSystem/{Architecture, Controllers, StepSchema,
TargetResolution}.md`

**04_Technical** — `AppleAuth.md` · `CargoDestinationButtonImplementation.md` · `MultiProviderAuth.md` ·
`NetworkLayer.md` · `PushNotifications.md` · `SignalHub.md`

**99_Reference** — `data_dumps/Map_example.md`

---

## Appendix C — Section index gaps

> [!NOTE]
> **Baseline snapshot (2026-07-28) — all rows below are now resolved.** CI enforces coverage; see
> [F3 Status](#f3--seven-entry-points-no-contract-between-them).

| Index | Covers | Missing |
|---|---|---|
| `01_Architecture/ArchitectureIndex.md` | 2 / 4 | `Schema.md`, `Cookbook.md` |
| `02_UI_UX/UISystemIndex.md` | 5 / 24 | 19 files — index is self-declared retired |
| `03_Systems/GameSystemsIndex.md` | 11 / 23 | 12 leaves, all covered by their sub-overview ✓ |
| `04_Technical/TechnicalReference.md` | 17 / 18 | `AI_Guidelines.md` |

---

## Appendix D — Confabulated docs, removed 2026-07-28

A category the original audit did not anticipate: docs that were **never accurate**, as distinct from
docs that drifted. They were short, confident, generically structured ("Core Features" / "Core
Responsibilities"), carried no `file:line` references, and described plausible systems that do not
exist. Because they read authoritatively, they are more dangerous than an obviously stale page.

Found while writing the [Autoload Register](04_Technical/AutoloadOrder.md) — producing an accurate
"Owns" column meant reading all 27 services, and five did not match their own doc.

| Doc | Asserted | Verified reality | Action |
|---|---|---|---|
| `03_Systems/RouteService.md` | "local navigation mesh"; ETA / hazard / consumption maths | `route_service.gd` is **59 lines**, 6 functions, pure API passthrough — all routing maths is server-side | deleted → Register |
| `03_Systems/MechanicsService.md` | "durability degradation and repair logic" | no durability, degrade, or repair code in `mechanics_service.gd` | deleted → Register |
| `03_Systems/ConvoyService.md` | "renaming, disbanding" convoys | neither operation exists | deleted → Register |
| `03_Systems/SettlementEconomy.md` | "`VendorService` orchestrates liquid/bulk fuel transfers" | no fuel or bulk logic in `vendor_service.gd` | deleted → Register |
| `03_Systems/MapSystem/TerrainMath.md` | a **hex** grid, **Fog of War**, client-side terrain speed/fuel multipliers | square `TileMapLayer`; no fog system anywhere in `Scripts/`; multipliers are server-side | **rewritten** — the tile→pixel conversion it also described *is* real and load-bearing in three files |

**Deliberately not generalised.** Same-shaped docs were checked and found **accurate**:
`04_Technical/NetworkLayer.md` (`_request_queue`, `_parallel_pool`, `DEBUG_BYPASS_TOKEN`, `app_config.cfg`
all verified) and `03_Systems/TutorialSystem/TargetResolution.md` (HARD/SOFT gating is real). The
pattern is narrow: docs describing concrete mechanisms someone built are true; four of the five
*service summaries* were invented. Do not treat brevity alone as evidence of confabulation.

**Why delete rather than tombstone.** Unlike `UISystemIndex.md` — a known entry point with external
references, kept as a stub — these four were obscure, thin, and wrong. Their inbound links were
redirected to the Register, git history preserves them, and a tombstone would have implied the content
was once correct.

**Detection heuristic for the Phase 3 sweep:** short doc · no `file:line` · no code fences · generic
section headings · `created` in the original 2026-05-18/19 bulk. That profile matched 14 docs; 5 were
confabulated, 2 verified accurate, and the rest are indexes or legitimately brief.

---

## Related

- **Drives:** [TODO.md § Systems Audit & Research Initiative](TODO.md#systems-audit--research-initiative-next-major-movement) — this audit is that initiative's doc-side worklist
- **Audits:** [DocumentationHome.md](DocumentationHome.md) · [AI_ONBOARDING.md](AI_ONBOARDING.md) · [PROJECT_MAP.md](PROJECT_MAP.md)
- **See also:** [SprintHistory.md](SprintHistory.md) — the precedent for the [F6](#f6--todomd-is-four-documents-in-a-trenchcoat) split
