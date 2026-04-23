# Changelog

All notable changes to Desolate Frontiers will be documented in this file.

## [0.3.19]

### Fixed
- iOS push notifications: migrated from broken standalone APN plugin to GodotApplePlugins GDExtension
- CI/CD: Fixed Fastlane match auth (SSH → HTTPS) for macOS/iOS builds
- CI/CD: Updated macOS runners to `macos-26` for Xcode 26 / iOS 26 SDK compliance
- CI/CD: Restored decoupled deployment architecture after merge clobber

### Changed
- Push notification manager now uses `PushNotifications` singleton (GodotApplePlugins) instead of legacy `APN` singleton
