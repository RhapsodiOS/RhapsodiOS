"""Free space in a fresh filesystem, handed out in ascending order.

The free regions are the ones initcg() leaves free (mkfs.c): in cylinder
group 0 everything from the end of the cylinder summary to the end of the
group, and in every later group also the stretch before its superblock
copy.  Whole blocks come out block-aligned; file tails are packed into
partly used blocks.  Nothing is ever freed.
"""
from instmedia import ufs_geometry as ug


class NoSpace(Exception):
    pass


class Space(object):
    def __init__(self, g):
        self.g = g
        # One byte per fragment of every group, 1 while it is free.
        self.free = bytearray(g.ncg * g.fpg)
        self._extents = []
        for c in range(g.ncg):
            if c > 0:
                self._extents.append((ug.cgbase(g, c), ug.cgsblock(g, c)))
            lo = ug.cgdmin(g, c)
            if c == 0:
                lo += ug.howmany(g.cssize, g.fsize)
            self._extents.append((lo, ug.cg_data_end(g, c)))
        for lo, hi in self._extents:
            self.free[lo:hi] = b"\x01" * (hi - lo)
        self._i = 0
        self._pos = 0
        self._tail = None       # (next fragment, end of block) for tails

    def _next_block(self):
        frag = self.g.frag
        while self._i < len(self._extents):
            lo, hi = self._extents[self._i]
            start = ug.roundup(max(self._pos, lo), frag)
            if start + frag <= hi:
                self._pos = start + frag
                return start
            self._i += 1
        raise NoSpace("the filesystem is full")

    def _claim(self, start, n):
        self.free[start:start + n] = bytes(n)
        return start

    def block(self):
        """First fragment of a free, block-aligned whole block."""
        return self._claim(self._next_block(), self.g.frag)

    def frags(self, n):
        """First of n < fs_frag contiguous free fragments inside one block."""
        if not 0 < n < self.g.frag:
            raise ValueError("a tail is 1 to %d fragments, not %d"
                             % (self.g.frag - 1, n))
        if self._tail is None or self._tail[0] + n > self._tail[1]:
            b = self._next_block()
            self._tail = (b, b + self.g.frag)
        start = self._tail[0]
        self._tail = (start + n, self._tail[1])
        return self._claim(start, n)

    def blksfree(self, c):
        """Group c's free-fragment bitmap, as cg_blksfree stores it."""
        base = ug.cgbase(self.g, c)
        out = bytearray(ug.howmany(self.g.fpg, 8))
        for i in range(self.g.fpg):
            if self.free[base + i]:
                out[i >> 3] |= 1 << (i & 7)
        return bytes(out)
