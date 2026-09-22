"""Write a boot2 image into both boot-area copies of vm/work/test.img.

boot1 does not load /usr/standalone/i386/boot. It reads the NeXT disk label
at sector 15, takes dl_boot0_blkno[0] and loads LOADSZ sectors from there
(src/boot-2/i386/boot1/boot1.s:185-210). The label names a second copy in
dl_boot0_blkno[1]; both are written so they stay identical, as they are on
golden.img. Each copy's slot runs from its block to the next copy's block,
or to the end of the front porch for the last one, and the whole slot is
rewritten: the booter, then zeros.

Refuses, before writing anything, a booter longer than LOADSZ sectors (read
out of boot1.s, as boot2/Makefile does) or longer than either slot. Only
vm/work/test.img may be written (rhap_inject.check_target). Every slot is
read back and compared after writing.

Usage: install-booter.py IMAGE BOOTER
"""
import hashlib
import os
import re
import struct
import sys

import rhap_image
import rhap_inject

_HERE = os.path.dirname(os.path.abspath(__file__))
BOOT1_SRC = os.path.join(_HERE, "..", "src", "boot-2", "i386", "boot1", "boot1.s")

# Offsets into the disk label: dl_dt (a disktab_t) starts at 44, and
# d_secsize, d_front and d_boot0_blkno[2] sit at 48, 68 and 80 within it
# (src/kernel-7/bsd/sys/disktab.h). All big-endian.
SECSIZE_OFF = 92
FRONT_OFF = 112
BOOT0_OFF = 124


def read_loadsz(boot1_src=BOOT1_SRC):
    """Return boot1's LOADSZ in bytes."""
    with open(boot1_src) as f:
        m = re.search(r"^LOADSZ\s+EQU\s+(\d+)", f.read(), re.M)
    if m is None:
        raise ValueError("no LOADSZ in %s" % boot1_src)
    return int(m.group(1)) * 512


def boot_slots(f):
    """Return [(offset, length)] for the two boot-area copies."""
    for off in rhap_image.LABEL_OFFSETS:
        f.seek(off)
        buf = f.read(1024)
        if buf[:4] == rhap_image.LABEL_MAGIC:
            break
    else:
        raise rhap_inject.SafetyError("no NeXT disk label found")
    secsize = struct.unpack_from(">i", buf, SECSIZE_OFF)[0]
    front = struct.unpack_from(">h", buf, FRONT_OFF)[0]
    b0, b1 = struct.unpack_from(">ii", buf, BOOT0_OFF)
    if not 0 < b0 < b1 < front:
        raise rhap_inject.SafetyError(
            "boot blocks %d, %d do not fit a front porch of %d" % (b0, b1, front))
    return [(b0 * secsize, (b1 - b0) * secsize),
            (b1 * secsize, (front - b1) * secsize)]


def install_booter(image, booter, limit):
    """Write `booter` into both slots of `image`. Returns the slots."""
    rhap_inject.check_target(image)
    if len(booter) > limit:
        raise rhap_inject.SafetyError(
            "booter is %d bytes; boot1 reads only %d" % (len(booter), limit))
    with open(image, "r+b") as f:
        slots = boot_slots(f)
        for off, length in slots:
            if len(booter) > length:
                raise rhap_inject.SafetyError(
                    "booter is %d bytes; the slot at %d holds %d" % (len(booter), off, length))
        for off, length in slots:
            f.seek(off)
            f.write(booter + bytes(length - len(booter)))
        f.flush()
        want = hashlib.sha256(booter).digest()
        for off, length in slots:
            f.seek(off)
            got = f.read(length)
            if hashlib.sha256(got[:len(booter)]).digest() != want or any(got[len(booter):]):
                raise rhap_inject.SafetyError("read-back of the slot at %d differs" % off)
    return slots


def main(argv):
    if len(argv) != 3:
        print("usage: install-booter.py IMAGE BOOTER", file=sys.stderr)
        return 2
    with open(argv[2], "rb") as f:
        booter = f.read()
    try:
        slots = install_booter(argv[1], booter, read_loadsz())
    except (rhap_inject.SafetyError, ValueError) as e:
        print("install-booter: %s" % e, file=sys.stderr)
        return 1
    print("booter %d bytes, sha256 %s" % (len(booter), hashlib.sha256(booter).hexdigest().upper()))
    for off, length in slots:
        print("  written and verified at byte %d (slot %d bytes)" % (off, length))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
