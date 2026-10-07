"""The floppy and DOS boot code is gone from boot-2 and cdis-3 (phase 6)."""
import os
import unittest

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")
I386 = os.path.join(SRC, "boot-2", "i386")
CDIS = os.path.join(SRC, "cdis-3")

REMOVED = [
    os.path.join(I386, "boot0", "boot0.asm"),
    os.path.join(I386, "boot1", "boot1.asm"),
    os.path.join(I386, "boot1", "boot1f"),
    os.path.join(I386, "boot1", "nullboot1"),
    os.path.join(I386, "boot1", "nullboot1.s"),
    os.path.join(I386, "boot1", "nullboot1.asm"),
    os.path.join(I386, "boot1", "gonext.c"),
    os.path.join(I386, "boot1", "gonext.com"),
    os.path.join(I386, "boot1", "replace.c"),
    os.path.join(I386, "boot1", "makefile.dos"),
    os.path.join(I386, "boot1", "mkboot.bat"),
    os.path.join(CDIS, "mkbootfloppy.sh"),
    os.path.join(CDIS, "mkdriverfloppy.sh"),
    os.path.join(CDIS, "mkinstallcd.sh"),
    os.path.join(CDIS, "README.mkinstallcd.md"),
]


def read(*parts):
    with open(os.path.join(I386, *parts), encoding="latin-1") as f:
        return f.read()


class TestBootCleanup(unittest.TestCase):
    def test_floppy_and_dos_boot_code_is_gone(self):
        for path in REMOVED:
            self.assertFalse(os.path.exists(path), path)
        makefile = read("boot1", "Makefile")
        for word in ("boot1f", "nullboot1", "FOREIGNDOS", "/usr/Dos"):
            self.assertFalse(word in makefile, word)
        self.assertFalse("FLOPPY" in read("boot1", "boot1.s"))
        boot = read("boot2", "boot.c")
        for word in ("DEV_FLOPPY", "Insert file system media",
                     "Insert Driver Disk", "floppy disk"):
            self.assertFalse(word in boot, word)
        drivers = read("libsaio", "drivers.c")
        for word in ("fd()", "Load Other Drivers?", "Missing Drivers:"):
            self.assertFalse(word in drivers, word)

    def test_floppy_motor_shutoff_is_kept(self):
        self.assertTrue("void turnOffFloppy(void)" in read("libsaio", "misc.c"))

    def test_boot0_has_no_menu_strings(self):
        boot0 = read("boot0", "boot0.s")
        for word in ("Type r for Rhapsody", "gotkey", "70h", "int\t16h"):
            self.assertFalse(word in boot0, word)
        for word in ("found_active", "int\t18h"):
            self.assertTrue(word in boot0, word)


if __name__ == "__main__":
    unittest.main()
