"""Build the UFS gap tests' base image: a copy of golden.img whose
/mach_kernel is a rebuilt kernel, installed as a real file.

usage: python ufs-e2e-image.py GOLDEN KERNEL [OUT]

graft-kernel.py repoints /mach_kernel at a donor file, which leaves damage
fsck -p will not preen.  This rewrites the kernel's own inode in place with
ufs_alloc's grow_file, which allocates and frees fragments and keeps every
summary consistent.  golden.img's /mach_kernel has two links (the other is
/private/tftpboot/mach_kernel), and grow_file keeps the inode, its mode and
its link count, so both names stay valid.

OUT defaults to work/ufs-e2e.img beside this script.  It must not exist and
must be under vm/work.  If ufs_check finds any problem in the result, OUT is
removed and the exit status is 1.
"""
import os
import shutil
import sys

import ufs_alloc
import ufs_check

HERE = os.path.dirname(os.path.abspath(__file__))
USAGE = "usage: python ufs-e2e-image.py GOLDEN KERNEL [OUT]"


def install_kernel(image, kernel):
    """Replace /mach_kernel's contents in image with the bytes kernel.
    Returns its inode number, which does not change."""
    with ufs_alloc.Allocator(image, writable=True) as a:
        a.validate()
        ino = a._resolve("/mach_kernel")
        a.grow_file(ino, kernel)
        a.flush()
    return ino


def main(argv):
    if len(argv) not in (3, 4):
        print(USAGE, file=sys.stderr)
        return 2
    golden, kernel_path = argv[1], argv[2]
    out = argv[3] if len(argv) == 4 else os.path.join(HERE, "work", "ufs-e2e.img")
    if os.path.exists(out):
        print("ufs-e2e-image: %s already exists" % out, file=sys.stderr)
        return 1
    try:
        ufs_alloc._refuse_master(out)
    except ufs_alloc.SafetyError as e:
        print("ufs-e2e-image: %s" % e, file=sys.stderr)
        return 1
    with open(kernel_path, "rb") as f:
        kernel = f.read()
    print("copying %s to %s" % (golden, out))
    try:
        shutil.copyfile(golden, out)
        ino = install_kernel(out, kernel)
        problems = ufs_check.check(out)
    except BaseException:
        if os.path.exists(out):
            os.remove(out)
        raise
    if problems:
        os.remove(out)
        print("ufs-e2e-image: ufs_check found %d problem(s); %s removed"
              % (len(problems), out), file=sys.stderr)
        for p in problems:
            print("  %s" % p, file=sys.stderr)
        return 1
    print("installed a %d-byte kernel in inode %d; ufs_check: 0 problems"
          % (len(kernel), ino))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
