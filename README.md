# agents
Agent profiles and personas, organised on a military unit structure

## Local check

Run the check before every push; CI runs the same command on every PR and every push to `main`:

```bash
bash scripts/check.sh
```

`scripts/check.sh` needs only bash, git and python3. It checks the shell scripts parse (`bash -n`) and lints every tracked `.md` file: non-empty, no trailing whitespace, newline at end of file, well-formed frontmatter (a closing `---`, `key: value` lines) and every relative link resolving to a tracked file. It prints `check: pass <short sha>` on success and exits non-zero on any failure.

The repo follows the trunk-readiness gate (`scripts/trunk-readiness.sh` in argus-config): a committed check, CI on push to `main` that runs it, and a green `main`.
