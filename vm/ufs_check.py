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

            btotoff, boff, _iusedoff, _freeoff = struct.unpack_from(
                "<4i", buf, ufs_alloc.CG_OFFSETS_OFF)
            recorded_blktot = struct.unpack_from("<%di" % g.cpg, buf, btotoff)
            if list(tables.blktot) != list(recorded_blktot):
                problems.append(
                    "cg %d: recomputed cg_btot %s != recorded %s"
                    % (c, tables.blktot, recorded_blktot))
            recorded_blks = struct.unpack_from(
                "<%dh" % (g.cpg * g.nrpos), buf, boff)
            if list(tables.blks) != list(recorded_blks):
                problems.append(
                    "cg %d: recomputed cg_blks %s != recorded %s"
                    % (c, tables.blks, recorded_blks))

            if g.contigsumsize > 0:
                clustersumoff, clusteroff, nclusterblks = struct.unpack_from(
                    "<3i", buf, 104)
                clustersfree, clustersum = ufs_cg.recompute_cluster_maps(
                    g, blksfree, nclusterblks)
                nclusterbytes = (g.fpg // g.frag + 7) // 8
                recorded_clustersfree = bytes(
                    buf[clusteroff:clusteroff + nclusterbytes])
                if clustersfree != recorded_clustersfree:
                    problems.append(
                        "cg %d: recomputed cg_clustersfree %s != recorded %s"
                        % (c, clustersfree, recorded_clustersfree))
                recorded_clustersum = struct.unpack_from(
                    "<%di" % len(clustersum), buf, clustersumoff)
                if list(clustersum) != list(recorded_clustersum):
                    problems.append(
                        "cg %d: recomputed cg_clustersum %s != recorded %s"
                        % (c, clustersum, recorded_clustersum))

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
