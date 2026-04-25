#!/bin/bash
set -e

echo "📦 Backing up export_presets.cfg..."
cp export_presets.cfg export_presets.cfg.backup

echo "🔧 Applying CI overrides..."
python3 -c '
import os, re, sys
with open("export_presets.cfg", "r") as f:
    content = f.read()

preset_match = re.search(r"\[preset\.(\d+)\]\s+name=\"iOS\"", content)
if not preset_match:
    print("Error: Could not find preset named \"iOS\"")
    sys.exit(1)

preset_index = preset_match.group(1)

section_regex = r"(\[preset\." + preset_index + r"\.options\].*?)(?=\n\[|$)"

def set_key(match):
    section = match.group(1)
    overrides = {
        "application/export_project_only": "false",
        "application/export_method_release": "2"
    }
    for key, val in overrides.items():
        if f"{key}=" in section:
            section = re.sub(f"{re.escape(key)}=.*", f"{key}={val}", section)
        else:
            section += f"\n{key}={val}"
    return section

new_content = re.sub(section_regex, set_key, content, flags=re.DOTALL)
with open("export_presets.cfg", "w") as f:
    f.write(new_content)
'

echo "🚀 Running Godot headless export (this will take a minute or two)..."
mkdir -p build/ios
# We run Godot. If it fails, the script will catch the error.
if /Applications/Godot.app/Contents/MacOS/Godot --headless --export-release "iOS" "build/ios/test_export.ipa"; then
    echo "✅ Export succeeded! The plugin linking issue is officially resolved."
else
    echo "❌ Export failed! Check the output above."
fi

echo "⏪ Restoring export_presets.cfg..."
mv export_presets.cfg.backup export_presets.cfg

echo "Done."
