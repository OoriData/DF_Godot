---
type: technical
tags:
  - layer/autoload
  - kind/deep-dive
  - concept/errors
  - status/current
aliases:
  - "Bug Reporting & Feedback"
created: 2026-07-28
updated: 2026-08-06
verified_against_code: 2026-08-06
status: current
---

# Bug Reporting & Feedback

The in-game **Feedback** button captures a screenshot, gathers recent logs and client metadata, and
POSTs a report to the backend (which creates the tracking issue server-side). This is the primary
telemetry channel for the beta, so **availability matters as much as the payload** — see
[Availability](#availability) below.

## Pipeline

**Two entry points, one window.** Both funnel into `GlobalFeedbackOverlay.open_bug_report()`.

```
(a) GlobalFeedbackOverlay floating button          ← available on EVERY screen
    Scripts/UI/global_feedback_overlay.gd
        │  CanvasLayer, layer = 200, PROCESS_MODE_ALWAYS
        │  created by GameScreenManager._ensure_feedback_overlay()  (:40)
        │
(b) UserInfoDisplay.ReportBugButton                ← top bar, main screen only
    Scenes/UserInfoDisplay.tscn:58
        │  pressed → _on_bug_report_pressed()  (user_info_display.gd:499)
        │  delegates via GameScreenManager.get_feedback_overlay()  (:54)
        ▼
GlobalFeedbackOverlay::open_bug_report()                (:88)
        │  await RenderingServer.frame_post_draw      ← capture BEFORE any popup appears
        │  viewport texture → Image → save_png_to_buffer()
        │  lazily instantiates BugReportWindow (PROCESS_MODE_ALWAYS) under get_tree().root
        ▼
BugReportWindow  (Scripts/UI/bug_report_window.gd, extends ResponsiveModalPanel)
        │  user fills Summary / Steps / Context, ticks consent
        │  _build_payload()  (:434)
        ▼
APICalls::submit_bug_report(payload)                    (api_calls.gd:1164)
        │  POST {BASE_URL}/bug-report, JSON body, _apply_auth_header()
        ▼
signal bug_report_submitted  →  BugReportWindow::_on_bug_report_submitted()
```

The screenshot is deliberately taken **before** the window is created — the whole point is to capture
what the player was looking at, not the report form.

> [!NOTE]
> **The top-bar button delegates rather than building its own window.** Before S12-5 it lazily created a
> *separate* `BugReportWindow`; two independently-owned windows meant the one you got depended on which
> button you pressed, and only one of them had `PROCESS_MODE_ALWAYS`. `user_info_display.gd` retains its
> original local path as a **fallback** (guarded by a `push_warning`) for the case where the display is
> hosted outside `GameScreenManager` — reporting a bug must never itself fail.

## Payload

Built by `_build_payload()`. Only `title` / `summary` / `description` / `steps` /
`additional_context` / `consent` are unconditional; the rest are opt-in checkboxes in the form.

| Field | Source | Notes |
|---|---|---|
| `title`, `summary` | Summary field | Submit stays disabled until this is non-empty |
| `description` | Composed markdown | `## Summary` / `## Steps to reproduce` / `## Additional context` |
| `steps`, `additional_context` | Form fields | Also sent raw, alongside the composed description |
| `consent` | Consent checkbox | **Required** — `_update_submit_enabled()` (`:387`) gates on it |
| `screenshot` | `{mime, base64}` | Downscaled to `MAX_SCREENSHOT_DIM = 1600` and dropped entirely above `MAX_SCREENSHOT_BYTES = 1_500_000` |
| `logs` | `Logger.get_recent_lines()` | Capped at 200 lines / 25 000 chars total / 500 chars per line |
| `meta` | `_collect_metadata()` (`:518`) | `client_time_unix`, `os.{name,version}`, `user.id` |
| `client_warnings` | Accumulated | e.g. "Screenshot too large; omitted." |

## Availability

The beta requirement is that Feedback is reachable **at any point** — it was previously reachable only
from the running main game screen, i.e. blocked in the two places bugs are most likely to be found.
**Resolved 2026-07-31 (S12-5)** by `GlobalFeedbackOverlay`. One node closes all four gaps:

| # | Former blocker | How it is answered now |
|---|---|---|
| 1 | **Login.** The button lived inside `MainScreen`, which is `visible = false`, `PROCESS_MODE_DISABLED`, and behind `get_tree().paused = true` until `initial_data_ready` (`game_screen_manager.gd:26-30`). | The overlay is owned by **`GameScreenManager`**, not `MainScreen`, so it is outside everything that gets disabled. **No affordance was added to `LoginScreen`** — a global overlay covers it for free. |
| 2 | **Paused tree.** `BugReportWindow` took the default `PROCESS_MODE_INHERIT`, so it would open frozen. | `PROCESS_MODE_ALWAYS` on the overlay, the button, **and** the lazily-created window. |
| 3 | **Tutorial.** The overlay gates input with full-screen `MOUSE_FILTER_STOP` shields and sets itself to `STOP` in HARD mode (`tutorial_overlay.gd:138-157`, `:441`, `:822-825`). | `layer = 200` beats `ResponsiveModalPanel`'s `100` and the link popups' `101`; the tutorial overlay is parented into MainScreen's onboarding layer, so it draws on canvas layer **0**. Godot delivers GUI input to CanvasLayers in **decreasing layer order**, so the button is hit-tested first. **`tutorial_overlay.gd` needed no change** — no hole was punched in the shields. |
| 4 | **Modals / error dialogs.** Same shape as (3). | Same mechanism as (3). |

**The transport was already global — only the entry point was ever gated.** Both findings still hold and
are why a pre-login report works at all:

- `_apply_auth_header()` (`api_calls.gd:458-468`) appends `Authorization` **only when a token exists**,
  so a pre-login submit is a well-formed unauthenticated POST rather than an error.
- `_collect_metadata()` (`:518`) reads the user from `GameStore` **best-effort** — a missing user yields
  `user.id = ""`, not a crash. A pre-login report arrives without user metadata and is otherwise intact.

> [!CAUTION]
> **Verified structurally, not visually.** Headless testing confirms the overlay constructs, sits at
> `layer = 200` with `PROCESS_MODE_ALWAYS` on both nodes, and lays out to a non-degenerate bottom-left
> rect inside the viewport. It **cannot** prove placement against real chrome (mobile bottom nav bar, the
> map's gear tab) in both orientations, nor that input actually reaches the button through a live tutorial
> shield. Those are the S12-5 device-test rows in [TODO.md](../TODO.md).

> [!NOTE]
> **Two Feedback affordances now exist on the main screen** — the top-bar button and the floating one.
> Deliberate, to avoid changing familiar UI unprompted. Hiding `%ReportBugButton` and letting the
> floating button be the sole entry point is a one-line follow-up if the redundancy reads as clutter.

## Offline submissions

A report submitted with no connectivity has **no response body to parse**, so it used to surface as
`Bug report submit failed (HTTP 0): Unknown error.` Since 2026-07-31 (S13-12), `api_calls.gd` substitutes
the `HTTPRequest.Result` code when `response_code == 0`, which routes the failure through the normal
translation map and yields *"Can't reach the server — check your internet connection."* Codes and the
enum-numbering trap: [ErrorSystem § Network / transport failures](ErrorSystem.md).

## Known issues

Audited end-to-end 2026-08-06, including six months of production reports. Open items are tracked as
**Sprint 14** in [TODO.md](../TODO.md) — `S14-1` … `S14-8`. The two that change how you read this page:

- The GitHub credential the backend posts with is a **personal** fine-grained PAT, not an org-owned one,
  and it expires 2027-02-14 (`S14-1`). Issue *authorship* therefore carries no reporter information —
  the reporter is the `auth_subject` line in the issue body.
- Screenshots are written to a container path with **no volume mount**, so they do not survive a redeploy
  (`S14-2`). A signed screenshot URL returning `404` rather than `403` is this, not a signing failure.

One finding confirms this page rather than correcting it: production contains a report submitted with
**no auth subject at all**, so the pre-login path in [Availability](#availability) is now proven on a
real client, not merely structurally. The placement and hit-testing caveats below still stand.

## Key Files

- **Global entry point**: `Scripts/UI/global_feedback_overlay.gd` (`open_bug_report`, screenshot capture)
- **Overlay owner**: `Scripts/UI/game_screen_manager.gd` (`_ensure_feedback_overlay`, `get_feedback_overlay`)
- **Top-bar button**: `Scripts/UI/user_info_display.gd` (`_on_bug_report_pressed` — delegates, with a local fallback)
- **Form + payload**: `Scripts/UI/bug_report_window.gd`
- **Transport**: `Scripts/System/api_calls.gd` (`submit_bug_report`, `POST /bug-report`)
- **Log source**: `Scripts/System/logger.gd` (`get_recent_lines`)

## Connected Systems

- [UI Element Audit § 1 UserInfoDisplay](../02_UI_UX/UIAudit.md) — where the top-bar button sits
- [Diagnostics & Troubleshooting](Diagnostics.md) — the logger the report drains
- [Error Handling System](ErrorSystem.md) — shares the `HTTP 0` transport path above
- [API Reference](API_Reference.md) — endpoint contracts
- [AI_ONBOARDING § Pro Tips](../AI_ONBOARDING.md) — the paused-tree / `PROCESS_MODE_ALWAYS` rule that
  blocker 2 is an instance of
