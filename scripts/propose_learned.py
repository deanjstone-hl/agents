"""Propose one Learned line to a profile as a branch and a PR to this repo (agents#16, D8).

Run through scripts/propose-learned.sh. An agent never edits its own profile in place: it
runs this from a clean checkout of the agents repo, which adds one line to the profile's
`## Learned` section on a new learned/<profile>-<slug> branch, re-renders generated/, runs the
profile check and commits. Unless --no-pr it then pushes the branch and opens the PR the
owner reviews; merging accepts the line, closing declines it. Every refusal happens before a
branch exists, and a failure after one switches back and deletes it.

Refusals: a profile id that is not a profile name, an unknown profile, an empty or multi-line
line, a source that is not an https URL, a bad date, a line over the length cap, a Learned
section already at the line cap, a line already in Learned, a branch that already exists, and
a tree that is not clean.
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(SCRIPTS, ".."))
SCHEMA_PATH = os.path.join(REPO, "schema", "profile.schema.json")
PROFILE_ID = re.compile(r"^(?:scout|specialist|lead|staff)-[a-z0-9-]+$")
SOURCE = re.compile(r"^https://[^\s()]+$")
HEADING = "## Learned"


class Refusal(Exception):
    pass


def git(root, *args, check=True):
    result = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    if check and result.returncode != 0:
        raise Refusal(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result


def learned_lines(text):
    lines = text.split("\n")
    if HEADING not in lines:
        return []
    start = lines.index(HEADING)
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    return [line.rstrip() for line in lines[start + 1 : end] if line.strip()]


def slugify(text):
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug[:40].strip("-") or "line"


def with_line(text, line):
    body = text.rstrip("\n") + "\n"
    if HEADING not in text.split("\n"):
        body += f"\n{HEADING}\n\n"
    return body + line + "\n"


def run(args):
    root = os.path.abspath(args.root)
    with open(SCHEMA_PATH, encoding="utf-8") as handle:
        spec = json.load(handle)["x-body"]
    max_lines = spec["learnedMaxLines"]
    max_length = spec["learnedMaxLineLength"]

    if not PROFILE_ID.match(args.profile):
        raise Refusal(f"profile id '{args.profile}' is not a profile name like specialist-slot-worker")
    text = " ".join(args.line.split()) if "\n" not in args.line else None
    if text is None:
        raise Refusal("the line must be one line: no newline")
    if not text:
        raise Refusal("the line is empty")
    if not SOURCE.match(args.source):
        raise Refusal("the source must be an https URL the owner can open (an issue, comment, PR or log)")
    date = args.date or datetime.date.today().isoformat()
    try:
        datetime.date.fromisoformat(date)
    except ValueError:
        raise Refusal(f"the date '{date}' is not YYYY-MM-DD") from None
    line = f"- {date}: {text} ([source]({args.source}))"
    if len(line) > max_length:
        raise Refusal(f"the Learned line is {len(line)} characters, the cap is {max_length}: shorten the text")

    if git(root, "status", "--porcelain").stdout.strip():
        raise Refusal("the working tree is not clean: commit or stash first, so the proposal commit holds only the proposal")

    original = git(root, "symbolic-ref", "--quiet", "--short", "HEAD", check=False).stdout.strip()
    if args.no_pr:
        start = "HEAD"
    else:
        git(root, "fetch", "origin", "main")
        start = "origin/main"
    start_sha = git(root, "rev-parse", "--verify", f"{start}^{{commit}}").stdout.strip()

    path = f"profiles/{args.profile}.md"
    shown = git(root, "show", f"{start_sha}:{path}", check=False)
    if shown.returncode != 0:
        raise Refusal(f"no such profile: {path} is not in {start}")
    existing = learned_lines(shown.stdout)
    if len(existing) >= max_lines:
        raise Refusal(f"{args.profile} already has {len(existing)} Learned lines and the cap is {max_lines}: the owner prunes a line first")
    if any(f": {text.lower()} ([source](" in current.lower() for current in existing):
        raise Refusal(f"that line is already in the Learned section of {args.profile}")

    branch = f"learned/{args.profile}-{slugify(text)}"
    if git(root, "show-ref", "--verify", "--quiet", f"refs/heads/{branch}", check=False).returncode == 0:
        raise Refusal(f"branch {branch} already exists: an earlier proposal of this line is still open or not cleaned up")

    git(root, "switch", "-q", "-c", branch, start_sha)
    try:
        with open(os.path.join(root, path), "w", encoding="utf-8") as handle:
            handle.write(with_line(shown.stdout, line))
        rendered = subprocess.run(["python3", "-I", os.path.join(SCRIPTS, "render.py"), "--root", root], capture_output=True, text=True)
        if rendered.returncode != 0:
            raise Refusal(f"render failed: {rendered.stderr.strip()}")
        checked = subprocess.run(
            ["python3", "-I", os.path.join(SCRIPTS, "check_profiles.py"), "--root", root, "--base", start_sha],
            capture_output=True, text=True,
        )
        if checked.returncode != 0:
            raise Refusal(f"the profile check failed:\n{checked.stderr.strip()}")
        touched = {
            row[3:].strip()
            for row in git(root, "status", "--porcelain").stdout.splitlines()
        }
        allowed = {path, f"generated/agents/{args.profile}.md", f"generated/briefs/{args.profile}.md"}
        if not touched <= allowed:
            raise Refusal(f"the render changed files beyond the profile's own ({', '.join(sorted(touched - allowed))}): generated/ was stale on the base")
        git(root, "add", "--", *sorted(touched))
        message = (
            f"docs: propose a Learned line for {args.profile}\n\n"
            f"{line}\n\n"
            "Proposed by an agent for the owner's review (agents#1 D8). The profile is not edited in place: "
            "merging this accepts the line, closing it declines it.\n"
        )
        git(root, "commit", "-q", "-m", message)
    except BaseException:
        git(root, "restore", "--source=HEAD", "--staged", "--worktree", "--", ".", check=False)
        git(root, "switch", "-q", original or start_sha, check=False)
        git(root, "branch", "-q", "-D", branch, check=False)
        raise

    print(f"propose-learned: committed {branch} with one line for {args.profile}", file=sys.stderr)
    if args.no_pr:
        print(f"propose-learned: --no-pr: push {branch} and open the PR to main yourself", file=sys.stderr)
        return 0

    body = (
        "## Summary\n\n"
        f"One Learned line for `{args.profile}`:\n\n> {line}\n\n"
        "## Why\n\n"
        f"Source: {args.source}\n\n"
        "## Review\n\n"
        "- Merge to accept the line; close to decline it. A profile never edits itself in place (agents#1 D8).\n"
        "- CI checks the shape (`scripts/check-learned.sh`: one line, one profile, nothing else) and the cap "
        "(`scripts/check-profiles.sh`: 10 lines of at most 200 characters).\n\n"
        "README: not needed because the change is one Learned line, not setup, commands or behaviour.\n"
    )
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as handle:
        handle.write(body)
        body_file = handle.name
    try:
        git(root, "push", "-u", "origin", branch)
        created = subprocess.run(
            ["gh", "pr", "create", "--base", "main", "--head", branch, "--title",
             f"docs: propose a Learned line for {args.profile}", "--body-file", body_file],
            cwd=root, capture_output=True, text=True,
        )
    finally:
        os.unlink(body_file)
    if created.returncode != 0:
        raise Refusal(f"the branch is pushed but gh pr create failed: {created.stderr.strip()}")
    print(created.stdout.strip())
    return 0


def main():
    parser = argparse.ArgumentParser(prog="propose-learned.sh", description=__doc__.split("\n")[0])
    parser.add_argument("--root", default=os.getcwd(), help="clean checkout of the agents repo (default: the current directory)")
    parser.add_argument("--profile", required=True, help="the proposing agent's own profile id, e.g. specialist-slot-worker")
    parser.add_argument("--line", required=True, help="the lesson, one line of plain text")
    parser.add_argument("--source", required=True, help="https URL of the owner's correction or the evidence")
    parser.add_argument("--date", default=None, help="YYYY-MM-DD (default today)")
    parser.add_argument("--no-pr", action="store_true", help="commit the branch locally; do not fetch, push or open the PR")
    args = parser.parse_args()
    try:
        return run(args)
    except Refusal as refusal:
        print(f"propose-learned: refused: {refusal}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
