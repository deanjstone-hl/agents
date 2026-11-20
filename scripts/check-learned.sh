#!/usr/bin/env bash
# Checks the shape of a Learned-line proposal (agents#16, D8): one PR adds one line to one
# profile's Learned section and changes nothing else. Run by scripts/check.sh.
#
#   bash scripts/check-learned.sh [--root <dir>] [--base <ref>] [--proposal]
#
# It checks a proposal only: with --proposal, with LEARNED_PROPOSAL=1 (CI sets it for a pull
# request whose head branch starts with learned/), or on a local learned/* branch; anywhere
# else it prints a note and passes. --base (or PROFILE_BASE) names the ref the change is
# compared with (default origin/main); a missing ref fails a proposal. The cap on the Learned
# section is scripts/check-profiles.sh (AGP010), not this check. The logic is
# scripts/check_learned.py; its header lists the diagnostic codes (LRN001 and up). Needs only
# bash, git and python3.
set -euo pipefail

exec python3 -I "$(dirname "${BASH_SOURCE[0]}")/check_learned.py" "$@"
