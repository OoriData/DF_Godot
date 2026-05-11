# Deployment & Environment

This document outlines how to configure, build, and deploy *Desolate Frontiers* across various platforms and environments.

## 1. Environment Configuration

The project uses `app_config.cfg` to manage environment-specific variables.

### Key Settings
- `active_env`: Switches between `dev` and `prod`.
- `base_url_dev`: Typically `http://127.0.0.1:1337` for local testing.
- `base_url_prod`: The live production API (e.g., `https://df-api.oori.dev:1337`).

### Switching Environments
To switch the client to production mode, change `active_env="prod"` in `app_config.cfg`. This ensures the `APICalls` service points to the correct simulation server.

---

## 2. Export Targets

The project is configured to export to the following platforms via `export_presets.cfg`:

- **macOS**: Signed and sandboxed for the Mac App Store.
- **Windows**: x86_64 desktop build with embedded PCK.
- **Linux**: x86_64 and ARM64 (for Steam Deck and Raspberry Pi compatibility).
- **Android**: Gradle-based build with adaptive icons.
- **iOS**: Xcode-integrated build with required privacy plists.

### Standard Export Filter
All presets should include `*.cfg` in their "Include Filter" to ensure `app_config.cfg` is bundled with the executable.

---

## 3. CI/CD Pipeline (GitHub Actions)

The project uses automated workflows located in `.github/workflows/` for continuous integration and deployment.

### Active Workflows
- **`build-and-release.yml`**: The primary pipeline that builds for all desktop platforms on every tag.
- **`_build-google-play.yml`**: Handles Android signing and upload to the Play Console.
- **`_build-ios-appstore.yml`**: Uses macOS runners to build and upload to TestFlight.
- **`_build-steam.yml`**: Integrates with the SteamWorks SDK to push builds to the Steam branch.
- **`_build-web.yml`**: Builds the HTML5 version (requires SharedArrayBuffer support for multi-threading).

---

## 4. Build Prerequisites

To build locally, you need:
1. **Godot 4.x**: Matching the version in `project.godot`.
2. **Export Templates**: Downloaded via the Godot editor.
3. **Android SDK**: Required for Android builds.
4. **Xcode**: Required for iOS and macOS builds.
5. **SteamWorks SDK**: Required if compiling with Steam integration enabled.

---

## 5. Security & Secrets
Sensitive information (like API keys or signing certificates) must **never** be committed to the repository. They are managed via **GitHub Actions Secrets** and injected into the build environment during the CI/CD process.
