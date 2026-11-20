#!/usr/bin/env python3
"""The parts of one Architecture scout run that need parsing (agents#20).

scripts/arch-scout-run.sh does the processes: it fetches the rolling issue, renders the brief,
runs `claude -p` under its hard stops and posts the comment. This file does the reading and
writing around them, so each can be tested without a model:

  agent --file F --field name|tools|disallowed|model|agents-json
        read a generated agent file (generated/agents/<id>.md); `agents-json` is the value of
        `claude --agents`, built from the profile so its tool list is the profile's own
  view --view F --week W --prior-out F --issue-out F
        read `gh issue view --json body,comments`: print `runs N` and `week_done 0|1` from the
        run markers in earlier comments, write the earlier comments to --prior-out and the
        issue body to --issue-out
  usage --transcript F
        read a session transcript: print {"requests": N, "output_tokens": N}. A request is one
        assistant message id; the transcript repeats it once per content block, so the largest
        count per id is kept and the ids are summed
  comment ...
        build the comment for one run, print `status <name>` and `exit <n>`

Statuses: ok, over-token (posted and flagged, exit 0), then max-turns, timeout, error, bad-shape
and no-transcript (posted, exit 3). The owner's caps (agents#19): `--max-turns` and the timeout are
hard stops; the output-token figure is a target that is read back and reported, never a stop.
Python 3 standard library only.
"""

import argparse
import json
import re
import sys

MARKER = re.compile(r"<!-- arch-scout-run: (\{.*?\}) -->")
FINDING_HEADING = re.compile(r"^### F\d+\b", re.MULTILINE)
YES_OR_NO = re.compile(r"yes or no:", re.IGNORECASE)
NO_FINDINGS = "No findings this week."
MAX_FINDINGS = 5
PRIOR_COMMENTS = 6
PRIOR_CHARS = 20000


def read_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def scalar_value(raw):
    """A front matter scalar: JSON-quoted by the renderer when it needs quotes, bare otherwise."""
    try:
        return json.loads(raw)
    except ValueError:
        return raw


def agent_file(args):
    text = open(args.file, encoding="utf-8").read()
    lines = text.split("\n")
    if lines[0] != "---":
        sys.exit(f"{args.file}: no front matter")
    end = lines.index("---", 1)
    values = {}
    key = None
    for line in lines[1:end]:
        item = re.match(r"^\s+-\s+(.*)$", line)
        scalar = re.match(r"^([A-Za-z]+):\s*(.*)$", line)
        if item and key:
            values[key].append(json.loads(item.group(1)))
        elif scalar:
            key = scalar.group(1)
            values[key] = scalar_value(scalar.group(2)) if scalar.group(2) else []
    prompt = "\n".join(lines[end + 1 :]).strip() + "\n"
    name = values["name"]
    if args.field == "name":
        print(name)
    elif args.field == "tools":
        print(",".join(values["tools"]))
    elif args.field == "disallowed":
        print(",".join(values.get("disallowedTools", [])))
    elif args.field == "model":
        print(values.get("model", ""))
    else:
        definition = {"description": values["description"], "prompt": prompt, "tools": values["tools"]}
        if values.get("model"):
            definition["model"] = values["model"]
        print(json.dumps({name: definition}))


def comment_markers(comment):
    markers = []
    for raw in MARKER.findall(comment.get("body") or ""):
        try:
            markers.append(json.loads(raw))
        except ValueError:
            continue
    return markers


def view(args):
    doc = read_json(args.view)
    comments = doc.get("comments") or []
    runs = 0
    week_done = 0
    for comment in comments:
        for marker in comment_markers(comment):
            runs += 1
            if marker.get("week") == args.week:
                week_done = 1
    chunks = []
    for comment in comments[-PRIOR_COMMENTS:]:
        author = (comment.get("author") or {}).get("login", "unknown")
        chunks.append(
            f"#### Comment by {author} on {comment.get('createdAt', '?')} ([comment]({comment.get('url', '')}))\n\n"
            + (comment.get("body") or "").strip()
        )
    prior = "\n\n".join(chunks) if chunks else "No earlier runs."
    if len(prior) > PRIOR_CHARS:
        prior = "[earlier comments cut]\n\n" + prior[-PRIOR_CHARS:]
    with open(args.prior_out, "w", encoding="utf-8") as handle:
        handle.write(prior + "\n")
    with open(args.issue_out, "w", encoding="utf-8") as handle:
        handle.write((doc.get("body") or "").strip() + "\n")
    print(f"runs {runs}")
    print(f"week_done {week_done}")


def transcript_usage(path):
    best = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            try:
                row = json.loads(line)
            except ValueError:
                continue
            message = row.get("message") if row.get("type") == "assistant" else None
            if not isinstance(message, dict) or not message.get("id"):
                continue
            tokens = (message.get("usage") or {}).get("output_tokens")
            if isinstance(tokens, int):
                best[message["id"]] = max(best.get(message["id"], 0), tokens)
    return {"requests": len(best), "output_tokens": sum(best.values())}


def usage(args):
    print(json.dumps(transcript_usage(args.transcript)))


def split_findings(reply):
    """The finding blocks of a reply, from the first `### F<n>` heading on."""
    starts = [m.start() for m in FINDING_HEADING.finditer(reply)]
    blocks = []
    for index, start in enumerate(starts):
        stop = starts[index + 1] if index + 1 < len(starts) else len(reply)
        blocks.append(reply[start:stop].rstrip())
    return blocks


def plural(count, word):
    return f"{count} {word}" if count == 1 else f"{count} {word}s"


def clock(seconds):
    return f"{seconds // 60}m {seconds % 60:02d}s"


def cap_label(seconds):
    return f"{seconds // 60} min" if seconds >= 60 and seconds % 60 == 0 else f"{seconds} s"


def comment(args):
    result = None
    if args.result:
        try:
            result = read_json(args.result)
        except (OSError, ValueError):
            result = None
    token_info = None
    if args.transcript:
        try:
            token_info = transcript_usage(args.transcript)
        except OSError:
            token_info = None
    tokens = token_info["output_tokens"] if token_info else None
    turns = None
    if result and isinstance(result.get("num_turns"), int):
        turns = result["num_turns"]
    elif token_info:
        turns = token_info["requests"]

    reply = ""
    if result and result.get("subtype") == "success" and not result.get("is_error"):
        reply = (result.get("result") or "").strip()

    kept = []
    dropped_no_question = 0
    dropped_over_cap = 0
    no_findings = False
    stopped = ""

    if args.hint == "timeout":
        status = "timeout"
        stopped = f"**Stopped at the time cap ({cap_label(args.timeout)}).** No findings were taken from this run."
    elif result is None:
        status = "error"
        stopped = "**The run failed.** `claude` printed no readable result. No findings were taken from this run."
    elif result.get("subtype") == "error_max_turns":
        status = "max-turns"
        stopped = f"**Stopped at the turn cap ({args.max_turns} turns).** No findings were taken from this run."
    elif result.get("subtype") != "success" or result.get("is_error"):
        status = "error"
        stopped = f"**The run failed** (`{result.get('subtype', 'unknown')}`). No findings were taken from this run."
    else:
        blocks = split_findings(reply)
        if blocks:
            valid = [block for block in blocks if YES_OR_NO.search(block)]
            dropped_no_question = len(blocks) - len(valid)
            kept = valid[:MAX_FINDINGS]
            dropped_over_cap = len(valid) - len(kept)
        elif NO_FINDINGS in reply:
            no_findings = True
        if kept or no_findings:
            if tokens is None:
                status = "no-transcript"
            elif tokens > args.token_target:
                status = "over-token"
            else:
                status = "ok"
        else:
            status = "bad-shape"

    renumbered = []
    for number, block in enumerate(kept, 1):
        renumbered.append(re.sub(r"^### F\d+", f"### F{number}", block, count=1))

    lines = [f"## Architecture scout, run {args.run} (week {args.week}, {args.when})", ""]
    lines.append(f"Target: `{args.target_name}`")
    lines.append("")
    if stopped:
        lines += [stopped, ""]
    elif status == "bad-shape":
        lines += [
            "**The reply had no valid findings.** It had neither a finding with a yes-or-no question nor the line "
            f"`{NO_FINDINGS}`, so nothing was taken from it.",
            "",
        ]
    elif renumbered:
        lines += ["\n\n".join(renumbered), ""]
    else:
        lines += [NO_FINDINGS, ""]
    notes = []
    if dropped_over_cap:
        notes.append(f"{plural(dropped_over_cap, 'finding')} dropped: over the cap of {MAX_FINDINGS}.")
    if dropped_no_question:
        notes.append(f"{plural(dropped_no_question, 'finding')} dropped: no yes-or-no question.")
    if notes:
        lines += ["  \n".join(notes), ""]

    if tokens is None:
        token_text = "output tokens unavailable (no transcript found)"
    else:
        token_text = f"output tokens {tokens:,} (target {args.token_target:,})"
    turn_text = f"turns {turns if turns is not None else '?'} of {args.max_turns}"
    time_text = f"time {clock(args.seconds)} of {clock(args.timeout)}"
    if status == "ok":
        verdict = "within caps"
    elif status == "over-token":
        verdict = "**OVER the token target**: tighten the cap (lower `SCOUT_MAX_TURNS`) before the next run"
    elif status == "no-transcript":
        verdict = "**caps not confirmed**"
    else:
        verdict = f"**{status}**"
    lines += ["---", f"Run stats: {turn_text} · {time_text} · {token_text} · {verdict}"]
    if renumbered:
        lines.append("Answer each finding with `F1 yes` or `F1 no` (one per line) in a reply.")
    marker = {
        "week": args.week,
        "run": args.run,
        "status": status,
        "turns": turns,
        "output_tokens": tokens,
        "seconds": args.seconds,
        "findings": len(renumbered),
    }
    lines += ["", f"<!-- arch-scout-run: {json.dumps(marker)} -->", ""]
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    print(f"status {status}")
    print(f"exit {0 if status in ('ok', 'over-token') else 3}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    agent = sub.add_parser("agent")
    agent.add_argument("--file", required=True)
    agent.add_argument("--field", required=True, choices=["name", "tools", "disallowed", "model", "agents-json"])
    agent.set_defaults(func=agent_file)

    view_parser = sub.add_parser("view")
    view_parser.add_argument("--view", required=True)
    view_parser.add_argument("--week", required=True)
    view_parser.add_argument("--prior-out", required=True)
    view_parser.add_argument("--issue-out", required=True)
    view_parser.set_defaults(func=view)

    usage_parser = sub.add_parser("usage")
    usage_parser.add_argument("--transcript", required=True)
    usage_parser.set_defaults(func=usage)

    comment_parser = sub.add_parser("comment")
    comment_parser.add_argument("--result", default="")
    comment_parser.add_argument("--transcript", default="")
    comment_parser.add_argument("--hint", default="", choices=["", "timeout"])
    comment_parser.add_argument("--seconds", type=int, required=True)
    comment_parser.add_argument("--max-turns", type=int, required=True)
    comment_parser.add_argument("--timeout", type=int, required=True)
    comment_parser.add_argument("--token-target", type=int, required=True)
    comment_parser.add_argument("--week", required=True)
    comment_parser.add_argument("--run", type=int, required=True)
    comment_parser.add_argument("--when", required=True)
    comment_parser.add_argument("--target-name", required=True)
    comment_parser.add_argument("--out", required=True)
    comment_parser.set_defaults(func=comment)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
