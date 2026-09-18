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
import time

import rhap_image
import ufs_cg

HERE = os.path.dirname(os.path.abspath(__file__))

# bsize=8192 and fsize=1024 (so frag=8) on golden.img; one indirect block
# holds bsize // 4 = 2048 pointers.  Double indirect is out of scope.  This
# module-level constant matches golden.img's own geometry and exists only so
# callers that don't have an Allocator handy (e.g. tests) have something to
# reference; Allocator.max_file_bytes() is authoritative and derives the
# real limit from self.g, so it stays correct for any image's geometry.
MAX_FILE_BYTES = (rhap_image.NDADDR + 2048) * 8192

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
        self._inode_cache = {}     # fragment number -> mutable dinode-block bytearray
        self._data_cache = {}      # fragment number -> pending file-content bytes

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def close(self):
        self.img.close()

    def max_file_bytes(self):
        """Largest file representable with direct plus single-indirect
        blocks, derived from this filesystem's own geometry (not the
        golden.img-shaped module constant MAX_FILE_BYTES)."""
        return (rhap_image.NDADDR + self.g.nindir) * self.g.bsize

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

    def _dirty_inode_block(self, frag):
        """The live, mutable cached dinode-block buffer covering fragment
        `frag` (frag-aligned, self.g.bsize bytes -- the same unit
        rhap_image._inode_location and Image.read_frag(..., bsize) use).
        """
        if frag not in self._inode_cache:
            self._inode_cache[frag] = bytearray(
                self.img.read_frag(frag, self.g.bsize))
        return self._inode_cache[frag]

    def _apply_inode_delta(self, c, local_indices, to_used, is_dir):
        """Flip inodes in group c's used-inode bitmap and update cg_cs,
        this group's fs_csaddr slot, and fs_cstotal -- the same three
        places _apply_group_delta keeps in step for fragments.  Pending
        only; nothing touches disk until flush().
        """
        buf = self._dirty_cg(c)
        iusedoff = struct.unpack_from("<i", buf, CG_OFFSETS_OFF + 8)[0]
        nbytes = (self.g.ipg + 7) // 8
        inosused = bytearray(buf[iusedoff:iusedoff + nbytes])
        for i in local_indices:
            byte, bit = divmod(i, 8)
            if to_used:
                inosused[byte] |= (1 << bit)
            else:
                inosused[byte] &= ~(1 << bit) & 0xFF
        buf[iusedoff:iusedoff + nbytes] = inosused

        old_ndir, old_nbfree, old_nifree, old_nffree = struct.unpack_from(
            "<4i", buf, CG_CS_OFF)
        n = len(local_indices)
        nifree_delta = -n if to_used else n
        ndir_delta = (n if to_used else -n) if is_dir else 0
        new_ndir = old_ndir + ndir_delta
        new_nifree = old_nifree + nifree_delta
        struct.pack_into("<4i", buf, CG_CS_OFF,
                          new_ndir, old_nbfree, new_nifree, old_nffree)

        cstable = self._dirty_cstable()
        struct.pack_into("<4i", cstable, c * 16,
                          new_ndir, old_nbfree, new_nifree, old_nffree)

        sb = self._dirty_sb()
        ndir, nbfree, nifree, nffree = struct.unpack_from(
            "<4i", sb, SB_CSTOTAL_OFF)
        ndir += ndir_delta
        nifree += nifree_delta
        struct.pack_into("<4i", sb, SB_CSTOTAL_OFF, ndir, nbfree, nifree, nffree)

    def alloc_inode(self, is_dir=False):
        """Claim the lowest-numbered free inode (never 0, 1 or 2 -- those
        are reserved and already marked used on any real filesystem).
        Updates the group's inode bitmap, cs_nifree, and cs_ndir when
        is_dir.  Returns the inode number.
        """
        self._require_writable("alloc_inode")
        for c in range(self.cg_count):
            inosused = self.inosused(c)
            for local in range(self.g.ipg):
                ino = c * self.g.ipg + local
                if ino < 3:
                    continue
                if not ufs_cg.bit_is_set(inosused, local):
                    self._apply_inode_delta(c, [local], to_used=True,
                                             is_dir=is_dir)
                    return ino
        raise SafetyError("no free inode in any cylinder group")

    def free_inode(self, ino, is_dir=False):
        """Release an inode previously returned by alloc_inode."""
        self._require_writable("free_inode")
        c, local = divmod(ino, self.g.ipg)
        self._apply_inode_delta(c, [local], to_used=False, is_dir=is_dir)

    def write_inode(self, ino, mode, size, db, ib, nlink, mtime):
        """Write a 128-byte dinode.  db is the 12 direct block pointers,
        ib the 3 indirect ones (rhap_image.Inode's layout: mode at 0,
        nlink at 2, size at 8, mtime at 24, db at 40, ib at 88).
        """
        self._require_writable("write_inode")
        if len(db) != rhap_image.NDADDR:
            raise ValueError("db must have %d entries" % rhap_image.NDADDR)
        if len(ib) != rhap_image.NIADDR:
            raise ValueError("ib must have %d entries" % rhap_image.NIADDR)
        frag, entry = rhap_image._inode_location(self.img, ino)
        buf = self._dirty_inode_block(frag)
        struct.pack_into("<Hh", buf, entry, mode, nlink)
        struct.pack_into("<Q", buf, entry + 8, size)
        struct.pack_into("<i", buf, entry + 24, mtime)
        struct.pack_into("<%di" % rhap_image.NDADDR, buf, entry + 40, *db)
        struct.pack_into("<%di" % rhap_image.NIADDR, buf, entry + 88, *ib)

    def set_inode_blocks(self, ino, nsectors):
        """Set di_blocks, which counts 512-byte sectors (not fragments)."""
        self._require_writable("set_inode_blocks")
        frag, entry = rhap_image._inode_location(self.img, ino)
        buf = self._dirty_inode_block(frag)
        struct.pack_into("<i", buf, entry + 104, nsectors)

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
        for frag, buf in self._inode_cache.items():
            f.seek(self.img.frag_offset(frag))
            f.write(bytes(buf))
        for frag, buf in self._data_cache.items():
            f.seek(self.img.frag_offset(frag))
            f.write(buf)
        f.flush()
        self._cg_cache.clear()
        self._sb_cache = None
        self._cstable_cache = None
        self._inode_cache.clear()
        self._data_cache.clear()

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

    def _write_data(self, frag_start, chunk):
        self._data_cache[frag_start] = bytes(chunk)

    def _zero_dinode(self, ino):
        """Clear a dinode's 128 bytes before write_inode fills it in, so a
        reused inode never inherits a dead occupant's uid/gid/times/etc.
        """
        frag, entry = rhap_image._inode_location(self.img, ino)
        buf = self._dirty_inode_block(frag)
        buf[entry:entry + rhap_image.DINODE_SIZE] = bytes(rhap_image.DINODE_SIZE)

    def _alloc_whole_blocks(self, nblocks, allocated):
        """Allocate `nblocks` whole fs_frag-fragment blocks, spread across
        as many cylinder groups as necessary (alloc_frags only ever
        searches one group per call).  Every raw fragment handed back is
        appended to `allocated`, for rollback on failure.  Returns the
        list of block-start fragment numbers, one per block.
        """
        frag = self.g.frag
        starts = []
        remaining = nblocks
        while remaining > 0:
            chunk = remaining
            got = None
            while chunk > 0:
                try:
                    got = self.alloc_frags(chunk * frag)
                    break
                except SafetyError:
                    chunk = chunk // 2
            if not got:
                raise SafetyError(
                    "not enough free space across any cylinder group to "
                    "allocate %d more block(s)" % remaining)
            allocated.extend(got)
            for i in range(chunk):
                starts.append(got[i * frag])
            remaining -= chunk
        return starts

    def _alloc_tail_block(self, tail_frags, allocated):
        """Allocate the single, possibly-partial final block of a file."""
        got = self.alloc_frags(tail_frags)
        allocated.extend(got)
        return got[0]

    def _alloc_and_write_blocks(self, data):
        """Allocate whole blocks for all but the tail, write `data` into
        them, and allocate/fill a single indirect block once the file
        needs more than NDADDR blocks.  Returns (db, ib, total_frags),
        where total_frags is every fragment allocated (content plus the
        indirect block itself) for di_blocks accounting.
        """
        bsize = self.g.bsize
        size = len(data)
        allocated = []
        try:
            block_starts = []
            if size > 0:
                nblocks = (size + bsize - 1) // bsize
                nfull = nblocks - 1
                tail_bytes = size - nfull * bsize
                fsize = self.g.fsize
                tail_frags = (tail_bytes + fsize - 1) // fsize
                if nfull > 0:
                    block_starts += self._alloc_whole_blocks(nfull, allocated)
                block_starts.append(self._alloc_tail_block(tail_frags, allocated))

            for idx, start in enumerate(block_starts):
                offset = idx * bsize
                chunk = data[offset:offset + bsize]
                if idx == len(block_starts) - 1:
                    # Zero the rest of the tail block's allocated fragments
                    # so a previously freed file's bytes don't leak into
                    # space the new file now owns.
                    want = tail_frags * fsize
                    if len(chunk) < want:
                        chunk = chunk + bytes(want - len(chunk))
                self._write_data(start, chunk)

            ndaddr = rhap_image.NDADDR
            db = block_starts[:ndaddr]
            db += [0] * (ndaddr - len(db))
            ib = [0, 0, 0]
            if len(block_starts) > ndaddr:
                indirect = self._alloc_whole_blocks(1, allocated)
                ib[0] = indirect[0]
                ptrs = block_starts[ndaddr:]
                ptrs += [0] * (self.g.nindir - len(ptrs))
                self._write_data(ib[0],
                                  struct.pack("<%di" % self.g.nindir, *ptrs))

            return db, ib, len(allocated)
        except SafetyError:
            self.free_frags(allocated)
            raise

    def _read_dinode(self, ino):
        """(mode, nlink, size, db, ib) for an existing inode, honoring any
        pending (unflushed) write in this session.
        """
        frag, entry = rhap_image._inode_location(self.img, ino)
        buf = self._inode_cache.get(frag)
        if buf is None:
            buf = self.img.read_frag(frag, self.g.bsize)
        mode, nlink = struct.unpack_from("<Hh", buf, entry)
        size = struct.unpack_from("<Q", buf, entry + 8)[0]
        db = list(struct.unpack_from("<%di" % rhap_image.NDADDR, buf, entry + 40))
        ib = list(struct.unpack_from("<%di" % rhap_image.NIADDR, buf, entry + 88))
        return mode, nlink, size, db, ib

    def _old_file_frags(self, size, db, ib):
        """Every fragment (content blocks plus the indirect block, if any)
        belonging to a file previously written by this module, based on
        our own layout: every block but the last is a full fs_frag-sized
        block, the last is sized to just cover the remainder.

        A block pointer of 0 means a hole (a sparse block) and occupies no
        space on disk -- it must never be handed to free_frags, or fragment
        0 (the boot block / superblock area) gets marked free.
        """
        if size == 0:
            return []
        bsize = self.g.bsize
        fsize = self.g.fsize
        frag = self.g.frag
        ndaddr = rhap_image.NDADDR
        nblocks = (size + bsize - 1) // bsize
        block_starts = list(db[:min(nblocks, ndaddr)])
        if nblocks > ndaddr:
            ind = self._data_cache.get(ib[0])
            if ind is None:
                ind = self.img.read_frag(ib[0], bsize)
            ptrs = struct.unpack_from("<%di" % self.g.nindir, ind, 0)
            block_starts += list(ptrs[:nblocks - ndaddr])
        tail_bytes = size - (nblocks - 1) * bsize
        tail_frags = (tail_bytes + fsize - 1) // fsize
        out = []
        for idx, start in enumerate(block_starts):
            if start == 0:
                continue  # hole: no space to release
            count = frag if idx < nblocks - 1 else tail_frags
            out.extend(start + k for k in range(count))
        if nblocks > ndaddr and ib[0] != 0:
            out.extend(ib[0] + k for k in range(frag))
        return out

    def write_new_file(self, data, mode=0o100644):
        """Allocate a fresh inode and fragments, write `data` as its
        contents, and return the inode number.  Refuses anything over
        MAX_FILE_BYTES before allocating anything.
        """
        self._require_writable("write_new_file")
        limit = self.max_file_bytes()
        if len(data) > limit:
            raise SafetyError(
                "file is %d bytes, over the %d-byte (16 MB) limit for "
                "direct plus single-indirect blocks" % (len(data), limit))
        ino = self.alloc_inode()
        try:
            db, ib, total_frags = self._alloc_and_write_blocks(data)
        except Exception:
            self.free_inode(ino)
            raise
        self._zero_dinode(ino)
        self.write_inode(ino, mode=mode, size=len(data), db=db, ib=ib,
                          nlink=1, mtime=int(time.time()))
        self.set_inode_blocks(ino, total_frags * (self.g.fsize // 512))
        return ino

    def grow_file(self, ino, data):
        """Replace an existing file's contents, allocating more fragments
        when `data` exceeds its current allocation and releasing the
        surplus when it shrinks.
        """
        self._require_writable("grow_file")
        limit = self.max_file_bytes()
        if len(data) > limit:
            raise SafetyError(
                "file is %d bytes, over the %d-byte (16 MB) limit for "
                "direct plus single-indirect blocks" % (len(data), limit))
        mode, nlink, old_size, old_db, old_ib = self._read_dinode(ino)
        old_frags = self._old_file_frags(old_size, old_db, old_ib)
        db, ib, total_frags = self._alloc_and_write_blocks(data)
        self.free_frags(old_frags)
        self.write_inode(ino, mode=mode, size=len(data), db=db, ib=ib,
                          nlink=nlink, mtime=int(time.time()))
        self.set_inode_blocks(ino, total_frags * (self.g.fsize // 512))
