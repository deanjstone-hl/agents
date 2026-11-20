#!/usr/bin/env bash
# The host-wide heavy lock wiring of scripts/check.sh (argus-config#1506): the vendored copy
# still matches its lock file, check.sh re-runs itself under the lock, and a busy lock gives
# exit 75 without running a step. Run by check.sh as its last step.
set -euo pipefail

builtin cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() {
  echo "check-heavy-lock: FAIL: $1" >&2
  exit 1
}

digest=$(sha256sum scripts/heavy-lock.sh | cut -d' ' -f1)
grep -q "^${digest}  heavy-lock.sh\$" scripts/heavy-lock.lock ||
  fail "scripts/heavy-lock.sh differs from the sha256 in scripts/heavy-lock.lock; run scripts/sync-heavy-lock.sh from argus-config"

grep -q 'heavy-lock.sh' scripts/check.sh && grep -q 'HEAVY_LOCK_HELD' scripts/check.sh ||
  fail "scripts/check.sh does not re-run itself under the heavy lock"

scratch=$(mktemp -d)
holder_pid=""
cleanup() {
  [ -z "$holder_pid" ] || kill "$holder_pid" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT

lock_file="$scratch/heavy.lock"
LOCK_FILE="$lock_file" bash -c 'exec 9>>"$LOCK_FILE"; flock 9; echo held; sleep 30' >"$scratch/held" &
holder_pid=$!
for _ in $(seq 1 100); do
  [ -s "$scratch/held" ] && break
  sleep 0.1
done
[ -s "$scratch/held" ] || fail "the test lock holder did not start"

rc=0
env -u HEAVY_LOCK_HELD HEAVY_LOCK_FILE="$lock_file" HEAVY_LOCK_TIMEOUT=1 HEAVY_LOCK_PSI_FILE="$scratch/none" \
  bash scripts/check.sh >"$scratch/out" 2>&1 || rc=$?
[ "$rc" -eq 75 ] || fail "a busy lock gave exit $rc, not 75: $(cat "$scratch/out")"
grep -q "waiting for the host lock" "$scratch/out" || fail "no 'waiting for the host lock' line"
if grep -q "check: step" "$scratch/out"; then
  fail "check.sh ran a step while the lock was held"
fi
echo "check-heavy-lock: ok"
