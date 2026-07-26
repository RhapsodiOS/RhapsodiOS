"""Build a source map from a reference analysis and a source tree.

Address-to-name comes from the Mach-O symbol table, which these legacy
driver binaries retain in full. Name-to-source-line comes from scanning
Objective-C implementations and C function definitions.
"""

from pathlib import Path
import re


_IMPLEMENTATION = re.compile(r"^@implementation\s+(\w+)(?:\s*\(\s*(\w+)\s*\))?")
_END = re.compile(r"^@end")
_METHOD = re.compile(r"^\s*([-+])(?:\s+|(?=\())(.*)$")
"""A C definition at column zero.

Two shapes occur in this tree.  The common one puts the return type and the
name on one line -- "static int foo(".  The other is the K&R style NeXT and
BSD sources favour, where the type sits on its own line and the name starts
at column zero:

    static void
    ahaTimeout(void *arg)
    {

The first alternative below matches the one-line form; it requires at least
one character before the name so that a bare "name(" cannot satisfy it by
consuming nothing.  The second matches the wrapped form.  Keeping them
separate rather than making the leading run optional matters: an optional
run would also match a call statement at column zero, which is a phantom
definition.  The caller only reaches this on lines that are not indented and
do not end in a semicolon, which is what keeps ordinary calls out.
"""
_C_DEFINITION = re.compile(
    r"^[A-Za-z_][A-Za-z_0-9 \t*]*?[ \t*]\b(\w+)\s*\("
    r"|^(\w+)\s*\("
)

_METHOD_DECLARATION_LIMIT = 20


def defined_symbols(macho_document):
    """Map each address to the sorted unique names defined there.

    Symbols with no section are undefined imports and are skipped.
    """
    index = {}
    for symbol in macho_document["symbols"]:
        if symbol["section"] is None:
            continue
        index.setdefault(symbol["address"], set()).add(symbol["name"])
    return {address: sorted(names) for address, names in index.items()}


def _selector(declaration):
    """Reduce an Objective-C method declaration to its bare selector.

    Keywords after the first may be empty: `initFromDeviceDescription::::` is a
    real selector in the shipped i386 drivers. Once the parenthesised types are
    gone, each colon is followed by its argument name and then, optionally, the
    next keyword, so matching `(\\w+)\\s*:` would capture the argument name as a
    keyword and turn `foo::::` into `foo:a:b:c:`. Walk the segments instead.
    """
    text = re.sub(r"\([^()]*\)", " ", declaration)
    text = text.split("{")[0]
    if ":" in text:
        segments = text.split(":")
        selector = segments[0].split()[-1] + ":" if segments[0].split() else ":"
        for segment in segments[1:-1]:
            words = segment.split()
            selector += (words[1] if len(words) > 1 else "") + ":"
        return selector
    words = re.findall(r"\w+", text)
    return words[0] if words else None


def _relative_posix(repo_root, path):
    return path.resolve().relative_to(repo_root.resolve()).as_posix()


def source_sites(repo_root, source_dir):
    """Map symbol names to the source locations that define them."""
    sites = {}
    paths = sorted(Path(source_dir).glob("*.m")) + sorted(Path(source_dir).glob("*.c"))
    for path in paths:
        relative = _relative_posix(Path(repo_root), path)
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        total = len(lines)
        current_class = None
        index = 0
        while index < total:
            number = index + 1
            line = lines[index]

            implementation = _IMPLEMENTATION.match(line)
            if implementation:
                name, category = implementation.group(1), implementation.group(2)
                current_class = f"{name}({category})" if category else name
                index += 1
                continue
            if _END.match(line):
                current_class = None
                index += 1
                continue

            method = _METHOD.match(line) if current_class is not None else None
            if method:
                declaration = [line]
                found_brace = "{" in line
                found_semicolon = not found_brace and line.rstrip().endswith(";")
                end = min(total, index + _METHOD_DECLARATION_LIMIT)
                scan = index
                while not found_brace and not found_semicolon and scan + 1 < end:
                    candidate = lines[scan + 1]
                    if (
                        _END.match(candidate)
                        or _IMPLEMENTATION.match(candidate)
                        or _METHOD.match(candidate)
                    ):
                        # A structural boundary, or the start of another
                        # method declaration, before any brace/semicolon
                        # means this was never a real declaration; stop
                        # without consuming the line so the outer loop can
                        # process it on its own (updating current_class,
                        # or scanning it as its own declaration).
                        break
                    scan += 1
                    declaration.append(candidate)
                    if "{" in candidate:
                        found_brace = True
                    elif candidate.rstrip().endswith(";"):
                        found_semicolon = True

                if found_brace and not found_semicolon:
                    selector = _selector(" ".join(declaration))
                    if selector:
                        key = f"{method.group(1)}[{current_class} {selector}]"
                        sites.setdefault(key, []).append((relative, number))

                index = scan + 1
                continue

            if line.rstrip().endswith(";") or line.startswith((" ", "\t", "#", "}")):
                index += 1
                continue
            definition = _C_DEFINITION.match(line)
            if definition:
                declaration = [line]
                found_brace = "{" in line
                found_semicolon = not found_brace and line.rstrip().endswith(";")
                # A closed parameter list with no ";" may be a K&R definition,
                # whose indented parameter declarations each end in ";". Those
                # must not be read as a prototype's terminator.
                kandr = line.rstrip().endswith(")")
                end = min(total, index + _METHOD_DECLARATION_LIMIT)
                scan = index
                while not found_brace and not found_semicolon and scan + 1 < end:
                    candidate = lines[scan + 1]
                    if (
                        _IMPLEMENTATION.match(candidate)
                        or _END.match(candidate)
                        or _C_DEFINITION.match(candidate)
                        or (current_class is not None and _METHOD.match(candidate))
                    ):
                        # A structural boundary, the start of another
                        # top-level declaration, or (inside an
                        # @implementation) the start of a method, before any
                        # brace/semicolon means this prototype/definition
                        # never resolved; stop without consuming the line so
                        # the outer loop can process it on its own.
                        break
                    scan += 1
                    declaration.append(candidate)
                    if "{" in candidate:
                        found_brace = True
                    elif candidate.rstrip().endswith(";") and not (
                        kandr and candidate[:1].isspace()
                    ):
                        found_semicolon = True

                if found_brace and not found_semicolon:
                    # The name comes from whichever _C_DEFINITION alternative
                    # matched: group 1 for "static int foo(", group 2 for the
                    # wrapped form where "foo(" starts the line.
                    name = definition.group(1) or definition.group(2)
                    sites.setdefault("_" + name, []).append((relative, number))

                index = scan
            index += 1
    return sites


def scope_analysis(analysis, addresses):
    """Return a copy of an analysis keeping only the named functions.

    The input identity is preserved, so a source map built against the result
    still binds to the real binary by SHA-256 while covering a declared subset
    of a large image.
    """
    scoped = dict(analysis)
    scoped["functions"] = [
        function for function in analysis["functions"]
        if function["address"] in addresses
    ]
    return scoped


def _overlapping_addresses(functions):
    """Return the addresses of every function whose range overlaps another's.

    Ranges are compared as [address, address + size). Overlap is transitive
    in effect even though this only checks pairs directly: in a chain where A
    overlaps B and B overlaps C, both pairwise checks fire and all three
    addresses end up in the result.
    """
    ordered = sorted(functions, key=lambda function: function["address"])
    overlapping = set()
    for index, function in enumerate(ordered):
        end = function["address"] + function["size"]
        for other in ordered[index + 1:]:
            if other["address"] >= end:
                break
            overlapping.add(function["address"])
            overlapping.add(other["address"])
    return overlapping


def build_source_map(
    reference_analysis, macho_document, sites, *, disputed=None, extra_names=None
):
    """Partition every reference function into exactly one source-map bucket."""
    disputed = set() if disputed is None else disputed
    function_addresses = {
        function["address"] for function in reference_analysis["functions"]
    }
    unmatched_disputed = sorted(disputed - function_addresses)
    if unmatched_disputed:
        raise ValueError(
            "disputed addresses do not match any analysis function: "
            f"{unmatched_disputed}"
        )
    symbols = defined_symbols(macho_document)
    if extra_names:
        merged = {address: set(names) for address, names in symbols.items()}
        for address, names in extra_names.items():
            merged.setdefault(address, set()).update(names)
        symbols = {address: sorted(names) for address, names in merged.items()}
    overlapping = _overlapping_addresses(reference_analysis["functions"])
    mapped, unmapped, duplicates, boundary = [], [], [], []

    for function in reference_analysis["functions"]:
        address = function["address"]
        names = sorted(function["names"])
        if not names:
            raise ValueError(
                f"analysis function at address {address} has no names; "
                "source-map-v1 requires at least one and the semantic validator "
                "requires an exact match against the analysis"
            )
        entry = {
            "address": address,
            "size": function["size"],
            "reference_names": names,
        }

        lookup = set(names) | set(symbols.get(address, []))
        candidates = sorted({site for name in lookup for site in sites.get(name, [])})

        reasons = []
        if address in disputed:
            reasons.append("analyzers disagree on function extent")
        if address in overlapping:
            reasons.append(
                "function range overlaps another; symbol may be an interior label"
            )

        if reasons:
            boundary.append({**entry, "reasons": sorted(set(reasons))})
        elif len(candidates) == 1:
            path, line = candidates[0]
            mapped.append({**entry, "source_path": path, "source_line": line})
        elif candidates:
            duplicates.append(
                {
                    **entry,
                    "candidates": [
                        {"source_path": path, "source_line": line}
                        for path, line in candidates
                    ],
                    "reasons": ["symbol name resolves to multiple definitions"],
                }
            )
        else:
            unmapped.append(entry)

    return {
        "schema_version": "source-map-v1",
        "reference_sha256": reference_analysis["input"]["sha256"].upper(),
        "mapped": _canonical(mapped),
        "unmapped": _canonical(unmapped),
        "duplicate_candidates": _canonical(duplicates),
        "boundary_disputed": _canonical(boundary),
    }


def _canonical(entries):
    """Sort entries the way the semantic validator requires."""
    return sorted(
        entries, key=lambda entry: (entry["address"], tuple(entry["reference_names"]))
    )
