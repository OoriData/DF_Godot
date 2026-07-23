#!/usr/bin/env python3
"""
rename_readmes.py
==================
Renames every README.md in the docs vault to a meaningful, descriptive name,
then updates all internal links that reference the old filenames.

Run:
  python3 docs/.scripts/rename_readmes.py --dry-run   # inspect
  python3 docs/.scripts/rename_readmes.py             # apply
"""

import os
import re
import sys
from pathlib import Path

DOCS_ROOT = Path(__file__).parent.parent.resolve()
DRY_RUN   = "--dry-run" in sys.argv

# ── Rename map: relative path inside DOCS_ROOT → new filename ────────────────
RENAMES = {
    "README.md":                                  "DocumentationHome.md",
    "01_Architecture/README.md":                  "ArchitectureIndex.md",
    "02_UI_UX/README.md":                         "UISystemIndex.md",
    "02_UI_UX/VendorPanel/README.md":             "VendorPanelOverview.md",
    "03_Systems/README.md":                       "GameSystemsIndex.md",
    "03_Systems/MapSystem/README.md":             "MapSystemOverview.md",
    "03_Systems/TutorialSystem/README.md":        "TutorialSystemOverview.md",
    "04_Technical/README.md":                     "TechnicalReference.md",
}

def build_replacement_table() -> dict[str, str]:
    """
    Build a dict of every possible link reference that could appear in any .md
    file → what it should be replaced with.

    We handle both basename-only and path-suffixed variants so no link is missed:
      README.md → DocumentationHome.md  (same-dir reference)
      ../README.md → ../DocumentationHome.md
      MapSystem/README.md → MapSystem/MapSystemOverview.md
      etc.
    """
    table: dict[str, str] = {}
    for rel_str, new_name in RENAMES.items():
        old_path = Path(rel_str)
        new_path = old_path.parent / new_name

        # Collect variations: any suffix combination that uniquely ends with
        # the old relative path segments.  We'll do regex-based replacement
        # inside each file relative to that file's own directory.
        table[rel_str] = str(new_path).replace("\\", "/")

        # Also store just the filename for same-folder references
        if old_path.parent == Path("."):
            # top-level README.md — the "same folder" reference is just "README.md"
            table["README.md"] = new_name  # only if it maps unambiguously
        else:
            # e.g. "README.md" inside 01_Architecture should map to ArchitectureIndex.md
            # but that could collide — we handle per-file below.
            pass

    return table


def fix_links_in_file(path: Path, renames: dict[str, str]) -> tuple[str, int]:
    """Replace all old README.md link targets in a file with new names."""
    text = path.read_text(encoding="utf-8")
    original = text
    count = 0

    # Build the absolute path of each renamed file so we can resolve relative
    # links from this specific file's directory.
    for rel_str, new_name in renames.items():
        old_abs = DOCS_ROOT / rel_str
        new_abs = old_abs.parent / new_name

        # What would the old and new paths look like relative to *this* file?
        try:
            old_rel = os.path.relpath(old_abs, path.parent).replace("\\", "/")
            new_rel = os.path.relpath(new_abs, path.parent).replace("\\", "/")
        except ValueError:
            continue  # different drive on Windows — skip

        if old_rel not in text:
            continue

        # Replace inside markdown links: (old_rel) → (new_rel)
        escaped = re.escape(old_rel)
        new_text, n = re.subn(
            r'\(' + escaped + r'\)',
            f'({new_rel})',
            text,
        )
        text = new_text
        count += n

    return text, count


def main() -> None:
    print(f"\n{'─'*60}")
    print(f"  README Rename — {'DRY RUN' if DRY_RUN else 'LIVE'}")
    print(f"  Vault root : {DOCS_ROOT}")
    print(f"{'─'*60}\n")

    # ── Step 1: Update links in all files ────────────────────────────────────
    print("  Phase 1 — Updating links across vault…")
    md_files = sorted(DOCS_ROOT.rglob("*.md"))
    link_total = 0
    for md in md_files:
        if ".scripts" in md.parts:
            continue
        new_text, n = fix_links_in_file(md, RENAMES)
        if n:
            link_total += n
            rel = md.relative_to(DOCS_ROOT)
            print(f"    {'[DRY] ' if DRY_RUN else ''}{n} link(s) updated  →  {rel}")
            if not DRY_RUN:
                md.write_text(new_text, encoding="utf-8")

    # ── Step 2: Rename the files ──────────────────────────────────────────────
    print(f"\n  Phase 2 — Renaming files…")
    for rel_str, new_name in RENAMES.items():
        old_abs = DOCS_ROOT / rel_str
        new_abs = old_abs.parent / new_name
        if not old_abs.exists():
            print(f"    MISSING  {rel_str}  (skipped)")
            continue
        rel_old = old_abs.relative_to(DOCS_ROOT)
        rel_new = new_abs.relative_to(DOCS_ROOT)
        print(f"    {'[DRY] ' if DRY_RUN else ''}{rel_old}  →  {rel_new}")
        if not DRY_RUN:
            old_abs.rename(new_abs)

    print(f"\n{'─'*60}")
    print(f"  Summary")
    print(f"    Files renamed        : {len(RENAMES)}")
    print(f"    Link references fixed: {link_total}")
    if DRY_RUN:
        print(f"\n  Nothing written — run without --dry-run to apply.")
    else:
        print(f"\n  Done.")
    print(f"{'─'*60}\n")


if __name__ == "__main__":
    main()
