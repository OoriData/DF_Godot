#!/usr/bin/env bash
#
# steam_enable.sh — Re-enable GodotSteam for desktop builds (reverses steam_disable.sh).
#
# USAGE:
#   1. Quit the Godot editor.
#   2. ./tools/steam_enable.sh
#   3. Reopen the editor — it re-registers the extension and rewrites
#      .godot/extension_list.cfg automatically.
#
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT="$PROJECT_ROOT/addons/godotsteam/godotsteam.gdextension"
EXT_DISABLED="$EXT.disabled"

if [[ -f "$EXT" && ! -f "$EXT_DISABLED" ]]; then
  echo "Steam already enabled. Nothing to do."
  exit 0
fi
if [[ ! -f "$EXT_DISABLED" ]]; then
  echo "ERROR: expected $EXT_DISABLED but it was not found." >&2
  exit 1
fi

mv "$EXT_DISABLED" "$EXT"
echo "• godotsteam.gdextension.disabled  ->  godotsteam.gdextension"

cat <<'EOF'

Steam ENABLED.  Reopen the Godot editor; it re-registers the extension on launch.
EOF
