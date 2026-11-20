#!/usr/bin/env bash
# Tests for the Learned-line proposal flow (agents#16, D8), written before it. An agent
# proposes one Learned line to its profile as a branch and a PR to this repo that the owner
# reviews; the profile is never edited in place. Two scripts carry it:
#
#   scripts/propose-learned.sh   builds the proposal: one line, one profile, a learned/ branch
#   scripts/check-learned.sh     checks a proposal against its base (the shape of the change)
#
# The cap itself (10 lines of at most 200 characters) is enforced by scripts/check-profiles.sh
# (AGP010) in scripts/check.sh; the cases at the end pin that a proposal over the cap fails
# there too. Each case builds a throwaway fixture repo with --root, so no broken proposal is
# ever a tracked file of this repo. Run by check.sh. Needs only bash, git and python3.
set -euo pipefail

builtin cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo=$PWD
# CI exports these for the real repo; a fixture has its own history and branch.
unset PROFILE_BASE LEARNED_PROPOSAL
propose="$repo/scripts/propose-learned.sh"
checker="$repo/scripts/check-learned.sh"
profile_checker="$repo/scripts/check-profiles.sh"
renderer="$repo/scripts/render.sh"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

cases=0
failed=0
fx=""
rc=0
out=""

fail() {
  echo "test-learned: FAIL: $1" >&2
  failed=$((failed + 1))
}

target=specialist-slot-worker
other=specialist-hygiene
src="https://github.com/deanjstone/agents/issues/16#issuecomment-1"

# A fresh fixture on branch main: the real profiles, doctrine and templates, rendered.
new_fixture() {
  cases=$((cases + 1))
  fx="$scratch/fx$cases"
  mkdir -p "$fx"
  cp -r "$repo/profiles" "$repo/doctrine" "$repo/templates" "$fx/"
  git -C "$fx" init -q -b main
  git -C "$fx" config user.email test@example.invalid
  git -C "$fx" config user.name test
  bash "$renderer" --root "$fx" >/dev/null 2>&1
  git -C "$fx" add -A
  git -C "$fx" commit -q -m "fixture"
}

commit_all() {
  git -C "$fx" add -A
  git -C "$fx" commit -q -m "${1:-change}"
}

# add_learned <profile-id> <n>: give a profile a Learned section of n well-formed lines.
add_learned() {
  {
    printf '\n## Learned\n\n'
    for i in $(seq 1 "$2"); do
      printf -- '- 2026-11-0%s: lesson %s ([source](https://example.invalid/%s))\n' "$((i % 9 + 1))" "$i" "$i"
    done
  } >>"$fx/profiles/$1.md"
}

run_propose() {
  rc=0
  out=$(bash "$propose" --root "$fx" --no-pr "$@" 2>&1) || rc=$?
}

run_check() {
  rc=0
  out=$(bash "$checker" --root "$fx" "$@" 2>&1) || rc=$?
}

expect_pass() {
  if [ "$rc" -ne 0 ]; then fail "$1: expected pass, exit $rc: $out"; fi
}

expect_fail() {
  if [ "$rc" -eq 0 ]; then
    fail "$1: expected failure, got pass: $out"
  elif ! grep -qF -- "$2" <<<"$out"; then
    fail "$1: expected '$2' in the output: $out"
  fi
}

learned_count() {
  python3 -I - "$fx/profiles/$1.md" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
if "## Learned" not in lines:
    print(0)
else:
    tail = lines[lines.index("## Learned") + 1:]
    print(len([l for l in tail if l.strip()]))
PY
}

branch_now() { git -C "$fx" symbolic-ref --short HEAD; }

# --- propose-learned.sh: the proposal ------------------------------------------------------

# A profile with no Learned section gets one, with the one line, on a learned/ branch.
new_fixture
main_before=$(git -C "$fx" rev-parse main)
run_propose --profile "$target" --line "Run the check before the push" --source "$src" --date 2026-11-21
expect_pass "propose into a profile with no Learned section"
[ "$(learned_count "$target")" = 1 ] || fail "no-Learned: expected one Learned line, got $(learned_count "$target")"
case "$(branch_now)" in
  learned/"$target"-*) ;;
  *) fail "no-Learned: branch is '$(branch_now)', expected learned/$target-<slug>" ;;
esac
[ "$(git -C "$fx" rev-parse main)" = "$main_before" ] || fail "no-Learned: main moved; a profile must never be edited in place"
grep -qF -- "- 2026-11-21: Run the check before the push ([source]($src))" "$fx/profiles/$target.md" \
  || fail "no-Learned: the formatted line is not in the profile"
subject=$(git -C "$fx" log -1 --format=%s)
[ "$subject" = "docs: propose a Learned line for $target" ] || fail "no-Learned: commit subject is '$subject'"
[ -z "$(git -C "$fx" status --porcelain)" ] || fail "no-Learned: the tree is not clean after the commit"
git -C "$fx" diff --name-only main HEAD | sort >"$scratch/changed-$cases"
expected=$(printf '%s\n' "generated/agents/$target.md" "generated/briefs/$target.md" "profiles/$target.md" | sort)
[ "$(cat "$scratch/changed-$cases")" = "$expected" ] || fail "no-Learned: changed files are not the profile and its two generated files: $(cat "$scratch/changed-$cases")"
bash "$renderer" --root "$fx" --check >/dev/null 2>&1 || fail "no-Learned: generated/ is stale after the proposal"
bash "$profile_checker" --root "$fx" --base main >/dev/null 2>&1 || fail "no-Learned: the proposal does not pass the profile check"
run_check --proposal --base main
expect_pass "no-Learned: check-learned on the proposal"

# A profile with a Learned section gains exactly one line at the end.
new_fixture
add_learned "$target" 3
commit_all "learned"
run_propose --profile "$target" --line "Read the issue comments first" --source "$src" --date 2026-11-21
expect_pass "propose into an existing Learned section"
[ "$(learned_count "$target")" = 4 ] || fail "existing: expected 4 Learned lines, got $(learned_count "$target")"
[ "$(tail -n1 "$fx/profiles/$target.md")" = "- 2026-11-21: Read the issue comments first ([source]($src))" ] \
  || fail "existing: the new line is not the last line of the profile"
added=$(git -C "$fx" diff --numstat main HEAD -- "profiles/$target.md" | cut -f1)
removed=$(git -C "$fx" diff --numstat main HEAD -- "profiles/$target.md" | cut -f2)
{ [ "$added" = 1 ] && [ "$removed" = 0 ]; } || fail "existing: profile diff is +$added/-$removed, expected +1/-0"
run_check --proposal --base main
expect_pass "existing: check-learned on the proposal"

# The cap: a full Learned section refuses a proposal, leaves no branch and no change.
new_fixture
add_learned "$target" 10
commit_all "learned at the cap"
run_propose --profile "$target" --line "One more" --source "$src"
expect_fail "propose at the cap" "cap"
[ "$(branch_now)" = main ] || fail "at-cap: left the branch '$(branch_now)'"
[ -z "$(git -C "$fx" status --porcelain)" ] || fail "at-cap: left changes in the tree"
[ "$(learned_count "$target")" = 10 ] || fail "at-cap: the Learned section changed"

# Refusals: each leaves main, the tree and the branch alone.
refuse() { # refuse <label> <expected text> <propose args...>
  local label=$1 expected=$2
  shift 2
  new_fixture
  run_propose "$@"
  expect_fail "$label" "$expected"
  [ "$(branch_now)" = main ] || fail "$label: left the branch '$(branch_now)'"
  [ -z "$(git -C "$fx" status --porcelain)" ] || fail "$label: left changes in the tree"
}

long_text=$(python3 -I -c 'print("x" * 190)')
refuse "unknown profile" "no such profile" --profile specialist-nope --line "text" --source "$src"
refuse "path in the profile id" "profile id" --profile "../README" --line "text" --source "$src"
refuse "missing line" "--line" --profile "$target" --source "$src"
refuse "missing source" "--source" --profile "$target" --line "text"
refuse "source that is not https" "source" --profile "$target" --line "text" --source "file:///etc/passwd"
refuse "empty line" "empty" --profile "$target" --line "   " --source "$src"
refuse "line with a newline" "one line" --profile "$target" --line $'first\nsecond' --source "$src"
refuse "line over the length cap" "200" --profile "$target" --line "$long_text" --source "$src"
refuse "bad date" "date" --profile "$target" --line "text" --source "$src" --date 21-11-2026

# A dirty tree is refused: the proposal commit must hold only the proposal.
new_fixture
echo "stray" >"$fx/stray.txt"
run_propose --profile "$target" --line "text" --source "$src"
expect_fail "dirty tree" "not clean"

# A line already in Learned is refused; so is a branch that already exists.
new_fixture
run_propose --profile "$target" --line "Same lesson" --source "$src" --date 2026-11-21
expect_pass "first proposal of a line"
git -C "$fx" switch -q main
run_propose --profile "$target" --line "Same lesson" --source "$src" --date 2026-11-22
expect_fail "branch of an earlier proposal exists" "branch"
new_fixture
add_learned "$target" 1
python3 -I - "$fx/profiles/$target.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read().rstrip("\n")
open(path, "w", encoding="utf-8").write(text + "\n- 2026-11-05: Same lesson ([source](https://example.invalid/9))\n")
PY
commit_all "learned with a lesson"
run_propose --profile "$target" --line "Same lesson" --source "$src"
expect_fail "duplicate of a line already in Learned" "already"

# --- check-learned.sh: the shape of a proposal ----------------------------------------------

# Outside a proposal the check does nothing: the owner may edit Learned lines on trunk.
new_fixture
add_learned "$target" 3
add_learned "$other" 2
commit_all "owner edits two profiles"
run_check --base main~1
expect_pass "not a proposal"
grep -qF "not a proposal" <<<"$out" || fail "not a proposal: no skip note: $out"

# Proposal mode by flag, by LEARNED_PROPOSAL, and by a learned/ branch name.
new_fixture
add_learned "$target" 2
add_learned "$other" 2
git -C "$fx" switch -q -c feature
commit_all "two profiles"
run_check --proposal --base main
expect_fail "flag: two profiles touched" "LRN002"
rc=0
out=$(LEARNED_PROPOSAL=1 bash "$checker" --root "$fx" --base main 2>&1) || rc=$?
expect_fail "env: two profiles touched" "LRN002"
git -C "$fx" switch -q -c learned/two-profiles
run_check --base main
expect_fail "branch name: two profiles touched" "LRN002"

# Two lines in one profile.
new_fixture
git -C "$fx" switch -q -c learned/two-lines
add_learned "$target" 2
commit_all "two lines"
run_check --proposal --base main
expect_fail "two lines added" "LRN004"

# A line edited or removed in place.
new_fixture
add_learned "$target" 3
commit_all "learned"
git -C "$fx" switch -q -c learned/edit
sed -i 's/lesson 2/lesson two, reworded/' "$fx/profiles/$target.md"
commit_all "edit in place"
run_check --proposal --base main
expect_fail "line edited in place" "LRN004"

new_fixture
add_learned "$target" 3
commit_all "learned"
git -C "$fx" switch -q -c learned/remove
sed -i '/lesson 2/d' "$fx/profiles/$target.md"
printf -- '- 2026-11-21: Fresh ([source](https://example.invalid/f))\n' >>"$fx/profiles/$target.md"
commit_all "remove one, add one"
run_check --proposal --base main
expect_fail "line removed" "LRN004"

# A change outside the Learned section: front matter, then another section.
new_fixture
git -C "$fx" switch -q -c learned/front
sed -i 's/^lane: .*/lane: read-only/' "$fx/profiles/$target.md"
printf '\n## Learned\n\n- 2026-11-21: Fresh ([source](https://example.invalid/f))\n' >>"$fx/profiles/$target.md"
commit_all "front matter"
run_check --proposal --base main
expect_fail "front matter changed" "LRN003"

new_fixture
git -C "$fx" switch -q -c learned/section
sed -i 's/^## Boundaries$/## Boundaries\n\n- A new boundary./' "$fx/profiles/$target.md"
printf '\n## Learned\n\n- 2026-11-21: Fresh ([source](https://example.invalid/f))\n' >>"$fx/profiles/$target.md"
commit_all "section"
run_check --proposal --base main
expect_fail "another section changed" "LRN003"

# A file outside the profile and its generated pair.
new_fixture
git -C "$fx" switch -q -c learned/readme
printf '\n## Learned\n\n- 2026-11-21: Fresh ([source](https://example.invalid/f))\n' >>"$fx/profiles/$target.md"
echo "extra" >"$fx/notes.md"
commit_all "extra file"
run_check --proposal --base main
expect_fail "extra file" "LRN001"

# A line that does not follow the format: date, text, source link.
new_fixture
git -C "$fx" switch -q -c learned/format
printf '\n## Learned\n\n- always run the check\n' >>"$fx/profiles/$target.md"
commit_all "bad format"
run_check --proposal --base main
expect_fail "line without date and source" "LRN005"

# A proposal that changes no Learned line.
new_fixture
git -C "$fx" switch -q -c learned/empty
echo "x" >"$fx/x.txt"
commit_all "nothing"
run_check --proposal --base main
expect_fail "no Learned change" "LRN006"

# A base that does not exist is an error, not a pass.
new_fixture
run_check --proposal --base no-such-ref
expect_fail "unknown base" "base"

# --- the cap, end to end -------------------------------------------------------------------

# A hand-made proposal that lifts Learned over the cap passes the shape check and fails the
# profile check that check.sh runs (AGP010).
new_fixture
add_learned "$target" 10
commit_all "learned at the cap"
git -C "$fx" switch -q -c learned/over-cap
printf -- '- 2026-11-21: Eleventh ([source](https://example.invalid/11))\n' >>"$fx/profiles/$target.md"
commit_all "eleventh line"
run_check --proposal --base main
expect_pass "over cap: the shape of the proposal is one line"
rc=0
out=$(bash "$profile_checker" --root "$fx" --base main 2>&1) || rc=$?
expect_fail "over cap: check-profiles" "AGP010"

# --- wiring: check.sh runs these, CI passes the head branch -----------------------------------
cases=$((cases + 1))
grep -qF "scripts/test-learned.sh" scripts/check.sh || fail "check.sh does not run scripts/test-learned.sh"
cases=$((cases + 1))
grep -qF "scripts/check-learned.sh" scripts/check.sh || fail "check.sh does not run scripts/check-learned.sh"
cases=$((cases + 1))
grep -qF "LEARNED_PROPOSAL" .github/workflows/check.yml || fail "check.yml does not pass LEARNED_PROPOSAL"
cases=$((cases + 1))
grep -qF "github.head_ref" .github/workflows/check.yml || fail "check.yml does not read the pull request's head branch"

if [ "$failed" -ne 0 ]; then
  echo "test-learned: FAIL: $failed of $cases checks failed" >&2
  exit 1
fi
echo "test-learned: $cases checks passed" >&2
