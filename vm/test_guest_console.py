"""Unit tests for guest-console.py: its QEMU command line, and the guard on
persistent boots.

Run with: cd vm && python -m unittest test_guest_console -v
"""
import importlib.util
import os
import tempfile
import unittest
import unittest.mock as mock

import rhap_inject

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


def _load_guest_console(image):
    # guest-console.py reads RHAP_TEST_IMAGE when it is imported
    with mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": image}):
        spec = importlib.util.spec_from_file_location(
            "guest_console", os.path.join(_HERE, "guest-console.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    return module


class TestPersistGuard(unittest.TestCase):
    """A persistent boot writes the image, so it must refuse protected ones
    before qemu is ever started. qemu is mocked out; nothing boots."""

    def _guest(self, env_image, persist, **kw):
        gc = _load_guest_console(env_image)
        with tempfile.TemporaryDirectory() as out, \
                mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": env_image}), \
                mock.patch.object(gc.subprocess, "Popen",
                                  side_effect=RuntimeError("qemu launched")) as popen:
            try:
                gc.Guest(out, persist=persist, port=4499, **kw)
            except RuntimeError:
                pass
            return popen

    def test_persistent_boot_refuses_a_golden_img(self):
        with tempfile.TemporaryDirectory() as d:
            image = os.path.join(d, "golden.img")
            with self.assertRaises(rhap_inject.SafetyError):
                self._guest(image, persist=True)

    def test_persistent_boot_allows_a_private_image(self):
        with tempfile.TemporaryDirectory() as d:
            popen = self._guest(os.path.join(d, "ufs-backport.img"), persist=True)
            popen.assert_called_once()

    def test_snapshot_boot_is_not_guarded(self):
        # without persist, qemu runs -snapshot and never writes the image
        with tempfile.TemporaryDirectory() as d:
            popen = self._guest(os.path.join(d, "golden.img"), persist=False)
            popen.assert_called_once()
            self.assertIn("-snapshot", popen.call_args[0][0])

    def test_persistent_boot_checks_the_image_argument(self):
        # image= overrides RHAP_TEST_IMAGE, so the guard must check it
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(rhap_inject.SafetyError):
                self._guest(os.path.join(d, "ufs-backport.img"), persist=True,
                            image=os.path.join(d, "golden.img"))


if __name__ == "__main__":
    unittest.main()
