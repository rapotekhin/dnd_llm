"""Verify PR bumps /VERSION and touches release notes (runs in GitHub Actions)."""

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


VERSION_FILE = "VERSION"
_SEMVER = re.compile(r"^\d+\.\d+\.\d+([.-][0-9A-Za-z.-]+)?$")


def check_version_changed(rng: str) -> bool:
    diff = _run_git(["diff", rng, "--", VERSION_FILE])
    if not diff.strip():
        print(f"ERROR: {VERSION_FILE} was not changed — bump the project version for this PR.")
        return False
    for line in diff.splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            version = line[1:].strip()
            if _SEMVER.match(version):
                print(f"OK: version set to {version} in {VERSION_FILE}.")
                return True
    print(f"ERROR: no added semver line (e.g. 0.3.2) found in {VERSION_FILE}.")
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
