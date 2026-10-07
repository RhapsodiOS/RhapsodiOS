# Bootable installer ISO

**Date:** 2026-10-07
**Status:** Implemented 2026-10-07; see `docs/build/instmedia-cd.md`
**Scope:** phase 6 of the install-media design
(`docs/superpowers/specs/2026-09-22-install-media-design.md`); GitHub issue
RhapsodiOS/RhapsodiOS#38. It builds on phase 5a's installer
(`docs/superpowers/specs/2026-10-05-sysinstall-design.md`,
`docs/build/sysinstall.md`).

## Goal

One command on the Windows host builds a bootable El Torito ISO of the
installer:
- It boots under `qemu -cdrom` with SeaBIOS and with IA32 UEFI, to
  `sysinstall`'s Welcome screen.
- An install from it onto a blank disk completes.
- The installed disk boots alone under both firmwares to `login:` and
  accepts SSH with the password chosen during install.

## Decisions

| Question | Decision |
|---|---|
| Where it's built | On the Windows host: `python -m instmedia.build --form cd`, beside the disk form, pure Python, no `mkisofs` |
| BIOS boot | El Torito **hard-disk emulation**: a small disk image with the usual `boot0` / `0xA7` / `boot1` / `boot2` layout and a tiny UFS holding the kernel and boot drivers |
| UEFI boot | El Torito EFI entry pointing at the same 64 MB ESP image the disk form uses |
| Root | The live root UFS on the CD itself (fsize 2048), found by the kernel with `rootdev=cdrom` |
| What ISO readers see | The boot images, the boot catalog and a short `README.TXT`. The UFS is invisible to them |

The umbrella spec planned a 2.88 MB floppy image for BIOS boot. Hard-disk
emulation replaces it: there's no size squeeze, and it uses the same `boot1`
path every installed disk boots through.

## Constraints from the tree

**BIOS boot path**
- `boot1` (the hard-disk build) reads the fdisk table, then the label at
  `relsect + 15`, then `boot2`, with INT 13h CHS reads using the geometry
  INT 13h/08h reports (`src/boot-2/i386/boot1/boot1.s`).
- `boot2` has no CD or 2048-byte code. It loads `mach_kernel` (or `.rcz`),
  `sarld` and the drivers from the boot disk's UFS
  (`src/boot-2/i386/libsaio/load.c`), and prepends `Instance0.table`'s
  `Kernel Flags` to the boot string (`boot2/boot.c:200-212`).
- `boot2` is about 64 bytes under `boot1`'s load limit, so no CD code is
  added to it.
- The compressed kernel is 1.1 MB (1,490,344 bytes raw, 1,116,554 as rcz).

**Kernel**
- `rootdev=cdrom` scans `sd0`–`sd15` for a device whose inquiry type is
  `DEVTYPE_CDROM` (`src/kernel-7/machdep/i386/swapgeneric.m:144-168`), then
  mounts it with `ffs_mountroot`. Root is always UFS on i386.
- EIDE (`AtapiCnt.h`) and AHCI (`AHCIATAPI.h`) present ATAPI drives as SCSI
  controllers. AHCI handles 2048-byte READ(10); EIDE normalizes the block size
  READ CAPACITY reports.
- A CD-style label (`secsize` 2048) needs a copy at 512-byte block 0,
  because the kernel reads in 2048-byte blocks; DR2's copies were at
  0/15/30/45 (`docs/build/instmedia-ufs.md`).
- No CD root has been booted in this project.

**UEFI loader**
- `bootefi` refuses media whose `BlockSize` isn't 512 (`efi_disk.c:35`, the
  label probe, and `:156`, `ebiosread`).
- It picks the disk the loader was read from (`LOADED_IMAGE->DeviceHandle`,
  then its whole-disk parent) and probes for the label at LBA 15 of that
  disk, or 15 sectors into its first `0xA7` partition.
- It appends `Instance0.table`'s `Kernel Flags` after its compiled-in
  `rootdev=hd0a -v`, so the table's `rootdev=` wins.

**Builder**
- `vm/instmedia` already writes the live root, UFS with fsize 2048 (phase 3
  checked a CD-style sample with `fsck -n`), labels, the ESP
  (`hdimage.esp_image`), and the hard-disk layout (`hdimage.write`).
  `vm/rcz.py` compresses.
- The live root is about 215 MB of UFS holding 66 apks.

**Reference:** DR2's install CD, `vm/install/rhapsody_dr2_x86.iso`: label
`secsize` 2048 at byte 7680, UFS at byte 655360, bsize 8192, fsize 2048.

## Disc layout

2048-byte sectors.

| Where | Contents |
|---|---|
| Sectors 0–15 (bytes 0–32767) | ISO 9660 system area. The NeXT label is at byte 7680 (512-byte block 15), with a copy at byte 0: `secsize` 2048, no fdisk table |
| Sector 16 onward | Primary volume descriptor, El Torito boot record, terminator; then the path tables, the root directory and the boot catalog |
| Next | `BIOSBOOT.IMG`: the BIOS boot image (16 MB) |
| Next | `EFIBOOT.IMG`: the ESP image (64 MB) |
| `dl_front` × 2048 onward | The live root UFS, fsize 2048, invisible to ISO readers |

**The root directory** lists `README.TXT`, `BOOT.CAT`, `BIOSBOOT.IMG` and
`EFIBOOT.IMG`, with ISO 9660 level 1 names and no Rock Ridge or Joliet.

**The boot catalog** has a validation entry, a default entry for BIOS
(platform 0, media type 4, hard-disk emulation, `BIOSBOOT.IMG`), and a
section header plus entry for platform `0xEF` (no emulation,
`EFIBOOT.IMG`).

**`BIOSBOOT.IMG`:**
- `boot0` and an fdisk table whose single `0xA7` entry is active and ends
  on a whole cylinder of the image's LBA-assisted geometry.
- Inside the `0xA7` partition: `boot1`, the label, two copies of `boot2`,
  then a UFS.
- The UFS holds `mach_kernel`, `/usr/standalone/i386/sarld`, the boot
  drivers under `/private/Drivers/i386`, and
  `/private/Drivers/i386/System.config/Instance0.table` with
  `Kernel Flags` = `rootdev=cdrom` and the media's generic Boot Drivers.

**`README.TXT`:** a few lines naming the disc and the release line from
`software_version`, and saying it boots on i386 BIOS and IA32 UEFI machines.

## Boot paths

**BIOS:**
1. SeaBIOS maps `BIOSBOOT.IMG` as drive `0x80` and loads its sector 0. The
   real hard disks shift up one BIOS number while the CD boot is active;
   the kernel still names them `hd0`, `hd1`, and so on.
2. `boot0`, `boot1`, `boot2` run their normal hard-disk path, unchanged.
3. `boot2` loads the kernel and boot drivers from the image's UFS, with
   `rootdev=cdrom`.
4. The kernel finds the CD drive, mounts the live root read-only, and `rc`
   runs `/etc/rc.cdrom`, which starts `sysinstall`.

**UEFI:**
1. edk2 boots `/EFI/BOOT/BOOTIA32.EFI` from `EFIBOOT.IMG`.
2. `bootefi` takes the CD as its boot disk (the whole-disk parent of the
   handle it was read from), finds the label at byte 7680, and loads the
   kernel and drivers from the live root UFS.
3. The kernel roots as above.

**`bootefi` changes:**
- **Read 2048-byte media.** `ebiosread` reads the 2048-byte blocks
  covering the request into a bounce buffer and copies out the 512-byte
  sectors asked for, instead of refusing any `BlockSize` other than 512.
- **Find the label on a CD.** On a disk with 2048-byte blocks, the label
  probe reads byte 7680 rather than LBA 15 or an fdisk partition.

**`sysinstall`:** unchanged. The live root is on `sd0` (major 6), so the disk
screen's live-root exclusion skips the CD. The ESP image (`I/esp.img.gz`) and
the packages come from the CD's UFS as before.

## Builder

```
cd vm
python -m instmedia.build --repo DIR --efi BOOTIA32.EFI --form cd --out IMAGE.iso
```

`--form disk` stays the default, so existing commands and `--preinstalled`
are unchanged. `--preinstalled` is refused with `--form cd`.

| Module | Change |
|---|---|
| `iso.py` (new) | Writes the ISO 9660 and El Torito structures around supplied images: volume descriptors, path tables (both byte orders), directory records, the boot catalog. Reads them back for checking. Standard library only; deterministic, with timestamps from the apks |
| `hdimage.py` | `boot_image(fs_sectors, boot0, boot1, boot2, nodes, now)`: the MBR and `0xA7` interior `write()` makes, with no ESP |
| `label.py` | The CD label: `secsize` 2048, no fdisk, copies at 512-byte blocks 0 and 15 |
| `live.py` | With `--form cd`, the system `Instance0.table` says `rootdev=cdrom`, not `rootdev=hd1a`. The rest of the live root is unchanged |
| `build.py` | `--form cd`: compose the live root, write its UFS with fsize 2048, build the boot image's tree and image, lay out the disc. Read back the live UFS and the boot image's UFS (`readback.diff`, `ufs_check`) and the ISO structures (`iso.py`), failing on any mismatch. Refuse a disc over 650 MB with a message naming the `live.list` fallback |

**Harness:** `vm/qemu_boot.py --cdrom ISO` attaches the ISO as a read-only
CD-ROM (IDE by default; `--cdrom-ahci` puts it on an AHCI controller) and
boots from it. It combines with `--keep-hd0` for install targets.

**Size:** about 215 MB of UFS, 64 MB of ESP and 16 MB of boot image, roughly
300 MB in all.

## Testing

**Host tests:**
- `iso.py`: PVD fields, the boot record's catalog pointer, the catalog
  validation entry's checksum and 0x55AA key, both catalog entries, both
  path tables, directory records and level 1 names. Checked against an
  independent parse of the raw bytes in the test, not only `iso.py`'s own
  reader.
- `hdimage.boot_image`: its MBR and `0xA7` interior match `write()`'s for the
  same size, and its UFS reads back holding only the boot files.
- `label.py`: the CD label's `secsize` and copy positions.
- `build.py --form cd`: `rootdev=cdrom`, the size refusal, the readback, and
  `--preinstalled` refused.
- `bootefi`: host tests for 2048-byte reads (offsets inside a block, a read
  spanning blocks, unaligned starts and lengths) and the CD label offset, in
  `src/bootefi-1/tests`.

**Guest gates** (temporary images, CLAUDE.md §6):
1. **Spike, first:** boot the ISO under SeaBIOS to the Welcome screen, once
   with an IDE CD-ROM and once with an AHCI CD-ROM. This proves hard-disk
   emulation, the unchanged booter path, and the kernel's `rootdev=cdrom`
   mount over ATAPI.
2. **SeaBIOS install:** an Auto install from the CD onto a blank 2 GB `hd0`.
   The installed disk then boots alone under SeaBIOS and under IA32 UEFI to
   `login:`, and SSH works with the chosen password.
3. **UEFI install:** the same, with the CD booted under IA32 UEFI.
4. **Regression:** the disk-form media still builds and reaches the Welcome
   screen.

## Cleanup: floppy and DOS boot code

Once the ISO gates pass, the floppy and DOS boot paths go: the ISO replaces
every job they did. This is the plan's last code task, followed by a rerun of
the disk-form and ISO gates.

**Removed:**

| Where | What |
|---|---|
| `src/boot-2/i386/boot1/` | `boot1f` (the floppy build target and the committed binary) and `boot1.s`'s `BOOTDEV=FLOPPY` branches |
| `src/boot-2/i386/boot1/` | `nullboot1.s`, `nullboot1.asm` and the `nullboot1` binary (the "isn't a startup disk" floppy sector) |
| `src/boot-2/i386/boot1/` | The DOS-hosted pieces: `gonext.c` and `gonext.com` (a DOS program that boots Rhapsody, installed to `/usr/Dos`), `replace.c`, `makefile.dos`, `mkboot.bat`, and the Makefile's `/usr/Dos` install |
| `src/boot-2/i386/boot0/`, `boot1/` | `boot0.asm` and `boot1.asm`, the Turbo Assembler (DOS) copies of the NASM sources the build actually uses |
| `src/boot-2/i386/boot0/boot0.s` | The partition menu: the 3-second wait for a key, the `r` / `d` / `1`-`4` choices, the DOS partition search, and the CMOS "reboot into NeXT/DOS" flags. `boot0` then boots the active partition directly, and hands to INT 18h when there is none |
| `src/boot-2/i386/boot2/boot.c` | Booting from a floppy: the `DEV_FLOPPY` boot-device branches, the "Insert file system media" prompt, and the floppy failure message |
| `src/boot-2/i386/libsaio/drivers.c` | Loading drivers from a driver floppy in Install Mode |
| `src/cdis-3/` | `mkbootfloppy.sh`, `mkdriverfloppy.sh`, and the legacy `mkinstallcd.sh` with `README.mkinstallcd.md`, which the ISO builder replaces |

References to these in docs, Makefiles and install lists go with them.

**Kept:**
- the floppy device driver (`drvPCFloppy`) and the `fd` device nodes, so
  machines with floppy drives still read them
- `turnOffFloppy()` in `libsaio/misc.c`, which stops a drive motor left
  running by the BIOS
- fdisk's DOS partition support, which reads and writes partition tables

**Checks:**
- `boot0` boots the active partition with no delay; dual-booting from `boot0`
  is gone (UEFI or another boot manager can still choose a system).
- `boot-2` builds, and `boot2` stays under `boot1`'s 45056-byte limit (it
  shrinks).
- The disk-form media and the ISO still reach the Welcome screen under both
  firmwares, and an installed disk still boots.

## Risks

Most serious first. The plan's first task is the gate 1 spike.
1. **The ATAPI CD root has never been booted:** `rootdev=cdrom` over EIDE or
   AHCI, and the kernel reading a 2048-byte label and UFS through them.
   `docs/drivers/drvEIDE-issues.md` records past ATAPI command failures.
2. **edk2's El Torito presentation:** that the ESP image appears as a child
   handle of the CD's 2048-byte BLOCK_IO, so `bootefi` finds its parent.
3. **SeaBIOS's geometry for the emulated disk** must match what `boot1`'s CHS
   reads assume. The image ends on a whole cylinder of its LBA-assisted
   geometry.
4. **The `sarld` node limit** applies to the boot image's driver list, the
   same generic list as the disk media.
5. **Issue #37:** ISASerialPort's boot-driver link failure. Master has since
   merged a completed drvISASerialPort reconstruction (1273da85a); the gates
   show whether the failure remains.

## Outcome

What implementation settled differently from the design above:
- **AHCI is out of the gates.** The spike found `_KernBusMemoryCreateMapping`
  dropping the page offset (fixed in `d231848fb`). The AHCI CD then hangs in
  an IRQ 11 interrupt storm, a driver bug filed as RhapsodiOS/RhapsodiOS#39.
  Gate 1 ran with an IDE CD only; `--cdrom-ahci` is tested by argument tests.
- **EIDE needs the `Dual_EIDE.table`.** The default table probes only the
  primary channel. The live root and the boot image carry the bundle's
  `Dual_EIDE.table` as `EIDE.config/Instance0.table`.
- **The label splits the start.** `d_front` is a signed short and can't hold
  the UFS start (sector 40992), so the label has `d_front` 16 and `p_base`
  40976, as every reader adds them.
- **Four label copies,** at bytes 0, 7680, 15360 and 23040, as DR2 had,
  not two.
- **The EFI catalog entry's count is capped** at 0xFFFF 512-byte units
  (32 MB) for a 64 MB image. edk2 boots it anyway.
- **`--cdrom` uses `bootindex`.** One approach for both firmwares: an
  `ide-cd` on the secondary channel with `bootindex=0`, no `-boot order`.
- **A short notice replaced the removed prompt.** Removing driver-floppy
  loading took boot2's "Missing Drivers" prompt, so boot2 prints the missing
  Boot Drivers and carries on. `bootefi` has no notice.
- **`disk.c` gives floppies no booter,** in place of `boot1f`.
- **`README.mkfloppies.md` is removed** with the floppy scripts it described.

## Out of scope

- USB or hybrid ISOs (`isohybrid`)
- the `live.list` package subset
- Rock Ridge and Joliet
- a CD build target on a Rhapsody guest
- removing the floppy device driver or fdisk's DOS partition support
- ppc
