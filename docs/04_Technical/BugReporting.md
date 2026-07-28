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
updated: 2026-07-28
verified_against_code: 2026-07-28
status: current
---

# Bug Reporting & Feedback

The in-game **Feedback** button captures a screenshot, gathers recent logs and client metadata, and
POSTs a report to the backend (which creates the tracking issue server-side). This is the primary
telemetry channel for the beta, so **availability matters as much as the payload** — see
[Availability](#availability--the-beta-blocker) below.

## Pipeline

```
UserInfoDisplay.ReportBugButton  (Scenes/UserInfoDisplay.tscn:58)
        │  pressed → call_deferred("_on_bug_report_pressed")
        ▼
user_info_display.gd::_on_bug_report_pressed()          (:483)
        │  await RenderingServer.frame_post_draw      ← capture BEFORE any popup appears
        │  viewport texture → Image → save_png_to_buffer()
        │  lazily instantiates BugReportWindow as a child of get_tree().root
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

## Availability — the beta blocker

> [!WARNING]
> **Open, tracked as [TODO.md](../TODO.md) Sprint 12 · S12-5 (2026-07-28).** The requirement for the beta
> is that Feedback is reachable *at any point*. Today it is reachable only from the running main game
> screen — and it is blocked in the two places bugs are most likely to be found.

**The transport is already global. Only the entry point is gated.** Two findings that make the fix
cheaper than it looks:

- `_apply_auth_header()` (`api_calls.gd:458-468`) appends `Authorization` **only when a token exists**,
  so a pre-login submit is a well-formed unauthenticated POST rather than an error.
- `_collect_metadata()` reads the user from `GameStore` **best-effort** — a missing user yields
  `user.id = ""`, not a crash. A pre-login report arrives without user metadata and is otherwise intact.

Blockers to remove:

| # | Blocker | Where |
|---|---|---|
| 1 | **Login.** The button lives inside `MainScreen`, which is `visible = false`, `PROCESS_MODE_DISABLED`, and behind `get_tree().paused = true` until `initial_data_ready`. `LoginScreen` has no feedback affordance. | `game_screen_manager.gd:26-29` |
| 2 | **Paused tree.** `BugReportWindow` is created with the default `PROCESS_MODE_INHERIT`, so it would be frozen even if opened pre-login. Needs `PROCESS_MODE_ALWAYS` — the pattern `LoginScreen` already uses. | `user_info_display.gd:495-501` |
| 3 | **Tutorial.** The overlay gates input with full-screen shield `Control`s at `MOUSE_FILTER_STOP`, and sets itself to `STOP` in HARD mode. Every step blocks the top bar. | `tutorial_overlay.gd:138-157`, `:441`, `:822-825` |
| 4 | **Modals / error dialogs.** Same shape as (3) — anything that dims and captures input hides the button. | — |

Suggested shape: promote the button to a small always-on-top `CanvasLayer` that outranks the tutorial
overlay, add an equivalent on `LoginScreen`, and set `PROCESS_MODE_ALWAYS` on both the button and the
window.

## Key Files

- **Button + capture**: `Scripts/UI/user_info_display.gd` (`_on_bug_report_pressed`)
- **Form + payload**: `Scripts/UI/bug_report_window.gd`
- **Transport**: `Scripts/System/api_calls.gd` (`submit_bug_report`, `POST /bug-report`)
- **Log source**: `Scripts/System/logger.gd` (`get_recent_lines`)

## Connected Systems

- [UI Element Audit § 1 UserInfoDisplay](../02_UI_UX/UIAudit.md) — where the button sits in the top bar
- [Diagnostics & Troubleshooting](Diagnostics.md) — the logger the report drains
- [API Reference](API_Reference.md) — endpoint contracts
