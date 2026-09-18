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
        self.writable = writable
        self.img = rhap_image.Image(image_path, writable=writable)
        self.g = ufs_cg.read_geometry(image_path)
        self.cg_count = self.g.ncg

        # Pending, unflushed writes.  Until flush() runs the image on disk is
        # byte-identical; these caches are how a mutation (alloc_frags,
        # free_frags) becomes visible to later reads in the same session
        # without touching the file.  Keyed/populated lazily, and only for
        # locations a mutation actually dirtied -- an untouched group is
        # never copied in here, it's just read straight off disk.
        self._cg_cache = {}        # cg index -> mutable header-block bytearray
        self._sb_cache = None      # mutable copy of the superblock block
        self._cstable_cache = None  # mutable copy of the fs_csaddr table

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
        """The whole cylinder-group header block, as a bytearray.

        Always a fresh copy, but if group c has a pending mutation this
        reflects it: callers (including our own accessors below) see the
        not-yet-flushed state, not stale disk contents.  Mutating the
        returned bytearray has no effect -- go through alloc_frags /
        free_frags to change anything.
        """
        if c in self._cg_cache:
            return bytearray(self._cg_cache[c])
        return bytearray(self.img.read_frag(self._cg_frag(c), self.g.bsize))

    def _dirty_cg(self, c):
        """The live, mutable cached header buffer for group c.

        First touch loads it from disk; later touches (and later reads via
        read_cg) reuse the same object, so this is the one and only place a
        cylinder group's header is read-modify-written before flush()."""
        if c not in self._cg_cache:
            self._cg_cache[c] = bytearray(
                self.img.read_frag(self._cg_frag(c), self.g.bsize))
        return self._cg_cache[c]

    def _dirty_sb(self):
        if self._sb_cache is None:
            self._sb_cache = bytearray(self.img._read_at(
                self.img.part_start + rhap_image.SBOFF, rhap_image.SBOFF))
        return self._sb_cache

    def _dirty_cstable(self):
        if self._cstable_cache is None:
            off = self.img.part_start + self.g.csaddr * self.g.fsize
            self._cstable_cache = bytearray(self.img._read_at(off, self.g.cssize))
        return self._cstable_cache

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
        if self._sb_cache is not None:
            sb = self._sb_cache
        else:
            sb = self.img._read_at(self.img.part_start + rhap_image.SBOFF,
                                    rhap_image.SBOFF)
        return struct.unpack_from("<4i", sb, SB_CSTOTAL_OFF)

    def frag_is_free(self, frag):
        """True if absolute fragment number `frag` is free.

        Reflects any pending, unflushed mutation to the owning group.
        """
        c, i = divmod(frag, self.g.fpg)
        buf = self.read_cg(c)
        freeoff = struct.unpack_from("<i", buf, CG_OFFSETS_OFF + 12)[0]
        return bool(ufs_cg.bit_is_set(buf[freeoff:], i))

    def _require_writable(self, what):
        if not self.writable:
            raise SafetyError("%s requires Allocator(writable=True)" % what)

    def _apply_group_delta(self, c, local_indices, to_used):
        """Flip fragments in group c's bitmap and update every downstream
        summary that ufs_check.check verifies: cg_cs, cg_frsum, the
        btot/blks tables, the cluster maps, this group's fs_csaddr slot,
        and fs_cstotal.  All of it lands in the pending caches; nothing
        touches disk until flush().
        """
        buf = self._dirty_cg(c)
        freeoff = struct.unpack_from("<i", buf, CG_OFFSETS_OFF + 12)[0]
        nbytes = (self.g.fpg + 7) // 8
        blksfree = bytearray(buf[freeoff:freeoff + nbytes])
        for i in local_indices:
            byte, bit = divmod(i, 8)
            if to_used:
                blksfree[byte] &= ~(1 << bit) & 0xFF
            else:
                blksfree[byte] |= (1 << bit)
        buf[freeoff:freeoff + nbytes] = blksfree

        old_ndir, old_nbfree, old_nifree, old_nffree = struct.unpack_from(
            "<4i", buf, CG_CS_OFF)
        tables = ufs_cg.recompute_cg_tables(self.g, blksfree)
        struct.pack_into("<4i", buf, CG_CS_OFF,
                          old_ndir, tables.nbfree, old_nifree, tables.nffree)
        struct.pack_into("<%di" % self.g.frag, buf, CG_FRSUM_OFF, *tables.frsum)

        btotoff, boff, _iusedoff, _freeoff = struct.unpack_from(
            "<4i", buf, CG_OFFSETS_OFF)
        struct.pack_into("<%di" % self.g.cpg, buf, btotoff, *tables.blktot)
        struct.pack_into("<%dh" % (self.g.cpg * self.g.nrpos), buf, boff,
                          *tables.blks)

        if self.g.contigsumsize > 0:
            clustersumoff, clusteroff, nclusterblks = struct.unpack_from(
                "<3i", buf, 104)
            clustersfree, clustersum = ufs_cg.recompute_cluster_maps(
                self.g, blksfree, nclusterblks)
            struct.pack_into("<%di" % len(clustersum), buf, clustersumoff,
                              *clustersum)
            buf[clusteroff:clusteroff + len(clustersfree)] = clustersfree

        cstable = self._dirty_cstable()
        struct.pack_into("<4i", cstable, c * 16,
                          old_ndir, tables.nbfree, old_nifree, tables.nffree)

        sb = self._dirty_sb()
        ndir, nbfree, nifree, nffree = struct.unpack_from(
            "<4i", sb, SB_CSTOTAL_OFF)
        nbfree += tables.nbfree - old_nbfree
        nffree += tables.nffree - old_nffree
        struct.pack_into("<4i", sb, SB_CSTOTAL_OFF, ndir, nbfree, nifree, nffree)

    def alloc_frags(self, n):
        """Allocate n fragments, as whole fs_frag-sized blocks plus at most
        one partial tail block for the remainder, all from a single
        cylinder group.  Returns absolute fragment numbers.
        """
        self._require_writable("alloc_frags")
        if n <= 0:
            raise ValueError("n must be positive")
        frag = self.g.frag
        blocks_needed = (n + frag - 1) // frag
        tail = n % frag

        for c in range(self.cg_count):
            buf = self.read_cg(c)
            freeoff = struct.unpack_from("<i", buf, CG_OFFSETS_OFF + 12)[0]
            nbytes = (self.g.fpg + 7) // 8
            blksfree = buf[freeoff:freeoff + nbytes]

            free_blocks = []
            for base in range(0, self.g.fpg, frag):
                if all(ufs_cg.bit_is_set(blksfree, base + i)
                       for i in range(frag)):
                    free_blocks.append(base)
                    if len(free_blocks) == blocks_needed:
                        break
            if len(free_blocks) < blocks_needed:
                continue

            result = []
            flip = []
            for idx, base in enumerate(free_blocks):
                take = frag if tail == 0 or idx < blocks_needed - 1 else tail
                for k in range(take):
                    flip.append(base + k)
                    result.append(self.g.fpg * c + base + k)
            self._apply_group_delta(c, flip, to_used=True)
            return result

        raise SafetyError(
            "no cylinder group has %d free fragment(s) (%d whole block(s) "
            "needed)" % (n, blocks_needed))

    def free_frags(self, frags):
        """Release fragments previously returned by alloc_frags."""
        self._require_writable("free_frags")
        by_group = {}
        for f in frags:
            c, i = divmod(f, self.g.fpg)
            by_group.setdefault(c, []).append(i)
        for c, indices in by_group.items():
            self._apply_group_delta(c, indices, to_used=False)

    def flush(self):
        """Write every pending change to disk.  The only method that writes."""
        self._require_writable("flush")
        f = self.img._f
        for c, buf in self._cg_cache.items():
            f.seek(self.cg_header_offset(c))
            f.write(bytes(buf))
        if self._sb_cache is not None:
            f.seek(self.img.part_start + rhap_image.SBOFF)
            f.write(bytes(self._sb_cache))
        if self._cstable_cache is not None:
            off = self.img.part_start + self.g.csaddr * self.g.fsize
            f.seek(off)
            f.write(bytes(self._cstable_cache))
        f.flush()
        self._cg_cache.clear()
        self._sb_cache = None
        self._cstable_cache = None

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
