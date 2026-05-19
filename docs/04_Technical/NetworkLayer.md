---
type: technical
tags:
  - technical
  - codex/network
aliases:
  - "Network Queue & Auth Bypass"
created: 2026-05-19
---

# Network Queue & Auth Bypass

The `APICalls` singleton handles all HTTP requests in *Desolate Frontiers*. It implements a robust queuing system and environment-specific authentication flows.

## Core Features
1. **Request Queueing & Watchdogs**: 
   - Requests (especially `PATCH` mutations) are serialized in `_request_queue`.
   - Parallel pools (`_parallel_pool`) are used for non-blocking GET requests.
   - A watchdog timer automatically clears stalled requests to prevent infinite UI loading states.
2. **Environment & Auth Bypass**:
   - Driven by `app_config.cfg` and the `active_env` variable.
   - In `dev` mode, the client accepts `DEBUG_BYPASS_TOKEN` allowing seamless offline/local mobile testing without navigating OAuth flows.
   - Production (`prod`) mode explicitly rejects these tokens, ensuring secure JWT validation.

## Key Files
- **Script**: `Scripts/System/api_calls.gd`
- **Config**: `app_config.cfg`

## Connected Systems
- [API Reference](API_Reference.md)
- [Identity](Identity.md)
