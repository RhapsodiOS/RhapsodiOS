import os
import tempfile
import unittest
import unittest.mock as mock

import qemu_boot


class TestBuildArgs(unittest.TestCase):
    def test_bios_boots_seabios_without_pflash(self):
        args = qemu_boot.build_args("bios", "D:/w/disk.img", "D:/out", 4444,
                                    "D:/fw")
        joined = " ".join(args)
        self.assertNotIn("if=pflash", joined)
        self.assertIn("-snapshot", args)
        self.assertIn("file=D:/w/disk.img,format=raw,if=ide,index=0,media=disk",
                      args)
        self.assertIn("file:%s" % os.path.join("D:/out", "console.log"), args)
        self.assertIn("file:%s" % os.path.join("D:/out", "kernel.log"), args)

    def test_uefi_boots_edk2_i386_with_its_vars_copy_in_outdir(self):
        joined = " ".join(qemu_boot.build_args("uefi", "D:/w/disk.img",
                                               "D:/out", 4444, "D:/fw"))
        self.assertIn("readonly=on,file=%s"
                      % os.path.join("D:/fw", "edk2-i386-code.fd"), joined)
        self.assertIn("unit=1,file=%s"
                      % os.path.join("D:/out", "edk2-i386-vars.fd"), joined)
        self.assertIn("-cpu Nehalem", joined)
        self.assertIn("PIIX4_PM.disable_s3=1", joined)
        self.assertIn("-m 256", joined)

    def test_esp_adds_a_virtio_disk(self):
        args = qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                    esp="esp.img")
        self.assertIn("id=esp,file=esp.img,format=raw,if=none", args)
        self.assertIn("virtio-blk-pci,drive=esp", args)

    def test_unknown_mode_raises(self):
        with self.assertRaises(ValueError):
            qemu_boot.build_args("efi", "a.img", "o", 1, "fw")


class TestSafety(unittest.TestCase):
    def test_golden_image_is_refused(self):
        golden = os.path.join(qemu_boot._HERE, "golden.img")
        if not os.path.exists(golden):
            self.skipTest("no vm/golden.img in this checkout")
        with self.assertRaises(SystemExit):
            qemu_boot.refuse_masters(golden)

    def test_other_images_are_allowed(self):
        fd, path = tempfile.mkstemp()
        os.close(fd)
        try:
            qemu_boot.refuse_masters(path)
        finally:
            os.unlink(path)

    def test_default_firmware_dir_is_qemus_share_directory(self):
        with mock.patch("shutil.which",
                        return_value="C:/q/qemu-system-i386.exe"), \
             mock.patch("os.path.realpath", side_effect=lambda p: p):
            self.assertEqual(
                qemu_boot.default_firmware_dir("qemu-system-i386"),
                os.path.join("C:/q", "share"))


if __name__ == "__main__":
    unittest.main()
