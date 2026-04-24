# Changelog

All notable changes to Desolate Frontiers will be documented in this file.

## [0.3.20]

### Fixed
- iOS local builds: Restored "One-Click Deploy" functionality by disabling the Push Notifications plugin and entitlements in the checked-in `export_presets.cfg`.
- CI/CD: Updated the build pipeline to dynamically re-enable the `PushNotifications` plugin and production entitlements at runtime, ensuring no impact on TestFlight releases.
- iOS local builds: Cleared hardcoded signing fields to allow native "Automatic Signing" on local developer machines.

## [0.3.19]

### Added
- Android push notifications via Firebase Cloud Messaging (FCM) using Godot 4.2+ v2 plugin architecture
- Custom `GodotFirebaseCloudMessaging` Android plugin with `EditorExportPlugin` integration
- Android 13+ POST_NOTIFICATIONS runtime permission support

### Fixed
- iOS push notifications: migrated from broken standalone APN plugin to GodotApplePlugins GDExtension
- CI/CD: Fixed Fastlane match auth (SSH → HTTPS) for macOS/iOS builds
- CI/CD: Updated macOS runners to `macos-26` for Xcode 26 / iOS 26 SDK compliance
- CI/CD: Restored decoupled deployment architecture after merge clobber
- CI/CD: Android build workflow now preserves custom Gradle files during template extraction
- Fixed `SceneTreeTimer.process_mode` crash in `api_calls.gd`
- Fixed `generate_tiles.gd` attempting to write to read-only `res://` on exported Android builds
- Fixed Android push token registration failing when using cached credentials
- Bypassed Godot 4.x `has_method()` bug that prevented Android Firebase plugins from initializing

### Changed
- Push notification manager now uses `GodotFirebaseCloudMessaging` singleton for Android (replaces dead Firebase/FirebaseApp code)
- Push notification manager now uses `PushNotifications` singleton (GodotApplePlugins) instead of legacy `APN` singleton
