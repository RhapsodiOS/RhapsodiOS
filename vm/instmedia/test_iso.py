import io
import struct
import unittest

from instmedia import iso

S = iso.SECTOR
FILES = [("README.TXT", 100), ("BOOT.CAT", 2048),
         ("BIOSBOOT.IMG", 5000), ("EFIBOOT.IMG", 3 * 1024 * 1024)]
MTIME = 1700000000
TOTAL = 4000


def build(pattern=False):
    ents, nxt = iso.layout(FILES, iso.FIRST_LBA)
    f = io.BytesIO(b"\0" * (TOTAL * S))
    if pattern:
        f.write(bytes(range(256)) * (16 * S // 256))
    iso.write_iso(f, "RHAPSODIOS", FILES, ents["BOOT.CAT"].lba, "BIOSBOOT.IMG",
                  "EFIBOOT.IMG", TOTAL, MTIME)
    return f.getvalue(), ents


def sec(img, n):
    return img[n * S:(n + 1) * S]


class IsoTest(unittest.TestCase):
    def test_layout_contiguous(self):
        ents, nxt = iso.layout([("A", 1), ("B", 2048), ("C", 2049)], 22)
        self.assertEqual([ents[k].lba for k in "ABC"], [22, 23, 24])
        self.assertEqual(nxt, 26)
        self.assertEqual(ents["C"].size, 2049)

    def test_pvd_fields(self):
        img, ents = build()
        p = sec(img, 16)
        self.assertEqual(p[0], 1)
        self.assertEqual(p[1:6], b"CD001")
        self.assertEqual(p[6], 1)
        self.assertEqual(p[40:72], b"RHAPSODIOS".ljust(32))
        self.assertEqual(struct.unpack("<I", p[80:84])[0], TOTAL)
        self.assertEqual(struct.unpack(">I", p[84:88])[0], TOTAL)
        self.assertEqual(struct.unpack("<H", p[128:130])[0], 2048)
        self.assertEqual(struct.unpack(">H", p[130:132])[0], 2048)
        self.assertEqual(p[881], 1)
        root = p[156:190]
        self.assertEqual(root[0], 34)
        self.assertEqual(struct.unpack("<I", root[2:6])[0], iso.ROOT_LBA)
        self.assertEqual(root[25], 2)
        self.assertEqual(p[813:817], b"2023")

    def test_boot_record_points_at_catalog(self):
        img, ents = build()
        b = sec(img, 17)
        self.assertEqual(b[0], 0)
        self.assertEqual(b[1:6], b"CD001")
        self.assertEqual(b[7:39], b"EL TORITO SPECIFICATION".ljust(32, b"\0"))
        self.assertEqual(struct.unpack("<I", b[71:75])[0],
                         ents["BOOT.CAT"].lba)
        t = sec(img, 18)
        self.assertEqual((t[0], t[1:6]), (255, b"CD001"))

    def test_catalog_entries(self):
        img, ents = build()
        c = sec(img, ents["BOOT.CAT"].lba)
        self.assertEqual(sum(struct.unpack("<16H", c[:32])) & 0xFFFF, 0)
        self.assertEqual((c[0], c[1]), (1, 0))
        self.assertEqual(c[4:28], b"RHAPSODIOS".ljust(24, b"\0"))
        self.assertEqual(c[30:32], b"\x55\xaa")
        d = c[32:64]
        self.assertEqual((d[0], d[1], d[4]), (0x88, 4, 0xA7))
        self.assertEqual(struct.unpack("<H", d[6:8])[0], 1)
        self.assertEqual(struct.unpack("<I", d[8:12])[0],
                         ents["BIOSBOOT.IMG"].lba)
        h = c[64:96]
        self.assertEqual((h[0], h[1]), (0x91, 0xEF))
        self.assertEqual(struct.unpack("<H", h[2:4])[0], 1)
        e = c[96:128]
        self.assertEqual((e[0], e[1], e[4]), (0x88, 0, 0))
        self.assertEqual(struct.unpack("<H", e[6:8])[0], 3 * 1024 * 2)
        self.assertEqual(struct.unpack("<I", e[8:12])[0],
                         ents["EFIBOOT.IMG"].lba)
        self.assertEqual(c[128:], b"\0" * (S - 128))

    def test_efi_sector_count_capped(self):
        files = [("BOOT.CAT", 2048), ("BIOSBOOT.IMG", 512),
                 ("EFIBOOT.IMG", 64 * 1024 * 1024)]
        ents, _ = iso.layout(files, iso.FIRST_LBA)
        f = io.BytesIO(b"\0" * (40000 * S))
        iso.write_iso(f, "RHAPSODIOS", files, ents["BOOT.CAT"].lba,
                      "BIOSBOOT.IMG", "EFIBOOT.IMG", 40000, MTIME)
        c = sec(f.getvalue(), ents["BOOT.CAT"].lba)
        self.assertEqual(struct.unpack("<H", c[102:104])[0], 0xFFFF)

    def test_records_pad_to_even_length(self):
        img, _ = build()
        r = sec(img, iso.ROOT_LBA)
        pos, names = 0, []
        while r[pos]:
            n = r[pos]
            if r[32 + pos] > 1:
                self.assertEqual(n % 2, 0)
            names.append(r[33 + pos:33 + pos + r[32 + pos]])
            pos += n
        self.assertIn(b"README.TXT;1", names)
        self.assertIn(b"BOOT.CAT;1", names)
        self.assertEqual(names[:2], [b"\0", b"\1"])
        self.assertEqual(names[2:], sorted(names[2:]))

    def test_path_tables_both_orders(self):
        img, _ = build()
        p = sec(img, 16)
        size = struct.unpack("<I", p[132:136])[0]
        self.assertEqual(size, struct.unpack(">I", p[136:140])[0])
        lpos = struct.unpack("<I", p[140:144])[0]
        mpos = struct.unpack(">I", p[148:152])[0]
        self.assertNotEqual(lpos, mpos)
        lt, mt = sec(img, lpos)[:size], sec(img, mpos)[:size]
        self.assertEqual(lt[:2], b"\x01\x00")
        self.assertEqual(struct.unpack("<IH", lt[2:8]), (iso.ROOT_LBA, 1))
        self.assertEqual(struct.unpack(">IH", mt[2:8]), (iso.ROOT_LBA, 1))
        self.assertEqual(size % 2, 0)

    def test_independent_parse(self):
        img, ents = build()
        assert img[16 * 2048 + 1:16 * 2048 + 6] == b"CD001"
        base = 16 * 2048
        rl = int.from_bytes(img[base + 158:base + 162], "little")
        rs = int.from_bytes(img[base + 166:base + 170], "little")
        d = img[rl * 2048:rl * 2048 + rs]
        got, pos = {}, 0
        while pos < len(d) and d[pos]:
            ln = d[pos]
            lba = int.from_bytes(d[pos + 2:pos + 6], "little")
            size = int.from_bytes(d[pos + 10:pos + 14], "little")
            nm = d[pos + 33:pos + 33 + d[pos + 32]]
            if nm not in (b"\0", b"\1"):
                got[nm.decode().split(";")[0]] = (lba, size)
            pos += ln
        self.assertEqual(got, {k: (v.lba, v.size) for k, v in ents.items()})
        self.assertEqual(len(got), 4)

    def test_round_trip(self):
        img, ents = build()
        r = iso.read_iso(io.BytesIO(img))
        self.assertEqual(r["volume_id"], "RHAPSODIOS")
        self.assertEqual(r["files"],
                         {k: (v.lba, v.size) for k, v in ents.items()})
        cat = r["catalog"]
        self.assertEqual(len(cat), 4)
        self.assertEqual(cat[1]["media"], 4)
        self.assertEqual(cat[1]["lba"], ents["BIOSBOOT.IMG"].lba)
        self.assertEqual(cat[2]["platform"], 0xEF)
        self.assertEqual(cat[3]["lba"], ents["EFIBOOT.IMG"].lba)

    def test_deterministic(self):
        self.assertEqual(build()[0], build()[0])

    def test_system_area_untouched(self):
        img, _ = build(pattern=True)
        self.assertEqual(img[:16 * S], bytes(range(256)) * (16 * S // 256))


if __name__ == "__main__":
    unittest.main()
