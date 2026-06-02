---
type: technical
tags:
  - technical
  - codex/settings
aliases:
  - "User Settings & Preferences"
created: 2026-05-19
---

# User Settings & Preferences

The Settings system acts as the local storage mechanism for non-gameplay configurations, persisting visual, audio, and accessibility choices.

## Core Features
1. **SettingsManager**:
   - Reads and writes to `user://settings.cfg`.
   - Tracks audio levels, UI interaction flags, tutorial completions, and cargo sorting metrics.
2. **Scale Normalization**:
   - `UI_scale_manager` binds to the `ui.scale` setting (desktop manual zoom). It sets `content_scale_factor` — a pure multiplier that scales the entire canvas (fonts, layout, icons) together. There is no separate font-scaling system.

## Key Files
- **Settings Store**: `Scripts/System/settings_manager.gd`
- **UI Scalar**: `Scripts/UI/UI_scale_manager.gd`

## Connected Systems
- [Diagnostics & Settings](Diagnostics.md)
