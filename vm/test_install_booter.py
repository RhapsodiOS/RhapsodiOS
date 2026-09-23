"""Unit tests for install-booter.py.

Run from the repository root with:
    python -m unittest discover -s vm -p test_install_booter.py -v
"""
import importlib.util
import os
import struct
import tempfile
import unittest
import unittest.mock as mock

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load():
    spec = importlib.util.spec_from_file_location(
        "install_booter", os.path.join(_HERE, "install-booter.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ib = _load()

KB = 1024


def _make_image(path, front=160, boot0=(32, 96), secsize=1024):
    """A disk image with only a NeXT label at sector 15, laid out like
    golden.img: 1 KB sectors, copies at blocks 32 and 96, porch of 160."""
    label = bytearray(1024)
    label[:4] = b"dlV3"
    struct.pack_into(">i", label, 92, secsize)
    struct.pack_into(">h", label, 112, front)
    struct.pack_into(">ii", label, 124, *boot0)
    data = bytearray(b"\xAA" * (200 * KB))      # non-zero, to see what changes
    data[7680:7680 + 1024] = label
    with open(path, "wb") as f:
        f.write(data)
    return bytes(data)


class InstallBooterTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.image = os.path.join(self.tmp.name, "test.img")
        self.guard = mock.patch.object(ib.rhap_inject, "check_target", lambda p: None)
        self.guard.start()

    def tearDown(self):
        self.guard.stop()
        self.tmp.cleanup()

    def _read(self):
        with open(self.image, "rb") as f:
            return f.read()

    def test_writes_both_copies_and_zero_fills_each_slot(self):
        before = _make_image(self.image)
        booter = bytes(range(256)) * 100             # 25,600 bytes
        slots = ib.install_booter(self.image, booter, 45056)
        self.assertEqual(slots, [(32 * KB, 64 * KB), (96 * KB, 64 * KB)])
        after = self._read()
        for off, length in slots:
            self.assertEqual(after[off:off + len(booter)], booter)
            self.assertEqual(after[off + len(booter):off + length], bytes(length - len(booter)))
        self.assertEqual(after[:32 * KB], before[:32 * KB])        # label untouched
        self.assertEqual(after[160 * KB:], before[160 * KB:])      # past the porch untouched

    def test_refuses_a_booter_longer_than_loadsz(self):
        before = _make_image(self.image)
        with self.assertRaises(ib.rhap_inject.SafetyError):
            ib.install_booter(self.image, b"\x01" * 45057, 45056)
        self.assertEqual(self._read(), before)

    def test_refuses_a_booter_longer_than_a_slot_before_writing_either(self):
        before = _make_image(self.image, front=104)   # second slot is 8 KB
        with self.assertRaises(ib.rhap_inject.SafetyError):
            ib.install_booter(self.image, b"\x01" * (9 * KB), 45056)
        self.assertEqual(self._read(), before)

    def test_refuses_an_image_the_guard_refuses(self):
        before = _make_image(self.image)
        self.guard.stop()
        try:
            with mock.patch.object(ib.rhap_inject, "check_target",
                                   side_effect=ib.rhap_inject.SafetyError("no")):
                with self.assertRaises(ib.rhap_inject.SafetyError):
                    ib.install_booter(self.image, b"\x01" * 100, 45056)
        finally:
            self.guard.start()
        self.assertEqual(self._read(), before)

    def test_read_loadsz_reads_boot1(self):
        path = os.path.join(self.tmp.name, "boot1.s")
        with open(path, "w") as f:
            f.write("BUFSZ\t\tEQU\t2000h\nLOADSZ\t\tEQU\t88\t; maxiumum possible size\n")
        self.assertEqual(ib.read_loadsz(path), 45056)

    def test_read_loadsz_refuses_a_file_without_it(self):
        path = os.path.join(self.tmp.name, "boot1.s")
        with open(path, "w") as f:
            f.write("BUFSZ\t\tEQU\t2000h\n")
        with self.assertRaises(ValueError):
            ib.read_loadsz(path)

    def test_repository_boot1_gives_45056(self):
        self.assertEqual(ib.read_loadsz(), 45056)


if __name__ == "__main__":
    unittest.main()
