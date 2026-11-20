# Schema

The profile schema: [`profile.schema.json`](profile.schema.json) holds the front matter fields, their enums and the body layout and caps. `bash scripts/check-profiles.sh` enforces it, and `scripts/check.sh` runs that on every check. Fields come from the [owner decisions](https://github.com/deanjstone/agents/issues/1#issuecomment-6868378783) (D3, D7, D8), the [layout proposal](https://github.com/deanjstone/agents/issues/1#issuecomment-6748843600) and the [research findings](https://github.com/deanjstone/agents/issues/5#issuecomment-7047073614).

A field declares; it does not enforce. A `tools` list or a `rank` states what a role may do. Enforcement stays in argus-config's installer and hooks. The one limit the check adds is the rank ceiling: `tools.allow` may not list a tool above the rank's row in [units](../doctrine/units.md#rank-ceiling).

## A profile

One file per profile: `profiles/<id>.md`, YAML front matter, then a prose body. Profile ids read `<rank>-<role>`, such as `specialist-reviewer` or `staff-xo`. The id equals the file name and its prefix equals `rank`, so a rank change is a rename.

Front matter fields. All are required except `skills` and `runtime`:

| Field | Rule |
| ----- | ---- |
| `id` | `<rank>-<role>`, lowercase, digits and hyphens |
| `version` | A quoted dotted number such as `"1.0"`. Rises on any behaviour change, and must rise on an authority change |
| `section` | `S1`, `S2`, `S3`, `S4`, `S6`, `command` or `fire-team`. There is no S5. See [units](../doctrine/units.md) |
| `rank` | `scout`, `specialist`, `lead` or `staff`. Names a permission envelope; see [units](../doctrine/units.md) |
| `mission` | One-sentence standing objective |
| `reports_to` | A profile id, or `owner` |
| `lane` | `read-only` or `write` |
| `model` | Default model tier or id, or `auto` |
| `skills` | Optional. Skills by name only; the skills themselves stay in argus-config |
| `tools` | A mapping with both `allow` and `deny` lists (either may be empty). `allow` is checked against the rank ceiling; `deny` is not |
| `inputs` | What the profile receives, as `snake_case` names. The original issue text always travels verbatim, listed or not |
| `outputs` | What the profile reports; at least one |
| `escalates_to` | Where an owner question goes: a profile id, or `owner` |
| `runtime` | Optional, reserved (D7). Defaults to `claude`, the only value accepted while the fields are Claude-shaped |

A key starting `x-` is an extension: the check allows it and a renderer ignores it. Any other key is an error. Call signs are assigned per spawn (`S2-1`, `S3-4`), not stored in a profile. See [units](../doctrine/units.md).

Front matter is a YAML subset so the check needs no YAML library: `key: value`, `key: [a, b]`, and one nested level (`tools:` with `allow:` and `deny:`) written as flow lists or `- item` lines. A plain value containing `: ` must be quoted.

## Body

Sections in this order, each non-empty, as `## ` headings with nothing before the first:

**Mission · Owns · Boundaries · Procedure · Done means · Report format**

then an optional `## Voice` (at most 3 non-empty lines) and an optional `## Learned` (at most 10 non-empty lines of at most 200 characters; an agent proposes one line, the owner reviews it). The caps live in `x-body` in the schema file.

```markdown
---
id: specialist-reviewer
version: "1.0"
section: S3
rank: specialist
mission: Review one large diff against the issue text and report PASS, ISSUES or BLOCKED.
reports_to: staff-xo
lane: read-only
model: auto
tools:
  allow: [Read, Grep, Glob, Bash]
  deny: [Edit, Write]
inputs: [issue_text, diff]
outputs: [report]
escalates_to: owner
---

## Mission
...
## Report format
Result, evidence, open questions.
```

## Unit files

`units/<unit>.yaml` pairs profiles into fire teams, checked against [`unit.schema.json`](unit.schema.json) by `bash scripts/check-units.sh`. Keys: `unit` (the file name), `version`, and `fire_teams`, a mapping of team name to `builder`, `reviewer`, `trigger` (only `changed-lines`), `threshold` (an integer of at least 1) and `gate` (a non-empty list of the mechanical checks that stay the gate). A key starting `x-` is an extension. Beyond the schema, the check fails when a named profile does not exist, the reviewer is the builder, the reviewer can write or takes no `diff` input, or its report goes to the builder. The rules are in the [README](../README.md#fire-team).

## What the check enforces

`scripts/check-profiles.sh [--root <dir>] [--units <file>] [--base <ref>]` prints `profiles/<file>:<line>: AGPnnn: <message>` and exits 1 on any failure. The codes are listed at the top of [`scripts/check_profiles.py`](../scripts/check_profiles.py).

- Missing, unknown or duplicate front matter keys (`AGP001` to `AGP003`), and values outside their type, enum or pattern, such as an unknown rank (`AGP004`). The rank enum is exactly `scout`, `specialist`, `lead`, `staff`.
- An `id` that is not the file name or whose prefix is not the rank (`AGP005`, `AGP006`).
- A missing or empty required section, or a duplicate, unknown or out-of-order one (`AGP007`, `AGP008`).
- A Voice or Learned section over its cap (`AGP009`, `AGP010`).
- An authority field changed without a higher `version` (`AGP011`). The authority fields are `rank`, `lane`, `tools`, `model` and `runtime`, compared with the base ref with defaults filled in, so writing out `runtime: claude` is not a change. A profile absent from the base is new and needs no bump. A profile renamed to another rank (same role, new prefix) is compared with the profile it replaced. The base is `--base`, then `PROFILE_BASE`, then `origin/main`; CI passes the commit before a push, or the pull request's base branch.
- A `tools.allow` entry above the rank's ceiling (`AGP013`). The ceiling is the `## Rank ceiling` table in [`doctrine/units.md`](../doctrine/units.md#rank-ceiling), read on every run (`--units` names another file): one row per rank (a row is its tools in backticks, or `none` when the rank adds no tool), each rank may list its own row and every row above it, and `*` is every tool. A tool with a pattern such as `Bash(git status:*)` counts as `Bash`. `tools.deny` is not checked. A table that is missing, has no row for a rank, has rows out of order, or names a tool without backticks fails the whole check (`AGP014`), even with no profiles, and no profile is judged against it.
- The owner's approval of an authority change is a review step the check cannot see.

Not checked: that `reports_to` or `escalates_to` name a profile that exists, and that a `scout` is `read-only`. Each needs a decision first; none is enforced yet. The ceiling limits tool names only; it does not read the rank's envelope in prose.

A profile never edits itself. An agent may propose one Learned line only as a change to this repo that the owner reviews.
