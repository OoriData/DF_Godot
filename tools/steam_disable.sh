#!/usr/bin/env bash
#
# steam_disable.sh — Unload GodotSteam so the project can build/run on iOS.
#
# WHY: Steamworks has no iOS SDK, so godotsteam ships no iOS library. In Godot
# 4.6 the old "ios.arm64 = ''" trick no longer suppresses the export error
# (iOS features were reworked — note the "apple_embedded" tag). Per GodotSteam's
# own docs, the fix is to remove the extension from .godot/extension_list.cfg.
# The editor regenerates that file from the .gdextension files present AT LAUNCH,
# so the .gdextension itself must be hidden before the editor starts.
#
# USAGE:
#   1. Quit the Godot editor.
#   2. ./tools/steam_disable.sh
#   3. Open the editor, then Project Run / export to iOS.
#   4. When back on desktop: ./tools/steam_enable.sh  (then reopen editor)
#
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT="$PROJECT_ROOT/addons/godotsteam/godotsteam.gdextension"
EXT_DISABLED="$EXT.disabled"
EXT_LIST="$PROJECT_ROOT/.godot/extension_list.cfg"

if [[ -f "$EXT_DISABLED" && ! -f "$EXT" ]]; then
  echo "Steam already disabled. Nothing to do."
  exit 0
fi
if [[ ! -f "$EXT" ]]; then
  echo "ERROR: expected $EXT but it was not found." >&2
  exit 1
fi

# Godot only loads "*.gdextension"; the ".disabled" suffix hides it from the loader.
mv "$EXT" "$EXT_DISABLED"
echo "• godotsteam.gdextension  ->  godotsteam.gdextension.disabled"

# Strip the entry from the loaded-extension list (the editor self-heals this on
# next launch, but removing it now avoids load-failure spam).
if [[ -f "$EXT_LIST" ]]; then
  grep -v "godotsteam/godotsteam.gdextension" "$EXT_LIST" > "$EXT_LIST.tmp" || true
  mv "$EXT_LIST.tmp" "$EXT_LIST"
  echo "• removed godotsteam from .godot/extension_list.cfg"
fi

cat <<'EOF'

Steam DISABLED.  Now: open the Godot editor, then Project Run / export to iOS.
Back on desktop later?  ->  ./tools/steam_enable.sh
EOF
