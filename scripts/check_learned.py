"""Check that a Learned-line proposal has the shape D8 allows (agents#16).

Run through scripts/check-learned.sh. A proposal is one pull request to this repo that adds
one line to one profile's `## Learned` section; the owner reviews it. A profile never edits
itself in place. This check reads the committed change from the merge base with the base ref
to HEAD and fails unless it is exactly that. The cap on the section (10 lines of at most 200
characters) is not checked here: scripts/check-profiles.sh enforces it (AGP010) in check.sh.

It runs on a proposal only: with --proposal, with LEARNED_PROPOSAL=1 (CI sets it for a pull
request whose head branch starts with learned/), or on a local branch named learned/*.
Anywhere else it prints a note and passes, so the owner can still edit Learned lines on trunk.

Every failure prints `<path>: LRNnnn: <message>` and the exit status is 1.

  LRN001  a file other than the profile and its two generated files changed
  LRN002  more than one profile changed
  LRN003  the profile changed outside its Learned section, or was added or deleted
  LRN004  Learned did not gain exactly one line at the end with the others untouched
  LRN005  the new line is not `- YYYY-MM-DD: <text> ([source](https://<url>))`
  LRN006  the change holds no Learned line
"""

import argparse
import datetime
import os
import re
import subprocess
import sys

DEFAULT_BASE = "origin/main"
HEADING = "## Learned"
LINE_FORMAT = re.compile(r"^- (\d{4}-\d{2}-\d{2}): (\S.*) \(\[source\]\((https://[^\s()]+)\)\)$")
PROFILE_PATH = re.compile(r"^profiles/((?:scout|specialist|lead|staff)-[a-z0-9-]+)\.md$")


def git(root, *args):
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)


def is_proposal(root, flag):
    if flag or os.environ.get("LEARNED_PROPOSAL") == "1":
        return True
    branch = git(root, "symbolic-ref", "--quiet", "--short", "HEAD")
    return branch.returncode == 0 and branch.stdout.strip().startswith("learned/")


def split_learned(text):
    """Returns (before, learned lines, after) as lists of rstripped non-trailing-blank lines."""
    lines = [line.rstrip() for line in text.split("\n")]
    if HEADING not in lines:
        return trim(lines), [], []
    start = lines.index(HEADING)
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    learned = [line for line in lines[start + 1 : end] if line.strip()]
    return trim(lines[:start]), learned, trim(lines[end:])


def trim(lines):
    out = list(lines)
    while out and not out[-1].strip():
        out.pop()
    return out


def main():
    parser = argparse.ArgumentParser(prog="check-learned.sh", description=__doc__.split("\n")[0])
    parser.add_argument("--root", default=os.getcwd(), help="repository to check (default: the current directory)")
    parser.add_argument("--base", default=None, help=f"ref the proposal is compared with (default {DEFAULT_BASE}; env PROFILE_BASE)")
    parser.add_argument("--proposal", action="store_true", help="treat the change as a proposal whatever the branch is called")
    args = parser.parse_args()
    root = os.path.abspath(args.root)

    if not is_proposal(root, args.proposal):
        print("check-learned: not a proposal (no --proposal, LEARNED_PROPOSAL=1 or learned/ branch); skipped", file=sys.stderr)
        return 0

    base = args.base or os.environ.get("PROFILE_BASE") or DEFAULT_BASE
    if git(root, "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}").returncode != 0:
        print(f"check-learned: FAIL: base '{base}' not found: cannot read the proposal", file=sys.stderr)
        return 1
    merge_base = git(root, "merge-base", base, "HEAD")
    point = merge_base.stdout.strip() if merge_base.returncode == 0 and merge_base.stdout.strip() else base

    diff = git(root, "diff", "--name-status", "--no-renames", point, "HEAD")
    if diff.returncode != 0:
        print(f"check-learned: FAIL: git diff failed: {diff.stderr.strip()}", file=sys.stderr)
        return 1
    changes = []
    for row in diff.stdout.splitlines():
        status, _, path = row.partition("\t")
        changes.append((status[:1], path))

    findings = []

    def add(path, code, message):
        findings.append((path, code, message))

    profiles = [(status, path) for status, path in changes if PROFILE_PATH.match(path)]
    ids = {PROFILE_PATH.match(path).group(1) for _, path in profiles}
    allowed = {f"profiles/{i}.md" for i in ids} | {f"generated/agents/{i}.md" for i in ids} | {f"generated/briefs/{i}.md" for i in ids}
    for _, path in changes:
        if path not in allowed:
            add(path, "LRN001", "a proposal changes only one profile and its two generated files")

    if not profiles:
        add("profiles", "LRN006", "the change holds no Learned line: no profile changed")
    elif len(profiles) > 1:
        add("profiles", "LRN002", f"{len(profiles)} profiles changed ({', '.join(sorted(ids))}); a proposal is one line for one profile")
    else:
        status, path = profiles[0]
        if status != "M":
            add(path, "LRN003", "a proposal changes an existing profile; it does not add or delete one")
        else:
            old = git(root, "show", f"{point}:{path}").stdout
            new = git(root, "show", f"HEAD:{path}").stdout
            old_before, old_learned, old_after = split_learned(old)
            new_before, new_learned, new_after = split_learned(new)
            if old_before != new_before or old_after != new_after:
                add(path, "LRN003", "the profile changed outside its Learned section; the owner changes the rest, not a proposal")
            if new_learned[: len(old_learned)] != old_learned or len(new_learned) != len(old_learned) + 1:
                add(
                    path, "LRN004",
                    f"Learned went from {len(old_learned)} to {len(new_learned)} line(s); a proposal adds exactly one line at the end "
                    "and leaves the others as they are",
                )
            elif new_learned == old_learned:
                add(path, "LRN006", "the change holds no Learned line")
            else:
                added = new_learned[-1]
                match = LINE_FORMAT.match(added)
                valid_date = False
                if match:
                    try:
                        datetime.date.fromisoformat(match.group(1))
                        valid_date = True
                    except ValueError:
                        valid_date = False
                if not (match and valid_date):
                    add(path, "LRN005", "the new line must be '- YYYY-MM-DD: <text> ([source](https://<url>))' with a real date")

    if findings:
        for path, code, message in findings:
            print(f"{path}: {code}: {message}", file=sys.stderr)
        print(f"check-learned: FAIL: {len(findings)} error(s)", file=sys.stderr)
        return 1
    print("check-learned: proposal ok (one Learned line)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
