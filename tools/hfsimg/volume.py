"""Read-only access to an HFS, HFS Plus or wrapped HFS Plus volume image."""

import struct

from hfsfmt import (
    HFS_SIG, HFSPLUS_SIG, EXTENTS_ID, CATALOG_ID, ALLOCATION_ID, STARTUP_ID,
    ATTRIBUTES_ID, ROOT_FOLDER_ID, LEAF, INDEX, HEADER, MAP,
    HFS_FOLDER, HFS_FILE, HFS_FOLDER_THREAD, HFS_FILE_THREAD,
    HP_FOLDER, HP_FILE, HP_FOLDER_THREAD, HP_FILE_THREAD, DATA_FORK, RSRC_FORK,
    MDB, VolumeHeader, ForkData, Extent, hfs_extents, plus_extents, plus_fork,
    u8, s8, u16, s16, u32, unicode_compare, relstring_compare, cmp)


class FormatError(Exception):
    pass


class Node(object):
    """One B-tree node: descriptor, record offsets and raw bytes."""

    def __init__(self, num, raw):
        self.num = num
        self.raw = raw
        self.flink = u32(raw, 0)
        self.blink = u32(raw, 4)
        self.kind = s8(raw, 8)
        self.height = u8(raw, 9)
        self.nrecs = u16(raw, 10)
        size = len(raw)
        if 14 + 2 * (self.nrecs + 1) > size:
            raise FormatError("node %d: %d records cannot fit" % (num, self.nrecs))
        # offsets[i] is the start of record i; offsets[nrecs] is free space
        self.offsets = [u16(raw, size - 2 * (i + 1)) for i in range(self.nrecs + 1)]

    def record(self, i):
        return self.raw[self.offsets[i]:self.offsets[i + 1]]


class BTree(object):
    """A catalog or extents B-tree, read whole into memory."""

    def __init__(self, vol, file_id, data):
        self.vol = vol
        self.file_id = file_id
        self.data = data
        if len(data) < 512:
            raise FormatError("B-tree %d: file is %d bytes" % (file_id, len(data)))
        h = data[14:14 + 106]
        self.tree_depth = u16(h, 0)
        self.root_node = u32(h, 2)
        self.leaf_records = u32(h, 6)
        self.first_leaf = u32(h, 10)
        self.last_leaf = u32(h, 14)
        self.node_size = u16(h, 18)
        self.max_key_length = u16(h, 20)
        self.total_nodes = u32(h, 22)
        self.free_nodes = u32(h, 26)
        self.clump_size = u32(h, 32)
        self.btree_type = u8(h, 36)
        self.attributes = u32(h, 38)
        if self.node_size not in (512, 1024, 2048, 4096, 8192, 16384, 32768):
            raise FormatError("B-tree %d: node size %d" % (file_id, self.node_size))

    def node(self, n):
        ns = self.node_size
        if n >= self.total_nodes or (n + 1) * ns > len(self.data):
            raise FormatError("B-tree %d: node %d out of range" % (self.file_id, n))
        return Node(n, self.data[n * ns:(n + 1) * ns])

    # --- keys -----------------------------------------------------------
    def split(self, rec):
        """(key bytes including its length field, data bytes) of a record."""
        if self.vol.plus:
            klen = u16(rec, 0)
            return rec[:2 + klen], rec[2 + klen:]
        klen = u8(rec, 0)
        return rec[:1 + klen], rec[(klen + 2) & ~1:]

    def key_value(self, key):
        """A comparable tuple for a key, following the kernel's compare."""
        if self.file_id == EXTENTS_ID:
            if self.vol.plus:
                return (u32(key, 4), u8(key, 2), u32(key, 8))
            return (u32(key, 2), u8(key, 1), u16(key, 6))
        if self.vol.plus:
            n = u16(key, 6)
            return (u32(key, 2), tuple(struct.unpack_from(">%dH" % n, key, 8)))
        return (u32(key, 2), bytes(key[7:7 + key[6]]))

    def compare(self, a, b):
        """-1/0/1 for two key_value tuples, as the kernel orders them."""
        if self.file_id == EXTENTS_ID:
            return cmp(a, b)
        if a[0] != b[0]:
            return cmp(a[0], b[0])
        if self.vol.plus:
            return unicode_compare(list(a[1]), list(b[1]))
        return relstring_compare(a[1], b[1])

    def leaf_records_iter(self):
        """Yield (key_value, key bytes, data bytes) in leaf-chain order."""
        n = self.first_leaf
        seen = set()
        while n:
            if n in seen:
                raise FormatError("B-tree %d: leaf chain loops at %d" % (self.file_id, n))
            seen.add(n)
            node = self.node(n)
            for i in range(node.nrecs):
                k, d = self.split(node.record(i))
                yield self.key_value(k), k, d
            n = node.flink


class Entry(object):
    """A catalog file or folder."""

    def __init__(self, cnid, parent, name, is_dir):
        self.cnid, self.parent, self.name, self.is_dir = cnid, parent, name, is_dir
        self.valence = 0
        self.data = None
        self.rsrc = None
        self.thread = None      # (type, parent, name) from the thread record
        self.thread_expected = True


class Volume(object):
    def __init__(self, path, offset=0):
        self.f = open(path, "rb")
        self.path = path
        self.base = offset
        self.wrapper = None
        head = self.read_at(offset + 1024, 512)
        sig = u16(head, 0)
        if sig == HFSPLUS_SIG:
            self._init_plus(offset, head)
        elif sig == HFS_SIG:
            mdb = MDB(head)
            if mdb.embed_sig == HFSPLUS_SIG:
                self.wrapper = mdb
                plus_base = (offset + mdb.al_bl_st * 512
                             + mdb.embed_start * mdb.al_blk_siz)
                self._init_plus(plus_base, self.read_at(plus_base + 1024, 512))
            else:
                self._init_hfs(offset, mdb)
        else:
            raise FormatError("no HFS signature at %d (found 0x%04x)" % (offset + 1024, sig))
        self._overflow = None
        self.extents = BTree(self, EXTENTS_ID, self.read_fork(self.special_fork(EXTENTS_ID), EXTENTS_ID))
        self.catalog = BTree(self, CATALOG_ID, self.read_fork(self.special_fork(CATALOG_ID), CATALOG_ID))

    def close(self):
        self.f.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def read_at(self, off, n):
        self.f.seek(off)
        b = self.f.read(n)
        if len(b) != n:
            raise FormatError("short read at %d" % off)
        return b

    def _init_plus(self, base, head):
        self.plus = True
        self.vh = VolumeHeader(head)
        if self.vh.sig != HFSPLUS_SIG:
            raise FormatError("embedded volume has no H+ signature")
        self.vol_base = base
        self.block_size = self.vh.block_size
        self.total_blocks = self.vh.total_blocks
        self.free_blocks = self.vh.free_blocks
        self.alloc_base = base

    def _init_hfs(self, base, mdb):
        self.plus = False
        self.mdb = mdb
        self.vol_base = base
        self.block_size = mdb.al_blk_siz
        self.total_blocks = mdb.nm_al_blks
        self.free_blocks = mdb.free_bks
        self.alloc_base = base + mdb.al_bl_st * 512

    def block_offset(self, n):
        return self.alloc_base + n * self.block_size

    # --- forks ----------------------------------------------------------
    def special_fork(self, file_id):
        if self.plus:
            return {EXTENTS_ID: self.vh.extents_file, CATALOG_ID: self.vh.catalog_file,
                    ALLOCATION_ID: self.vh.allocation_file,
                    STARTUP_ID: self.vh.startup_file,
                    ATTRIBUTES_ID: self.vh.attributes_file}[file_id]
        m = self.mdb
        size, ext = {EXTENTS_ID: (m.xt_fl_size, m.xt_ext_rec),
                     CATALOG_ID: (m.ct_fl_size, m.ct_ext_rec)}[file_id]
        return ForkData(size, sum(e.count for e in ext), ext)

    def overflow_extents(self, file_id, fork_type):
        """Extents-overflow records for one fork, in startBlock order."""
        if file_id == EXTENTS_ID:
            return []
        out = []
        for kv, key, data in self.extents.leaf_records_iter():
            if kv[0] == file_id and kv[1] == fork_type:
                ext = plus_extents(data, 0) if self.plus else hfs_extents(data, 0)
                out.append((kv[2], ext))
        return out

    def fork_extents(self, fork, file_id, fork_type=DATA_FORK):
        """Every extent of a fork, first record plus overflow, in order."""
        exts = [e for e in fork.extents if e.count]
        for start, ext in self.overflow_extents(file_id, fork_type):
            if start != sum(e.count for e in exts):
                raise FormatError("file %d fork %d: overflow record at block %d, expected %d"
                                  % (file_id, fork_type, start, sum(e.count for e in exts)))
            exts.extend(e for e in ext if e.count)
        return exts

    def read_fork(self, fork, file_id, fork_type=DATA_FORK):
        if file_id == EXTENTS_ID or not hasattr(self, "extents"):
            exts = [e for e in fork.extents if e.count]
        else:
            exts = self.fork_extents(fork, file_id, fork_type)
        chunks = []
        for e in exts:
            chunks.append(self.read_at(self.block_offset(e.start), e.count * self.block_size))
        data = b"".join(chunks)
        if len(data) < fork.logical_size:
            raise FormatError("file %d: fork holds %d bytes, logical size %d"
                              % (file_id, len(data), fork.logical_size))
        return data[:fork.logical_size]

    # --- catalog --------------------------------------------------------
    def entries(self):
        """Every catalog file and folder, keyed by CNID."""
        ents = {}
        threads = {}
        for kv, key, d in self.catalog.leaf_records_iter():
            parent, name = kv
            rtype = s16(d, 0)
            if self.plus:
                if rtype == HP_FOLDER:
                    e = Entry(u32(d, 8), parent, name, True)
                    e.valence = u32(d, 4)
                elif rtype == HP_FILE:
                    e = Entry(u32(d, 8), parent, name, False)
                    e.data, e.rsrc = plus_fork(d, 88), plus_fork(d, 168)
                elif rtype in (HP_FOLDER_THREAD, HP_FILE_THREAD):
                    n = u16(d, 8)
                    threads[parent] = (rtype, u32(d, 4),
                                       tuple(struct.unpack_from(">%dH" % n, d, 10)))
                    continue
                else:
                    raise FormatError("catalog record type %d" % rtype)
            else:
                if rtype == HFS_FOLDER:
                    e = Entry(u32(d, 6), parent, name, True)
                    e.valence = u16(d, 4)
                elif rtype == HFS_FILE:
                    e = Entry(u32(d, 20), parent, name, False)
                    e.thread_expected = bool(d[2] & 0x02)    # kHFSThreadExistsMask
                    e.data = ForkData(u32(d, 26), 0, hfs_extents(d, 74))
                    e.rsrc = ForkData(u32(d, 36), 0, hfs_extents(d, 86))
                elif rtype in (HFS_FOLDER_THREAD, HFS_FILE_THREAD):
                    threads[parent] = (rtype, u32(d, 10), bytes(d[15:15 + d[14]]))
                    continue
                else:
                    raise FormatError("catalog record type 0x%04x" % rtype)
            ents[e.cnid] = e
        for cnid, t in threads.items():
            if cnid in ents:
                ents[cnid].thread = t
        self.threads = threads
        return ents

    def name_str(self, name):
        if self.plus:
            return struct.pack(">%dH" % len(name), *name).decode("utf-16-be")
        return name.decode("mac_roman")

    def walk(self):
        """Yield (path, Entry) for everything under the root, sorted by path."""
        ents = self.entries()
        kids = {}
        for e in ents.values():
            kids.setdefault(e.parent, []).append(e)
        out = []

        def rec(cnid, prefix):
            for e in kids.get(cnid, []):
                p = prefix + "/" + self.name_str(e.name)
                out.append((p, e))
                if e.is_dir:
                    rec(e.cnid, p)
        rec(ROOT_FOLDER_ID, "")
        return sorted(out, key=lambda t: t[0])

    def read_file(self, entry):
        return self.read_fork(entry.data, entry.cnid, DATA_FORK)
