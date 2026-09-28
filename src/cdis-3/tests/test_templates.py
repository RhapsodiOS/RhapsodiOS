"""The installed-system templates against the files they derive from.

    cd src/cdis-3 && python -m unittest discover -s tests -v
"""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
SRC = os.path.dirname(PROJECT)
TEMPLATES = os.path.join(PROJECT, "templates")
NAMES = ("fstab", "hostconfig", "Instance0.table")


def read(*parts):
    with open(os.path.join(*parts), "rb") as f:
        return f.read()


def table_keys(text):
    return re.findall(rb'^"([^"]+)"\s*=', text, re.M)


def table_value(text, key):
    return re.search(rb'^"%s"\s*=\s*"([^"]*)";' % re.escape(key), text,
                     re.M).group(1)


class TestTemplates(unittest.TestCase):
    def test_fstab_is_fstab_hds_root_line(self):
        root_line = read(SRC, "files-5", "private", "etc",
                         "fstab.hd").split(b"\n")[0] + b"\n"
        self.assertEqual(read(TEMPLATES, "fstab").replace(b"@DISK@", b"hd0"),
                         root_line)

    def test_hostconfig_is_files_copy_with_three_services_off(self):
        ours = read(TEMPLATES, "hostconfig").split(b"\n")
        theirs = read(SRC, "files-5", "private", "etc",
                      "hostconfig").split(b"\n")
        self.assertEqual(len(ours), len(theirs))
        changed = [(a, b) for a, b in zip(theirs, ours) if a != b]
        self.assertEqual(changed, [
            (b"APPLETALK=-YES-", b"APPLETALK=-NO-"),
            (b"AUTOMOUNT=-YES-", b"AUTOMOUNT=-NO-"),
            (b"TIMESYNC=-YES-", b"TIMESYNC=-NO-")])
        self.assertIn(b"SSHSERVER=-YES-", ours)

    def test_instance0_has_default_tables_keys_and_the_overrides(self):
        ours = read(TEMPLATES, "Instance0.table")
        default = read(SRC, "system_config-1", "i386", "Default.table")
        self.assertEqual(table_keys(ours), table_keys(default))
        self.assertEqual(table_value(ours, b"Boot Drivers"),
                         b"EISABus PCIBus PS2Keyboard EIDE AHCI NE2K")
        self.assertEqual(table_value(ours, b"Kernel Flags"),
                         b"rootdev=@DISK@a")
        self.assertEqual(table_value(ours, b"Boot Graphics"), b"No")
        for key in (b"Version", b"Active Drivers", b"Kernel",
                    b"Install Mode", b"APM"):
            self.assertEqual(table_value(ours, key),
                             table_value(default, key))

    def test_the_postamble_installs_every_template(self):
        postamble = read(PROJECT, "Makefile.postamble")
        for name in NAMES:
            self.assertIn(b"templates/" + name.encode(), postamble)

    def test_no_carriage_returns(self):
        for name in NAMES:
            self.assertNotIn(b"\r", read(TEMPLATES, name), name)


if __name__ == "__main__":
    unittest.main()
