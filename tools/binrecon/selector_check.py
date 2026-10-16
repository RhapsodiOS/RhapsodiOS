"""Compare a driver's Objective-C selectors against a reference binary's.

The reference binary's __TEXT,__text symbol table names every method Apple
compiled, in "-[Class(Category) selector]" form. This script parses the same
names out of our sources and reports four disagreements:

  renames     our selector matches a reference name only after dropping one
              leading underscore, and the class has no correctly-named sibling
  duplicates  either an exact method name is defined more than once, or a
              correctly-named sibling already exists for an underscored
              definition, making it redundant rather than a rename
  missing     a reference selector with no counterpart in our sources
  extra       one of our selectors with no counterpart in the reference

Exit status is 0 when renames and duplicates are both empty. Missing and extra
are reported but do not affect the status: a reconstruction in progress is
expected to have both, whereas a rename or a duplicate is always a defect.
"""

import collections
import ast
import re
import sys
from pathlib import Path

from binrecon.macho import read_macho

TEXT_SECTION = "__TEXT,__text"


def reference_selectors(path):
    document = read_macho(path)
    return {
        symbol["name"]
        for symbol in document["symbols"]
        if symbol["section"] == TEXT_SECTION
        and symbol["name"].startswith(("-[", "+["))
    }


def _outside_parens(text):
    """Drop parenthesised spans, so argument types don't look like keywords."""
    kept = []
    depth = 0
    for character in text:
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
        elif depth == 0:
            kept.append(character)
    return "".join(kept)


def _selector(signature):
    """Extract the selector from a method signature, types and argument names removed.

    Apple declares some methods with empty keywords — `initFromDeviceDescription::::`
    is a real selector in the reference binary. Once the parenthesised types are
    gone, each colon is followed by its argument name and then, optionally, the
    next keyword. Matching `(\\w*)\\s*:` would capture the argument name as the
    keyword and silently turn `foo:::` into `foo:a:b:`, so walk the segments
    instead: in every segment after the first, the argument name is the leading
    word and the keyword is whatever word follows it, or nothing.
    """
    body = _outside_parens(signature).strip()
    if ":" not in body:
        words = body.split()
        return words[0] if words else ""

    segments = body.split(":")
    selector = segments[0].strip() + ":"
    for segment in segments[1:-1]:
        words = segment.split()
        selector += (words[1] if len(words) > 1 else "") + ":"
    return selector


def _architecture_condition(directive, architecture):
    """Evaluate the target-architecture conditions used by Foundation sources.

    Unknown feature macros return None so both branches remain visible to the
    source inventory instead of being guessed away.
    """
    directive = directive.strip()
    match = re.match(r"#\s*(if|elif|ifdef|ifndef)\s+(.*)$", directive)
    if not match:
        return None
    kind, expression = match.groups()
    expression = expression.split("/*", 1)[0].split("//", 1)[0].strip()

    def macro_value(name):
        if name in ("__ppc__", "__POWERPC__"):
            return architecture == "ppc"
        if name == "__i386__":
            return architecture == "i386"
        if name == "__BIG_ENDIAN__":
            return architecture == "ppc"
        return None

    if kind in ("ifdef", "ifndef"):
        value = macro_value(expression)
        if value is None:
            return None
        return value if kind == "ifdef" else not value

    def replace_defined(match):
        name = match.group(1) or match.group(2)
        value = macro_value(name)
        return "True" if value is True else "False" if value is False else "UNKNOWN"

    expression = re.sub(
        r"\bdefined\s*(?:\(\s*(\w+)\s*\)|(\w+))",
        replace_defined,
        expression,
    )
    if "UNKNOWN" in expression or re.search(r"[^\s()!&|A-Za-z]", expression):
        return None
    if re.search(r"\b(?!(?:True|False|and|or|not)\b)[A-Za-z_]\w*\b", expression):
        return None
    expression = expression.replace("&&", " and ").replace("||", " or ")
    expression = re.sub(r"!(?!=)", " not ", expression).strip()
    try:
        node = ast.parse(expression, mode="eval").body
    except SyntaxError:
        return None

    def evaluate(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, bool):
            return node.value
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            return not evaluate(node.operand)
        if isinstance(node, ast.BoolOp) and isinstance(node.op, ast.And):
            return all(evaluate(value) for value in node.values)
        if isinstance(node, ast.BoolOp) and isinstance(node.op, ast.Or):
            return any(evaluate(value) for value in node.values)
        raise ValueError("unsupported preprocessor expression")

    try:
        return evaluate(node)
    except ValueError:
        return None


def source_methods(source_dir, architecture=None):
    """Yield (full_name, class_name, selector, path, line) per definition."""
    for path in sorted(Path(source_dir).glob("*.m")):
        lines = path.read_text(errors="replace").splitlines()
        class_name = category = None
        active = True
        conditionals = []
        index = 0
        while index < len(lines):
            line = lines[index]
            directive = re.match(r"^\s*#\s*(if|ifdef|ifndef|elif|else|endif)\b", line)
            if directive and architecture is not None:
                kind = directive.group(1)
                if kind in ("if", "ifdef", "ifndef"):
                    condition = _architecture_condition(line, architecture)
                    conditionals.append((active, condition))
                    active = active and condition is not False
                elif kind == "elif" and conditionals:
                    parent, previous = conditionals[-1]
                    condition = _architecture_condition(line, architecture)
                    active = parent and previous is not True and condition is not False
                    if previous is False:
                        conditionals[-1] = (parent, condition)
                    elif previous is None and condition is not False:
                        conditionals[-1] = (parent, None)
                    else:
                        conditionals[-1] = (parent, previous or condition)
                elif kind == "else" and conditionals:
                    parent, previous = conditionals[-1]
                    active = parent and previous is not True
                    conditionals[-1] = (parent, True if previous is False else None)
                elif kind == "endif" and conditionals:
                    active, _ = conditionals.pop()
                index += 1
                continue
            if not active:
                index += 1
                continue
            opening = re.match(r"^@implementation\s+(\w+)\s*(?:\(\s*(\w+)\s*\))?", line)
            if opening:
                class_name, category = opening.group(1), opening.group(2)
                index += 1
                continue
            if line.startswith("@end"):
                class_name = category = None
                index += 1
                continue
            generated = re.match(
                r"^NS_NUMBER_VALUE_METHOD\(\s*(\w+)\s*,", line
            )
            if class_name == "NSNumber" and generated:
                selector = generated.group(1)
                scope = "%s(%s)" % (class_name, category) if category else class_name
                yield ("-[%s %s]" % (scope, selector),
                       class_name, selector, path.name, index + 1)
                index += 1
                continue
            if class_name and re.match(r"^[-+]\s*[\(\w]", line):
                start = index
                signature = line
                # A signature may wrap across lines; it ends at the body brace.
                while "{" not in signature and index + 1 < len(lines) and len(signature) < 600:
                    index += 1
                    signature += " " + lines[index]
                head = signature.split("{")[0].strip()
                sign, remainder = head[0], head[1:]
                selector = _selector(remainder)
                scope = "%s(%s)" % (class_name, category) if category else class_name
                yield ("%s[%s %s]" % (sign, scope, selector),
                       class_name, selector, path.name, start + 1)
            index += 1


def classify(reference, methods):
    methods = list(methods)
    selectors_by_class = collections.defaultdict(set)
    full_counts = collections.Counter(full for full, _, _, _, _ in methods)
    for _, class_name, selector, _, _ in methods:
        selectors_by_class[class_name].add(selector)

    renames, duplicates, ours = [], [], set()
    for full, class_name, selector, filename, line in methods:
        ours.add(full)
        record = (full, filename, line)
        if full_counts[full] > 1:
            duplicates.append(record)
        if not selector.startswith("_"):
            continue
        if full in reference or full.replace(" _", " ", 1) not in reference:
            continue
        if selector[1:] in selectors_by_class[class_name]:
            duplicates.append(record)
        else:
            renames.append(record)

    duplicates = list(dict.fromkeys(duplicates))

    normalised = {full.replace(" _", " ", 1) for full in ours}
    missing = sorted(reference - normalised - ours)
    extra = sorted(name for name in ours if name not in reference
                   and name.replace(" _", " ", 1) not in reference)
    return renames, duplicates, missing, extra


def main(argv):
    if len(argv) != 3:
        print("usage: selector_check.py REFERENCE_BINARY SOURCE_DIR", file=sys.stderr)
        return 2

    reference_path = Path(argv[1])
    document = read_macho(reference_path)
    reference = {
        symbol["name"]
        for symbol in document["symbols"]
        if symbol["section"] == TEXT_SECTION
        and symbol["name"].startswith(("-[", "+["))
    }
    methods = list(source_methods(argv[2], document["input"]["architecture"]))
    renames, duplicates, missing, extra = classify(reference, methods)

    print("reference selectors: %d" % len(reference))
    print("our definitions:     %d" % len(methods))
    for label, records in (("renames", renames), ("duplicates", duplicates)):
        print("\n%s (%d):" % (label, len(records)))
        for full, filename, line in sorted(records, key=lambda r: (r[1], r[2])):
            print("    %-58s %s:%d" % (full, filename, line))
    for label, names in (("missing", missing), ("extra", extra)):
        print("\n%s (%d):" % (label, len(names)))
        for name in names:
            print("    %s" % name)

    return 0 if not renames and not duplicates else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
