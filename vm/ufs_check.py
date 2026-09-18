"""Recompute every UFS allocation invariant and report disagreements.

Fast enough for unit tests, and independent of the write path in the sense
that it derives everything from the raw bitmaps.  It shares assumptions with
the code it checks, which is why the acceptance gate is the guest's fsck and
not this.
"""
import struct

import rhap_image
import ufs_alloc
import ufs_cg


def _popcount(bitmap, nbits):
    return sum(ufs_cg.bit_is_set(bitmap, i) for i in range(nbits))


def check(image_path):
    problems = []
    with ufs_alloc.Allocator(image_path) as a:
        g = a.g
        csaddr_off = a.img.part_start + g.csaddr * g.fsize
        cstable = a.img._read_at(csaddr_off, g.cssize)

        totals = [0, 0, 0, 0]
        for c in range(a.cg_count):
            ndir, nbfree, nifree, nffree = a.cg_summary(c)
            for i, v in enumerate((ndir, nbfree, nifree, nffree)):
                totals[i] += v

            blksfree = a.blksfree(c)
            tables = ufs_cg.recompute_cg_tables(g, blksfree)
            if tables.nbfree != nbfree:
                problems.append(
                    "cg %d: recomputed nbfree %d != recorded %d"
                    % (c, tables.nbfree, nbfree))
            if tables.nffree != nffree:
                problems.append(
                    "cg %d: recomputed nffree %d != recorded %d"
                    % (c, tables.nffree, nffree))

            buf = a.read_cg(c)
            recorded_frsum = struct.unpack_from(
                "<%di" % g.frag, buf, ufs_alloc.CG_FRSUM_OFF)
            if list(tables.frsum) != list(recorded_frsum):
                problems.append(
                    "cg %d: recomputed cg_frsum %s != recorded %s"
                    % (c, tables.frsum, recorded_frsum))

            inosused = a.inosused(c)
            used = _popcount(inosused, g.ipg)
            computed_nifree = g.ipg - used
            if computed_nifree != nifree:
                problems.append(
                    "cg %d: recomputed nifree %d != recorded %d"
                    % (c, computed_nifree, nifree))

            slot = struct.unpack_from("<4i", cstable, c * 16)
            if slot != (ndir, nbfree, nifree, nffree):
                problems.append(
                    "cg %d: fs_csaddr slot %s != group's own cg_cs %s"
                    % (c, slot, (ndir, nbfree, nifree, nffree)))

        recorded_total = a.fs_cstotal()
        if tuple(totals) != tuple(recorded_total):
            problems.append(
                "summed cylinder-group summaries %s != fs_cstotal %s"
                % (tuple(totals), tuple(recorded_total)))

    return problems
