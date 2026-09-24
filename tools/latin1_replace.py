"""Replace text in a source file without disturbing any of its other bytes.

Legacy Apple and NeXT sources hold Mac-Roman bytes that are not valid UTF-8,
and editors that decode files as UTF-8 silently rewrite them.  This tool reads
and writes the file as latin-1, so every byte outside the replaced text comes
through unchanged.

    python tools/latin1_replace.py FILE [--count N] < PATCH

PATCH is the old text, a line reading exactly =====, then the new text.
Whitespace in the old text matches any run of whitespace in the file, so
indentation need not be copied exactly.  The new text is written with the
file's own line endings.  Nothing is written unless the old text matches
exactly N times (default 1); every match is replaced.
"""

import re
import sys

SEPARATOR = "====="


def split_patch(text):
    lines = text.replace("\r\n", "\n").split("\n")
    if SEPARATOR not in lines:
        raise ValueError("the patch has no ===== line")
    i = lines.index(SEPARATOR)
    old = "\n".join(lines[:i])
    new = "\n".join(lines[i + 1:])
    if new.endswith("\n"):
        new = new[:-1]
    if not old.split():
        raise ValueError("the old text is empty")
    return old, new


def pattern(old):
    """A regex matching `old` with any whitespace between its tokens."""
    tokens = old.split()
    out = re.escape(tokens[0])
    for prev, tok in zip(tokens, tokens[1:]):
        gap = r"\s+" if (prev[-1].isalnum() or prev[-1] == "_") and \
            (tok[0].isalnum() or tok[0] == "_") else r"\s*"
        out += gap + re.escape(tok)
    return re.compile(out)


def replace(text, old, new, count=1):
    rx = pattern(old)
    found = len(rx.findall(text))
    if found != count:
        raise ValueError("old text matches %d times, expected %d" % (found, count))
    if "\r\n" in text:
        new = new.replace("\n", "\r\n")
    return rx.sub(lambda m: new, text)


def main(argv):
    args = argv[1:]
    count = 1
    if "--count" in args:
        i = args.index("--count")
        count = int(args[i + 1])
        del args[i:i + 2]
    if len(args) != 1:
        print(__doc__)
        return 2
    path = args[0]
    with open(path, encoding="latin-1", newline="") as f:
        text = f.read()
    try:
        old, new = split_patch(sys.stdin.read())
        result = replace(text, old, new, count)
    except ValueError as e:
        print("%s: %s" % (path, e), file=sys.stderr)
        return 1
    with open(path, "w", encoding="latin-1", newline="") as f:
        f.write(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
