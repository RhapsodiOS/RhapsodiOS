"""Compare the __TEXT sections of two sets of Mach-O object files.

Proves a change left the ppc kernel's code untouched: every section whose
segment is __TEXT (code, literal strings, constants) must match byte for
byte, relocations included.

    python macho_text.py BEFORE_DIR AFTER_DIR [--new NAME.o ...]

Compares every .o in BEFORE_DIR with the same name in AFTER_DIR.  Objects
only in AFTER_DIR are errors unless named with --new.  Exits 0 when all match.
"""

import os
import struct
import sys

LC_SEGMENT = 1
S_ZEROFILL = 1


def text_sections(path):
    """{section name: (bytes, relocation bytes)} for every __TEXT section."""
    with open(path, "rb") as f:
        b = f.read()
    magic = b[:4]
    if magic == b"\xfe\xed\xfa\xce":
        e = ">"
    elif magic == b"\xce\xfa\xed\xfe":
        e = "<"
    else:
        raise ValueError("%s is not a 32-bit Mach-O file" % path)
    ncmds = struct.unpack_from(e + "I", b, 16)[0]
    off = 28
    out = {}
    for _ in range(ncmds):
        cmd, size = struct.unpack_from(e + "II", b, off)
        if cmd == LC_SEGMENT:
            nsects = struct.unpack_from(e + "I", b, off + 48)[0]
            s = off + 56
            for _ in range(nsects):
                sect = b[s:s + 16].split(b"\0")[0].decode("ascii")
                seg = b[s + 16:s + 32].split(b"\0")[0].decode("ascii")
                addr, sz, fileoff, align, reloff, nreloc, flags = \
                    struct.unpack_from(e + "7I", b, s + 32)
                if seg == "__TEXT":
                    data = b"" if (flags & 0xFF) == S_ZEROFILL else b[fileoff:fileoff + sz]
                    out[sect] = (data, b[reloff:reloff + 8 * nreloc])
                s += 68
        off += size
    return out


def compare(before, after):
    """Differences between two objects' __TEXT sections, as strings."""
    a, b = text_sections(before), text_sections(after)
    out = []
    for name in sorted(set(a) | set(b)):
        if name not in a or name not in b:
            out.append("section %s exists in only one object" % name)
        elif a[name][0] != b[name][0]:
            out.append("section %s bytes differ" % name)
        elif a[name][1] != b[name][1]:
            out.append("section %s relocations differ" % name)
    return out


def compare_dirs(before_dir, after_dir, new=()):
    problems = []
    names_a = set(n for n in os.listdir(before_dir) if n.endswith(".o"))
    names_b = set(n for n in os.listdir(after_dir) if n.endswith(".o"))
    for n in sorted(names_a - names_b):
        problems.append("%s: missing after the change" % n)
    for n in sorted(names_b - names_a - set(new)):
        problems.append("%s: new object not expected" % n)
    for n in sorted(names_a & names_b):
        for d in compare(os.path.join(before_dir, n), os.path.join(after_dir, n)):
            problems.append("%s: %s" % (n, d))
    return problems


def main(argv):
    args = argv[1:]
    new = []
    if "--new" in args:
        i = args.index("--new")
        new = args[i + 1:]
        args = args[:i]
    if len(args) != 2:
        print(__doc__)
        return 2
    problems = compare_dirs(args[0], args[1], new)
    for p in problems:
        print(p)
    print("identical" if not problems else "%d differences" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
