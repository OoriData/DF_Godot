#!/usr/bin/env python3
"""
docs_check.py — structural linter for the Desolate Frontiers documentation graph.

Treats docs/ as a knowledge graph and asserts the invariants defined in
docs/DocumentationAudit.md. Every check here caught a real defect during the
2026-07-28 audit; none are speculative.

Usage:
    python3 tools/docs_check.py             # errors fail (exit 1), warnings print
    python3 tools/docs_check.py --strict    # dead ends/orphans fail too (staleness never does)
    python3 tools/docs_check.py --warnings  # list warnings in full (they are
                                            # summarised by default)
    python3 tools/docs_check.py --backlog   # print the drift backlog and exit 0

Checks (E = error, W = warning):
    E  link       relative .md links resolve
    E  anchor     #anchors resolve to a real heading in the target
    E  codepath   `Scripts/…`, `Scenes/…`, `Tests/…` references exist in the tree
    E  frontmatter every doc has type / updated / status
    E  tags       every tag is in the approved vocabulary
    E  index      every doc is covered by its section index (directly, or via a
                  sub-overview that index links to)
    E  autoload   the Autoload Register lists every project.godot [autoload] entry
    W  orphan     doc has no inbound links
    W  deadend    doc has no outbound links
    W  stale      verified_against_code older than STALE_DAYS (or absent)
    W  codedrift  cited code changed AFTER the doc was last verified
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import subprocess
import sys
from collections import defaultdict

# ── configuration ────────────────────────────────────────────────────────────

DOCS = "docs"
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STALE_DAYS = 30  # this project moves fast; 30d keeps the queue honest

# Section indexes. A doc in one of these directories must be reachable from its
# index, either directly or through a sub-overview the index links to.
SECTION_INDEXES = {
    "01_Architecture": "01_Architecture/ArchitectureIndex.md",
    "02_UI_UX": "02_UI_UX/UIAudit.md",
    "03_Systems": "03_Systems/GameSystemsIndex.md",
    "04_Technical": "04_Technical/TechnicalReference.md",
    "99_Reference": "99_Reference/Glossary.md",
}

# Root-level docs are their own entry points and are exempt from index coverage.
ROOT_EXEMPT = {
    "DocumentationHome.md",
    "AI_ONBOARDING.md",
    "PROJECT_MAP.md",
    "TODO.md",
    "SprintHistory.md",
    "DocumentationAudit.md",
}

# Written by a hardcoded string template in Godot (APICalls._debug_dump_map_to_file(),
# Scripts/System/api_calls.gd), overwritten wholesale on the first /map load in any dev
# session with debug dumps on. It has no knowledge of the frontmatter contract and will
# clobber it every time — so frontmatter is not required here. If you teach the dumper to
# emit frontmatter, remove this and let the normal check cover it.
AUTO_GENERATED = {
    "99_Reference/data_dumps/Map_example.md",
}

# Approved tag vocabulary (audit F2). Keep this small enough to hold in your head.
APPROVED_TAGS = {
    # facet: layer — where in the stack this lives
    "layer/ui", "layer/service", "layer/autoload", "layer/backend", "layer/protocol",
    # facet: platform — where it only/especially applies
    "platform/steam", "platform/ios", "platform/android", "platform/desktop", "platform/web",
    # facet: concept — cross-cutting concerns that folders cannot express
    "concept/scaling", "concept/auth", "concept/binary-protocol",
    "concept/onboarding", "concept/persistence", "concept/errors",
    # facet: status — drift tracking (audit F4)
    "status/current", "status/unverified", "status/drifting", "status/archive",
    # facet: kind — document role
    "kind/index", "kind/reference", "kind/deep-dive", "kind/process", "kind/audit",
}

VALID_STATUS = {"current", "unverified", "drifting", "archive"}

# Must enumerate every project.godot [autoload] entry — see check_autoload_register.
AUTOLOAD_REGISTER = "04_Technical/AutoloadOrder.md"

# Paths owned by other repos — referenced deliberately, unresolvable from here.
EXTERNAL_PREFIXES = (
    "df_lib/", "pylib/", "engine/", "desolate_frontiers/", "~/", "addons/gut",
)

CODEPATH_RE = re.compile(
    r"`((?:Scripts|Scenes|Tests|Assets|tools)/[A-Za-z0-9_/\.-]+\."
    r"(?:gd|tscn|tres|json|sh|py|cfg))(?::\d+(?:-\d+)?)?`"
)
# Bare filename citations — `convoy_menu.gd`. Resolved via repo_basename_index().
BARE_CODEFILE_RE = re.compile(r"`([A-Za-z0-9_]+\.(?:gd|tscn|tres|py|sh))`")
LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")
HEADING_RE = re.compile(r"^#{1,6}\s+(.*)$", re.M)
FENCE_RE = re.compile(r"```.*?```", re.S)


# ── helpers ──────────────────────────────────────────────────────────────────

def slugify(heading: str) -> str:
    """GitHub's heading-anchor algorithm.

    Strips backticks and punctuation, lowercases, then maps each remaining space
    to one hyphen. Punctuation removal leaves the surrounding spaces intact, so
    'F4 - No staleness' yields 'f4--no-staleness' (two hyphens). Collapsing the
    whitespace instead produces a slug that silently fails to resolve on GitHub.
    """
    s = heading.strip().replace("`", "").lower()
    s = re.sub(r"[^\w\s-]", "", s)
    return s.strip().replace(" ", "-")


def strip_fences(text: str) -> str:
    """Drop fenced code blocks: illustrative links inside them are not real edges."""
    return FENCE_RE.sub("", text)


def parse_frontmatter(text: str) -> dict | None:
    """Minimal YAML frontmatter reader — handles the scalar and list forms used here."""
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    out: dict = {}
    key = None
    for line in text[4:end].splitlines():
        if not line.strip():
            continue
        if line.startswith("  - ") and key:
            out.setdefault(key, []).append(line[4:].strip().strip('"\''))
        elif ":" in line and not line.startswith(" "):
            key, _, val = line.partition(":")
            key = key.strip()
            val = val.strip().strip('"\'')
            out[key] = val if val else []
    return out


def repo_basename_index() -> dict[str, str]:
    """Map `foo.gd` -> `Scripts/…/foo.gd` for tracked source files.

    Docs cite bare filenames far more often than full paths (49 docs vs 43 at last
    count), so code-drift detection would miss over half the graph without this.
    Ambiguous basenames are dropped rather than guessed — a wrong resolution would
    produce a confidently false drift warning, which is worse than a missed one.
    `addons/` is excluded: vendored third-party code isn't ours to track.
    """
    try:
        out = subprocess.run(
            ["git", "ls-files", "*.gd", "*.tscn", "*.tres", "*.py", "*.sh"],
            cwd=REPO_ROOT, capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return {}
    if out.returncode != 0:
        return {}

    seen: dict[str, list[str]] = defaultdict(list)
    for path in out.stdout.split():
        if path.startswith("addons/"):
            continue
        seen[os.path.basename(path)].append(path)
    return {name: paths[0] for name, paths in seen.items() if len(paths) == 1}


def git_last_commit_times(paths: set[str]) -> dict[str, int]:
    """Unix timestamp of the last commit touching each path — in ONE git call.

    Walks history newest-first with --name-only and records the first (= newest)
    commit each path appears in. Doing this per-file would be hundreds of
    subprocesses; this is one, and history here is small enough to walk whole.

    Only committed state is considered. Uncommitted edits are invisible on
    purpose: this must give the same answer on your machine and in CI.
    """
    if not paths:
        return {}
    try:
        out = subprocess.run(
            ["git", "log", "--format=__C__%ct", "--name-only"],
            cwd=REPO_ROOT, capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError):
        return {}
    if out.returncode != 0:
        return {}

    newest: dict[str, int] = {}
    ts = 0
    for line in out.stdout.splitlines():
        if line.startswith("__C__"):
            try:
                ts = int(line[5:])
            except ValueError:
                ts = 0
        elif line and line in paths and line not in newest:
            newest[line] = ts
    return newest


def find_docs() -> list[str]:
    docs = []
    for dirpath, dirnames, filenames in os.walk(DOCS):
        dirnames[:] = [d for d in dirnames if d != ".obsidian"]
        for name in filenames:
            if name.endswith(".md"):
                docs.append(os.path.relpath(os.path.join(dirpath, name), DOCS))
    return sorted(docs)


# ── the checker ──────────────────────────────────────────────────────────────

class DocsCheck:
    def __init__(self) -> None:
        self.errors: list[tuple[str, str, str]] = []    # (check, doc, detail)
        self.warnings: list[tuple[str, str, str]] = []
        self.docs = find_docs()
        self.text: dict[str, str] = {}
        self.body: dict[str, str] = {}
        self.fm: dict[str, dict | None] = {}
        self.anchors: dict[str, set[str]] = {}
        self.outbound: dict[str, set[str]] = defaultdict(set)
        self.inbound: dict[str, set[str]] = defaultdict(set)

        for doc in self.docs:
            raw = open(os.path.join(DOCS, doc), encoding="utf8").read()
            self.text[doc] = raw
            self.body[doc] = strip_fences(raw)
            self.fm[doc] = parse_frontmatter(raw)
            self.anchors[doc] = {slugify(h) for h in HEADING_RE.findall(raw)}

    def is_archived(self, doc: str) -> bool:
        return (self.fm.get(doc) or {}).get("status") == "archive"

    def err(self, check: str, doc: str, detail: str) -> None:
        self.errors.append((check, doc, detail))

    def warn(self, check: str, doc: str, detail: str) -> None:
        self.warnings.append((check, doc, detail))

    # ── individual checks ────────────────────────────────────────────────────

    def check_links_and_anchors(self) -> None:
        known = set(self.docs)
        for doc in self.docs:
            for _label, target in LINK_RE.findall(self.body[doc]):
                if target.startswith(("http://", "https://", "mailto:")):
                    continue
                path, _, anchor = target.partition("#")

                if not path:  # same-document anchor
                    if anchor and anchor not in self.anchors[doc]:
                        self.err("anchor", doc, f"#{anchor} (no such heading here)")
                    continue

                resolved = os.path.normpath(os.path.join(os.path.dirname(doc), path))

                if path.endswith(".md"):
                    if resolved not in known:
                        self.err("link", doc, target)
                        continue
                    self.outbound[doc].add(resolved)
                    self.inbound[resolved].add(doc)
                    if anchor and anchor not in self.anchors[resolved]:
                        self.err("anchor", doc, f"{target} (no such heading in target)")
                else:
                    # link out of docs/ into the repo (source files, addons, …)
                    on_disk = os.path.normpath(os.path.join(REPO_ROOT, DOCS, os.path.dirname(doc), path))
                    if not os.path.exists(on_disk):
                        self.err("link", doc, f"{target} (not on disk)")

    def check_codepaths(self) -> None:
        """Verify referenced source paths exist.

        Docs sometimes cite a path *because* it is wrong (the audit's drift table) or
        not yet written (a planned test). Wrap those in:
            <!-- docs-check:ignore-codepaths start -->
            …
            <!-- docs-check:ignore-codepaths end -->
        which suppresses this check without weakening it anywhere else.
        """
        for doc in self.docs:
            suppressed = False
            for line in self.body[doc].splitlines():
                if "docs-check:ignore-codepaths start" in line:
                    suppressed = True
                    continue
                if "docs-check:ignore-codepaths end" in line:
                    suppressed = False
                    continue
                if suppressed:
                    continue
                for ref in CODEPATH_RE.findall(line):
                    if ref.startswith(EXTERNAL_PREFIXES):
                        continue
                    if not os.path.exists(os.path.join(REPO_ROOT, ref)):
                        self.err("codepath", doc, ref)

    def check_frontmatter(self) -> None:
        for doc in self.docs:
            if doc in AUTO_GENERATED:
                continue
            fm = self.fm[doc]
            if fm is None:
                self.err("frontmatter", doc, "missing frontmatter block")
                continue
            for field in ("type", "updated", "status"):
                if not fm.get(field):
                    self.err("frontmatter", doc, f"missing '{field}:'")
            status = fm.get("status")
            if status and status not in VALID_STATUS:
                self.err("frontmatter", doc,
                         f"status '{status}' not in {sorted(VALID_STATUS)}")

    def check_tags(self) -> None:
        for doc in self.docs:
            fm = self.fm[doc] or {}
            for tag in fm.get("tags", []) or []:
                if tag not in APPROVED_TAGS:
                    self.err("tags", doc, f"'{tag}' not in approved vocabulary")

    def check_index_coverage(self) -> None:
        """Every doc reachable from its section index, directly or via a sub-overview.

        The hub-of-hubs model is explicitly allowed: an index may link to an
        overview which links to the leaves (as GameSystemsIndex does for
        MapSystem/ and TutorialSystem/).
        """
        for section, index in SECTION_INDEXES.items():
            if index not in self.text:
                self.err("index", index, "section index does not exist")
                continue
            # two-hop closure from the index
            reachable = {index}
            frontier = [index]
            while frontier:
                current = frontier.pop()
                for nxt in self.outbound.get(current, ()):
                    if nxt not in reachable and nxt.startswith(section):
                        reachable.add(nxt)
                        frontier.append(nxt)
            for doc in self.docs:
                if not doc.startswith(section + os.sep):
                    continue
                if self.is_archived(doc):
                    # Tombstones exist so old links land somewhere. Listing them in a
                    # live index is the opposite of retiring them.
                    continue
                if doc not in reachable:
                    self.err("index", doc, f"not reachable from {index}")

    def check_autoload_register(self) -> None:
        """The Autoload Register must list every `[autoload]` entry in project.godot.

        A hand-maintained list of globals is exactly the kind of doc that falls behind
        in silence, so it is checked rather than trusted.
        """
        if AUTOLOAD_REGISTER not in self.text:
            self.err("autoload", AUTOLOAD_REGISTER, "autoload register doc is missing")
            return
        project = os.path.join(REPO_ROOT, "project.godot")
        if not os.path.exists(project):
            return
        names, in_block = [], False
        for line in open(project, encoding="utf8"):
            line = line.strip()
            if line.startswith("["):
                in_block = line == "[autoload]"
                continue
            if in_block and "=" in line:
                names.append(line.split("=", 1)[0].strip())
        body = self.text[AUTOLOAD_REGISTER]
        for name in names:
            if not re.search(rf"`{re.escape(name)}`", body):
                self.err("autoload", AUTOLOAD_REGISTER,
                         f"'{name}' is in project.godot [autoload] but not in the register")

    def check_graph_shape(self) -> None:
        for doc in self.docs:
            if doc in ROOT_EXEMPT and doc != "DocumentationAudit.md":
                continue
            if self.is_archived(doc):
                continue
            if not self.inbound.get(doc):
                self.warn("orphan", doc, "no inbound links")
            if not self.outbound.get(doc):
                self.warn("deadend", doc, "no outbound links (add a '## Related' footer)")

    def check_code_drift(self) -> dict[str, list[str]]:
        """Flag docs whose cited code changed *after* the doc was last verified.

        This is the sharp signal the STALE_DAYS clock only approximates: a doc can
        be 3 days old and already wrong because the file it describes moved
        yesterday. Returns {doc: [code paths that moved since verification]}.

        Docs with no `verified_against_code` are skipped — already covered by the
        stale check, and flagging them twice adds noise, not information.
        """
        basenames = repo_basename_index()
        cited: dict[str, set[str]] = {}
        every_path: set[str] = set()
        for doc in self.docs:
            paths = set()
            for ref in CODEPATH_RE.findall(self.body[doc]):
                if ref.startswith(EXTERNAL_PREFIXES):
                    continue
                if os.path.exists(os.path.join(REPO_ROOT, ref)):
                    paths.add(ref)
            # Bare `foo.gd` citations resolve through the basename index.
            for bare in BARE_CODEFILE_RE.findall(self.body[doc]):
                resolved = basenames.get(bare)
                if resolved:
                    paths.add(resolved)
            if paths:
                cited[doc] = paths
                every_path |= paths

        commit_times = git_last_commit_times(every_path)
        drifted: dict[str, list[str]] = {}
        for doc, paths in cited.items():
            fm = self.fm.get(doc) or {}
            raw = fm.get("verified_against_code")
            if not raw:
                continue
            try:
                verified_ts = int(dt.datetime.fromisoformat(str(raw)).timestamp()) + 86400
            except ValueError:
                continue
            moved = sorted(p for p in paths
                           if commit_times.get(p, 0) > verified_ts)
            if moved:
                drifted[doc] = moved
                shown = ", ".join(moved[:3]) + (f" (+{len(moved) - 3} more)" if len(moved) > 3 else "")
                self.warn("codedrift", doc, f"cited code changed since verification: {shown}")
        return drifted

    def check_staleness(self) -> list[tuple[int, int, str, str]]:
        """Warn on docs not verified against code recently. Returns the backlog."""
        today = dt.date.today()
        backlog = []
        for doc in self.docs:
            fm = self.fm[doc] or {}
            raw = fm.get("verified_against_code")
            inbound = len(self.inbound.get(doc, ()))
            if not raw:
                backlog.append((10_000, inbound, doc, "never"))
                self.warn("stale", doc, "never verified against code")
                continue
            try:
                age = (today - dt.date.fromisoformat(str(raw))).days
            except ValueError:
                self.err("frontmatter", doc, f"verified_against_code '{raw}' is not YYYY-MM-DD")
                continue
            if age > STALE_DAYS:
                backlog.append((age, inbound, doc, str(raw)))
                self.warn("stale", doc, f"verified {age} days ago ({raw})")
        # Code-drift outranks age: a doc whose source demonstrably moved is a
        # known problem, not a maybe. Within each group, most-depended-on first.
        drifted = getattr(self, "drifted", {})
        backlog.sort(key=lambda r: (0 if r[2] in drifted else 1, -r[1], -r[0]))
        return backlog

    # ── driver ───────────────────────────────────────────────────────────────

    def run(self) -> list[tuple[int, int, str, str]]:
        self.check_links_and_anchors()   # must run first: it builds the graph
        self.check_codepaths()
        self.check_frontmatter()
        self.check_tags()
        self.check_index_coverage()
        self.check_autoload_register()
        self.check_graph_shape()
        self.drifted = self.check_code_drift()
        return self.check_staleness()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--strict", action="store_true",
                    help="treat structural warnings (dead ends, orphans) as failures; staleness never fails")
    ap.add_argument("--warnings", action="store_true", help="list every warning")
    ap.add_argument("--backlog", action="store_true",
                    help="print the drift backlog (most-trusted docs first) and exit 0")
    args = ap.parse_args()

    os.chdir(REPO_ROOT)
    check = DocsCheck()
    backlog = check.run()

    if args.backlog:
        print(f"Drift backlog — {len(backlog)} docs need verification against code")
        print(f"{'inbound':>7}  {'age':>6}  doc")
        for age, inbound, doc, last in backlog:
            age_s = "never" if age == 10_000 else f"{age}d"
            print(f"{inbound:>7}  {age_s:>6}  {doc}")
        return 0

    by_check: dict[str, list] = defaultdict(list)
    for name, doc, detail in check.errors:
        by_check[name].append((doc, detail))

    if check.errors:
        print(f"✗ {len(check.errors)} error(s)\n")
        for name in sorted(by_check):
            print(f"  [{name}]")
            for doc, detail in sorted(by_check[name]):
                print(f"    {doc}: {detail}")
            print()
    else:
        print(f"✓ {len(check.docs)} docs — no errors")

    warn_by: dict[str, list] = defaultdict(list)
    for name, doc, detail in check.warnings:
        warn_by[name].append((doc, detail))
    if check.warnings:
        summary = ", ".join(f"{k}={len(v)}" for k, v in sorted(warn_by.items()))
        print(f"⚠ {len(check.warnings)} warning(s): {summary}")
        if args.warnings:
            print()
            for name in sorted(warn_by):
                print(f"  [{name}]")
                for doc, detail in sorted(warn_by[name]):
                    print(f"    {doc}: {detail}")
                print()
        else:
            print("  (re-run with --warnings to list them, --backlog for the drift queue)")

    if check.errors:
        return 1

    # --strict gates *structural* warnings only. Staleness is a rolling backlog,
    # not a defect: failing CI on it would mean the build breaks by the passage of
    # time, and the fix (re-reading source) can't be rushed to unblock a merge.
    if args.strict:
        structural = [w for w in check.warnings if w[0] in ("deadend", "orphan")]
        if structural:
            print(f"\n--strict: {len(structural)} structural warning(s) treated as errors.")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
