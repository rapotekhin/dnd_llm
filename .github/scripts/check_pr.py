"""Verify PR touches game version and release notes (runs in GitHub Actions)."""

from __future__ import annotations

import os
import re
import subprocess
import sys


def _run_git(args: list[str]) -> str:
    r = subprocess.run(
        ["git", *args],
        capture_output=True,
        text=True,
        check=False,
        cwd=os.environ.get("GITHUB_WORKSPACE"),
    )
    if r.returncode != 0:
        print(r.stderr.strip() or r.stdout.strip() or f"git {' '.join(args)} failed")
        sys.exit(1)
    return r.stdout


def _triple_dot_range() -> str:
    base = os.environ.get("PR_BASE_SHA", "").strip()
    head = os.environ.get("PR_HEAD_SHA", "").strip()
    if not base or not head:
        print("ERROR: PR_BASE_SHA and PR_HEAD_SHA must be set (pull_request event).")
        sys.exit(1)
    return f"{base}...{head}"


def check_version_changed(rng: str) -> bool:
    diff = _run_git(["diff", rng, "--", "game/__init__.py"])
    if not diff.strip():
        print("ERROR: game/__init__.py was not changed — bump __version__ for this PR.")
        return False
    if "__version__" not in diff:
        print("ERROR: __version__ in game/__init__.py was not modified.")
        return False
    for line in diff.splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            m = re.search(r'__version__\s*=\s*["\']([^"\']+)["\']', line)
            if m:
                print(f"OK: __version__ set to {m.group(1)} in diff.")
                return True
    print("ERROR: no added __version__ = \"...\" line found in diff.")
    return False


def check_release_notes_changed(rng: str) -> bool:
    names = _run_git(["diff", "--name-only", rng])
    files = {f.strip() for f in names.splitlines() if f.strip()}
    if "RELEASE_NOTES.md" not in files:
        print("ERROR: RELEASE_NOTES.md must be updated in this PR.")
        return False
    print("OK: RELEASE_NOTES.md is among changed files.")
    return True


def main() -> None:
    rng = _triple_dot_range()
    print(f"Checking diff range: {rng}\n")
    ok_v = check_version_changed(rng)
    ok_n = check_release_notes_changed(rng)
    if not (ok_v and ok_n):
        sys.exit(1)
    print("\nAll PR checks passed.")


if __name__ == "__main__":
    main()
