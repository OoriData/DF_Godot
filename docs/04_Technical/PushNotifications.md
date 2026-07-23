---
type: technical
tags:
  - technical
  - codex/push-notifications
aliases:
  - "Push Notification Manager"
created: 2026-05-19
---

# Push Notification Manager

The `PushNotificationManager` autoload manages OS-level notifications and deep-linking into the game state.

## Core Features
1. **Cross-Platform Initialization**:
   - Integrates with iOS (`PushNotifications` singleton) and Android (`GodotFirebaseCloudMessaging`).
   - Retrieves device tokens and registers them with the backend (`APICalls.register_push_token`).
2. **In-Game Toasts & Deep-Linking**:
   - If the app is open when a payload arrives, it renders a custom `PushToast.tscn`.
   - Emits `push_dialogue_requested` to trigger deep-linking (e.g., automatically panning the camera or opening a specific settlement menu based on the `dialogue_id`).

## Key Files
- **Script**: `Scripts/System/Services/push_notification_manager.gd`

## Connected Systems
- [Autoload Order](AutoloadOrder.md)
