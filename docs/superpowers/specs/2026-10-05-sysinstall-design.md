# sysinstall: the RhapsodiOS installer

**Date:** 2026-10-05
**Status:** Design approved in conversation, pending spec review
**Scope:** phase 5a of the install-media design
(`docs/superpowers/specs/2026-09-22-install-media-design.md`). It replaces
that design's *Installer* section (`mbrinst` and `rhapinstall`) and builds
on phase 4's media (`docs/build/instmedia-live.md`).

## Goal

Milestone B, as the install-media design defines it:
- The hard-disk install media, attached to QEMU as `hd1`, installs onto a
  blank `hd0`.
- That disk then boots on its own under SeaBIOS and under IA32 UEFI to a
  console `login:`.
- It accepts `ssh root@` with the password chosen during install.

The installer is `sysinstall`, a full-screen curses program in the spirit
of FreeBSD 2.x's sysinstall. It is written fresh, not ported: it borrows
that program's structure, not its code.

## Decisions

| Question | Decision |
|---|---|
| Installer | `sysinstall`, one C program with curses menus, built as a tool inside `cdis-3` |
| CDIS | `cdis-3` stays the home. `rc.cdrom` shrinks to a hook that starts `sysinstall`. The perl installer, `rc.cdrom.x86`, `rc.cdrom.PPC` and the non-English strings go |
| Language | English only. Localization comes later |
| Partitioning | **Auto** erases the disk and writes the fixed layout. **Advanced** is a small partition editor with rules that keep the disk bootable |
| Filesystem | UFS only. The i386 kernel mounts root only as FFS |
| Packages | Sets: hand-written `*.set` files, each listing apk names. Phase 5a ships `base` only |
| Drivers | A standalone `driverDetect`, beside `driverLoader`, matches PCI devices to drivers' `Auto Detect IDs` |
| Media boot drivers | Generic only, to stay inside the booter's driver-linking limits |

**Later phases:**
- 5b: the developer-tools and windowing-system sets
- 5c: upgrade mode
- 6: the El Torito CD (unchanged)

## Constraints from the tree

**Disk tools**
- **CDIS's partitioning can't be used.** `fdisk` needs BIOS geometry from
  `/dev/kmem` (`fdisk.c:219-245`), which `bootefi` leaves zeroed. Its
  partition-type table has no `0xEF`, so it can't make an ESP.
- **`disk -i` writes the label, boot blocks and filesystem.** Once it finds
  an `0xA7` entry in the MBR, it writes `boot1`, the label copies and two
  copies of `boot2`, then runs `newfs` on each partition with `p_newfs`
  (`disk.c:1030-1045`, `1376-1394`).
- **`disk` without BIOS geometry** falls back to `useAllSectors`
  (install-media design, *Disk tools*). Whether it still honours an
  existing `0xA7` entry under UEFI is unproven; see *Risks*.

**Drivers**
- **The booter scans PCI** (`boot-2/i386/libsaio/pci.c`) but loads only the
  drivers its `Boot Drivers` key names (`drivers.c`). Each listed driver
  costs `sarld` symbol nodes.
- **The kernel matches by ID.** `PCIKernBus` probes a driver against its
  `Location`, or else every device against its `Auto Detect IDs`
  (`PCIKernBus.m:239-300`). A driver whose card is absent fails its probe
  harmlessly.
- **`driverLoader` probes Active Drivers through `Instance<N>.table`**
  (`driverLoader.m`). With only a `Default.table` and a blank `Location`,
  phase 4 saw NE2K never probed. Apple's installer filled each detected
  driver's `Location` in.
- **Userland can enumerate PCI.** The PCIBus resource driver answers
  `PCI_ConfigReg(dev,func,bus,reg)` and `PCI_Maximums` through
  `IODeviceMaster`'s `getCharValues` (`PCIResourceDriver.m:105-200`). No tool
  uses it yet.
- **108 driver tables carry `Auto Detect IDs`:** space-separated
  `0xDDDDVVVV` values, plus the `id&mask` and `primary:secondary` forms the
  booter's `testIDs` accepts (`drivers.c:320`). `Family` is Network, Disk,
  Display, Audio or Bus.

**Packages and passwords**
- **`apk add --root T --initdb`** works and creates the apk database
  (phase 2).
- **libc's `crypt()`** produces hashes the guest's `getpwnam` accepts
  (phase 4: `crypt("rhapsodi","rh")` = `rhME8brSxdukA`).
- **`pwd_mkdb` always writes `/etc`,** so it runs under
  `chroot T /usr/sbin/pwd_mkdb -p /etc/master.passwd`.

**Startup**
- **`rc` runs `/etc/rc.cdrom` and halts** when both it and
  `/System/Installation` exist (`files-5/private/etc/rc`).
- **The live root is read-only.** The kernel has no MFS, so nothing is
  writable until the target is mounted.

## Architecture

```
 media boot (generic Boot Drivers) ── rc → /etc/rc.cdrom → sysinstall
        │
        ├─ driverDetect -l Network SCSI      load detected cards
        ├─ disk screen ─ partition screen (Auto | Advanced)
        ├─ drivers screen   (driverDetect matches, pick and choose)
        ├─ sets screen ─ root password ─ summary
        │
        ▼  write phase
 MBR + ESP ─ disk -i -b ─ mount ─ apk add ─ configure ─ driverDetect -w
        │
        ▼
 installed disk: boot0 │ ESP │ 0xA7 UFS → login: + sshd
```

### `cdis-3` after this phase

| Path | Change |
|---|---|
| `sysinstall.tproj/` | New. Builds `/System/Installation/CDIS/sysinstall` |
| `sets/base.set` | New. Installed to `/System/Installation/Sets/` |
| `rc.cdrom` | Now only a hook: runs `sysinstall`, and on a non-zero exit offers a shell |
| `rc.cdrom.x86`, `rc.cdrom.PPC` | Removed, with their install lines |
| `French.lproj`, `German.lproj`, `Japanese.lproj` | Removed |
| `templates/` | Unchanged. `sysinstall` now reads them |
| Other CDIS tools (`pickdisk`, `sysconfig`, `findroot`, …) | Left in place, unused. Listed as dead code, not deleted |

### `sysinstall` sources

| File | Job | Uses curses |
|---|---|---|
| `main.c` | The screen sequence and the error menu | yes |
| `ui.c` | Menu, checklist, input box, message box and progress box on libcurses | yes |
| `disks.c` | Candidate disks: `/dev/rhd0-3h` and `/dev/rsd0-7h` that open, sized with `DKIOCNUMBLKS`, minus the disk holding the live root (from `mount`'s `/` line) | no |
| `layout.c` | The Auto layout, the Advanced rules, LBA-assisted CHS, MBR encode and decode | no |
| `sets.c` | Parse `*.set` files | no |
| `config.c` | Render templates; edit `master.passwd` | no |
| `steps.c` | Run the write phase: log each command and check every exit status | no |

The files marked "no" have no curses and no Rhapsody-only headers in their
logic. Their tests compile and run on the Windows host with the local
clang.

## Screens

1. **Welcome.** The release line from `software_version`. Before this
   screen appears, `driverDetect -l Network SCSI` has run, and the screen
   lists what it loaded.
2. **Disk.** The candidate disks with sizes. Disks under 1 GB are refused.
3. **Partitioning.** **Auto** or **Advanced**, then a confirm screen naming
   the disk and its size.
4. **Drivers.** A checklist per family. Detected drivers are ticked;
   undetectable ones (ISA and generic) are listed unticked.
5. **Sets.** A checklist. `base` is required and always ticked.
6. **Root password.** Entered twice, with echo off. It can't be empty, and
   the screen says only the first 8 characters count.
7. **Summary.** Disk, layout, drivers, sets. "Install?"
8. **Progress.** One line per step, plus the tail of the current command's
   output.
9. **Done.** Reboot, shell or halt.

**Errors:** any failed step shows the command and its output tail, then
offers **start over**, **shell** or **halt**. Nothing continues past a failed
step.

**Keys:** every menu item has a digit or letter as well as arrow and Return
navigation, so QEMU key injection can drive every screen.

## Partitioning

### Auto

The install-media design's hard-disk layout:

| Where | Contents |
|---|---|
| LBA 0 | `boot0` and the fdisk table |
| LBA 2048 | ESP, type `0xEF`, 131072 sectors |
| LBA 133120 | `0xA7`, active, to the last whole cylinder |

### Advanced

A small editor over the disk's existing MBR:
- list the four entries
- delete an entry
- create one in free space, with a type of ESP, Rhapsody UFS or any hex
  code
- mark one active

Before it writes, it refuses a table that breaks any of these rules:
- exactly one `0xA7` entry, and it is the active one
- exactly one `0xEF` entry of exactly 131072 sectors, because the media
  carries one fixed-size ESP image and there is no FAT writer in C
- no overlapping entries
- the new `0xA7` entry ends on a cylinder of the LBA-assisted geometry

Other entries are kept as they are, so dual-boot layouts are possible.

### CHS

Start and end CHS use the LBA-assisted rule the install-media design gives:
`spt` 63; heads 16, 32, 64, 128 or 255 by disk size; entries past
cylinder 1023 written as 1023/254/63. It matches `build_uefi_image.py`'s
`lba_assist_geometry`, and the host tests compare the two.

## Write phase

`N` is the chosen disk, `T` is `/private/var/tmp/mnta`, and `I` is
`/System/Installation`.

| # | Step | How |
|---|---|---|
| 1 | MBR | `boot0` from `/usr/standalone/i386/boot0`, then the table and the `0x55AA` signature, written to sector 0 of `/dev/rhdNh` |
| 2 | ESP | `gzip -dc I/esp.img.gz` through a pipe, written at the ESP's LBA. Refused unless it is exactly 131072 sectors |
| 3 | Label, boot blocks, filesystem | `disk -i -b /dev/rhdNh` |
| 4 | Mount | `mount /dev/hdNa T`. The log moves from memory to `T/private/var/log/sysinstall.log` |
| 5 | Packages | One `apk add --root T --initdb I/Packages/files-*.apk` followed by every other apk named in the chosen sets, each package once. `files` depends on `basic-cmds`, `csu` and `libsystem`, and apk resolves a dependency only among the apks it is given |
| 6 | Configure | Render `fstab`, `Instance0-i386.table` and `hostconfig` for `hdN`. Link `T/private/Devices` to `Drivers/i386`. Set root's `master.passwd` field to `crypt()` of the password with a random salt, then `chroot T /usr/sbin/pwd_mkdb -p /etc/master.passwd` |
| 7 | Drivers | `driverDetect -w T <chosen drivers>` |
| 8 | Check | Fail if `T/private/etc/rc.cdrom` exists, so the installer can't run at every boot |
| 9 | Finish | `umount T`, `sync` |

**Device names:** a disk installed as `hdN` gets `rootdev=hdNa`. The
harness keeps the media on `hd1`, so the target is `hd0`.

## `driverDetect`

A standalone tool in `src/driverkit-3/driverDetect/`, installed as
`/usr/sbin/driverDetect` beside `driverLoader`, and part of the base set.

| Command | Does |
|---|---|
| `driverDetect` | Lists every match: family, driver, location, IDs |
| `driverDetect -l <family…>` | Loads and probes the matched drivers of those families in the running kernel |
| `driverDetect -w <root> <driver…>` | Writes `<root>`'s system `Instance0.table` and each chosen PCI driver's own `Instance0.table`, with `Location` filled in |

**Matching:**
1. Enumerate PCI through the PCIBus resource driver: `PCI_Maximums`, then
   `PCI_ConfigReg` on every bus, device and function.
2. Read every `/usr/Devices/*.config/Default.table`.
3. Match `Auto Detect IDs` with the booter's rules: plain IDs, `id&mask`,
   and `primary:secondary`.

**The system table `-w` writes:**
- `Boot Drivers`: `EISABus PCIBus PS2Keyboard`, plus the disk controller
  driver the user ticked on the Drivers screen. That screen pre-ticks the
  controller the target sits on: for `sdN`, the SCSI driver `-l` loaded;
  for `hdN`, `AHCI` when `driverDetect` matched an AHCI controller, else
  `EIDE`.
- `Active Drivers`: the chosen network, display and audio drivers, the
  input drivers, and `BPF`
- the other keys from CDIS's `Instance0-i386.table` template, with
  `rootdev=hdNa`

**Loading on the read-only live root:** `-l` can't write `Instance` tables
for `driverLoader`. Instead it loads the relocatable and probes it with a
table built in memory, through the libkernload and libDriver calls
`driverLoader` uses. The plan's first task proves this; see *Risks*.

## Media changes (`vm/instmedia`)

- **Boot drivers.** The media's `Instance0.table` names `EISABus PCIBus
  PS2Keyboard EIDE AHCI ISASerialPort` as Boot Drivers and `VGA` as an
  Active Driver.
- **Sets.** The builder reads `I/Sets/*.set` from the `cdis` apk. It refuses
  the media if a set names a package the repository lacks, or if a package
  is in no set. Only packages named in a set go into `I/Packages`.
- **Pre-installed image.** `--preinstalled` keeps working, so the phase 4
  gates remain as regression checks.
- **Closure.** `Libcurses-1` (U) joins it, because `sysinstall` links it.
  `driverkit` already ships with the kernel build.

### Set files

```
title       Base system
description Console system with networking and SSH
required    yes
files
basic-cmds
...
```

Keyword lines come first, then one package name per line. Blank lines and
lines starting with `#` are ignored. `base.set` lists every package
phase 4 put on the media, plus `driverkit` and `libcurses` if they aren't
already among them.

## Testing

**Host unit tests** (local clang on Windows):
- the Auto layout, LBA-assisted CHS against `lba_assist_geometry`, MBR
  encode and decode
- every Advanced rule, accepted and refused
- set-file parsing
- template rendering and the `master.passwd` edit
- `driverDetect`'s ID matching, against real `Default.table` files from
  `src/drivers-i386`

**`vm/instmedia` tests:** the set checks, and that only packages named in a
set are carried.

**Guest gates.** Every gate boots temporary copies of its disk images
(CLAUDE.md §6).
1. Under SeaBIOS, an Auto install onto a blank 2 GB `hd0`, with the password
   `rhapsodi2`. Then boot `hd0` alone under SeaBIOS and under IA32 UEFI to
   `login:`, and log in over SSH on port 2549 with the new password.
2. The same install, from the media booted under IA32 UEFI.
3. An install onto a 4 GB `hd0`, for the CHS-translation risk.
4. With `-device ne2k_pci`, `driverDetect` on the installer lists NE2K at its
   slot. On the installed disk, NE2K loads as an Active Driver from its
   `Instance0.table` with `Location` filled in, and DHCP gives `en0` an
   address.
5. A scripted Advanced run that creates the ESP and `0xA7` entries by hand,
   then boots the result.

## Risks

Most serious first. The plan's first task is a spike on a guest that
settles the first three before anything else is built.
1. **`driverDetect -l` on a read-only root.** If the probe call takes only
   a table path, not a table in memory, loading network and SCSI drivers
   before the disk screen needs another route.
2. **`disk -i -b` under UEFI,** with no BIOS geometry: it must still find
   and use our `0xA7` entry.
3. **The kernel taking up the new MBR and label without a reboot,** so that
   `hdNa` exists for step 4. Writing sector 0 and the ESP through
   `/dev/rhdNh` on a blank disk is part of the same check.
4. **4.4BSD curses** has no colour and few widgets. The UI layer stays
   small, and nothing depends on colour.
5. **The `sarld` limit.** The media's Boot Drivers drop `NE2K`, so the
   media's list is shorter than phase 4's. The installed disk's list grows
   only by its disk controller.

## Out of scope

- upgrades (5c), and the developer and windowing sets (5b)
- languages other than English
- root filesystems other than UFS
- reusing an existing ESP, or ESPs of any size but 64 MB
- ppc
