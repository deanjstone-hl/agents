#!/usr/bin/env bash
# The local check: what CI runs on every push to main, run before a push
# (trunk-based development, argus-config#1312). The repo holds Markdown profiles and
# personas, so the check lints them: every tracked .md file must be non-empty, valid
# UTF-8, free of tabs-for-indent and trailing whitespace, with well-formed frontmatter
# (when it starts with `---`, a closing `---` and `key: value` lines), and every
# relative link must resolve to a tracked file. Needs only bash, git and python3.
# Prints `check: pass <short sha>` on success; any failure exits non-zero.
set -euo pipefail

builtin cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "check: step 1/2 shell syntax" >&2
for script in scripts/*.sh; do
  bash -n "$script" || {
    echo "check: FAIL at step 1/2 (bash -n $script)" >&2
    exit 1
  }
done

echo "check: step 2/2 markdown profiles" >&2
git ls-files -z -- '*.md' | python3 -I -c '
import os
import re
import sys

files = [f for f in sys.stdin.buffer.read().decode().split("\0") if f]
tracked = set(os.path.normpath(f) for f in files)
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
  echo "check: FAIL at step 2/2 (markdown profiles)" >&2
  exit 1
}

echo "check: pass $(git rev-parse --short HEAD)"
