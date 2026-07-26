"""Compare a driver's Objective-C selectors against a reference binary's.

The reference binary's __TEXT,__text symbol table names every method Apple
compiled, in "-[Class(Category) selector]" form. This script parses the same
names out of our sources and reports four disagreements:

  renames     our selector matches a reference name only after dropping one
              leading underscore, and the class has no correctly-named sibling
  duplicates  same, but a correctly-named sibling already exists, so the
              underscored definition is redundant and must be deleted rather
              than renamed
  missing     a reference selector with no counterpart in our sources
  extra       one of our selectors with no counterpart in the reference

Exit status is 0 when renames and duplicates are both empty. Missing and extra
are reported but do not affect the status: a reconstruction in progress is
expected to have both, whereas a rename or a duplicate is always a defect.
"""

import collections
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
    body = _outside_parens(signature).strip()
    if ":" in body:
        return "".join(part + ":" for part in re.findall(r"(\w*)\s*:", body))
    words = body.split()
    return words[0] if words else ""


def source_methods(source_dir):
    """Yield (full_name, class_name, selector, path, line) per definition."""
    for path in sorted(Path(source_dir).glob("*.m")):
        lines = path.read_text(errors="replace").splitlines()
        class_name = category = None
        index = 0
        while index < len(lines):
            line = lines[index]
            opening = re.match(r"^@implementation\s+(\w+)\s*(?:\(\s*(\w+)\s*\))?", line)
            if opening:
                class_name, category = opening.group(1), opening.group(2)
                index += 1
                continue
            if line.startswith("@end"):
                class_name = category = None
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
    selectors_by_class = collections.defaultdict(set)
    for _, class_name, selector, _, _ in methods:
        selectors_by_class[class_name].add(selector)

    renames, duplicates, ours = [], [], set()
    for full, class_name, selector, filename, line in methods:
        ours.add(full)
        if not selector.startswith("_"):
            continue
        if full.replace(" _", " ", 1) not in reference:
            continue
        record = (full, filename, line)
        if selector[1:] in selectors_by_class[class_name]:
            duplicates.append(record)
        else:
            renames.append(record)

    normalised = {full.replace(" _", " ", 1) for full in ours}
    missing = sorted(reference - normalised - ours)
    extra = sorted(name for name in ours if name not in reference
                   and name.replace(" _", " ", 1) not in reference)
    return renames, duplicates, missing, extra


def main(argv):
    if len(argv) != 3:
        print("usage: selector_check.py REFERENCE_BINARY SOURCE_DIR", file=sys.stderr)
        return 2

    reference = reference_selectors(Path(argv[1]))
    methods = list(source_methods(argv[2]))
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
