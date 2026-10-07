# sysinstall and driverDetect

`sysinstall` is the installer on the install media: a full-screen curses
program that partitions a disk, installs the apks of the chosen sets and
configures the result. `driverDetect` finds the machine's PCI devices,
matches them to drivers, loads the matched network and SCSI drivers on the
live media and records the chosen drivers on the target. This is phase 5a of
the install-media design
(`docs/superpowers/specs/2026-09-22-install-media-design.md`), designed in
`docs/superpowers/specs/2026-10-05-sysinstall-design.md`. It reaches
milestone B: the media installs onto a blank `hd0`, and that disk boots on
its own under SeaBIOS and under IA32 UEFI to a `login:` that accepts SSH
with the password chosen during the install.

`docs/build/instmedia-cd.md` covers the same media as a bootable ISO.

`sysinstall` lives in `src/cdis-3/sysinstall.tproj` and installs as
`/System/Installation/CDIS/sysinstall`. `rc.cdrom` is now only a hook that
runs it. `driverDetect` lives in `src/driverkit-3/driverDetect` and installs
as `/usr/sbin/driverDetect`, beside `driverLoader`.

| Module | Job |
|---|---|
| `main.c` | The screen sequence, the partition editor and the error screen |
| `ui.c` | Menu, checklist, input box, message box and progress box on libcurses |
| `disks.c` | Candidate disks: `/dev/rhd0-3h` and `/dev/rsd0-7h` that open, sized with `DKIOCNUMBLKS`, minus the disk holding the live root |
| `layout.c` | The Auto layout, the Advanced rules, LBA-assisted CHS, MBR encode and decode |
| `sets.c` | Parses `*.set` files and takes the union of the chosen sets, `files` first |
| `config.c` | Renders the templates and edits root's `master.passwd` field |
| `steps.c` | Runs the write phase: logs each command and checks every exit status |
| `driverDetect.c` | The `driverDetect` command: PCI scan, `-l` and `-w` |
| `match.c` | `Auto Detect IDs` matching and the table edits (`table_set`, `Location`) |

Only `main.c` and `ui.c` use curses. The other `sysinstall` files and
`match.c` have host tests that build with the local clang
(`sysinstall.tproj/tests`, `driverDetect/tests`).

## The screens

1. **Welcome.** The release line from `software_version`, and the drivers
   `driverDetect -l Network SCSI` loaded for this machine's cards.
2. **Disk.** Candidate disks with sizes. Disks under 1 GB are refused, so
   the media's own 280 MB disk shows as too small.
3. **Partitioning.** **Auto** or **Advanced**, then a confirm screen naming
   the disk and the partitions that will be erased.
4. **Drivers.** One checklist per family that has drivers on the media: Disk
   (EIDE and AHCI; the controller the target sits on is ticked) and Network
   (detected cards ticked).
5. **Sets.** A checklist. `base` is required and always ticked.
6. **Root password.** Entered twice, with echo off. It can't be empty, and
   the screen says only the first 8 characters count.
7. **Summary.** Disk, layout, drivers, sets. "Install?"
8. **Progress.** One line per step, with the tail of the current command's
   output.
9. **Done.** Reboot, shell or halt.

A failed step shows the command and its output tail, then offers start over,
shell or halt. Nothing continues past a failed step. Every menu item has a
digit or letter, so QEMU key injection drives every screen.

## Partitioning

**Auto** erases the disk and writes the layout `hdimage.py` writes:

| Where | Contents |
|---|---|
| LBA 0 | `boot0` and the fdisk table |
| LBA 2048 | ESP, type `0xEF`, 131072 sectors |
| LBA 133120 | `0xA7`, active, to the last whole cylinder of the LBA-assisted geometry |

**Advanced** is an editor over the disk's MBR: list, delete, create in free
space (ESP, Rhapsody UFS or a hex type) and mark active. `layout_check`
refuses to write a table that breaks any of these rules, and the editor
shows the reason:
- no entry has a size of zero or runs past the end of the disk
- no two entries overlap
- exactly one `0xA7` entry, and it is active
- the `0xA7` entry ends on a cylinder boundary
- exactly one `0xEF` entry, of exactly 131072 sectors
- the ESP starts at LBA 2048

Other entries are kept, so a dual-boot table can pass. Start and end CHS
use the LBA-assisted rule of `build_uefi_image.py`'s `lba_assist_geometry`
(`spt` 63; 16, 32, 64, 128 or 255 heads by disk size; 1023/254/63 past
cylinder 1023), and the host tests compare the two.

## The write phase

`N` is the chosen disk, `T` is `/private/var/tmp/mnta`, `I` is
`/System/Installation`.

| # | Step | How |
|---|---|---|
| 1 | MBR | `boot0` from `/usr/standalone/i386/boot0`, then the table and `0x55AA`, written to sector 0 of `/dev/rhdNh` |
| 2 | ESP | `gzip -dc I/esp.img.gz` through a pipe, written at the ESP's LBA. Refused unless it is exactly 131072 sectors |
| 3 | Label, boot blocks, filesystem | `disk -i -b /dev/rhdNh` |
| 4 | Mount | `mount /dev/hdNa T`. The log moves from memory to `T/private/var/log/sysinstall.log` |
| 5 | Packages | Look up every node in the live `/dev`, then one `apk add --root T --initdb` run of every package of the chosen sets, with `files` first |
| 6 | Configure | Render `fstab`, `Instance0-i386.table` and `hostconfig` for `hdN`. Link `T/private/Devices` to `Drivers/i386`. Set root's `master.passwd` field to `crypt()` of the password with a random salt, then `chroot T /usr/sbin/pwd_mkdb -p /etc/master.passwd` |
| 7 | Drivers | `driverDetect -w T <chosen drivers>` |
| 8 | Check | Fails if `T/private/etc/rc.cdrom` exists |
| 9 | Finish | `sync`, `sync`, then one best-effort `umount T` |

Every apk path is resolved before apk starts, so a missing or doubled
package stops step 5 with its name. A disk installed as `hdN` gets
`rootdev=hdNa`; the harness keeps the media on `hd1`, so the target is
`hd0`.

## Sets

A set file lists packages for the installer. Keyword lines come first, then
one apk name per line; blank lines and `#` lines are ignored:

```
title       Base system
description Console system with networking and SSH
required    yes
files
basic-cmds
...
```

`src/cdis-3/sets/base.set` is installed to `/System/Installation/Sets/` and
lists the 66 packages on the media: phase 4's 65, which already include
`driverkit` and `libcurses`, and `drvisaserialinput` for the media's
ISASerialPort Boot Driver. The
set is the only thing that decides what the media carries: `vm/instmedia/build.py`'s
`check_sets` refuses the media if a set names a package the repository
lacks, or if a repository package is in no set, and
`/System/Installation/Packages` holds only the apks some set names.

## driverDetect

| Command | Does |
|---|---|
| `driverDetect` | Lists every match: family, driver, location, IDs |
| `driverDetect -l <family...>` | Loads and probes the matched drivers of those families in the running kernel, with a table built in memory, so the read-only live root needs no `Instance` table |
| `driverDetect -w <root> <driver...>` | Writes `<root>`'s system `Instance0.table`, and each chosen PCI driver's own `Instance0.table` with `Location` filled in |

The matcher reads every `/usr/Devices/*.config/Default.table` and applies
the booter's `Auto Detect IDs` rules: plain `0xDDDDVVVV`, `id&mask` and
`primary:secondary`.

PCI is read through the PCIBus resource driver's `PCI_Maximums` and
`PCI_ConfigReg` parameters. Our `drvPCIBus` answers them with a doubled
parenthesis, DR2's driver with the names without the underscore, so
`driverDetect` tries three spellings and uses the first that answers:

| `PCI_Maximums` | `PCI_ConfigReg` |
|---|---|
| `PCI_Maximums(` | `PCI_ConfigReg(Dev:%d Func:%d Bus:%d Reg:%d)` |
| `PCI_Maximums((` | `PCI_ConfigReg((Dev:%d Func:%d Bus:%d Reg:%d)` |
| `PCIMaximums(` | `PCIConfigReg(Dev:%d Func:%d Bus:%d Reg:%d)` |

The system table `-w` writes has `Boot Drivers` `EISABus PCIBus PS2Keyboard`
plus the chosen disk controller, `Active Drivers` of the chosen network,
display, audio and input drivers plus `BPF`, and `Kernel Flags`
`rootdev=hdNa`.

## The media changes

`vm/instmedia` changed for this phase:
- **Generic boot drivers.** The media's `Instance0.table` has Boot Drivers
  `EISABus PCIBus PS2Keyboard EIDE AHCI ISASerialPort` and Active Driver
  `VGA` (`live.py`'s `MEDIA_BOOT_DRIVERS` and `MEDIA_ACTIVE_DRIVERS`). NE2K
  is no longer a media Boot Driver: `driverDetect -l` finds it by PCI ID and
  loads it, so the media keeps inside the booter's `sarld` node limit.
- **Sets.** `check_sets` as above. `CDIS_NEEDS` now names `sysinstall`,
  `base.set`, `disk`, `mount`, `umount`, `apk`, `chroot`, `driverDetect`,
  `pwd_mkdb`, `gzip` and `sync`, in place of perl, the `.x86` and `.PPC`
  halves, the English strings and the old tools.
- **`/private/Devices`.** The media carries the link to `Drivers/i386` too,
  which phase 4's media did without. `/usr/Devices` is a link to
  `../private/Devices`, so without it `driverDetect` found no tables, printed
  nothing and exited 0.
- **`--preinstalled`** is unchanged, so phase 4's gates stay as regression
  checks.

## The closure

Built on a private `-snapshot` guest from the bootstrapped image, in
`/build/p5`, with an rbuild built from the worktree's `rbuild-1` and a repo
hard-linked from `/build/repo` (minus the old i386 `files`, plus
`vm/work/p2-apks` and `p4-apks`). U is `gcc-darwin-universal.conf`; I is
`gcc-darwin-i386.conf --arch i386`:

```sh
rbuild buildpackage --state $B/state --dir $A $B/src/$P $B/repo $B/out
```

| Project | Profile | Why |
|---|---|---|
| `Libcurses-1` | U | `sysinstall` links `-lcurses` |
| `drvISASerialPort` | I | The media's Boot Drivers name it, so its `_reloc` must be on the media |
| `cdis-3` | I | `sysinstall`, `rc.cdrom` and `base.set` |
| `driverkit-3` (through `rbuild kernel`) | I | `driverDetect` |

Everything else is phase 4's closure. `drvISASerialPort` needed two
packaging fixes to build (`PUBLIC_HEADERS` with no install directory, and
`English.lproj/Help` instead of `DriverHelp`).

## Commands

```bash
cd src/bootefi-1 && PATH="/c/Program Files/LLVM/bin:$PATH" make CCTOOLS=../Developer/Commands/cctools-2/include
cd ../../vm
python -m instmedia.collect work/p5-repo --image work/rhap-i386-bootstrapped.img --add work/p2-apks --add work/p4-apks --add work/p5-apks
python -m instmedia.build --repo work/p5-repo --efi ../src/bootefi-1/BUILD/BOOTIA32.EFI --out work/p5-gate/media.img
python -m instmedia.build --repo work/p5-repo --efi ../src/bootefi-1/BUILD/BOOTIA32.EFI --out work/p5-gate/preinstalled.img --preinstalled
python -c "open('work/p5-gate/target.img','wb').truncate(2<<30)"
```

`work/p5-apks` holds the new `cdis`, `libcurses`, `driverkit` and
`drvisaserialinput` apks. The target name must match
`work/p5-*/...` or be under the temp directory, or `--keep-hd0` refuses it.

**An Auto install** (SeaBIOS; the Gate 1 schedule):

```bash
python qemu_boot.py bios work/p5-gate/target.img logs/p5-gate/install --hd1 work/p5-gate/media.img --boot-hd1 --keep-hd0 --nic ne2k_pci \
  --type 130: --type 145: --type 160: --type 175: --type 190: --type 205: --type 220: \
  --type 235:rhapsodi2 --type 245:rhapsodi2 --type 255: --type 640:3
```

`--keep-hd0` lets the target keep the guest's writes while every other
drive stays snapshotted. Each `--type` presses Return after its text, and an
empty text presses Return alone; Return takes the default item of every
screen. The screens are up at about 127 s (Welcome), 136, 151, 166
(confirm), 181 and 196 (the driver lists), 211 (sets), 226 and 236
(password), 251 (summary), and Done at about 510 s. `3` on Done is Halt.
Under UEFI the Welcome screen is up by 90 s, so the same schedule fits. On a
loaded host Done came at 600 to 700 s, so Halt goes later (700 s).

**Boot the written disk alone**, once per firmware:

```bash
python qemu_boot.py bios work/p5-gate/target.img logs/p5-gate/boot-bios --nic ne2k_pci --ssh-port 2549 --at 120,240,330
```

For the SSH login, copy `vm`'s remote scripts to a scratch directory, with
a `vm.conf` that says `Port=2549`, the install password and
`Ssh=C:/Windows/System32/OpenSSH/ssh.exe` (Git's OpenSSH rejects `ssh-dss`).
Run a script
through `guest-remote.ps1 -Run` once the console shows `login:`. Remove the
`[127.0.0.1]:2549` line from `%TEMP%\rhap-known_hosts` between runs, and
retry a session that came back truncated: one opened before `Startup
complete` can.

**Advanced** (Gate 5) uses `--keys SECONDS:TEXT`, which types without
pressing Return, because the editor's menus act on a key and a trailing
Return would land on the next menu. After the Welcome and Disk screens it
sends `2` (Advanced), `211` (create, first free region, ESP), `212` with
Return (create, region 1, `0xA7`, default size), `4` (use this table:
refused, because `0xA7` isn't active), Return, `32` (mark entry 2 active)
and `4` again, then continues as an Auto install does.

## Results

Results on 2026-10-06: the five gates and phase 4's regression gates pass.
The final media is `media5.img`, built from `p5-repo6` (101 apks, 66 of them
on each image).

| Image | apks | Nodes | UFS | Disk |
|---|---|---|---|---|
| `media.img` | 66 | 5705 | 215 MB | 280 MB |
| `preinstalled.img` | 66 | 5637 | 654 MB | 719 MB |

| Gate | Install | Result |
|---|---|---|
| 1 | SeaBIOS, Auto, 2 GB, password `rhapsodi2` | Reaches Done. Halt from Done gives a disk marked clean (`FILESYSTEM CLEAN; SKIPPING CHECKS`). It boots alone under SeaBIOS (`login:` by 330 s) and under UEFI (240 s). SSH as root accepts `rhapsodi2` and `rhapsodi`, and refuses a wrong password. `/dev/hd0a on /`, `en0` 10.0.2.15, `no rc.cdrom`, and `/private/var/lib/apk` holds the database |
| 2 | Media booted under IA32 UEFI | The same, with Done by 690 s. The loader read from the media's disk, `rootdev=hd1a` |
| 3 | SeaBIOS, Auto, 4 GB | The MBR matches LBA-assisted CHS byte for byte (heads 255, `0xA7` ends 521/254/63) and boots. `df` shows the whole 4 GB partition |
| 4 | `-device ne2k_pci` | The media's Welcome screen lists `NE2K (Network, Dev:3 Func:0 Bus:0)`. On the installed disk NE2K is an Active Driver with `Location` `Dev:3 Func:0 Bus:0` in its `Instance0.table`, and DHCP gives `en0` 10.0.2.15 under both firmwares |
| 5 | SeaBIOS, Advanced, 2 GB | The editor refuses an inactive `0xA7`, then accepts the table the keys build. Sector 0 is byte-identical to Gate 2's, and the disk boots to `login:` and SSH |

| Regression gate | Firmware | Result |
|---|---|---|
| 3 (phase 4) | SeaBIOS | `preinstalled.img`: NE2K and BPF load, `login:`, SSH as root with `rhapsodi`, `driverDetect` present |
| 4 (phase 4) | IA32 UEFI | The same. The first login came back truncated; a retry 20 s later was complete |

## Worth knowing

- **The kernel keeps a mounted filesystem busy after two execs.** Running
  a binary from a mounted UFS twice leaves it busy until shutdown; once is
  fine.
  - On the guest: `mount /dev/hd0a T`, `chroot T /usr/bin/true` twice,
    `umount T` gives "Device busy", and `umount` after one run succeeds. No
    process or open file remains (`ps -ax`, `fstat`), and a retry minutes
    later and `sync` don't help. `reboot` from that state syncs and restarts
    normally.
  - `apk` runs `files`' two install scripts, each starting `T`'s `sh`, and
    step 6 runs `chroot T pwd_mkdb`, so the install can't avoid it.
    `apk-tools` 2.0_pre12 has no `--no-scripts`.
  - Step 9 is therefore best-effort: the Done screen's reboot or halt starts
    the kernel's forced unmount. The disks came out clean (`fs_clean` 1,
    `fs_fmod` 0).
  - Suspected: the VM object cache in `kernel-7/vm/vnode_pager.c`
    (`vnode_pager_setup`, `vnode_uncache`, `vnode_pager_umount`). A kernel
    fix was raised as a separate task.
- **The live `/dev` is looked up before `apk` runs.** `checkalias()`
  (`kernel-7/bsd/vfs/vfs_subr.c`) gives an in-use device vnode that no file
  system has claimed to the first one that looks up a node for that device.
  On the media that vnode is the root's own, `hd1a`. Without the sweep,
  `apk`'s `chown` of `files`' `private/dev/hd1a` hands it to `T`, which then
  can't be unmounted. This was confirmed on the guest (`mknod b 3 8` and
  `chown` busy; after `ls -l /dev/hd1a` first, not busy).
- **Everything installs in one apk run.** `files` depends on `basic-cmds`,
  `csu` and `libsystem`. `apk-tools` 2.0_pre12 resolves a dependency only
  among the apks on its command line, so `files` alone fails with "Unable to
  install 'files'".
- **Only 8 characters of the password count.** The install password
  `rhapsodi2` and `rhapsodi` both log in over SSH.
- **Installed filesystems are big-endian.** `disk -i` on the guest writes a
  byte-swapped UFS; `fsck` prints "Reverse Byte order Filesystem Detected"
  and the kernel and booter handle it. `vm/rhap_image.py` reads only
  little-endian, so reading an installed disk on the host needs a scratch
  copy with the UFS fields read big-endian.
- **Open: the ISASerialPort boot driver doesn't link under UEFI.** The
  media's boot prints `Error occurred while linking driver ISASerialPort:
  rld(): Undefined symbols: _IOEnterCriticalSection _IOExitCriticalSection`
  and pauses 10 seconds. The media still boots and nothing needs the driver.
  Installed disks don't list it as a Boot Driver. SeaBIOS probably prints
  the same on screen. The owner should decide: rebuild the driver or supply
  the symbols.
- **The `driverDetect` list is silent on failure.** `readTables` returns on
  a failed `opendir` of `/usr/Devices`, so a dangling link printed nothing
  and exited 0. That is how the missing media link was found. Left as it
  is.
- **Kernel output paints over the curses screen** when `driverDetect -l`
  loads a driver on the Welcome screen, and can clip the "Press Return"
  line. Cosmetic.
- **`--type` always presses Return.** Use `--keys` for key-driven screens.
- **The pre-installed image stays,** for regression and for gates that
  don't need an install.
- **Not touched here:** `LibcAT-1` and the universal-apk dependency limits
  phase 4 recorded, and the other CDIS tools (`pickdisk`, `sysconfig`,
  `findroot`), which stay unused.
- **The Instance0 template's comment is out of date.** In
  `src/cdis-3/templates/Instance0-i386.table`, it says NE2K is a Boot Driver
  because the booter finds the card by PCI IDs. The kernel probes Boot
  Drivers, not the booter, and an installed disk's table comes from
  `driverDetect -w`, which puts NE2K in Active Drivers with `Location`
  filled in. The template's `Boot Drivers` line still names NE2K and only
  serves the pre-installed image. Not changed by this task.
- **Leftovers:** the gate targets (`target-g1e.img`, `target-g2.img`,
  `target-g3.img`, `target-g5.img`) and the throwaway ones remain in
  `vm/work/p5-gate`.
