import os
import tempfile
import unittest

from instmedia import apkrepo, testapks as ta


class TestMemberName(unittest.TestCase):
    def test_strips_dot_slash_and_slashes(self):
        self.assertEqual(apkrepo.member_name("./usr/bin/"), "usr/bin")
        self.assertEqual(apkrepo.member_name("usr/bin"), "usr/bin")
        self.assertEqual(apkrepo.member_name("././a"), "a")
        self.assertEqual(apkrepo.member_name("."), "")
        self.assertEqual(apkrepo.member_name("./"), "")

    def test_control_members(self):
        for name in (".PKGINFO", ".pre-install", ".post-deinstall",
                     ".SIGN.RSA.key.pub"):
            self.assertTrue(apkrepo.is_control(name))
        for name in (".hidden", "PKGINFO", "usr/.PKGINFO"):
            self.assertFalse(apkrepo.is_control(name))


class TestReadPkginfo(unittest.TestCase):
    def test_reads_it_wherever_it_sits(self):
        with tempfile.TemporaryDirectory() as tmp:
            info = ta.pkginfo("grep", "2.1-1", depend="libsystem csu")
            path = ta.make(tmp, "grep.apk", None,
                           [ta.d("usr"), ta.f(".PKGINFO", info)])
            got = apkrepo.read_pkginfo(path)
            with open(path, "rb") as fh:
                self.assertEqual(apkrepo.read_pkginfo(fh.read()), got)
        self.assertEqual(got["pkgname"], "grep")
        self.assertEqual(got["pkgver"], "2.1-1")
        self.assertEqual(got["depend"], "libsystem csu")

    def test_refuses_an_apk_without_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = ta.make(tmp, "x.apk", None, [ta.d("usr")])
            with self.assertRaises(apkrepo.RepoError):
                apkrepo.read_pkginfo(path)


class TestIndex(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def add(self, filename, name, arch):
        ta.make(self.dir, filename, ta.pkginfo(name, arch=arch))

    def test_prefers_i386_then_universal(self):
        self.add("libc-1-i386.apk", "libc", "i386-apple-rhapsody")
        self.add("libc-1-universal.apk", "libc", "universal-apple-rhapsody")
        self.add("grep-1-universal.apk", "grep", "universal-apple-rhapsody")
        got = apkrepo.index(self.dir)
        self.assertEqual(sorted(got), ["grep", "libc"])
        self.assertEqual(got["libc"].cpu, "i386")
        self.assertEqual(os.path.basename(got["libc"].path),
                         "libc-1-i386.apk")
        self.assertEqual(got["grep"].cpu, "universal")

    def test_leaves_out_hdrs_and_obj_companions(self):
        self.add("libc-1-universal.apk", "libc", "universal-apple-rhapsody")
        self.add("libc-hdrs-1-universal.apk", "libc-hdrs",
                 "universal-apple-rhapsody")
        self.add("libc-obj-1-universal.apk", "libc-obj",
                 "universal-apple-rhapsody")
        self.assertEqual(sorted(apkrepo.index(self.dir)), ["libc"])

    def test_refuses_a_ppc_only_package(self):
        self.add("pexpert-1-ppc.apk", "drvpexpert", "ppc-apple-rhapsody")
        with self.assertRaisesRegex(apkrepo.RepoError, "only for ppc"):
            apkrepo.index(self.dir)

    def test_refuses_two_builds_for_one_cpu(self):
        self.add("files-1-universal.apk", "files", "universal-apple-rhapsody")
        self.add("files-2-universal.apk", "files", "universal-apple-rhapsody")
        with self.assertRaisesRegex(apkrepo.RepoError, "two universal"):
            apkrepo.index(self.dir)

    def test_refuses_an_unknown_arch(self):
        self.add("x-1.apk", "x", "m68k-next-nextstep")
        with self.assertRaises(apkrepo.RepoError):
            apkrepo.index(self.dir)

    def test_ignores_other_files(self):
        self.add("grep-1-universal.apk", "grep", "universal-apple-rhapsody")
        open(os.path.join(self.dir, "grep-1-universal.apk.src"), "w").close()
        self.assertEqual(sorted(apkrepo.index(self.dir)), ["grep"])


if __name__ == "__main__":
    unittest.main()
