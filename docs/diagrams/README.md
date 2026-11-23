# Diagrams

Three self-contained HTML/SVG diagrams for `agents`: its architecture, its main flow, and its build and deploy path. Drawn in the house style of [argus-config/docs/diagrams](https://github.com/deanjstone/argus-config/tree/main/docs/diagrams) with the [diagram-design](https://github.com/cathrynlavery/diagram-design) Claude Code plugin checks (map [argus-config#1433](https://github.com/deanjstone/argus-config/issues/1433), task [context#453](https://github.com/deanjstone/context/issues/453)). Open the `.html` file in a browser.

Each step node is a `<g id="step-<flow>-<step>">`, the deep-link contract of [ops-hub#13](https://github.com/deanjstone-hl/ops-hub/issues/13): the hub links `#/diagrams/<repo>/<path>#<step-id>`, and the page highlights the targeted step (`:target`). Anything inferred is marked `[speculation]` in the diagram or its source line.

| Diagram | Type | Flow | Step ids | Sources |
|---|---|---|---|---|
| `architecture.html` | Architecture | `agents` | `readme` `units` `culture` `schema` `profiles` `generated` `check` `ci` `consumer` | README.md, doctrine/units.md, doctrine/culture.md, schema/README.md, scripts/check.sh, .github/workflows/check.yml |
| `profile-flow.html` | Flow | `profile` | `doctrine` `profile` `check` `push` `render` `generated` `install` `session` | README.md (How it reaches a session, Local check), doctrine/culture.md, schema/README.md, scripts/check.sh. |
| `build-deploy.html` | Pipeline | `agentsci` | `push` `ci` `main` `release` `promote` | .github/workflows/check.yml, scripts/check.sh, README.md (How it reaches a session) |

## Not drawn

Profiles, briefs and generated output: none exist yet, so they are drawn as planned and the render step is marked `[speculation]`. The doctrine text itself is not redrawn.

## Network

The diagrams use the system font stack and make no network request. They name services and roles, never addresses or ids.

## Redrawing

The diagrams are hand-checked against their sources, not generated from them. After the sources change, redraw and rerun the plugin's checks: `self_check.py` in the skill directory and `verify-geometry.py` in the plugin's `scripts/`.
