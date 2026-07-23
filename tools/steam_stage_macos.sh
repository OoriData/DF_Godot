#!/usr/bin/env bash
#
# steam_stage_macos.sh — Prepare an exported macOS build for Steam upload.
#
# WHAT IT DOES:
#   1. Accepts a Godot macOS export as either a .zip or a .app.
#   2. Extracts it (via ditto, preserving the bundle's symlinks + exec bits).
#   3. Strips macOS cruft (.DS_Store, __MACOSX) that pollutes Steam depots.
#   4. Ad-hoc re-signs the nested Steam dylibs and the app bundle WITH the
#      entitlements GodotSteam requires, dropping hardened-runtime library
#      validation.
#   5. Copies the finished .app into the destination (Steam macOS depot folder).
#
# WHY (do not remove this step):
#   Godot's macOS export ad-hoc signs with hardened runtime and NO entitlements.
#   Hardened-runtime *library validation* then refuses to load the third-party
#   GodotSteam dylib, so the game aborts at launch:
#       SIGABRT in GDExtensionManager::load_extensions -> open_dynamic_library
#   Steam builds are ad-hoc signed (the Oori "Apple Distribution" cert is revoked
#   and is the wrong type anyway — Steam needs Developer ID, not App Store), so we
#   re-sign here with:
#       com.apple.security.cs.disable-library-validation
#       com.apple.security.cs.allow-dyld-environment-variables   (Steam overlay)
#
# USAGE:
#   ./tools/steam_stage_macos.sh <macos-zip-or-app> [dest-dir]
#
#   dest-dir defaults to the macOS Steam depot staging folder (4242883).
#
# EXAMPLES:
#   ./tools/steam_stage_macos.sh ~/Downloads/"Desolate Frontiers macOS.zip"
#   ./tools/steam_stage_macos.sh build/mac/DF.app /tmp/out   # e.g. from CI
#
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_DEST="$PROJECT_ROOT/steamworks_sdk/tools/ContentBuilder/content/4242880/4242883"

SRC="${1:-}"
DEST="${2:-$DEFAULT_DEST}"

if [[ -z "$SRC" || ! -e "$SRC" ]]; then
  echo "ERROR: pass the exported macOS .zip or .app as the first argument." >&2
  echo "Usage: $0 <macos-zip-or-app> [dest-dir]" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1 + 2. Get a .app into $WORK
if [[ "$SRC" == *.zip ]]; then
  echo "• Extracting $SRC"
  ditto -x -k "$SRC" "$WORK"
else
  echo "• Copying $SRC"
  ditto "$SRC" "$WORK/$(basename "$SRC")"
fi

# 3. Strip cruft
find "$WORK" -name '.DS_Store' -delete 2>/dev/null || true
rm -rf "$WORK/__MACOSX" 2>/dev/null || true

APP="$(find "$WORK" -maxdepth 2 -name '*.app' -type d | head -1)"
if [[ -z "$APP" ]]; then
  echo "ERROR: no .app bundle found inside $SRC" >&2
  exit 1
fi
echo "• Found app: $(basename "$APP")"

# Sanity: the GodotSteam dylib must actually be present, or Steam features are dead.
if ! ls "$APP/Contents/Frameworks/"*godotsteam*.dylib >/dev/null 2>&1; then
  echo "WARNING: no GodotSteam dylib in $APP/Contents/Frameworks/ — this build has NO" >&2
  echo "         Steamworks integration (was the plugin enabled before export?)." >&2
fi

# 4. Ad-hoc re-sign
ENT="$WORK/steam_entitlements.plist"
cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <true/>
</dict>
</plist>
PLIST

echo "• Re-signing nested libraries (ad-hoc)"
find "$APP/Contents/Frameworks" -type f \( -name '*.dylib' -o -name 'GodotApplePlugins' \) \
  -exec codesign --force --timestamp=none -s - {} \;

echo "• Re-signing app bundle (ad-hoc, entitlements applied)"
codesign --force --timestamp=none --entitlements "$ENT" -s - "$APP"

codesign --verify --deep --strict "$APP" && echo "• Signature verified OK"

# 5. Place into destination depot folder
mkdir -p "$DEST"
rm -rf "${DEST:?}/"*
ditto "$APP" "$DEST/$(basename "$APP")"
echo "• Staged -> $DEST/$(basename "$APP")"
echo "Done."
