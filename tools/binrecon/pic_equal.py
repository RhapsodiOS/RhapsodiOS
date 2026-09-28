"""Compare functions between two IDA analyses, ignoring layout only.

binrecon's masked_equal does not normalize position-independent code: an
i386 `lea eax, (aFoo - 3D55h)[ebx]` or a ppc `addis r3, r31, (aFoo -
loc_3038)@ha` carries the PIC base of wherever the function landed, so two
functions with the same instructions and the same symbolic targets still
compare different when the image layout differs.

Two instructions are equal here when their bytes are identical, or when
their mnemonic and operand text agree after:
- dropping the PIC-base term (`- 3D55h`, `- loc_3038`, `- offset loc_5160`);
- rewriting every `loc_XXXX` label to its offset from the function start;
- dropping IDA's `dword ptr ` / `byte ptr ` / `word ptr ` size annotations.
Symbolic targets (`_printf`, `aUsageSOperatio`, `_verbose`) must still
agree, so a function that calls or loads something else stays different.
Data IDA names only by address (`off_C014`) and raw PIC displacements
(`[ecx+287Ah]`) may differ, but each reference value must pair with one
rebuilt value throughout the function, and vice versa.

Usage: pic_equal.py REFERENCE_ANALYSIS REBUILT_ANALYSIS [NAME ...]
Prints `pic_equal <name>` or `different <name>: <first differing pair>`
per common function (or per NAME), and exits 0.
"""

import json
import re
import sys

_PICBASE = re.compile(r"\s*-\s*(?:offset\s+)?(?:loc_[0-9A-F]+|[0-9A-F]+h)\)")
_LOC = re.compile(r"\bloc_([0-9A-F]+)\b")
_SIZE = re.compile(r"\b(?:byte|word|dword|qword) ptr ")
# IDA names for data it only knows by address (including jump tables, and
# the `paXxx` pointer names it gives some selector references on one side
# and `off_XXXX` on the other), and raw PIC displacements (at least three
# hex digits inside brackets).
_ADDRESS = re.compile(r"\b(?:off|dword|word|byte|unk|stru|qword|asc|jpt)_[0-9A-F]+\b"
                      r"|\bpa[A-Z]\w*|[+-][0-9A-F]{3,}h(?=\])|- 0x[0-9A-F]{3,}(?=\))")


def _normalize(text, start):
    text = _PICBASE.sub(")", text)
    text = _LOC.sub(lambda m: "L+%x" % (int(m.group(1), 16) - start), text)
    return _SIZE.sub("", text)


def _stream(function):
    start = function["address"]
    return [(i["bytes"], "%s %s" % (i["mnemonic"], _normalize(i["operands"], start)))
            for i in function["instructions"]]


def _by_name(path):
    out = {}
    for function in json.load(open(path, encoding="utf-8"))["functions"]:
        for name in function["names"]:
            out.setdefault(name, function)
    return out


def _pair(ref_text, new_text, forward, backward):
    """Equal when the texts differ only in address tokens paired one-to-one."""
    ref_tokens, new_tokens = _ADDRESS.findall(ref_text), _ADDRESS.findall(new_text)
    if len(ref_tokens) != len(new_tokens) or not ref_tokens:
        return False
    if _ADDRESS.sub("@", ref_text) != _ADDRESS.sub("@", new_text):
        return False
    for r, n in zip(ref_tokens, new_tokens):
        if forward.setdefault(r, n) != n or backward.setdefault(n, r) != r:
            return False
    return True


def compare(reference, rebuilt):
    a, b = _stream(reference), _stream(rebuilt)
    forward, backward = {}, {}
    for index in range(max(len(a), len(b))):
        if index >= len(a) or index >= len(b):
            return "length %d vs %d" % (len(a), len(b))
        if a[index][0] == b[index][0] or a[index][1] == b[index][1]:
            continue
        if not _pair(a[index][1], b[index][1], forward, backward):
            return "#%d: %r | %r" % (index, a[index][1], b[index][1])
    return None


def main(argv):
    if len(argv) < 3:
        print(__doc__.split("\n\n")[-2], file=sys.stderr)
        return 2
    ref, new = _by_name(argv[1]), _by_name(argv[2])
    names = argv[3:] or sorted(set(ref) & set(new))
    for name in names:
        if name not in ref or name not in new:
            print("missing %s" % name)
            continue
        difference = compare(ref[name], new[name])
        print("pic_equal %s" % name if difference is None else "different %s: %s" % (name, difference))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
