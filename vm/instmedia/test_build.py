import contextlib
import io
import os
import tempfile
import unittest

import rhap_image
from ufs_extract import Node
from instmedia import apkrepo, build, live, testapks as ta, test_live

BOOT_DRIVERS = ("EISABus", "PCIBus", "PS2Keyboard", "EIDE", "AHCI", "NE2K")
CDIS = "System/Installation/CDIS/"


def make_bootable_repo(directory, drivers=BOOT_DRIVERS + ("BPF",),
                       driver_loader=True, extra=()):
    """test_live's repo plus what a bootable root must have: the boot
    drivers, and BPF, the Active Driver dhcpcd needs."""
    test_live.make_repo(directory)
    ta.make(directory, "boot-64-i386.apk",
            ta.pkginfo("boot", "64", "i386-apple-rhapsody"), [
                ta.f("usr/standalone/i386/boot0", b"\x33" * 446),
                ta.f("usr/standalone/i386/boot1", b"\x44" * 510 + b"\x55\xaa"),
                ta.f("usr/standalone/i386/boot", b"B" * 30000),
                ta.f("usr/standalone/i386/sarld", b"S" * 1000)],
            dot_slash=False)
    ta.make(directory, "kernel-154.5.1-i386.apk",
            ta.pkginfo("kernel", "154.5.1", "i386-apple-rhapsody"), [
                ta.f("mach_kernel", b"K" * 70000, 0o444), ta.d("private"),
                ta.d("private/tftpboot"),
                ta.hard("private/tftpboot/mach_kernel", "mach_kernel")])
    for name in drivers:
        ta.make(directory, "drv%s-1-i386.apk" % name.lower(),
                ta.pkginfo("drv" + name.lower(), "1", "i386-apple-rhapsody"),
                [ta.f("private/Drivers/i386/%s.config/%s_reloc"
                      % (name, name), name.encode() * 100)], dot_slash=False)
    base = [ta.f("usr/sbin/sshd", b"sshd"), ta.f("sbin/mount", b"mount"),
            ta.f("usr/libexec/getty", b"getty"), ta.f("usr/bin/perl", b"pl"),
            ta.f("private/etc/rc.cdrom.PPC", b"1;\n"),
            ta.f(CDIS + "English.lproj/Localizable.strings", b"\"A\" = \"a\";"),
            ta.f(CDIS + "findroot", b"f"), ta.f(CDIS + "gc", b"g"),
            ta.f(CDIS + "popconsole", b"p"),
            ta.dev("private/dev/hd0a", "blk", 3, 0),
            ta.dev("private/dev/rhd0a", "chr", 15, 0),
            ta.dev("private/dev/null", "chr", 3, 2)]
    if driver_loader:
        base.append(ta.f("usr/sbin/driverLoader", b"dl"))
    ta.make(directory, "base-cmds-1-universal.apk", ta.pkginfo("base-cmds"),
            base + list(extra), dot_slash=False)


class TestBuild(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = os.path.join(self.tmp.name, "repo")
        os.mkdir(self.repo)
        self.efi = os.path.join(self.tmp.name, "BOOTIA32.EFI")
        with open(self.efi, "wb") as f:
            f.write(b"MZ" + b"e" * 5000)
        self.out = os.path.join(self.tmp.name, "media.img")

    def tearDown(self):
        self.tmp.cleanup()

    def test_live_media_builds_and_reads_back(self):
        make_bootable_repo(self.repo)
        napks, nnodes, g, total = build.build(self.repo, self.efi, self.out)
        self.assertEqual(napks, 3 + 2 + len(BOOT_DRIVERS) + 1 + 1)
        with rhap_image.Image(self.out) as img:
            self.assertIsNotNone(img.resolve("/private/etc/rc.cdrom"))
            self.assertIsNotNone(
                img.resolve("/System/Installation/Packages/"
                            "kernel-154.5.1-i386.apk"))

    def test_preinstalled_builds_and_reads_back(self):
        make_bootable_repo(self.repo)
        build.build(self.repo, self.efi, self.out, preinstalled=True)
        with rhap_image.Image(self.out) as img:
            self.assertIsNone(img.resolve("/private/etc/rc.cdrom"))
            fstab = img.read_file(img.resolve("/private/etc/fstab"))
        self.assertEqual(fstab, b"/dev/hd0a\t/\tufs\trw\t1 1\n")

    def test_a_missing_boot_driver_is_named(self):
        make_bootable_repo(self.repo, drivers=("EISABus", "PCIBus",
                                               "PS2Keyboard", "EIDE",
                                               "NE2K"))
        with self.assertRaisesRegex(build.BuildError, "AHCI_reloc"):
            build.build(self.repo, self.efi, self.out)
        self.assertFalse(os.path.exists(self.out))

    def test_preinstalled_needs_driverloader(self):
        make_bootable_repo(self.repo, driver_loader=False)
        with self.assertRaisesRegex(build.BuildError,
                                    "missing /usr/sbin/driverLoader"):
            build.build(self.repo, self.efi, self.out, preinstalled=True)

    def test_the_network_card_is_checked_as_a_boot_driver(self):
        make_bootable_repo(self.repo, drivers=BOOT_DRIVERS[:-1])
        with self.assertRaisesRegex(build.BuildError, "NE2K_reloc"):
            build.build(self.repo, self.efi, self.out, preinstalled=True)

    def test_preinstalled_needs_the_bpf_driver(self):
        make_bootable_repo(self.repo, drivers=BOOT_DRIVERS)
        with self.assertRaisesRegex(build.BuildError, "BPF.config/BPF_reloc"):
            build.build(self.repo, self.efi, self.out, preinstalled=True)

    def test_the_media_does_not_need_driverloader(self):
        make_bootable_repo(self.repo, driver_loader=False)
        build.build(self.repo, self.efi, self.out)

    def test_preinstalled_needs_usr_devices_to_reach_the_table(self):
        make_bootable_repo(self.repo)
        nodes, _ = live.compose(apkrepo.index(self.repo), b"E",
                                preinstalled=True, password_hash="x")
        nodes = [n._replace(data="../private/Nowhere")
                 if n.path == "/usr/Devices" else n for n in nodes]
        self.assertIn("/usr/Devices/System.config/Instance0.table does not "
                      "lead", "\n".join(build.check_tree(nodes, True)))

    def test_conflicts_are_refused(self):
        make_bootable_repo(self.repo)
        ta.make(self.repo, "rival-1-universal.apk", ta.pkginfo("rival"),
                [ta.f("usr/sbin/sshd", b"other")], dot_slash=False)
        with self.assertRaisesRegex(build.BuildError,
                                    "/usr/sbin/sshd: claimed by base-cmds "
                                    "and rival"):
            build.build(self.repo, self.efi, self.out)

    def test_a_too_small_filesystem_is_refused(self):
        make_bootable_repo(self.repo, extra=[ta.f("big", b"b" * 3000000)])
        with self.assertRaisesRegex(build.BuildError, "--fs-mb"):
            build.build(self.repo, self.efi, self.out, fs_mb=1)
        self.assertFalse(os.path.exists(self.out))

    def test_main_reports_errors_without_a_traceback(self):
        make_bootable_repo(self.repo, drivers=())
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(build.main(["build", "--repo", self.repo,
                                         "--efi", self.efi, "--out",
                                         self.out]), 1)
        self.assertIn("missing /private/Drivers/i386/EIDE.config/EIDE_reloc",
                      err.getvalue())

    def test_main_reports_a_package_it_cannot_lay_down(self):
        make_bootable_repo(self.repo)
        ta.make(self.repo, "zz-1-universal.apk", ta.pkginfo("zz"),
                [ta.ln("usr/lost", "nowhere/at/all"),
                 ta.f("usr/lost/file", b"x")], dot_slash=False)
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(build.main(["build", "--repo", self.repo,
                                         "--efi", self.efi, "--out",
                                         self.out]), 1)
        self.assertIn("no directory /usr/nowhere", err.getvalue())


class TestChecks(unittest.TestCase):
    def test_dev_majors(self):
        nodes = [Node("/private/dev/hd1a", "blk", 0o640, 0, 5, 0, (3, 8)),
                 Node("/private/dev/rsd0a", "chr", 0o640, 0, 5, 0, (14, 0)),
                 Node("/private/dev/sd0a", "blk", 0o640, 0, 5, 0, (7, 0)),
                 Node("/private/dev/rhd0a", "blk", 0o640, 0, 5, 0, (15, 0)),
                 Node("/private/dev/fd", "dir", 0o555, 0, 0, 0, None),
                 Node("/private/dev/urandom", "chr", 0o644, 0, 0, 0, (17, 1)),
                 Node("/private/dev/tty", "chr", 0o666, 0, 0, 0, (2, 0))]
        self.assertEqual(build.check_dev(nodes), [
            "/private/dev/sd0a is blk 7, the kernel wants blk 6",
            "/private/dev/rhd0a is blk 15, the kernel wants blk 3"])

    def test_controller_character_nodes_take_the_character_major(self):
        # files' MAKEDEV makes fdc0 and sdc0 as character devices of the
        # floppy and SCSI drivers.
        nodes = [Node("/private/dev/fdc0", "chr", 0o644, 0, 0, 0, (41, 64)),
                 Node("/private/dev/sdc0", "chr", 0o644, 0, 0, 0, (14, 0)),
                 Node("/private/dev/hd0_hfs_a", "blk", 0o640, 0, 5, 0,
                      (3, 128))]
        self.assertEqual(build.check_dev(nodes), [])

    def test_boot_drivers(self):
        self.assertEqual(build.boot_drivers(
            b'"Kernel" = "mach_kernel";\n"Boot Drivers" = "EIDE  AHCI";\n'),
            ["EIDE", "AHCI"])
        with self.assertRaises(build.BuildError):
            build.boot_drivers(b'"Kernel" = "mach_kernel";\n')

    def test_fs_sectors_is_whole_megabytes_with_headroom(self):
        nodes = [Node("/a", "reg", 0o644, 0, 0, 0, b"x" * 3000000)]
        got = build.fs_sectors(nodes, 1024 * 1024)
        self.assertEqual(got % 2048, 0)
        self.assertGreaterEqual(got * 512, 3000000 * 5 // 4 + 1024 * 1024)


if __name__ == "__main__":
    unittest.main()
