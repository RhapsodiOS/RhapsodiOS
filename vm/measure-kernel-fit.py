"""Report whether the rebuilt kernel's rcz stream fits the installation floppy.

Prints the ceiling derived from the floppy's own superblock, the measured
compressed size, and the margin.  Exit 0 if it fits, 1 if it does not.
"""

import os
import sys

import rcz
import rhap_image

HERE = os.path.dirname(os.path.abspath(__file__))
FLOPPY = os.path.join(HERE, "install", "rhapsody_dr2_x86_InstallationFloppy.img")
KERNEL = os.path.join(HERE, "..", "out", "i386", "mach_kernel")
TARGET = "/mach_kernel.rcz"


def used_frags_excluding(img, skip_ino):
    total = 0
    stack = ["/"]
    while stack:
        path = stack.pop()
        for name, ino, dtype in img.listdir(path):
            if name in (".", ".."):
                continue
            child = path.rstrip("/") + "/" + name
            if ino != skip_ino:
                total += img.inode(ino).blocks
            if dtype == 4:
                stack.append(child)
    return total


def main():
    with rhap_image.Image(FLOPPY) as img:
        kernel_ino = img.resolve(TARGET)
        other = used_frags_excluding(img, kernel_ino)
        budget = img.fs_size_data() - other
        payload = budget - img.frag
        ceiling = (payload // img.frag) * img.frag * img.fsize

    with open(KERNEL, "rb") as f:
        raw = f.read()
    stream = rcz.compress(raw)

    print("kernel            %d bytes" % len(raw))
    print("compressed        %d bytes" % len(stream))
    print("other objects     %d frags" % other)
    print("budget            %d frags" % budget)
    print("ceiling           %d bytes" % ceiling)
    print("margin            %+d bytes" % (ceiling - len(stream)))
    if len(stream) <= ceiling:
        print("VERDICT: fits 1.44 MB")
        return 0
    print("VERDICT: does NOT fit; fall through to the 2.88 MB branch (Task 7a)")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
