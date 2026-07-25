"""Build a source map from a reference analysis and a source tree.

Address-to-name comes from the Mach-O symbol table, which these legacy
driver binaries retain in full. Name-to-source-line comes from scanning
Objective-C implementations and C function definitions.
"""

from pathlib import Path
import re


_IMPLEMENTATION = re.compile(r"^@implementation\s+(\w+)(?:\s*\(\s*(\w+)\s*\))?")
_END = re.compile(r"^@end")
_METHOD = re.compile(r"^\s*([-+])\s+(.*)$")
_C_DEFINITION = re.compile(r"^[A-Za-z_][A-Za-z_0-9 \t*]*?\b(\w+)\s*\(")

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
    """Reduce an Objective-C method declaration to its bare selector."""
    text = re.sub(r"\([^()]*\)", " ", declaration)
    text = text.split("{")[0]
    keywords = re.findall(r"(\w+)\s*:", text)
    if keywords:
        return "".join(keyword + ":" for keyword in keywords)
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

            if current_class is not None:
                method = _METHOD.match(line)
                if method:
                    declaration = [line]
                    found_brace = "{" in line
                    found_semicolon = not found_brace and line.rstrip().endswith(";")
                    end = min(total, index + _METHOD_DECLARATION_LIMIT)
                    scan = index
                    while not found_brace and not found_semicolon and scan + 1 < end:
                        scan += 1
                        next_line = lines[scan]
                        declaration.append(next_line)
                        if "{" in next_line:
                            found_brace = True
                        elif next_line.rstrip().endswith(";"):
                            found_semicolon = True

                    if found_brace and not found_semicolon:
                        selector = _selector(" ".join(declaration))
                        if selector:
                            key = f"{method.group(1)}[{current_class} {selector}]"
                            sites.setdefault(key, []).append((relative, number))

                    index = scan
                index += 1
                continue

            if line.rstrip().endswith(";") or line.startswith((" ", "\t", "#", "}")):
                index += 1
                continue
            definition = _C_DEFINITION.match(line)
            if definition:
                sites.setdefault("_" + definition.group(1), []).append((relative, number))
            index += 1
    return sites
