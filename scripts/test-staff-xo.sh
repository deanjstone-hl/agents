#!/usr/bin/env bash
# Tests for the staff-xo profile and the shared working rules (agents#15), written before them.
# These read the real profiles/, doctrine/ and generated/ of this repo. They pin the envelope
# of the orchestrator (the one staff-rank profile, section `command`, reporting to the owner),
# the role rules lifted from the orchestrator charter that the profile must carry, and the
# shared rules that move into doctrine/culture.md and so reach every generated charter and
# brief. The schema, ceiling and renderer have their own tests; this file only pins what
# staff-xo and the culture say. Run by check.sh. Needs only bash and python3.
set -euo pipefail

builtin cd "$(dirname "${BASH_SOURCE[0]}")/.."

failed=0
cases=0

fail() {
  echo "test-staff-xo: FAIL: $1" >&2
  failed=$((failed + 1))
}

xo=staff-xo
tick=staff-tick

# field <id> <key>: the value of a top-level front matter key.
field() {
  python3 -I - "profiles/$1.md" "$2" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
end = lines.index("---", 1)
for line in lines[1:end]:
    m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
    if m and m.group(1) == sys.argv[2]:
        print(m.group(2).strip().strip('"'))
        break
PY
}

expect_field() {
  cases=$((cases + 1))
  local got
  got=$(field "$1" "$2")
  [ "$got" = "$3" ] || fail "$1: $2 is '$got', expected '$3'"
}

expect_in() {
  cases=$((cases + 1))
  [ -s "$1" ] || { fail "missing or empty $1"; return; }
  grep -qF -- "$2" "$1" || fail "$1 does not say '$2'"
}

expect_not_in() {
  cases=$((cases + 1))
  [ -s "$1" ] || { fail "missing or empty $1"; return; }
  if grep -qF -- "$2" "$1"; then fail "$1 says '$2'"; fi
}

# --- both profiles exist, with their generated charter and brief ----------------------------
for id in "$xo" "$tick"; do
  for file in "profiles/$id.md" "generated/agents/$id.md" "generated/briefs/$id.md"; do
    cases=$((cases + 1))
    [ -s "$file" ] || fail "missing or empty $file"
  done
  expect_field "$id" id "$id"
done

# --- envelope: two staff profiles (agents#26), both in the command section -------------------
# Aquila (staff-xo) is the owner's pathway and answers to the owner. The tick (staff-tick)
# holds the leases and reports to Aquila. Both need loop-state tools, so both are `staff`.
for id in "$xo" "$tick"; do
  expect_field "$id" rank staff
  expect_field "$id" section command
  expect_field "$id" lane write
  expect_field "$id" model sonnet
  expect_in "profiles/$id.md" 'allow: ["*"]'
done
expect_field "$xo" reports_to owner
expect_field "$xo" escalates_to owner
expect_field "$tick" reports_to "$xo"
expect_field "$tick" escalates_to "$xo"

# --- units.md allows a second staff profile and names both ------------------------------------
expect_in doctrine/units.md 'More than one profile may hold the `staff` rank'
expect_in doctrine/units.md 'profile: staff-xo'
expect_in doctrine/units.md 'profile: staff-tick'
expect_not_in doctrine/units.md 'Aquila (`direction` and `afk`)'

# --- the owner-facing role (staff-xo): what the owner-chat charter says --------------------
for phrase in \
  'the only session called Aquila' \
  "owner's pathway" \
  'Answer to the name' \
  "Don't sign GitHub comments" \
  'Aquila (WSL2)' \
  '`staff-tick`' \
  'The Aquila Tick T3 project should be tied to' \
  '`owner_turn` and nothing else' \
  '`status_read`' \
  '`directives_read`' \
  'Never call `tick_gate`' \
  '`slot_*`' \
  '`child_*`' \
  '`owner_thread_set`' \
  'You close no slot issue' \
  'You start no children and no workers' \
  '[tick-report]' \
  '[owner-handover]' \
  'Never call `owner_turn` for a `[tick-report]`' \
  '`t3_thread_configure`' \
  '`t3_thread_update`' \
  '`directives_set`' \
  '[owner-relay]' \
  'tick-webhook-post.sh' \
  'The webhook URL is a secret' \
  'Live changes need the owner' \
  'An approved live step runs once' \
  'void 24 hours' \
  '`AskUserQuestion`' \
  'File suspected bugs' \
  'deanjstone/research' \
  'Check the tick' \
  'read 186 of 186' \
  'Compact, don' \
  'status card' \
  'runbook'; do
  expect_in "profiles/$xo.md" "$phrase"
done
# ... and not the tick's own work.
for phrase in \
  'Only this thread launches AFK workers' \
  'Filling a slot' \
  '`child_start`' \
  '`child_close`' \
  '`promotion_flag_raise`' \
  'verify-claim.sh merged' \
  'verify-claim.sh pushed' \
  'Reactive launch only' \
  'Single-thread mode' \
  'Ready to settle:'; do
  expect_not_in "profiles/$xo.md" "$phrase"
done

# --- the tick (staff-tick): the orchestrator charter's role text ----------------------------
for phrase in \
  'You are not Aquila' \
  'Aquila (`staff-xo`)' \
  '`direction`' \
  '`afk`' \
  'Only this thread launches AFK workers' \
  'Launch and delegate without asking' \
  'Delegate by default' \
  'Code fixes go to a worker slot' \
  'Keep launched threads out of `~/aquila`' \
  'T3 updates' \
  'No overnight hold' \
  'The lease decides who runs' \
  'Owner questions on a tick park' \
  'Never merge a worker' \
  'never `link_pull_request` or `watch_pull_request`' \
  '`t3_thread_configure`' \
  'you are not the tick' \
  '`directives_set`' \
  '`owner_turn`' \
  '[aquila-nudge]' \
  '[afk-nudge]' \
  '[owner-relay]' \
  'A nudge runs the whole checklist' \
  'split mode' \
  'File suspected bugs' \
  '`child_start`' \
  '`child_close`' \
  'Only you close a slot issue' \
  'verify-claim.sh merged' \
  'verify-claim.sh pushed' \
  '`promotion_flag_raise`' \
  'A close counts as verified only when' \
  'Reactive launch only' \
  'Waits for the owner' \
  'runbook' \
  'Ready to settle:'; do
  expect_in "profiles/$tick.md" "$phrase"
done
# The tick does not take Aquila's name, single-thread mode or the owner-facing mechanics.
for phrase in \
  'the only session called Aquila' \
  'Answer to the name' \
  'Single-thread mode' \
  'Aquila (WSL2)' \
  'status card, the data map' \
  'tick-webhook-post.sh'; do
  expect_not_in "profiles/$tick.md" "$phrase"
done

# --- the orchestrator's mechanics stay in argus-config; the profiles do not copy them -------
for id in "$xo" "$tick"; do
  for phrase in \
    'flock -w 120' \
    'sync-deploy-copy.sh' \
    'brrr-notify' \
    'Window ladder' \
    'Compact at 250k' \
    'Source: `envs/wsl2/charters/orchestrator.md`'; do
    expect_not_in "profiles/$id.md" "$phrase"
  done
done

# --- the shared rules live in the culture, once, and reach every generated charter ----------
culture=doctrine/culture.md
for phrase in \
  'State, not memory' \
  'Trust the labels' \
  'Own the outcome' \
  'explicit yes' \
  'markdown link' \
  'AEDT' \
  'Owner-first Resolution' \
  'Plain commands' \
  'Ready to settle:'; do
  expect_in "$culture" "$phrase"
done
for generated in generated/agents/*.md generated/briefs/*.md; do
  for phrase in 'State, not memory' 'Own the outcome' 'Owner-first Resolution' 'Plain commands'; do
    expect_in "$generated" "$phrase"
  done
done
# The rules the profile lifts into the culture are not repeated in the profile.
for phrase in \
  '**State, not memory.**' \
  '**Trust the labels.**' \
  '**Own the outcome.**' \
  '**Notation.**' \
  '**Plain commands.**'; do
  expect_not_in "profiles/$xo.md" "$phrase"
  expect_not_in "profiles/$tick.md" "$phrase"
done

# --- the check runs this file ---------------------------------------------------------------
expect_in scripts/check.sh 'test-staff-xo.sh'

if [ "$failed" -ne 0 ]; then
  echo "test-staff-xo: $failed of $cases checks failed" >&2
  exit 1
fi
echo "test-staff-xo: $cases checks ok" >&2
