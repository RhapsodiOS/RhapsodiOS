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
NAMES = ("fstab", "hostconfig", "Instance0-i386.table", "Instance0-ppc.table")
# Mac OS X Server 1.2.1's /private/Drivers/ppc/System.config/Default.table,
# key by key.  On ppc the booter picks the boot drivers, 0700_Devices names
# the drivers it loads, and the kernel takes its root from Open Firmware,
# so the installed system needs none of the i386 template's overrides.
PPC_TABLE = [(b"Version", b"5.20"),
             (b"Active Drivers",
              b"PPCAwacs Floppy BPF SwitchEthernet PPCSerialPort PortServer"),
             (b"Kernel Flags", b""), (b"Boot Drivers", b""),
             (b"Language", b"English")]

# rc.cdrom's whole text: start the installer, and offer a shell if it fails.
HOOK = [b"#!/bin/sh",
        b"/System/Installation/CDIS/sysinstall || exec /bin/sh", b""]


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

    def test_i386_instance0_has_default_tables_keys_and_the_overrides(self):
        ours = read(TEMPLATES, "Instance0-i386.table")
        default = read(SRC, "system_config-1", "i386", "Default.table")
        self.assertEqual(table_keys(ours), table_keys(default))
        self.assertEqual(table_value(ours, b"Boot Drivers"),
                         b"PS2Keyboard EIDE AHCI NE2K")
        self.assertEqual(table_value(ours, b"Active Drivers"),
                         table_value(default, b"Active Drivers") + b" BPF")
        self.assertEqual(table_value(ours, b"Kernel Flags"),
                         b"rootdev=@DISK@a")
        self.assertEqual(table_value(ours, b"Boot Graphics"), b"No")
        for key in (b"Version", b"Kernel", b"Install Mode", b"APM"):
            self.assertEqual(table_value(ours, key),
                             table_value(default, key))

    def test_i386_boot_sources_use_the_kernel_linked_buses(self):
        network = read(SRC, "system_config-1", "i386", "Instance0.network")
        self.assertEqual(table_value(network, b"Boot Drivers"), b"PS2Keyboard")
        detector = read(SRC, "driverkit-3", "driverDetect", "driverDetect.c")
        self.assertRegex(detector, rb'#define BASE_BOOT\s+"PS2Keyboard"')

    def test_ppc_instance0_is_mac_os_x_servers_table(self):
        ours = read(TEMPLATES, "Instance0-ppc.table")
        self.assertEqual(
            re.findall(rb'^"([^"]+)"\s*=\s*"([^"]*)";', ours, re.M),
            PPC_TABLE)

    def test_the_postamble_installs_every_template(self):
        postamble = read(PROJECT, "Makefile.postamble")
        for name in NAMES:
            self.assertIn(b"templates/" + name.encode(), postamble)

    def test_english_only_and_the_hook(self):
        names = os.listdir(PROJECT)
        self.assertEqual([n for n in names if n.endswith(".lproj")],
                         ["English.lproj"])
        self.assertNotIn("rc.cdrom.x86", names)
        self.assertNotIn("rc.cdrom.PPC", names)
        self.assertEqual(read(PROJECT, "rc.cdrom").split(b"\n"), HOOK)
        postamble = read(PROJECT, "Makefile.postamble")
        self.assertRegex(
            postamble,
            rb"sets/\*\.set \$\(DSTROOT\)/System/Installation/Sets\n")
        self.assertNotIn(b"SCRIPT2", postamble)
        self.assertNotIn(b"SCRIPT3", postamble)
        tools = re.search(rb"^TOOLS = ((?:.*\\\n)*.*)$",
                          read(PROJECT, "Makefile"), re.M).group(1)
        self.assertIn(b"sysinstall.tproj", tools.split())

    def test_no_carriage_returns(self):
        for name in NAMES:
            self.assertNotIn(b"\r", read(TEMPLATES, name), name)


if __name__ == "__main__":
    unittest.main()
