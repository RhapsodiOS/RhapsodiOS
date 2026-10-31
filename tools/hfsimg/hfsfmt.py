"""HFS and HFS Plus on-disk constants, key ordering and record layouts.

Everything on disk is big-endian.  Layouts follow Inside Macintosh: Files
(HFS) and Apple Technical Note TN1150 (HFS Plus).  Name ordering uses the
kernel's own tables, parsed out of UCStringCompareData.h, so these tools and
kernel-7 cannot disagree about which key sorts first.
"""

import os
import re
import struct

REPO = os.environ.get("HFSIMG_REPO") or os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TABLES = os.path.join(REPO, "src", "kernel-7", "bsd", "hfs", "hfscommon",
                      "Unicode", "UCStringCompareData.h")

HFS_SIG = 0x4244            # 'BD'
HFSPLUS_SIG = 0x482B        # 'H+'
HFSPLUS_VERSION = 4

ROOT_PARENT_ID = 1
ROOT_FOLDER_ID = 2
EXTENTS_ID = 3
CATALOG_ID = 4
BADBLOCK_ID = 5
ALLOCATION_ID = 6
STARTUP_ID = 7
ATTRIBUTES_ID = 8
FIRST_USER_ID = 16

LEAF, INDEX, HEADER, MAP = -1, 0, 1, 2

HFS_FOLDER, HFS_FILE = 0x0100, 0x0200
HFS_FOLDER_THREAD, HFS_FILE_THREAD = 0x0300, 0x0400
HP_FOLDER, HP_FILE, HP_FOLDER_THREAD, HP_FILE_THREAD = 1, 2, 3, 4

DATA_FORK, RSRC_FORK = 0x00, 0xFF

UNMOUNTED_BIT = 1 << 8      # kHFSVolumeUnmountedMask

MAC_EPOCH_DELTA = 2082844800   # seconds from 1904-01-01 to 1970-01-01


def u8(b, o):
    return b[o]


def s8(b, o):
    return struct.unpack_from(">b", b, o)[0]


def u16(b, o):
    return struct.unpack_from(">H", b, o)[0]


def s16(b, o):
    return struct.unpack_from(">h", b, o)[0]


def u32(b, o):
    return struct.unpack_from(">I", b, o)[0]


def u64(b, o):
    return struct.unpack_from(">Q", b, o)[0]


_tables = {}


def _table(name):
    if name not in _tables:
        text = open(TABLES, encoding="latin-1").read()
        m = re.search(name + r"\[\]\s*=\s*\{(.*?)\};", text, re.S)
        body = re.sub(r"//[^\n]*|/\*.*?\*/", "", m.group(1), flags=re.S)
        _tables[name] = [int(x, 16) for x in re.findall(r"0x[0-9A-Fa-f]+", body)]
    return _tables[name]


def fold_unicode(units):
    """The character sequence FastUnicodeCompare actually compares: each
    UTF-16 unit case-folded through gLowerCaseTable, ignorables dropped."""
    t = _table("gLowerCaseTable")
    out = []
    for c in units:
        sub = t[c >> 8]
        if sub:
            c = t[sub + (c & 0xFF)]
        if c:
            out.append(c)
    return out


def unicode_compare(a, b):
    """FastUnicodeCompare (UnicodeWrappers.c): -1, 0 or 1."""
    fa, fb = fold_unicode(a), fold_unicode(b)
    return (fa > fb) - (fa < fb)


def relstring_compare(a, b):
    """FastRelString (UnicodeWrappers.c) over two Mac Roman byte strings."""
    t = _table("gCompareTable")
    best = (len(a) > len(b)) - (len(a) < len(b))
    for x, y in zip(a, b):
        if x != y:
            sx, sy = t[x], t[y]
            if sx != sy:
                return 1 if sx > sy else -1
    return best


def cmp(a, b):
    return (a > b) - (a < b)


class Extent(object):
    __slots__ = ("start", "count")

    def __init__(self, start, count):
        self.start, self.count = start, count

    def __repr__(self):
        return "Extent(%d, %d)" % (self.start, self.count)


def hfs_extents(b, o):
    """An HFSExtentRecord: three (UInt16 start, UInt16 count)."""
    return [Extent(u16(b, o + 4 * i), u16(b, o + 4 * i + 2)) for i in range(3)]


def plus_extents(b, o):
    """An HFSPlusExtentRecord: eight (UInt32 start, UInt32 count)."""
    return [Extent(u32(b, o + 8 * i), u32(b, o + 8 * i + 4)) for i in range(8)]


class ForkData(object):
    """HFSPlusForkData, or the HFS equivalent assembled from a file record."""

    def __init__(self, logical_size, total_blocks, extents, clump=0):
        self.logical_size = logical_size
        self.total_blocks = total_blocks
        self.extents = extents
        self.clump = clump


def plus_fork(b, o):
    return ForkData(u64(b, o), u32(b, o + 12), plus_extents(b, o + 16), u32(b, o + 8))


class MDB(object):
    """HFSMasterDirectoryBlock, 162 bytes at volume offset 1024."""

    def __init__(self, b):
        self.raw = bytes(b[:162])
        self.sig = u16(b, 0)
        self.cr_date = u32(b, 2)
        self.ls_mod = u32(b, 6)
        self.atrb = u16(b, 10)
        self.nm_fls = u16(b, 12)
        self.vbm_st = u16(b, 14)
        self.alloc_ptr = u16(b, 16)
        self.nm_al_blks = u16(b, 18)
        self.al_blk_siz = u32(b, 20)
        self.clp_siz = u32(b, 24)
        self.al_bl_st = u16(b, 28)
        self.nxt_cnid = u32(b, 30)
        self.free_bks = u16(b, 34)
        self.vn = bytes(b[37:37 + b[36]])
        self.vol_bk_up = u32(b, 64)
        self.v_seq_num = u16(b, 68)
        self.wr_cnt = u32(b, 70)
        self.xt_clp_siz = u32(b, 74)
        self.ct_clp_siz = u32(b, 78)
        self.nm_rt_dirs = u16(b, 82)
        self.fil_cnt = u32(b, 84)
        self.dir_cnt = u32(b, 88)
        self.fndr_info = bytes(b[92:124])
        self.embed_sig = u16(b, 124)
        self.embed_start = u16(b, 126)
        self.embed_count = u16(b, 128)
        self.xt_fl_size = u32(b, 130)
        self.xt_ext_rec = hfs_extents(b, 134)
        self.ct_fl_size = u32(b, 146)
        self.ct_ext_rec = hfs_extents(b, 150)


class VolumeHeader(object):
    """HFSPlusVolumeHeader, 512 bytes at volume offset 1024."""

    def __init__(self, b):
        self.raw = bytes(b[:512])
        self.sig = u16(b, 0)
        self.version = u16(b, 2)
        self.attributes = u32(b, 4)
        self.last_mounted_version = bytes(b[8:12])
        self.create_date = u32(b, 16)
        self.modify_date = u32(b, 20)
        self.backup_date = u32(b, 24)
        self.checked_date = u32(b, 28)
        self.file_count = u32(b, 32)
        self.folder_count = u32(b, 36)
        self.block_size = u32(b, 40)
        self.total_blocks = u32(b, 44)
        self.free_blocks = u32(b, 48)
        self.next_allocation = u32(b, 52)
        self.rsrc_clump = u32(b, 56)
        self.data_clump = u32(b, 60)
        self.next_catalog_id = u32(b, 64)
        self.write_count = u32(b, 68)
        self.encodings_bitmap = u64(b, 72)
        self.finder_info = bytes(b[80:112])
        self.allocation_file = plus_fork(b, 112)
        self.extents_file = plus_fork(b, 192)
        self.catalog_file = plus_fork(b, 272)
        self.attributes_file = plus_fork(b, 352)
        self.startup_file = plus_fork(b, 432)
