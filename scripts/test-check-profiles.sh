#!/usr/bin/env bash
# Tests for scripts/check-profiles.sh (agents#8), written before the checker. Each case builds
# a throwaway git repo with a profiles/ directory and runs the checker against it with
# --root, so no broken fixture is ever a tracked file of this repo. Run by check.sh.
# Needs only bash, git and python3.
set -euo pipefail

builtin cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo=$PWD
# CI exports PROFILE_BASE for the real repo; a fixture has its own history.
unset PROFILE_BASE
checker="$repo/scripts/check-profiles.sh"
schema="$repo/schema/profile.schema.json"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

cases=0
failed=0
fx=""
rc=0
out=""

fail() {
  echo "test-check-profiles: FAIL: $1" >&2
  failed=$((failed + 1))
}

# A fresh fixture repo on branch main with an empty profiles/ directory.
new_fixture() {
  cases=$((cases + 1))
  fx="$scratch/fx$cases"
  mkdir -p "$fx/profiles"
  git -C "$fx" init -q -b main
  git -C "$fx" config user.email test@example.invalid
  git -C "$fx" config user.name test
}

commit_fixture() {
  git -C "$fx" add -A
  git -C "$fx" commit -q -m "fixture"
}

# The six required sections, then the optional ones appended by the caller.
required_sections() {
  cat <<'EOF'
## Mission

Review one large diff against the issue text.

## Owns

- The review report.

## Boundaries

- Do not commit. No live systems.

## Procedure

1. Read the issue text and the diff.
2. Run the checks.

## Done means

- Every changed file was read.

## Report format

Result, evidence, open questions.
EOF
}

# A valid profile: valid_text [rank] [role]
valid_text() {
  local rank=${1:-specialist} role=${2:-reviewer} allow="[Read, Grep, Glob, Bash]"
  # A scout stays inside its ceiling (doctrine/units.md, Rank ceiling): no Bash.
  if [ "$rank" = scout ]; then allow="[Read, Grep, Glob]"; fi
  cat <<EOF
---
id: $rank-$role
version: "1.0"
section: S3
rank: $rank
mission: Review one large diff against the issue text and report PASS, ISSUES or BLOCKED.
reports_to: staff-xo
lane: read-only
model: auto
skills: [tdd]
tools:
  allow: $allow
  deny: [Edit, Write]
inputs: [issue_text, diff]
outputs: [report]
escalates_to: owner
---

EOF
  required_sections
}

# put <profile-id>: stdin becomes profiles/<profile-id>.md
put() {
  cat >"$fx/profiles/$1.md"
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

# expect_fail <name> <fixed string the output must carry> [checker args]
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

# --- the schema file ---------------------------------------------------------------------

cases=$((cases + 1))
if [ ! -f "$schema" ]; then
  fail "schema/profile.schema.json does not exist"
else
  python3 -I - "$schema" <<'PY' || fail "schema/profile.schema.json: wrong content (see above)"
import json
import sys

schema = json.load(open(sys.argv[1]))
props = schema["properties"]
errors = []
if props["rank"]["enum"] != ["scout", "specialist", "lead", "staff"]:
    errors.append("rank enum is not exactly scout, specialist, lead, staff")
if props["runtime"]["default"] != "claude" or props["runtime"]["enum"] != ["claude"]:
    errors.append("runtime must default to claude and accept only claude (D7)")
if "runtime" in schema["required"]:
    errors.append("runtime must be optional")
body = schema["x-body"]
if body["sections"] != ["Mission", "Owns", "Boundaries", "Procedure", "Done means", "Report format"]:
    errors.append("x-body.sections is not the D3 layout")
if body["voiceMaxLines"] != 3:
    errors.append("voiceMaxLines is not 3")
if not isinstance(body["learnedMaxLines"], int) or body["learnedMaxLines"] < 1:
    errors.append("learnedMaxLines is not a positive integer")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY
fi

# --- valid profiles ----------------------------------------------------------------------

new_fixture
expect_pass "no profiles at all"
grep -qF "0 profile(s) ok" <<<"$out" || fail "no profiles: summary line missing: $out"

for rank in scout specialist lead staff; do
  new_fixture
  valid_text "$rank" worker | put "$rank-worker"
  expect_pass "a $rank profile is valid"
done

new_fixture
valid_text | put specialist-reviewer
expect_pass "a valid profile passes"
grep -qF "1 profile(s) ok" <<<"$out" || fail "valid: summary line missing: $out"

new_fixture
valid_text | sed 's/^lane: .*/lane: read-only\nx-note: free text for a renderer to ignore/' | put specialist-reviewer
expect_pass "an x- key is allowed and ignored"

new_fixture
valid_text | sed '/^skills:/d' | put specialist-reviewer
expect_pass "skills is optional"

new_fixture
valid_text | sed -e 's/^  allow: .*$/  allow:\n    - Read\n    - Grep/' | put specialist-reviewer
expect_pass "a block list is read like a flow list"

new_fixture
{
  valid_text
  printf '\n## Voice\n\nPlain.\nEvidence first.\nNo flourish.\n'
} | put specialist-reviewer
expect_pass "a Voice of three lines"

new_fixture
{
  valid_text
  printf '\n## Voice\n\nPlain.\n\n## Learned\n\n- 2026-11-21: one lesson ([source](https://example.invalid/1))\n'
} | put specialist-reviewer
expect_pass "Voice then Learned after the six sections"

# --- missing, unknown and duplicate fields -----------------------------------------------

for key in id version section rank mission reports_to lane model tools inputs outputs escalates_to; do
  new_fixture
  if [ "$key" = tools ]; then
    valid_text | sed -e '/^tools:$/,/^  deny:/d' | put specialist-reviewer
  else
    valid_text | sed "/^$key:/d" | put specialist-reviewer
  fi
  expect_fail "missing $key" "AGP001"
  grep -qF "$key" <<<"$out" || fail "missing $key: the message does not name the key: $out"
done

new_fixture
valid_text | sed 's/^lane: .*/lane: read-only\nbonus: 1/' | put specialist-reviewer
expect_fail "an unknown key" "AGP002"

new_fixture
valid_text | sed 's/^lane: .*/lane: read-only\nlane: write/' | put specialist-reviewer
expect_fail "a duplicate key" "AGP003"

new_fixture
valid_text | awk 'n >= 2 { print } /^---$/ { n++ }' | put specialist-reviewer
expect_fail "no front matter" "AGP012"

new_fixture
valid_text | awk '/^---$/ { n++; if (n == 2) { print "x: y"; next } } { print }' | put specialist-reviewer
expect_fail "unclosed front matter" "AGP012"

# --- ranks, ids, enums -------------------------------------------------------------------

new_fixture
valid_text sergeant reviewer | put sergeant-reviewer
expect_fail "an unknown rank" "AGP004"
grep -qF "rank" <<<"$out" || fail "unknown rank: the message does not name rank: $out"

new_fixture
valid_text specialist reviewer | sed 's/^rank: .*/rank: lead/' | put specialist-reviewer
expect_fail "an id prefix that is not the rank" "AGP006"

new_fixture
valid_text specialist reviewer | put specialist-other
expect_fail "an id that is not the file name" "AGP005"

new_fixture
valid_text | sed 's/^lane: .*/lane: readwrite/' | put specialist-reviewer
expect_fail "a lane outside the enum" "AGP004"

new_fixture
valid_text | sed 's/^section: .*/section: S5/' | put specialist-reviewer
expect_fail "a section outside the enum" "AGP004"

new_fixture
valid_text | sed 's/^version: .*/version: 1.0/' | put specialist-reviewer
expect_fail "an unquoted version" "AGP004"

new_fixture
valid_text | sed 's/^id: .*/id: specialist-Reviewer/' | put specialist-reviewer
expect_fail "an id with capitals" "AGP004"

new_fixture
valid_text | sed 's/^reports_to: .*/reports_to: boss/' | put specialist-reviewer
expect_fail "reports_to that is neither owner nor a profile id" "AGP004"

new_fixture
valid_text | sed 's/^mission: .*/mission:/' | put specialist-reviewer
expect_fail "an empty mission" "AGP004"

new_fixture
valid_text | sed 's/^outputs: .*/outputs: []/' | put specialist-reviewer
expect_fail "empty outputs" "AGP004"

new_fixture
valid_text | sed '/^  deny:/d' | put specialist-reviewer
expect_fail "tools without deny" "AGP001"

# --- the reserved runtime key (D7) -------------------------------------------------------

new_fixture
valid_text | sed 's/^lane: .*/lane: read-only\nruntime: claude/' | put specialist-reviewer
expect_pass "runtime: claude"

new_fixture
valid_text | sed 's/^lane: .*/lane: read-only\nruntime: codex/' | put specialist-reviewer
expect_fail "runtime: codex" "AGP004"

# --- body layout (D3) --------------------------------------------------------------------

for heading in Mission Owns Boundaries Procedure "Done means" "Report format"; do
  new_fixture
  valid_text | awk -v h="## $heading" '$0 == h { skip = 1; next } /^## / { skip = 0 } !skip { print }' | put specialist-reviewer
  expect_fail "missing section $heading" "AGP007"
  grep -qF "$heading" <<<"$out" || fail "missing section $heading: the message does not name it: $out"
done

new_fixture
{
  valid_text | sed '/^## Owns$/,$d'
  printf '## Boundaries\n\n- x\n\n## Owns\n\n- y\n\n## Procedure\n\n1. z\n\n## Done means\n\n- d\n\n## Report format\n\nr\n'
} | put specialist-reviewer
expect_fail "sections out of order" "AGP008"

new_fixture
{
  valid_text
  printf '\n## Mission\n\nAgain.\n'
} | put specialist-reviewer
expect_fail "a duplicate section" "AGP008"

new_fixture
{
  valid_text
  printf '\n## Notes\n\nExtra.\n'
} | put specialist-reviewer
expect_fail "an unknown section" "AGP008"

new_fixture
{
  valid_text
  printf '\n## Learned\n\n- one\n\n## Voice\n\nPlain.\n'
} | put specialist-reviewer
expect_fail "Learned before Voice" "AGP008"

new_fixture
valid_text | sed '/^Review one large diff against the issue text\.$/d' | put specialist-reviewer
expect_fail "an empty required section" "AGP007"

new_fixture
valid_text | awk '$0 == "## Mission" && !done { print "Stray text."; print ""; done = 1 } { print }' | put specialist-reviewer
expect_fail "text before the first section" "AGP008"

# --- Voice and Learned caps (D3, D8) -----------------------------------------------------

new_fixture
{
  valid_text
  printf '\n## Voice\n\nOne.\nTwo.\nThree.\nFour.\n'
} | put specialist-reviewer
expect_fail "a Voice of four lines" "AGP009"

learned_cap=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["x-body"]["learnedMaxLines"])' "$schema" 2>/dev/null || echo 10)
line_cap=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["x-body"]["learnedMaxLineLength"])' "$schema" 2>/dev/null || echo 200)

new_fixture
{
  valid_text
  printf '\n## Learned\n\n'
  for i in $(seq 1 "$learned_cap"); do printf -- '- line %s\n' "$i"; done
} | put specialist-reviewer
expect_pass "Learned at the cap ($learned_cap lines)"

new_fixture
{
  valid_text
  printf '\n## Learned\n\n'
  for i in $(seq 1 $((learned_cap + 1))); do printf -- '- line %s\n' "$i"; done
} | put specialist-reviewer
expect_fail "Learned one line over the cap" "AGP010"

new_fixture
{
  valid_text
  printf '\n## Learned\n\n- '
  head -c $((line_cap - 2)) /dev/zero | tr '\0' a
  printf '\n'
} | put specialist-reviewer
expect_pass "a Learned line at the length cap ($line_cap characters)"

new_fixture
{
  valid_text
  printf '\n## Learned\n\n- '
  head -c $((line_cap - 1)) /dev/zero | tr '\0' a
  printf '\n'
} | put specialist-reviewer
expect_fail "a Learned line one character over the length cap" "AGP010"

# --- authority changes need a version bump -----------------------------------------------

# base_then_edit <sed expression>: commit a valid profile, then edit the working copy.
base_then_edit() {
  new_fixture
  valid_text | put specialist-reviewer
  commit_fixture
  sed -i -e "$1" "$fx/profiles/specialist-reviewer.md"
}

base_then_edit 's/^lane: .*/lane: write/'
expect_fail "lane changed, version kept" "AGP011" --base HEAD
grep -qF "lane" <<<"$out" || fail "lane changed: the message does not name lane: $out"

base_then_edit 's/^lane: .*/lane: write/;s/^version: .*/version: "1.1"/'
expect_pass "lane changed, version bumped" --base HEAD

base_then_edit 's/^model: .*/model: opus/'
expect_fail "model changed, version kept" "AGP011" --base HEAD

base_then_edit 's/^  allow: .*/  allow: [Read, Grep, Glob, Bash, WebFetch]/'
expect_fail "tools changed, version kept" "AGP011" --base HEAD

base_then_edit 's/^  deny: .*/  deny: [Write]/;s/^version: .*/version: "1.1"/'
expect_pass "tools changed, version bumped" --base HEAD

base_then_edit 's/^lane: .*/lane: write/;s/^version: .*/version: "0.9"/'
expect_fail "lane changed, version lowered" "AGP011" --base HEAD

base_then_edit 's/^lane: .*/lane: write/;s/^version: .*/version: "1.0"/'
expect_fail "lane changed, version re-quoted but equal" "AGP011" --base HEAD

base_then_edit 's/^mission: .*/mission: A different sentence for the same role./'
expect_pass "a non-authority field changed without a bump" --base HEAD

base_then_edit 's/^skills: .*/skills: [tdd, pr]/'
expect_pass "skills changed without a bump" --base HEAD

base_then_edit 's/^lane: .*/lane: read-only\nruntime: claude/'
expect_pass "spelling out the default runtime is not a change" --base HEAD

base_then_edit 's/^version: .*/version: "1.10"/;s/^lane: .*/lane: write/'
expect_pass "version 1.10 is above 1.9" --base HEAD

new_fixture
valid_text | sed 's/^version: .*/version: "1.9"/' | put specialist-reviewer
commit_fixture
sed -i -e 's/^version: .*/version: "1.10"/' -e 's/^lane: .*/lane: write/' "$fx/profiles/specialist-reviewer.md"
expect_pass "versions compare as numbers, not text (1.9 to 1.10)" --base HEAD

# A new profile has nothing to compare against.
new_fixture
valid_text specialist other | put specialist-other
commit_fixture
valid_text | put specialist-reviewer
expect_pass "a new profile needs no bump" --base HEAD

# A rank change is a rename (the id carries the rank), so it is matched by role.
new_fixture
valid_text specialist reviewer | put specialist-reviewer
commit_fixture
git -C "$fx" mv profiles/specialist-reviewer.md profiles/lead-reviewer.md
sed -i -e 's/^id: .*/id: lead-reviewer/' -e 's/^rank: .*/rank: lead/' "$fx/profiles/lead-reviewer.md"
expect_fail "rank changed by rename, version kept" "AGP011" --base HEAD
grep -qF "rank" <<<"$out" || fail "rank rename: the message does not name rank: $out"

sed -i -e 's/^version: .*/version: "2.0"/' "$fx/profiles/lead-reviewer.md"
expect_pass "rank changed by rename, version bumped" --base HEAD

# The base itself.
new_fixture
valid_text | put specialist-reviewer
commit_fixture
expect_fail "an explicit base that does not exist" "no-such-ref" --base no-such-ref

new_fixture
valid_text | put specialist-reviewer
expect_pass "the default base (origin/main) missing is a loud skip, not a failure"
grep -qF "version-bump rule skipped" <<<"$out" || fail "missing default base: no skip note: $out"

new_fixture
valid_text | put specialist-reviewer
commit_fixture
sed -i 's/^lane: .*/lane: write/' "$fx/profiles/specialist-reviewer.md"
rc=0
out=$(PROFILE_BASE=HEAD bash "$checker" --root "$fx" 2>&1) || rc=$?
if [ "$rc" -eq 0 ] || ! grep -qF AGP011 <<<"$out"; then
  fail "PROFILE_BASE is not read: exit $rc: $out"
fi

# --- the rank ceiling (agents#21) ---------------------------------------------------------

# The table is read from doctrine/units.md (--units overrides the file in these cases). Each
# case that needs a different table writes its own file; the values of the real table are the
# owner's to change, so the cases against it use only the first rows: scout reads, specialist
# adds Bash and WebFetch, lead adds Edit and Write, staff takes everything.

# with_allow <rank> <flow list>: a valid profile of that rank listing exactly those tools.
with_allow() {
  local rank=$1 list=$2
  valid_text "$rank" worker | sed "s/^  allow: .*/  allow: $list/" | put "$rank-worker"
}

# A units file with a table of four rank rows: units_file <path> <scout> <specialist> <lead> <staff>
units_file() {
  local path=$1
  cat >"$path" <<EOF
# Units

## Rank ceiling

| Rank | Adds to the tools of the rank below |
| ---- | ----------------------------------- |
| scout | $2 |
| specialist | $3 |
| lead | $4 |
| staff | $5 |

## Next section

Text.
EOF
}

cases=$((cases + 1))
if ! grep -qE '^## Rank ceiling$' "$repo/doctrine/units.md"; then
  fail "doctrine/units.md has no '## Rank ceiling' section"
else
  for rank in scout specialist lead staff; do
    grep -qE "^\| \`?$rank\`? \| .*\`" "$repo/doctrine/units.md" || fail "doctrine/units.md: the ceiling table has no row for $rank with backticked tools"
  done
fi

new_fixture
with_allow scout "[Read, Grep, Glob]"
expect_pass "a scout inside its ceiling"

new_fixture
with_allow scout "[Read, Grep, Glob, Edit]"
expect_fail "a scout listing Edit" "AGP013"
grep -qF "Edit" <<<"$out" || fail "scout Edit: the message does not name the tool: $out"
grep -qF "scout" <<<"$out" || fail "scout Edit: the message does not name the rank: $out"
grep -qF "profiles/scout-worker.md:" <<<"$out" || fail "scout Edit: the message does not name the file: $out"
grep -qF "lead" <<<"$out" || fail "scout Edit: the message does not name the lowest rank that allows it (lead): $out"

new_fixture
with_allow scout "[Read, Bash]"
expect_fail "a scout listing Bash" "AGP013"

new_fixture
with_allow scout "[Read, Edit, Write, WebFetch]"
expect_fail "a scout listing several tools above its ceiling" "AGP013"
for tool in Edit Write WebFetch; do
  grep -qF "$tool" <<<"$out" || fail "several tools: the message does not name $tool: $out"
done

new_fixture
with_allow specialist "[Read, Grep, Glob, Bash, WebFetch]"
expect_pass "a specialist inherits the scout tools and adds Bash and WebFetch"

new_fixture
with_allow specialist "[Read, Edit]"
expect_fail "a specialist listing Edit" "AGP013"

new_fixture
with_allow lead "[Read, Grep, Glob, Bash, WebFetch, Edit, Write]"
expect_pass "a lead inherits both lower ranks and adds Edit and Write"

new_fixture
with_allow lead "[Read, Agent]"
expect_fail "a lead listing a tool the table gives only staff" "AGP013"

new_fixture
with_allow staff "[Read, Edit, Write, Bash, Agent, mcp__loop-state__slot_list]"
expect_pass "staff may list any tool, MCP tools included"

new_fixture
with_allow specialist "[Read, Bash(git status:*)]"
expect_pass "a parameterised tool is checked by its name"

new_fixture
with_allow scout "[Read, Bash(git status:*)]"
expect_fail "a parameterised tool above the ceiling" "AGP013"

new_fixture
with_allow scout "[Read, mcp__loop-state__slot_list]"
expect_fail "an MCP tool above a scout's ceiling" "AGP013"

new_fixture
with_allow scout "[]"
expect_pass "an empty allow list is inside every ceiling"

new_fixture
valid_text scout worker | sed 's/^  deny: .*/  deny: [Edit, Write, Bash, WhateverTool]/' | put scout-worker
expect_pass "deny is not checked against the table"

new_fixture
valid_text sergeant worker | put sergeant-worker
expect_fail "an unknown rank is only a schema error" "AGP004"
grep -qF "AGP013" <<<"$out" && fail "an unknown rank must not also report AGP013: $out"

new_fixture
with_allow scout "[Read, Edit]"
line=$(grep -n '^  allow:' "$fx/profiles/scout-worker.md" | head -1 | cut -d: -f1)
tools_line=$(grep -n '^tools:' "$fx/profiles/scout-worker.md" | head -1 | cut -d: -f1)
run_check
grep -qF "profiles/scout-worker.md:$tools_line: AGP013" <<<"$out" || fail "the finding is not on the tools line ($tools_line, allow line $line): $out"

# The table is the source: change it and the same profile passes or fails.
new_fixture
with_allow scout "[Read, Edit]"
units_file "$fx/units.md" '`Read`, `Grep`, `Glob`, `Edit`' '`Bash`' '`Write`' '`*`'
expect_pass "the table is read from the file, not built in" --units "$fx/units.md"

new_fixture
with_allow lead "[Read, Agent]"
units_file "$fx/units.md" '`Read`' '`Bash`' '`*`' '`Agent`'
expect_pass "a * row allows every tool from that rank up" --units "$fx/units.md"

new_fixture
with_allow specialist "[Read, Agent]"
units_file "$fx/units.md" '`Read`' '`Bash`' '`*`' '`Agent`'
expect_fail "a * row above the profile's rank does not reach it" "AGP013" --units "$fx/units.md"

new_fixture
with_allow scout "[Read]"
units_file "$fx/units.md" '`Read`, `Grep`' '`Bash` and `WebFetch`' '`Edit`' '`*`'
expect_pass "tools may be joined with 'and'" --units "$fx/units.md"

# A table that cannot be read fails the check, with or without profiles.
new_fixture
expect_fail "a units file that does not exist" "AGP014" --units "$fx/no-such-units.md"

new_fixture
printf '# Units\n\nNo ceiling here.\n' >"$fx/units.md"
expect_fail "no Rank ceiling section" "AGP014" --units "$fx/units.md"

new_fixture
printf '# Units\n\n## Rank ceiling\n\nNo table.\n' >"$fx/units.md"
expect_fail "a Rank ceiling section without a table" "AGP014" --units "$fx/units.md"

new_fixture
units_file "$fx/units.md" '`Read`' '`Bash`' '`Edit`' '`*`'
sed -i '/^| lead |/d' "$fx/units.md"
expect_fail "a rank missing from the table" "AGP014" --units "$fx/units.md"
grep -qF "lead" <<<"$out" || fail "missing rank: the message does not name lead: $out"

new_fixture
units_file "$fx/units.md" '`Read`' '`Bash`' '`Edit`' '`*`'
sed -i 's/^| lead |/| sergeant |/' "$fx/units.md"
expect_fail "an unknown rank row" "AGP014" --units "$fx/units.md"

new_fixture
units_file "$fx/units.md" '`Read`' '`Bash`' '`Edit`' '`*`'
sed -i 's/^| scout |\(.*\)$/| scout |\1\n| scout | `Write` |/' "$fx/units.md"
expect_fail "a rank listed twice" "AGP014" --units "$fx/units.md"

new_fixture
units_file "$fx/units.md" '`Read`' '`Bash`' '`Edit`' '`*`'
awk '/^\| scout \|/ { s = $0; next } /^\| specialist \|/ { print; print s; next } { print }' "$fx/units.md" >"$fx/units.new"
mv "$fx/units.new" "$fx/units.md"
expect_fail "ranks out of order (the order is how a rank inherits)" "AGP014" --units "$fx/units.md"

new_fixture
units_file "$fx/units.md" '' '`Bash`' '`Edit`' '`*`'
expect_fail "a rank with no tools" "AGP014" --units "$fx/units.md"

new_fixture
units_file "$fx/units.md" 'Read, Grep' '`Bash`' '`Edit`' '`*`'
expect_fail "tool names without backticks" "AGP014" --units "$fx/units.md"

new_fixture
units_file "$fx/units.md" '`Read` mostly' '`Bash`' '`Edit`' '`*`'
expect_fail "text outside the backticks" "AGP014" --units "$fx/units.md"

new_fixture
units_file "$fx/units.md" '`Read Grep`' '`Bash`' '`Edit`' '`*`'
expect_fail "a tool name with a space" "AGP014" --units "$fx/units.md"

new_fixture
with_allow scout "[Read, Edit]"
units_file "$fx/units.md" '`Read`' '`Bash`' '`Edit`' '`*`'
sed -i '/^| lead |/d' "$fx/units.md"
expect_fail "an unreadable table is reported, profiles are not guessed against it" "AGP014" --units "$fx/units.md"
grep -qF "AGP013" <<<"$out" && fail "an unreadable table must not produce AGP013 findings: $out"

new_fixture
units_file "$fx/units.md" '`Read`' '`Bash`' '`Edit`' '`*`'
sed -i 's/^## Next section$/## Rank ceiling (draft)/' "$fx/units.md"
expect_pass "only the exact '## Rank ceiling' heading counts, later headings end the table" --units "$fx/units.md"

# --- check.sh runs it --------------------------------------------------------------------

cases=$((cases + 1))
grep -q 'scripts/check-profiles.sh' scripts/check.sh || fail "scripts/check.sh does not run check-profiles.sh"
grep -q 'scripts/test-check-profiles.sh' scripts/check.sh || fail "scripts/check.sh does not run test-check-profiles.sh"

if [ "$failed" -ne 0 ]; then
  echo "test-check-profiles: $failed failure(s) in $cases case(s)" >&2
  exit 1
fi
echo "test-check-profiles: ok ($cases cases)"
