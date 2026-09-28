import os
import tempfile
import unittest

from ufs_extract import Node
from instmedia import rootfs, testapks as ta

T = ta.T
FILES = [ta.d("private"), ta.d("private/etc"), ta.ln("etc", "private/etc"),
         ta.f(".hidden", b"mach\n"), ta.d("usr"),
         ta.d("private/dev"), ta.dev("private/dev/hd0a", "blk", 3, 0),
         ta.dev("private/dev/rhd0a", "chr", 15, 0),
         ta.f("private/etc/motd", b"hi\n")]


def tree_of(*apks):
    """A Tree holding the given (owner, members, dot_slash) apks."""
    tree = rootfs.Tree()
    for owner, members, dot_slash in apks:
        rootfs.add_apk(tree, ta.tar_bytes(ta.pkginfo(owner), members,
                                          dot_slash), owner)
    return tree


class TestAddApk(unittest.TestCase):
    def test_every_kind_lands_with_its_metadata(self):
        tree = tree_of(("files", FILES, True))
        self.assertEqual(tree.get("/etc"),
                         Node("/etc", "lnk", 0o755, 0, 0, T, "private/etc"))
        self.assertEqual(tree.get("/private/dev/hd0a").data, (3, 0))
        self.assertEqual(tree.get("/private/dev/hd0a").kind, "blk")
        self.assertEqual(tree.get("/private/dev/rhd0a").kind, "chr")
        self.assertEqual(tree.get("/private/etc/motd").mode, 0o644)
        self.assertEqual(tree.conflicts, [])

    def test_control_members_are_skipped_and_dot_files_kept(self):
        members = [ta.f(".post-install", b"#!/bin/sh\n", 0o755),
                   ta.f(".hidden", b"x")]
        tree = tree_of(("files", members, True))
        self.assertIsNone(tree.get("/.PKGINFO"))
        self.assertIsNone(tree.get("/.post-install"))
        self.assertEqual(tree.get("/.hidden").data, b"x")

    def test_names_without_dot_slash_read_the_same(self):
        a = tree_of(("files", FILES, True)).nodes()
        b = tree_of(("files", FILES, False)).nodes()
        self.assertEqual(a, b)

    def test_a_symlinked_parent_is_followed(self):
        tree = tree_of(("files", FILES, True),
                       ("openssh", [ta.d("etc"), ta.f("etc/ssh_config", b"c")],
                        False))
        self.assertEqual(tree.get("/private/etc/ssh_config").data, b"c")
        self.assertIsNone(tree.get("/etc/ssh_config"))
        self.assertEqual(tree.get("/etc").kind, "lnk")
        self.assertEqual(tree.conflicts, [])

    def test_missing_parents_are_made(self):
        tree = tree_of(("zlib", [ta.f("usr/lib/libz.a", b"z")], False))
        self.assertEqual(tree.get("/usr").kind, "dir")
        self.assertEqual(tree.get("/usr/lib").kind, "dir")

    def test_hard_link_names_its_target(self):
        tree = tree_of(("kernel", [ta.f("mach_kernel", b"k" * 100, 0o444),
                                   ta.d("private"), ta.d("private/tftpboot"),
                                   ta.hard("private/tftpboot/mach_kernel",
                                           "mach_kernel")], True))
        self.assertEqual(tree.get("/private/tftpboot/mach_kernel").data,
                         "/mach_kernel")
        self.assertEqual(tree.data("/private/tftpboot/mach_kernel"),
                         b"k" * 100)

    def test_hard_link_to_nothing_is_refused(self):
        with self.assertRaises(rootfs.TreeError):
            tree_of(("x", [ta.hard("b", "a")], False))

    def test_extracting_through_a_dangling_symlink_is_refused(self):
        with self.assertRaises(rootfs.TreeError):
            tree_of(("files", [ta.ln("usr", "nowhere/at/all")], False),
                    ("x", [ta.f("usr/bin/x", b"x")], False))


class TestConflicts(unittest.TestCase):
    def test_a_file_two_packages_claim_is_reported_and_first_kept(self):
        tree = tree_of(("files", FILES, True),
                       ("other", [ta.f("private/etc/motd", b"no\n")], False))
        self.assertEqual(tree.conflicts, [rootfs.Conflict(
            "/private/etc/motd", "files", "other")])
        self.assertEqual(tree.data("/private/etc/motd"), b"hi\n")

    def test_a_claim_through_a_symlink_is_reported_at_the_real_path(self):
        tree = tree_of(("files", FILES, True),
                       ("other", [ta.f("etc/motd", b"no\n")], False))
        self.assertEqual([c.path for c in tree.conflicts],
                         ["/private/etc/motd"])

    def test_shared_directories_merge(self):
        tree = tree_of(("a", [ta.d("usr"), ta.d("usr/bin"),
                              ta.f("usr/bin/a", b"a")], False),
                       ("b", [ta.d("usr"), ta.d("usr/bin"),
                              ta.f("usr/bin/b", b"b")], False))
        self.assertEqual(tree.conflicts, [])
        self.assertEqual(tree.data("/usr/bin/b"), b"b")

    def test_a_directory_over_a_file_is_a_conflict(self):
        tree = tree_of(("a", [ta.f("x", b"a")], False),
                       ("b", [ta.d("x")], False))
        self.assertEqual(tree.conflicts, [rootfs.Conflict("/x", "a", "b")])
        self.assertEqual(tree.get("/x").kind, "reg")

    def test_a_file_over_a_directory_is_a_conflict(self):
        tree = tree_of(("a", [ta.d("x")], False),
                       ("b", [ta.f("x", b"b")], False))
        self.assertEqual(tree.conflicts, [rootfs.Conflict("/x", "a", "b")])


class TestPutAndNodes(unittest.TestCase):
    def test_put_replaces_and_makes_parents(self):
        tree = tree_of(("files", FILES, True))
        tree.put(Node("/etc/motd", "reg", 0o600, 0, 0, T + 5, b"new\n"))
        tree.put(Node("/Local/Library/Receipts", "dir", 0o755, 0, 0, T, None))
        self.assertEqual(tree.get("/private/etc/motd"),
                         Node("/private/etc/motd", "reg", 0o600, 0, 0,
                              T + 5, b"new\n"))
        self.assertEqual(tree.get("/Local/Library").kind, "dir")
        self.assertEqual(tree.conflicts, [])

    def test_put_refuses_a_file_over_a_directory(self):
        tree = tree_of(("files", FILES, True))
        with self.assertRaises(rootfs.TreeError):
            tree.put(Node("/usr", "reg", 0o644, 0, 0, T, b"x"))

    def test_nodes_put_each_directory_before_its_contents(self):
        tree = tree_of(("z", [ta.f("b/c/d", b"x"), ta.f("a", b"y"),
                              ta.f("b-c", b"z")], False))
        paths = [n.path for n in tree.nodes()]
        self.assertEqual(paths[0], "/")
        for i, p in enumerate(paths[1:], 1):
            self.assertIn(os.path.dirname(p), paths[:i])
        self.assertEqual(paths, sorted(paths, key=rootfs._sort_key))

    def test_newest_mtime(self):
        tree = tree_of(("z", [ta.f("a", b"y", mtime=T + 99)], False))
        self.assertEqual(tree.newest_mtime(), T + 99)


if __name__ == "__main__":
    unittest.main()
