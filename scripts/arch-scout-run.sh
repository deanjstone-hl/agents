#!/usr/bin/env bash
# One run of the weekly Architecture scout (agents#20). Read-only: the scout has Read, Grep and
# Glob and posts nothing itself; this script posts its reply as one comment on the rolling issue.
#
#   bash scripts/arch-scout-run.sh --issue <owner/repo#N> --target <dir> [--dry-run] [--force]
#
# What it does, in order:
#   1. reads the rolling issue (its body is the brief's issue text, its comments the earlier
#      runs and the owner's answers) and stops if this week already has a run, or the pilot's
#      run cap is reached, unless --force;
#   2. renders the brief of profiles/scout-architecture.md (scripts/render.sh --brief);
#   3. runs `claude -p` in <dir> as that profile's own agent file, tools limited to the profile's
#      list, under the owner's hard stops: --max-turns 60 and a 30 minute timeout (agents#19);
#   4. reads the output tokens back from the session transcript (agents#19: a target of about
#      60k, never a stop) and posts one comment: at most 5 findings, each ending on a yes-or-no
#      question, then the run stats and a machine-readable marker.
#
# Environment (the unit written by scripts/owner-steps/20.sh sets the first four):
#   SCOUT_MAX_TURNS   turn cap, default 60. Lower it when a run goes over the token target
#   SCOUT_TIMEOUT     wall-clock cap in seconds, default 1800
#   SCOUT_TOKEN_TARGET  output-token target to report against, default 60000
#   SCOUT_MAX_RUNS    runs the pilot allows, default 2 (two weeks); raise it to extend the pilot
#   SCOUT_STATE_DIR   per-run files (brief, reply, comment), default ~/.local/state/agents/arch-scout
#   SCOUT_WEEK, SCOUT_WHEN  override the ISO week and the AEDT stamp (tests)
#   CLAUDE_BIN        the claude binary, default `claude` on PATH, then ~/.local/bin/claude
#
# Exit: 0 posted and within the hard stops (an over-target run is posted and flagged, still 0),
# 2 bad arguments, 3 posted but the run failed a hard stop or came back unusable, 4 the comment
# could not be posted (it is kept in $SCOUT_STATE_DIR/last-comment.md), 5 no claude binary.
# Needs bash, python3, gh and claude.
set -euo pipefail

root=$(builtin cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
report="$root/scripts/scout_report.py"
profile_id=scout-architecture
agent_file="$root/generated/agents/$profile_id.md"

issue_ref=""
target=""
dry_run=0
force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --issue) issue_ref="${2:-}"; shift 2 ;;
    --target) target="${2:-}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --force) force=1; shift ;;
    *) echo "arch-scout-run: unknown argument $1" >&2; exit 2 ;;
  esac
done
if ! [[ "$issue_ref" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+#[0-9]+$ ]]; then
  echo "arch-scout-run: --issue <owner/repo#N> is required" >&2
  exit 2
fi
if [ ! -d "$target" ]; then
  echo "arch-scout-run: --target '$target' is not a directory" >&2
  exit 2
fi
target=$(builtin cd "$target" && pwd)
target_name=$(basename "$target")
issue_repo=${issue_ref%#*}
issue_number=${issue_ref##*#}

max_turns=${SCOUT_MAX_TURNS:-60}
timeout_s=${SCOUT_TIMEOUT:-1800}
token_target=${SCOUT_TOKEN_TARGET:-60000}
max_runs=${SCOUT_MAX_RUNS:-2}
state_root=${SCOUT_STATE_DIR:-$HOME/.local/state/agents/arch-scout}
week=${SCOUT_WEEK:-$(date +%G-W%V)}
when=${SCOUT_WHEN:-$(TZ=Australia/Sydney date '+%-d %b %Y %H:%M %Z')}

tools=$(python3 -I "$report" agent --file "$agent_file" --field tools)
deny=$(python3 -I "$report" agent --file "$agent_file" --field disallowed)
model=$(python3 -I "$report" agent --file "$agent_file" --field model)
agents_json=$(python3 -I "$report" agent --file "$agent_file" --field agents-json)

claude_bin=${CLAUDE_BIN:-$(command -v claude || true)}
[ -n "$claude_bin" ] || claude_bin="$HOME/.local/bin/claude"

session_id=$(python3 -I -c 'import uuid; print(uuid.uuid4())')
command_line=(timeout "$timeout_s" "$claude_bin" -p --agents "$agents_json" --agent "$profile_id")
[ -z "$model" ] || command_line+=(--model "$model")
command_line+=(--tools "$tools" --disallowed-tools "$deny" --strict-mcp-config --setting-sources ""
  --max-turns "$max_turns" --session-id "$session_id" --output-format json)

if [ "$dry_run" -eq 1 ]; then
  echo "arch-scout-run: dry run, nothing is called"
  echo "cwd $target"
  echo "timeout $timeout_s $claude_bin -p --agent $profile_id --model ${model:-auto} --tools $tools --disallowed-tools $deny --strict-mcp-config --setting-sources '' --max-turns $max_turns --session-id <uuid> --output-format json (--agents <$profile_id from $agent_file>, brief on stdin)"
  echo "token target $token_target, pilot cap $max_runs runs, issue $issue_ref"
  exit 0
fi

if [ ! -x "$claude_bin" ] && ! command -v "$claude_bin" >/dev/null 2>&1; then
  echo "arch-scout-run: no claude binary ($claude_bin)" >&2
  exit 5
fi

# --- the rolling issue: state, then the brief inputs ---------------------------------------
mkdir -p "$state_root"
run_dir=$(mktemp -d "$state_root/run.XXXXXX")
gh issue view "$issue_number" -R "$issue_repo" --json body,comments >"$run_dir/view.json"
runs=0
week_done=0
while read -r key value; do
  case "$key" in
    runs) runs=$value ;;
    week_done) week_done=$value ;;
  esac
done < <(python3 -I "$report" view --view "$run_dir/view.json" --week "$week" \
  --prior-out "$run_dir/prior-findings.md" --issue-out "$run_dir/issue.md")

if [ "$force" -eq 0 ] && [ "$week_done" -eq 1 ]; then
  echo "arch-scout-run: already ran in $week, nothing to do (--force runs again)"
  exit 0
fi
if [ "$force" -eq 0 ] && [ "$runs" -ge "$max_runs" ]; then
  echo "arch-scout-run: pilot complete: $runs of $max_runs runs; disarm with scripts/owner-steps/20.sh disarm, or raise SCOUT_MAX_RUNS to extend"
  exit 0
fi
run_number=$((runs + 1))

printf 'name: %s\npath: %s\n' "$target_name" "$target" >"$run_dir/target-repo.txt"
bash "$root/scripts/render.sh" --brief "$profile_id" --issue-file "$run_dir/issue.md" \
  --input "target_repo=$run_dir/target-repo.txt" --input "prior_findings=$run_dir/prior-findings.md" \
  >"$run_dir/brief.md"

# --- the run, under the hard stops ----------------------------------------------------------
started=$SECONDS
rc=0
(builtin cd "$target" && "${command_line[@]}" <"$run_dir/brief.md" >"$run_dir/result.json" 2>"$run_dir/claude.err") || rc=$?
seconds=$((SECONDS - started))

hint=""
[ "$rc" -ne 124 ] || hint=timeout
transcript=$(find "$HOME/.claude/projects" -maxdepth 2 -name "$session_id.jsonl" -print -quit 2>/dev/null || true)

status=""
exit_code=0
while read -r key value; do
  case "$key" in
    status) status=$value ;;
    exit) exit_code=$value ;;
  esac
done < <(python3 -I "$report" comment --result "$run_dir/result.json" --transcript "$transcript" \
  --hint "$hint" --seconds "$seconds" --max-turns "$max_turns" --timeout "$timeout_s" \
  --token-target "$token_target" --week "$week" --run "$run_number" --when "$when" \
  --target-name "$target_name" --out "$run_dir/comment.md")

cp "$run_dir/comment.md" "$state_root/last-comment.md"
if ! gh issue comment "$issue_number" -R "$issue_repo" --body-file "$run_dir/comment.md" >"$run_dir/posted.txt"; then
  echo "arch-scout-run: could not post the comment on $issue_ref; it is kept in $state_root/last-comment.md" >&2
  exit 4
fi
echo "arch-scout-run: run $run_number ($week) $status in ${seconds}s, posted on $issue_ref"
exit "$exit_code"
