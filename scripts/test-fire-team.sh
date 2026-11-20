#!/usr/bin/env bash
# Tests for the builder + reviewer fire team (agents#11), written before the code: the unit
# file check (scripts/check-units.sh), the size trigger (scripts/review-needed.sh) and the
# real specialist-reviewer profile. Each fixture case builds a throwaway git repo and runs the
# scripts against it with --root, so no broken fixture is ever a tracked file of this repo.
# Run by check.sh. Needs only bash, git and python3.
set -euo pipefail

builtin cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo=$PWD
unset PROFILE_BASE
checker="$repo/scripts/check-units.sh"
trigger="$repo/scripts/review-needed.sh"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

cases=0
failed=0
fx=""
rc=0
out=""

fail() {
  echo "test-fire-team: FAIL: $1" >&2
  failed=$((failed + 1))
}

new_fixture() {
  cases=$((cases + 1))
  fx="$scratch/fx$cases"
  mkdir -p "$fx/profiles" "$fx/units"
  git -C "$fx" init -q -b main
  git -C "$fx" config user.email test@example.invalid
  git -C "$fx" config user.name test
}

sections() {
  cat <<'EOF'

## Mission

Do the job.

## Owns

- The job.

## Boundaries

- No live systems.

## Procedure

1. Do it.

## Done means

- It is done.

## Report format

Result, evidence, open questions.
EOF
}

# put_profile <id> <lane> <allow list> <inputs list> <reports_to>
put_profile() {
  local id=$1 lane=$2 allow=$3 inputs=$4 reports_to=$5
  {
    cat <<EOF
---
id: $id
version: "1.0"
section: fire-team
rank: specialist
mission: Stand in for a $id.
reports_to: $reports_to
lane: $lane
model: auto
tools:
  allow: $allow
  deny: []
inputs: $inputs
outputs: [report]
escalates_to: staff-xo
---
EOF
    sections
  } >"$fx/profiles/$id.md"
}

# A fixture holding a valid builder, a valid reviewer and a valid unit file.
valid_fixture() {
  new_fixture
  put_profile specialist-worker write "[Read, Grep, Glob, Bash, Edit, Write]" "[issue_text]" staff-xo
  put_profile specialist-reviewer read-only "[Read, Grep, Glob, Bash]" "[issue_text, diff]" staff-xo
  valid_unit >"$fx/units/aquila.yaml"
}

valid_unit() {
  cat <<'EOF'
# The fire team is a buddy-pair analogy, not the doctrinal four-member team.
unit: aquila
version: "1.0"
fire_teams:
  slot:
    builder: specialist-worker
    reviewer: specialist-reviewer
    trigger: changed-lines
    threshold: 300
    gate: [ci, verify-claim]
EOF
}

put_unit() {
  cat >"$fx/units/aquila.yaml"
}

run_check() {
  rc=0
  out=$(bash "$checker" --root "$fx" "$@" 2>&1) || rc=$?
}

expect_pass() {
  local name=$1
  shift
  run_check "$@"
  if [ "$rc" -ne 0 ]; then
    fail "$name: expected pass, got exit $rc: $out"
  fi
}

# expect_fail <name> <string the output must carry>
expect_fail() {
  local name=$1 needle=$2
  shift 2
  run_check "$@"
  if [ "$rc" -eq 0 ]; then
    fail "$name: expected a failure, got exit 0: $out"
  elif [ "$rc" -eq 127 ] || ! grep -qF -- "$needle" <<<"$out"; then
    fail "$name: exit $rc without '$needle' in: $out"
  fi
}

# --- the unit file check -----------------------------------------------------------------

cases=$((cases + 1))
[ -f schema/unit.schema.json ] || fail "schema/unit.schema.json does not exist"

new_fixture
rmdir "$fx/units"
expect_pass "no units directory"
grep -qF "0 unit file(s) ok" <<<"$out" || fail "no units: summary line missing: $out"

valid_fixture
expect_pass "a valid unit file"
grep -qF "1 unit file(s) ok" <<<"$out" || fail "valid unit: summary line missing: $out"

valid_fixture
sed -i 's/^unit: aquila$/unit: aquila\nx-note: free text/' "$fx/units/aquila.yaml"
expect_pass "an x- key is allowed"

valid_fixture
sed -i 's/^reviewer: .*//; s/reviewer: specialist-reviewer/reviewer: specialist-ghost/' "$fx/units/aquila.yaml"
expect_fail "a reviewer that is not a profile" "AGU006"

valid_fixture
sed -i 's/builder: specialist-worker/builder: specialist-ghost/' "$fx/units/aquila.yaml"
expect_fail "a builder that is not a profile" "AGU006"

valid_fixture
sed -i 's/reviewer: specialist-reviewer/reviewer: specialist-worker/' "$fx/units/aquila.yaml"
expect_fail "the builder reviewing its own work" "AGU007"

valid_fixture
put_profile specialist-reviewer write "[Read, Grep, Glob, Bash]" "[issue_text, diff]" staff-xo
expect_fail "a reviewer with a write lane" "AGU008"

valid_fixture
put_profile specialist-reviewer read-only "[Read, Grep, Glob, Bash, Edit]" "[issue_text, diff]" staff-xo
expect_fail "a reviewer that lists Edit" "AGU008"

valid_fixture
put_profile specialist-reviewer read-only "[Read, Grep, Glob, Bash, Write]" "[issue_text, diff]" staff-xo
expect_fail "a reviewer that lists Write" "AGU008"

valid_fixture
put_profile specialist-reviewer read-only "[Read, Grep, Glob, Bash]" "[issue_text, diff]" specialist-worker
expect_fail "a reviewer whose report goes through the builder" "AGU009"

valid_fixture
put_profile specialist-reviewer read-only "[Read, Grep, Glob, Bash]" "[issue_text]" staff-xo
expect_fail "a reviewer that takes no diff" "AGU010"

valid_fixture
sed -i '/^    gate:/d' "$fx/units/aquila.yaml"
expect_fail "a fire team with no gate" "AGU001"

valid_fixture
sed -i 's/gate: \[ci, verify-claim\]/gate: []/' "$fx/units/aquila.yaml"
expect_fail "an empty gate: a reviewer must never be the only check" "AGU004"

valid_fixture
sed -i 's/threshold: 300/threshold: 0/' "$fx/units/aquila.yaml"
expect_fail "a threshold of zero" "AGU004"

valid_fixture
sed -i 's/threshold: 300/threshold: "300"/' "$fx/units/aquila.yaml"
expect_fail "a threshold that is a string" "AGU004"

valid_fixture
sed -i 's/trigger: changed-lines/trigger: every-pr/' "$fx/units/aquila.yaml"
expect_fail "a trigger that is not changed-lines" "AGU004"

valid_fixture
sed -i 's/^version: .*/surprise: 1/' "$fx/units/aquila.yaml"
expect_fail "an unknown key and a missing version" "AGU002"

valid_fixture
sed -i 's/^unit: aquila$/unit: aquila\nunit: other/' "$fx/units/aquila.yaml"
expect_fail "a duplicate key" "AGU003"

valid_fixture
printf 'this is not a mapping\n' >>"$fx/units/aquila.yaml"
expect_fail "a line that is not key: value" "AGU005"

valid_fixture
sed -i 's/^unit: aquila$/unit: other/' "$fx/units/aquila.yaml"
expect_fail "a unit that is not the file name" "AGU011"

valid_fixture
sed -i 's/^fire_teams:$/fire_teams: none/' "$fx/units/aquila.yaml"
expect_fail "fire_teams that is not a mapping" "AGU004"

valid_fixture
sed -i 's/^  slot:$/  Slot_Team:/' "$fx/units/aquila.yaml"
expect_fail "a team name that is not lowercase words" "AGU004"

valid_fixture
sed -i 's/^    gate: .*$/    gate: [ci, verify-claim]\n    model: opus/' "$fx/units/aquila.yaml"
expect_fail "an unknown key inside a team" "AGU002"

# --- the size trigger --------------------------------------------------------------------

# lines_commit <file> <count>: append count lines to a file and commit it
lines_commit() {
  local file=$1 count=$2
  for ((i = 0; i < count; i++)); do echo "line $i of $file"; done >>"$fx/$file"
  git -C "$fx" add -A
  git -C "$fx" commit -q -m "add $count lines to $file"
}

run_trigger() {
  rc=0
  out=$(bash "$trigger" --root "$fx" "$@" 2>&1) || rc=$?
}

# expect_trigger <name> <required|skip> <number of lines the output must carry> [args]
expect_trigger() {
  local name=$1 verdict=$2 lines=$3
  shift 3
  run_trigger "$@"
  if [ "$rc" -ne 0 ]; then
    fail "$name: exit $rc: $out"
  elif [ "$(awk '{print $1; exit}' <<<"$out")" != "$verdict" ]; then
    fail "$name: expected '$verdict' first, got: $out"
  elif ! grep -qF -- "$lines changed lines" <<<"$out" || ! grep -qF "threshold 300" <<<"$out"; then
    fail "$name: output carries neither '$lines changed lines' nor 'threshold 300': $out"
  fi
}

valid_fixture
for ((i = 0; i < 50; i++)); do echo "old line $i"; done >"$fx/old.txt"
git -C "$fx" add -A
git -C "$fx" commit -q -m base
base=$(git -C "$fx" rev-parse HEAD)

lines_commit a.txt 300
expect_trigger "exactly the threshold is not large" skip 300 --base "$base" --head HEAD

lines_commit b.txt 1
expect_trigger "one line over the threshold is large" required 301 --base "$base" --head HEAD

sed -i '1,10d' "$fx/old.txt"
git -C "$fx" add -A
git -C "$fx" commit -q -m "delete 10 lines"
expect_trigger "deleted lines count too" required 311 --base "$base" --head HEAD

head=$(git -C "$fx" rev-parse HEAD)
expect_trigger "an explicit team name" required 311 --base "$base" --head "$head" --team slot

valid_fixture
git -C "$fx" add -A
git -C "$fx" commit -q -m base
base=$(git -C "$fx" rev-parse HEAD)
head -c 4096 /dev/urandom >"$fx/blob.bin"
lines_commit small.txt 5
expect_trigger "a binary file counts as no lines" skip 5 --base "$base" --head HEAD

run_trigger --base "$base" --head HEAD --team nope
if [ "$rc" -ne 2 ] || ! grep -qF "nope" <<<"$out"; then
  fail "an unknown team: expected exit 2 naming it, got $rc: $out"
fi

run_trigger --base "no-such-ref" --head HEAD
if [ "$rc" -ne 2 ]; then
  fail "an unknown base ref: expected exit 2, got $rc: $out"
fi

new_fixture
git -C "$fx" commit -q --allow-empty -m base
run_trigger --base HEAD --head HEAD
if [ "$rc" -ne 2 ] || ! grep -qF "units" <<<"$out"; then
  fail "no unit file: expected exit 2 naming units, got $rc: $out"
fi

valid_fixture
cat >>"$fx/units/aquila.yaml" <<'EOF'
  second:
    builder: specialist-worker
    reviewer: specialist-reviewer
    trigger: changed-lines
    threshold: 50
    gate: [ci]
EOF
git -C "$fx" add -A
git -C "$fx" commit -q -m base
run_trigger --base HEAD --head HEAD
if [ "$rc" -ne 2 ] || ! grep -qF -- "--team" <<<"$out"; then
  fail "two teams and no --team: expected exit 2 asking for --team, got $rc: $out"
fi

# --- the real reviewer profile -----------------------------------------------------------

reviewer=profiles/specialist-reviewer.md

cases=$((cases + 1))
if [ ! -f "$reviewer" ]; then
  fail "$reviewer does not exist"
else
  python3 -I - "$reviewer" <<'PY' || fail "$reviewer: wrong content (see above)"
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
front, body = text.split("\n---\n", 1)
errors = []


def need(condition, message):
    if not condition:
        errors.append(message)


def line(key):
    match = re.search(rf"^{key}: *(.*)$", front, re.M)
    return match.group(1).strip() if match else ""


need(line("id") == "specialist-reviewer", "id is not specialist-reviewer")
need(line("rank") == "specialist", "rank is not specialist")
need(line("section") == "fire-team", "section is not fire-team")
need(line("lane") == "read-only", "lane is not read-only")
need(line("reports_to") == "staff-xo", "reports_to is not staff-xo")
inputs = line("inputs")
need("issue_text" in inputs and "diff" in inputs, "inputs lack issue_text or diff")
allow = re.search(r"^  allow: *(.*)$", front, re.M)
need(allow is not None, "tools.allow is missing")
if allow:
    for tool in ("Read", "Grep", "Glob", "Bash"):
        need(tool in allow.group(1), f"tools.allow lacks {tool}: the reviewer reads and must run the checks")
    for tool in ("Edit", "Write", "WebFetch"):
        need(tool not in allow.group(1), f"tools.allow lists {tool}")
deny = re.search(r"^  deny: *(.*)$", front, re.M)
need(deny is not None and "Edit" in deny.group(1) and "Write" in deny.group(1), "tools.deny must list Edit and Write")

sections = dict(re.findall(r"^## (.+)\n((?:(?!## ).*\n?)*)", body, re.M))
report = sections.get("Report format", "")
for verdict in ("PASS", "ISSUES", "BLOCKED"):
    need(verdict in report, f"Report format does not define {verdict}")
need("changed-lines" in sections.get("Boundaries", "") or "300" in body, "the size trigger is not stated")
boundaries = sections.get("Boundaries", "")
need(re.search(r"sole gate|only gate", boundaries, re.I), "Boundaries do not say the reviewer is never the sole gate")
need("verify-claim" in body and "CI" in body, "the body does not name CI and verify-claim as the gate")
need("clean context" in body.lower(), "the body does not state the clean-context rule")
need(re.search(r"verbatim", body, re.I), "the body does not say the issue text is verbatim")
need(re.search(r"not (the )?author|author's (summary|narrative|claims?)", body, re.I), "the body does not discount the author's narrative")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY
fi

cases=$((cases + 1))
issue="$scratch/issue.txt"
diff_file="$scratch/changes.diff"
printf 'ISSUE-TEXT-MARKER: fix the thing exactly as written\nsecond line\n' >"$issue"
printf 'diff --git a/x b/x\n+DIFF-MARKER\n' >"$diff_file"
printf '/home/user/.t3/worktrees/example/review-head\n' >"$scratch/checkout.txt"
brief_out="$scratch/brief.out"
if ! bash scripts/render.sh --brief specialist-reviewer --issue-file "$issue" --input diff="$diff_file" --input checkout="$scratch/checkout.txt" >"$brief_out" 2>"$scratch/brief.err"; then
  fail "render.sh --brief specialist-reviewer failed: $(cat "$scratch/brief.err")"
else
  grep -qF "ISSUE-TEXT-MARKER: fix the thing exactly as written" "$brief_out" || fail "the rendered reviewer brief lacks the issue text"
  grep -qF "DIFF-MARKER" "$brief_out" || fail "the rendered reviewer brief lacks the diff"
  grep -qF "example/review-head" "$brief_out" || fail "the rendered reviewer brief lacks the checkout path"
fi

cases=$((cases + 1))
fx=$repo
run_check
if [ "$rc" -ne 0 ]; then
  fail "the real unit files do not pass check-units.sh (run against the repo): $out"
fi
[ -f units/aquila.yaml ] || fail "units/aquila.yaml does not exist"

# --- check.sh runs it --------------------------------------------------------------------

cases=$((cases + 1))
grep -q 'scripts/check-units.sh' scripts/check.sh || fail "scripts/check.sh does not run check-units.sh"
grep -q 'scripts/test-fire-team.sh' scripts/check.sh || fail "scripts/check.sh does not run test-fire-team.sh"

if [ "$failed" -ne 0 ]; then
  echo "test-fire-team: $failed failure(s) in $cases case(s)" >&2
  exit 1
fi
echo "test-fire-team: ok ($cases cases)"
