#!/usr/bin/env python3
import os
import re
import sys

VAULT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PROJECT_ROOT = os.path.abspath(os.path.join(VAULT_ROOT, ".."))

print("=" * 60)
print("  Desolate Frontiers Documentation Gap Analyzer")
print(f"  Vault root   : {VAULT_ROOT}")
print(f"  Project root : {PROJECT_ROOT}")
print("=" * 60)

# 1. Parse project.godot for Autoloads
autoloads = {}
project_godot_path = os.path.join(PROJECT_ROOT, "project.godot")
if os.path.exists(project_godot_path):
    with open(project_godot_path, "r", encoding="utf-8") as f:
        in_autoload = False
        for line in f:
            line = line.strip()
            if line.startswith("[autoload]"):
                in_autoload = True
                continue
            if in_autoload and line.startswith("["):
                in_autoload = False
            if in_autoload and "=" in line:
                key, val = line.split("=", 1)
                key = key.strip()
                val = val.strip().replace('"', '')
                if val.startswith("*res://"):
                    val = val[7:]
                autoloads[key] = val

print(f"\n[+] Found {len(autoloads)} Autoload Singletons in project.godot.")

# 2. Get list of all MD files in Vault
md_files = {}
all_md_paths = []
for root, dirs, files in os.walk(VAULT_ROOT):
    for file in files:
        if file.endswith(".md"):
            rel_path = os.path.relpath(os.path.join(root, file), VAULT_ROOT)
            basename = os.path.splitext(file)[0]
            md_files[basename.lower()] = rel_path
            all_md_paths.append(os.path.join(root, file))

print(f"[+] Found {len(all_md_paths)} Markdown documentation files in Vault.")

# 3. Analyze Index files for links pointing directly to GDScripts
direct_script_links = []
index_files = [
    os.path.join(VAULT_ROOT, "02_UI_UX/UISystemIndex.md"),
    os.path.join(VAULT_ROOT, "03_Systems/GameSystemsIndex.md"),
    os.path.join(VAULT_ROOT, "04_Technical/TechnicalReference.md")
]

gd_pattern = re.compile(r'\[([^\]]+)\]\(([^)]+\.gd)\)')

for index_path in index_files:
    if os.path.exists(index_path):
        rel_index = os.path.relpath(index_path, VAULT_ROOT)
        with open(index_path, "r", encoding="utf-8") as f:
            for i, line in enumerate(f, 1):
                matches = gd_pattern.findall(line)
                for label, target in matches:
                    direct_script_links.append({
                        "index": rel_index,
                        "line": i,
                        "label": label,
                        "target": target
                    })

# 4. Check which Autoloads are referenced in the documentation
autoload_mentions = {a: [] for a in autoloads.keys()}
# Standard cross-references
for file_path in all_md_paths:
    rel_file = os.path.relpath(file_path, VAULT_ROOT)
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()
        for a in autoloads.keys():
            # Check for name or script path mentions
            script_name = os.path.basename(autoloads[a])
            if a in content or script_name in content:
                autoload_mentions[a].append(rel_file)

# 5. Extract unresolved Wikilinks [[Link]]
wikilink_pattern = re.compile(r'\[\[([^\]|#]+)(?:\||#)?[^\]]*\]\]')
unresolved_links = []

for file_path in all_md_paths:
    rel_file = os.path.relpath(file_path, VAULT_ROOT)
    with open(file_path, "r", encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            links = wikilink_pattern.findall(line)
            for link in links:
                link_clean = link.strip().lower()
                # Check if it corresponds to any known MD file base name
                if link_clean not in md_files:
                    unresolved_links.append({
                        "file": rel_file,
                        "line": i,
                        "link": link
                    })

# --- RENDER RESULTS ---
print("\n" + "=" * 60)
print("  ANALYSIS RESULTS")
print("=" * 60)

# Section A: Undocumented Menus (Index links pointing directly to GD files)
print("\n⚠️  UNDOCUMENTED SYSTEMS (Index files pointing directly to raw scripts):")
if direct_script_links:
    for link in direct_script_links:
        print(f"  - [{link['index']}:L{link['line']}] Link '{link['label']}' points directly to raw script:")
        print(f"    --> {link['target']}")
else:
    print("  None! All index links point to rich Markdown documentation.")

# Section B: Undocumented Autoloads
print("\n⚠️  UNDOCUMENTED AUTOLOADS (Registered singletons with 0 references in docs):")
undoc_autoloads = 0
for a, mentions in autoload_mentions.items():
    if len(mentions) == 0:
        undoc_autoloads += 1
        print(f"  - Singleton: '{a}' ({autoloads[a]})")
if undoc_autoloads == 0:
    print("  None! All Autoload singletons are referenced in documentation.")
else:
    print(f"  --> Total: {undoc_autoloads} undocumented autoload singletons.")

# Section C: Broken/Unresolved Wikilinks
print("\n⚠️  UNRESOLVED WIKILINKS (Links referencing files that do not exist):")
if unresolved_links:
    for l in unresolved_links:
        print(f"  - [{l['file']}:L{l['line']}] Broken WikiLink: [[{l['link']}]]")
else:
    print("  None! All internal Wikilinks resolve perfectly.")

print("\n" + "=" * 60)
print("  Done. Follow the blueprint to resolve these gaps!")
print("=" * 60)
