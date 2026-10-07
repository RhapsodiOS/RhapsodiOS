# The bootable installer ISO

`vm/instmedia` builds the installer as an El Torito ISO on the Windows
host, in pure Python, with no `mkisofs`. This is phase 6 of the
install-media design
(`docs/superpowers/specs/2026-09-22-install-media-design.md`), designed in
`docs/superpowers/specs/2026-10-07-bootable-iso-design.md`. The ISO boots
under `qemu -cdrom` with SeaBIOS and with IA32 UEFI to `sysinstall`'s
Welcome screen. An install from it onto a blank disk completes, and that
disk boots alone under both firmwares to a `login:` that accepts SSH. It
carries the same 66 apks as the disk-form media
(`docs/build/sysinstall.md`).

## Build it

```bash
cd src/bootefi-1 && PATH="/c/Program Files/LLVM/bin:$PATH" make CCTOOLS=../Developer/Commands/cctools-2/include
cd ../../vm
python -m instmedia.collect work/p6-repo --image work/rhap-i386-bootstrapped.img --add work/p2-apks --add work/p4-apks --add work/p5-apks ...
python -m instmedia.build --repo work/p6-repo --efi ../src/bootefi-1/BUILD/BOOTIA32.EFI --form cd --out work/p6-gate/installer.iso
```

`collect` takes phase 5's `--add` directories, plus the directories holding
the newer `cdis`, `boot` and `diskdev-cmds` apks. The build prints `66
apks, 5706 nodes, 215 MB of UFS, 295 MB disc`.

`--form disk` stays the default. `--preinstalled` is refused with `--form
cd`. A disc over 650 MiB (`build.CD_LIMIT`) is refused before the output
is opened, with a message naming the `live.list` fallback. After writing,
the build reads the ISO back: `readback.diff` and `ufs_check.check` on the
live UFS, and `check_iso` on the El Torito structures. Any failure removes
the output.

Boot it:

```bash
python qemu_boot.py bios target.img logs/cd-bios --cdrom work/p6-gate/installer.iso --at 60,120
python qemu_boot.py uefi target.img logs/cd-uefi --cdrom work/p6-gate/installer.iso --at 60,120
```

`--cdrom` attaches the ISO read-only as an IDE CD-ROM on the secondary
channel (`ide-cd,bus=ide.1,unit=0,bootindex=0`), for both firmwares, and
drops `-boot order`. It combines with `--keep-hd0` for install targets.

## Modules

| Where | Job |
|---|---|
| `iso.py` | ISO 9660 and El Torito: volume descriptors, path tables in both byte orders, directory records, the boot catalog. `layout`, `write_iso` and `read_iso`. Standard library only; no Rock Ridge or Joliet |
| `hdimage.boot_image` | The BIOS boot image: `boot0`, an fdisk table with one `0xA7` entry, and the partition interior `write()` makes, with no ESP |
| `label.cd_label` | The CD's NeXT label: `secsize` 2048, no fdisk table, copies at `CD_COPIES` (bytes 0, 7680, 15360, 23040) |
| `live.compose(form="cd")` | `rootdev=cdrom` in the system table, and `EIDE.config/Instance0.table` taken from the bundle's `Dual_EIDE.table` |
| `build --form cd` | Composes the root, writes the live UFS (fsize 2048) and the boot image, lays out the disc and reads it back |
| `qemu_boot --cdrom`, `--cdrom-ahci` | Attach the ISO as an IDE or AHCI CD and boot from it |
| `bootefi` `efi_sector.c` | 2048-byte reads through a bounce buffer, and the CD's label offset |

## The disc

2048-byte sectors.

| Sector | Contents |
|---|---|
| 0-15 | System area. Label copies at bytes 0, 7680, 15360 and 23040 (`secsize` 2048); no fdisk table |
| 16-21 | Primary volume descriptor (16), El Torito boot record (17), terminator (18), path tables (19, 20), root directory (21) |
| 22 | `BOOT.CAT` |
| 23 | `README.TXT` |
| 24 | `BIOSBOOT.IMG`, 16 MB (8192 sectors) |
| 8216 | `EFIBOOT.IMG`, 64 MB (32768 sectors) |
| 40992 | The live UFS, to the end of the disc |

The UFS starts at the next free sector (40984) rounded up to 32. It is
fsize 2048, 110080 sectors, 215 MB. The ISO is 151072 sectors, 309,395,456
bytes. The ISO 9660 directory lists the four files and the UFS is invisible
to ISO readers.

**The label** sits at byte 7680 (512-byte block 15), with `secsize` 2048.
`d_front` is a signed short and can't hold 40992, so the label has
`d_front` 16 and `p_base` 40976. Every reader adds the two: the kernel's
`IODiskPartition`, boot2's `disk.c` and `bootefi`. `label.cd_label` takes an
optional `p_base` for this.

**`BIOSBOOT.IMG`** is a hard disk in miniature, 32768 sectors on a 16 head,
63 sector geometry:
- `boot0` and one `0xA7` entry: active, LBA 63, 32193 sectors, ending at
  LBA 32255 (cylinder 31, head 15, sector 63), a whole cylinder.
- `boot1`, the label, two `boot2` copies, then a UFS of 31873 sectors
  holding `/mach_kernel`, `/usr/standalone/i386/sarld`, each Boot Driver's
  `.config` bundle, and `System.config`, whose `Instance0.table` says
  `rootdev=cdrom`. Hard links whose other name is left out become the file.

**`EFIBOOT.IMG`** is the same 64 MB ESP the disk form writes, holding
`/EFI/BOOT/BOOTIA32.EFI`.

**The boot catalog** has:
- a validation entry (key `0x55AA`, checksummed)
- a default entry: platform 0, media type 4 (hard-disk emulation), system
  type `0xA7`, sector count 1, `BIOSBOOT.IMG`
- a section header and an entry for platform `0xEF`, no emulation,
  `EFIBOOT.IMG`

The EFI entry's sector count is a 16-bit number of 512-byte units, so it is
capped at 0xFFFF (32 MB) while the image is 64 MB. edk2 boots it anyway.

## The two boot paths

**SeaBIOS.**
1. SeaBIOS maps `BIOSBOOT.IMG` as drive `0x80`, and `boot0`, `boot1` and
   `boot2` run their normal hard-disk path with no CD code.
2. `boot2` loads the kernel and boot drivers from the image's UFS with
   `rootdev=cdrom`.
3. The kernel finds the ATAPI drive as `sd0` (`hc1: ATAPI CD-ROM`,
   `sd0: Device Block Size: 2048 bytes`, `sd0: Disk Label: RhapsodiOS`),
   mounts the live UFS as root (`rootdev 600`), and `rc.cdrom` starts
   `sysinstall`. The real disks keep the names `hd0`, `hd1`, and so on.

**IA32 UEFI.**
1. edk2 boots `/EFI/BOOT/BOOTIA32.EFI` from `EFIBOOT.IMG`.
2. `bootefi` takes the CD as the disk it was read from: it treats the El
   Torito image's handle as a child of the CD. It reads the label at byte
   7680 without reading LBA 0 or walking an fdisk table, and reads the
   kernel and drivers from the live UFS through a 12 KB bounce buffer of
   2048-byte blocks.
3. The boot string ends `rootdev=cdrom`, and the kernel roots as above.

## Results

Results on 2026-10-06; the cleanup reruns on 2026-10-07. Logs are under
`vm/logs/p6-gate/` (`p6-smoke/` for the spike and smokes, `p6-t9/` for the
cleanup). The gate ISO is 309,395,456 bytes; its repo holds 101 apks and 66
go on the disc.

| Gate | Result | Evidence |
|---|---|---|
| 1 SeaBIOS, IDE CD | Welcome by 60 s; `sd0: Disk Label: RhapsodiOS`, `root on sd0`, `rootdev 600` | `g1-bios/` |
| 1 IA32 UEFI, IDE CD | Welcome by 60 s; boot string `rootdev=hd0a -v rootdev=cdrom` | `g1-uefi/` |
| 2 Auto install from the CD, SeaBIOS, 2 GB | The Disk screen lists only `hd0`. Done by 520 s, `FILESYSTEM CLEAN`. The target alone reaches `login:` by 240 s under SeaBIOS and under UEFI. SSH shows `/dev/hd0a on /`, `en0` 10.0.2.15, no `rc.cdrom` | `g2-install/`, `g2-boot-bios/`, `g2-boot-uefi/` |
| 3 Auto install from the CD, UEFI | The same: Done by 520 s, `login:` by 240 s and SSH under both firmwares | `g3-install/`, `g3-boot-bios/`, `g3-boot-uefi/` |
| 4 Disk-form media (regression) | Welcome by 150 s with the media as `hd1` | `g4-media-bios/` |

Cleanup reruns (`p6-t9/`): the ISO under SeaBIOS and UEFI, the disk media
under SeaBIOS, an Auto install from the ISO to Done, and the target alone to
`login:` and SSH all pass with the new booters. A scratch copy of the media
with a missing Boot Driver printed the notice and went straight on to the
kernel.

The AHCI CD is not in the gates; see Worth knowing.

## The cleanup

The ISO replaces the floppy and DOS boot paths, so they are gone:
- `boot1f`, `nullboot1`, `gonext`, `replace`, `makefile.dos`, `mkboot.bat`,
  the `/usr/Dos` install, `boot0.asm` and `boot1.asm`, and `boot1.s`'s
  floppy branches
- boot0's partition menu, the key wait and the CMOS flags: it boots the
  active partition, or calls INT 18h when there is none
- boot2's floppy boot-device branch, "Insert file system media" prompt and
  driver-disk prompts, and `drivers.c`'s driver-floppy loading
- `disk.c`'s `boot1f` for floppies: they now get no booter
- cdis-3's `mkbootfloppy.sh`, `mkdriverfloppy.sh`, `mkinstallcd.sh` and the
  `README.mkinstallcd.md` and `README.mkfloppies.md` that described them

Kept: `drvPCFloppy` and the `fd` nodes, `turnOffFloppy()` and fdisk's DOS
partition support.

| Booter | Before | After |
|---|---|---|
| `boot2` | 45008 bytes | 38432 bytes (limit 45056) |
| `boot0` code | 432 bytes | 156 bytes |
| `boot1` | 512 | 512, byte-identical |
| `BOOTIA32.EFI` | 41984 bytes | 36352 bytes |

`vm/test_boot_cleanup.py` checks the files and strings are gone.

## Worth knowing

- **The CD needs EIDE's `Dual_EIDE.table`.** The default table probes the
  primary channel only, so a CD on the secondary channel is never seen and
  the kernel stops at `root device?`. `live.compose(form="cd")` copies the
  bundle's `Dual_EIDE.table` to `EIDE.config/Instance0.table`, and the boot
  image carries the same copy.
- **The spike found a kernel bug.** `_KernBusMemoryCreateMapping` rounded a
  physical address down to the 8 KB page and dropped the offset, so AHCI's
  ABAR at `0xfebf1000` mapped to `0xfebf0000`. Fixed in `d231848fb`
  (`kernel: keep the page offset when mapping device memory`); it affects
  every AHCI user.
- **An AHCI CD can't boot yet.** With the mapping fixed, AHCI finds the
  ATAPI drive and then an IRQ 11 interrupt storm hangs the kernel. That is
  a driver bug, filed as RhapsodiOS/RhapsodiOS#39. `--cdrom-ahci` exists
  (the controller sits at PCI slot 5, clear of `--nic`'s slot 3) and is
  tested only by argument tests.
- **#37 is still there.** The ISASerialPort boot driver fails to link
  (`_IOEnterCriticalSection`, `_IOExitCriticalSection` undefined) on every
  media boot: the CD under both firmwares and the disk media under SeaBIOS.
  It costs 10 s and nothing else. Installed disks don't list the driver.
- **SSH from this host needs Windows' OpenSSH.** Git's OpenSSH 10.3
  rejects `HostKeyAlgorithms=ssh-dss`. Put
  `Ssh=C:/Windows/System32/OpenSSH/ssh.exe` in the scratch `vm.conf`, with
  forward slashes: a backslash path is mangled when written through bash.
  An SSH session can still come back truncated or empty under load; retry.
- **`--keep-hd0` takes `work/pN-*` targets** for any phase, not only
  `work/p5-*`. The protected names and the temp-directory rule are unchanged.
- **The missing-driver notice clears `errors`,** as the old prompt did, so
  an unrelated earlier error (#37's link error) skips its 10 s pause when a
  Boot Driver is also missing. `bootefi` shows no notice.
- **boot0 has no menu,** so dual-booting from boot0 is gone. UEFI or another
  boot manager can still choose a system.
- **Stale references left:** `BootHelp.txt`'s `fd()` example, unused
  driver-disk strings in `NetInstall.strings`, the dead driver-ask keys in
  `Instance0.network`, `libsaio/saio.def` (not built) and a comment in
  `boot2/Makefile`.
- **Kernel version on the gate disks** is 5.3 (`kernel-154.5.1`), built from
  the branch before master's 5.6 bump.
- **Leftovers:** the gate targets and throwaway images remain in
  `vm/work/p6-gate`.
