# Bootable installer ISO (install-media phase 6) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `python -m instmedia.build --form cd` makes an El Torito ISO of the
installer that boots under `qemu -cdrom` with SeaBIOS and IA32 UEFI, installs,
and leaves a disk that boots alone to `login:` with SSH. Afterwards the floppy
and DOS boot code, and `boot0`'s partition menu, are removed.

**Architecture:**
- BIOS boots a 16 MB hard-disk-emulation image (`boot0` / `0xA7` / `boot1` /
  `boot2` plus a tiny UFS with the kernel and boot drivers). UEFI boots the
  existing ESP image through an El Torito EFI entry.
- The live root is a UFS (fsize 2048) on the CD behind a `secsize` 2048 label,
  found by the kernel with `rootdev=cdrom`.
- `bootefi` learns 2048-byte media and the CD label offset.

**Tech Stack:** Python 3.13 standard library (`vm/instmedia`, `vm/qemu_boot.py`),
C (`src/bootefi-1`, clang on the host; `src/boot-2` NASM), QEMU.

**Spec:** `docs/superpowers/specs/2026-10-07-bootable-iso-design.md` (phase 6 of
`docs/superpowers/specs/2026-09-22-install-media-design.md`; phase 5a record:
`docs/build/sysinstall.md`).

## Global Constraints

- Built on the Windows host, pure Python, no `mkisofs`: `cd vm && python -m instmedia.build --repo DIR --efi BOOTIA32.EFI --form cd --out IMAGE.iso`. `--form disk` stays the default; `--preinstalled` with `--form cd` is refused.
- Disc: 2048-byte sectors. ISO system area = sectors 0–15. NeXT label `secsize` 2048, no fdisk, at byte 7680 (512-byte block 15) with a copy at byte 0.
- Root directory: `README.TXT`, `BOOT.CAT`, `BIOSBOOT.IMG`, `EFIBOOT.IMG`; ISO 9660 level 1 names (`NAME.EXT;1`), no Rock Ridge or Joliet.
- Boot catalog: validation entry (checksum, key 0x55 0xAA), default entry platform 0 media type 4 (hard-disk emulation) → `BIOSBOOT.IMG`; section header platform `0xEF` + entry no-emulation → `EFIBOOT.IMG`.
- `BIOSBOOT.IMG` is 16 MB (32768 512-byte sectors): `boot0`, one active `0xA7` entry ending on a whole LBA-assisted cylinder, `boot1`, label, two `boot2` copies, then a UFS with `mach_kernel`, `/usr/standalone/i386/sarld`, the boot drivers under `/private/Drivers/i386`, and `/private/Drivers/i386/System.config/Instance0.table` with `Kernel Flags` = `rootdev=cdrom` and Boot Drivers `EISABus PCIBus PS2Keyboard EIDE AHCI ISASerialPort`.
- `EFIBOOT.IMG` = `hdimage.esp_image(efi)` (131072 sectors, 64 MB).
- Live root identical to the disk form except the system `Instance0.table` says `rootdev=cdrom`.
- The builder refuses a disc over 650 MiB (681,574,400 bytes) with a message naming the `live.list` fallback.
- `qemu_boot.py --cdrom ISO` (IDE CD-ROM, read-only, boots from it); `--cdrom-ahci` puts it on an AHCI controller; combines with `--keep-hd0`.
- Cleanup removes: `boot1f` + `boot1.s` FLOPPY branches; `nullboot1.*`; `gonext.c`, `gonext.com`, `replace.c`, `makefile.dos`, `mkboot.bat`, the `/usr/Dos` install; `boot0.asm`, `boot1.asm`; `boot0.s`'s partition menu (3 s key wait, `r`/`d`/`1`–`4`, DOS search, CMOS reboot flags: it then boots the active partition, INT 18h if none); `boot2/boot.c` floppy boot paths; `libsaio/drivers.c` driver-floppy loading; `src/cdis-3/mkbootfloppy.sh`, `mkdriverfloppy.sh`, `mkinstallcd.sh`, `README.mkinstallcd.md`. Keeps `drvPCFloppy`, `fd` nodes, `turnOffFloppy()`, fdisk's DOS partition support. `boot2` stays under 45056 bytes.
- CLAUDE.md: commit subjects start with a subsystem prefix, short, no metadata; check legacy files for Mac-Roman bytes before editing (edit via latin-1 if present); boot tests only on temporary images; never write or delete `vm/work/rhap-i386-bootstrapped.img`; never boot `vm/golden.img`, `vm/rhapsody.vmdk`, `vm/work/test.img`; quit guests via QMP `quit`.

## Review Focus

1. **A request in `bootefi` that starts and ends mid-block on 2048-byte media** (e.g. 3 sectors from 512-byte sector 5): exactly those bytes come back, nothing outside the buffer is written. Task 7: `test_read_spans_blocks_unaligned`.
2. **A 512-byte-block disk after the change** (every disk today): reads and the label probe behave exactly as before. Task 7: `test_512_byte_media_unchanged`.
3. **Directory and path-table records whose names have odd/even lengths** (padding byte rules): ISO readers parse every record. Task 4: `test_records_pad_to_even_length` and the independent parser in `test_independent_parse`.
4. **A live root large enough to push the disc past 650 MiB:** refused before writing, with the `live.list` message. Task 5: `test_cd_over_650_mib_is_refused`.
5. **`boot0` with no active partition, or an active entry other than the first:** it boots the active one and hands to INT 18h when none. Task 9: guest check on the media (active entry is the only entry) plus the disk form; host check `test_boot0_has_no_menu_strings`.

---

## File structure

| File | Job |
|---|---|
| `vm/instmedia/label.py` | `cd_label(g, front, p_size, name)` and `CD_COPIES` |
| `vm/instmedia/live.py` | `compose(..., form="disk")`: `form="cd"` renders `rootdev=cdrom` |
| `vm/instmedia/hdimage.py` | `boot_image(path, fs_sectors, boot0, boot1, boot2, nodes, now)` |
| `vm/instmedia/iso.py` (new) | ISO 9660 + El Torito writer and reader |
| `vm/instmedia/build.py` | `--form cd`, `build_cd(...)`, readback, size refusal |
| `vm/instmedia/test_{label,live,hdimage,iso,build}.py` | Tests |
| `vm/qemu_boot.py`, `vm/test_qemu_boot.py` | `--cdrom`, `--cdrom-ahci` |
| `src/bootefi-1/efi_sector.{c,h}` (new) | Pure 2048-byte read arithmetic and the CD label offset |
| `src/bootefi-1/efi_disk.c` | Uses `efi_sector` |
| `src/bootefi-1/tests/efi_sector_test.c`, `tests/Makefile` | Host tests |
| `src/boot-2/i386/{boot0,boot1,boot2,libsaio}`, `src/cdis-3` | Cleanup (Task 9) |
| `docs/build/instmedia-cd.md` (new) | Record (Task 10) |

---

### Task 1: Spike the CD root (controller)

**Files:** none in the repo; scratch only. Ledger the result.

- [ ] **Step 1: Make a CD-style live root image** in scratch with the existing
  builder pieces: compose the phase 5a live root from the last good repo
  (`D:/RhapsodiOS/vm/work/p5-repo9`, read-only), with the system
  `Instance0.table`'s `Kernel Flags` set to `rootdev=cdrom`; write its UFS with
  fsize 2048 (`ufs_geometry` as `sample.cd_volume` does), a `secsize` 2048
  label (copies at 512-byte blocks 0 and 15, `p_base` 0, `front` 320 2048-byte
  blocks = 655360 bytes as DR2), and pad to a whole 2048-byte sector.
- [ ] **Step 2: Boot it as the root** under SeaBIOS: boot phase 5a's disk media
  (`D:/RhapsodiOS/vm/work/p5-gate/media7.img`) as hd0 with its booter, but with a
  scratch copy whose system `Instance0.table` says `rootdev=cdrom`, and attach
  the step-1 image as a CD-ROM: once on IDE (`-drive file=…,media=cdrom,if=ide,index=2,readonly=on`)
  and once on AHCI (`-device ahci,id=ahci -drive id=cd,file=…,media=cdrom,if=none,readonly=on -device ide-cd,drive=cd,bus=ahci.0`).
  Use `qemu_boot.py`'s internals or a scratch runner; `-snapshot` always.
- [ ] **Step 3: Pass:** `kernel.log` shows the CD found (`sd0`) and root mounted
  from it, and a screenshot shows `sysinstall`'s Welcome screen, for both IDE
  and AHCI. **Fail:** read the logs, find where `rootdev=cdrom`, the ATAPI
  driver, the label read or the UFS mount breaks, and rule on a fix (it becomes
  a task before Task 8). Ledger `Task 1: IDE PASS|FAIL, AHCI PASS|FAIL` with log
  paths.

### Task 2: CD label and `rootdev=cdrom` in the live root

**Files:** Modify `vm/instmedia/label.py`, `vm/instmedia/live.py`; Test `vm/instmedia/test_label.py`, `vm/instmedia/test_live.py`

**Interfaces — Produces:**
- `label.CD_COPIES = (0, 15)` (512-byte block numbers).
- `label.cd_label(g, front, p_size, name) -> bytes` — a `dlV3` label with `secsize` 2048, `front` and `p_size` in 2048-byte blocks, `p_base` 0, no boot blocks, filesystem fields from geometry `g` (as `for_filesystem` does).
- `live.compose(apks, esp, preinstalled=False, password_hash=None, form="disk")`; `form="cd"` sets the system table's `Kernel Flags` to `rootdev=cdrom`; `live.CD_KERNEL_FLAGS = "rootdev=cdrom"`.

- [ ] **Step 1: Write the failing tests:** `test_cd_label_fields` (decode
  with the existing reader in `test_label.py`: `secsize` 2048, `front`,
  `p_size`, checksum valid); `test_cd_label_copies_carry_their_block` (each copy
  placed with `place()` at `CD_COPIES` has `dl_label_blkno` equal to its 512-byte
  block); `test_cd_form_sets_rootdev_cdrom` (compose with `form="cd"`: system
  table's `Kernel Flags` is `rootdev=cdrom`; with the default it's
  `rootdev=hd1a`, as today).
- [ ] **Step 2: Run** `cd vm && python -m unittest instmedia.test_label instmedia.test_live`. Expected: FAIL (no `cd_label`, unknown `form`).
- [ ] **Step 3: Implement** both.
- [ ] **Step 4: Run** the same command. Expected: OK.
- [ ] **Step 5: Commit** `instmedia: add the CD label and render rootdev=cdrom for the CD form`.

### Task 3: The BIOS boot image

**Files:** Modify `vm/instmedia/hdimage.py`; Test `vm/instmedia/test_hdimage.py`

**Interfaces — Produces:** `hdimage.BOOT_IMAGE_SECTORS = 32768`;
`hdimage.boot_image(path, fs_sectors, boot0, boot1, boot2, nodes, now) -> (g, total)`:
the MBR (one active `0xA7` entry from LBA 63, ending on the last whole
LBA-assisted cylinder at or below `BOOT_IMAGE_SECTORS`) and the `0xA7` interior
exactly as `write()` lays it out (boot1, label copies +15/30/45, boot2 at
+64/+192, UFS from +320). `total == BOOT_IMAGE_SECTORS`; refuse `nodes` that
don't fit.

- [ ] **Step 1: Write the failing tests:** `test_boot_image_layout` (MBR has one
  entry, active, type `0xA7`, start 63; signature; `boot1` at the partition's
  first sector; label at +15 decodes with `p_base` = 63; UFS reads back with
  `readback.diff` against the nodes); `test_boot_image_is_16_mb`;
  `test_boot_image_ends_on_a_cylinder` (end LBA+1 divisible by heads×63 of
  `build_uefi_image.lba_assist_geometry(32768)`); `test_boot_image_refuses_too_much`.
- [ ] **Step 2: Run** `cd vm && RHAPSODY_MEDIA_DIR=D:/RhapsodiOS/vm python -m unittest instmedia.test_hdimage`. Expected: FAIL.
- [ ] **Step 3: Implement** `boot_image`, reusing `write()`'s interior code (factor
  a shared helper if needed rather than copying it).
- [ ] **Step 4: Run** the same. Expected: OK.
- [ ] **Step 5: Commit** `instmedia: build the small hard-disk image the CD's BIOS boot uses`.

### Task 4: `iso.py`, the ISO 9660 and El Torito writer

**Files:** Create `vm/instmedia/iso.py`, `vm/instmedia/test_iso.py`

**Interfaces — Produces:**
```python
SECTOR = 2048
FileEntry = namedtuple("FileEntry", "name lba size")        # name like "README.TXT"
def layout(files, first_lba): ...                            # -> {name: FileEntry}, next free lba
def write_iso(f, volume_id, files, catalog_lba, bios_name, efi_name, total_sectors, mtime): ...
    # writes PVD (sector 16), boot record (17), terminator (18), path tables, root dir, catalog
def read_iso(f): ...                                         # -> dict(volume_id, files={name: (lba,size)}, catalog=[entries])
```
`files` is an ordered list of `(name, size)`; data is written by the caller at
each entry's `lba`. Volume ID `"RHAPSODIOS"`. Path tables in both byte orders
(L at its LBA, M at its LBA). Directory records padded to even length. Timestamps
from `mtime` (deterministic). Catalog: validation entry (header ID 1, platform
0, ID string `"RHAPSODIOS"`, checksum making the 16-bit sum zero, 0x55 0xAA),
default entry (0x88 bootable, media 4, load segment 0, sector count 1, LBA of
`bios_name`), section header (0x91 final, platform 0xEF, 1 entry), entry (0x88,
media 0, sector count = image size in 512-byte units capped at 0xFFFF, LBA of
`efi_name`).

- [ ] **Step 1: Write the failing tests:** `test_pvd_fields` (`CD001`, version 1,
  volume space size = `total_sectors`, logical block size 2048, root record's
  extent = root dir LBA); `test_boot_record_points_at_catalog` (`EL TORITO
  SPECIFICATION`, catalog LBA); `test_catalog_entries` (validation checksum 0,
  key 0x55AA, default entry media 4 → `BIOSBOOT.IMG`'s LBA, section 0xEF → EFI
  entry media 0); `test_records_pad_to_even_length` (names `README.TXT;1`,
  `BOOT.CAT;1` etc.); `test_path_tables_both_orders`; `test_independent_parse`
  (a small parser written in the test from ECMA-119 field offsets, not using
  `iso.py`, lists exactly the four files with the right LBAs and sizes);
  `test_round_trip` (`read_iso(write_iso(...))`).
- [ ] **Step 2: Run** `cd vm && python -m unittest instmedia.test_iso`. Expected: FAIL (no module).
- [ ] **Step 3: Implement** `iso.py`.
- [ ] **Step 4: Run** the same. Expected: OK.
- [ ] **Step 5: Commit** `instmedia: add an ISO 9660 and El Torito writer`.

### Task 5: `build.py --form cd`

**Files:** Modify `vm/instmedia/build.py`; Test `vm/instmedia/test_build.py`

**Interfaces — Consumes:** Tasks 2–4. **Produces:** `build.build(repo, efi_path, out, preinstalled=False, fs_mb=None, form="disk")`;
`build.CD_LIMIT = 681574400`; `build.README_TEXT(release) -> bytes`.
Disc order per the spec: system area (label copies at bytes 0 and 7680), sector
16 descriptors, path tables, root dir, catalog, `README.TXT`, `BIOSBOOT.IMG`,
`EFIBOOT.IMG`, then the live UFS from `front` (the first 2048-byte sector after
`EFIBOOT.IMG`, rounded up to 32 sectors). The boot image's tree holds `mach_kernel`,
`/usr/standalone/i386/sarld`, each Boot Driver's `<name>.config` directory from
the live tree, and its own `Instance0.table` (the live CD table). Readback:
`readback.diff` + `ufs_check` on the live UFS (read at its byte offset) and on
the boot image's UFS; `iso.read_iso` must list the four files at their LBAs.

- [ ] **Step 1: Write the failing tests** (fixture `make_bootable_repo` as the disk
  tests use): `test_cd_builds_and_reads_back` (ISO lists the four files; label at
  byte 7680 has `secsize` 2048; live UFS readable via `rhap_image` at its offset;
  live `Instance0.table` says `rootdev=cdrom`; `BIOSBOOT.IMG` MBR active `0xA7`);
  `test_cd_boot_image_holds_only_boot_files`; `test_cd_over_650_mib_is_refused`
  (monkeypatch `CD_LIMIT` small; BuildError mentions `live.list`; nothing written);
  `test_cd_refuses_preinstalled`; `test_main_accepts_form_cd`.
- [ ] **Step 2: Run** the phase 5a vm suite command (see `docs/build/sysinstall.md`). Expected: the new tests FAIL, others pass.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the vm suite. Expected: all OK.
- [ ] **Step 5: Commit** `instmedia: build the installer as a bootable ISO with --form cd`.

### Task 6: `qemu_boot.py --cdrom`

**Files:** Modify `vm/qemu_boot.py`, `vm/test_qemu_boot.py`

**Interfaces — Produces:** `--cdrom ISO` and `--cdrom-ahci`. IDE: the ISO as
`if=ide,index=2,media=cdrom,readonly=on` and boot order `d` for BIOS / a
`bootindex=0` CD for UEFI; AHCI: an `ahci` controller and `ide-cd` with
`bootindex=0`. Refuse `--cdrom` with `--boot-hd1`; refuse the protected images
by the existing rules.

- [ ] **Step 1: Write the failing tests** in the file's style: `test_cdrom_ide_args`,
  `test_cdrom_ahci_args`, `test_cdrom_with_keep_hd0`, `test_cdrom_refuses_boot_hd1`.
- [ ] **Step 2: Run** `cd vm && python -m unittest test_qemu_boot`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same. Expected: OK.
- [ ] **Step 5: Commit** `vm: boot the installer ISO from a CD-ROM in qemu_boot`.

### Task 7: `bootefi` on 2048-byte media

**Files:** Create `src/bootefi-1/efi_sector.c`, `efi_sector.h`, `tests/efi_sector_test.c`; Modify `src/bootefi-1/efi_disk.c` (lines ~35 and ~145-160), `src/bootefi-1/tests/Makefile`, the bootefi Makefile's source list

**Interfaces — Produces:**
```c
/* Which media blocks cover 512-byte sectors [secno, secno+nsecs) */
void efi_sector_span(UINT32 block_size, UINT64 secno, UINT32 nsecs,
                     UINT64 *first_block, UINT32 *nblocks, UINT32 *skip_bytes);
/* 512-byte sector number of the label probe on this disk: 15 for 512-byte media
   (whole disk), 15 (byte 7680) for 2048-byte media read through efi_sector_span */
UINT64 efi_cd_label_sector(UINT32 block_size);
```
Use the typedefs `efi_pci_acpi.c` uses on the host. `ebiosread`: for
`BlockSize == 512` unchanged; for 2048, read `nblocks` blocks into a static bounce
buffer sized for the largest request (`biosbuf`'s size rounded up to 2048 plus
one block) and copy `nsecs*512` bytes from `skip_bytes`. The label probe on a
2048-byte disk reads the sector `efi_cd_label_sector` gives, with no fdisk walk.
Other block sizes keep failing as today.

- [ ] **Step 1: Write the failing tests:** `test_512_byte_media_unchanged`
  (block_size 512: first_block = secno, nblocks = nsecs, skip 0);
  `test_aligned_2048` (secno 8, nsecs 4 → block 2, 1 block, skip 0);
  `test_read_spans_blocks_unaligned` (secno 5, nsecs 3 → block 1, 1 block, skip
  512; secno 3, nsecs 2 → block 0, 2 blocks, skip 1536); `test_cd_label_sector`
  (15 for both sizes, and for 2048 the span is block 3, skip 1536).
- [ ] **Step 2: Run** `cd src/bootefi-1/tests && make test-sector` (new target, CC clang). Expected: compile failure.
- [ ] **Step 3: Implement** `efi_sector.c` and wire `efi_disk.c`.
- [ ] **Step 4: Run** `make test-sector` and the existing `make test-disk-select test-bootargs test-acpi`; then rebuild `BOOTIA32.EFI` (`cd src/bootefi-1 && PATH="/c/Program Files/LLVM/bin:$PATH" make CCTOOLS=../Developer/Commands/cctools-2/include`). Expected: all pass, EFI builds.
- [ ] **Step 5: Commit** `bootefi: read 2048-byte media and find the label on a CD`.

### Task 8: Build the ISO and run the gates (controller)

**Files:** none; fixes get their own `<subsystem>: …` commits with tests first.

- [ ] **Step 1:** Collect (fresh repo dir `vm/work/p6-repo`, adds as the
  phase 5a media used: see `docs/build/sysinstall.md`) and build
  `vm/work/p6-gate/installer.iso` with `--form cd`, plus the disk media.
- [ ] **Step 2: Gate 1:** boot the ISO under SeaBIOS with `--cdrom` and with
  `--cdrom-ahci`, to the Welcome screen. Under IA32 UEFI with `--cdrom` to the
  Welcome screen.
- [ ] **Step 3: Gate 2:** SeaBIOS CD boot, Auto install onto a fresh 2 GB
  `--keep-hd0` target (typing scripts from `docs/build/sysinstall.md`), reach
  Done, Halt; boot the target alone under SeaBIOS and UEFI to `login:`; SSH with
  the chosen password.
- [ ] **Step 4: Gate 3:** the same with the CD booted under UEFI.
- [ ] **Step 5: Gate 4:** the disk-form media still reaches the Welcome screen.
- [ ] **Step 6:** Record whether issue #37's ISASerialPort link failure appears.

### Task 9: Remove the floppy and DOS boot code

**Files:** per the Global Constraints cleanup list; Test `src/cdis-3/tests/test_templates.py` (or a new `src/boot-2/i386/tests/test_cleanup.py` if that dir has a Python test convention; else add to `vm/test_boot_cleanup.py`)

- [ ] **Step 1: Write the failing test** `test_floppy_and_dos_boot_code_is_gone`:
  none of the removed files exist; `boot1/Makefile` has no `boot1f`,
  `FOREIGNDOS` or `/usr/Dos`; `boot1.s` has no `FLOPPY`; `boot2/boot.c` has no
  `DEV_FLOPPY` and no "Insert file system media"; `drivers.c` has no driver-floppy
  prompt; `src/cdis-3` has none of the four scripts; and
  `test_boot0_has_no_menu_strings`: `boot0.s` has no `'Type r for Rhapsody'`,
  no `gotkey`, no CMOS port `70h` access. Keeps: `misc.c` still defines
  `turnOffFloppy`.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Remove** (check Mac-Roman bytes first; `git rm` for files). Rebuild
  boot-2 on a private guest (recipe: `docs/build/sysinstall.md` / phase 5a Task 9
  report), fetch the `boot` apk, and record `boot2`'s size (must be < 45056).
- [ ] **Step 4: Run the test** (OK) and the gates: rebuild the ISO and disk media
  from a fresh repo with the new `boot` apk; ISO under SeaBIOS and UEFI to the
  Welcome screen; disk media to the Welcome screen; one Auto install from the ISO
  under SeaBIOS whose disk boots alone (`boot0` with no menu).
- [ ] **Step 5: Commit** in pieces: `boot: remove the floppy and DOS boot code`,
  `boot: make boot0 boot the active partition without a menu`, `cdis: drop the
  floppy and legacy CD scripts`.

### Task 10: Record it

**Files:** Create `docs/build/instmedia-cd.md`; Modify the umbrella spec (phase 6
row, CD form, Booter changes, risks 2 and 8 notes "(Before phase 6; now …)"),
`docs/superpowers/specs/2026-10-07-bootable-iso-design.md` (Status, Outcome),
`docs/build/sysinstall.md` (the ISO pointer).

- [ ] **Step 1:** Write the doc (style of `docs/build/sysinstall.md`: modules,
  disc layout, commands, gate results table, Worth knowing) and the notes.
- [ ] **Step 2: Commit** `docs: record phase 6, the bootable installer ISO`.
