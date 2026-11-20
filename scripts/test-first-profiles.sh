#!/usr/bin/env bash
# Tests for the first four profiles (agents#10), written before them. These read the real
# profiles/ and generated/ of this repo and pin the owner decisions of 21 Nov 2026 07:12 AEDT
# (the research collector and hygiene are specialists, the analyst is a strictly read-only
# scout, the slot worker is the one profile that writes) and the charter rules each profile
# must carry (a worker never closes the issue; every reporting profile ends on
# `Ready to settle:`). The schema, ceiling and renderer have their own tests; this file only
# pins what these four profiles say. Run by check.sh. Needs only bash and python3.
set -euo pipefail

builtin cd "$(dirname "${BASH_SOURCE[0]}")/.."

failed=0
cases=0

fail() {
  echo "test-first-profiles: FAIL: $1" >&2
  failed=$((failed + 1))
}

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

# tool_list <id> <allow|deny>: the entries of tools.allow or tools.deny, one per line.
tool_list() {
  python3 -I - "profiles/$1.md" "$2" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
end = lines.index("---", 1)
inside = False
for line in lines[1:end]:
    if re.match(r"^tools:\s*$", line):
        inside = True
        continue
    if inside and re.match(r"^\S", line):
        break
    m = re.match(r"^\s+(allow|deny):\s*(.*)$", line)
    if inside and m and m.group(1) == sys.argv[2]:
        for item in m.group(2).strip().strip("[]").split(","):
            if item.strip():
                print(item.strip())
PY
}

expect_field() {
  cases=$((cases + 1))
  local got
  got=$(field "$1" "$2")
  [ "$got" = "$3" ] || fail "$1: $2 is '$got', expected '$3'"
}

expect_tool() {
  cases=$((cases + 1))
  tool_list "$1" "$2" | grep -qxF "$3" || fail "$1: tools.$2 does not list $3"
}

expect_no_tool() {
  cases=$((cases + 1))
  if tool_list "$1" "$2" | grep -qxF "$3"; then fail "$1: tools.$2 lists $3"; fi
}

expect_body() {
  cases=$((cases + 1))
  grep -qF -- "$3" "profiles/$1.md" || fail "$1: body does not say '$3'"
}

expect_file() {
  cases=$((cases + 1))
  [ -s "$1" ] || fail "missing or empty $1"
}

collector=specialist-research-collector
analyst=scout-research-analyst
hygiene=specialist-hygiene
worker=specialist-slot-worker

# --- the four profiles exist, with their generated charter and brief ----------------------
for id in "$collector" "$analyst" "$hygiene" "$worker"; do
  expect_file "profiles/$id.md"
  expect_file "generated/agents/$id.md"
  expect_file "generated/briefs/$id.md"
  expect_field "$id" id "$id"
done

# --- lanes, ranks, sections and models ----------------------------------------------------
expect_field "$collector" rank specialist
expect_field "$collector" section S2
expect_field "$collector" lane read-only
expect_field "$analyst" rank scout
expect_field "$analyst" section S2
expect_field "$analyst" lane read-only
expect_field "$hygiene" rank specialist
expect_field "$hygiene" section S1
expect_field "$hygiene" lane read-only
expect_field "$hygiene" model sonnet
expect_field "$worker" rank specialist
expect_field "$worker" section S3
expect_field "$worker" lane write
for id in "$collector" "$analyst" "$hygiene" "$worker"; do
  expect_field "$id" reports_to staff-xo
  expect_field "$id" escalates_to staff-xo
done

# --- tools: only the slot worker writes ---------------------------------------------------
for id in "$collector" "$analyst" "$hygiene"; do
  expect_no_tool "$id" allow Edit
  expect_no_tool "$id" allow Write
  expect_tool "$id" deny Edit
  expect_tool "$id" deny Write
done
for tool in Read Grep Glob; do
  expect_tool "$analyst" allow "$tool"
done
for tool in Bash WebFetch Edit Write; do
  expect_no_tool "$analyst" allow "$tool"
done
expect_tool "$collector" allow WebFetch
expect_tool "$collector" allow Bash
expect_tool "$hygiene" allow Bash
expect_no_tool "$hygiene" allow WebFetch
for tool in Read Grep Glob Bash WebFetch Edit Write; do
  expect_tool "$worker" allow "$tool"
done

# --- rules each profile must carry --------------------------------------------------------
for id in "$collector" "$analyst" "$hygiene" "$worker"; do
  expect_body "$id" 'Ready to settle:'
done
for id in "$collector" "$analyst" "$worker"; do
  expect_body "$id" 'Never close the issue'
done
expect_body "$hygiene" 'Close nothing'
expect_body "$collector" 'primary source'
expect_body "$analyst" 'Cite'
expect_body "$hygiene" 'needs:owner'
expect_body "$hygiene" 'wave:held'
expect_body "$worker" 'Refs #'
expect_body "$worker" 'slot_await_ci'
expect_body "$worker" 'git push origin HEAD:main'
expect_body "$worker" '## Resolution evidence'

if [ "$failed" -ne 0 ]; then
  echo "test-first-profiles: $failed of $cases checks failed" >&2
  exit 1
fi
echo "test-first-profiles: $cases checks ok" >&2
