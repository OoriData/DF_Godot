#!/usr/bin/env python3
"""Bump `updated:` on staged docs — pre-commit companion to docs_check.py.

The audit (F4) separates two ideas that are easy to conflate:
  updated:                bumped automatically whenever the file changes (this script)
  verified_against_code:  bumped ONLY by a human who re-read the source (never automated)

Automating the second would defeat the purpose — editing prose is not verification.

Install as a git hook:
    ln -sf ../../tools/docs_bump_updated.py .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
"""

from __future__ import annotations

import datetime as dt
import re
import subprocess
import sys

TODAY = dt.date.today().isoformat()


def staged_docs() -> list[str]:
    out = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
        capture_output=True, text=True, check=True).stdout
    return [p for p in out.splitlines() if p.startswith("docs/") and p.endswith(".md")]


def bump(path: str) -> bool:
    try:
        text = open(path, encoding="utf8").read()
    except FileNotFoundError:
        return False
    if not text.startswith("---\n"):
        return False
    end = text.find("\n---", 4)
    if end == -1:
        return False
    head, tail = text[:end], text[end:]
    if re.search(r"^updated:", head, re.M):
        new_head = re.sub(r"^updated:.*$", f"updated: {TODAY}", head, count=1, flags=re.M)
    else:
        new_head = re.sub(r"^(created:.*)$", rf"\1\nupdated: {TODAY}", head, count=1, flags=re.M)
        if new_head == head:
            new_head = head + f"\nupdated: {TODAY}"
    if new_head == head:
        return False
    open(path, "w", encoding="utf8").write(new_head + tail)
    subprocess.run(["git", "add", path], check=True)
    return True


def main() -> int:
    changed = [p for p in staged_docs() if bump(p)]
    for p in changed:
        print(f"docs: bumped updated: -> {TODAY} in {p}")

    result = subprocess.run([sys.executable, "tools/docs_check.py"],
                            capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode != 0:
        print("\ncommit blocked: fix the errors above, or run "
              "`python3 tools/docs_check.py` for detail.", file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
