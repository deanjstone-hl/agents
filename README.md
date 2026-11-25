# agents
Agent profiles and personas, organised on a military unit structure

The structure is a naming and permission scheme, not a chain of command: owner, an XO (Aquila, the owner's pathway only) with the tick beside it, staff lanes S-1, S-2, S-3, S-4 and S-6, and fire teams. Ranks are permission tiers (scout, specialist, lead, staff) and are our extension, not army doctrine.

## Layout

| Path | Holds |
| ---- | ----- |
| [doctrine/units.md](doctrine/units.md) | Echelons, staff lanes, rank tiers, the rank-to-tools ceiling, call signs and where the analogy breaks |
| [doctrine/culture.md](doctrine/culture.md) | What every profile shares: the three-line voice and the working rules (state not memory, trust the labels, own the outcome, live changes need the owner's yes, notation, the owner-first Resolution, plain commands, `Ready to settle:`) |
| [schema/](schema/README.md) | The profile schema (`profile.schema.json`): fields, enums, body layout and the rules the check enforces |
| [profiles/](#first-profiles) | One `<rank>-<role>.md` per profile, checked against the schema: the first four are listed under [First profiles](#first-profiles), Aquila and the tick under [Aquila and the tick](#aquila-and-the-tick) |
| [templates/brief.md](templates/brief.md) | The brief template `render.sh` fills for each profile |
| `generated/` | Committed output of `render.sh`: `agents/<id>.md` and `briefs/<id>.md` per profile |
| [units/](#fire-team) | `aquila.yaml`: which profiles pair up as a fire team and when the pair reviews, checked against [`schema/unit.schema.json`](schema/unit.schema.json) |
| [docs/](docs/arch-scout-issue.md) | `arch-scout-issue.md`, the body of the Architecture scout's rolling issue; `diagrams/` |
| `scripts/` | The local check, the profile and unit checks, the renderer, the review trigger, the Architecture scout's run script and `owner-steps/` |

The plan and every decision are in [agents/1](https://github.com/deanjstone/agents/issues/1).

## How it reaches a session

`agents` is not a deploy repo. argus-config consumes `generated/` through its own installer, deploy gate and promotion, which stay the only path to live. Nothing here changes a session until argus-config promotes it.

## First profiles

Authored from the charter text inventoried in [agents/6](https://github.com/deanjstone/agents/issues/6). The owner's decisions of 21 Nov 2026 shape the ranks: a scout stays strictly read-only, a specialist may list `Edit` and `Write` ([agents/22](https://github.com/deanjstone/agents/issues/22)).

| Profile | Lane | Rank | Does |
| ------- | ---- | ---- | ---- |
| [`specialist-research-collector`](profiles/specialist-research-collector.md) | S-2 | specialist | Reads primary sources for one question and reports cited findings. Needs `WebFetch` and `Bash`, so it is not a scout |
| [`scout-research-analyst`](profiles/scout-research-analyst.md) | S-2 | scout | Weighs the collector's findings and reports what they support. `Read`, `Grep`, `Glob` only |
| [`specialist-hygiene`](profiles/specialist-hygiene.md) | S-1 | specialist | Sweeps the backlog twice a week and posts one batch of proposals. Read-only on code; needs `Bash` for `gh`. Model `sonnet` |
| [`specialist-slot-worker`](profiles/specialist-slot-worker.md) | S-3 | specialist | Takes one issue end to end and lands it. The only one of the four that writes |

Each carries Mission, Owns, Boundaries, Procedure, Done means and Report format, and renders to `generated/agents/<id>.md` and `generated/briefs/<id>.md`. The hygiene profile had no Done means in the charter; its own is new text. The slot worker's trunk and PR flows are two steps of one Procedure, chosen by the `repo_flow` input. The charter's repo-engineering rules (release pattern, capture-file names) are not worker text and stay in argus-config.

## Fire team

[`units/aquila.yaml`](units/aquila.yaml) pairs the [slot worker](profiles/specialist-slot-worker.md) (builder) with the new [`specialist-reviewer`](profiles/specialist-reviewer.md) as team `slot`. The pair is a buddy-check analogy, not the doctrinal four-member fire team ([where the analogy breaks](doctrine/units.md#where-the-analogy-breaks)).

The reviewer ([agents/11](https://github.com/deanjstone/agents/issues/11), owner decision D6) is a specialist with a read-only lane (`Read`, `Grep`, `Glob`, `Bash`; no `Edit` or `Write`). Its brief carries the issue text verbatim, the diff and the path of a checkout of the change, and nothing from the author's narrative. It must run the checks, and reports `PASS`, `ISSUES` or `BLOCKED` with the evidence for it.

- **Size-triggered.** It runs only above `threshold` changed lines, 300 to start ([argus-config/824](https://github.com/deanjstone/argus-config/issues/824): single-pass review tied the fan-out on changes of 300 lines or fewer and lost on all three of 585 lines or more, from 10 changes). The count is the added plus deleted lines of `git diff --numstat <base> <head>`, binary files as none. `bash scripts/review-needed.sh --base <ref> --head <ref> [--team slot]` prints `required (N changed lines, threshold T, team slot): launch <reviewer>` or `skip (...)`, and exits 2 when it cannot decide.
- **Never the sole gate.** CI and `verify-claim.sh` stay the gate. Every team lists its `gate` in the unit file, never empty, and a `PASS` approves no merge.
- **Independent.** `bash scripts/check-units.sh` fails when the reviewer is the builder, can write (a write lane, or `Edit` or `Write` in `tools.allow`), takes no `diff` input, or reports to the builder, and when either profile does not exist. Codes `AGU001` to `AGU011` are listed at the top of [`scripts/check_units.py`](scripts/check_units.py).

Render a reviewer brief the way `## Inputs` says: `bash scripts/render.sh --brief specialist-reviewer --issue-file issue.txt --input diff=changes.diff --input checkout=checkout-path.txt`. The tests are `scripts/test-fire-team.sh`, run by `check.sh`. Nothing launches the reviewer yet: wiring it into the orchestrator's briefs is [agents/13](https://github.com/deanjstone/agents/issues/13).

## Aquila and the tick

The orchestrator is two profiles of rank `staff`, both section `command`, lane `write`, every tool and model `sonnet` ([agents/26](https://github.com/deanjstone-hl/agents/issues/26); the owner's decisions 13 and 14 on [argus-config/1622](https://github.com/deanjstone-hl/argus-config/issues/1622): "Tick stays nested" and "argus-config now, agents later"). The earlier single profile was the tick under Aquila's name ([agents/15](https://github.com/deanjstone/agents/issues/15)).

- [`staff-xo`](profiles/staff-xo.md) is **Aquila**, the owner's pathway: the threads in the Aquila project (`~/aquila`). It shows the status card, presents the decision queue, relays the owner's answers and runs the owner-approved live steps, and it is the only session called Aquila. It reads loop-state and writes only `owner_turn`, closes no slot issue and starts no worker or child. It reports to the owner.
- [`staff-tick`](profiles/staff-tick.md) is the **tick**, the `Aquila Tick` project nested at `~/aquila/tick`. It holds both loop-state leases, fills and verifies the worker slots and the closes, keeps the decision queue and loop status current, and reports to Aquila. It is not Aquila.

Each Procedure ends on a pointer to its **runbook**, the operating mechanics that stay in argus-config because they would tie this repo to loop-state internals: for the tick, the sections of [`orchestrator.md`](https://github.com/deanjstone/argus-config/blob/main/envs/wsl2/charters/orchestrator.md) after the role text (the tick checklist, filling a slot and its gates, homelab standby, handover, cross-env control, notifications, budget, degradation and rotation); for Aquila, the sections of [`aquila.md`](https://github.com/deanjstone/argus-config/blob/main/envs/wsl2/charters/aquila.md) after the role text (the status card, the webhook helper, the self-handover, leaving and the compaction snapshot). argus-config sources `~/aquila/tick/CLAUDE.md` from `generated/agents/staff-tick.md` plus the tick runbook, and `~/aquila/CLAUDE.md` from `generated/agents/staff-xo.md` plus Aquila's runbook. That wiring is an argus-config follow-up, and nothing live changes until argus-config consumes `generated/` and promotes it.

The ranks allow more than one `staff` profile because both need loop-state tools ([doctrine/units.md](doctrine/units.md#ranks-our-extension-not-doctrine)); the profile, not the rank, says what each may call. The workers and children still name `staff-xo` in `reports_to` and `escalates_to`; pointing them at `staff-tick` is a separate step.

The shared rules the charter repeated in more than one place moved into [`doctrine/culture.md`](doctrine/culture.md), one copy each, and so reach every generated charter and brief. The inventory behind the split is in [agents/6](https://github.com/deanjstone/agents/issues/6#issuecomment-7037964961). The existing profiles may still repeat a rule in their own words. `scripts/test-staff-xo.sh` pins both profiles' envelopes and the rules each must carry, and the rules the culture must hold.

## Architecture scout

The pilot of one standing role ([agents/20](https://github.com/deanjstone/agents/issues/20)), run on the owner's decisions of 17 Nov 2026 ([agents/19](https://github.com/deanjstone/agents/issues/19#issuecomment-6926939164)). [`scout-architecture`](profiles/scout-architecture.md) is a scout (`Read`, `Grep`, `Glob` only, model `sonnet`, reports to the owner). Once a week it reads one repo and reports at most five architecture findings, each citing `path:line` and ending on a `Yes or no:` question, or the single line `No findings this week.` It posts nothing itself.

| Piece | What it does |
| ----- | ------------ |
| [`scripts/arch-scout-run.sh`](scripts/arch-scout-run.sh) | One run: `--issue <owner/repo#N> --target <dir> [--dry-run] [--force]`. Reads the rolling issue (its body is the brief's issue text, its comments are `prior_findings`), renders the brief, runs `claude -p` in the target as the profile's own agent file with `--tools` and `--disallowed-tools` from the profile, `--strict-mcp-config` and no setting sources, then posts the reply as one comment |
| [`scripts/scout_report.py`](scripts/scout_report.py) | The parsing: the agent file to `--agents` JSON, the run markers and prior comments of the issue, the transcript read-back, and the comment itself |
| [`scripts/owner-steps/20.sh`](scripts/owner-steps/20.sh) | The one command that arms the schedule (below). A live step: the owner runs it, no agent does |
| [`docs/arch-scout-issue.md`](docs/arch-scout-issue.md) | The body of the rolling issue: mission, how to answer, the caps, the pilot |

**Caps.** `--max-turns 60` and a 30 minute `timeout` are hard stops. The 60k output-token figure is a target, not a stop: `claude -p` has no output-token flag, so the script reads the tokens back from the session transcript (it passes `--session-id`, so the file is known) after each run. A request is one assistant message id, counted once at its largest count, since the transcript writes it once per content block. A run over 60k is posted and flagged `OVER the token target`, and the owner tightens `SCOUT_MAX_TURNS`. There is no dollar cap. A run that hits a hard stop, comes back with no valid findings or leaves no transcript still posts a stats comment and exits 3, so the pilot's success test sees it.

**The comment.** `## Architecture scout, run <n> (week <ISO week>, <AEDT time>)`, the findings renumbered `F1` to `F5`, a `Run stats:` line (turns, time and output tokens against their caps, then `within caps` or the reason it is not), the line asking for `F1 yes` or `F1 no` replies, and a hidden `<!-- arch-scout-run: {...} -->` marker with the week, run number, status, turns, tokens, seconds and finding count. More than five findings keep the first five and the comment says how many were dropped; a finding with no yes-or-no question is dropped the same way. The markers are how the script knows a week already ran (it stops unless `--force`) and how many runs the pilot has had (`SCOUT_MAX_RUNS`, 2).

**Arming it.** Nothing here is armed. The owner runs one command, after `git -C /home/deanj/repos/agents pull --ff-only`:

```bash
bash /home/deanj/repos/agents/scripts/owner-steps/20.sh
```

It creates the rolling issue ("Architecture scout: weekly findings (pilot)", labels `mode:hitl`, `wave:later`, `type:chore`) if no open one has that title, writes the user unit `arch-scout.service` and `arch-scout.timer` (Mondays 07:00 Sydney time, `Persistent=true`, `Nice=10`, `MemoryMax=2G`), and enables the timer. `SCOUT_TARGET` names the repo to read (default `~/repos/argus`). `print` shows what it would write; `disarm` disables the timer and removes both units. Tighten or extend the pilot by editing the `Environment=` lines of the unit (`SCOUT_MAX_TURNS`, `SCOUT_TIMEOUT`, `SCOUT_MAX_RUNS`) and running `systemctl --user daemon-reload`. The units are written as plain files for the pilot; keeping the role means moving them into argus-config's installer.

## Local check

Run the check before every push; CI runs the same command on every PR and every push to `main`:

```bash
bash scripts/check.sh
```

`scripts/check.sh` needs only bash, git and python3. It runs thirteen steps: the shell and Python scripts parse; every tracked `.md` file is linted (non-empty, no trailing whitespace, newline at end of file, well-formed frontmatter with a closing `---` and `key: value` lines, every relative link resolving to a tracked file); every `profiles/*.md` is checked against the profile schema (below); the tests of that profile check run; the tests of the renderer run; `scripts/render.sh --check` fails if the committed `generated/` is not what the sources render to; `scripts/check-heavy-lock.sh` checks the lock wiring below; `scripts/test-first-profiles.sh` pins what the four first profiles say (rank, lane, tools, and the rules each must carry); `scripts/check-units.sh` checks the unit files; `scripts/test-fire-team.sh` runs the tests of the unit check, the size trigger and the reviewer profile; `scripts/test-staff-xo.sh` pins the `staff-xo` and `staff-tick` profiles and the culture's working rules; `scripts/test-learned.sh` runs the tests of the Learned-line flow, then `scripts/check-learned.sh` checks a proposal branch (below); and `scripts/test-arch-scout.sh` runs the tests of the [Architecture scout](#architecture-scout) against fake `claude`, `gh` and `systemctl`. It prints `check: pass <short sha>` on success and exits non-zero on any failure. The gate takes the host-wide heavy lock ([argus-config/1506](https://github.com/deanjstone/argus-config/issues/1506)): `scripts/check.sh` re-runs itself through `scripts/heavy-lock.sh`, so only one full check runs at a time on a host, whichever thread or CI job starts it, and it also waits while memory `some avg60` is 10 or more. A queued run prints `waiting for the host lock` and starts when the holder ends; it exits 75 without running once `HEAVY_LOCK_TIMEOUT` (3600 s) passes. `scripts/heavy-lock.sh` and `scripts/heavy-lock.lock` are vendored byte-for-byte from argus-config (its `scripts/sync-heavy-lock.sh` rewrites both; never edit them here), and `scripts/check-heavy-lock.sh` fails on a copy that no longer matches its lock.

### Profile check

`bash scripts/check-profiles.sh [--root <dir>] [--units <file>] [--base <ref>]` checks `profiles/*.md` against [`schema/profile.schema.json`](schema/profile.schema.json) and prints `profiles/<file>:<line>: AGPnnn: <message>` for each failure. It fails on missing, unknown or duplicate fields, an unknown rank (the ranks are `scout`, `specialist`, `lead`, `staff`), an id that is not the file name or rank, a `tools.allow` entry above the rank's ceiling (the table in [doctrine/units.md](doctrine/units.md#rank-ceiling), `--units` names another file), a wrong section layout, a Voice over 3 lines, a Learned section over 10 lines of 200 characters, and an authority field (`rank`, `lane`, `tools`, `model`, `runtime`) changed without a higher `version` than the base. `runtime` is optional and defaults to `claude`. The base is `--base`, then `PROFILE_BASE`, then `origin/main`; a missing `origin/main` skips the version rule with a note, and CI passes the commit before the push (or the pull request's base branch). `scripts/test-check-profiles.sh` holds the tests, run by `check.sh`; each case builds a throwaway fixture repo, so no broken profile is tracked. Fields, rules and the diagnostic codes are in [schema/](schema/README.md).

### Learned lines

A profile never edits itself. An agent that learns something its own profile should say proposes one line, and the owner reviews it ([agents/1](https://github.com/deanjstone/agents/issues/1) D8; cross-cutting feedback still goes to the memory system).

```bash
bash scripts/propose-learned.sh --profile specialist-slot-worker \
  --line "Read the issue comments before the body" \
  --source https://github.com/deanjstone/agents/issues/16#issuecomment-1
```

Run it from a clean checkout of this repo. `scripts/propose-learned.sh` adds `- <date>: <lesson> ([source](https://<url>))` to the profile's `## Learned` section on a new `learned/<profile>-<slug>` branch, renders `generated/`, runs the profile check and commits `docs: propose a Learned line for <profile>`. Without `--no-pr` it then fetches `origin/main`, branches from it, pushes the branch and opens the PR: merging accepts the line and closing it declines it. It refuses, before a branch exists, an unknown profile, a line that is empty, has a newline or runs past 200 characters, a source that is not an https URL, a bad date, a line already in Learned, a dirty tree and a Learned section already at its cap, which the owner prunes first.

Two checks hold it in place. The cap, 10 lines of at most 200 characters, is `scripts/check-profiles.sh` (`AGP010`) in `check.sh`, so no change can lift a profile over it. `bash scripts/check-learned.sh [--root <dir>] [--base <ref>] [--proposal]` checks the shape of a proposal: the change from the merge base holds one profile and its two `generated/` files (`LRN001`, `LRN002`), changes nothing in the profile outside Learned (`LRN003`), adds exactly one line at the end and leaves the others as they are (`LRN004`), and that line has the date, text and source link (`LRN005`, `LRN006`). It checks a proposal only: with `--proposal`, with `LEARNED_PROPOSAL=1` (CI sets it for a pull request whose head branch starts with `learned/`) or on a local `learned/*` branch; anywhere else it passes with a note, so the owner can still prune or reword lines on trunk. `scripts/test-learned.sh` holds the tests.

### Render

`bash scripts/render.sh` turns each profile into two committed files under `generated/`, joined with [`doctrine/culture.md`](doctrine/culture.md) and [`templates/brief.md`](templates/brief.md). Run it after any change to a profile, the culture or the template, and commit `generated/` in the same landing; `check.sh` fails on a stale, missing or orphaned file (`bash scripts/render.sh --check` names it). A profile that fails the profile check, the rank ceiling included, is never rendered, and nothing is written unless every profile renders.

| Output | What it is |
| ------ | ---------- |
| `generated/agents/<id>.md` | A [Claude subagent file](https://code.claude.com/docs/en/sub-agents#frontmatter-reference): `name` is the id, `description` the mission, `tools` is `tools.allow`, `disallowedTools` is `tools.deny`, `model` passes through (`auto` leaves it out so Claude Code picks), `skills` passes through. The body is the identity line, then the culture, then the profile's sections. The other fields stay in the profile; Claude Code ignores unknown fields, so none is emitted |
| `generated/briefs/<id>.md` | The brief for a spawned worker: the template with the identity line, culture, charter and an `## Inputs` section filled in |

Why subagent files and not skill files: a subagent's `tools` is an allowlist and its body is its system prompt, so the profile's `tools` keeps its meaning. A skill's `allowed-tools` only pre-approves tools for a turn and [does not restrict which are available](https://code.claude.com/docs/en/skills#pre-approve-tools-for-a-skill). An empty `tools.allow` is refused, because a subagent file that names no tools inherits every tool.

The culture joined is the part of `doctrine/culture.md` from its first `## ` section to the `<!-- render:end -->` line, one heading level down under `## Culture`. The brief template may use `{{id}}`, `{{mission}}`, `{{identity}}`, `{{culture}}`, `{{charter}}` and `{{inputs}}`, and must use `{{inputs}}`. Culture and profiles may not contain `{{`, nor a relative link (the output sits in a different directory).

**The original issue text is a mandatory brief input.** `## Inputs` always opens with an `issue_text` slot, whether the profile lists it or not; the other inputs a profile lists follow. A template without `{{inputs}}` is refused. To get a finished brief, fill the slots; the issue text goes in byte for byte:

```bash
bash scripts/render.sh --brief specialist-reviewer --issue-file issue.txt --input diff=changes.diff
```

That prints the brief to stdout and writes nothing. It fails if `--issue-file` is missing, empty or blank, if a declared input is not supplied, or if an undeclared one is. `scripts/test-render.sh` holds the tests, run by `check.sh`; each case builds a throwaway fixture root. Diagnostic codes (`AGR001` and up) are listed at the top of [`scripts/render.py`](scripts/render.py).

The repo follows the trunk-readiness gate (`scripts/trunk-readiness.sh` in argus-config): a committed check, CI on push to `main` that runs it, and a green `main`.

The README guard ([`readme-guard.yml`](.github/workflows/readme-guard.yml), logic in
[`.github/scripts/readme-guard.sh`](.github/scripts/readme-guard.sh), vendored from
[argus-config/1147](https://github.com/deanjstone/argus-config/issues/1147)) runs on every push to `main`, always on `ubuntu-latest`. It
fails a push that changes `package.json` scripts or `bin`, a workflow, a deploy or install script, an env template or
a CLI entry point without touching a README, unless a commit message carries `README: not needed because <reason>`.
Change the script in argus-config and re-copy it; do not edit it here.

## License

Licensed under the [Apache License, Version 2.0](LICENSE). See [NOTICE](NOTICE) for attribution.
