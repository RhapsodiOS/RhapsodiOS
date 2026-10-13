# instmedia's install media

`vm/instmedia/` builds a bootable hard-disk image on the Windows host from
nothing but our apks. Two kinds come out of it: the install media, whose
root boots into CDIS's installer, and, with `--preinstalled`, a disk that
boots as an installed system. This is phase 4 of the install-media design
(`docs/superpowers/specs/2026-09-22-install-media-design.md`). It retires
the design's first risk: a system built only from our apks boots. The
media reaches the installer's menus, and the pre-installed disk reaches a
multi-user `login:` and accepts SSH, under SeaBIOS and under IA32 UEFI.

(Before phase 5; now the media's installer is `sysinstall`, not CDIS's perl
`rc.cdrom`. The media's Boot Drivers are generic, `build.py` checks for
`sysinstall` and its tools instead of perl, and `/System/Installation/Packages`
holds only the packages a set names. `docs/build/sysinstall.md` records the
changes; the rest of this page is phase 4's.)

| Module | Job |
|---|---|
| `collect.py` | Gathers the apks into one flat directory: the universal apks in the bootstrapped image's `/build/repo`, read in place, then each `--add` directory. A later build of a package replaces an earlier one |
| `apkrepo.py` | Indexes that directory: one build per package, i386 over universal. It refuses ppc-only builds and leaves out `-hdrs` and `-obj` companions |
| `rootfs.py` | Lays apk payloads out as a node tree the way `apk add` would, following the root's `etc`, `var` and `tmp` links, and records every path two packages claim |
| `live.py` | Composes the root: `files` first, then the rest by name, then the live overlay or the installed-system configuration |
| `hdimage.py` | Writes the disk: `boot0` and the fdisk table, the ESP, and the `0xA7` partition as `disk -i -b` lays it out |
| `build.py` | The command: checks the root, writes the image and reads it back |

`testconfig.py` holds the pre-installed disk's password hash, and
`testapks.py` makes the small apks the tests use.

## The disk

| Where | Contents |
|---|---|
| LBA 0 | `boot0` and the fdisk table |
| LBA 2048 | The ESP: FAT32, 131072 sectors, holding only `/EFI/BOOT/BOOTIA32.EFI` |
| LBA 133120 | The active `0xA7` partition: `boot1` in its first sector, label copies at +15/30/45, `boot2` at +64 and +192, UFS from +320 |

The disk ends on a cylinder of the LBA-assisted geometry the BIOS picks
for it, so the `0xA7` entry's end CHS is exact.

**The media's root** is every apk plus an overlay of four things:
- `/private/etc/rc.cdrom`: the `cdis` apk's inert `rc.cdrom.hidden`, made
  live (0755). `rc` and `rc.boot` run it because `/System/Installation` is
  there too.
- `/private/Drivers/i386/System.config/Instance0.table`: CDIS's
  `Instance0-i386.table` template, rendered for `hd1`, the media's disk in
  the harness.
- `/System/Installation/Packages/*.apk`: every apk the root was made from.
- `/System/Installation/esp.img.gz`: the ESP, for the installer to write.

**The pre-installed root** has no overlay. Instead:
- `fstab`, `Instance0.table` and `hostconfig` are rendered from CDIS's
  templates for `hd0`.
- `/private/Devices` is linked to `Drivers/i386`.
- Root's password is `testconfig`'s hash of `rhapsodi`.

**`build.py` refuses an image,** listing every problem, when:
- two packages claim a path
- the root lacks `mach_kernel`, `boot0`, `boot1`, `boot`, `sarld`, or a
  Boot Driver its `Instance0.table` names
- the media lacks what CDIS runs before its first menus: `perl`,
  `rc.cdrom` and its `.x86` and `.PPC` halves, the English strings,
  `findroot`, `gc`, `popconsole` and `pickdisk`
- the pre-installed disk lacks `sshd`, `mount`, `getty`, `driverLoader` or
  BPF, or its `/usr/Devices/System.config/Instance0.table` doesn't lead to
  the system table
- a `/dev` node's major disagrees with the kernel's. The block and
  character majors are `hd` 3 and 15, `sd` 6 and 14, and `fd` 1 and 41.

After writing, it reads the image back: `readback.diff` against the tree
and `ufs_check.check` on the allocation accounting must both be clean.

## The boot closure

These projects were built on a private `-snapshot` guest booted from the
bootstrapped image, in `/build/p4`, and fetched to `vm/work/p4-apks`. U is
`gcc-darwin-universal.conf`; I is `gcc-darwin-i386.conf --arch i386`.

| Projects | Why |
|---|---|
| `driverTools-1` (U), then `rbuild kernel` (I) for `driverkit-3`, `kernload-1` and `kernel-7` | The drivers need `drivertools`. `driverkit` carries `driverLoader` |
| `drvEISABus`, `drvPCIBus`, `drvPS2Keyboard`, `drvEIDE`, `drvAHCI`, `drvNE2k` (I) | The Boot Drivers, the network card among them. `drvEIDE` also makes `drveide-hdrs` |
| `drvBPF` (I) | Added: `dhcpcd` needs `/dev/bpf*`, which BPF's Post-Load creates |
| `Libinfo-1`, `yacc-1`, `flex-1`, `Libtelnet-1`, `gawk-1` (U) | Build dependencies of `network_cmds` and `boot-2`. `Libinfo` is rebuilt for its header fix |
| `network_cmds`, `dhcpcd-1`, `gnuzip-1`, `system_config-1` (U) | `ifconfig`, `syslogd` and `inetd`; DHCP; `gzip`; the `System.config` bundles |
| `diskdev_cmds`, `cdis-3` (I) | `mount`, `fsck`, `newfs` and `disk`; the installer. They are built I because rbuild resolves a universal build's dependencies only against universal apks, and `drveide-hdrs` exists only for i386 |
| `boot-2` (I) | `boot0`, `boot1`, `boot2` and `sarld` |
| `files-5`, `relcontrol-10` (U) | Added. `files` is rebuilt from current source so that `0800_Network` tries `dhcpcd`. `relcontrol` installs `software_version`, which CDIS's release line reads |

Phase 2's apks in `vm/work/p2-apks` (zlib, apk-tools, perl, OpenSSL,
OpenSSH, and an older `files`) are added before `p4-apks`, so the rebuilt
`files` wins. perl is what CDIS's `rc.cdrom` runs on. `LibcAT-1` was
planned and dropped: it builds for ppc only, and nothing in `network_cmds`
links it.

## Commands

```bash
cd src/bootefi-1 && PATH="/c/Program Files/LLVM/bin:$PATH" make
cd ../../vm
python -m instmedia.collect work/p4-repo --image work/rhap-i386-bootstrapped.img --add work/p2-apks --add work/p4-apks
python -m instmedia.build --repo work/p4-repo --efi ../src/bootefi-1/BUILD/BOOTIA32.EFI --out work/p4-gate/media.img
python -m instmedia.build --repo work/p4-repo --efi ../src/bootefi-1/BUILD/BOOTIA32.EFI --out work/p4-gate/preinstalled.img --preinstalled
python -c "open('work/p4-gate/blank.img','wb').truncate(2<<30)"
python qemu_boot.py bios work/p4-gate/blank.img logs/p4-gate/media-bios --hd1 work/p4-gate/media.img --boot-hd1 --type 150:1 --type 200:1 --at 145,240
python qemu_boot.py bios work/p4-gate/preinstalled.img logs/p4-gate/pre-bios --nic ne2k_pci --ssh-port 2549 --at 120,240,330
```

Repeat both boots with `uefi` in place of `bios`. UEFI reaches the menu
about ten seconds later, so its media run typed at 160 and 210 s.
- `collect` refuses a non-empty output directory, so each collection needs
  a fresh one.
- `blank.img` is the 2 GB target the installer sees as `hd0`.
- For the SSH login, copy `vm`'s remote scripts to a scratch directory,
  with a `vm.conf` that says `Port=2549` and `Password=rhapsodi`. Run a
  script through `guest-remote.ps1 -Run` once the console shows `Startup
  complete`.
- Every first boot makes new host keys. Remove the `[127.0.0.1]:2549` line
  from `%TEMP%\rhap-known_hosts` between runs.

## Results

Results on 2026-09-28: all four gates pass. The images came from
`vm/work/p4-repo7`, which collected 100 apks; 65 of them went on each
image.

| Image | Nodes | UFS | Disk |
|---|---|---|---|
| `media.img` | 5678 | 214 MB | 279 MB |
| `preinstalled.img` | 5612 | 653 MB | 718 MB |

| Gate | Firmware | Image | Result |
|---|---|---|---|
| 1 | SeaBIOS | `media.img` | Root on `hd1a` (`rootdev 308`), read-only, fsck skipped. `Darwin OS Release: Mac OS X Server 1.2.1 (Medusa1E3)` and the language menu by 145 s. `1` brings the Intel warning, and `1` again runs `pickdisk`, which names `IDE Disk 0 (Type 255) - 2048 MB` as the startup disk and offers install or advanced options |
| 2 | IA32 UEFI | `media.img` | The same, with the menu by 155 s |
| 3 | SeaBIOS | `preinstalled.img` | NE2K probed as a Boot Driver and BPF loaded by `driverLoader`. DHCP gives `en0` 10.0.2.15 at boot, then `Startup complete` and the console `login:`. SSH as root with `rhapsodi` on port 2549 shows `/dev/hd0a on /`, `en0` at 10.0.2.15, `no rc.cdrom`, and `Instance0.table` through `/usr/Devices` |
| 4 | IA32 UEFI | `preinstalled.img` | The same |

## Worth knowing

- **CDIS is the installer.**
  - `cdis-3` ships its script as `/private/etc/rc.cdrom.hidden`, so `apk
    add` puts only an inert copy on a target. The builder makes the
    media's copy live.
  - `sysconfig` isn't built, so CDIS asks its language question first.
  - The installer's templates live in `/System/Installation/CDIS/templates`,
    and the target mounts at CDIS's `/private/var/tmp/mnta`.
  - The Instance0 template comes per architecture: `Instance0-i386.table`
    carries this design's overrides. `Instance0-ppc.table` is Mac OS X
    Server 1.2.1's ppc `Default.table`, because on ppc the booter picks the
    boot drivers and the kernel takes its root from Open Firmware.
  - The release line reads `relcontrol`'s
    `/System/Library/CoreServices/software_version`, Mac OS X Server
    1.2.1's, taken from the ppc disk. It prints the version with the
    product code in parentheses. It used to print a hard-coded "Darwin OS"
    and a stray `(1%)`, which was `ConsoleMessage`'s progress argument.
- **NE2K is a Boot Driver.** As an Active Driver with only its
  `Default.table`, DR2's `driverLoader` never probed it: no banner and no
  `en0`. It loads once `Configure` has written an `Instance0.table` naming
  the card's PCI location. As a Boot Driver, the kernel probes it by PCI
  IDs before root is mounted, whatever slot the card is in.
- **BPF must be an Active Driver.** `dhcpcd` opens `/dev/bpf*`, which BPF's
  Post-Load creates. Without it `en0` stays down and nothing says why, so
  `build.py` refuses a pre-installed disk without BPF.
- **`/private/Devices` is the installer's.**
  - `driverLoader` reads the system table through `/usr/Devices`, which
    `files` links to `../private/Devices`.
  - CDIS links `/private/Devices` to `Drivers/<arch>` on its target
    (`rc.cdrom`), so no package ships the link. One link in a universal
    apk would be wrong on one of the two architectures.
  - The pre-installed disk gets the link from the builder.
  - The media needs none, because the booters look in
    `/private/Drivers/i386` before `/usr/Devices`.
    (Before phase 5; now the media carries the link too, because
    `sysinstall`'s `driverDetect` reads the drivers through `/usr/Devices`.
    See `docs/build/sysinstall.md`.)
- **Logins need no `lookupd`.** `nibindd`, `lookupd` and `niutil` aren't
  built, so no NetInfo domain comes up. The console and SSH logins still
  work, because `getpwnam` reads `master.passwd`.
- **The companion rule.** `-hdrs` and `-obj` apks repeat files their base
  packages ship, and `apk add` refuses a path two packages claim. So the
  media carries neither, like phase 2's apk-installed root.
- **Packaging fixes.** Each of these was a path two apks claimed, a build
  failure, or a check the builder got wrong:
  - `driverkit` no longer installs `PrivateHeaders/driverkit/i386/PCMCIA.h`,
    which the kernel installs too.
  - `Libinfo` and `boot` leave `arpa/inet.h` and
    `machdep/i386/kernBootStruct.h` to the kernel, whose copies every
    build already compiles against.
  - `network_cmds` drops `libcat` from its `makedepends`, and links
    `named-xfer` with `$(ARCHITECTURE_FLAGS)`, which had come out i486-only.
  - `drvPCIBus` counts buses in an int. Under UEFI `bootefi` reports
    `maxBusNum` 255, and an `unsigned char` counter wrapped forever.
  - `build.py` checks `/dev` majors per disk family and node kind, so the
    controllers' character nodes (`fdc0`, `sdc0`) pass.
- **First-boot delays.** QEMU's DHCP names no host, so `0800_Network` waits
  for `bpwhoami` to time out. The first boot also makes the SSH host keys.
  `Startup complete` comes within four minutes. SSH sessions opened before
  then came back truncated, one with no output at all, though `sshd` took
  them. Sessions opened after it returned everything.
- **Known noise.**
  - Under UEFI, `init` prints `unrecognized flag '-?'`: `bootefi`'s
    compiled-in `-v` reaches `init`, whose `getopt` takes only `-s` and
    `-f`.
  - The pre-installed disk's startup reports `nmserver`, `nibindd`,
    `lookupd`, `pbs`, `lpd`, `npd` and `niutil` not found.
