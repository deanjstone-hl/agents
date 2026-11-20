"""Whether a change is large enough for its fire team's reviewer (agents#11).

Run through scripts/review-needed.sh, which documents the arguments and the output. Exit status
0 means a decision was printed, 2 means none could be made.
"""

import argparse
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_profiles as cp  # noqa: E402
import check_units as cu  # noqa: E402


def refuse(message):
    print(f"review-needed: {message}", file=sys.stderr)
    return 2


def changed_lines(root, base, head):
    """Added plus deleted lines between two refs, or (None, why)."""
    result = subprocess.run(["git", "-C", root, "diff", "--numstat", base, head], capture_output=True)
    if result.returncode != 0:
        return None, result.stderr.decode("utf-8", "replace").strip() or f"git diff {base} {head} failed"
    total = 0
    for line in result.stdout.decode("utf-8", "replace").split("\n"):
        parts = line.split("\t")
        if len(parts) >= 3 and parts[0] != "-" and parts[1] != "-":
            total += int(parts[0]) + int(parts[1])
    return total, None


def main():
    parser = argparse.ArgumentParser(prog="review-needed.sh", description=__doc__.split("\n")[0])
    parser.add_argument("--root", default=cu.REPO, help="repository holding units/ (default: this repository)")
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--team", default=None, help="the fire team to ask about; needed when several are defined")
    args = parser.parse_args()
    root = os.path.abspath(args.root)

    with open(cu.UNIT_SCHEMA_PATH, encoding="utf-8") as handle:
        schema = json.load(handle)
    findings = cp.Findings()
    teams = []
    names = cu.unit_files(root)
    if not names:
        return refuse(f"no units/*.yaml under {root}: cannot read a threshold")
    for name in names:
        front, _ = cu.load_unit(os.path.join(root, "units", name), f"units/{name}", schema, findings)
        if front and isinstance(front.get("fire_teams"), dict):
            teams.extend((team_name, team) for team_name, team in front["fire_teams"].items() if isinstance(team, dict))
    if findings.items:
        for path, line, code, message in findings.items:
            print(f"{path}:{line}: {code}: {message}", file=sys.stderr)
        return refuse("a unit file is invalid; run scripts/check-units.sh")

    if args.team:
        chosen = [(n, t) for n, t in teams if n == args.team]
        if not chosen:
            return refuse(f"no fire team '{args.team}' (teams: {', '.join(n for n, _ in teams) or 'none'})")
    else:
        chosen = teams
    if len(chosen) != 1:
        return refuse(f"{len(chosen)} fire teams ({', '.join(n for n, _ in chosen)}): name one with --team")
    team_name, team = chosen[0]

    total, why = changed_lines(root, args.base, args.head)
    if total is None:
        return refuse(why)
    threshold = team["threshold"]
    detail = f"{total} changed lines, threshold {threshold}, team {team_name}"
    if total > threshold:
        print(f"required ({detail}): launch {team['reviewer']}")
    else:
        print(f"skip ({detail})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
