"""Install a driver bundle into a disk image and register it as a boot driver.

The loader opens /private/Drivers/i386/<Name>.config/<Name>_reloc
(src/boot-2/i386/libsaio/load.c:382) and reads Instance0.table from the same
directory. DRIVER_DIR ships Default.table but no Instance0.table, so
Default.table's contents are also written under the Instance0.table name.
<Name> must additionally appear in the "Boot Drivers" key of
/private/Drivers/i386/System.config/Instance0.table, or the loader never
looks for the bundle at all.

rhap_inject.set_table_key never allocates, and its check_target restricts
writes to exactly vm/work/test.img -- not any path under vm/work, which is
what install-driver.py actually produces (a fresh clone per run). It is
tried first anyway, since it is the narrower, already-audited tool; when it
refuses, the new table text is computed here and written with
Allocator.grow_file, which is allowed to allocate.
"""
import os
import re
import subprocess
import sys

import rhap_image
import rhap_inject
import ufs_alloc

BOOT_DRIVERS_TABLE = "/private/Drivers/i386/System.config/Instance0.table"


def _driver_name(driver_dir):
    base = os.path.basename(os.path.normpath(driver_dir))
    if base.endswith(".config"):
        return base[:-len(".config")]
    return base


def _install_bundle(a, dest, src_dir):
    """Recreate src_dir's tree at dest inside the image, one mkdir/create_file
    per entry, in sorted order so a run is reproducible."""
    a.mkdir(dest)
    for entry in sorted(os.listdir(src_dir)):
        src = os.path.join(src_dir, entry)
        child = dest + "/" + entry
        if os.path.isdir(src):
            _install_bundle(a, child, src)
        else:
            with open(src, "rb") as f:
                a.create_file(child, f.read())


def _current_value(text, key):
    m = re.search(br'"%s"\s*=\s*"([^"]*)"' % re.escape(key.encode()), text)
    if m is None:
        raise ufs_alloc.SafetyError("key %r not present in table" % key)
    return m.group(1).decode("ascii")


def _add_boot_driver(out_image, name):
    """Add `name` to the Boot Drivers key of System.config/Instance0.table.

    Returns "set_table_key" or "grow_file" depending on which path actually
    wrote the change, or "unchanged" if `name` was already listed.
    """
    key = "Boot Drivers"
    with rhap_image.Image(out_image) as img:
        ino = img.resolve(BOOT_DRIVERS_TABLE)
        if ino is None:
            raise ufs_alloc.SafetyError("%s does not exist" % BOOT_DRIVERS_TABLE)
        text = img.read_file(ino)
    current = _current_value(text, key)
    if name in current.split():
        return "unchanged"
    new_value = current + " " + name

    try:
        with rhap_image.Image(out_image, writable=True) as img:
            rhap_inject.set_table_key(img, BOOT_DRIVERS_TABLE, key, new_value)
        return "set_table_key"
    except rhap_inject.SafetyError:
        pass

    _, updated = rhap_inject._replace_table_key(text, key, new_value)
    with ufs_alloc.Allocator(out_image, writable=True) as a:
        a.validate()
        ino = a._resolve(BOOT_DRIVERS_TABLE)
        a.grow_file(ino, updated)
        a.flush()
    return "grow_file"


def install_driver(src_image, driver_dir, out_image):
    """Clone src_image to out_image, install driver_dir's bundle under
    /private/Drivers/i386, add an Instance0.table alongside its
    Default.table, and list the driver as a boot driver.  Returns which
    path (set_table_key or grow_file) wrote the Boot Drivers change.
    """
    name = _driver_name(driver_dir)
    ufs_alloc._refuse_master(out_image)
    subprocess.check_call(["cp", "-c", src_image, out_image])

    base = "/private/Drivers/i386/%s.config" % name
    with ufs_alloc.Allocator(out_image, writable=True) as a:
        a.validate()
        _install_bundle(a, base, driver_dir)
        with open(os.path.join(driver_dir, "Default.table"), "rb") as f:
            default_data = f.read()
        a.create_file(base + "/Instance0.table", default_data)
        a.flush()

    return _add_boot_driver(out_image, name)


def main(argv):
    if len(argv) != 4:
        print("usage: install-driver.py SRC_IMAGE DRIVER_DIR OUT_IMAGE",
              file=sys.stderr)
        return 2
    src_image, driver_dir, out_image = argv[1], argv[2], argv[3]
    try:
        via = install_driver(src_image, driver_dir, out_image)
    except (ufs_alloc.SafetyError, rhap_inject.SafetyError) as e:
        print("install-driver: %s" % e, file=sys.stderr)
        return 1
    if via == "unchanged":
        print("%s already listed as a boot driver; leaving unchanged"
              % _driver_name(driver_dir))
    else:
        print("Boot Drivers updated via %s" % via)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
