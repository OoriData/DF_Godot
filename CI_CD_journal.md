# CI/CD Adaptation Journal

## 2026-02-18 - Initial Adaptation
- Started adapting CI/CD workflows from Spellist to Desolate Frontiers.
- Analyzed `project.godot` and `export_presets.cfg` to map preset names and bundle IDs.
- Identified the following preset mappings:
    - Web: "Web" (Preset 8)
    - Android: "Android (Play Store)" (Preset 6)
    - iOS: "iOS" (Preset 7)
    - macOS: "macOS (App Store)" (Preset 1)
    - Windows (Steam): "Windows Desktop (x86)" (Preset 2)
    - macOS (Steam): "macOS" (Preset 0)

### Changes Implemented
- **`build-and-release.yml`**: Updated platform list to include `steam` by default.
- **`_build-web.yml`**: Renamed export preset to "Web". Verified `webapp-hosting` branch deployment.
- **`_build-google-play.yml`**:
    - Updated package name to `com.ooridata.desolate_frontiers`.
    - Updated output filename to `Desolate_Frontiers.aab`.
- **`_build-ios-appstore.yml`**:
    - Updated App Identifier to `com.ooridata.desolate-frontiers`.
    - Default profile logic updated to match new bundle ID.
    - Updated output filename to `Desolate_Frontiers.ipa`.
- **`_build-macos-appstore.yml`**:
    - Updated Provisioning Profile to `Oori_Data_Desolate_Frontiers_Mac_App_Store.provisionprofile`.
    - Updated output filename to `Desolate_Frontiers.pkg`.
- **`_build-steam.yml`**:
    - Updated Windows preset to "Windows Desktop (x86)".
    - Created `steam_scripts/` directory with `app_build.vdf`, `depot_build_windows.vdf`, and `depot_build_macos.vdf` templates using placeholders.
    - **Update (2026-02-18 3:11PM)**: Switched `build_macos` job to `macos-latest` runner because Godot 4 requires Xcode tools for macOS export (even for Steam/Ad-hoc if signing is checked in the preset).
    - **Update (2026-02-18 3:25PM)**: Replaced broken `cybercode/steamcmd-action` with `RageAgainstThePixel/setup-steamcmd@v1` in the `deploy` job.
    - **Update (2026-02-18 3:35PM)**: Improved `config.vdf` pathing in the deploy job to use the action's environment variables.
    - **Update (2026-02-18 5:47PM)**: `localconfig.vdf` and `config.vdf` updated. Proceeding with refreshed `config.vdf` in CI.
    - **Update (2026-02-18 5:50PM)**: `config.vdf` alone is still failing on the runner with a Mobile Guard challenge. Recommending a switch back to Email Auth to force `ssfn` creation.
    - **Update (2026-02-18 5:58PM)**: Pivoted to `game-ci/steam-deploy` action which has better internal handling for the `config.vdf` auth method.
    - **Update (2026-02-18 6:15PM)**: Fixed incorrect preset indices in iOS and macOS Store workflows by refactoring Python injection scripts to search for presets by name.
    - **Update (2026-02-18 6:21PM)**: `game-ci/steam-deploy` failed (Access Denied + config mismatch). Reverted to manual `steamcmd` with an isolated `STEAM_HOME` on the runner to prevent session pollution.
    - **Update (2026-02-18 6:35PM)**: Recommended "Clean Folder" local login to capture a portable `config.vdf`.
    - **Update (2026-02-19 5:25PM)**: `config.vdf` auth token rotation proved too unreliable for CI/CD environments. Steam invalidates the cached session frequently. Pivoted strategy: Abandoned automated `steamcmd` deployment in favor of building `.zip` artifacts and publishing them via GitHub Releases for manual Steamworks upload.
    - **Update (2026-02-19 5:50PM)**: Investigated Android, iOS, and macOS (App Store) pipeline failures.
        - **Android**: `_build-google-play.yml` failed because Godot 4 templates require the `android/build` directory to exist before extracting `android_source.zip`. Also required fixing `.gitignore` to allow the template to be tracked by git while ignoring the bulky `libs/` and `.gradle/` outputs.
        - **iOS/macOS**: `_build-ios-appstore.yml` and `_build-macos-appstore.yml` failed because the `fastlane/` directory, `Gemfile`, and `Gemfile.lock` were not copied from the Spellist project. Also reminded the user to populate the `MATCH_SSH_KEY` repository secret.
    - **Update (2026-02-19 7:12PM)**: Apple (iOS/macOS) builds successfully resolved after the user seeded provisioning profiles locally and fixed Fastlane config.
    - **Update (2026-02-19 7:15PM)**: Android build failed with "The caller does not have permission". This indicates that while the app exists, the Service Account is not authorized to manage it or the app hasn't finalized its internal setup.
### Note on Steam Credentials
Steam requires clear-text credentials for automated uploads. Use a dedicated service account if possible and ensure `STEAM_CONFIG_VDF` is used if Steam Guard is active.

## 2026-03-26 - Push Notifications CI Update
- **`_build-ios-appstore.yml`**: Integrated an automated Python step to dynamically inject the `entitlements/push_notifications="Production"` flag into `export_presets.cfg` during the headless Xcode export. This solves the issue of missing capabilities when exporting strictly via GitHub Actions without opening Xcode.
- **Local Debug vs CI Codesigning**: Removed hardcoded App Store provisioning profiles (`application/provisioning_profile_specifier_release`) and distribution certificates (`application/code_sign_identity_release`) from `export_presets.cfg`. This allows developers to natively debug push notifications on local devices via automatic Xcode signing. To maintain flawless App Store headless exports, the specific Apple Distribution code-signing identity is now dynamically injected into the build pipeline at runtime exclusively via `_build-ios-appstore.yml`.

## 2026-04-22 - Security: addressable gem bump
- **`Gemfile.lock`**: Bumped `addressable` from `2.8.9` → `2.9.0` to resolve **CVE-2026-35611** (High severity ReDoS vulnerability affecting versions `>= 2.3.0, < 2.9.0`).
  - `fastlane`'s existing constraint (`>= 2.8, < 3.0.0`) already accepts 2.9.x — no other lock file entries required updating.
  - The transitive `public_suffix` dependency constraint (`>= 2.0.2, < 8.0`) is unchanged between versions.

## 2026-04-22 - Fix: Push Notification Entitlement Enabled for Local Installs
- **`export_presets.cfg`**: Changed `entitlements/push_notifications` from `"Disabled"` to `"Production"` for the iOS preset (preset 7).
  - **Root cause**: With the entitlement disabled, Apple's APNs refuses to issue a device token when `register_push_notifications()` is called. The `APN` singleton's `device_address_changed` signal never fires, so `register_push_token()` is never called, and no tokens are stored in the backend DB — resulting in zero push notifications delivered.
  - **Note on CI**: The `_build-ios-appstore.yml` pipeline already dynamically injects `"Production"` at build time (see 2026-03-26 entry), so App Store/TestFlight builds were unaffected. This fix restores push notification functionality for **local device installs** made via the Godot editor's one-click deploy.

## 2026-04-22 - Fix: APN Singleton Name Corrected in PushNotificationManager
- **`Scripts/System/Services/push_notification_manager.gd`**: Changed all `Engine.has_singleton("APN")` / `Engine.get_singleton("APN")` calls to use `"PushNotifications"` — the name registered by `ios/plugins/apn.gdip`.
  - **Root cause**: The `.gdip` manifest registers the plugin under the name `"PushNotifications"`, so `Engine.has_singleton("APN")` always returned `false`. This caused `_setup_ios()` to return immediately, skipping signal connections entirely. No `device_address_changed` signal was ever received, so `register_push_token()` was never called and the DB remained empty.
  - Also removed the dead `apn.init()` call (the plugin has no `init()` method — initialization happens automatically via `godot_apn_init`) and added `print()` logging to make future debugging easier.
