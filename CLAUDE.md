# Desolate Frontiers — Agent Entry Point

Godot 4.6 game (GL Compatibility), mobile (portrait + landscape) and desktop, single global content-scale.

## Start here

**Read [docs/AI_ONBOARDING.md](docs/AI_ONBOARDING.md) before writing code.** It defines the Five Laws (UI scaling, unidirectional data, thin panels, diagnostic flags, debounced updates). These override default behavior.

## Routing (task → where to look)

| I need to… | Go to |
|---|---|
| Find the files for a feature/task | [docs/PROJECT_MAP.md](docs/PROJECT_MAP.md) |
| Know current state / known issues / in-flight work | [docs/TODO.md](docs/TODO.md) — items have stable IDs (`BUG-01`, `TD-04`, `S12-4`); cite the ID, don't restate the issue |
| Browse the full doc set / learning path | [docs/DocumentationHome.md](docs/DocumentationHome.md) |
| Understand UI structure (scenes, scripts, layer map) | [docs/02_UI_UX/UIAudit.md](docs/02_UI_UX/UIAudit.md) — *structural reference; live status is in TODO.md* |
| **Which service/autoload owns this?** | [docs/04_Technical/AutoloadOrder.md](docs/04_Technical/AutoloadOrder.md) — all 27 autoloads, real line counts, verified responsibilities. CI-checked against `project.godot` |
| **A layout looks broken / crammed / clipped** | [docs/04_Technical/DebuggingVisualBugs.md](docs/04_Technical/DebuggingVisualBugs.md) — **read before instrumenting.** Pinpoint → reproduce in-editor → measure after animations → rule out structure |
| **A stat reads blank or 0 everywhere** | [docs/04_Technical/DataBoundaries.md](docs/04_Technical/DataBoundaries.md) — likely the JSON-vs-binary seam, i.e. a *third* repo. "Not backend" and "not frontend" can both be true |
| Colors / spacing tokens | `Scripts/System/ui_theme.gd` (`UITheme.*`) is authoritative; rationale in [DesignSystem.md](docs/02_UI_UX/DesignSystem.md) |
| Build / deploy / run | [docs/04_Technical/TechnicalReference.md](docs/04_Technical/TechnicalReference.md), [Deployment.md](docs/04_Technical/Deployment.md) |
| Write or edit a doc | [AI_Guidelines § 6 Documentation Standards](docs/04_Technical/AI_Guidelines.md) — frontmatter, tags, links. **CI-enforced:** run `python3 tools/docs_check.py` |

## Verify, don't trust

Docs are point-in-time snapshots. Status claims and `file:line` references may be stale — **confirm against current code before relying on them.** Code is the source of truth.

Since 2026-07-28 each doc says *how* stale it is. Check its frontmatter:

- `status: current` + a recent `verified_against_code:` — someone actually checked it against the source.
- `status: unverified` — never checked since the doc audit. Most docs. Treat with the usual suspicion.
- `status: drifting` — known wrong. Read the code, then fix the doc.

`python3 tools/docs_check.py --backlog` lists what most needs re-verification. **Docs whose cited source
files were committed *after* the doc was last verified rank first** (known-drifted, not merely old); the
rest follow by how many other docs depend on them. Full structural review:
[docs/DocumentationAudit.md](docs/DocumentationAudit.md).

**If you change code and know its doc is now wrong**, set that doc's frontmatter to `status: drifting`
(and the matching `- status/drifting` tag). Five seconds, and it turns silent rot into a tracked item.
