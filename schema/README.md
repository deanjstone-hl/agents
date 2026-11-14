# Schema

The home of the profile schema. `profile.schema.json` and its checks are not here yet: they are the next build step, written tests first. This page records what that schema is to hold, from the [owner decisions](https://github.com/deanjstone/agents/issues/1#issuecomment-6868378783) and the [layout proposal](https://github.com/deanjstone/agents/issues/1#issuecomment-6748843600), so the step starts from settled fields.

## A profile

One file per profile: YAML front matter, then a prose body. Profile ids read `<rank>-<role>`, such as `specialist-reviewer` or `staff-xo`.

Front matter fields:

| Field | Meaning |
| ----- | ------- |
| `id` | The profile id |
| `section` | `S1` to `S6`, `command` or `fire-team`. See [units](../doctrine/units.md) |
| `rank` | `scout`, `specialist`, `lead` or `staff`. Names a permission envelope; see [units](../doctrine/units.md) |
| `mission` | One-sentence standing objective |
| `reports_to` | A profile id, or `owner` |
| `lane` | `read-only` or `write` |
| `model` | Default model tier |
| `skills` | Skills by name only; the skills themselves stay in argus-config |
| `tools` | Allowed and denied tools |
| `inputs` | What the profile receives. The original issue text always travels verbatim |
| `outputs` | What the profile reports |
| `escalates_to` | Where an owner question goes |
| `runtime` | Reserved key, default `claude`. Claude-shaped fields only for now |
| `version` | Bumps on any behaviour change |

Call signs are assigned per spawn (`S2-1`, `S3-4`), not stored in a profile. See [units](../doctrine/units.md).

Body sections, in order: **Mission · Owns · Boundaries · Procedure · Done means · Report format**, then a capped **Learned** section.

## Rules the check will enforce

- The rank enum is exactly `scout`, `specialist`, `lead`, `staff`.
- A voice is at most three lines.
- A change to `rank`, `lane`, `tools` or `model` is an authority change: it needs a `version` bump and the owner's approval.
- The **Learned** section is capped. The cap value is set when the schema is written.
- A profile never edits itself. An agent may propose one Learned line only as a pull request to this repo that the owner reviews.
