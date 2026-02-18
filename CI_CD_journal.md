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

### Note on Steam Credentials
Steam requires clear-text credentials for automated uploads. Use a dedicated service account if possible and ensure `STEAM_CONFIG_VDF` is used if Steam Guard is active.
