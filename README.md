# RhapsodiOS

This is an open source reimplementation of Apple's Rhapsody operating system, that later became Mac OS X Server 1.0 through 1.2v3.

It's a fork of the Darwin 0.3 open source release done by Apple in the summer of 1999 with additional contributions from the community.

## Notes

These sources work best with a case-sensitive file system. Rhapsody DR 2 and Mac OS X Server 1.0 through 1.2v3 have been tested to work at the moment.

Current builds are driven from a Windows host against a Rhapsody DR2 / Mac OS X Server **ppc** guest over OpenSSH. Copy `vm/vm.conf.example` to `vm/vm.conf` and set `Host`, `User`, `Password`, and the build paths. Defaults:

| Guest path | Role |
|------------|------|
| `/build/src` | Synced sources (`RemoteRoot/src`) |
| `/build/tools` | Private `rbuild` and bootstrap helpers |
| `/build/bootstrap-root` | Bootstrap sysroot |
| `/build/repo` | Package repository (`.apk`) |
| `/build/built` | World `DSTROOT` |
| `/build/state` | Resume state |

`rbuild` replaced the Perl `darwin-buildpackage` / `darwin-buildall` tools. QEMU, SSH crypto, and image-loop details live in `vm/README.md`.

## Sync sources

Upload from the repository `src/` tree. Prefer one project path over `-All`:

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path rbuild-1
powershell -NoProfile -File vm\sync-src.ps1 -Path cctools-2
```

`-All` uploads the entire `src/` tree. Exactly one of `-All` or `-Path` is required.

## Install rbuild

Builds, tests, and installs `rbuild` plus private `relpath`, `decomment`, `config`, and `mig` helpers into `/build/tools`:

```powershell
powershell -NoProfile -File vm\build-src.ps1 -Rbuild
```

Success prints `build-src: complete (rbuild)` and exits 0.

On the guest, the same `rbuild` tree is:

```sh
cd /build/src/rbuild-1
make CC=/usr/bin/cc clean test all
```

## Bootstrap

Stage-0 seed: resume `src/BootstrapManifest` into `/build/bootstrap-root` and `/build/repo`. `-Rbuild` and `-Bootstrap` cannot be combined.

```powershell
powershell -NoProfile -File vm\build-src.ps1 -Bootstrap
```

Success prints `build-src: complete (bootstrap)` and exits 0. Already-built packages are skipped.

## Full build

`-All` runs **rbuild**, **bootstrap**, **kernel/drivers**, then **world** in that order:

```powershell
powershell -NoProfile -File vm\build-src.ps1 -All
```

Success prints `build-src: complete (rbuild, bootstrap, kernel-drivers, world)` and exits 0.

`-Fresh` is valid only with `-All`. It deletes `/build/tools`, `/build/bootstrap-root`, `/build/repo`, `/build/built`, and `/build/state`, and keeps `/build/src`.

To reset those outputs without starting a rebuild:

```powershell
powershell -NoProfile -File vm\clean-build.ps1
```

Then sync anything that changed, run `-Rbuild`, then `-Bootstrap` (or `-All`).

Individual phases after rbuild is installed:

```powershell
powershell -NoProfile -File vm\build-src.ps1 -KernelDrivers
powershell -NoProfile -File vm\build-src.ps1 -World
```

| Flag | Remote action |
|------|----------------|
| `-Rbuild` | `make CC=… clean test all` in `src/rbuild-1`, install into `/build/tools` |
| `-Bootstrap` | `rbuild bootstrap --sysroot … --toolchain … --state … BootstrapManifest` |
| `-KernelDrivers` | `driverkit-3`, `driverTools-1`, `kernload-1`, `drivers-<arch>/bus/drvPExpert`, `kernel-7`, then optional `drv*` / `Intel*` projects |
| `-World` | `rbuild buildall --state … Manifest /build/repo /build/built` |
| `-All` | The four phases above, in order |
