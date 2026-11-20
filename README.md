# agents
Agent profiles and personas, organised on a military unit structure

The structure is a naming and permission scheme, not a chain of command: owner, an XO (Aquila, the orchestrator only), staff lanes S-1, S-2, S-3, S-4 and S-6, and fire teams. Ranks are permission tiers (scout, specialist, lead, staff) and are our extension, not army doctrine.

## Layout

| Path | Holds |
| ---- | ----- |
| [doctrine/units.md](doctrine/units.md) | Echelons, staff lanes, rank tiers, the rank-to-tools ceiling, call signs and where the analogy breaks |
| [doctrine/culture.md](doctrine/culture.md) | What every profile shares, starting with the three-line voice |
| [schema/](schema/README.md) | The profile schema (`profile.schema.json`): fields, enums, body layout and the rules the check enforces |
| `profiles/` | One `<rank>-<role>.md` per profile, checked against the schema (none yet) |
| [templates/brief.md](templates/brief.md) | The brief template `render.sh` fills for each profile |
| `generated/` | Committed output of `render.sh`: `agents/<id>.md` and `briefs/<id>.md` per profile (none yet, as there are no profiles) |
| `scripts/` | The local check, the profile check and the renderer |

The first profiles and `units/` are added by later steps. The plan and every decision are in [agents/1](https://github.com/deanjstone/agents/issues/1).

## How it reaches a session

`agents` is not a deploy repo. argus-config consumes `generated/` through its own installer, deploy gate and promotion, which stay the only path to live. Nothing here changes a session until argus-config promotes it.

## Local check

Run the check before every push; CI runs the same command on every PR and every push to `main`:

```bash
bash scripts/check.sh
```

`scripts/check.sh` needs only bash, git and python3. It runs seven steps: the shell and Python scripts parse; every tracked `.md` file is linted (non-empty, no trailing whitespace, newline at end of file, well-formed frontmatter with a closing `---` and `key: value` lines, every relative link resolving to a tracked file); every `profiles/*.md` is checked against the profile schema (below); the tests of that profile check run; the tests of the renderer run; `scripts/render.sh --check` fails if the committed `generated/` is not what the sources render to; and `scripts/check-heavy-lock.sh` checks the lock wiring below. It prints `check: pass <short sha>` on success and exits non-zero on any failure. The gate takes the host-wide heavy lock ([argus-config/1506](https://github.com/deanjstone/argus-config/issues/1506)): `scripts/check.sh` re-runs itself through `scripts/heavy-lock.sh`, so only one full check runs at a time on a host, whichever thread or CI job starts it, and it also waits while memory `some avg60` is 10 or more. A queued run prints `waiting for the host lock` and starts when the holder ends; it exits 75 without running once `HEAVY_LOCK_TIMEOUT` (3600 s) passes. `scripts/heavy-lock.sh` and `scripts/heavy-lock.lock` are vendored byte-for-byte from argus-config (its `scripts/sync-heavy-lock.sh` rewrites both; never edit them here), and `scripts/check-heavy-lock.sh` fails on a copy that no longer matches its lock.

### Profile check

`bash scripts/check-profiles.sh [--root <dir>] [--units <file>] [--base <ref>]` checks `profiles/*.md` against [`schema/profile.schema.json`](schema/profile.schema.json) and prints `profiles/<file>:<line>: AGPnnn: <message>` for each failure. It fails on missing, unknown or duplicate fields, an unknown rank (the ranks are `scout`, `specialist`, `lead`, `staff`), an id that is not the file name or rank, a `tools.allow` entry above the rank's ceiling (the table in [doctrine/units.md](doctrine/units.md#rank-ceiling), `--units` names another file), a wrong section layout, a Voice over 3 lines, a Learned section over 10 lines of 200 characters, and an authority field (`rank`, `lane`, `tools`, `model`, `runtime`) changed without a higher `version` than the base. `runtime` is optional and defaults to `claude`. The base is `--base`, then `PROFILE_BASE`, then `origin/main`; a missing `origin/main` skips the version rule with a note, and CI passes the commit before the push (or the pull request's base branch). `scripts/test-check-profiles.sh` holds the tests, run by `check.sh`; each case builds a throwaway fixture repo, so no broken profile is tracked. Fields, rules and the diagnostic codes are in [schema/](schema/README.md).

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
