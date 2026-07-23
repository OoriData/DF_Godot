---
type: technical
tags:
  - technical
  - codex/deployment
aliases:
  - "Deployment & Environment"
created: 2026-05-18
updated: 2026-07-23
---

# Deployment & Environment

How *Desolate Frontiers* is versioned, built, and shipped to every storefront.

> **TL;DR of the split:** GitHub Actions **builds** every platform. It **auto-publishes**
> to Google Play, TestFlight, the Mac App Store, and GitHub Pages. **Steam is the exception**
> — CI only produces the Windows/macOS artifacts; uploading them to Steam is a **manual
> SteamPipe step** on a Mac (see §5). In every store, CI gets the binary into the store's
> back-end, but the final "submit for review / release" click is always manual.

---

## 1. Environment configuration (`app_config.cfg`)

- `[api] active_env` — `dev` or `prod`. `base_url_dev` / `base_url_prod` set the API endpoint.
- `[steam] app_id` — Steamworks AppID (`4242880`). Was previously defaulting to `480` (the
  Spacewar test app); if this is missing, Steam features attach to the wrong app.

`*.cfg` is bundled into every export so `app_config.cfg` ships with the build.

---

## 2. Versioning & release triggers

1. Bump `config/version` in `project.godot` (strict `x.y.z`, **no** suffixes — CI rejects `1.2.3-rc1`).
2. Add a matching `## [x.y.z]` section to `CHANGELOG.md` (its body becomes the GitHub Release notes;
   missing → "No release notes found").
3. Trigger the pipeline (`build-and-release.yml`), one of:
   - **Push a `v*` tag** → builds all 5 platforms **and publishes** + creates the GitHub Release.
   - **Push to the `release` branch** → builds + publishes.
   - **Actions → "Build and Release" → Run workflow** → choose platforms; publish only happens
     if you tick **`dispatch_publish`** (leave unticked for a safe build-only dry run).

> **Branch note:** `release` is only ever updated from `main` via a **GitHub Pull Request** —
> never a local `git merge` (that has broken the branch before).

---

## 3. Automated store pipeline

| Platform | Build workflow | Publish target | Auto-submits? |
|---|---|---|---|
| Android | `_build-google-play.yml` → `.aab` | Google Play, track `internal`, status **draft** | No — promote/submit in Play Console |
| iOS | `_build-ios-appstore.yml` → `.ipa` | **TestFlight** (fastlane) | No — submit from App Store Connect |
| macOS (App Store) | `_build-macos-appstore.yml` → `.pkg` | App Store Connect, **not** submitted | No — attach to a version & submit |
| Web | `_build-web.yml` | GitHub Pages | n/a |
| **Steam** | `_build-steam.yml` → Win/macOS zips | **nothing — manual, see §5** | Manual |
| GitHub Release | — | Tagged `v<version>` release w/ all artifacts (full builds only) | n/a |

### Required GitHub secrets
`GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`, `APP_STORE_CONNECT_API_KEY`, `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_ISSUER_ID`, `MATCH_PASSWORD`, `MATCH_GIT_URL`, `GIT_TOKEN`,
`APPLE_DISTRIBUTION_P12`. Signing certs live in the `OoriData/mobile-signing-certs` match repo.

---

## 4. GodotSteam: the "disabled at rest" rule ⚠️

GodotSteam has **no iOS library**, and Godot 4.6 broke the old `ios.arm64=""` suppression.
If the plugin is enabled in the committed repo, the **iOS build in the full pipeline crashes**.

**Rule: `addons/godotsteam/godotsteam.gdextension` must be committed as `.disabled`.**
It is enabled *only* for the Steam build — locally via `tools/steam_enable.sh`, and in CI by a
step inside `_build-steam.yml` (the non-Steam workflows never see it enabled). `SteamManager`
([`Scripts/System/steam_manager.gd`](../../Scripts/System/steam_manager.gd)) is guarded by
`ClassDB.class_exists("Steam")`, so the game runs fine on every platform with the plugin off.

### Helper scripts (`tools/`)

| Script | What it does | When to run |
|---|---|---|
| `steam_enable.sh` | Renames `.gdextension.disabled` → `.gdextension`. | Before building **desktop/Steam** locally. Quit the editor first, run it, then reopen the editor (regenerates `.godot/extension_list.cfg`). |
| `steam_disable.sh` | Reverse — renames back to `.disabled` and strips the extension_list entry. | Before any **iOS** work or Project Run (editor closed). Also the fix if your phone vanishes from the remote-deploy dropdown. |
| `steam_stage_macos.sh` | Takes an exported macOS `.zip`/`.app`, strips cruft, **ad-hoc re-signs it with the entitlements GodotSteam needs**, and stages it into the macOS Steam depot. | After exporting the macOS Steam build (see §5 / §6). CI runs this automatically. |

---

## 5. Steam release (manual)

**Identity:** AppID **`4242880`** · Windows depot **`4242882`** · macOS depot **`4242883`**
(`4242881` is a spare). SteamPipe config lives in
`steamworks_sdk/tools/ContentBuilder/scripts/4242880.vdf`; `steamcmd` is at
`steamworks_sdk/tools/ContentBuilder/builder_osx/steamcmd`. Steam has **no web uploader** —
build files must go up via SteamPipe (`steamcmd` on macOS, or `SteamPipeGUI.exe` on Windows).

> The `content/`, `output/`, and `builder_*` folders under ContentBuilder are gitignored —
> they hold regenerated builds and the steamcmd runtime (both way over GitHub's 100MB limit).
> Only the `.vdf` build scripts are tracked.

### Steps

1. **Build** the Steam Win + macOS artifacts — either via GitHub (`_build-steam.yml`, download the
   `steam-build-windows` / `steam-build-macos` artifacts) or locally (`steam_enable.sh` → reopen
   editor → export the "Windows Desktop (x86)" and "macOS" presets).
2. **Stage** the builds into the depot folders:
   - Windows → unzip `.exe` + `steam_api64.dll` (+ `libgodotsteam…dll`) into
     `steamworks_sdk/tools/ContentBuilder/content/4242880/4242882/`
   - macOS → `tools/steam_stage_macos.sh <macos.zip>` (re-signs + stages into `…/4242883/`)
3. **Verify Steamworks is present** — Windows folder must contain `steam_api64.dll`; the `.app` must
   contain `libsteam_api.dylib`. Missing = no Steam login / DF+ purchases.
4. **Upload** (needs your Steamworks login + Steam Guard):
   ```
   cd steamworks_sdk/tools/ContentBuilder
   ./builder_osx/steamcmd +login <user> +run_app_build "$(pwd)/scripts/4242880.vdf" +quit
   ```
   Success ends with `Successfully finished AppID 4242880 build (BuildID …)`.
5. **Set live** — partner.steamgames.com → app → **SteamPipe → Builds** → select the BuildID →
   set live on the **`beta`** branch → **Preview Change → Publish**.
6. **Test** — Steam client → game → Properties → Betas → opt into `beta` → launch. Confirm it runs
   and `[SteamManager] Steam initialized successfully.` appears.
7. **Promote** — set the same build live on **`default`** → Publish. Now everyone gets it.
8. **Developer Update post** — partner site → **Marketing & Visibility → Events & Announcements** →
   Create Event → type **Update** → title + patch notes + header image → Publish.
9. **`tools/steam_disable.sh`** before returning to any iOS work.

---

## 6. macOS signing notes

- The Oori **`Apple Distribution`** cert is **revoked** and is the wrong type anyway (App Store, not
  Developer ID). So Steam macOS builds are **ad-hoc signed** via `steam_stage_macos.sh`.
- Export **preset 0 ("macOS")** is configured for Steam: `disable_library_validation=true`,
  `allow_dyld_environment_variables=true`, `app_sandbox=false`. **Do not** copy these to preset 1
  ("macOS (App Store)"), which must stay sandboxed.
- **Future improvement:** obtain a **Developer ID Application** certificate + enable notarization →
  Gatekeeper-clean builds with no ad-hoc workaround.

---

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| macOS Steam build **crashes at launch** (`SIGABRT` in `GDExtensionManager::load_extensions`) | Hardened-runtime library validation blocking the Steam dylib. Re-run `tools/steam_stage_macos.sh`; confirm preset 0 entitlements (§6). |
| `steamcmd`: **"Invalid content root for depot …"** | The depot staging folder is empty — you didn't unzip the build into `content/4242880/<depot>/`. |
| iOS build fails in the full pipeline | GodotSteam enabled at rest — restore `.disabled` (§4) and re-commit. |
| Steam upload shows only self-update, no build | `steamcmd` was still updating itself / waiting for Steam Guard. Re-run and complete login. |
| Windows build missing `steam_api64.dll` | Plugin wasn't enabled before export (`steam_enable.sh` + reopen editor / CI enable step). |

---

## 8. Security & secrets

Never commit API keys or signing certs. They live in **GitHub Actions Secrets** and the
`OoriData/mobile-signing-certs` match repo, injected at build time.
