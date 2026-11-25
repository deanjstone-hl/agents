#!/usr/bin/env bash
# The local check: what CI runs on every push to main, run before a push
# (trunk-based development, argus-config#1312). The repo holds Markdown profiles and
# personas, so the check lints them: every tracked .md file must be non-empty, valid
# UTF-8, free of tabs-for-indent and trailing whitespace, with well-formed frontmatter
# (when it starts with `---`, a closing `---` and `key: value` lines), and every
# relative link must resolve to a tracked file. It then checks profiles/*.md against
# schema/profile.schema.json (scripts/check-profiles.sh) and runs that checker's tests, then
# runs the renderer's tests and checks that the committed generated/ output is what
# scripts/render.sh renders from the sources. Last, it runs the tests that pin the first four
# profiles (scripts/test-first-profiles.sh), checks units/*.yaml against schema/unit.schema.json
# and the profiles they name (scripts/check-units.sh), and runs the tests of the fire team: that
# check, the size trigger and the reviewer profile (scripts/test-fire-team.sh), and the tests that
# pin the staff-xo and staff-tick profiles and the shared working rules of doctrine/culture.md (scripts/test-staff-xo.sh).
# Last, it runs the tests of the Learned-line proposal flow (scripts/test-learned.sh) and checks the shape of a
# proposal branch (scripts/check-learned.sh: one line, one profile, nothing else; a no-op outside learned/*).
# Last of all, it runs the tests of the weekly Architecture scout (scripts/test-arch-scout.sh): its profile, the run
# script's hard stops and token read-back, and the owner step that arms the timer, all against fake claude, gh and systemctl.
# Needs only bash, git and python3.
# Prints `check: pass <short sha>` on success; any failure exits non-zero.
set -euo pipefail

builtin cd "$(dirname "${BASH_SOURCE[0]}")/.."

# One full check at a time per host (argus-config#1506): two overlapping gates made
# systemd-oomd kill agent scopes. The re-exec waits for the host lock (HEAVY_LOCK_TIMEOUT,
# default 3600 s, then exit 75) and runs this script with HEAVY_LOCK_HELD=1 so it does not
# wait again. scripts/heavy-lock.sh is vendored from argus-config.
if [ "${HEAVY_LOCK_HELD:-}" != 1 ]; then
  exec bash "$PWD/scripts/heavy-lock.sh" bash "$PWD/scripts/check.sh" "$@"
fi

echo "check: step 1/13 script syntax" >&2
for script in scripts/*.sh scripts/owner-steps/*.sh; do
  bash -n "$script" || {
    echo "check: FAIL at step 1/13 (bash -n $script)" >&2
    exit 1
  }
done
for script in scripts/*.py; do
  python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1])' "$script" || {
    echo "check: FAIL at step 1/13 (python syntax $script)" >&2
    exit 1
  }
done

echo "check: step 2/13 markdown" >&2
git ls-files -z -- '*.md' | python3 -I -c '
import os
import re
import subprocess
import sys

files = [f for f in sys.stdin.buffer.read().decode().split("\0") if f]
tracked = set(
    os.path.normpath(f)
    for f in subprocess.run(
        ["git", "ls-files", "-z"], capture_output=True, check=True
    ).stdout.decode().split("\0")
    if f
)
errors = []
FRONT_LINE = re.compile(r"^(?:[A-Za-z0-9_-]+:(?:\s.*)?|\s+.*|-\s.*|#.*|)$")
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")

for path in files:
    try:
        text = open(path, encoding="utf-8").read()
    except (UnicodeDecodeError, OSError) as exc:
        errors.append(f"{path}: unreadable ({exc})")
        continue
    if not text.strip():
        errors.append(f"{path}: empty")
        continue
    lines = text.split("\n")
    for number, line in enumerate(lines, 1):
        if line != line.rstrip():
            errors.append(f"{path}:{number}: trailing whitespace")
    if not text.endswith("\n"):
        errors.append(f"{path}: no newline at end of file")
    if lines[0] == "---":
        closing = next((i for i, l in enumerate(lines[1:], 1) if l == "---"), None)
        if closing is None:
            errors.append(f"{path}: frontmatter is not closed with ---")
        else:
            for number, line in enumerate(lines[1:closing], 2):
                if not FRONT_LINE.match(line):
                    errors.append(f"{path}:{number}: malformed frontmatter line")
    in_fence = False
    for number, line in enumerate(lines, 1):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for target in LINK.findall(line):
            if re.match(r"^(?:[a-z][a-z0-9+.-]*:|#|/)", target):
                continue
            target_path = target.split("#", 1)[0]
            if not target_path:
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), target_path))
            is_dir = any(t.startswith(resolved + "/") for t in tracked)
            if resolved not in tracked and not is_dir:
                errors.append(f"{path}:{number}: broken relative link {target}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"markdown: {len(files)} file(s) ok", file=sys.stderr)
' || {
  echo "check: FAIL at step 2/13 (markdown)" >&2
  exit 1
}

echo "check: step 3/13 profiles against the schema" >&2
bash scripts/check-profiles.sh || {
  echo "check: FAIL at step 3/13 (profiles)" >&2
  exit 1
}

echo "check: step 4/13 profile check tests" >&2
bash scripts/test-check-profiles.sh || {
  echo "check: FAIL at step 4/13 (profile check tests)" >&2
  exit 1
}

echo "check: step 5/13 render tests" >&2
bash scripts/test-render.sh || {
  echo "check: FAIL at step 5/13 (render tests)" >&2
  exit 1
}

echo "check: step 6/13 generated output is current" >&2
bash scripts/render.sh --check || {
  echo "check: FAIL at step 6/13 (generated output; run bash scripts/render.sh and commit generated/)" >&2
  exit 1
}

echo "check: step 7/13 heavy lock wiring" >&2
bash scripts/check-heavy-lock.sh || {
  echo "check: FAIL at step 7/13 (heavy lock wiring)" >&2
  exit 1
}

echo "check: step 8/13 first profiles" >&2
bash scripts/test-first-profiles.sh || {
  echo "check: FAIL at step 8/13 (first profiles)" >&2
  exit 1
}

echo "check: step 9/13 unit files" >&2
bash scripts/check-units.sh || {
  echo "check: FAIL at step 9/13 (unit files)" >&2
  exit 1
}

echo "check: step 10/13 fire team tests" >&2
bash scripts/test-fire-team.sh || {
  echo "check: FAIL at step 10/13 (fire team tests)" >&2
  exit 1
}

echo "check: step 11/13 staff-xo and the shared working rules" >&2
bash scripts/test-staff-xo.sh || {
  echo "check: FAIL at step 11/13 (staff-xo)" >&2
  exit 1
}

echo "check: step 12/13 Learned-line proposals" >&2
bash scripts/test-learned.sh || {
  echo "check: FAIL at step 12/13 (Learned-line proposal tests)" >&2
  exit 1
}
bash scripts/check-learned.sh || {
  echo "check: FAIL at step 12/13 (Learned-line proposal check)" >&2
  exit 1
}

echo "check: step 13/13 Architecture scout" >&2
bash scripts/test-arch-scout.sh || {
  echo "check: FAIL at step 13/13 (Architecture scout tests)" >&2
  exit 1
}

echo "check: pass $(git rev-parse --short HEAD)"
