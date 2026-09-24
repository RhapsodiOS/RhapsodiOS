"""Judge a kernel serial log (COM2) for evidence the root filesystem
mounted on hd0a.

    python vm/check_rootmount.py KERNEL_LOG

setconf() prints "rootdev 300, howto ..." once it has chosen hd0a
(machdep/i386/swapgeneric.m); the failure lines are the kernel's own
(bsd/kern/init_main.c, subr_prf.c, swapgeneric.m) and check_label's
(driverkit-3/libDriver/label_subr.c).  A clean log is necessary, not
sufficient: pair it with a screenshot showing userland.
"""
import re
import sys

FAILURES = ("cannot mount root", "panic", "root device?",
            "Label in wrong location")


def problems(text):
    found = []
    if not re.search(r"^rootdev 300\b", text, re.MULTILINE):
        found.append("no 'rootdev 300' line")
    for marker in FAILURES:
        if marker in text:
            found.append("found %r" % marker)
    return found


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: %s KERNEL_LOG\n" % argv[0])
        return 2
    with open(argv[1], "rb") as f:
        text = f.read().decode("latin-1")
    found = problems(text)
    for line in found:
        print(line)
    if not found:
        print("root mount evidence OK")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
