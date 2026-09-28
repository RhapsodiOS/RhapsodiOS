import os
import random
import unittest

from instmedia import collect, testapks as ta

IMAGE = os.environ.get("RHAPSODY_BOOTSTRAP_IMAGE")


def apk(name, pkgname, arch="universal-apple-rhapsody", body=b"x"):
    return (name, ta.tar_bytes(ta.pkginfo(pkgname, arch=arch),
                               [ta.f("usr/share/" + name, body)]))


class TestMerge(unittest.TestCase):
    def test_a_later_source_replaces_every_build_of_a_package(self):
        base = [apk("files-1-universal.apk", "files"),
                apk("grep-1-universal.apk", "grep")]
        added = [apk("files-1-universal.apk", "files", body=b"new"),
                 apk("kernel-1-i386.apk", "kernel", "i386-apple-rhapsody")]
        got = collect.merge(base, added)
        self.assertEqual(sorted(got), ["files-1-universal.apk",
                                       "grep-1-universal.apk",
                                       "kernel-1-i386.apk"])
        self.assertEqual(got["files-1-universal.apk"], added[0][1])

    def test_a_renamed_rebuild_drops_the_old_file(self):
        got = collect.merge([apk("files-1-universal.apk", "files")],
                            [apk("files-2-universal.apk", "files")])
        self.assertEqual(sorted(got), ["files-2-universal.apk"])

    def test_damaged_apks_are_refused(self):
        name, data = apk("grep-1-universal.apk", "grep", body=b"y" * 5000)
        with self.assertRaisesRegex(collect.CollectError, "damaged"):
            collect.merge([(name, data[:len(data) // 2])])

    def test_a_block_from_another_file_is_refused_wherever_it_lands(self):
        # A DUP block on the image puts another file's data in an apk.
        r = random.Random(4)

        def many(pkgname):
            return ta.tar_bytes(ta.pkginfo(pkgname), [
                ta.f("usr/share/%s/%d" % (pkgname, i),
                     bytes(r.randrange(256) for _ in range(3000)))
                for i in range(20)])
        data, other = many("grep"), many("sed")
        for off in range(0, len(data) - 1024, 1024):
            bad = data[:off] + other[off:off + 1024] + data[off + 1024:]
            with self.subTest(off=off), self.assertRaisesRegex(
                    collect.CollectError, "damaged"):
                collect.verify("grep-1-universal.apk", bad)

    def test_the_same_filename_twice_in_one_source_is_refused(self):
        with self.assertRaises(collect.CollectError):
            collect.merge([apk("a.apk", "a"), apk("a.apk", "b")])


@unittest.skipUnless(IMAGE, "set RHAPSODY_BOOTSTRAP_IMAGE to the "
                     "bootstrapped guest image to read its repository")
class TestImage(unittest.TestCase):
    def test_reads_the_universal_bootstrap_apks(self):
        got = collect.image_apks(IMAGE)
        names = [n for n, _ in got]
        self.assertEqual(len(names), 68)
        self.assertIn("libsystem-25.1-2-universal.apk", names)
        self.assertTrue(all(n.endswith("-universal.apk") for n in names))
        collect.merge(got)
