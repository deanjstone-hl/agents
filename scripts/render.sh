#!/usr/bin/env bash
# Renders profiles/*.md into the committed generated/ output (agents#9): a Claude subagent
# file and a brief per profile, joined with doctrine/culture.md and templates/brief.md.
#
#   bash scripts/render.sh [--root <dir>]                 write generated/
#   bash scripts/render.sh [--root <dir>] --check         fail if generated/ is stale
#   bash scripts/render.sh [--root <dir>] --brief <id> --issue-file <file> [--input <name>=<file>]...
#                                                         print one finished brief to stdout
#
# The original issue text is a mandatory brief input: --brief without --issue-file fails.
# The logic is scripts/render.py; its header lists the diagnostic codes (AGR001 and up).
# Run by scripts/check.sh as `render.sh --check`. Needs only bash and python3.
set -euo pipefail

exec python3 -I "$(dirname "${BASH_SOURCE[0]}")/render.py" "$@"
