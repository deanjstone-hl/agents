#!/usr/bin/env bash
# Proposes one Learned line to a profile as a branch and a PR to this repo (agents#16, D8):
# a profile never edits itself in place, and the owner reviews every proposed line.
#
#   bash scripts/propose-learned.sh --profile <id> --line "<lesson>" --source <https url>
#        [--date YYYY-MM-DD] [--root <dir>] [--no-pr]
#
# Run it from a clean checkout of the agents repo. It adds `- <date>: <lesson> ([source](<url>))`
# to the profile's `## Learned` section on a new learned/<id>-<slug> branch, renders generated/,
# runs the profile check and commits; without --no-pr it then pushes the branch and opens the PR
# (merge accepts the line, close declines it). It refuses a Learned section already at its cap.
# scripts/check-learned.sh checks the shape of the result in CI. The logic is
# scripts/propose_learned.py. Needs only bash, git and python3 (and gh for the PR).
set -euo pipefail

exec python3 -I "$(dirname "${BASH_SOURCE[0]}")/propose_learned.py" "$@"
