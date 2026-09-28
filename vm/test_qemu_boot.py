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


class TestSecondDiskAndTyping(unittest.TestCase):
    def test_hd1_is_the_primary_slave_and_snapshotted(self):
        args = qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                    hd1="b.img")
        self.assertIn("file=b.img,format=raw,if=ide,index=1,media=disk",
                      args)
        self.assertIn("-snapshot", args)

    def test_parse_typed(self):
        self.assertEqual(qemu_boot.parse_typed("70:fsck -n /dev/rhd1a"),
                         (70.0, "fsck -n /dev/rhd1a"))
        self.assertEqual(qemu_boot.parse_typed("6:-s"), (6.0, "-s"))

    def test_parse_typed_refuses_bad_specs(self):
        for spec in ("fsck", "5:a|b"):
            with self.assertRaises(ValueError):
                qemu_boot.parse_typed(spec)

    def test_run_types_each_key_then_enter(self):
        with tempfile.TemporaryDirectory() as tmp:
            image = os.path.join(tmp, "disk.img")
            open(image, "w").close()
            fake_qmp = mock.Mock()
            with mock.patch("qemu_boot.subprocess.Popen"), \
                 mock.patch("qemu_boot.qemu_shot.QMP",
                            return_value=fake_qmp), \
                 mock.patch("qemu_boot.time.sleep", return_value=None):
                qemu_boot.run("bios", image, os.path.join(tmp, "out"), [],
                              "fw", typed=[(5.0, "-s")])
            keys = [c.kwargs["keys"] for c in fake_qmp.execute.call_args_list
                    if c.args == ("send-key",)]
            self.assertEqual(keys, [[{"type": "qcode", "data": "minus"}],
                                    [{"type": "qcode", "data": "s"}],
                                    [{"type": "qcode", "data": "ret"}]])

    def test_main_passes_hd1_and_typed_to_run(self):
        with mock.patch("qemu_boot.run") as run:
            qemu_boot.main(["qemu_boot.py", "bios", "a.img", "out",
                            "--hd1", "b.img", "--type", "6:-s",
                            "--type", "70:fsck -n /dev/rhd1a",
                            "--at", "90", "--firmware-dir", "fw"])
        run.assert_called_once_with(
            "bios", "a.img", "out", [90.0], "fw", esp=None, hd1="b.img",
            typed=[(6.0, "-s"), (70.0, "fsck -n /dev/rhd1a")],
            boot_hd1=False, nic=None, ssh_port=None)


class TestInstallMediaHarness(unittest.TestCase):
    def test_boot_hd1_puts_the_media_first_and_keeps_hd0(self):
        args = qemu_boot.build_args("bios", "target.img", "o", 1, "fw",
                                    hd1="media.img", boot_hd1=True)
        self.assertIn("id=hd0,file=target.img,format=raw,if=none", args)
        self.assertIn("ide-hd,drive=hd0,bus=ide.0,unit=0,bootindex=1", args)
        self.assertIn("id=hd1,file=media.img,format=raw,if=none", args)
        self.assertIn("ide-hd,drive=hd1,bus=ide.0,unit=1,bootindex=0", args)
        self.assertNotIn("order=c", args)
        self.assertNotIn("file=media.img,format=raw,if=ide,index=1,"
                         "media=disk", args)
        self.assertIn("-snapshot", args)

    def test_boot_hd1_under_uefi(self):
        args = qemu_boot.build_args("uefi", "target.img", "o", 1, "fw",
                                    hd1="media.img", boot_hd1=True)
        self.assertIn("ide-hd,drive=hd1,bus=ide.0,unit=1,bootindex=0", args)
        self.assertIn("Nehalem", args)

    def test_boot_hd1_needs_hd1(self):
        with self.assertRaises(ValueError):
            qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                 boot_hd1=True)

    def test_nic_with_an_ssh_forward(self):
        args = qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                    nic="ne2k_pci", ssh_port=2549)
        self.assertIn("user,id=n0,hostfwd=tcp:127.0.0.1:2549-:22", args)
        self.assertIn("ne2k_pci,netdev=n0,addr=03.0", args)

    def test_nic_without_a_forward_and_none_by_default(self):
        args = qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                    nic="ne2k_pci")
        self.assertIn("user,id=n0", args)
        self.assertNotIn("-netdev", qemu_boot.build_args(
            "bios", "a.img", "o", 1, "fw"))

    def test_ssh_port_needs_a_nic(self):
        with self.assertRaises(ValueError):
            qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                 ssh_port=2549)

    def test_main_passes_the_harness_options(self):
        with mock.patch("qemu_boot.run") as run:
            qemu_boot.main(["qemu_boot.py", "uefi", "t.img", "out",
                            "--hd1", "m.img", "--boot-hd1", "--nic",
                            "ne2k_pci", "--ssh-port", "2549", "--at", "600",
                            "--firmware-dir", "fw"])
        run.assert_called_once_with(
            "uefi", "t.img", "out", [600.0], "fw", esp=None, hd1="m.img",
            typed=[], boot_hd1=True, nic="ne2k_pci", ssh_port=2549)


if __name__ == "__main__":
    unittest.main()
