"""ISO 9660 (ECMA-119) and El Torito 1.0 boot-catalog writer and reader.

Only the descriptors, the two path tables, the single root directory and the
boot catalog are written; file data and sectors 0-15 belong to the caller.
Sector map: 16 PVD, 17 boot record, 18 terminator, 19 L path table, 20 M path
table, 21 root directory, files from FIRST_LBA.  Output is deterministic: every
timestamp comes from the mtime argument.
"""
import struct
import time
from collections import namedtuple

SECTOR = 2048
PVD_LBA, BOOT_LBA, TERM_LBA = 16, 17, 18
LPATH_LBA, MPATH_LBA, ROOT_LBA = 19, 20, 21
FIRST_LBA = 22

FileEntry = namedtuple("FileEntry", "name lba size")


def _sectors(size):
    return (size + SECTOR - 1) // SECTOR


def layout(files, first_lba):
    """Assign contiguous LBAs in order; return (entries, next_lba)."""
    out, lba = {}, first_lba
    for name, size in files:
        out[name] = FileEntry(name, lba, size)
        lba += _sectors(size)
    return out, lba


def _both32(n):
    return struct.pack("<I", n) + struct.pack(">I", n)


def _both16(n):
    return struct.pack("<H", n) + struct.pack(">H", n)


def _date7(mtime):
    t = time.gmtime(mtime)
    return bytes([t.tm_year - 1900, t.tm_mon, t.tm_mday,
                  t.tm_hour, t.tm_min, t.tm_sec, 0])


def _date17(mtime):
    t = time.gmtime(mtime)
    return ("%04d%02d%02d%02d%02d%02d00" % t[:6]).encode("ascii") + b"\0"


def _record(name, lba, size, flags, mtime):
    pad = b"\0" if len(name) % 2 == 0 else b""
    length = 33 + len(name) + len(pad)
    return (struct.pack("<BB", length, 0) + _both32(lba) + _both32(size)
            + _date7(mtime) + struct.pack("<BBB", flags, 0, 0) + _both16(1)
            + struct.pack("<B", len(name)) + name + pad)


def _path_table(order):
    p32, p16 = ("<I", "<H") if order == "<" else (">I", ">H")
    ent = struct.pack("<BB", 1, 0) + struct.pack(p32, ROOT_LBA) \
        + struct.pack(p16, 1) + b"\0"
    return ent + b"\0" * (len(ent) % 2)


def _padded(text, size, fill=b" "):
    raw = text.encode("ascii")
    if len(raw) > size:
        raise ValueError("%r longer than %d" % (text, size))
    return raw + fill * (size - len(raw))


def _put(f, lba, data):
    f.seek(lba * SECTOR)
    f.write(data.ljust(_sectors(len(data)) * SECTOR, b"\0"))


def _catalog(volume_id, bios, efi, bios_system_type):
    ident = _padded(volume_id, 24, b"\0")
    words = b"\x01\x00\x00\x00" + ident + b"\0\0\x55\xaa"
    total = sum(struct.unpack("<16H", words)) & 0xFFFF
    val = words[:28] + struct.pack("<H", (-total) & 0xFFFF) + b"\x55\xaa"
    d = struct.pack("<BBHBBHI", 0x88, 4, 0, bios_system_type, 0, 1, bios.lba)
    h = struct.pack("<BBH", 0x91, 0xEF, 1) + b"\0" * 28
    count = min((efi.size + 511) // 512, 0xFFFF)
    e = struct.pack("<BBHBBHI", 0x88, 0, 0, 0, 0, count, efi.lba)
    return b"".join(x.ljust(32, b"\0") for x in (val, d, h, e))


def write_iso(f, volume_id, files, catalog_lba, bios_name, efi_name,
              total_sectors, mtime, bios_system_type=0xA7):
    """Write descriptors, path tables, root directory and boot catalog.

    `files` is the ordered (name, size) list that layout() takes; the file data
    itself (including the catalog's own sector at catalog_lba) is the caller's.
    """
    ents, _ = layout(files, FIRST_LBA)
    ltab, mtab = _path_table("<"), _path_table(">")

    recs = [_record(b"\0", ROOT_LBA, SECTOR, 2, mtime),
            _record(b"\1", ROOT_LBA, SECTOR, 2, mtime)]
    for name in sorted(ents):
        e = ents[name]
        recs.append(_record(name.encode("ascii") + b";1", e.lba, e.size, 0,
                            mtime))
    root = b"".join(recs)
    if len(root) > SECTOR:
        raise ValueError("root directory does not fit in one sector")

    pvd = bytearray(SECTOR)
    pvd[0:8] = b"\x01CD001\x01\x00"
    pvd[8:40] = _padded("", 32)
    pvd[40:72] = _padded(volume_id, 32)
    pvd[80:88] = _both32(total_sectors)
    pvd[120:124] = _both16(1)
    pvd[124:128] = _both16(1)
    pvd[128:132] = _both16(SECTOR)
    pvd[132:140] = _both32(len(ltab))
    pvd[140:144] = struct.pack("<I", LPATH_LBA)
    pvd[148:152] = struct.pack(">I", MPATH_LBA)
    pvd[156:190] = _record(b"\0", ROOT_LBA, SECTOR, 2, mtime)
    for off, size in ((190, 128), (318, 128), (446, 128), (574, 128),
                      (702, 37), (739, 37), (776, 37)):
        pvd[off:off + size] = b" " * size
    date = _date17(mtime)
    pvd[813:830] = date
    pvd[830:847] = date
    pvd[847:864] = b"0" * 16 + b"\0"
    pvd[864:881] = b"0" * 16 + b"\0"
    pvd[881] = 1

    boot = b"\x00CD001\x01" + _padded("EL TORITO SPECIFICATION", 32, b"\0") \
        + b"\0" * 32 + struct.pack("<I", catalog_lba)
    term = b"\xffCD001\x01"

    _put(f, PVD_LBA, bytes(pvd))
    _put(f, BOOT_LBA, boot)
    _put(f, TERM_LBA, term)
    _put(f, LPATH_LBA, ltab)
    _put(f, MPATH_LBA, mtab)
    _put(f, ROOT_LBA, root)
    _put(f, catalog_lba, _catalog(volume_id, ents[bios_name], ents[efi_name],
                                  bios_system_type))


def _read_sector(f, lba):
    f.seek(lba * SECTOR)
    return f.read(SECTOR)


def read_iso(f):
    """Parse a written image: volume_id, files {name: (lba, size)}, catalog."""
    pvd = _read_sector(f, PVD_LBA)
    if pvd[0] != 1 or pvd[1:6] != b"CD001":
        raise ValueError("no primary volume descriptor")
    boot = _read_sector(f, BOOT_LBA)
    if boot[0] != 0 or boot[7:30] != b"EL TORITO SPECIFICATION":
        raise ValueError("no El Torito boot record")
    root_lba, root_size = struct.unpack("<I", pvd[158:162])[0], \
        struct.unpack("<I", pvd[166:170])[0]
    f.seek(root_lba * SECTOR)
    root = f.read(root_size)
    files, pos = {}, 0
    while pos < len(root) and root[pos]:
        length, nlen = root[pos], root[pos + 32]
        name = root[pos + 33:pos + 33 + nlen]
        if name not in (b"\0", b"\1"):
            lba = struct.unpack("<I", root[pos + 2:pos + 6])[0]
            size = struct.unpack("<I", root[pos + 10:pos + 14])[0]
            files[name.decode("ascii").split(";")[0]] = (lba, size)
        pos += length
    cat_lba = struct.unpack("<I", boot[71:75])[0]
    cat = _read_sector(f, cat_lba)
    words = sum(struct.unpack("<16H", cat[:32])) & 0xFFFF
    if words or cat[30:32] != b"\x55\xaa":
        raise ValueError("bad validation entry")
    catalog = [{"kind": "validation", "platform": cat[1],
                "id": cat[4:28].rstrip(b"\0").decode("ascii")}]
    for off in (32, 96):
        e = cat[off:off + 32]
        catalog.append({
            "kind": "default" if off == 32 else "section",
            "boot": e[0], "media": e[1], "system_type": e[4],
            "count": struct.unpack("<H", e[6:8])[0],
            "lba": struct.unpack("<I", e[8:12])[0]})
        if off == 32:
            h = cat[64:96]
            catalog.append({"kind": "header", "final": h[0] == 0x91,
                            "platform": h[1],
                            "entries": struct.unpack("<H", h[2:4])[0]})
    return {"volume_id": pvd[40:72].decode("ascii").rstrip(),
            "files": files, "catalog": catalog,
            "catalog_lba": cat_lba}
