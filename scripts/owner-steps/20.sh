#!/usr/bin/env bash
# Owner step for agents#20: arm (or disarm) the weekly Architecture scout. This is a live change
# (a schedule), so no agent runs it: the owner approves this one command.
#
#   bash scripts/owner-steps/20.sh            arm: create the rolling issue if it is missing, write
#                                             the user unit and timer, enable the timer
#   bash scripts/owner-steps/20.sh print      show the issue title and the two units, write nothing
#   bash scripts/owner-steps/20.sh disarm     disable the timer and remove both units
#
# The timer runs scripts/arch-scout-run.sh from the deploy copy of this repo (AGENTS_CHECKOUT,
# default ~/repos/agents) every Monday 07:00 Sydney time, with the owner's hard stops: 60 turns,
# 30 minutes (agents#19). It stops itself after SCOUT_MAX_RUNS runs, 2 for the two-week pilot.
# SCOUT_TARGET names the repo the scout reads (default ~/repos/argus). Needs bash, gh and systemctl.
set -euo pipefail

root=$(builtin cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
checkout=${AGENTS_CHECKOUT:-$HOME/repos/agents}
target=${SCOUT_TARGET:-$HOME/repos/argus}
issue_repo=deanjstone/agents
issue_title="Architecture scout: weekly findings (pilot)"
unit_dir="$HOME/.config/systemd/user"
mode=${1:-arm}

case "$mode" in
  arm | print | disarm) ;;
  *) echo "20.sh: unknown subcommand '$mode' (arm, print or disarm)" >&2; exit 2 ;;
esac

if [ "$mode" = disarm ]; then
  systemctl --user disable --now arch-scout.timer || true
  rm -f "$unit_dir/arch-scout.timer" "$unit_dir/arch-scout.service"
  systemctl --user daemon-reload
  echo "20.sh: disarmed; the rolling issue stays open for the owner to settle"
  exit 0
fi

if [ ! -f "$checkout/scripts/arch-scout-run.sh" ]; then
  echo "20.sh: $checkout has no scripts/arch-scout-run.sh; run: git -C $checkout pull --ff-only" >&2
  exit 2
fi
if [ ! -d "$target" ]; then
  echo "20.sh: SCOUT_TARGET '$target' is not a directory" >&2
  exit 2
fi

issue_number="<new issue>"
if [ "$mode" = arm ]; then
  listing=$(gh issue list -R "$issue_repo" --state open --search "\"$issue_title\" in:title" --json number,title)
  existing=$(python3 -I -c 'import json, sys
rows = [r for r in json.loads(sys.argv[1]) if r["title"] == sys.argv[2]]
print(rows[0]["number"] if rows else "")' "$listing" "$issue_title")
  if [ -n "$existing" ]; then
    issue_number=$existing
  else
    url=$(gh issue create -R "$issue_repo" --title "$issue_title" --body-file "$root/docs/arch-scout-issue.md" \
      --label mode:hitl --label wave:later --label type:chore)
    issue_number=${url##*/}
  fi
fi

service="[Unit]
Description=Weekly read-only Architecture scout (agents#20)
Documentation=https://github.com/deanjstone/agents/issues/20

[Service]
Type=oneshot
# A user unit never sources a login profile: claude and gh are found through this PATH.
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin
# The owner's caps (agents#19): 60 turns and 30 minutes are hard stops, 60k output tokens a target.
Environment=SCOUT_MAX_TURNS=60
Environment=SCOUT_TIMEOUT=1800
Environment=SCOUT_TOKEN_TARGET=60000
# Two runs is the two-week pilot. Raise it to extend the pilot.
Environment=SCOUT_MAX_RUNS=2
ExecStart=/usr/bin/env bash $checkout/scripts/arch-scout-run.sh --issue $issue_repo#$issue_number --target $target
# The script's own 30 minute timeout fires first; this leaves room to post the comment.
TimeoutStartSec=2100
Nice=10
MemoryMax=2G
StandardOutput=journal
StandardError=journal
"
timer="[Unit]
Description=Weekly Architecture scout, Mondays 07:00 Sydney time (agents#20)
Documentation=https://github.com/deanjstone/agents/issues/20

[Timer]
OnCalendar=Mon *-*-* 07:00:00 Australia/Sydney
# A host that was off at 07:00 runs when it comes back.
Persistent=true

[Install]
WantedBy=timers.target
"

if [ "$mode" = print ]; then
  echo "issue: $issue_repo \"$issue_title\" (#$issue_number)"
  echo
  echo "# $unit_dir/arch-scout.service"
  echo "$service"
  echo "# $unit_dir/arch-scout.timer"
  echo "$timer"
  exit 0
fi

mkdir -p "$unit_dir"
printf '%s' "$service" >"$unit_dir/arch-scout.service"
printf '%s' "$timer" >"$unit_dir/arch-scout.timer"
systemctl --user daemon-reload
systemctl --user enable --now arch-scout.timer
systemctl --user list-timers arch-scout.timer --no-pager || true
echo "20.sh: armed arch-scout.timer: rolling issue $issue_repo#$issue_number, target $target, next run in the list above"
