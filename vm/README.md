# Rhapsody QEMU VM

Automated boot/inspect/patch loop for a Rhapsody disk image under modern QEMU
on Windows: boot headlessly or interactively, inspect the UFS image offline,
patch a driver config table or binary in place, and re-boot to observe the
result - without a human watching the VGA window for most of that cycle.

This does not claim the underlying IDE/interrupt boot bug is solved. See
`docs/drivers/drvEIDE-issues.md` for the current state of that investigation.

## Syncing `src/` to the guest (`sync-src.ps1`)

For the PPC build box (or any guest listed in `vm.conf`), use `sync-src.ps1` to
upload the local repository `src/` tree to `RemoteRoot/src` via OpenSSH
(`tar | ssh`). Modern `scp` drops the connection against this guest even with
legacy SCP mode, so the script streams a tar archive over SSH instead.

Copy `vm.conf.example` to `vm.conf` first and set `Host`, `User`, `Password`,
and `RemoteRoot` (default `/build`). Requires Windows OpenSSH Client
(`ssh.exe`) and `tar.exe`.

The guest sshd only accepts ancient algorithms. The script always passes the
same options as a manual login (see `SSH CONNECTION.md`):

```
KexAlgorithms=diffie-hellman-group1-sha1
HostKeyAlgorithms=ssh-dss
Ciphers=3des-cbc
MACs=hmac-sha1
```

Modern PuTTY `pscp`/`plink` will fail against this host with
`FATAL ERROR: Remote side unexpectedly closed network connection` unless a
saved session re-enables those algorithms — prefer `sync-src.ps1` or the
OpenSSH one-liner in `SSH CONNECTION.md`.

Host-key verification uses a throwaway file under `%TEMP%` with
`StrictHostKeyChecking=no` so a failed write to `~/.ssh/known_hosts` (common
with this guest’s `ssh-dss` host key on Windows OpenSSH) does not abort the
transfer.

```bat
powershell -File vm\sync-src.ps1 -All
powershell -File vm\sync-src.ps1 -Path drivers-i386/bus/drvPCMCIABus
```

| Flag | Effect |
|------|--------|
| `-All` | Upload the entire local `src/` directory to `RemoteRoot/src` |
| `-Path <rel>` | Upload one folder or file under `src/` (path relative to `src/`) |

Exactly one of `-All` or `-Path` is required. `-Path` creates the remote parent
directory first, then extracts the leaf under `RemoteRoot/src/<rel>`.

After extract, the script gives the synced tree exactly the execute bits git
records (Windows tar drops Unix `+x`, which breaks `./configure`): it clears
`+x` everywhere, then sets it on every file the index lists as `100755`.
Untracked files named `configure`, `config.guess`/`config.sub`, common
autotools helpers, `build_gcc`, `*.sh` or `*.pl` also get `+x`. A tracked
script that must run needs `git update-index --chmod=+x`.

This script only syncs `src/`. Broader uploads (e.g. whatever `SyncPaths` lists
in `vm.conf`) still go through `rhap-vm.ps1 sync` (PuTTY-based; same crypto
caveat applies until that tool is updated).

## Guest builds (`build-src.ps1`)

After syncing with `sync-src.ps1`, kick off builds on the PPC guest. Uses the
same OpenSSH legacy-crypto path as `sync-src` (via `rhap-remote.ps1`). The
canonical host steps also live in the repository `README.md`.

```bat
powershell -NoProfile -File vm\build-src.ps1 -Rbuild
powershell -NoProfile -File vm\build-src.ps1 -Bootstrap
powershell -NoProfile -File vm\build-src.ps1 -Kernel
powershell -NoProfile -File vm\build-src.ps1 -KernelDrivers
powershell -NoProfile -File vm\build-src.ps1 -World
powershell -NoProfile -File vm\build-src.ps1 -All
powershell -NoProfile -File vm\clean-build.ps1
```

| Flag | Remote action |
|------|----------------|
| `-Rbuild` | `make CC=… clean test all` in `RemoteRoot/src/rbuild-1`, then install `rbuild` and private helpers into `ToolsDir` |
| `-Bootstrap` | thin `rbuild bootstrap` then `rbuild bootstrap-universal` with the same `--sysroot BootstrapRoot --toolchain … --state StateDir` and full `BootstrapManifest RepoDir RepoDir` |
| `-Kernel` | `rbuild kernel --state StateDir --arch <profile> SourceRoot RepoDir BuiltDir` for `driverkit-3`, `driverTools-1`, `kernload-1`, `drivers-<arch>/bus/drvPExpert`, `kernel-7`; once per CPU, i386 then ppc, for the universal profile |
| `-KernelDrivers` | `rbuild kerneldrivers --state StateDir --arch <profile> SourceRoot RepoDir BuiltDir` (i386 then ppc for the universal profile) for remaining packaged `drv*` / `Intel*` projects under `drivers-<arch>` (plus `drvBPF` / `drvPortServer` / `drvSCSIServer` / `drvSCSITape` when they have `dpkg/control`). Paths in `src/rbuild-1/kernel-drivers-blacklist.json` are skipped until they package; rbuild exits non-zero if any non-skipped driver failed. |
| `-World` | `rbuild buildall --state StateDir Manifest RepoDir BuiltDir` |
| `-All` | `-Rbuild`, `-Bootstrap`, `-Kernel`, `-KernelDrivers`, then `-World` |
| `-Fresh` | With `-All` only: delete `ToolsDir`, `BootstrapRoot`, `RepoDir`, `BuiltDir`, and `StateDir`; keep `SourceRoot` |

Exactly one of `-All`, `-Rbuild`, `-Bootstrap`, `-Kernel`, `-KernelDrivers`, or `-World` is required. `-Rbuild` cannot be combined with `-Bootstrap`. Defaults (override in `vm.conf`): `RemoteRoot=/build`, `RepoDir=/build/repo`, `BuiltDir=/build/built`. Typical fresh-box order: `-Rbuild` → `-Bootstrap` → `-Kernel` → `-KernelDrivers` / `-World`, or a single `-All`. `clean-build.ps1` performs the `-Fresh` output reset without starting a rebuild.

### Choosing an architecture: toolchain profiles

The `<arch>` in the table above comes from the toolchain profile, selected by
`ToolchainProfile=` in `vm.conf` (default
`rbuild-1/toolchains/gcc-darwin-ppc.conf`, set in `rhap-remote.ps1`). Three
profiles ship in `src/rbuild-1/toolchains/`:

| Profile | `-Kernel` / `-KernelDrivers` build | `-Rbuild` / `-Bootstrap` |
|---------|------------------------------------|--------------------------|
| `gcc-darwin-ppc.conf` | ppc | run as before on the ppc guest |
| `gcc-darwin-i386.conf` | i386 | only on an i386 guest, or when every Mach-O tool in `BootstrapRoot/usr/bin` is universal; preflight refuses and stops otherwise |
| `gcc-darwin-universal.conf` | i386, then ppc | hand rbuild `gcc-darwin-<guest cpu>.conf` from beside it, unchanged; the guest CPU comes from `/usr/bin/arch` |

`-World` ignores the profile's CPU: `rbuild buildall` builds universal
packages by default.

Bootstrap state records a fingerprint of the exact profile file it ran with,
so switching `-Bootstrap` between `gcc-darwin-ppc.conf` and
`gcc-darwin-i386.conf` stops with `toolchain state mismatch; use -Fresh`.
The universal profile avoids that on the ppc guest because it bootstraps with
`gcc-darwin-ppc.conf` byte for byte. The ppc profile was renamed from
`gcc-darwin.conf` without changing its bytes, so existing state stays valid.

`-Kernel` requires every core package source locally except a platform
expert: `src/drivers-i386/bus/drvPExpert` does not exist yet, so with the
i386 or universal profile `build-src.ps1` prints `no local source for
drivers-i386/bus/drvPExpert; rbuild will skip it` and rbuild builds the i386
kernel without it. Any other missing core source still stops the phase.

To build one package for one CPU, call `rbuild` on the guest directly:

```sh
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
rbuild kernel --state /build/state --arch i386 /build/src /build/repo /build/<dst>
rbuild buildpackage --state /build/state --arch i386 --dir --target all \
    /build/src/drivers-i386/ide/drvAHCI /build/repo /build/<dst>
```

`rbuild` and `relpath` live in `/build/tools/bin`, which is **not** on the
default login `PATH`; without the export the build dies early with
`relpath: not found` and `Must define DSTROOT`.

Output is apks in `/build/<dst>`, not a loose binary. The kernel is inside
`kernel-*-i386.apk` at `./private/tftpboot/mach_kernel`; the apk is a gzipped
tar, so this gets it out:

```sh
gzip -dc /build/<dst>/kernel-154.5.1-7-i386.apk |
    tar xf - ./private/tftpboot/mach_kernel
```

## Image chain

| File | Role |
|------|------|
| `rhapsody.vmdk` | Original guest disk. Never opened for write, never booted. |
| `golden.img` | Raw conversion of `rhapsody.vmdk` (`qemu-img convert -O raw`). The read-only master; never booted, never written. |
| `work/test.img` | Writable scratch copy of `golden.img`. The **only** image any tool here will boot or write, unless `RHAP_TEST_IMAGE` names another (below). Disposable - recreate it any time. |

`golden.img` and `rhapsody.vmdk` are never written to directly: `rhap_inject.py`
and `qemu-shot.py` both refuse any path that doesn't resolve to
`vm/work/test.img` (`rhap_inject.check_target`), and `qemu-shot.py` additionally
boots with `-snapshot` so QEMU itself can't write through to the backing file.

Setting the opt-in `RHAP_TEST_IMAGE` environment variable to an absolute path
lets a session use its own working image: `check_target` then accepts that
path too, but still refuses `golden.img` and `rhapsody.vmdk` even if the
variable names them. `guest-console.py` boots the `RHAP_TEST_IMAGE` image
instead of `work/test.img`. With `--persist` it calls `check_target` first;
snapshot boots never write the image.

## reset-image.cmd

```bat
reset-image.cmd
```

Recreates `work\test.img` from `golden.img` (deletes the old one, then
`qemu-img convert`). Run it whenever the working image might be in a bad
state - before a test run, after an injection you don't want to keep, or
after a rebuild that no longer fits a previously grafted donor (see
`rhap_inject.py` below).

## start-vm.cmd

```bat
start-vm.cmd [-trace]
```

Interactive boot of `work\test.img`. COM1 is `-serial null` (it belongs to
the guest's `drvISASerialPort`); COM2 is `-serial stdio`, so the kernel's
serial debug console (see "Boot prompt" below) prints directly into this
window. `-trace` adds QEMU's `ide_*`/`pci_cfg_*` event tracing plus `-d int`,
logged to `logs\qemu-trace.log`.

## qemu-shot.py

```
python qemu-shot.py IMAGE OUTDIR [--at SECONDS[,SECONDS...]] [--keys STRING] [--keys-at SECONDS] [--trace]
```

Headless capture harness, standard library only:

- `IMAGE` must resolve to `vm/work/test.img` (or `RHAP_TEST_IMAGE`, if set);
  anything else (including `golden.img`) is refused before QEMU is launched.
  The drive is also opened with `-snapshot`.
- Writes `OUTDIR/shot-<seconds>s.png` at each `--at` point via QMP
  `screendump`. These filenames encode **host wall-clock seconds**, not
  guest boot progress - under TCG they are not comparable between runs.
- Writes the guest's COM2 serial console to `OUTDIR/serial.log`. COM1 stays
  `null`, same reasoning as `start-vm.cmd`.
- `--keys STRING` sends keystrokes at the boot prompt via QMP `send-key` at
  `--keys-at` seconds (default 3.0), e.g. `--keys="mach_kernel -v"` to pick a
  kernel and boot verbosely. Supported characters: `a-z`, `0-9`, `-`, `_`,
  `=`, space, and `\n`/`\r` for Return. Typing *any* character at the boot
  prompt cancels its 10-second auto-boot countdown, so a custom command line
  (e.g. one with `rootdev=...` or `serial=...`) needs an explicit trailing
  `\n` in `--keys` to actually submit it - `--keys="-v"` alone still
  auto-boots after the countdown, but `--keys="mach_kernel rootdev=9999 -v"`
  without a trailing newline just sits at the prompt forever.
- `--trace` adds the same tracing `start-vm.cmd -trace` does.

## rhap_image.py (read-only inspector)

```
python rhap_image.py IMAGE {ls|stat|cat|slack} PATH
```

Parses the NeXT disk label and UFS filesystem directly (no `mount`, no
external tools). Read-only, so it accepts any image path, including
`golden.img`. `slack` prints `size max_writable slack`, i.e. how many more
bytes could be written in place before `rhap_inject.py` would refuse.

## rhap_inject.py (in-place writer)

```
python rhap_inject.py IMAGE {set-key|put} ...
```

Only `vm/work/test.img` (or `RHAP_TEST_IMAGE`, if set) may be targeted;
`check_target` is checked before the image is ever opened for write. Never
allocates - it can only overwrite bytes within a file's already-allocated
fragments.

- `set-key PATH KEY VALUE` - rewrite one `"key" = "value";` entry in a
  DriverKit `.table` config file in place.
- `put PATH LOCAL-FILE` - overwrite an existing regular file in place.
  Refused if the payload needs a different number of fragments than the
  file currently occupies, or if the file has holes.
- `graft_file(img, target_path, donor_path, data)` - Python function only,
  no CLI command. Use it when a payload (typically a rebuilt kernel) is too
  large for its own file's allocation: it repoints `target_path`'s directory
  entry at a donor file's inode after overwriting the donor's blocks and
  bumping its link count. The donor must be an existing, hole-free regular
  file with `nlink == 1` (a private, single-named file) - unless re-grafting
  the same target onto the same donor again, which is idempotent **only**
  while the new payload still fits the donor's *current* size. The first
  graft onto a donor sets its addressable size to that payload's size; a
  later, larger payload does not fit and cannot be grafted onto the same
  donor again. Recovering from that requires `reset-image.cmd` followed by
  re-applying whatever injections are needed, not another graft.

## Boot prompt

At the `boot:` prompt (10 second timeout), type `<kernel> <args>`, e.g.:

```
mach_kernel -v serial=0x2f8
```

- Leaving it blank boots the default kernel from the startup device.
- `serial=0x2f8` selects the kernel serial debug console port (default is
  already COM2/0x2f8; `serial=0x3f8` would use COM1 instead, `serial=0`
  disables it).
- `-v` boots verbosely.
- `rootdev=9999` does **not** panic the kernel: `getargs()` parses a
  purely-numeric `rootdev=` value as an integer and stores its raw bytes
  into `swapgeneric.m`'s `rootdevice` buffer (see `i386_init.c`'s
  `kernargs` table), which then fails `setconf()`'s name match and drops
  into an interactive `root device?` retry loop (`bsd/kern/init_main.c`'s
  mountroot loop) rather than calling `panic()`. Useful for exercising that
  code path, not for producing a `panic:` line.
- A driver's own `IOLog` output reaches serial before `syslogd` opens
  `/dev/klog` too, via the same `putchar()` tap's `TOCONS` pass (see
  `bsd/kern/subr_prf.c`) - so `"Debug" = "Yes"` in a driver's `.table` (e.g.
  `set-key /private/Drivers/i386/EIDE.config/Instance0.table "Debug" Yes`)
  is visible on serial from early boot, not just after login.

## Tests

Standard library only (`unittest`), run from inside `vm/`:

```bat
cd vm
python -m unittest test_rhap_image -v
python -m unittest test_rhap_inject -v
python -m unittest test_qemu_shot -v
```

Tests that need `golden.img` / `work/test.img` skip automatically if those
files haven't been built yet.

## Driving the guest console

`guest-console.py` types into the guest over QMP and reads the framebuffer
back. The kernel serial console is output-only, so anything interactive — a
single-user shell, the boot prompt, a getty — has to be driven this way.

```bash
python guest-console.py --probe        # boot single-user, screenshot the prompt
python guest-console.py --test-mouse   # boot multi-user, check the cursor moves
```

Writes are discarded by default (`-snapshot`); pass `--persist` to let them
reach `work/test.img` (or the `RHAP_TEST_IMAGE` image, if set).

## Things that are not obvious

**Never run `fsck` on an image with a grafted file.** Grafting deliberately
leaves the donor's blocks allocated but unreferenced. `fsck` correctly regards
that as an error and frees them, after which the allocator can hand those
blocks to a later write. Observed consequence: `fsck` followed by a `cp`
removed `/mach_kernel`'s directory entry outright and left the image
unbootable. Recover with `reset-image.cmd` and re-graft.

**A grafted inode will not survive a normal multi-user boot.** `/etc/rc.boot`
runs `fsck -p`, which rejects the grafted inode with `UNKNOWN FILE TYPE` and
drops to `Reboot failed - serious errors`. Grafting is therefore fine for
*boot-testing* a kernel — the boot loader reads it before any `fsck` — but a
system that must come up multi-user needs the file installed by the guest's own
allocator, or the boot-time `fsck` disabled. The working image currently has it
disabled in `/private/etc/rc.boot`.

**Which drivers load is decided centrally**, not by what is present in
`/private/Drivers/i386`. The list lives in
`System.config/Instance0.table` under the keys `"Boot Drivers"` and
`"Active Drivers"`. Adding or removing a bundle's `Instance0.table` does
nothing on its own — a driver absent from those lists is never instantiated,
and one present in them loads regardless. This is how `drvBusMouse` was
swapped for `drvPS2Mouse` to get a working pointer under QEMU.

**`rhap_image.py` does not follow symlinks.** `/etc`, `/private/Devices` and
`/usr/Devices` are all symlinks; use the real paths (`/private/etc`,
`/private/Drivers/i386`).
