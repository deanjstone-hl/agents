#!/usr/bin/env bash
# Says whether a change is large enough for its fire team's reviewer to run (agents#11, D6).
# The threshold is read from units/*.yaml; the count is the added plus deleted lines of
# `git diff --numstat <base> <head>`, binary files as none. A change above the threshold needs
# the reviewer; at or below it does not. The answer is advice: CI and verify-claim.sh stay the gate.
#
#   bash scripts/review-needed.sh [--root <dir>] [--base <ref>] [--head <ref>] [--team <name>]
#
# Prints `required (N changed lines, threshold T, team X): launch <reviewer>` or
# `skip (N changed lines, threshold T, team X)` and exits 0; exits 2 when it cannot decide
# (bad ref, no unit file, an unknown or ambiguous team). Defaults: base origin/main, head HEAD.
# Needs only bash, git and python3.
set -euo pipefail

exec python3 -I "$(dirname "${BASH_SOURCE[0]}")/review_needed.py" "$@"
