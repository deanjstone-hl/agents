# agents
Agent profiles and personas, organised on a military unit structure

The structure is a naming and permission scheme, not a chain of command: owner, an XO (Aquila, the orchestrator only), staff lanes S-1, S-2, S-3, S-4 and S-6, and fire teams. Ranks are permission tiers (scout, specialist, lead, staff) and are our extension, not army doctrine.

## Layout

| Path | Holds |
| ---- | ----- |
| [doctrine/units.md](doctrine/units.md) | Echelons, staff lanes, rank tiers, call signs and where the analogy breaks |
| [doctrine/culture.md](doctrine/culture.md) | What every profile shares, starting with the three-line voice |
| [schema/](schema/README.md) | The profile schema: fields, enums and the rules the check will enforce |
| `scripts/` | The local check |

Profiles, briefs, `units/` and `generated/` are added by later steps. The plan and every decision are in [agents/1](https://github.com/deanjstone/agents/issues/1).

## How it reaches a session

`agents` is not a deploy repo. argus-config consumes `generated/` through its own installer, deploy gate and promotion, which stay the only path to live. Nothing here changes a session until argus-config promotes it.

## Local check

Run the check before every push; CI runs the same command on every PR and every push to `main`:

```bash
bash scripts/check.sh
```

`scripts/check.sh` needs only bash, git and python3. It checks the shell scripts parse (`bash -n`) and lints every tracked `.md` file: non-empty, no trailing whitespace, newline at end of file, well-formed frontmatter (a closing `---`, `key: value` lines) and every relative link resolving to a tracked file. It prints `check: pass <short sha>` on success and exits non-zero on any failure.

The repo follows the trunk-readiness gate (`scripts/trunk-readiness.sh` in argus-config): a committed check, CI on push to `main` that runs it, and a green `main`.

## License

Licensed under the [Apache License, Version 2.0](LICENSE). See [NOTICE](NOTICE) for attribution.
