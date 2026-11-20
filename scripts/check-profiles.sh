#!/usr/bin/env bash
# Checks profiles/*.md against schema/profile.schema.json (agents#8): required and unknown
# fields, ranks, ids, the body layout, the Voice and Learned caps, and authority fields
# changed without a version bump against a base ref. Run by scripts/check.sh.
#
#   bash scripts/check-profiles.sh [--root <dir>] [--base <ref>]
#
# --base (or PROFILE_BASE) names the ref the version-bump rule compares with; a ref that
# does not exist is an error. Without it the base is origin/main, and a missing origin/main
# skips the rule with a note. The logic is scripts/check_profiles.py; diagnostic codes
# (AGP001 and up) are listed at the top of that file. Needs only bash and python3 (and git
# for the version rule).
set -euo pipefail

exec python3 -I "$(dirname "${BASH_SOURCE[0]}")/check_profiles.py" "$@"
