#!/usr/bin/env bash
# Checks units/*.yaml against schema/unit.schema.json and the profiles they name (agents#11):
# both fire-team profiles exist, the reviewer is not the builder, cannot write, takes a diff,
# and does not report to the builder; a gate that stays mechanical is always listed.
#
#   bash scripts/check-units.sh [--root <dir>]
#
# Prints `units/<file>:<line>: AGUnnn: <message>` for each failure; the codes are listed at the
# top of scripts/check_units.py. Run by scripts/check.sh. Needs only bash and python3.
set -euo pipefail

exec python3 -I "$(dirname "${BASH_SOURCE[0]}")/check_units.py" "$@"
