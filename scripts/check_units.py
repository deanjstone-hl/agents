"""Check units/*.yaml against schema/unit.schema.json and the profiles (agents#11).

Run through scripts/check-units.sh. A unit file pairs a builder and a reviewer into a fire team
and says when the reviewer runs. The structure is checked with the validator and the YAML subset
reader of scripts/check_profiles.py; the pairing rules below it need the profiles.

Every failure prints `units/<file>:<line>: AGUnnn: <message>` and the exit status is 1.

  AGU001  missing required key
  AGU002  unknown key (extensions start with x-)
  AGU003  duplicate key
  AGU004  value does not fit the schema (type, enum, pattern, minimum, items)
  AGU005  file not readable, or a line is not YAML this check reads
  AGU006  a team names a profile that does not exist
  AGU007  builder and reviewer are the same profile
  AGU008  the reviewer can write: its lane is not read-only, or tools.allow lists Edit or Write
  AGU009  the reviewer reports to the builder, so its report would pass through the author
  AGU010  the reviewer takes no diff input
  AGU011  the unit is not the file name
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_profiles as cp  # noqa: E402

REPO = cp.REPO
UNIT_SCHEMA_PATH = os.path.join(REPO, "schema", "unit.schema.json")
TEAM_NAME = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
CODE_MAP = {
    "AGP001": "AGU001",
    "AGP002": "AGU002",
    "AGP003": "AGU003",
    "AGP004": "AGU004",
    "AGP012": "AGU005",
}


def load_unit(path, display, schema, findings):
    """Read and validate one unit file. Returns (mapping, line_of) or (None, None)."""
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except (UnicodeDecodeError, OSError) as exc:
        findings.add(display, 1, "AGU005", f"unreadable ({exc})")
        return None, None
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    scratch = cp.Findings()
    front, key_lines = cp.parse_front_matter([(i + 1, line) for i, line in enumerate(lines)], scratch, display)
    for _, number, code, message in scratch.items:
        findings.add(display, number, CODE_MAP.get(code, "AGU005"), message)

    def line_of(key):
        return key_lines.get(key, 1)

    errors = []
    cp.validate(front, schema, "", errors)
    teams = front.get("fire_teams")
    if isinstance(teams, dict):
        for name, team in teams.items():
            if not TEAM_NAME.match(name):
                errors.append((f"fire_teams.{name}", "AGP004", f"fire_teams.{name}: team name must be lowercase words joined by hyphens"))
            cp.validate(team, schema["x-team"], f"fire_teams.{name}", errors)
    for key_path, code, message in errors:
        findings.add(display, line_of(re.split(r"[.\[]", key_path)[0]), CODE_MAP.get(code, "AGU004"), message)
    return front, line_of


def load_profiles(root):
    """{id: front matter} for every profiles/*.md that parses; problems are the profile check's."""
    with open(cp.SCHEMA_PATH, encoding="utf-8") as handle:
        profile_schema = json.load(handle)
    directory = os.path.join(root, "profiles")
    found = {}
    if not os.path.isdir(directory):
        return found
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".md") or name == "README.md":
            continue
        try:
            with open(os.path.join(directory, name), encoding="utf-8") as handle:
                text = handle.read()
        except (UnicodeDecodeError, OSError):
            continue
        front, _, _ = cp.load_profile(text, profile_schema, f"profiles/{name}", cp.Findings())
        if front is not None:
            found[name[:-3]] = front
    return found


def unit_files(root):
    directory = os.path.join(root, "units")
    if not os.path.isdir(directory):
        return []
    return sorted(name for name in os.listdir(directory) if name.endswith(".yaml"))


def check_team(display, line, name, team, profiles, findings):
    builder, reviewer = team.get("builder"), team.get("reviewer")
    for role, identity in (("builder", builder), ("reviewer", reviewer)):
        if isinstance(identity, str) and identity not in profiles:
            findings.add(display, line, "AGU006", f"team '{name}': {role} '{identity}' is not a profile in profiles/")
    if not (isinstance(builder, str) and isinstance(reviewer, str)):
        return
    if builder == reviewer:
        findings.add(display, line, "AGU007", f"team '{name}': the builder and the reviewer are both '{builder}'")
        return
    front = profiles.get(reviewer)
    if front is None:
        return
    reasons = []
    if front.get("lane") != "read-only":
        reasons.append(f"lane is '{front.get('lane')}', not read-only")
    tools = front.get("tools")
    allow = tools.get("allow") if isinstance(tools, dict) else None
    writers = sorted({cp.tool_name(t) for t in allow if isinstance(t, str) and cp.tool_name(t) in ("Edit", "Write")}) if isinstance(allow, list) else []
    if writers:
        reasons.append(f"tools.allow lists {', '.join(writers)}")
    if reasons:
        findings.add(display, line, "AGU008", f"team '{name}': reviewer '{reviewer}' can write: {'; '.join(reasons)}")
    if front.get("reports_to") == builder:
        findings.add(display, line, "AGU009", f"team '{name}': reviewer '{reviewer}' reports to the builder '{builder}'; its report must not pass through the author")
    inputs = front.get("inputs")
    if not (isinstance(inputs, list) and "diff" in inputs):
        findings.add(display, line, "AGU010", f"team '{name}': reviewer '{reviewer}' does not list diff in inputs")


def main():
    parser = argparse.ArgumentParser(prog="check-units.sh", description=__doc__.split("\n")[0])
    parser.add_argument("--root", default=REPO, help="repository holding units/ and profiles/ (default: this repository)")
    args = parser.parse_args()
    root = os.path.abspath(args.root)

    with open(UNIT_SCHEMA_PATH, encoding="utf-8") as handle:
        schema = json.load(handle)
    profiles = load_profiles(root)
    findings = cp.Findings()
    names = unit_files(root)
    for name in names:
        display = f"units/{name}"
        front, line_of = load_unit(os.path.join(root, "units", name), display, schema, findings)
        if front is None:
            continue
        if isinstance(front.get("unit"), str) and front["unit"] != name[:-5]:
            findings.add(display, line_of("unit"), "AGU011", f"unit '{front['unit']}' is not the file name '{name[:-5]}'")
        teams = front.get("fire_teams")
        if isinstance(teams, dict):
            for team_name, team in teams.items():
                if isinstance(team, dict):
                    check_team(display, line_of("fire_teams"), team_name, team, profiles, findings)

    if findings.items:
        for path, line, code, message in findings.items:
            print(f"{path}:{line}: {code}: {message}", file=sys.stderr)
        files = len({item[0] for item in findings.items})
        print(f"check-units: FAIL: {len(findings)} error(s) in {files} file(s)", file=sys.stderr)
        return 1
    print(f"check-units: {len(names)} unit file(s) ok", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
