"""Write and read small FAT32 volumes with the standard library only.

Enough FAT32 for an EFI System Partition, and deliberately no more: 8.3
names, one sector per cluster, one cluster per directory, files stored
contiguously.  build() raises FatError for anything outside that instead of
producing a volume the firmware would misread.

Layout follows Microsoft's FAT specification (fatgen103): 32 reserved
sectors with FSInfo at sector 1 and a backup boot sector at 6, two FATs, and
the root directory at cluster 2.
"""
import struct

SECTOR = 512
RESERVED = 32
NUM_FATS = 2
ROOT_CLUSTER = 2
FAT32_MIN_CLUSTERS = 65525      # below this the firmware reads it as FAT16
EOC = 0x0FFFFFFF
ATTR_VOLUME_ID = 0x08
ATTR_DIRECTORY = 0x10
ATTR_ARCHIVE = 0x20
DIRENT = 32
ENTRIES_PER_DIR = SECTOR // DIRENT
# A fixed timestamp (1999-06-01 00:00) keeps builds byte-for-byte repeatable.
DOS_DATE = ((1999 - 1980) << 9) | (6 << 5) | 1
DOS_TIME = 0
VOLUME_ID = 0x52484150          # "RHAP"
_NAME_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-~!#$%&'()@^{}")


class FatError(Exception):
    pass


def short_name(component):
    """The 11-byte directory-entry name for an upper-case 8.3 component."""
    base, _, ext = component.partition(".")
    if (not base or len(base) > 8 or len(ext) > 3 or "." in ext
            or not set(base + ext) <= _NAME_CHARS):
        raise FatError("%r is not an upper-case 8.3 name" % component)
    return (base.ljust(8) + ext.ljust(3)).encode("ascii")


def fat_sectors(total_sectors):
    """FATSz32 for one sector per cluster (fatgen103, "FAT Volume
    Initialization")."""
    tmp1 = total_sectors - RESERVED
    tmp2 = (256 * 1 + NUM_FATS) // 2
    return (tmp1 + tmp2 - 1) // tmp2


def _dirent(name11, attr, cluster, size):
    e = bytearray(DIRENT)
    e[0:11] = name11
    e[11] = attr
    struct.pack_into("<HHH", e, 14, DOS_TIME, DOS_DATE, DOS_DATE)
    struct.pack_into("<HHHHI", e, 20, cluster >> 16, DOS_TIME, DOS_DATE,
                     cluster & 0xFFFF, size)
    return bytes(e)


def _tree(files):
    """{dir path: {name11: ("dir", child path) | ("file", data)}}"""
    dirs = {"": {}}
    for path in sorted(files):
        parts = path.split("/")
        parent = ""
        for comp in parts[:-1]:
            name11 = short_name(comp)
            child = comp if not parent else parent + "/" + comp
            kind = dirs[parent].setdefault(name11, ("dir", child))[0]
            if kind != "dir":
                raise FatError("%s is both a file and a directory" % child)
            dirs.setdefault(child, {})
            parent = child
        name11 = short_name(parts[-1])
        if name11 in dirs[parent]:
            raise FatError("%s appears twice" % path)
        dirs[parent][name11] = ("file", files[path])
    return dirs


def build(total_sectors, files, label="RHAPEFI", hidden_sectors=0):
    """Return a FAT32 volume of total_sectors as bytes.

    files maps "DIR/SUB/NAME.EXT" paths to contents; parent directories are
    created as needed.  hidden_sectors is the partition's starting LBA,
    recorded in the BPB as the specification asks.
    """
    if len(label) > 11:
        raise FatError("volume label %r is longer than 11 characters" % label)
    label11 = label.upper().ljust(11).encode("ascii")
    fatsz = fat_sectors(total_sectors)
    data_start = RESERVED + NUM_FATS * fatsz
    clusters = total_sectors - data_start
    if clusters < FAT32_MIN_CLUSTERS:
        raise FatError("%d sectors give %d clusters; FAT32 needs at least %d"
                       % (total_sectors, clusters, FAT32_MIN_CLUSTERS))

    dirs = _tree(files)
    # Root first, then the other directories shallowest first, then data.
    order = sorted(dirs, key=lambda d: (d.count("/") if d else -1, d))
    dir_cluster = dict((d, ROOT_CLUSTER + i) for i, d in enumerate(order))
    next_cluster = ROOT_CLUSTER + len(order)
    fat = [0] * (clusters + 2)
    fat[0] = 0x0FFFFFF8
    fat[1] = EOC
    for d in order:
        fat[dir_cluster[d]] = EOC

    image = bytearray(total_sectors * SECTOR)
    file_cluster = {}
    for d in order:
        for name11, (kind, value) in sorted(dirs[d].items()):
            if kind != "file":
                continue
            if not value:
                file_cluster[(d, name11)] = 0
                continue
            n = (len(value) + SECTOR - 1) // SECTOR
            if next_cluster + n > clusters + 2:
                raise FatError("contents do not fit in %d sectors"
                               % total_sectors)
            for c in range(next_cluster, next_cluster + n - 1):
                fat[c] = c + 1
            fat[next_cluster + n - 1] = EOC
            off = (data_start + next_cluster - 2) * SECTOR
            image[off:off + len(value)] = value
            file_cluster[(d, name11)] = next_cluster
            next_cluster += n

    for d in order:
        if d:
            parent = d.rpartition("/")[0]
            entries = [
                _dirent(b".          ", ATTR_DIRECTORY, dir_cluster[d], 0),
                _dirent(b"..         ", ATTR_DIRECTORY,
                        dir_cluster[parent] if parent else 0, 0),
            ]
        else:
            entries = [_dirent(label11, ATTR_VOLUME_ID, 0, 0)]
        for name11, (kind, value) in sorted(dirs[d].items()):
            if kind == "dir":
                entries.append(_dirent(name11, ATTR_DIRECTORY,
                                       dir_cluster[value], 0))
            else:
                entries.append(_dirent(name11, ATTR_ARCHIVE,
                                       file_cluster[(d, name11)], len(value)))
        if len(entries) > ENTRIES_PER_DIR:
            raise FatError("directory %r needs more than one cluster"
                           % (d or "/"))
        off = (data_start + dir_cluster[d] - 2) * SECTOR
        image[off:off + DIRENT * len(entries)] = b"".join(entries)

    fat_bytes = struct.pack("<%dI" % len(fat), *fat)
    for i in range(NUM_FATS):
        off = (RESERVED + i * fatsz) * SECTOR
        image[off:off + len(fat_bytes)] = fat_bytes

    boot = bytearray(SECTOR)
    boot[0:3] = b"\xeb\x58\x90"
    boot[3:11] = b"RHAPSODI"
    struct.pack_into("<HBHBHHBHHHII", boot, 11, SECTOR, 1, RESERVED,
                     NUM_FATS, 0, 0, 0xF8, 0, 63, 255, hidden_sectors,
                     total_sectors)
    struct.pack_into("<IHHIHH", boot, 36, fatsz, 0, 0, ROOT_CLUSTER, 1, 6)
    boot[64] = 0x80
    boot[66] = 0x29
    struct.pack_into("<I", boot, 67, VOLUME_ID)
    boot[71:82] = label11
    boot[82:90] = b"FAT32   "
    boot[510:512] = b"\x55\xaa"

    fsinfo = bytearray(SECTOR)
    struct.pack_into("<I", fsinfo, 0, 0x41615252)
    struct.pack_into("<III", fsinfo, 484, 0x61417272,
                     clusters + 2 - next_cluster, next_cluster)
    struct.pack_into("<I", fsinfo, 508, 0xAA550000)

    for sector, block in ((0, boot), (1, fsinfo), (6, boot), (7, fsinfo)):
        image[sector * SECTOR:(sector + 1) * SECTOR] = block
    return bytes(image)


def _layout(image):
    bps, spc, rsvd, nfats = struct.unpack_from("<HBHB", image, 11)
    fatsz, = struct.unpack_from("<I", image, 36)
    root, = struct.unpack_from("<I", image, 44)
    if bps != SECTOR or spc != 1 or image[82:90] != b"FAT32   ":
        raise FatError("not a volume this module writes")
    return rsvd, rsvd + nfats * fatsz, root


def _chain(image, rsvd, first):
    clusters = []
    c = first
    while 2 <= c < 0x0FFFFFF8:
        clusters.append(c)
        c = struct.unpack_from("<I", image, rsvd * SECTOR + 4 * c)[0] & EOC
    return clusters


def read_file(image, path):
    """The contents of path in a volume build() produced."""
    rsvd, data_start, cluster = _layout(image)
    parts = path.split("/")
    for i, comp in enumerate(parts):
        want = short_name(comp)
        raw = b"".join(
            image[(data_start + c - 2) * SECTOR:(data_start + c - 1) * SECTOR]
            for c in _chain(image, rsvd, cluster))
        for off in range(0, len(raw), DIRENT):
            e = raw[off:off + DIRENT]
            if e[0] == 0:
                break
            if e[0:11] == want:
                break
        else:
            e = b"\0"
        if e[0] == 0:
            raise FatError("%s: no such file or directory" % path)
        is_dir = bool(e[11] & ATTR_DIRECTORY)
        first = (struct.unpack_from("<H", e, 20)[0] << 16
                 | struct.unpack_from("<H", e, 26)[0])
        if i < len(parts) - 1:
            if not is_dir:
                raise FatError("%s: %s is not a directory" % (path, comp))
            cluster = first
        else:
            if is_dir:
                raise FatError("%s is a directory" % path)
            size, = struct.unpack_from("<I", e, 28)
            data = b"".join(
                image[(data_start + c - 2) * SECTOR:
                      (data_start + c - 1) * SECTOR]
                for c in _chain(image, rsvd, first))
            return data[:size]
