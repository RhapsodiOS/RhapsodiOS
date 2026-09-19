"""Graft a rebuilt mach_kernel into a disk image so it can be boot-tested.

/mach_kernel on golden.img has almost no slack: size 1459520 bytes,
max_writable 1460224 bytes -- 704 bytes.  rhap_inject.write_file (the plain
`put` path) never allocates; it only overwrites a file's already-mapped
fragments.  Any realistically rebuilt kernel binary will exceed that 704-byte
margin and be refused outright.

rhap_inject.graft_file works around this by repointing /mach_kernel's
directory entry at a larger, expendable donor file instead of overwriting
/mach_kernel's own fragments.  Read its docstring before changing anything
here: notably, the first graft onto a donor shrinks the donor's di_size down
to the payload size, which caps every later graft onto that same donor there
too.  That is why this tool always grafts into a fresh copy of the source
image rather than re-grafting an existing working image.

check_target() (from rhap_inject, also called internally by graft_file)
restricts writes to exactly vm/work/test.img -- not any path under vm/work.
That is inherited, not reinvented, here: it means the OUT_IMAGE argument to
this tool must be vm/work/test.img, and any other destination is refused
before anything is copied or written.
"""

import os
import shutil
import sys

import rhap_image
import rhap_inject

MACHO_MAGIC = b"\xce\xfa\xed\xfe"

DEFAULT_DONOR = (
    "/System/Documentation/Developer/YellowBox/TasksAndConcepts/PB/ProjectBuilder.pdf"
)


def graft_kernel(src_image, kernel_path, out_image, donor_path=DEFAULT_DONOR):
    """Copy src_image to out_image, then graft kernel_path in as /mach_kernel.

    Returns (old_size, new_size, headroom) on success.  Raises
    rhap_inject.SafetyError (from check_target or graft_file) on any refusal,
    before out_image has been touched.
    """
    rhap_inject.check_target(out_image)

    if not os.path.exists(src_image):
        raise rhap_inject.SafetyError("no such source image: %s" % src_image)
    if not os.path.exists(kernel_path):
        raise rhap_inject.SafetyError("no such kernel file: %s" % kernel_path)

    with open(kernel_path, "rb") as fh:
        data = fh.read()

    # Read-only pass against the source to fail loudly, before copying
    # anything, if the donor cannot possibly take this payload.
    with rhap_image.Image(src_image) as probe:
        old_ino = probe.resolve("/mach_kernel")
        if old_ino is None:
            raise rhap_inject.SafetyError("%s: /mach_kernel does not exist" % src_image)
        old_size = probe.inode(old_ino).size

    shutil.copyfile(src_image, out_image)

    img = rhap_image.Image(out_image, writable=True)
    try:
        donor_ino = rhap_inject.graft_file(img, "/mach_kernel", donor_path, data)
    finally:
        img.close()

    check = rhap_image.Image(out_image)
    try:
        ino = check.resolve("/mach_kernel")
        if ino != donor_ino:
            raise rhap_inject.SafetyError(
                "/mach_kernel resolves to inode %r, expected donor inode %d"
                % (ino, donor_ino))
        got = check.read_file(ino)
        if len(got) != len(data):
            raise rhap_inject.SafetyError(
                "/mach_kernel is %d bytes after graft, expected %d"
                % (len(got), len(data)))
        if got[:4] != MACHO_MAGIC:
            raise rhap_inject.SafetyError(
                "/mach_kernel does not start with Mach-O magic %s after graft: got %s"
                % (MACHO_MAGIC.hex(), got[:4].hex()))
        donor_inode = check.inode(donor_ino)
        headroom = check.max_writable(donor_inode) - donor_inode.size
    finally:
        check.close()

    return old_size, len(data), headroom, donor_ino


def main(argv):
    if len(argv) not in (4, 5):
        print("usage: graft-kernel.py SRC_IMAGE KERNEL_FILE OUT_IMAGE [DONOR_PATH]",
              file=sys.stderr)
        return 2
    src_image, kernel_path, out_image = argv[1], argv[2], argv[3]
    donor_path = argv[4] if len(argv) == 5 else DEFAULT_DONOR

    try:
        old_size, new_size, headroom, donor_ino = graft_kernel(
            src_image, kernel_path, out_image, donor_path)
    except rhap_inject.SafetyError as e:
        print("graft-kernel: %s" % e, file=sys.stderr)
        return 1

    print("donor:        %s (inode %d)" % (donor_path, donor_ino))
    print("old kernel:   %d bytes" % old_size)
    print("new kernel:   %d bytes" % new_size)
    print("headroom:     %d bytes" % headroom)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
