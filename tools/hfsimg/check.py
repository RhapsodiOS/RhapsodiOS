"""Consistency checks for an HFS or HFS Plus volume image.

check(volume) returns a list of human-readable problems; an empty list means
the volume is consistent.  It checks what the kernel's writes can break: B-tree
structure, key order, node maps, the allocation bitmap against every extent,
folder valences, thread records and the volume counts.
"""

from hfsfmt import (
    EXTENTS_ID, CATALOG_ID, ALLOCATION_ID, STARTUP_ID, ATTRIBUTES_ID,
    BADBLOCK_ID, ROOT_FOLDER_ID, ROOT_PARENT_ID, LEAF, INDEX, HEADER, MAP,
    DATA_FORK, RSRC_FORK, UNMOUNTED_BIT, u16, u32)
from volume import FormatError


def _map_bits(tree, problems):
    """The node allocation map: header record 2, then chained map nodes."""
    tag = "B-tree %d" % tree.file_id
    hdr = tree.node(0)
    bits = bytearray(hdr.record(2))
    n = hdr.flink
    seen = {0}
    while n:
        if n in seen:
            problems.append("%s: map node chain loops at %d" % (tag, n))
            break
        seen.add(n)
        node = tree.node(n)
        if node.kind != MAP:
            problems.append("%s: node %d in the map chain has kind %d" % (tag, n, node.kind))
            break
        bits += node.record(0)
        n = node.flink
    used = set(i for i in range(min(tree.total_nodes, len(bits) * 8))
               if bits[i >> 3] & (0x80 >> (i & 7)))
    return used, seen


def check_btree(tree, problems):
    tag = "B-tree %d" % tree.file_id
    ns = tree.node_size
    if tree.total_nodes * ns != len(tree.data):
        problems.append("%s: totalNodes*nodeSize %d != file size %d"
                        % (tag, tree.total_nodes * ns, len(tree.data)))
    hdr = tree.node(0)
    if hdr.kind != HEADER or hdr.nrecs != 3:
        problems.append("%s: node 0 is not a 3-record header node" % tag)
        return
    used, map_nodes = _map_bits(tree, problems)
    if tree.free_nodes != tree.total_nodes - len(used):
        problems.append("%s: freeNodes %d, map says %d"
                        % (tag, tree.free_nodes, tree.total_nodes - len(used)))

    def node_ok(node):
        offs = node.offsets
        if offs[0] != 14:
            problems.append("%s: node %d first record at %d" % (tag, node.num, offs[0]))
            return False
        for i in range(node.nrecs):
            if offs[i + 1] <= offs[i]:
                problems.append("%s: node %d offsets not increasing at %d" % (tag, node.num, i))
                return False
        if offs[node.nrecs] > ns - 2 * (node.nrecs + 1):
            problems.append("%s: node %d records overlap the offset table" % (tag, node.num))
            return False
        return True

    reached = set(map_nodes)
    leaves = []
    total_leaf_records = 0
    if tree.root_node == 0:
        if tree.leaf_records or tree.tree_depth:
            problems.append("%s: empty tree with leafRecords/treeDepth set" % tag)
    else:
        # walk down from the root: (node number, expected height, lower bound key)
        stack = [(tree.root_node, tree.tree_depth, None)]
        while stack:
            num, height, first_key = stack.pop()
            if num in reached:
                problems.append("%s: node %d reached twice" % (tag, num))
                continue
            reached.add(num)
            node = tree.node(num)
            if node.height != height:
                problems.append("%s: node %d height %d, expected %d" % (tag, num, node.height, height))
            want = LEAF if height == 1 else INDEX
            if node.kind != want:
                problems.append("%s: node %d kind %d, expected %d" % (tag, num, node.kind, want))
                continue
            if not node_ok(node):
                continue
            keys = []
            for i in range(node.nrecs):
                k, d = tree.split(node.record(i))
                keys.append((tree.key_value(k), d))
            for i in range(1, len(keys)):
                if tree.compare(keys[i - 1][0], keys[i][0]) >= 0:
                    problems.append("%s: node %d keys out of order at record %d" % (tag, num, i))
            if first_key is not None and keys and tree.compare(first_key, keys[0][0]) != 0:
                problems.append("%s: node %d first key differs from its index key" % (tag, num))
            if node.kind == LEAF:
                leaves.append(num)
                total_leaf_records += node.nrecs
            else:
                for kv, d in reversed(keys):
                    stack.append((u32(d, 0), height - 1, kv))
    if total_leaf_records != tree.leaf_records:
        problems.append("%s: header leafRecords %d, tree holds %d"
                        % (tag, tree.leaf_records, total_leaf_records))
    # the leaf chain must visit the same leaves, in key order, doubly linked
    chain = []
    n, prev = tree.first_leaf, 0
    while n and len(chain) <= len(leaves):
        node = tree.node(n)
        if node.blink != prev:
            problems.append("%s: leaf %d blink %d, expected %d" % (tag, n, node.blink, prev))
        chain.append(n)
        prev, n = n, node.flink
    if sorted(chain) != sorted(leaves):
        problems.append("%s: leaf chain %s does not match the tree's leaves %s"
                        % (tag, chain[:8], sorted(leaves)[:8]))
    if leaves and chain and chain[-1] != tree.last_leaf:
        problems.append("%s: lastLeafNode %d, chain ends at %d" % (tag, tree.last_leaf, chain[-1]))
    prev_key = None
    for kv, k, d in tree.leaf_records_iter():
        if prev_key is not None and tree.compare(prev_key, kv) >= 0:
            problems.append("%s: leaf chain keys out of order" % tag)
            break
        prev_key = kv
    if reached != used:
        extra, missing = sorted(used - reached), sorted(reached - used)
        if extra:
            problems.append("%s: map marks unused nodes %s" % (tag, extra[:8]))
        if missing:
            problems.append("%s: map misses used nodes %s" % (tag, missing[:8]))


def _claim(owner, exts, claimed, problems, total):
    for e in exts:
        for b in range(e.start, e.start + e.count):
            if b >= total:
                problems.append("%s: block %d beyond the volume" % (owner, b))
                return
            if b in claimed:
                problems.append("%s: block %d also belongs to %s" % (owner, b, claimed[b]))
                return
            claimed[b] = owner


def check_allocation(vol, ents, problems):
    total = vol.total_blocks
    claimed = {}
    specials = [EXTENTS_ID, CATALOG_ID]
    if vol.plus:
        specials += [ALLOCATION_ID, STARTUP_ID, ATTRIBUTES_ID]
    for fid in specials:
        fork = vol.special_fork(fid)
        _claim("special file %d" % fid, vol.fork_extents(fork, fid), claimed, problems, total)
    for e in ents.values():
        if e.is_dir:
            continue
        for fork, ftype in ((e.data, DATA_FORK), (e.rsrc, RSRC_FORK)):
            exts = vol.fork_extents(fork, e.cnid, ftype)
            blocks = sum(x.count for x in exts)
            if blocks * vol.block_size < fork.logical_size:
                problems.append("file %d fork %d: %d blocks hold less than %d bytes"
                                % (e.cnid, ftype, blocks, fork.logical_size))
            _claim("file %d fork %d" % (e.cnid, ftype), exts, claimed, problems, total)
    if vol.plus:
        # blocks holding the first 1536 bytes and the last 1024 bytes of the volume
        bs = vol.block_size
        reserved = set(range(0, (1536 + bs - 1) // bs))
        end = total * bs
        reserved |= set(range((end - 1024) // bs, total))
        for b in reserved:
            if b in claimed:
                problems.append("reserved block %d belongs to %s" % (b, claimed[b]))
            claimed.setdefault(b, "volume header area")
        bitmap = vol.read_fork(vol.vh.allocation_file, ALLOCATION_ID)
    else:
        m = vol.mdb
        nbytes = (total + 7) // 8
        bitmap = vol.read_at(vol.vol_base + m.vbm_st * 512, nbytes)
    set_bits = set(b for b in range(total) if bitmap[b >> 3] & (0x80 >> (b & 7)))
    orphan = sorted(set_bits - set(claimed))
    lost = sorted(set(claimed) - set_bits)
    if orphan:
        problems.append("bitmap marks %d unowned blocks, first %s" % (len(orphan), orphan[:8]))
    if lost:
        problems.append("bitmap misses %d owned blocks, first %s" % (len(lost), lost[:8]))
    if vol.free_blocks != total - len(set_bits):
        problems.append("free block count %d, bitmap says %d"
                        % (vol.free_blocks, total - len(set_bits)))


def check_catalog(vol, ents, problems):
    children = {}
    for e in ents.values():
        children.setdefault(e.parent, []).append(e)
    if ROOT_FOLDER_ID not in ents or ents[ROOT_FOLDER_ID].parent != ROOT_PARENT_ID:
        problems.append("catalog: no root folder")
    for e in ents.values():
        if e.thread is None:
            if e.thread_expected:
                problems.append("catalog: CNID %d has no thread record" % e.cnid)
        elif e.thread[1] != e.parent or e.thread[2] != e.name:
            problems.append("catalog: CNID %d thread record disagrees with its key" % e.cnid)
        if e.is_dir and e.valence != len(children.get(e.cnid, [])):
            problems.append("catalog: folder %d valence %d, holds %d"
                            % (e.cnid, e.valence, len(children.get(e.cnid, []))))
        if e.cnid != ROOT_FOLDER_ID and e.parent not in ents:
            problems.append("catalog: CNID %d parent %d missing" % (e.cnid, e.parent))
    for cnid in vol.threads:
        if cnid not in ents:
            problems.append("catalog: thread record for missing CNID %d" % cnid)
    files = sum(1 for e in ents.values() if not e.is_dir)
    folders = sum(1 for e in ents.values() if e.is_dir) - 1
    max_id = max(ents) if ents else 0
    if vol.plus:
        vh = vol.vh
        if vh.file_count != files or vh.folder_count != folders:
            problems.append("volume header counts %d files %d folders, catalog has %d/%d"
                            % (vh.file_count, vh.folder_count, files, folders))
        if vh.next_catalog_id <= max_id:
            problems.append("nextCatalogID %d not above %d" % (vh.next_catalog_id, max_id))
    else:
        m = vol.mdb
        root_kids = children.get(ROOT_FOLDER_ID, [])
        if m.fil_cnt != files or m.dir_cnt != folders:
            problems.append("MDB counts %d files %d folders, catalog has %d/%d"
                            % (m.fil_cnt, m.dir_cnt, files, folders))
        if m.nm_fls != sum(1 for e in root_kids if not e.is_dir) or \
                m.nm_rt_dirs != sum(1 for e in root_kids if e.is_dir):
            problems.append("MDB root counts disagree with the catalog")
        if m.nxt_cnid <= max_id:
            problems.append("drNxtCNID %d not above %d" % (m.nxt_cnid, max_id))


def check(vol):
    problems = []
    try:
        attrs = vol.vh.attributes if vol.plus else vol.mdb.atrb
        if not attrs & UNMOUNTED_BIT:
            problems.append("volume was not cleanly unmounted")
        check_btree(vol.extents, problems)
        check_btree(vol.catalog, problems)
        ents = vol.entries()
        check_catalog(vol, ents, problems)
        check_allocation(vol, ents, problems)
    except FormatError as e:
        problems.append("format error: %s" % e)
    return problems
