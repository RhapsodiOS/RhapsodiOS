"""Build HFS, HFS Plus and wrapped HFS Plus volume images from a manifest.

A manifest is a list of ("dir", path) and ("file", path, size) entries with
"/"-separated paths relative to the volume root; parents come before their
children.  File contents come from content.data(path, size).  A ("frag",
path, size, pieces) entry makes a file whose data is split into that many
separate extents, to force extents-overflow records.
"""

import functools
import struct
import unicodedata

import content
from hfsfmt import (
    HFS_SIG, HFSPLUS_SIG, HFSPLUS_VERSION, ROOT_PARENT_ID, ROOT_FOLDER_ID,
    EXTENTS_ID, CATALOG_ID, FIRST_USER_ID, LEAF, INDEX, HEADER,
    HFS_FOLDER, HFS_FILE, HFS_FOLDER_THREAD, HFS_FILE_THREAD,
    HP_FOLDER, HP_FILE, HP_FOLDER_THREAD, HP_FILE_THREAD, DATA_FORK,
    UNMOUNTED_BIT, unicode_compare, relstring_compare, cmp)

DATE = 3029529600            # 2000-01-01 00:00:00 in Mac time
BIG_KEYS, VAR_INDEX_KEYS = 0x2, 0x4


def _cmp_key(plus, is_catalog):
    def compare(a, b):
        if not is_catalog:
            return cmp(a, b)
        if a[0] != b[0]:
            return cmp(a[0], b[0])
        if plus:
            return unicode_compare(list(a[1]), list(b[1]))
        return relstring_compare(a[1], b[1])
    return compare


class TreeSpec(object):
    """Everything needed to lay out one B-tree file."""

    def __init__(self, plus, is_catalog, node_size, total_nodes):
        self.plus, self.is_catalog = plus, is_catalog
        self.node_size, self.total_nodes = node_size, total_nodes
        if plus:
            self.max_key = 516 if is_catalog else 10
            self.attributes = BIG_KEYS | (VAR_INDEX_KEYS if is_catalog else 0)
        else:
            self.max_key = 37 if is_catalog else 7
            self.attributes = 0


def _index_key(spec, key):
    """HFS index keys are padded to the maximum key length; HFS Plus
    catalog index keys are variable length, extents keys are fixed."""
    if spec.plus:
        return key
    k = bytes([spec.max_key]) + key[1:] + b"\0" * (spec.max_key + 1 - len(key))
    return k + b"\0" * (len(k) & 1)


def _node(kind, height, records, flink, blink, size):
    buf = bytearray(size)
    struct.pack_into(">IIbBHH", buf, 0, flink, blink, kind, height, len(records), 0)
    off = 14
    for i, r in enumerate(records):
        buf[off:off + len(r)] = r
        struct.pack_into(">H", buf, size - 2 * (i + 1), off)
        off += len(r)
    struct.pack_into(">H", buf, size - 2 * (len(records) + 1), off)
    return buf


def _fits(records, size):
    return 14 + sum(len(r) for r in records) + 2 * (len(records) + 1) <= size


def _layout(spec, records):
    """Pack sorted records into leaf and index nodes numbered from 1.
    Returns (nodes, used, depth, root, first_leaf, last_leaf, nrecords)."""
    ns = spec.node_size
    compare = _cmp_key(spec.plus, spec.is_catalog)
    records = sorted(records, key=functools.cmp_to_key(lambda a, b: compare(a[0], b[0])))
    nodes = {}                      # number -> bytearray
    next_num = [1]

    def pack_level(recs, kind, height):
        """recs: list of (first key, record bytes). Returns [(num, first key)]."""
        groups, cur = [], []
        for first, r in recs:
            if cur and not _fits([x[1] for x in cur] + [r], ns):
                groups.append(cur)
                cur = []
            cur.append((first, r))
        if cur:
            groups.append(cur)
        nums = list(range(next_num[0], next_num[0] + len(groups)))
        next_num[0] += len(groups)
        for i, g in enumerate(groups):
            flink = nums[i + 1] if i + 1 < len(groups) else 0
            blink = nums[i - 1] if i else 0
            nodes[nums[i]] = _node(kind, height, [r for _, r in g], flink, blink, ns)
        return [(nums[i], g[0][0]) for i, g in enumerate(groups)]

    depth = root = first_leaf = last_leaf = 0
    if records:
        level = pack_level([(key, key + data) for _, key, data in records], LEAF, 1)
        first_leaf, last_leaf = level[0][0], level[-1][0]
        depth = 1
        while len(level) > 1:
            depth += 1
            level = pack_level([(k, _index_key(spec, k) + struct.pack(">I", n))
                                for n, k in level], INDEX, depth)
        root = level[0][0]
    return nodes, next_num[0], depth, root, first_leaf, last_leaf, len(records)


def build_tree(spec, records, clump):
    """records: list of (sort value, key bytes, data bytes), any order.
    Returns the B-tree file bytes (total_nodes * node_size)."""
    ns = spec.node_size
    nodes, used, depth, root, first_leaf, last_leaf, nrec = _layout(spec, records)
    if used > spec.total_nodes:
        raise ValueError("B-tree needs %d nodes, has %d" % (used, spec.total_nodes))
    map_bytes = ns - 14 - 106 - 128 - 8
    if spec.total_nodes > map_bytes * 8:
        raise ValueError("B-tree too large for a header-only node map")
    header = struct.pack(">HIIIIHHIIHIBBI64x", depth, root, nrec, first_leaf,
                         last_leaf, ns, spec.max_key, spec.total_nodes,
                         spec.total_nodes - used, 0, clump, 0, 0, spec.attributes)
    bitmap = bytearray(map_bytes)
    for i in range(used):
        bitmap[i >> 3] |= 0x80 >> (i & 7)
    nodes[0] = _node(HEADER, 0, [header, b"\0" * 128, bytes(bitmap)], 0, 0, ns)
    out = bytearray(spec.total_nodes * ns)
    for n, b in nodes.items():
        out[n * ns:(n + 1) * ns] = b
    return bytes(out)


class _Alloc(object):
    """Sequential allocation-block allocator with a bitmap."""

    def __init__(self, total):
        self.total = total
        self.bits = bytearray((total + 7) // 8)
        self.next = 0

    def mark(self, start, count):
        for b in range(start, start + count):
            self.bits[b >> 3] |= 0x80 >> (b & 7)

    def take(self, count, gap=0):
        start = self.next
        if start + count > self.total:
            raise ValueError("volume full")
        self.mark(start, count)
        self.next = start + count + gap
        return start

    def used(self):
        return sum(bin(x).count("1") for x in self.bits)


def _names(manifest):
    """Assign CNIDs and parents. Returns list of dicts in manifest order."""
    ids = {"": ROOT_FOLDER_ID}
    out = []
    cnid = FIRST_USER_ID
    for ent in manifest:
        kind, path = ent[0], ent[1]
        parent, _, name = path.rpartition("/")
        item = {"kind": kind, "path": path, "name": name, "parent": ids[parent],
                "cnid": cnid, "size": ent[2] if kind != "dir" else 0,
                "pieces": ent[3] if kind == "frag" else 1}
        ids[path] = cnid
        cnid += 1
        out.append(item)
    return out, cnid


def _place_files(items, alloc, block_size):
    """Allocate every file's data; returns {cnid: [(start, count), ...]}."""
    placed = {}
    for it in items:
        if it["kind"] == "dir" or it["size"] == 0:
            placed[it["cnid"]] = []
            continue
        blocks = (it["size"] + block_size - 1) // block_size
        pieces = min(it["pieces"], blocks)
        exts = []
        for p in range(pieces):
            n = blocks // pieces + (1 if p < blocks % pieces else 0)
            exts.append((alloc.take(n, gap=1 if pieces > 1 else 0), n))
        placed[it["cnid"]] = exts
    return placed


# --------------------------------------------------------------------------
# HFS Plus

def _uni(name):
    """HFS Plus stores names in decomposed Unicode (TN1150)."""
    raw = unicodedata.normalize("NFD", name).encode("utf-16-be")
    return struct.unpack(">%dH" % (len(raw) // 2), raw)


def _plus_key(parent, name):
    units = _uni(name)
    body = struct.pack(">IH", parent, len(units)) + struct.pack(">%dH" % len(units), *units)
    return (parent, units), struct.pack(">H", len(body)) + body


def _plus_fork(size, exts, block_size):
    rec = list(exts[:8]) + [(0, 0)] * (8 - len(exts[:8]))
    total = sum(c for _, c in exts)
    return struct.pack(">QII", size, 0, total) + b"".join(struct.pack(">II", s, c) for s, c in rec)


def _plus_overflow(cnid, exts):
    """Extents-overflow records for extents beyond the first eight."""
    out = []
    done = sum(c for _, c in exts[:8])
    rest = exts[8:]
    while rest:
        chunk, rest = rest[:8], rest[8:]
        key = struct.pack(">HBBII", 10, DATA_FORK, 0, cnid, done)
        data = b"".join(struct.pack(">II", s, c) for s, c in chunk) + b"\0" * 8 * (8 - len(chunk))
        out.append(((cnid, DATA_FORK, done), key, data))
        done += sum(c for _, c in chunk)
    return out


def build_plus(manifest, size, volname="HFSPlusTest", block_size=4096,
               catalog_nodes=None, catalog_slack=8):
    """An HFS Plus volume image of `size` bytes."""
    total = size // block_size
    items, next_cnid = _names(manifest)
    alloc = _Alloc(total)
    alloc.take(1)                                   # boot blocks + volume header
    alloc.mark(total - 1, 1)                        # alternate volume header
    bitmap_blocks = ((total + 7) // 8 + block_size - 1) // block_size
    a_start = alloc.take(bitmap_blocks)
    x_nodes, x_ns = 16, 1024
    x_blocks = x_nodes * x_ns // block_size
    x_start = alloc.take(x_blocks)
    kids = {}
    for it in items:
        kids[it["parent"]] = kids.get(it["parent"], 0) + 1
    c_ns = 4096
    # records need file extents, which need the catalog placed first: size it
    # from a trial layout with dummy extents
    def catalog_records(placed):
        out = []
        sv, k = _plus_key(ROOT_PARENT_ID, volname)
        out.append((sv, k, _plus_folder(ROOT_FOLDER_ID, kids.get(ROOT_FOLDER_ID, 0))))
        sv, k = _plus_key(ROOT_FOLDER_ID, "")
        out.append((sv, k, _plus_thread(HP_FOLDER_THREAD, ROOT_PARENT_ID, volname)))
        for it in items:
            sv, k = _plus_key(it["parent"], it["name"])
            if it["kind"] == "dir":
                out.append((sv, k, _plus_folder(it["cnid"], kids.get(it["cnid"], 0))))
                tt = HP_FOLDER_THREAD
            else:
                exts = placed[it["cnid"]]
                out.append((sv, k, _plus_file(it["cnid"], it["size"], exts, block_size)))
                tt = HP_FILE_THREAD
            sv, k = _plus_key(it["cnid"], "")
            out.append((sv, k, _plus_thread(tt, it["parent"], it["name"])))
        return out
    trial = catalog_records({it["cnid"]: [] for it in items})
    need = _count_nodes(TreeSpec(True, True, c_ns, 1 << 20), trial)
    if catalog_nodes is None:
        catalog_nodes = need + catalog_slack
        per_block = max(1, block_size // c_ns)
        catalog_nodes += (-catalog_nodes) % per_block
    c_blocks = catalog_nodes * c_ns // block_size
    c_start = alloc.take(c_blocks)
    placed = _place_files(items, alloc, block_size)
    recs = catalog_records(placed)
    ovf = []
    for it in items:
        ovf += _plus_overflow(it["cnid"], placed.get(it["cnid"], []))
    ext_tree = build_tree(TreeSpec(True, False, x_ns, x_nodes), ovf, x_ns * 4)
    cat_tree = build_tree(TreeSpec(True, True, c_ns, catalog_nodes), recs, c_ns * 4)
    img = bytearray(total * block_size)
    img[a_start * block_size:a_start * block_size + len(alloc.bits)] = alloc.bits
    img[x_start * block_size:x_start * block_size + len(ext_tree)] = ext_tree
    img[c_start * block_size:c_start * block_size + len(cat_tree)] = cat_tree
    for it in items:
        if it["kind"] != "dir" and it["size"]:
            data = content.data(it["path"], it["size"])
            pos = 0
            for s, c in placed[it["cnid"]]:
                chunk = data[pos:pos + c * block_size]
                img[s * block_size:s * block_size + len(chunk)] = chunk
                pos += c * block_size
    files = sum(1 for it in items if it["kind"] != "dir")
    folders = sum(1 for it in items if it["kind"] == "dir")
    vh = struct.pack(">HHI4sIIIIIIIIIIIIIIIQ32x", HFSPLUS_SIG, HFSPLUS_VERSION,
                     UNMOUNTED_BIT, b"8.10", 0, DATE, DATE, 0, DATE, files, folders,
                     block_size, total, total - alloc.used(), alloc.next,
                     block_size * 4, block_size * 4, next_cnid, 0, 1)
    assert len(vh) == 112
    vh += _plus_fork(bitmap_blocks * block_size, [(a_start, bitmap_blocks)], block_size)
    vh += _plus_fork(len(ext_tree), [(x_start, x_blocks)], block_size)
    vh += _plus_fork(len(cat_tree), [(c_start, c_blocks)], block_size)
    vh += _plus_fork(0, [], block_size) * 2
    vh = vh.ljust(512, b"\0")
    img[1024:1536] = vh
    img[len(img) - 1024:len(img) - 512] = vh
    return bytes(img)


def _plus_folder(cnid, valence):
    return struct.pack(">hHIIIIIII16x16x16xII", HP_FOLDER, 0, valence, cnid,
                       DATE, DATE, DATE, DATE, 0, 0, 0)


def _plus_file(cnid, size, exts, block_size):
    head = struct.pack(">hHIIIIIII16x16x16xII", HP_FILE, 0x0002, 0, cnid,
                       DATE, DATE, DATE, DATE, 0, 0, 0)
    return head + _plus_fork(size, exts, block_size) + _plus_fork(0, [], block_size)


def _plus_thread(ttype, parent, name):
    units = _uni(name)
    return struct.pack(">hhIH", ttype, 0, parent, len(units)) + \
        struct.pack(">%dH" % len(units), *units)


def _count_nodes(spec, records):
    return _layout(spec, records)[1]


# --------------------------------------------------------------------------
# HFS

def _roman(name):
    return name.encode("mac_roman")


def _hfs_key(parent, name):
    n = _roman(name)
    body = struct.pack(">BIB", 0, parent, len(n)) + n
    k = bytes([len(body)]) + body
    return (parent, n), k + b"\0" * (len(k) & 1)


def _hfs_ext(exts):
    rec = list(exts[:3]) + [(0, 0)] * (3 - len(exts[:3]))
    return b"".join(struct.pack(">HH", s, c) for s, c in rec)


def _hfs_overflow(cnid, exts):
    out = []
    done = sum(c for _, c in exts[:3])
    rest = exts[3:]
    while rest:
        chunk, rest = rest[:3], rest[3:]
        key = struct.pack(">BBIH", 7, DATA_FORK, cnid, done)
        out.append(((cnid, DATA_FORK, done), key, _hfs_ext(chunk)))
        done += sum(c for _, c in chunk)
    return out


def _hfs_folder(cnid, valence):
    return struct.pack(">hHHIIII16x16x16x", HFS_FOLDER, 0, valence, cnid, DATE, DATE, 0)


def _hfs_file(cnid, size, exts, block_size):
    phys = sum(c for _, c in exts) * block_size
    return (struct.pack(">hbb16xIHII", HFS_FILE, 0x02, 0, cnid, 0, size, phys)
            + struct.pack(">HIIIII16xH", 0, 0, 0, DATE, DATE, 0, 0)
            + _hfs_ext(exts[:3]) + _hfs_ext([]) + b"\0\0\0\0")


def _hfs_thread(ttype, parent, name):
    n = _roman(name)
    return struct.pack(">h8xIB", ttype, parent, len(n)) + n + b"\0" * (31 - len(n))


def build_hfs(manifest, size, volname="HFSTest", block_size=1024, catalog_slack=16):
    """An HFS (standard) volume image of `size` bytes."""
    sectors = size // 512
    vbm_st = 3
    # allocation blocks start after the bitmap; leave the last two sectors
    # (alternate MDB and one spare) outside the allocation area
    total = (sectors - vbm_st - 2) * 512 // block_size
    bitmap_sectors = (total + 4095) // 4096
    al_bl_st = vbm_st + bitmap_sectors
    total = min(total, (sectors - al_bl_st - 2) * 512 // block_size, 65535)
    items, next_cnid = _names(manifest)
    alloc = _Alloc(total)
    x_ns, x_nodes = 512, 16
    x_blocks = x_nodes * x_ns // block_size
    x_start = alloc.take(x_blocks)
    kids = {}
    for it in items:
        kids[it["parent"]] = kids.get(it["parent"], 0) + 1

    def catalog_records(placed):
        out = []
        sv, k = _hfs_key(ROOT_PARENT_ID, volname)
        out.append((sv, k, _hfs_folder(ROOT_FOLDER_ID, kids.get(ROOT_FOLDER_ID, 0))))
        sv, k = _hfs_key(ROOT_FOLDER_ID, "")
        out.append((sv, k, _hfs_thread(HFS_FOLDER_THREAD, ROOT_PARENT_ID, volname)))
        for it in items:
            sv, k = _hfs_key(it["parent"], it["name"])
            if it["kind"] == "dir":
                out.append((sv, k, _hfs_folder(it["cnid"], kids.get(it["cnid"], 0))))
                tt = HFS_FOLDER_THREAD
            else:
                out.append((sv, k, _hfs_file(it["cnid"], it["size"], placed[it["cnid"]], block_size)))
                tt = HFS_FILE_THREAD
            sv, k = _hfs_key(it["cnid"], "")
            out.append((sv, k, _hfs_thread(tt, it["parent"], it["name"])))
        return out
    c_ns = 512
    trial = catalog_records({it["cnid"]: [] for it in items})
    catalog_nodes = _count_nodes(TreeSpec(False, True, c_ns, 1 << 12), trial) + catalog_slack
    catalog_nodes += (-catalog_nodes) % max(1, block_size // c_ns)
    c_blocks = catalog_nodes * c_ns // block_size
    c_start = alloc.take(c_blocks)
    placed = _place_files(items, alloc, block_size)
    ovf = []
    for it in items:
        ovf += _hfs_overflow(it["cnid"], placed.get(it["cnid"], []))
    ext_tree = build_tree(TreeSpec(False, False, x_ns, x_nodes), ovf, x_ns * 4)
    cat_tree = build_tree(TreeSpec(False, True, c_ns, catalog_nodes), catalog_records(placed), c_ns * 4)
    img = bytearray(sectors * 512)
    base = al_bl_st * 512
    img[vbm_st * 512:vbm_st * 512 + len(alloc.bits)] = alloc.bits
    img[base + x_start * block_size:base + x_start * block_size + len(ext_tree)] = ext_tree
    img[base + c_start * block_size:base + c_start * block_size + len(cat_tree)] = cat_tree
    for it in items:
        if it["kind"] != "dir" and it["size"]:
            data = content.data(it["path"], it["size"])
            pos = 0
            for s, c in placed[it["cnid"]]:
                chunk = data[pos:pos + c * block_size]
                img[base + s * block_size:base + s * block_size + len(chunk)] = chunk
                pos += c * block_size
    root_files = sum(1 for it in items if it["parent"] == ROOT_FOLDER_ID and it["kind"] != "dir")
    root_dirs = sum(1 for it in items if it["parent"] == ROOT_FOLDER_ID and it["kind"] == "dir")
    files = sum(1 for it in items if it["kind"] != "dir")
    folders = sum(1 for it in items if it["kind"] == "dir")
    vn = _roman(volname)
    mdb = struct.pack(">HIIHHHHHIIHIHB27s", HFS_SIG, DATE, DATE, UNMOUNTED_BIT, root_files,
                      vbm_st, 0, total, block_size, block_size * 4, al_bl_st,
                      next_cnid, total - alloc.used(), len(vn), vn)
    mdb += struct.pack(">IHIIIHII32xHHH", 0, 0, 0, block_size * 4, block_size * 4,
                       root_dirs, files, folders, 0, 0, 0)
    mdb += struct.pack(">I", len(ext_tree)) + _hfs_ext([(x_start, x_blocks)])
    mdb += struct.pack(">I", len(cat_tree)) + _hfs_ext([(c_start, c_blocks)])
    assert len(mdb) == 162, len(mdb)
    img[1024:1024 + 162] = mdb
    img[len(img) - 1024:len(img) - 1024 + 162] = mdb
    return bytes(img)


# --------------------------------------------------------------------------
# HFS Plus wrapped in HFS

def build_wrapped(manifest, size, volname="WrappedTest", wrapper_block=4096, **kw):
    """An HFS wrapper whose one allocated extent is an HFS Plus volume."""
    sectors = size // 512
    vbm_st = 3
    total = (sectors - vbm_st - 2) * 512 // wrapper_block
    bitmap_sectors = (total + 4095) // 4096
    al_bl_st = vbm_st + bitmap_sectors
    total = (sectors - al_bl_st - 2) * 512 // wrapper_block
    embed_start, embed_count = 0, total
    plus = build_plus(manifest, embed_count * wrapper_block, volname=volname, **kw)
    img = bytearray(sectors * 512)
    bits = bytearray(bitmap_sectors * 512)
    for b in range(embed_count):
        bits[b >> 3] |= 0x80 >> (b & 7)
    img[vbm_st * 512:vbm_st * 512 + len(bits)] = bits
    off = al_bl_st * 512 + embed_start * wrapper_block
    img[off:off + len(plus)] = plus
    vn = _roman(volname)
    mdb = struct.pack(">HIIHHHHHIIHIHB27s", HFS_SIG, DATE, DATE,
                      0x8300, 0,
                      vbm_st, 0, total, wrapper_block, wrapper_block, al_bl_st,
                      FIRST_USER_ID, 0, len(vn), vn)
    mdb += struct.pack(">IHIIIHII32xHHH", 0, 0, 0, wrapper_block, wrapper_block,
                       0, 0, 0, HFSPLUS_SIG, embed_start, embed_count)
    mdb += struct.pack(">I", 0) + _hfs_ext([]) + struct.pack(">I", 0) + _hfs_ext([])
    assert len(mdb) == 162
    img[1024:1024 + 162] = mdb
    img[len(img) - 1024:len(img) - 1024 + 162] = mdb
    return bytes(img)


def build_plus8k(manifest, size):
    """HFS Plus with 8K allocation blocks, twice i386's 4K logical block."""
    return build_plus(manifest, size, block_size=8192)


BUILDERS = {"hfs": build_hfs, "hfsplus": build_plus, "wrapped": build_wrapped,
            "hfsplus8k": build_plus8k}
