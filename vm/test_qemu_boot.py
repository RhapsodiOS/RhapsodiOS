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
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "golden.img")
            open(path, "w").close()
            with self.assertRaises(SystemExit):
                qemu_boot.refuse_masters(path)

    def test_rhapsody_vmdk_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "rhapsody.vmdk")
            open(path, "w").close()
            with self.assertRaises(SystemExit):
                qemu_boot.refuse_masters(path)

    def test_master_name_is_refused_case_insensitively(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "Golden.IMG")
            open(path, "w").close()
            with self.assertRaises(SystemExit):
                qemu_boot.refuse_masters(path)

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


class TestRunReportsQemuFailures(unittest.TestCase):
    def _fake_image(self, tmpdir):
        path = os.path.join(tmpdir, "disk.img")
        open(path, "w").close()
        return path

    def test_qmp_connect_failure_names_the_stderr_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            image = self._fake_image(tmp)
            outdir = os.path.join(tmp, "out")
            fake_proc = mock.Mock()
            fake_proc.poll.return_value = 1
            with mock.patch("qemu_boot.subprocess.Popen",
                            return_value=fake_proc), \
                 mock.patch("qemu_boot.qemu_shot.QMP",
                            side_effect=RuntimeError("no connection")):
                with self.assertRaises(SystemExit) as ctx:
                    qemu_boot.run("bios", image, outdir, [1], "fw")
            self.assertIn(os.path.join(outdir, "qemu-stderr.log"),
                         str(ctx.exception))

    def test_lost_qmp_connection_during_screenshot_names_the_stderr_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            image = self._fake_image(tmp)
            outdir = os.path.join(tmp, "out")
            fake_proc = mock.Mock()
            fake_proc.poll.return_value = None
            fake_qmp = mock.Mock()
            fake_qmp.execute.side_effect = ConnectionResetError("reset")
            with mock.patch("qemu_boot.subprocess.Popen",
                            return_value=fake_proc), \
                 mock.patch("qemu_boot.qemu_shot.QMP",
                            return_value=fake_qmp), \
                 mock.patch("qemu_boot.time.sleep", return_value=None):
                with self.assertRaises(SystemExit) as ctx:
                    qemu_boot.run("bios", image, outdir, [1], "fw")
            self.assertIn(os.path.join(outdir, "qemu-stderr.log"),
                         str(ctx.exception))

    def test_popen_failure_closes_the_stderr_log_and_propagates(self):
        # No SystemExit wraps this one: only the QMP-connect and screenshot
        # failures above are translated into a diagnostic SystemExit, because
        # only those have a running QEMU process (and thus a stderr log
        # worth pointing at) to report on. A Popen failure means QEMU never
        # started, so the original error (FileNotFoundError, here standing
        # in for "qemu-system-i386 is not on PATH") is left to propagate
        # unchanged; the fix under test is only that it no longer leaks the
        # open stderr log handle on the way out.
        with tempfile.TemporaryDirectory() as tmp:
            image = self._fake_image(tmp)
            outdir = os.path.join(tmp, "out")
            opened = []

            def tracking_open(*args, **kwargs):
                f = open(*args, **kwargs)
                opened.append(f)
                return f

            with mock.patch("qemu_boot.subprocess.Popen",
                            side_effect=FileNotFoundError("no qemu")), \
                 mock.patch("qemu_boot.open", tracking_open, create=True):
                with self.assertRaises(FileNotFoundError):
                    qemu_boot.run("bios", image, outdir, [1], "fw")
            self.assertEqual(len(opened), 1)
            self.assertTrue(opened[0].closed)


if __name__ == "__main__":
    unittest.main()
