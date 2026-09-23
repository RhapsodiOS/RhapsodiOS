"""Unit test for guest-console.py's QEMU command line.

Run with: cd vm && python -m unittest test_guest_console -v
"""
import importlib.util
import os
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "guest_console", os.path.join(_HERE, "guest-console.py"))
gc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gc)


class QemuArgsTest(unittest.TestCase):
    def test_defaults_keep_the_old_command_line(self):
        a = gc.qemu_args(gc.IMAGE, False, 4481, "null", "ne2k_pci", (), "s.log")
        self.assertIn("ne2k_pci,netdev=n0", a)
        i = a.index("-drive")
        self.assertEqual(
            a[i + 1], "file=%s,format=raw,if=ide,index=0,media=disk" % gc.IMAGE)
        self.assertEqual(a[i + 2], "-snapshot")
        self.assertIn("file:s.log", a)

    def test_image_nic_and_extra(self):
        extra = ("-object", "filter-dump,id=f0,netdev=n0,file=p.pcap")
        a = gc.qemu_args("x.img", True, 4600, "null",
                         "i82559er,addr=03.0", extra, "s.log")
        self.assertIn("file=x.img,format=raw,if=ide,index=0,media=disk", a)
        self.assertIn("i82559er,addr=03.0,netdev=n0", a)
        self.assertNotIn("-snapshot", a)
        self.assertEqual(a[-2:], list(extra))
        self.assertIn("tcp:127.0.0.1:4600,server,nowait", a)


if __name__ == "__main__":
    unittest.main()
