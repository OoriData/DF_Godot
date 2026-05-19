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
   - `UI_scale_manager` and `TextScale` bind dynamically to configuration changes, normalizing resolutions and fonts across disparate device screen sizes.

## Key Files
- **Settings Store**: `Scripts/System/settings_manager.gd`
- **Text Scalar**: `Scripts/System/text_scale.gd`
- **UI Scalar**: `Scripts/UI/UI_scale_manager.gd`

## Connected Systems
- [Diagnostics & Settings](Diagnostics.md)
