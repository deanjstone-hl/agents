"""Render profiles/*.md into the committed generated/ output (agents#9).

Run through scripts/render.sh. Standard library only. One profile gives two files:

  generated/agents/<id>.md   a Claude subagent file: the charter, with front matter mapped to
                             the subagent fields (name, description, tools, disallowedTools,
                             model, skills) and a body of culture, then the profile
  generated/briefs/<id>.md   the brief for a spawned worker: templates/brief.md filled with
                             the identity line, culture, charter and an input slot per
                             input. The original issue text is a mandatory input: its slot
                             is always there, listed in the profile or not

  bash scripts/render.sh [--root <dir>]                 write generated/
  bash scripts/render.sh [--root <dir>] --check         fail if generated/ is not what the sources render to
  bash scripts/render.sh [--root <dir>] --brief <id> --issue-file <file> [--input <name>=<file>]...
                                                        print one finished brief (the issue text verbatim) to stdout

Profiles are validated first with the profile check (scripts/check_profiles.py), so a profile
that fails it is never rendered. Everything is built in memory and written only if all of it
succeeded. Every failure prints `render: AGRnnn: <message>` (a profile problem prints the
profile check's own `profiles/<file>:<line>: AGPnnn` lines) and the exit status is 1; a usage
error exits 2.

  AGR001  doctrine/culture.md or templates/brief.md missing, unreadable or with nothing to join
  AGR002  the brief template has no {{inputs}} slot, so it would drop the issue text
  AGR003  the brief template holds a placeholder the renderer does not know
  AGR004  culture or a profile holds '{{', which is reserved for the brief's slots
  AGR005  a relative link in text that is copied into generated/ (it would point nowhere)
  AGR006  a profile's tools.allow is empty (a subagent file cannot say "no tools")
  AGR007  a profile failed the profile check
  AGR008  a --brief request is wrong: no or blank issue text, an input missing or unknown, an unknown profile
  AGR009  generated/ is stale, missing a file or holds a file no profile makes (--check)
  AGR010  a culture heading is too deep to move down one level
"""

import argparse
import importlib.util
import json
import os
import re
import sys

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(SCRIPTS, ".."))
SCHEMA_PATH = os.path.join(REPO, "schema", "profile.schema.json")

CULTURE_PATH = "doctrine/culture.md"
TEMPLATE_PATH = "templates/brief.md"
CULTURE_END = "<!-- render:end -->"
OUTPUT_DIRS = ("generated/agents", "generated/briefs")
PLACEHOLDERS = ("id", "mission", "identity", "culture", "charter", "inputs")
ISSUE_INPUT = "issue_text"

PLACEHOLDER = re.compile(r"\{\{([^{}]*)\}\}")
HEADING = re.compile(r"^(#{1,6}) +\S")
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
ABSOLUTE = re.compile(r"^(?:[a-z][a-z0-9+.-]*:|#|/)")


class Errors:
    def __init__(self):
        self.items = []

    def add(self, code, message):
        self.items.append((code, message))

    def __len__(self):
        return len(self.items)

    def report(self):
        for code, message in self.items:
            print(f"render: {code}: {message}", file=sys.stderr)


def load_checker():
    spec = importlib.util.spec_from_file_location("check_profiles", os.path.join(SCRIPTS, "check_profiles.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_source(root, rel, errors):
    try:
        with open(os.path.join(root, rel), encoding="utf-8") as handle:
            return handle.read()
    except FileNotFoundError:
        errors.add("AGR001", f"{rel} does not exist")
    except (UnicodeDecodeError, OSError) as exc:
        errors.add("AGR001", f"{rel} is unreadable ({exc})")
    return None


def fence_flags(lines):
    """For each line, whether it is a code fence line or inside one."""
    flags, inside = [], False
    for line in lines:
        if line.lstrip().startswith("```"):
            inside = not inside
            flags.append(True)
        else:
            flags.append(inside)
    return flags


def trim_blank(lines):
    start, end = 0, len(lines)
    while start < end and not lines[start].strip():
        start += 1
    while end > start and not lines[end - 1].strip():
        end -= 1
    return lines[start:end]


# --- culture ----------------------------------------------------------------------------------


def culture_block(text, errors):
    """The culture text to join: from the first '## ' section to the render:end marker, every
    heading one level down so it sits under '## Culture'. None when it cannot be built."""
    lines = text.split("\n")
    flags = fence_flags(lines)
    for index, line in enumerate(lines):
        if line.strip() == CULTURE_END and not flags[index]:
            lines, flags = lines[:index], flags[:index]
            break
    first = next((i for i, line in enumerate(lines) if line.startswith("## ") and not flags[i]), None)
    if first is None:
        errors.add("AGR001", f"{CULTURE_PATH} has no '## ' section to join")
        return None
    joined = []
    for line, fenced in zip(lines[first:], flags[first:]):
        match = None if fenced else HEADING.match(line)
        if match:
            if len(match.group(1)) >= 6:
                errors.add("AGR010", f"{CULTURE_PATH}: heading '{line}' is too deep to move down one level")
                return None
            line = "#" + line
        joined.append(line)
    joined = trim_blank(joined)
    if not joined:
        errors.add("AGR001", f"{CULTURE_PATH} has nothing to join")
        return None
    return "\n".join(["## Culture", ""] + joined)


# --- checks on text that is copied into generated/ ---------------------------------------------


def check_copied_text(text, label, errors, slots_allowed=False):
    """label names the source file. The '{{' ban keeps a slot unambiguous (the brief template
    is the one file that holds them); a relative link would resolve from generated/ instead
    of from its source."""
    if "{{" in text and not slots_allowed:
        errors.add("AGR004", f"{label} holds '{{{{', which is reserved for the brief's slots")
    lines = text.split("\n")
    for line, fenced in zip(lines, fence_flags(lines)):
        if fenced:
            continue
        for target in LINK.findall(line):
            if ABSOLUTE.match(target) or not target.split("#", 1)[0]:
                continue
            errors.add("AGR005", f"{label}: relative link {target} would point nowhere from generated/; use an absolute URL")


# --- one profile ------------------------------------------------------------------------------


def identity_line(front):
    return (
        f"Rank: {front['rank']}. Section: {front['section']}. Lane: {front['lane']}. "
        f"Version: {front['version']}. Reports to: {front['reports_to']}. "
        f"Escalates to: {front['escalates_to']}."
    )


def provenance(identifier):
    return f"<!-- Generated by scripts/render.sh from profiles/{identifier}.md. Do not edit. -->"


def yaml_list(key, values):
    return [f"{key}:"] + [f"  - {json.dumps(value, ensure_ascii=False)}" for value in values]


def agent_file(front, culture, body):
    lines = ["---", f"name: {front['id']}", f"description: {json.dumps(front['mission'], ensure_ascii=False)}"]
    lines += yaml_list("tools", front["tools"]["allow"])
    if front["tools"]["deny"]:
        lines += yaml_list("disallowedTools", front["tools"]["deny"])
    if front["model"] != "auto":
        lines.append(f"model: {front['model']}")
    if front.get("skills"):
        lines += yaml_list("skills", front["skills"])
    lines += ["---", "", provenance(front["id"]), "", f"# {front['id']}", "", identity_line(front), "", culture, "", body]
    return "\n".join(lines) + "\n"


def input_names(front):
    return [ISSUE_INPUT] + [name for name in front["inputs"] if name != ISSUE_INPUT]


def inputs_block(front, values):
    """The Inputs section: one slot per input, the issue text first. values maps an input name
    to its content, or is None to leave each slot as a literal {{name}} line."""
    lines = ["## Inputs"]
    for name in input_names(front):
        note = (
            "The original issue text, verbatim. Do not summarise or paraphrase it."
            if name == ISSUE_INPUT
            else "Supplied by the caller, verbatim."
        )
        slot = "{{" + name + "}}" if values is None else values[name]
        lines += ["", f"### {name}", "", note, "", f"<!-- input:{name}:begin -->", slot, f"<!-- input:{name}:end -->"]
    return "\n".join(lines)


def brief_file(front, culture, body, template, values=None):
    parts = {
        "id": front["id"],
        "mission": front["mission"],
        "identity": identity_line(front),
        "culture": culture,
        "charter": body,
        "inputs": inputs_block(front, values),
    }
    # One pass: a filled-in value is never scanned for placeholders again.
    filled = PLACEHOLDER.sub(lambda match: parts[match.group(1)], template).strip("\n")
    return provenance(front["id"]) + "\n\n" + filled + "\n"


# --- loading everything ------------------------------------------------------------------------


def load_template(root, errors):
    text = read_source(root, TEMPLATE_PATH, errors)
    if text is None:
        return None
    names = PLACEHOLDER.findall(text)
    unknown = sorted({name for name in names if name not in PLACEHOLDERS})
    for name in unknown:
        errors.add("AGR003", f"{TEMPLATE_PATH} holds an unknown placeholder {{{{{name}}}}}; the known ones are {', '.join('{{' + p + '}}' for p in PLACEHOLDERS)}")
    if "inputs" not in names:
        errors.add(
            "AGR002",
            f"{TEMPLATE_PATH} has no {{{{inputs}}}} slot, so a brief would carry no issue text, and the original issue text is a mandatory brief input",
        )
    check_copied_text(text, TEMPLATE_PATH, errors, slots_allowed=True)
    return None if unknown or "inputs" not in names else text


def load_profiles(root, checker, errors):
    """Validated profiles as (front, body text). A profile problem prints the profile check's
    lines and adds one AGR007."""
    with open(SCHEMA_PATH, encoding="utf-8") as handle:
        schema = json.load(handle)
    findings = checker.Findings()
    profile_dir = os.path.join(root, "profiles")
    names = sorted(n for n in os.listdir(profile_dir) if n.endswith(".md") and n != "README.md") if os.path.isdir(profile_dir) else []
    loaded = []
    for name in names:
        rel = f"profiles/{name}"
        try:
            with open(os.path.join(profile_dir, name), encoding="utf-8") as handle:
                text = handle.read()
        except (UnicodeDecodeError, OSError) as exc:
            findings.add(rel, 1, "AGP012", f"unreadable ({exc})")
            continue
        front, body_rows, line_of = checker.load_profile(text, schema, rel, findings)
        if front is None:
            continue
        checker.check_identity(front, name[:-3], rel, line_of, findings)
        checker.check_body(body_rows, schema, rel, findings)
        loaded.append((rel, front, "\n".join(trim_blank([row[1] for row in body_rows]))))
    if findings.items:
        for path, line, code, message in findings.items:
            print(f"{path}:{line}: {code}: {message}" if line else f"{path}: {code}: {message}", file=sys.stderr)
        errors.add("AGR007", f"{len({item[0] for item in findings.items})} profile file(s) fail the profile check; nothing rendered")
        return None
    return loaded


def build(root, errors):
    """Returns ({output path: text}, {id: (front, culture, body, template)}) or (None, None)."""
    checker = load_checker()
    culture_text = read_source(root, CULTURE_PATH, errors)
    culture = culture_block(culture_text, errors) if culture_text is not None else None
    if culture is not None:
        check_copied_text(culture, CULTURE_PATH, errors)
    template = load_template(root, errors)
    profiles = load_profiles(root, checker, errors)
    if profiles is None or culture is None or template is None:
        return None, None
    outputs, parts = {}, {}
    for rel, front, body in profiles:
        check_copied_text(body, rel, errors)
        if not front["tools"]["allow"]:
            errors.add("AGR006", f"{rel}: tools.allow is empty, and a subagent file that names no tools inherits every tool; list the tools the role may use")
            continue
        identifier = front["id"]
        outputs[f"generated/agents/{identifier}.md"] = agent_file(front, culture, body)
        outputs[f"generated/briefs/{identifier}.md"] = brief_file(front, culture, body, template)
        parts[identifier] = (front, culture, body, template)
    if len(errors):
        return None, None
    return outputs, parts


# --- modes ------------------------------------------------------------------------------------


def existing_outputs(root):
    found = set()
    for directory in OUTPUT_DIRS:
        full = os.path.join(root, directory)
        if os.path.isdir(full):
            found.update(f"{directory}/{n}" for n in os.listdir(full) if n.endswith(".md") and os.path.isfile(os.path.join(full, n)))
    return found


def read_existing(root, rel):
    try:
        with open(os.path.join(root, rel), encoding="utf-8", newline="") as handle:
            return handle.read()
    except (UnicodeDecodeError, OSError):
        return None


def mode_write(root, outputs):
    written = 0
    for rel, text in sorted(outputs.items()):
        if read_existing(root, rel) == text:
            continue
        full = os.path.join(root, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        written += 1
    removed = sorted(existing_outputs(root) - set(outputs))
    for rel in removed:
        os.remove(os.path.join(root, rel))
    print(f"render: {len(outputs) // 2} profile(s), {written} file(s) written, {len(removed)} removed", file=sys.stderr)
    return 0


def mode_check(root, outputs, errors):
    for rel, text in sorted(outputs.items()):
        current = read_existing(root, rel)
        if current is None:
            errors.add("AGR009", f"MISSING: {rel} is not there; run bash scripts/render.sh")
        elif current != text:
            errors.add("AGR009", f"STALE: {rel} is not what its sources render to; run bash scripts/render.sh")
    for rel in sorted(existing_outputs(root) - set(outputs)):
        errors.add("AGR009", f"ORPHAN: {rel} is made by no profile; run bash scripts/render.sh")
    if len(errors):
        return 1
    print(f"render: check: {len(outputs)} file(s) up to date", file=sys.stderr)
    return 0


def read_input(path, label, errors):
    try:
        with open(path, "rb") as handle:
            return handle.read().decode("utf-8")
    except FileNotFoundError:
        errors.add("AGR008", f"{label} {path} does not exist")
    except UnicodeDecodeError:
        errors.add("AGR008", f"{label} {path} is not valid UTF-8")
    except OSError as exc:
        errors.add("AGR008", f"{label} {path} is unreadable ({exc})")
    return None


def mode_brief(parts, identifier, issue_file, input_args, errors):
    if identifier not in parts:
        errors.add("AGR008", f"no profile '{identifier}' (profiles: {', '.join(sorted(parts)) or 'none'})")
        return 1
    front, culture, body, template = parts[identifier]
    values = {}
    if issue_file is None:
        errors.add("AGR008", "the original issue text is a mandatory brief input: pass --issue-file <file>")
    else:
        issue = read_input(issue_file, "issue file", errors)
        if issue is not None:
            if not issue.strip():
                errors.add("AGR008", f"the original issue text is a mandatory brief input, and {issue_file} is blank")
            else:
                values[ISSUE_INPUT] = issue
    declared = [name for name in input_names(front) if name != ISSUE_INPUT]
    supplied = {}
    for argument in input_args:
        name, separator, path = argument.partition("=")
        if not separator or not name or not path:
            errors.add("AGR008", f"--input '{argument}' is not <name>=<file>")
        elif name == ISSUE_INPUT:
            errors.add("AGR008", "the issue text is passed with --issue-file, not --input")
        elif name not in declared:
            errors.add("AGR008", f"unknown input '{name}' for {identifier} (it declares: {', '.join(declared) or 'only the issue text'})")
        elif name in supplied:
            errors.add("AGR008", f"input '{name}' given twice")
        else:
            content = read_input(path, f"input {name}", errors)
            if content is not None:
                supplied[name] = content
    for name in declared:
        if name not in supplied and not any(arg.partition("=")[0] == name for arg in input_args):
            errors.add("AGR008", f"missing input '{name}': {identifier} declares it, pass --input {name}=<file>")
    if len(errors):
        return 1
    values.update(supplied)
    sys.stdout.buffer.write(brief_file(front, culture, body, template, values).encode("utf-8"))
    return 0


def main():
    parser = argparse.ArgumentParser(prog="render.sh", description=__doc__.split("\n")[0])
    parser.add_argument("--root", default=REPO, help="repository holding profiles/, doctrine/ and templates/ (default: this repository)")
    parser.add_argument("--check", action="store_true", help="fail if generated/ is not what the sources render to; write nothing")
    parser.add_argument("--brief", metavar="ID", help="print the finished brief for one profile to stdout; write nothing")
    parser.add_argument("--issue-file", metavar="FILE", help="with --brief: the original issue text, inserted verbatim (mandatory)")
    parser.add_argument("--input", action="append", default=[], metavar="NAME=FILE", help="with --brief: one more declared input, inserted verbatim")
    args = parser.parse_args()
    if args.check and args.brief is not None:
        parser.error("--check and --brief cannot be used together")
    if args.brief is None and (args.issue_file is not None or args.input):
        parser.error("--issue-file and --input need --brief")
    root = os.path.abspath(args.root)

    errors = Errors()
    outputs, parts = build(root, errors)
    if outputs is None:
        errors.report()
        return 1
    if args.brief is not None:
        status = mode_brief(parts, args.brief, args.issue_file, args.input, errors)
    elif args.check:
        status = mode_check(root, outputs, errors)
    else:
        status = mode_write(root, outputs)
    errors.report()
    return status


if __name__ == "__main__":
    sys.exit(main())
