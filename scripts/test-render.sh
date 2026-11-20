#!/usr/bin/env bash
# Tests for scripts/render.sh (agents#9), written before the renderer. Each case builds a
# throwaway fixture root (doctrine/culture.md, templates/brief.md, profiles/) and runs the
# renderer against it with --root, so no fixture output is ever a tracked file of this repo.
# Run by check.sh. Needs only bash and python3.
set -euo pipefail

builtin cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo=$PWD
renderer="$repo/scripts/render.sh"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

cases=0
failed=0
fx=""
rc=0
out=""
brief_out="$scratch/brief.out"
brief_err="$scratch/brief.err"

fail() {
  echo "test-render: FAIL: $1" >&2
  failed=$((failed + 1))
}

# The shared culture of a fixture. Text before the first '## ' and after the render:end
# marker is for maintainers and must never reach a generated file.
culture_text() {
  cat <<'EOF'
# Culture

INTRO-NOT-JOINED: a maintainer note before the first section.

## Voice

- Terse operator.
- No flourishes.

## Working rules

- One writer per change.

```text
## not a heading
```

<!-- render:end -->

## Maintainer notes

NOTES-NOT-JOINED
EOF
}

# A fresh fixture root holding the real brief template and a small culture.
new_fixture() {
  cases=$((cases + 1))
  fx="$scratch/fx$cases"
  mkdir -p "$fx/profiles" "$fx/doctrine" "$fx/templates"
  cp "$repo/templates/brief.md" "$fx/templates/brief.md" 2>/dev/null || true
  culture_text >"$fx/doctrine/culture.md"
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
  local rank=${1:-specialist} role=${2:-reviewer}
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
  allow: [Read, Grep, Glob, Bash]
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

run_render() {
  rc=0
  out=$(bash "$renderer" --root "$fx" "$@" 2>&1) || rc=$?
}

expect_pass() {
  local name=$1
  shift
  run_render "$@"
  if [ "$rc" -ne 0 ]; then
    fail "$name: expected pass, got exit $rc: $out"
  fi
}

# expect_fail <name> <fixed string the output must carry> [renderer args]
expect_fail() {
  local name=$1 needle=$2
  shift 2
  run_render "$@"
  if [ "$rc" -eq 0 ]; then
    fail "$name: expected a failure, got exit 0: $out"
  elif [ "$rc" -eq 127 ] || ! grep -qF -- "$needle" <<<"$out"; then
    fail "$name: exit $rc without '$needle' in: $out"
  fi
}

# expect_usage <name> [renderer args]: exit status 2
expect_usage() {
  local name=$1
  shift
  run_render "$@"
  if [ "$rc" -ne 2 ]; then
    fail "$name: expected exit 2, got $rc: $out"
  fi
}

has() { # has <file> <fixed string>
  grep -qF -- "$2" "$1" || fail "$3: '$2' not in $1"
}

lacks() { # lacks <file> <fixed string>
  if grep -qF -- "$2" "$1"; then fail "$3: '$2' is in $1"; fi
}

has_line() { # has_line <file> <exact line>
  grep -qxF -- "$2" "$1" || fail "$3: no line '$2' in $1"
}

line_of() { # line_of <file> <exact line>: the first line number, 0 when absent
  local n
  n=$(grep -nxF -- "$2" "$1" | head -n 1 | cut -d: -f1 || true)
  echo "${n:-0}"
}

count_line() { # count_line <file> <exact line>
  grep -cxF -- "$2" "$1" || true
}

# The front matter of a generated agent file, between its first two --- lines.
front() {
  sed -n '2,/^---$/p' "$1" | sed '$d'
}

agent_file() { echo "$fx/generated/agents/$1.md"; }
brief_file() { echo "$fx/generated/briefs/$1.md"; }

# brief <id> [renderer args]: run --brief, stdout to $brief_out, stderr to $brief_err.
run_brief() {
  rc=0
  bash "$renderer" --root "$fx" --brief "$@" >"$brief_out" 2>"$brief_err" || rc=$?
}

expect_brief_fail() { # expect_brief_fail <name> <needle> <brief args>
  local name=$1 needle=$2
  shift 2
  run_brief "$@"
  if [ "$rc" -eq 0 ]; then
    fail "$name: expected a failure, got exit 0"
  elif [ "$rc" -eq 127 ] || ! grep -qF -- "$needle" "$brief_err"; then
    fail "$name: exit $rc without '$needle' in: $(cat "$brief_err")"
  fi
}

# --- no profiles ---------------------------------------------------------------------------

new_fixture
expect_pass "no profiles at all"
grep -qF "0 profile(s)" <<<"$out" || fail "no profiles: summary line missing: $out"
[ ! -e "$fx/generated" ] || fail "no profiles: generated/ was created"
expect_pass "no profiles, --check" --check

# --- the agent file (the render target: a Claude subagent file) ----------------------------

new_fixture
valid_text | put specialist-reviewer
expect_pass "a valid profile renders"
a=$(agent_file specialist-reviewer)
b=$(brief_file specialist-reviewer)
[ -f "$a" ] || fail "no generated/agents/specialist-reviewer.md"
[ -f "$b" ] || fail "no generated/briefs/specialist-reviewer.md"

if [ -f "$a" ]; then
  [ "$(head -n 1 "$a")" = "---" ] || fail "agent file: front matter is not the first line"
  expected_front=$(
    cat <<'EOF'
name: specialist-reviewer
description: "Review one large diff against the issue text and report PASS, ISSUES or BLOCKED."
tools:
  - "Read"
  - "Grep"
  - "Glob"
  - "Bash"
disallowedTools:
  - "Edit"
  - "Write"
skills:
  - "tdd"
EOF
  )
  [ "$(front "$a")" = "$expected_front" ] || fail "agent file: front matter is not the subagent mapping: $(front "$a")"
  for key in rank lane section version reports_to escalates_to inputs outputs runtime; do
    if front "$a" | grep -q "^$key:"; then fail "agent file: '$key' leaked into the subagent front matter"; fi
  done
  has_line "$a" "# specialist-reviewer" "agent file title"
  has_line "$a" "Rank: specialist. Section: S3. Lane: read-only. Version: 1.0. Reports to: staff-xo. Escalates to: owner." "agent file identity line"
  has "$a" "<!-- Generated by scripts/render.sh from profiles/specialist-reviewer.md. Do not edit. -->" "agent file provenance"
fi

new_fixture
valid_text scout reader | sed -e 's/^model: auto/model: opus/' -e '/^skills:/d' -e 's/^  deny: .*/  deny: []/' -e 's/^  allow: .*/  allow: [Read, Grep, Glob]/' | put scout-reader
expect_pass "a pinned model, no skills, no denied tools"
a=$(agent_file scout-reader)
has_line "$a" "model: opus" "a pinned model passes through"
if front "$a" | grep -qE '^(skills|disallowedTools):'; then fail "empty skills and deny lists must be left out: $(front "$a")"; fi

new_fixture
valid_text | put specialist-reviewer
expect_pass "model auto"
if front "$(agent_file specialist-reviewer)" | grep -q '^model:'; then fail "model auto must not become a literal override"; fi

new_fixture
valid_text | sed 's/^mission: .*/mission: "Say \\"hi\\": then stop."/' | put specialist-reviewer
expect_pass "a mission with a quote and a colon"
has_line "$(agent_file specialist-reviewer)" 'description: "Say \"hi\": then stop."' "a mission is quoted for YAML"

new_fixture
valid_text | sed 's/^  allow: .*/  allow: []/' | put specialist-reviewer
expect_fail "an empty allow list" "AGR006"
expect_fail "an empty allow list names the field" "tools.allow"
[ ! -e "$fx/generated" ] || fail "an empty allow list: something was written"

# --- the body: culture first, then the profile ---------------------------------------------

new_fixture
{
  valid_text
  printf '\n## Voice\n\nPlain.\nEvidence first.\n'
} | put specialist-reviewer
expect_pass "culture joins the profile"
a=$(agent_file specialist-reviewer)
b=$(brief_file specialist-reviewer)
for f in "$a" "$b"; do
  has_line "$f" "## Culture" "$f culture heading"
  has_line "$f" "### Voice" "$f culture Voice demoted one level"
  has_line "$f" "### Working rules" "$f culture section demoted one level"
  has "$f" "- One writer per change." "$f culture text"
  has_line "$f" "## not a heading" "$f a fenced line is not demoted"
  lacks "$f" "INTRO-NOT-JOINED" "$f text before the first culture section"
  lacks "$f" "NOTES-NOT-JOINED" "$f text after the render:end marker"
  lacks "$f" "render:end" "$f the marker itself"
  has_line "$f" "## Mission" "$f profile Mission"
  has_line "$f" "## Report format" "$f profile Report format"
  has_line "$f" "## Voice" "$f the profile's own Voice stays a ## section"
  culture_at=$(line_of "$f" "## Culture")
  mission_at=$(line_of "$f" "## Mission")
  report_at=$(line_of "$f" "## Report format")
  if [ "$culture_at" -eq 0 ] || [ "$culture_at" -ge "$mission_at" ] || [ "$mission_at" -ge "$report_at" ]; then
    fail "$f: order is not culture, then Mission ... Report format ($culture_at, $mission_at, $report_at)"
  fi
done

new_fixture
valid_text | put specialist-reviewer
printf '# Culture\n\nNo sections here.\n' >"$fx/doctrine/culture.md"
expect_fail "a culture with nothing to join" "AGR001"

new_fixture
valid_text | put specialist-reviewer
rm -f "$fx/doctrine/culture.md"
expect_fail "no culture file" "doctrine/culture.md"

new_fixture
valid_text | put specialist-reviewer
rm -f "$fx/templates/brief.md"
expect_fail "no brief template" "templates/brief.md"

# --- the brief: the issue text is a mandatory input ----------------------------------------

new_fixture
valid_text | put specialist-reviewer
expect_pass "a brief renders"
b=$(brief_file specialist-reviewer)
has_line "$b" "# Brief: specialist-reviewer" "brief title"
has_line "$b" "## Inputs" "brief inputs heading"
has_line "$b" "### issue_text" "brief issue_text heading"
has_line "$b" "### diff" "brief declared input"
has_line "$b" "<!-- input:issue_text:begin -->" "issue text begin marker"
has_line "$b" "<!-- input:issue_text:end -->" "issue text end marker"
[ "$(count_line "$b" "{{issue_text}}")" -eq 1 ] || fail "brief: issue_text slot is not there exactly once"
[ "$(count_line "$b" "{{diff}}")" -eq 1 ] || fail "brief: diff slot is not there exactly once"
has_line "$b" "Rank: specialist. Section: S3. Lane: read-only. Version: 1.0. Reports to: staff-xo. Escalates to: owner." "brief identity line"
has "$b" "<!-- Generated by scripts/render.sh from profiles/specialist-reviewer.md. Do not edit. -->" "brief provenance"
issue_at=$(line_of "$b" "### issue_text")
diff_at=$(line_of "$b" "### diff")
[ "$issue_at" -gt 0 ] && [ "$issue_at" -lt "$diff_at" ] || fail "brief: issue_text must come before the other inputs"

new_fixture
valid_text | sed 's/^inputs: .*/inputs: []/' | put specialist-reviewer
expect_pass "a profile that lists no inputs"
b=$(brief_file specialist-reviewer)
[ "$(count_line "$b" "{{issue_text}}")" -eq 1 ] || fail "no listed inputs: the issue text slot is still mandatory"
lacks "$b" "### diff" "no listed inputs: no diff slot"

new_fixture
valid_text | sed 's/^inputs: .*/inputs: [diff, issue_text]/' | put specialist-reviewer
expect_pass "issue_text listed after another input"
b=$(brief_file specialist-reviewer)
[ "$(count_line "$b" "{{issue_text}}")" -eq 1 ] || fail "issue_text listed late: not exactly one slot"
issue_at=$(line_of "$b" "### issue_text")
diff_at=$(line_of "$b" "### diff")
[ "$issue_at" -gt 0 ] && [ "$issue_at" -lt "$diff_at" ] || fail "issue_text listed late: it must still come first"

new_fixture
valid_text | put specialist-reviewer
grep -v '{{inputs}}' "$repo/templates/brief.md" >"$fx/templates/brief.md" || true
expect_fail "a template without the inputs slot" "{{inputs}}"
expect_fail "a template without the inputs slot says why" "issue text"
[ ! -e "$fx/generated" ] || fail "a template without the inputs slot: something was written"

new_fixture
valid_text | put specialist-reviewer
printf '{{inputs}}\n\n{{nonsense}}\n' >"$fx/templates/brief.md"
expect_fail "an unknown placeholder" "{{nonsense}}"

new_fixture
valid_text | put specialist-reviewer
printf 'Plain brief for {{id}}.\n\n{{inputs}}\n' >"$fx/templates/brief.md"
expect_pass "a template that uses only some placeholders"
has_line "$(brief_file specialist-reviewer)" "Plain brief for specialist-reviewer." "a template is filled as written"

# --- filling a brief with the issue text ---------------------------------------------------

new_fixture
valid_text | put specialist-reviewer
printf 'Fix the thing: {{diff}} {{issue_text}} $1 \\n & unicode é — end  ' >"$scratch/issue.txt"
printf 'DIFFBODY\n' >"$scratch/diff.txt"
run_brief specialist-reviewer --issue-file "$scratch/issue.txt" --input "diff=$scratch/diff.txt"
[ "$rc" -eq 0 ] || fail "fill: exit $rc: $(cat "$brief_err")"
python3 -I -c '
import sys
out = open(sys.argv[1], "rb").read()
issue = open(sys.argv[2], "rb").read()
sys.exit(0 if issue in out else 1)
' "$brief_out" "$scratch/issue.txt" || fail "fill: the issue text is not in the brief byte for byte"
[ "$(grep -c 'DIFFBODY' "$brief_out" || true)" -eq 1 ] || fail "fill: the diff was not inserted exactly once (an issue holding {{diff}} must not be expanded)"
[ "$(grep -o '{{diff}}' "$brief_out" | wc -l)" -eq 1 ] || fail "fill: the issue's own {{diff}} was lost or expanded"
has_line "$brief_out" "<!-- input:issue_text:begin -->" "fill: begin marker kept"
has_line "$brief_out" "<!-- input:issue_text:end -->" "fill: end marker kept"
has_line "$brief_out" "## Mission" "fill: charter present"
has_line "$brief_out" "## Culture" "fill: culture present"
begin_at=$(line_of "$brief_out" "<!-- input:issue_text:begin -->")
end_at=$(line_of "$brief_out" "<!-- input:issue_text:end -->")
[ "$begin_at" -gt 0 ] && [ "$end_at" -gt "$begin_at" ] || fail "fill: the end marker must follow the begin marker"
[ ! -e "$fx/generated" ] || fail "fill: --brief wrote into generated/"

new_fixture
valid_text | sed 's/^inputs: .*/inputs: []/' | put specialist-reviewer
printf 'Line one\r\nLine two\r\n\r\n' >"$scratch/issue-crlf.txt"
run_brief specialist-reviewer --issue-file "$scratch/issue-crlf.txt"
[ "$rc" -eq 0 ] || fail "fill crlf: exit $rc: $(cat "$brief_err")"
python3 -I -c '
import sys
out = open(sys.argv[1], "rb").read()
issue = open(sys.argv[2], "rb").read()
sys.exit(0 if issue in out else 1)
' "$brief_out" "$scratch/issue-crlf.txt" || fail "fill: CRLF line endings were changed"
if grep -q '{{' "$brief_out"; then fail "fill: an unfilled {{slot}} is left in the brief"; fi

new_fixture
valid_text | put specialist-reviewer
printf 'Issue.\n' >"$scratch/issue.txt"
printf 'DIFFBODY\n' >"$scratch/diff.txt"
expect_brief_fail "no --issue-file" "mandatory" specialist-reviewer --input "diff=$scratch/diff.txt"
expect_brief_fail "no --issue-file names the flag" "--issue-file" specialist-reviewer --input "diff=$scratch/diff.txt"
: >"$scratch/empty.txt"
expect_brief_fail "an empty issue file" "mandatory" specialist-reviewer --issue-file "$scratch/empty.txt" --input "diff=$scratch/diff.txt"
printf ' \n\t\n' >"$scratch/blank.txt"
expect_brief_fail "a blank issue file" "mandatory" specialist-reviewer --issue-file "$scratch/blank.txt" --input "diff=$scratch/diff.txt"
expect_brief_fail "a missing issue file" "no-such-issue.txt" specialist-reviewer --issue-file "$scratch/no-such-issue.txt" --input "diff=$scratch/diff.txt"
expect_brief_fail "a declared input not supplied" "diff" specialist-reviewer --issue-file "$scratch/issue.txt"
expect_brief_fail "an input the profile does not declare" "unknown" specialist-reviewer --issue-file "$scratch/issue.txt" --input "diff=$scratch/diff.txt" --input "other=$scratch/diff.txt"
expect_brief_fail "issue_text through --input" "--issue-file" specialist-reviewer --issue-file "$scratch/issue.txt" --input "diff=$scratch/diff.txt" --input "issue_text=$scratch/issue.txt"
expect_brief_fail "an unknown profile id" "no-such-profile" no-such-profile --issue-file "$scratch/issue.txt"
printf '\xff\xfe not utf-8' >"$scratch/bad.txt"
expect_brief_fail "an issue file that is not UTF-8" "UTF-8" specialist-reviewer --issue-file "$scratch/bad.txt" --input "diff=$scratch/diff.txt"

expect_usage "an unknown flag" --no-such-flag
expect_usage "--brief with --check" --brief specialist-reviewer --check
expect_usage "--issue-file without --brief" --issue-file "$scratch/issue.txt"
expect_usage "--brief without an id" --brief

# --- a profile that fails the profile check is not rendered --------------------------------

new_fixture
valid_text | put specialist-reviewer
valid_text scout reader | sed 's/^rank: scout/rank: private/' | put scout-reader
expect_fail "an invalid profile" "AGP004"
[ ! -e "$fx/generated" ] || fail "an invalid profile: the valid one was written anyway"

new_fixture
valid_text | sed 's/^id: .*/id: specialist-other/' | put specialist-reviewer
expect_fail "an id that is not the file name" "AGP005"

new_fixture
valid_text | put specialist-reviewer
valid_text scout reader | sed 's/^  allow: .*/  allow: [Read, Edit]/' | put scout-reader
expect_fail "a profile above its rank's tool ceiling" "AGP013"
[ ! -e "$fx/generated" ] || fail "a profile above its rank's tool ceiling: something was written"

# --- text the renderer must not carry over -------------------------------------------------

new_fixture
{
  valid_text
  printf '\nSee the {{issue_text}} slot.\n'
} | sed 's/^Result, evidence, open questions\.$/Result, {{issue_text}}, open questions./' | put specialist-reviewer
expect_fail "a profile that holds a brief slot" "AGR004"

new_fixture
valid_text | put specialist-reviewer
printf '\nAlso {{diff}} here.\n' >>"$fx/doctrine/culture.md"
sed -i 's/^<!-- render:end -->$//' "$fx/doctrine/culture.md"
expect_fail "a culture that holds a brief slot" "AGR004"

new_fixture
valid_text | sed 's/^- The review report\.$/- The report, see [the doctrine](..\/doctrine\/units.md)./' | put specialist-reviewer
expect_fail "a relative link in a profile" "relative link"

new_fixture
valid_text | sed 's/^- The review report\.$/- The report, see [units](https:\/\/example.invalid\/units) and [here](#top)./' | put specialist-reviewer
expect_pass "absolute and anchor links are kept"

# --- output hygiene and determinism --------------------------------------------------------

new_fixture
valid_text | put specialist-reviewer
valid_text lead planner | put lead-planner
expect_pass "two profiles"
for f in "$fx"/generated/agents/*.md "$fx"/generated/briefs/*.md; do
  if grep -n ' $' "$f" >/dev/null; then fail "$f has trailing whitespace"; fi
  [ -n "$(tail -c 1 "$f" | tr -d '\n')" ] && fail "$f has no newline at the end"
  [ "$(tail -c 2 "$f" | od -An -c | tr -d ' ')" != '\n\n' ] || fail "$f ends with a blank line"
done
[ "$(ls "$fx/generated/agents" | wc -l)" -eq 2 ] || fail "two profiles: not two agent files"
[ "$(ls "$fx/generated/briefs" | wc -l)" -eq 2 ] || fail "two profiles: not two brief files"
cp -r "$fx/generated" "$scratch/first-run"
expect_pass "a second render"
diff -r "$scratch/first-run" "$fx/generated" >/dev/null || fail "a second render changed the output"
rm -rf "$scratch/first-run"

new_fixture
valid_text | put specialist-reviewer
cp "$fx/profiles/specialist-reviewer.md" "$scratch/original-profile.md"
expect_pass "render leaves its sources alone"
cmp -s "$fx/profiles/specialist-reviewer.md" "$scratch/original-profile.md" || fail "render changed a profile"

# --- --check: the committed output must be what the sources render to ----------------------

new_fixture
valid_text | put specialist-reviewer
valid_text lead planner | put lead-planner
expect_pass "render before check"
expect_pass "--check passes on fresh output" --check
grep -qF "up to date" <<<"$out" || fail "--check: no 'up to date' line: $out"

printf '\nhand edit\n' >>"$(agent_file specialist-reviewer)"
expect_fail "--check fails on a hand-edited agent file" "STALE" --check
grep -qF "generated/agents/specialist-reviewer.md" <<<"$out" || fail "--check: the stale file is not named: $out"
grep -qF "hand edit" "$(agent_file specialist-reviewer)" || fail "--check repaired a file; it must only report"
expect_pass "render repairs a hand edit"
expect_pass "--check passes after repair" --check

rm "$(brief_file specialist-reviewer)"
expect_fail "--check fails on a missing brief" "MISSING" --check
[ ! -e "$(brief_file specialist-reviewer)" ] || fail "--check wrote a missing file"
expect_pass "render restores a missing file"

printf 'x\n' >"$fx/generated/agents/stale-orphan.md"
expect_fail "--check fails on a file no profile makes" "ORPHAN" --check
grep -qF "generated/agents/stale-orphan.md" <<<"$out" || fail "--check: the orphan is not named: $out"
expect_pass "render removes an orphan"
[ ! -e "$fx/generated/agents/stale-orphan.md" ] || fail "render left an orphan"

mkdir -p "$fx/generated/notes"
printf 'keep\n' >"$fx/generated/notes/keep.txt"
printf 'keep\n' >"$fx/generated/agents/keep.txt"
expect_pass "files that are not generated markdown"
[ -f "$fx/generated/notes/keep.txt" ] && [ -f "$fx/generated/agents/keep.txt" ] || fail "render deleted a file it did not make"
expect_pass "--check ignores files that are not generated markdown" --check

sed -i 's/^- One writer per change\.$/- One writer per change.\n- A new shared rule./' "$fx/doctrine/culture.md"
expect_fail "a culture change makes every output stale" "STALE" --check
[ "$(grep -c 'STALE' <<<"$out" || true)" -ge 4 ] || fail "a culture change must stale each agent file and brief: $out"
expect_pass "render after a culture change"
expect_pass "--check after a culture change" --check

sed -i 's/^Review one large diff against the issue text\.$/Review one diff./' "$fx/profiles/specialist-reviewer.md"
expect_fail "a profile change makes its output stale" "STALE" --check
expect_pass "render after a profile change"

rm "$fx/profiles/specialist-reviewer.md"
expect_fail "a deleted profile leaves orphans" "ORPHAN" --check
expect_pass "render after a profile is deleted"
[ ! -e "$(agent_file specialist-reviewer)" ] && [ ! -e "$(brief_file specialist-reviewer)" ] || fail "render kept the output of a deleted profile"
expect_pass "--check after a profile is deleted" --check

# --- the real culture and template ---------------------------------------------------------

new_fixture
cp "$repo/doctrine/culture.md" "$fx/doctrine/culture.md"
valid_text | put specialist-reviewer
expect_pass "the real culture and template"
has "$(agent_file specialist-reviewer)" "Terse operator" "the real culture reaches the agent file"
has "$(brief_file specialist-reviewer)" "Terse operator" "the real culture reaches the brief"
lacks "$(brief_file specialist-reviewer)" "Not here yet" "maintainer notes of the real culture stay out"

# --- check.sh runs it ----------------------------------------------------------------------

cases=$((cases + 1))
grep -q 'scripts/render.sh --check' scripts/check.sh || fail "scripts/check.sh does not run render.sh --check"
grep -q 'scripts/test-render.sh' scripts/check.sh || fail "scripts/check.sh does not run test-render.sh"

if [ "$failed" -ne 0 ]; then
  echo "test-render: $failed failure(s) in $cases case(s)" >&2
  exit 1
fi
echo "test-render: ok ($cases cases)"
