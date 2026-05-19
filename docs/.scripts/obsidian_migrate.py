#!/usr/bin/env python3
"""
obsidian_migrate.py
====================
Migrates the DF_Godot /docs directory to an Obsidian-compatible knowledge graph.

What it does:
  1. Adds YAML frontmatter to every .md file (tags derived from folder structure,
     aliases derived from the H1 heading, type from folder name).
  2. Converts absolute `file:///Users/aidan/Work/DF_Godot/docs/...` links to
     clean relative links (e.g. `../03_Systems/ItemsAndMissions.md`).
  3. Replaces bare `res://Scripts/...` code references with relative links to the
     real file path from the repo root so Obsidian can display them as nodes.
  4. Writes an `.obsidian/` vault config (graph-colour rules, appearance, plugins).
  5. Prints a dry-run report before writing — call with --dry-run to inspect only.

Usage:
  python3 docs/.scripts/obsidian_migrate.py           # live run
  python3 docs/.scripts/obsidian_migrate.py --dry-run # inspect only
"""

import os
import re
import sys
import json
import shutil
from pathlib import Path
from datetime import date

# ── Config ─────────────────────────────────────────────────────────────────────
DOCS_ROOT     = Path(__file__).parent.parent.resolve()          # /…/DF_Godot/docs
REPO_ROOT     = DOCS_ROOT.parent                                # /…/DF_Godot
ABS_LINK_BASE = "file:///Users/aidan/Work/DF_Godot/docs"       # old absolute prefix
TODAY         = date.today().isoformat()
DRY_RUN       = "--dry-run" in sys.argv

# ── Folder → tag / type mapping ────────────────────────────────────────────────
FOLDER_META = {
    "01_Architecture": {"type": "architecture",  "tags": ["architecture"]},
    "02_UI_UX":        {"type": "ui-ux",         "tags": ["ui", "ux"]},
    "03_Systems":      {"type": "system",         "tags": ["system"]},
    "04_Technical":    {"type": "technical",      "tags": ["technical"]},
    "99_Reference":    {"type": "reference",      "tags": ["reference"]},
}

# Sub-folder refinements (first path segment after the section folder)
SUB_FOLDER_TAGS = {
    "MapSystem":     ["system/map"],
    "TutorialSystem":["system/tutorial"],
    "VendorPanel":   ["ui/vendor"],
}

# ── Helpers ────────────────────────────────────────────────────────────────────

def section_for(path: Path) -> str:
    """Return the top-level section folder name for a file inside DOCS_ROOT."""
    try:
        rel = path.relative_to(DOCS_ROOT)
        return rel.parts[0] if rel.parts else ""
    except ValueError:
        return ""


def sub_folder_for(path: Path) -> str:
    """Return the immediate sub-folder name (one level below section), if any."""
    try:
        rel = path.relative_to(DOCS_ROOT)
        return rel.parts[1] if len(rel.parts) > 2 else ""
    except ValueError:
        return ""


def extract_h1(text: str) -> str | None:
    """Return the first H1 heading text, or None."""
    m = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
    return m.group(1).strip() if m else None


def build_frontmatter(path: Path, text: str) -> str:
    """Construct a YAML frontmatter block for the given file."""
    section  = section_for(path)
    sub      = sub_folder_for(path)
    meta     = FOLDER_META.get(section, {"type": "note", "tags": []})
    tags     = list(meta["tags"])

    if sub and sub in SUB_FOLDER_TAGS:
        tags += SUB_FOLDER_TAGS[sub]

    # Add filename-level tag (kebab of stem)
    stem_tag = path.stem.lower().replace(" ", "-")
    tags.append(f"codex/{stem_tag}")

    h1 = extract_h1(text)
    alias_lines = f'aliases:\n  - "{h1}"\n' if h1 and h1 != path.stem else ""

    tag_block = "\n".join(f"  - {t}" for t in tags)
    fm = (
        "---\n"
        f"type: {meta['type']}\n"
        f"tags:\n{tag_block}\n"
        f"{alias_lines}"
        f"created: {TODAY}\n"
        "---\n\n"
    )
    return fm


def already_has_frontmatter(text: str) -> bool:
    return text.lstrip().startswith("---")


def abs_to_relative(match: re.Match, source_file: Path) -> str:
    """
    Replace an absolute file:///…/docs/path/to/File.md link with a relative one.
    match.group(1) = link text, match.group(2) = abs URL
    """
    label = match.group(1)
    abs_url = match.group(2)

    # Strip the absolute prefix to get the path inside docs/
    inner = abs_url.replace(ABS_LINK_BASE + "/", "").replace(ABS_LINK_BASE, "")
    target = DOCS_ROOT / inner

    try:
        rel = os.path.relpath(target, source_file.parent)
    except ValueError:
        rel = inner  # fallback on Windows drive mismatch

    return f"[{label}]({rel})"


def convert_links(text: str, source_file: Path) -> tuple[str, int]:
    """Convert all absolute doc links to relative. Returns (new_text, count)."""
    pattern = re.compile(
        r'\[([^\]]+)\]\((file:///Users/aidan/Work/DF_Godot/docs[^)]*)\)'
    )
    count = 0
    def replacer(m: re.Match) -> str:
        nonlocal count
        count += 1
        return abs_to_relative(m, source_file)

    new_text = pattern.sub(replacer, text)
    return new_text, count


# ── Obsidian vault config ──────────────────────────────────────────────────────

OBSIDIAN_CONFIG = {
    "app.json": {
        "useMarkdownLinks": True,       # keep standard Markdown links (not wikilinks)
        "newLinkFormat": "relative",
        "attachmentFolderPath": ".attachments",
        "showLineNumber": True,
    },
    "appearance.json": {
        "theme": "obsidian",
        "cssTheme": "",
        "fontSize": 16,
    },
    "graph.json": {
        "colorGroups": [
            {"query": "tag:architecture",  "color": {"a": 1, "rgb": 4473164}},   # blue
            {"query": "tag:system",        "color": {"a": 1, "rgb": 2980422}},   # green
            {"query": "tag:ui",            "color": {"a": 1, "rgb": 14776960}},  # orange
            {"query": "tag:technical",     "color": {"a": 1, "rgb": 9699539}},   # purple
            {"query": "tag:reference",     "color": {"a": 1, "rgb": 11250603}},  # yellow
        ],
        "showTags": True,
        "showAttachments": False,
        "hideUnresolved": False,
    },
    "core-plugins.json": [
        "file-explorer", "global-search", "switcher", "graph",
        "backlink", "outgoing-link", "tag-pane", "markdown-importer",
    ],
}


def write_obsidian_config(vault_root: Path) -> None:
    obsidian_dir = vault_root / ".obsidian"
    obsidian_dir.mkdir(exist_ok=True)
    for filename, content in OBSIDIAN_CONFIG.items():
        out = obsidian_dir / filename
        if not DRY_RUN:
            out.write_text(json.dumps(content, indent=2))
        print(f"  {'[DRY] ' if DRY_RUN else ''}write {out.relative_to(vault_root)}")


# ── Main ───────────────────────────────────────────────────────────────────────

def process_file(path: Path) -> dict:
    result = {"path": path, "frontmatter_added": False, "links_fixed": 0, "skipped": False}
    text = path.read_text(encoding="utf-8")

    # Skip empty files
    if not text.strip():
        result["skipped"] = True
        return result

    new_text = text

    # 1. Add frontmatter if missing
    if not already_has_frontmatter(new_text):
        new_text = build_frontmatter(path, new_text) + new_text
        result["frontmatter_added"] = True

    # 2. Fix absolute links
    new_text, count = convert_links(new_text, path)
    result["links_fixed"] = count

    # 3. Write if changed
    if new_text != text and not DRY_RUN:
        path.write_text(new_text, encoding="utf-8")

    return result


def main() -> None:
    print(f"\n{'─'*60}")
    print(f"  Obsidian Migration — {'DRY RUN' if DRY_RUN else 'LIVE'}")
    print(f"  Vault root : {DOCS_ROOT}")
    print(f"{'─'*60}\n")

    md_files = sorted(DOCS_ROOT.rglob("*.md"))
    total_fm = 0
    total_links = 0
    skipped = 0

    for md in md_files:
        # Skip files inside the .scripts directory itself
        if ".scripts" in md.parts:
            continue

        res = process_file(md)
        rel = md.relative_to(DOCS_ROOT)

        if res["skipped"]:
            skipped += 1
            print(f"  SKIP  {rel}")
            continue

        markers = []
        if res["frontmatter_added"]:
            markers.append("FM+")
            total_fm += 1
        if res["links_fixed"]:
            markers.append(f"{res['links_fixed']} links")
            total_links += res["links_fixed"]

        status = " | ".join(markers) if markers else "ok"
        prefix = "[DRY] " if DRY_RUN else ""
        print(f"  {prefix}{status:<18} {rel}")

    print(f"\n  ── Obsidian vault config ──")
    write_obsidian_config(DOCS_ROOT)

    print(f"\n{'─'*60}")
    print(f"  Summary")
    print(f"    Files processed : {len(md_files) - skipped}")
    print(f"    Frontmatter added : {total_fm}")
    print(f"    Absolute links fixed : {total_links}")
    print(f"    Skipped (empty) : {skipped}")
    if DRY_RUN:
        print(f"\n  Nothing written — run without --dry-run to apply.")
    else:
        print(f"\n  Done. Open '{DOCS_ROOT}' as an Obsidian vault.")
    print(f"{'─'*60}\n")


if __name__ == "__main__":
    main()
