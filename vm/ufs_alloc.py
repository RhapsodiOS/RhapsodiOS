"""Allocating writer for the Rhapsody disk image.

Unlike rhap_inject.py, which never allocates and only rewrites already-mapped
fragments, this module grows the filesystem: it claims fragments and inodes,
creates directory entries, and maintains every summary the kernel and fsck
rely on.  That power is why the safety rules here are strict.

Never operates on vm/golden.img.  Every refusal raises SafetyError, and
refusals happen before the first byte is written.
"""
import os
import struct

import rhap_image
import ufs_cg

HERE = os.path.dirname(os.path.abspath(__file__))

CG_CS_OFF = 24          # struct csum inside the cg header
CG_OFFSETS_OFF = 84     # cg_btotoff, cg_boff, cg_iusedoff, cg_freeoff

# struct fs in src/kernel-7/bsd/ufs/ffs/fs.h:241 (the "struct csum
# fs_cstotal" member).  Counting every preceding int32-sized field (each
# ufs_daddr_t/time_t on this platform is also 4 bytes, confirmed because
# doing so lines up every later field with ufs_cg.SB_FIELDS' offsets, e.g.
# fs_nindir at 116 and fs_fpg at 188) puts fs_cstotal at byte 192.
# Allocator.validate() proves this against golden.img: the sum of all 510
# per-group summaries must equal the value read from this offset exactly.
SB_CSTOTAL_OFF = 192

# cg_frsum[MAXFRAG] follows cg_rotor/cg_frotor/cg_irotor, which follow
# cg_cs (CG_CS_OFF + 16 bytes).  MAXFRAG is 8 (src/kernel-7/bsd/sys/param.h).
CG_FRSUM_OFF = CG_CS_OFF + 16 + 12


class SafetyError(Exception):
    pass


def _refuse_master(path):
    """Refuse the read-only master and anything outside vm/work."""
    real = os.path.realpath(path)
    golden = os.path.realpath(os.path.join(HERE, "golden.img"))
    if real == golden:
        raise SafetyError("refusing to write to the master image: %s" % path)
    work = os.path.realpath(os.path.join(HERE, "work"))
    if not real.startswith(work + os.sep):
        raise SafetyError("writable images must live under %s: %s"
                          % (work, path))


class Allocator(object):
    """Read (and, when writable, eventually write) a multi-group UFS image."""

    def __init__(self, image_path, writable=False):
        if writable:
            _refuse_master(image_path)
        self.path = image_path
        self.img = rhap_image.Image(image_path, writable=writable)
        self.g = ufs_cg.read_geometry(image_path)
        self.cg_count = self.g.ncg

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def close(self):
        self.img.close()

    def _cg_frag(self, c):
        return rhap_image._cgstart(self.img, c) + self.g.cblkno

    def cg_header_offset(self, c):
        """Absolute byte offset of group c's header block."""
        return self.img.part_start + self._cg_frag(c) * self.g.fsize

    def read_cg(self, c):
        """The whole cylinder-group header block, as a bytearray."""
        return bytearray(self.img.read_frag(self._cg_frag(c), self.g.bsize))

    def cg_summary(self, c):
        """(ndir, nbfree, nifree, nffree) recorded in group c's own header."""
        buf = self.read_cg(c)
        return struct.unpack_from("<4i", buf, CG_CS_OFF)

    def blksfree(self, c):
        """Free-fragment bitmap for group c.  A set bit means free."""
        buf = self.read_cg(c)
        freeoff = struct.unpack_from("<i", buf, CG_OFFSETS_OFF + 12)[0]
        n = (self.g.fpg + 7) // 8
        return bytearray(buf[freeoff:freeoff + n])

    def inosused(self, c):
        """Used-inode bitmap for group c.  A set bit means in use."""
        buf = self.read_cg(c)
        iusedoff = struct.unpack_from("<i", buf, CG_OFFSETS_OFF + 8)[0]
        n = (self.g.ipg + 7) // 8
        return bytearray(buf[iusedoff:iusedoff + n])

    def fs_cstotal(self):
        """(ndir, nbfree, nifree, nffree) recorded in the superblock."""
        sb = self.img._read_at(self.img.part_start + rhap_image.SBOFF,
                                rhap_image.SBOFF)
        return struct.unpack_from("<4i", sb, SB_CSTOTAL_OFF)

    def validate(self):
        """Refuse to proceed unless our model already matches a good filesystem."""
        totals = [0, 0, 0, 0]
        for c in range(self.cg_count):
            for i, v in enumerate(self.cg_summary(c)):
                totals[i] += v
        recorded = self.fs_cstotal()
        if tuple(totals) != tuple(recorded):
            raise SafetyError(
                "summed cylinder-group summaries %s disagree with fs_cstotal %s; "
                "the on-disk layout is not what this tool expects"
                % (tuple(totals), tuple(recorded)))
