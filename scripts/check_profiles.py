"""Check profiles/*.md against schema/profile.schema.json (agents#8).

Run through scripts/check-profiles.sh. Standard library only: the check needs bash, git and
python3 and nothing else, so it carries a small validator for the JSON Schema keywords the
schema uses and a reader for the YAML subset a profile's front matter is allowed to use
(`key: scalar`, `key: [a, b]`, and one nested level of mappings and `- item` lists).

Every failure prints `profiles/<file>:<line>: AGPnnn: <message>` and the exit status is 1.

  AGP001  missing required key
  AGP002  unknown key (extensions start with x-)
  AGP003  duplicate key
  AGP004  value does not fit the schema (type, enum, pattern, length, items)
  AGP005  id is not the file name
  AGP006  id prefix is not the rank
  AGP007  missing or empty required section
  AGP008  section duplicated, unknown, out of order or text before the first section
  AGP009  Voice is longer than the cap
  AGP010  Learned is over the line or length cap
  AGP011  authority field changed without a higher version
  AGP012  front matter missing, unclosed or not readable
  AGP013  tools.allow lists a tool above the rank's ceiling (doctrine/units.md, Rank ceiling)
  AGP014  the rank ceiling table cannot be read: file, section, table, rows or tool names
"""

import argparse
import copy
import json
import os
import re
import subprocess
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SCHEMA_PATH = os.path.join(REPO, "schema", "profile.schema.json")
UNITS_PATH = os.path.join(REPO, "doctrine", "units.md")
UNITS_DISPLAY = "doctrine/units.md"
CEILING_HEADING = "## Rank ceiling"
DEFAULT_BASE = "origin/main"


class Findings:
    def __init__(self):
        self.items = []

    def add(self, path, line, code, message):
        self.items.append((path, line, code, message))

    def __len__(self):
        return len(self.items)


# --- front matter: a small YAML subset --------------------------------------------------------

KEY_LINE = re.compile(r"^([A-Za-z0-9_-]+):(?:\s+(.*))?$")
INT = re.compile(r"^-?[0-9]+$")
FLOAT = re.compile(r"^-?[0-9]+\.[0-9]+$")


class FrontMatterError(Exception):
    def __init__(self, line, message):
        super().__init__(message)
        self.line = line
        self.message = message


def split_flow(text, line):
    parts, current, quote = [], "", None
    for char in text:
        if quote:
            current += char
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
            current += char
        elif char == ",":
            parts.append(current)
            current = ""
        else:
            current += char
    if quote:
        raise FrontMatterError(line, "unterminated quote in a list")
    if current.strip() or parts:
        parts.append(current)
    return [p.strip() for p in parts]


def parse_scalar(text, line):
    text = text.strip()
    if text.startswith('"'):
        try:
            value = json.loads(text)
        except ValueError:
            raise FrontMatterError(line, f"bad double-quoted string {text}")
        if not isinstance(value, str):
            raise FrontMatterError(line, f"bad double-quoted string {text}")
        return value
    if text.startswith("'"):
        if len(text) < 2 or not text.endswith("'"):
            raise FrontMatterError(line, f"bad single-quoted string {text}")
        return text[1:-1].replace("''", "'")
    if text.startswith("["):
        if not text.endswith("]"):
            raise FrontMatterError(line, "a [list] must close on the same line")
        return [parse_scalar(part, line) for part in split_flow(text[1:-1], line) if part != ""]
    if text[:1] in "{&*!|>%@`":
        raise FrontMatterError(line, f"unsupported YAML syntax '{text[:1]}': use plain or quoted scalars and lists")
    if " #" in text:
        text = text.split(" #", 1)[0].rstrip()
    if ": " in text or text.endswith(":"):
        raise FrontMatterError(line, "a value containing ': ' must be quoted")
    if text in ("true", "false"):
        return text == "true"
    if text in ("null", "~"):
        return None
    if INT.match(text):
        return int(text)
    if FLOAT.match(text):
        return float(text)
    return text


def parse_front_matter(rows, findings, path):
    """rows: (line number, text) for the lines between the two --- markers.

    Returns (mapping, {key: line}). Problems go to findings; the mapping keeps what parsed."""
    items = []
    for number, text in rows:
        stripped = text.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "\t" in text[: len(text) - len(text.lstrip())]:
            findings.add(path, number, "AGP012", "tab used to indent front matter")
            continue
        items.append((number, len(text) - len(text.lstrip(" ")), stripped))

    key_lines = {}

    def parse_list(index, indent):
        values = []
        while index < len(items) and items[index][1] == indent and (
            items[index][2] == "-" or items[index][2].startswith("- ")
        ):
            number, _, text = items[index]
            rest = text[1:].strip()
            if not rest:
                findings.add(path, number, "AGP012", "an empty '-' list item")
            else:
                try:
                    values.append(parse_scalar(rest, number))
                except FrontMatterError as exc:
                    findings.add(path, exc.line, "AGP012", exc.message)
            index += 1
        return values, index

    def parse_mapping(index, indent, top):
        mapping = {}
        while index < len(items):
            number, item_indent, text = items[index]
            if item_indent < indent:
                break
            if item_indent > indent:
                findings.add(path, number, "AGP012", "unexpected indentation")
                index += 1
                continue
            match = KEY_LINE.match(text)
            if not match:
                findings.add(path, number, "AGP012", f"not a 'key: value' line: {text}")
                index += 1
                continue
            key, rest = match.group(1), match.group(2)
            index += 1
            value = None
            if rest is None or not rest.strip():
                if index < len(items):
                    next_number, next_indent, next_text = items[index]
                    is_item = next_text == "-" or next_text.startswith("- ")
                    if next_indent > indent:
                        if is_item:
                            value, index = parse_list(index, next_indent)
                        else:
                            value, index = parse_mapping(index, next_indent, False)
                    elif next_indent == indent and is_item:
                        value, index = parse_list(index, indent)
            else:
                try:
                    value = parse_scalar(rest, number)
                except FrontMatterError as exc:
                    findings.add(path, exc.line, "AGP012", exc.message)
                    value = None
            if key in mapping:
                findings.add(path, number, "AGP003", f"duplicate key '{key}'")
                continue
            mapping[key] = value
            if top:
                key_lines[key] = number
        return mapping, index

    result = parse_mapping(0, 0, True)[0] if items else {}
    return result, key_lines


def split_profile(text):
    """Returns (front rows, body rows, error) with 1-based line numbers."""
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    if not lines or lines[0] != "---":
        return None, None, "the file must start with a --- front matter block"
    closing = next((i for i, line in enumerate(lines[1:], 1) if line == "---"), None)
    if closing is None:
        return None, None, "front matter is not closed with ---"
    front = [(i + 1, lines[i]) for i in range(1, closing)]
    body = [(i + 1, lines[i]) for i in range(closing + 1, len(lines))]
    return front, body, None


# --- a small JSON Schema validator ----------------------------------------------------------


def type_name(value):
    if value is None:
        return "an empty value"
    if isinstance(value, bool):
        return "a boolean"
    if isinstance(value, (int, float)):
        return "a number"
    if isinstance(value, str):
        return "a string"
    if isinstance(value, list):
        return "a list"
    return "a mapping"


def type_ok(value, expected):
    if expected == "string":
        return isinstance(value, str)
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    return True


def join_path(path, key):
    return f"{path}.{key}" if path else key


def validate(value, schema, path, errors):
    """Append (path, code, message) for each way value fails schema."""
    expected = schema.get("type")
    if expected and not type_ok(value, expected):
        errors.append((path, "AGP004", f"{path}: expected {expected}, got {type_name(value)}"))
        return
    if "enum" in schema and value not in schema["enum"]:
        options = ", ".join(str(option) for option in schema["enum"])
        errors.append((path, "AGP004", f"{path}: {value!r} is not one of {options}"))
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            errors.append((path, "AGP004", f"{path}: must not be empty"))
        pattern = schema.get("pattern")
        if pattern and not re.search(pattern, value):
            errors.append((path, "AGP004", f"{path}: {value!r} does not match {pattern}"))
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        extensions = [re.compile(p) for p in schema.get("patternProperties", {})]
        for key in schema.get("required", []):
            if key not in value:
                errors.append((join_path(path, key), "AGP001", f"missing required key '{join_path(path, key)}'"))
        for key, sub in value.items():
            if key in properties:
                validate(sub, properties[key], join_path(path, key), errors)
            elif not any(p.search(key) for p in extensions) and schema.get("additionalProperties") is False:
                hint = " (extensions start with x-)" if not path else ""
                errors.append((join_path(path, key), "AGP002", f"unknown key '{join_path(path, key)}'{hint}"))
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            errors.append((path, "AGP004", f"{path}: needs at least {schema['minItems']} item(s)"))
        if schema.get("uniqueItems") and len({json.dumps(item, sort_keys=True) for item in value}) != len(value):
            errors.append((path, "AGP004", f"{path}: items must be unique"))
        item_schema = schema.get("items")
        if item_schema:
            for index, item in enumerate(value):
                validate(item, item_schema, f"{path}[{index}]", errors)


def with_defaults(front, schema):
    effective = copy.deepcopy(front)
    for key, sub in schema.get("properties", {}).items():
        if key not in effective and "default" in sub:
            effective[key] = copy.deepcopy(sub["default"])
    return effective


# --- one profile ----------------------------------------------------------------------------


def load_profile(text, schema, path, findings):
    """Parse and validate one profile's text.

    Returns (effective front matter or None, body rows, line_of) where line_of(key) is the line
    of a top-level key, or the first front matter line."""
    front_rows, body_rows, problem = split_profile(text)
    if problem:
        findings.add(path, 1, "AGP012", problem)
        return None, None, None
    front, key_lines = parse_front_matter(front_rows, findings, path)
    first = front_rows[0][0] if front_rows else 2

    def line_of(key):
        return key_lines.get(key, first)

    errors = []
    validate(front, schema, "", errors)
    for key_path, code, message in errors:
        findings.add(path, line_of(re.split(r"[.\[]", key_path)[0]), code, message)
    return with_defaults(front, schema), body_rows, line_of


def check_identity(front, stem, path, line_of, findings):
    identity = front.get("id")
    rank = front.get("rank")
    if isinstance(identity, str):
        if identity != stem:
            findings.add(path, line_of("id"), "AGP005", f"id '{identity}' is not the file name '{stem}'")
        prefix = identity.split("-", 1)[0]
        if isinstance(rank, str) and prefix in ("scout", "specialist", "lead", "staff") and prefix != rank:
            findings.add(path, line_of("id"), "AGP006", f"id prefix '{prefix}' is not the rank '{rank}'")


def check_body(body_rows, schema, path, findings):
    spec = schema["x-body"]
    required = spec["sections"]
    optional = spec["optionalSections"]
    known = required + optional

    sections = []  # (heading, line, content lines)
    preamble = []
    in_fence = False
    for number, text in body_rows:
        if text.lstrip().startswith("```"):
            in_fence = not in_fence
        heading = None if in_fence or text.lstrip().startswith("```") else re.match(r"^## (.+)$", text)
        if heading:
            sections.append([heading.group(1), number, []])
        elif sections:
            sections[-1][2].append(text)
        elif text.strip():
            preamble.append(number)

    if preamble:
        findings.add(path, preamble[0], "AGP008", "text before the first '## ' section")

    seen = {}
    order = []
    for heading, number, content in sections:
        if heading not in known:
            findings.add(path, number, "AGP008", f"unknown section '{heading}'")
        elif heading in seen:
            findings.add(path, number, "AGP008", f"duplicate section '{heading}'")
        else:
            seen[heading] = (number, content)
            order.append(heading)

    for heading in required:
        if heading not in seen:
            findings.add(path, 1, "AGP007", f"missing section '## {heading}'")
        elif not any(line.strip() for line in seen[heading][1]):
            findings.add(path, seen[heading][0], "AGP007", f"section '## {heading}' is empty")

    furthest = -1
    for heading in order:
        index = known.index(heading)
        if index < furthest:
            after = known[furthest]
            findings.add(path, seen[heading][0], "AGP008", f"section '## {heading}' is out of order: it comes before '## {after}'")
        else:
            furthest = index

    if "Voice" in seen:
        lines = [line for line in seen["Voice"][1] if line.strip()]
        if len(lines) > spec["voiceMaxLines"]:
            findings.add(path, seen["Voice"][0], "AGP009", f"Voice has {len(lines)} lines, the cap is {spec['voiceMaxLines']}")
    if "Learned" in seen:
        lines = [line for line in seen["Learned"][1] if line.strip()]
        if len(lines) > spec["learnedMaxLines"]:
            findings.add(path, seen["Learned"][0], "AGP010", f"Learned has {len(lines)} lines, the cap is {spec['learnedMaxLines']}")
        for line in lines:
            if len(line) > spec["learnedMaxLineLength"]:
                findings.add(
                    path, seen["Learned"][0], "AGP010",
                    f"a Learned line is {len(line)} characters, the cap is {spec['learnedMaxLineLength']}",
                )
                break


# --- the rank-to-tools ceiling (agents#21) -----------------------------------------------------

TOOL_NAME = re.compile(r"^(\*|[A-Za-z][A-Za-z0-9_:.-]*)$")
SEPARATOR_CELL = re.compile(r"^:?-+:?$")


def table_cells(line):
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def parse_tool_cell(cell):
    """The backticked tool names in a table cell, or (None, why) when the cell is not only
    backticked names joined by commas or 'and'."""
    names = re.findall(r"`([^`]*)`", cell)
    leftover = re.sub(r"\band\b|[,\s]", "", re.sub(r"`[^`]*`", "", cell))
    if not names:
        return None, "lists no tools (write each tool name in backticks)"
    if leftover:
        return None, f"has text outside the backticks: '{leftover}'"
    for name in names:
        if not TOOL_NAME.match(name):
            return None, f"has '{name}', which is not a tool name (or * for every tool)"
    return names, None


def load_ceiling(path, display, ranks, findings):
    """Read the `## Rank ceiling` table of the units doctrine.

    One row per rank, lowest first; the second column holds the tools that rank adds to those of
    the rank below, each in backticks (`*` is every tool). Returns {rank: (tools in table order,
    every tool)} with the lower ranks already folded in, or None after adding AGP014 findings."""
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().split("\n")
    except (UnicodeDecodeError, OSError) as exc:
        findings.add(display, 0, "AGP014", f"cannot read the rank ceiling table: {exc}")
        return None
    start = next((i for i, line in enumerate(lines) if line.rstrip() == CEILING_HEADING), None)
    if start is None:
        findings.add(display, 1, "AGP014", f"no '{CEILING_HEADING}' section")
        return None
    rows = []
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if re.match(r"^#{1,2} ", line):
            break
        if line.lstrip().startswith("|"):
            rows.append((index + 1, table_cells(line)))
    rows = [row for row in rows[1:] if not all(SEPARATOR_CELL.match(cell) for cell in row[1])]
    if not rows:
        findings.add(display, start + 1, "AGP014", f"'{CEILING_HEADING}' holds no table of rank rows")
        return None

    before = len(findings)
    seen, added = [], {}
    for number, cells in rows:
        rank = cells[0].strip("`*_ ")
        if rank not in ranks:
            findings.add(display, number, "AGP014", f"'{rank}' is not a rank ({', '.join(ranks)})")
            continue
        if rank in seen:
            findings.add(display, number, "AGP014", f"rank '{rank}' is listed twice")
            continue
        seen.append(rank)
        names, why = parse_tool_cell(cells[1] if len(cells) > 1 else "")
        if why:
            findings.add(display, number, "AGP014", f"the {rank} row {why}")
        else:
            added[rank] = names
    missing = [rank for rank in ranks if rank not in seen]
    if missing:
        findings.add(display, start + 1, "AGP014", f"the table has no row for {', '.join(missing)}")
    elif seen != list(ranks):
        findings.add(display, start + 1, "AGP014", f"the rows must run {' > '.join(ranks)}: a rank inherits the rows above it")
    if len(findings) > before:
        return None

    ceiling, tools = {}, []
    for rank in ranks:
        tools = tools + [name for name in added[rank] if name not in tools]
        ceiling[rank] = (list(tools), "*" in tools)
    return ceiling


def tool_name(entry):
    """`Bash(git status:*)` is the tool Bash with a narrower pattern."""
    return entry.split("(", 1)[0].strip()


def check_ceiling(front, path, line_of, ceiling, ranks, findings):
    rank, tools = front.get("rank"), front.get("tools")
    if not isinstance(rank, str) or rank not in ceiling or not isinstance(tools, dict):
        return
    allow = tools.get("allow")
    if not isinstance(allow, list):
        return
    allowed, everything = ceiling[rank]
    if everything:
        return
    above = []
    for entry in allow:
        if not isinstance(entry, str) or tool_name(entry) in allowed or entry in above:
            continue
        above.append(entry)
    if not above:
        return
    parts = []
    for entry in above:
        first = next((r for r in ranks if tool_name(entry) in ceiling[r][0] or ceiling[r][1]), None)
        parts.append(f"{entry} (first allowed at {first})" if first else f"{entry} (in no rank's row)")
    findings.add(
        path, line_of("tools"), "AGP013",
        f"tools.allow lists above the {rank} ceiling: {', '.join(parts)}; a {rank} may list {', '.join(allowed)}",
    )


# --- authority changes against the base -------------------------------------------------------


def git(root, *args):
    return subprocess.run(["git", "-C", root, *args], capture_output=True)


def version_tuple(text):
    return tuple(int(part) for part in text.split("."))


def version_above(new, old):
    a, b = version_tuple(new), version_tuple(old)
    width = max(len(a), len(b))
    return a + (0,) * (width - len(a)) > b + (0,) * (width - len(b))


def base_profiles(root, base):
    listing = git(root, "ls-tree", "-r", "--name-only", base, "--", "profiles/")
    names = listing.stdout.decode().split("\n") if listing.returncode == 0 else []
    return sorted(n[len("profiles/"):-3] for n in names if n.startswith("profiles/") and n.endswith(".md") and "/" not in n[len("profiles/"):])


def check_authority(root, base, effective_by_stem, schema, findings):
    fields = schema["x-authority"]["fields"]
    in_base = base_profiles(root, base)
    for stem, (path, front) in sorted(effective_by_stem.items()):
        if not isinstance(front.get("version"), str) or not re.match(r"^[0-9]+(\.[0-9]+)*$", front["version"]):
            continue
        counterpart = stem if stem in in_base else None
        if counterpart is None and "-" in stem:
            role = stem.split("-", 1)[1]
            renamed = [b for b in in_base if b.split("-", 1)[-1] == role and b not in effective_by_stem]
            counterpart = renamed[0] if renamed else None
        if counterpart is None:
            continue
        shown = git(root, "show", f"{base}:profiles/{counterpart}.md")
        if shown.returncode != 0:
            continue
        scratch = Findings()
        old, _, _ = load_profile(shown.stdout.decode("utf-8", "replace"), schema, path, scratch)
        old_version = old.get("version") if old else None
        if old is None or not isinstance(old_version, str) or not re.match(r"^[0-9]+(\.[0-9]+)*$", old_version):
            print(f"check-profiles: note: {base}:profiles/{counterpart}.md does not parse; version-bump rule skipped for {stem}", file=sys.stderr)
            continue
        changed = [f for f in fields if old.get(f) != front.get(f)]
        if changed and not version_above(front["version"], old_version):
            findings.add(
                path, 1, "AGP011",
                f"authority field(s) {', '.join(changed)} changed from {base}:profiles/{counterpart}.md "
                f"but version {front['version']} is not above {old_version}",
            )


# --- driver -----------------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(prog="check-profiles.sh", description=__doc__.split("\n")[0])
    parser.add_argument("--root", default=REPO, help="repository holding profiles/ (default: this repository)")
    parser.add_argument("--units", default=None, help=f"file holding the '{CEILING_HEADING}' table (default {UNITS_DISPLAY} in this repository)")
    parser.add_argument("--base", default=None, help=f"ref the version-bump rule compares with (default {DEFAULT_BASE}; env PROFILE_BASE)")
    args = parser.parse_args()
    root = os.path.abspath(args.root)

    base = args.base or os.environ.get("PROFILE_BASE") or None
    explicit_base = base is not None
    base = base or DEFAULT_BASE

    with open(SCHEMA_PATH, encoding="utf-8") as handle:
        schema = json.load(handle)

    findings = Findings()
    ranks = schema["properties"]["rank"]["enum"]
    ceiling = load_ceiling(args.units or UNITS_PATH, args.units or UNITS_DISPLAY, ranks, findings)
    profile_dir = os.path.join(root, "profiles")
    names = sorted(n for n in os.listdir(profile_dir) if n.endswith(".md") and n != "README.md") if os.path.isdir(profile_dir) else []

    effective_by_stem = {}
    for name in names:
        rel = f"profiles/{name}"
        stem = name[:-3]
        try:
            with open(os.path.join(profile_dir, name), encoding="utf-8") as handle:
                text = handle.read()
        except (UnicodeDecodeError, OSError) as exc:
            findings.add(rel, 1, "AGP012", f"unreadable ({exc})")
            continue
        effective, body_rows, line_of = load_profile(text, schema, rel, findings)
        if effective is None:
            continue
        check_identity(effective, stem, rel, line_of, findings)
        check_body(body_rows, schema, rel, findings)
        if ceiling:
            check_ceiling(effective, rel, line_of, ceiling, ranks, findings)
        effective_by_stem[stem] = (rel, effective)

    resolvable = git(root, "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}").returncode == 0
    if resolvable:
        check_authority(root, base, effective_by_stem, schema, findings)
    elif explicit_base:
        findings.add("profiles", 0, "AGP011", f"base '{base}' not found: cannot compare authority fields")
    else:
        print(f"check-profiles: note: {base} not found; version-bump rule skipped", file=sys.stderr)

    if findings.items:
        for path, line, code, message in findings.items:
            where = f"{path}:{line}" if line else path
            print(f"{where}: {code}: {message}", file=sys.stderr)
        files = len({item[0] for item in findings.items})
        print(f"check-profiles: FAIL: {len(findings)} error(s) in {files} file(s)", file=sys.stderr)
        return 1
    print(f"check-profiles: {len(names)} profile(s) ok", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
