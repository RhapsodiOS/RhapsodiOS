import importlib.util
import os
import pathlib
import tempfile
import unittest
import unittest.mock as mock

import rhap_inject

HERE = pathlib.Path(__file__).parent


def _load_guest_console(image):
    # guest-console.py reads RHAP_TEST_IMAGE when it is imported
    with mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": image}):
        spec = importlib.util.spec_from_file_location(
            "guest_console", HERE / "guest-console.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    return module


class TestPersistGuard(unittest.TestCase):
    """A persistent boot writes the image, so it must refuse protected ones
    before qemu is ever started. qemu is mocked out; nothing boots."""

    def _guest(self, image, persist):
        gc = _load_guest_console(image)
        with tempfile.TemporaryDirectory() as out, \
                mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": image}), \
                mock.patch.object(gc.subprocess, "Popen",
                                  side_effect=RuntimeError("qemu launched")) as popen:
            try:
                gc.Guest(out, persist=persist, port=4499)
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


if __name__ == "__main__":
    unittest.main()
