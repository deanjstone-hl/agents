Standing issue for the Architecture scout pilot ([agents/20](https://github.com/deanjstone/agents/issues/20)). The scout posts one comment here each week and changes nothing. Nobody closes this issue until the pilot is settled.

## What the scout does

Once a week a read-only agent (`scout-architecture`: `Read`, `Grep` and `Glob` only) reads one repo and looks for structural problems: a leaking boundary, a module with two jobs, a dependency pointing the wrong way, a duplicated mechanism, a doc that no longer matches the code. It posts at most five findings. Each cites code by `path:line` and ends on a question you can answer yes or no. Defects, style, performance and test gaps are out of scope.

## How to answer

Reply with one line per finding: `F1 yes`, `F2 no`. A `no` settles that finding and the scout does not raise it again. A `yes` is yours to schedule: the scout files nothing.

## The caps

| Cap | Value | Kind |
| --- | ----- | ---- |
| Turns | 60 | hard stop |
| Wall clock | 30 minutes | hard stop |
| Output tokens | about 60,000 | target, read back from the transcript after each run |

Every comment ends with a stats line: turns, time and output tokens against these caps. A run over the token target is flagged, and the cap is tightened before the next run.

## The pilot

Two weekly runs. Keep the role if you accept at least half of all findings and every run stayed within 60 turns, 30 minutes and about 60,000 output tokens. Otherwise stop or retune. Two runs give at most ten findings, so the accept rate is a thin sample; extend the pilot if it is inconclusive.

Mode: hitl
