#!/usr/bin/env bash
# Tests for the Architecture scout pilot (agents#20), written before it. The pilot runs one
# read-only scout, `scout-architecture`, once a week against one repo and posts one comment on
# one rolling issue. Three pieces carry it:
#
#   profiles/scout-architecture.md      the role: Read, Grep and Glob only, at most 5 findings
#   scripts/arch-scout-run.sh           one run: brief, `claude -p` with the hard stops, read-back, comment
#   scripts/owner-steps/20.sh           the one command that arms the weekly timer (a live step)
#
# The decisions pinned here are the owner's of 17 Nov 2026 06:33 AEDT (agents#19): hard stops of
# `--max-turns 60` and a 30 minute timeout, 60k output tokens a target read back from the
# transcript (not a stop), weekly, one rolling issue with at most 5 findings per comment each
# answerable yes or no. The runs use fake `claude`, `gh` and `systemctl` on PATH and a fake HOME,
# so no model is called and nothing live is touched. Run by check.sh. Needs bash and python3.
set -euo pipefail

builtin cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo=$PWD
run="$repo/scripts/arch-scout-run.sh"
arm="$repo/scripts/owner-steps/20.sh"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

cases=0
failed=0
rc=0
out=""

fail() {
  echo "test-arch-scout: FAIL: $1" >&2
  failed=$((failed + 1))
}

expect() {
  cases=$((cases + 1))
  if ! "$@"; then fail "$* (case $cases)"; fi
}

# --- the profile --------------------------------------------------------------------------
profile=profiles/scout-architecture.md
expect test -s "$profile"
expect test -s generated/agents/scout-architecture.md
expect test -s generated/briefs/scout-architecture.md
expect grep -qx 'rank: scout' "$profile"
expect grep -qx 'lane: read-only' "$profile"
expect grep -qx 'section: S2' "$profile"
expect grep -qx 'reports_to: owner' "$profile"
expect grep -qx 'escalates_to: owner' "$profile"
expect grep -qx 'model: sonnet' "$profile"
expect grep -qx 'inputs: \[target_repo, prior_findings\]' "$profile"
expect grep -qx 'outputs: \[findings\]' "$profile"
expect grep -qx '  allow: \[Read, Grep, Glob\]' "$profile"
expect grep -qx '  deny: \[Bash, WebFetch, Edit, Write\]' "$profile"
# the report shape the run script parses
expect grep -qF -- 'at most five findings' "$profile"
expect grep -qF -- '### F1:' "$profile"
expect grep -qF -- 'Yes or no:' "$profile"
expect grep -qF -- 'No findings this week.' "$profile"
expect grep -qF -- '60 turns' "$profile"
expect grep -qF -- 'never close' "$profile"

# --- fixtures for a run -------------------------------------------------------------------
fake_bin="$scratch/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/claude" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$FAKE_LOG/claude.argv"
pwd >"$FAKE_LOG/claude.cwd"
cat >"$FAKE_LOG/claude.stdin"
sid=""
prev=""
for arg in "$@"; do
  [ "$prev" = "--session-id" ] && sid=$arg
  prev=$arg
done
if [ -f "$FAKE_DIR/transcript.jsonl" ]; then
  mkdir -p "$HOME/.claude/projects/-fake-target"
  cp "$FAKE_DIR/transcript.jsonl" "$HOME/.claude/projects/-fake-target/$sid.jsonl"
fi
[ -f "$FAKE_DIR/sleep" ] && sleep "$(cat "$FAKE_DIR/sleep")"
cat "$FAKE_DIR/result.json"
FAKE

cat >"$fake_bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_LOG/gh.calls"
case "$1 $2" in
  "issue view") cat "$FAKE_DIR/view.json" ;;
  "issue list") cat "$FAKE_DIR/list.json" ;;
  "issue comment")
    prev=""
    for arg in "$@"; do
      [ "$prev" = "--body-file" ] && cp "$arg" "$FAKE_LOG/posted.md"
      prev=$arg
    done
    echo "https://github.com/deanjstone/agents/issues/77#issuecomment-1"
    ;;
  "issue create")
    prev=""
    for arg in "$@"; do
      [ "$prev" = "--body-file" ] && cp "$arg" "$FAKE_LOG/created-body.md"
      prev=$arg
    done
    echo "https://github.com/deanjstone/agents/issues/88"
    ;;
  *) echo "fake gh: unexpected $*" >&2; exit 9 ;;
esac
FAKE

cat >"$fake_bin/systemctl" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_LOG/systemctl.calls"
FAKE
chmod +x "$fake_bin/claude" "$fake_bin/gh" "$fake_bin/systemctl"
export PATH="$fake_bin:$PATH"

# new_case: a fresh HOME, state directory and fake log; the target repo the scout runs in.
new_case() {
  cases=$((cases + 1))
  case_dir="$scratch/case$cases"
  mkdir -p "$case_dir/home" "$case_dir/state" "$case_dir/log" "$case_dir/fake" "$case_dir/target"
  export HOME="$case_dir/home"
  export FAKE_LOG="$case_dir/log"
  export FAKE_DIR="$case_dir/fake"
  export SCOUT_STATE_DIR="$case_dir/state"
  export SCOUT_WEEK="2026-W47"
  export SCOUT_WHEN="22 Nov 2026 07:00 AEDT"
  unset SCOUT_MAX_TURNS SCOUT_TIMEOUT SCOUT_TOKEN_TARGET SCOUT_MAX_RUNS
  printf '{"body":"Standing mission: scout argus.","comments":[]}\n' >"$FAKE_DIR/view.json"
  echo '[]' >"$FAKE_DIR/list.json"
}

# result_json <subtype> <num_turns> <result text>: what `claude -p --output-format json` prints.
result_json() {
  python3 -I - "$FAKE_DIR/result.json" "$1" "$2" "$3" <<'PY'
import json, sys
path, subtype, turns, text = sys.argv[1:5]
doc = {"type": "result", "subtype": subtype, "is_error": subtype != "success", "num_turns": int(turns), "duration_ms": 1000}
if subtype == "success":
    doc["result"] = text
json.dump(doc, open(path, "w"))
PY
}

# transcript <total output tokens>: three requests; the first is written twice as streaming
# does (one entry per content block, a partial count first), so a naive sum overcounts.
transcript() {
  python3 -I - "$FAKE_DIR/transcript.jsonl" "$1" <<'PY'
import json, sys
path, total = sys.argv[1], int(sys.argv[2])
first, second = total // 4, total // 4
third = total - first - second
def entry(msg_id, tokens):
    return {"type": "assistant", "message": {"id": msg_id, "usage": {"output_tokens": tokens, "input_tokens": 9, "cache_read_input_tokens": 99999}}}
rows = [{"type": "user"}, entry("msg_a", 3), entry("msg_a", first), entry("msg_b", second), entry("msg_c", third)]
open(path, "w").write("".join(json.dumps(row) + "\n" for row in rows))
PY
}

# findings <count>: a scout reply with that many findings, each ending on a yes-or-no question.
findings() {
  local count=$1 n
  for n in $(seq 1 "$count"); do
    printf '### F%s: Finding number %s\n- **Where:** `src/a.ts:%s`\n- **Evidence:** it does a thing.\n- **Why it matters:** it drifts.\n**Yes or no:** Should the thing move?\n\n' "$n" "$n" "$n"
  done
}

launch() {
  rc=0
  out=$(bash "$run" --issue deanjstone/agents#77 --target "$case_dir/target" "$@" 2>&1) || rc=$?
}

posted() { cat "$FAKE_LOG/posted.md"; }
has() { grep -qF -- "$1" <<<"$2"; }
lacks() { ! grep -qF -- "$1" <<<"$2"; }

# --- a clean run: stats, findings, the hard stops ------------------------------------------
new_case
result_json success 23 "$(findings 3)"
transcript 28000
launch
expect test "$rc" -eq 0
expect test -s "$FAKE_LOG/posted.md"
body=$(posted || true)
expect has '## Architecture scout, run 1 (week 2026-W47, 22 Nov 2026 07:00 AEDT)' "$body"
expect has '### F1: Finding number 1' "$body"
expect has '### F3: Finding number 3' "$body"
expect lacks '### F4' "$body"
expect has 'Run stats: turns 23 of 60' "$body"
expect has 'output tokens 28,000 (target 60,000)' "$body"
expect has 'within caps' "$body"
expect has '<!-- arch-scout-run: ' "$body"
expect has '"week": "2026-W47"' "$body"
expect has '"output_tokens": 28000' "$body"
expect has 'Answer each finding' "$body"
# it posted with --body-file to the rolling issue
expect grep -qE 'issue comment 77 .*-R deanjstone/agents .*--body-file' "$FAKE_LOG/gh.calls"
# the hard stops and the envelope, from the profile
argv=$(cat "$FAKE_LOG/claude.argv")
expect has '--max-turns' "$argv"
expect grep -qx -- '--max-turns' "$FAKE_LOG/claude.argv"
expect grep -qx -- '60' "$FAKE_LOG/claude.argv"
expect grep -qx -- '--tools' "$FAKE_LOG/claude.argv"
expect grep -qx -- 'Read,Grep,Glob' "$FAKE_LOG/claude.argv"
expect grep -qx -- '--disallowed-tools' "$FAKE_LOG/claude.argv"
expect grep -qx -- 'Bash,WebFetch,Edit,Write' "$FAKE_LOG/claude.argv"
expect grep -qx -- '--strict-mcp-config' "$FAKE_LOG/claude.argv"
expect grep -qx -- '--agent' "$FAKE_LOG/claude.argv"
expect grep -qx -- 'scout-architecture' "$FAKE_LOG/claude.argv"
expect grep -qx -- '--output-format' "$FAKE_LOG/claude.argv"
expect grep -qx -- 'json' "$FAKE_LOG/claude.argv"
expect grep -qx -- '--session-id' "$FAKE_LOG/claude.argv"
expect grep -qx -- '--model' "$FAKE_LOG/claude.argv"
expect grep -qx -- 'sonnet' "$FAKE_LOG/claude.argv"
expect lacks '--no-session-persistence' "$argv"
expect lacks '--dangerously-skip-permissions' "$argv"
expect lacks '--max-budget-usd' "$argv"
# it runs in the target repo, and the brief carries the issue text and the target
expect test "$(cat "$FAKE_LOG/claude.cwd")" = "$case_dir/target"
stdin=$(cat "$FAKE_LOG/claude.stdin")
expect has 'Standing mission: scout argus.' "$stdin"
expect has "$case_dir/target" "$stdin"

# --- the dry run prints the command and the caps and calls nothing -------------------------
new_case
launch --dry-run
expect test "$rc" -eq 0
expect has 'timeout 1800' "$out"
expect has '--max-turns 60' "$out"
expect has '--tools Read,Grep,Glob' "$out"
expect test ! -e "$FAKE_LOG/claude.argv"
expect test ! -e "$FAKE_LOG/posted.md"

# --- the caps come from the environment, so a pilot can tighten them -----------------------
new_case
SCOUT_MAX_TURNS=40 SCOUT_TIMEOUT=900 launch --dry-run
expect has 'timeout 900' "$out"
expect has '--max-turns 40' "$out"

# --- over the token target: posted and flagged, not a failure ------------------------------
new_case
result_json success 41 "$(findings 2)"
transcript 71234
launch
expect test "$rc" -eq 0
body=$(posted || true)
expect has 'output tokens 71,234 (target 60,000)' "$body"
expect has 'OVER the token target' "$body"
expect lacks 'within caps' "$body"
expect has '"status": "over-token"' "$body"

# --- more than five findings: the first five, renumbered, the rest counted -----------------
new_case
result_json success 30 "$(findings 7)"
transcript 20000
launch
expect test "$rc" -eq 0
body=$(posted || true)
expect has '### F5: Finding number 5' "$body"
expect lacks '### F6' "$body"
expect has '2 findings dropped: over the cap of 5' "$body"

# --- a finding without a yes-or-no question is dropped, the others renumbered --------------
new_case
bad=$(printf '### F1: Has no question\n- **Where:** `a.ts:1`\n\n### F2: Has one\n**Yes or no:** Move it?\n')
result_json success 12 "$bad"
transcript 9000
launch
expect test "$rc" -eq 0
body=$(posted || true)
expect has '### F1: Has one' "$body"
expect lacks 'Has no question' "$body"
expect has '1 finding dropped: no yes-or-no question' "$body"

# --- no findings is a valid run --------------------------------------------------------------
new_case
result_json success 9 "No findings this week."
transcript 3000
launch
expect test "$rc" -eq 0
body=$(posted || true)
expect has 'No findings this week.' "$body"
expect has 'within caps' "$body"
expect has '"findings": 0' "$body"

# --- a reply with neither findings nor the no-findings line is a failed run -----------------
new_case
result_json success 9 "I looked around and it seems fine."
transcript 3000
launch
expect test "$rc" -eq 3
body=$(posted || true)
expect has '"status": "bad-shape"' "$body"
expect lacks 'seems fine' "$body"

# --- hit the turn cap: no findings, the stop is on the record --------------------------------
new_case
result_json error_max_turns 60 ""
transcript 52000
launch
expect test "$rc" -eq 3
body=$(posted || true)
expect has 'Stopped at the turn cap (60 turns)' "$body"
expect has '"status": "max-turns"' "$body"
expect has 'output tokens 52,000' "$body"

# --- hit the timeout: the run is killed, the stop is on the record ---------------------------
new_case
echo 5 >"$FAKE_DIR/sleep"
result_json success 3 "$(findings 1)"
transcript 1000
SCOUT_TIMEOUT=1 launch
expect test "$rc" -eq 3
body=$(posted || true)
expect has 'Stopped at the time cap (1 s)' "$body"
expect has '"status": "timeout"' "$body"

# --- no transcript: the tokens are unknown and the run is not called within caps -------------
new_case
result_json success 11 "$(findings 1)"
launch
expect test "$rc" -eq 3
body=$(posted || true)
expect has 'output tokens unavailable (no transcript found)' "$body"
expect lacks 'within caps' "$body"
expect has '"status": "no-transcript"' "$body"

# --- one run a week, a run cap, and --force ---------------------------------------------------
marker='<!-- arch-scout-run: {"week": "2026-W47", "run": 1, "status": "ok"} -->'
python3 -I - "$scratch/view-week.json" "$marker" <<'PY'
import json, sys
json.dump({"body": "Standing mission.", "comments": [{"author": {"login": "deanjstone"}, "createdAt": "2026-11-22T07:00:00+11:00", "url": "https://github.com/deanjstone/agents/issues/77#issuecomment-5", "body": "## Architecture scout, run 1\n### F1: Old finding\n**Yes or no:** Old?\n" + sys.argv[2]}]}, open(sys.argv[1], "w"))
PY

new_case
cp "$scratch/view-week.json" "$FAKE_DIR/view.json"
result_json success 5 "$(findings 1)"
transcript 1000
launch
expect test "$rc" -eq 0
expect has 'already ran in 2026-W47' "$out"
expect test ! -e "$FAKE_LOG/claude.argv"
expect test ! -e "$FAKE_LOG/posted.md"

new_case
cp "$scratch/view-week.json" "$FAKE_DIR/view.json"
result_json success 5 "$(findings 1)"
transcript 1000
launch --force
expect test "$rc" -eq 0
body=$(posted || true)
expect has 'run 2 (week 2026-W47' "$body"
# the earlier comment travels to the scout as prior findings, so it does not repeat them
stdin=$(cat "$FAKE_LOG/claude.stdin")
expect has 'Old finding' "$stdin"

new_case
cp "$scratch/view-week.json" "$FAKE_DIR/view.json"
SCOUT_WEEK=2026-W48 SCOUT_MAX_RUNS=1 launch
expect test "$rc" -eq 0
expect has 'pilot complete: 1 of 1 runs' "$out"
expect test ! -e "$FAKE_LOG/claude.argv"

# --- a failed post keeps the comment and exits 4 ----------------------------------------------
new_case
result_json success 5 "$(findings 1)"
transcript 1000
cat >"$scratch/gh-fail" <<'FAKE'
#!/usr/bin/env bash
[ "$1 $2" = "issue view" ] && { cat "$FAKE_DIR/view.json"; exit 0; }
exit 1
FAKE
mkdir -p "$scratch/failbin"
cp "$fake_bin/claude" "$scratch/failbin/claude"
cp "$scratch/gh-fail" "$scratch/failbin/gh"
chmod +x "$scratch/failbin/gh" "$scratch/failbin/claude"
rc=0
out=$(PATH="$scratch/failbin:$PATH" bash "$run" --issue deanjstone/agents#77 --target "$case_dir/target" 2>&1) || rc=$?
expect test "$rc" -eq 4
expect has 'could not post' "$out"
expect test -s "$SCOUT_STATE_DIR/last-comment.md"

# --- argument errors ----------------------------------------------------------------------------
new_case
rc=0
out=$(bash "$run" --target "$case_dir/target" 2>&1) || rc=$?
expect test "$rc" -eq 2
expect has '--issue' "$out"
rc=0
out=$(bash "$run" --issue deanjstone/agents#77 --target "$case_dir/nowhere" 2>&1) || rc=$?
expect test "$rc" -eq 2
expect has 'not a directory' "$out"

# --- the arming step: units, the issue, the logged commands -----------------------------------
arm_env() {
  AGENTS_CHECKOUT="$repo" SCOUT_TARGET="$case_dir/target" bash "$arm" "$@"
}

new_case
rc=0
out=$(arm_env print 2>&1) || rc=$?
expect test "$rc" -eq 0
expect has 'OnCalendar=Mon *-*-* 07:00:00 Australia/Sydney' "$out"
expect has 'Persistent=true' "$out"
expect has 'Environment=SCOUT_MAX_TURNS=60' "$out"
expect has 'Environment=SCOUT_TIMEOUT=1800' "$out"
expect has 'Environment=SCOUT_MAX_RUNS=2' "$out"
expect has "arch-scout-run.sh --issue deanjstone/agents#" "$out"
expect has "--target $case_dir/target" "$out"
expect has "Environment=PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin" "$out"
expect has 'TimeoutStartSec=2100' "$out"
expect test ! -e "$FAKE_LOG/systemctl.calls"
expect test ! -e "$HOME/.config/systemd/user/arch-scout.timer"

# a new rolling issue is created from docs/arch-scout-issue.md, with owner-only labels
new_case
rc=0
out=$(PATH="$fake_bin:$PATH" arm_env 2>&1) || rc=$?
expect test "$rc" -eq 0
expect test -s "$HOME/.config/systemd/user/arch-scout.service"
expect test -s "$HOME/.config/systemd/user/arch-scout.timer"
expect grep -qF -- 'arch-scout-run.sh --issue deanjstone/agents#88' "$HOME/.config/systemd/user/arch-scout.service"
expect grep -qE 'issue create .*-R deanjstone/agents' "$FAKE_LOG/gh.calls"
expect grep -qF -- '--label mode:hitl' "$FAKE_LOG/gh.calls"
expect grep -qF -- '--label wave:later' "$FAKE_LOG/gh.calls"
expect grep -qF -- '--label type:chore' "$FAKE_LOG/gh.calls"
expect test -s "$FAKE_LOG/created-body.md"
expect grep -qxF -- '--user daemon-reload' "$FAKE_LOG/systemctl.calls"
expect grep -qxF -- '--user enable --now arch-scout.timer' "$FAKE_LOG/systemctl.calls"
expect has 'arch-scout.timer' "$out"

# an open rolling issue is reused, never duplicated
new_case
echo '[{"number":55,"title":"Architecture scout: weekly findings (pilot)"}]' >"$FAKE_DIR/list.json"
rc=0
out=$(PATH="$fake_bin:$PATH" arm_env 2>&1) || rc=$?
expect test "$rc" -eq 0
expect grep -qF -- 'arch-scout-run.sh --issue deanjstone/agents#55' "$HOME/.config/systemd/user/arch-scout.service"
expect test ! -e "$FAKE_LOG/created-body.md"

# disarm removes the units and stops the timer
rc=0
out=$(PATH="$fake_bin:$PATH" arm_env disarm 2>&1) || rc=$?
expect test "$rc" -eq 0
expect test ! -e "$HOME/.config/systemd/user/arch-scout.timer"
expect test ! -e "$HOME/.config/systemd/user/arch-scout.service"
expect grep -qxF -- '--user disable --now arch-scout.timer' "$FAKE_LOG/systemctl.calls"

# the step refuses a checkout without the run script, and an unknown subcommand
new_case
rc=0
out=$(AGENTS_CHECKOUT="$case_dir/nowhere" SCOUT_TARGET="$case_dir/target" PATH="$fake_bin:$PATH" bash "$arm" 2>&1) || rc=$?
expect test "$rc" -eq 2
expect has 'arch-scout-run.sh' "$out"
rc=0
out=$(arm_env frobnicate 2>&1) || rc=$?
expect test "$rc" -eq 2

if [ "$failed" -ne 0 ]; then
  echo "test-arch-scout: $failed of $cases checks failed" >&2
  exit 1
fi
echo "test-arch-scout: $cases checks passed" >&2
