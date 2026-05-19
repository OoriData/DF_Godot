#!/usr/bin/env python3
import os
import re

VAULT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

print("=" * 60)
print("  Desolate Frontiers Orphan Node Finder")
print(f"  Vault root : {VAULT_ROOT}")
print("=" * 60)

# Get all markdown files
all_md_files = []
clean_names = set()
file_to_path = {}

for root, dirs, files in os.walk(VAULT_ROOT):
    for file in files:
        if file.endswith(".md"):
            rel_path = os.path.relpath(os.path.join(root, file), VAULT_ROOT)
            basename = os.path.splitext(file)[0]
            all_md_files.append(rel_path)
            clean_names.add(basename.lower())
            file_to_path[basename.lower()] = rel_path

# Directed graph: target_file -> set of source_files linking to it
incoming_links = {f: set() for f in all_md_files}

wikilink_pattern = re.compile(r'\[\[([^\]|#]+)(?:\||#)?[^\]]*\]\]')
markdown_link_pattern = re.compile(r'\[[^\]]+\]\(([^)]+\.md)\)')

for rel_path in all_md_files:
    full_path = os.path.join(VAULT_ROOT, rel_path)
    with open(full_path, "r", encoding="utf-8") as f:
        content = f.read()
        
        # Parse [[WikiLinks]]
        wikilinks = wikilink_pattern.findall(content)
        for link in wikilinks:
            link_lower = link.strip().lower()
            if link_lower in file_to_path:
                target = file_to_path[link_lower]
                if target != rel_path:
                    incoming_links[target].add(rel_path)
                    
        # Parse [Markdown](links.md)
        md_links = markdown_link_pattern.findall(content)
        for link in md_links:
            # Get just the filename
            basename = os.path.splitext(os.path.basename(link))[0].lower()
            if basename in file_to_path:
                target = file_to_path[basename]
                if target != rel_path:
                    incoming_links[target].add(rel_path)

# Find orphans (0 incoming links, excluding DocumentationHome.md and AI_ONBOARDING.md)
orphans = []
for file, sources in incoming_links.items():
    # DocumentationHome and AI_ONBOARDING are entry points, they naturally have 0 incoming links sometimes
    if len(sources) == 0 and os.path.basename(file) not in ["DocumentationHome.md", "AI_ONBOARDING.md"]:
        orphans.append(file)

print(f"\n[+] Scanned {len(all_md_files)} files.")
print(f"[+] Found {len(orphans)} orphan nodes:")

if orphans:
    for orphan in sorted(orphans):
        print(f"  - {orphan}")
else:
    print("  None! Every single node in your graph has at least one path leading to it.")
print("=" * 60)
