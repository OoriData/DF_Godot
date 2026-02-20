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
