import gzip
import os
import tempfile
import unittest

from instmedia import apkrepo, live, testapks as ta

PASSWD = (b"##\n# comment\n##\nnobody:*:-2:-2::0:0:Unprivileged:/:/dev/null\n"
          b"root:*:0:0::0:0:System Administrator:/:/bin/tcsh\n")
TABLE = (b'"Boot Drivers" = "EISABus PCIBus PS2Keyboard EIDE AHCI NE2K";\n'
         b'"Active Drivers" = "VGA";\n'
         b'"Kernel Flags" = "rootdev=@DISK@a";\n')
FSTAB = b"/dev/@DISK@a\t/\tufs\trw\t1 1\n"
HOSTCONFIG = b"APPLETALK=-NO-\nSSHSERVER=-YES-\n"
RC_CDROM = b"#!/usr/bin/perl -w\nprint 'installer';\n"


def make_repo(directory):
    """files, cdis and one package that installs through etc/."""
    ta.make(directory, "files-1-universal.apk", ta.pkginfo("files"), [
        ta.d("private"), ta.d("private/etc"), ta.ln("etc", "private/etc"),
        ta.d("usr"), ta.ln("usr/Devices", "../private/Devices"),
        ta.f("private/etc/master.passwd", PASSWD, 0o600),
        ta.f("private/etc/hostconfig", b"APPLETALK=-YES-\n"),
        ta.d("System"), ta.d("private/Drivers"),
        ta.d("private/Drivers/i386"),
        ta.d("private/Drivers/i386/System.config")])
    cdis = "System/Installation/CDIS/"
    ta.make(directory, "cdis-156.1-universal.apk", ta.pkginfo("cdis"), [
        ta.d("System/Installation"), ta.d("System/Installation/CDIS"),
        ta.f(cdis + "pickdisk", b"pickdisk", 0o555),
        ta.d(cdis + "templates"),
        ta.f(cdis + "templates/fstab", FSTAB, 0o444),
        ta.f(cdis + "templates/Instance0.table", TABLE, 0o444),
        ta.f(cdis + "templates/hostconfig", HOSTCONFIG, 0o444),
        ta.f("private/etc/rc.cdrom.hidden", RC_CDROM, 0o555),
        ta.f("private/etc/rc.cdrom.x86", b"1;\n", 0o444),
        ta.d("private/var"), ta.d("private/var/tmp"),
        ta.d("private/var/tmp/mnta")], dot_slash=False)
    ta.make(directory, "aaa-1-universal.apk", ta.pkginfo("aaa"),
            [ta.f("etc/aaa.conf", b"a")], dot_slash=False)


class TestRender(unittest.TestCase):
    def test_render_and_password(self):
        self.assertEqual(live.render(FSTAB, "hd0"),
                         b"/dev/hd0a\t/\tufs\trw\t1 1\n")
        got = live.set_root_password(PASSWD, "rhME8brSxdukA")
        self.assertIn(b"\nroot:rhME8brSxdukA:0:0::0:0:System Administrator"
                      b":/:/bin/tcsh\n", got)
        self.assertIn(b"nobody:*:", got)
        with self.assertRaises(live.ComposeError):
            live.set_root_password(b"nobody:*:1:1\n", "x")


class TestCompose(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        make_repo(cls.tmp.name)
        cls.apks = apkrepo.index(cls.tmp.name)
        cls.esp = b"E" * 4096
        nodes, cls.conflicts = live.compose(cls.apks, cls.esp)
        cls.live = {n.path: n for n in nodes}
        nodes, _ = live.compose(cls.apks, cls.esp, preinstalled=True,
                                password_hash="rhME8brSxdukA")
        cls.pre = {n.path: n for n in nodes}

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_files_goes_first_so_packages_follow_its_links(self):
        self.assertEqual(live.install_order(self.apks)[0].name, "files")
        self.assertEqual(self.live["/private/etc/aaa.conf"].data, b"a")
        self.assertEqual(self.conflicts, [])

    def test_live_overlay_makes_cdis_live(self):
        rc = self.live[live.RC_CDROM]
        self.assertEqual((rc.kind, rc.mode, rc.data), ("reg", 0o755, RC_CDROM))
        self.assertEqual(self.live[live.RC_CDROM_INERT].data, RC_CDROM)
        self.assertEqual(self.live[live.SYSTEM_TABLE].data,
                         live.render(TABLE, "hd1"))
        self.assertEqual(self.live["/private/var/tmp/mnta"].kind, "dir")

    def test_live_carries_every_apk_and_the_esp(self):
        for fn in os.listdir(self.tmp.name):
            with open(os.path.join(self.tmp.name, fn), "rb") as f:
                self.assertEqual(
                    self.live["/System/Installation/Packages/" + fn].data,
                    f.read())
        self.assertEqual(gzip.decompress(
            self.live["/System/Installation/esp.img.gz"].data), self.esp)

    def test_preinstalled_renders_the_templates_for_hd0(self):
        self.assertEqual(self.pre[live.FSTAB].data,
                         b"/dev/hd0a\t/\tufs\trw\t1 1\n")
        self.assertEqual(self.pre[live.SYSTEM_TABLE].data,
                         live.render(TABLE, "hd0"))
        self.assertEqual(self.pre[live.HOSTCONFIG].data, HOSTCONFIG)
        passwd = self.pre[live.MASTER_PASSWD]
        self.assertEqual(passwd.mode, 0o600)
        self.assertIn(b"\nroot:rhME8brSxdukA:", passwd.data)

    def test_preinstalled_does_not_start_the_installer(self):
        self.assertNotIn(live.RC_CDROM, self.pre)
        self.assertNotIn("/System/Installation/Packages", self.pre)
        self.assertNotIn("/System/Installation/esp.img.gz", self.pre)
        self.assertNotIn(live.FSTAB, self.live)

    def test_every_node_takes_a_time_from_the_apks(self):
        for n in self.live.values():
            self.assertLessEqual(n.mtime, ta.T)

    def test_no_files_apk_is_refused(self):
        with self.assertRaises(live.ComposeError):
            live.compose({k: v for k, v in self.apks.items()
                          if k != "files"}, self.esp)

    def test_preinstalled_needs_a_password(self):
        with self.assertRaises(live.ComposeError):
            live.compose(self.apks, self.esp, preinstalled=True)


if __name__ == "__main__":
    unittest.main()
