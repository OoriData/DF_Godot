---
type: technical
tags:
  - technical
  - codex/auth
aliases:
  - "Multi-Provider Auth Handshakes"
created: 2026-05-19
---

# Multi-Provider Authentication

*Desolate Frontiers* supports secure cross-platform identity management across Steam, iOS, and Android ecosystems.

## Core Features
1. **Google Sign-In (`GodotGoogleSignIn`)**:
   - Manages asynchronous JWT retrieval on Android devices.
2. **Steam Ticket Authentication (`SteamManager`)**:
   - Interfaces directly with the Steamworks API to validate sessions without requiring passwords.
3. **Account Merging & Conflicts**:
   - Handles HTTP 409 Conflict responses when linking accounts.
   - Parses the `merge_token` to preview conflict resolutions, allowing players to definitively link multiple providers to one unified User ID.

## Key Files
- **Google Service**: `Scripts/System/Services/google_auth_service.gd`
- **Steam Manager**: `Scripts/System/steam_manager.gd`

## Connected Systems
- [Identity Overview](Identity.md)
- [Apple Auth](AppleAuth.md)
