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
rebuilt value throughout the function, and vice versa, and the pairs must
keep the reference's order within each address space (PIC-relative and
absolute), so two targets swapped between call sites stay different.
IDA's `paXxx` pointer names carry no address: they are paired but cannot
be ordered, so a selector reference named that way on one side is checked
only for consistency.

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
# Raw displacements count only on a general register, never on the frame
# (`[ebp-808h]` is a stack slot, not an address).
_ADDRESS = re.compile(r"\b(?:off|dword|word|byte|unk|stru|qword|asc|jpt)_[0-9A-F]+\b"
                      r"|\bpa[A-Z]\w*"
                      r"|(?<=\[e[abcd]x)[+-][0-9A-F]{3,}h(?=\])|(?<=\[e[sd]i)[+-][0-9A-F]{3,}h(?=\])"
                      r"|- 0x[0-9A-F]{3,}(?=\))"
                      r"|(?<=^add e[a-d]x, )[0-9A-F]{4,}h$|(?<=^add e[sd]i, )[0-9A-F]{4,}h$")
_NAMED = re.compile(r"^[a-z]+_([0-9A-F]+)$")


def _value(token):
    """(space, number) for a token that encodes an address, else None.

    `rel` values are PIC-base relative (raw displacements and add
    immediates); `abs` values are absolute addresses.  IDA's `paXxx` names
    carry no address and are only paired, not ordered."""
    m = _NAMED.match(token)
    if m:
        return ("abs", int(m.group(1), 16))
    if token.startswith("- 0x"):
        return ("abs", int(token[4:], 16))
    if token.endswith("h"):
        sign = -1 if token.startswith("-") else 1
        return ("rel", sign * int(token.lstrip("+-")[:-1], 16))
    return None


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


def _order_kept(forward):
    """Layout moves sections, not the order of targets within one space."""
    spaces = {}
    for r, n in forward.items():
        rv, nv = _value(r), _value(n)
        if rv is None or nv is None:
            continue
        if rv[0] != nv[0]:
            return "address kinds differ: %s | %s" % (r, n)
        spaces.setdefault(rv[0], []).append((rv[1], nv[1], r, n))
    for pairs in spaces.values():
        pairs.sort()
        for (r1v, n1, r1, t1), (r2v, n2, r2, t2) in zip(pairs, pairs[1:]):
            # One address can appear in two textual forms (`dword_6F38` and
            # `- 0x6F38`): equal reference values need equal rebuilt values.
            if (r2v == r1v) != (n2 == n1) or (r2v != r1v and n2 < n1):
                return "target order differs: %s->%s, %s->%s" % (r1, t1, r2, t2)
    return None


def compare(reference, rebuilt):
    a, b = _stream(reference), _stream(rebuilt)
    forward, backward = {}, {}
    for index in range(max(len(a), len(b))):
        if index >= len(a) or index >= len(b):
            return "length %d vs %d" % (len(a), len(b))
        if a[index][1] == b[index][1]:
            # Identical text still pins its address tokens to themselves.
            for token in _ADDRESS.findall(a[index][1]):
                if forward.setdefault(token, token) != token or backward.setdefault(token, token) != token:
                    return "#%d: %r pairs inconsistently" % (index, a[index][1])
            continue
        if a[index][0] == b[index][0]:
            continue
        if not _pair(a[index][1], b[index][1], forward, backward):
            return "#%d: %r | %r" % (index, a[index][1], b[index][1])
    return _order_kept(forward)


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
