# Changelog

All notable changes to Desolate Frontiers will be documented in this file.

## [0.3.21]

### Added
- Integrated responsive font scaling for convoy menu item cards (portrait/mobile support).
- Enhanced UI layout management in `main_screen.gd` using unified `_refresh_menu_layout` logic.

### Changed
- Refined cargo physics scaling: Adjusted 2D size calculation to better reflect cargo volume in physics simulations.
- Updated vehicle setup: Improved trailer attachment logic to look for parts in the `trailer` slot.
- Temporarily disabled trailers to stabilize current build for commit.
- Standardized UI scaling logic to explicitly handle portrait vs landscape orientations.
- **Reconciled Oori Visual Identity Overhaul**: Successfully merged major UI branding changes across all main menus (`convoy_menu.gd`, `convoy_cargo_menu.gd`, `settings_menu.gd`, etc.).
- Standardized the use of `TextureRect` tiled backgrounds (`res://Assets/Themes/Oori Backround.png`) and `StyleBoxEmpty` overrides across the menu system.

### Fixed
- Fixed missing function and variable declarations (`background_margin`, `_on_viewport_size_changed`, `_update_layout`) in `convoy_menu.gd` and `convoy_cargo_menu.gd`.
- Enabled `unique_name_in_owner` for `MenuContainer` in `MainScreen.tscn` to resolve runtime null reference errors.
- Removed redundant calls to missing styling functions in `convoy_list_panel.gd`.
- Restored project stability and successful headless initialization.
## [0.3.20]

### Fixed
- iOS local builds: Restored "One-Click Deploy" functionality by disabling the Push Notifications plugin and entitlements in the checked-in `export_presets.cfg`.
- CI/CD: Updated the build pipeline to dynamically re-enable the `PushNotifications` plugin and production entitlements at runtime.
- iOS local builds: Cleared hardcoded signing fields to allow native "Automatic Signing" on local developer machines.
- macOS builds: Set Preset 0 ("macOS") to Ad-hoc signing by default, fixing local builds on developer machines.
- CI/CD: Restored macOS build stability. Proper distribution signing for non-App Store builds is pending manual certificate seeding in the Match repository.

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
