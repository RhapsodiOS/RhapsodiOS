"""Build a hybrid MBR disk: a FAT16 EFI System Partition holding the UEFI
loader, followed by an existing Rhapsody partition copied verbatim.

MBR rather than GPT, so read_label() in boot-2's disk.c keeps finding the
Rhapsody partition by its 0xA7 system id.
"""

import os
import shutil
import struct
import subprocess
import sys

SECTOR = 512
MBR_PART_OFFSET = 446
FDISK_NEXTNAME = 0xA7
EFI_SYSTEM = 0xEF
ESP_LBA = 2048  # 1 MB in, the conventional alignment
CHS_OUT_OF_RANGE = b"\xfe\xff\xff"

MTOOLS = ("mformat", "mmd", "mcopy")


def _require_mtools():
    missing = [t for t in MTOOLS if shutil.which(t) is None]
    if missing:
        raise RuntimeError(
            "missing mtools binaries: %s (install mtools, e.g. "
            "'brew install mtools' or 'apt-get install mtools')"
            % ", ".join(missing))


def _part_entry(systid, lba_start, nsectors):
    return (b"\x00" + CHS_OUT_OF_RANGE + bytes([systid]) + CHS_OUT_OF_RANGE
            + struct.pack("<II", lba_start, nsectors))


def _run(argv):
    proc = subprocess.run(argv, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT)
    if proc.returncode != 0:
        raise RuntimeError("%s failed: %s"
                           % (argv[0], proc.stdout.decode(errors="replace")))


def build(rhapsody_image, efi_app, out_path, esp_mb=16):
    """Write a hybrid MBR disk to out_path."""
    for path in (rhapsody_image, efi_app):
        if not os.path.exists(path):
            raise RuntimeError("no such file: %s" % path)
    _require_mtools()

    esp_sectors = esp_mb * 1024 * 1024 // SECTOR
    rhapsody_bytes = os.path.getsize(rhapsody_image)
    if rhapsody_bytes % SECTOR:
        raise RuntimeError("%s is not a whole number of %d-byte sectors"
                           % (rhapsody_image, SECTOR))
    rhapsody_sectors = rhapsody_bytes // SECTOR
    rhapsody_lba = ESP_LBA + esp_sectors
    total_sectors = rhapsody_lba + rhapsody_sectors

    with open(out_path, "wb") as out:
        out.truncate(total_sectors * SECTOR)

        mbr = bytearray(SECTOR)
        entries = (_part_entry(EFI_SYSTEM, ESP_LBA, esp_sectors)
                   + _part_entry(FDISK_NEXTNAME, rhapsody_lba,
                                 rhapsody_sectors))
        mbr[MBR_PART_OFFSET:MBR_PART_OFFSET + len(entries)] = entries
        mbr[510:512] = b"\x55\xaa"
        out.seek(0)
        out.write(mbr)

        out.seek(rhapsody_lba * SECTOR)
        with open(rhapsody_image, "rb") as src:
            shutil.copyfileobj(src, out, length=1024 * 1024)

    at = "%s@@%d" % (out_path, ESP_LBA * SECTOR)
    _run(["mformat", "-i", at, "-F", "-v", "RHAPEFI", "::"])
    _run(["mmd", "-i", at, "::/EFI"])
    _run(["mmd", "-i", at, "::/EFI/BOOT"])
    _run(["mcopy", "-i", at, efi_app, "::/EFI/BOOT/BOOTIA32.EFI"])


def main(argv):
    if len(argv) not in (4, 5):
        sys.stderr.write(
            "usage: %s RHAPSODY_IMAGE EFI_APP OUT_PATH [ESP_MB]\n" % argv[0])
        return 2
    esp_mb = int(argv[4]) if len(argv) == 5 else 16
    build(argv[1], argv[2], argv[3], esp_mb=esp_mb)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
