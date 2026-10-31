# Installing a Rhapsody root with apk

Phase 2 of the install-media design
(`docs/superpowers/specs/2026-09-22-install-media-design.md`) put apk-tools,
OpenSSL and OpenSSH into the world build and showed that apk can lay down a
whole root from rbuild's universal apks:

```sh
apk add --root <scratch> --initdb <every base apk>
```

## What each project needed

| Project | Change |
|---|---|
| `src/Manifest` | Lists `apk-tools-1`, `OpenSSH` and `OpenSSL` |
| `rbuild-1` | Packs `.PKGINFO` and the install scripts first, with no `./` prefix, as apk-tools reads them. Writes a package's `depend` list into `.PKGINFO` |
| `files-5` | `depend = basic-cmds, csu, libsystem`: its install scripts need `sh`, dyld and libSystem, so apk installs those first |
| `apk-tools-1` | Builds with make 3.74 and gcc 2.95, reads zlib 1.1.3 gzip streams, pax and GNU tar archives, and installs into Rhapsody's root layout. `src/Commands/apk-tools-1/PORTING.md` has the details |
| `zlib-1` | Installs its headers at `System.framework`'s real path. `/usr/include` is a symlink in the root, and rbuild refuses to merge a directory over one |
| `perl-1` | Reads `environ` through `_NSGetEnviron`, since Rhapsody's `crt1.o` exports no `__environ` |
| `OpenSSL` | Built `no-idea`: this tree ships the IDEA sources as empty files |
| `OpenSSH` | `fixpaths` is given its input by file name, since make 3.74 gives VPATH targets their full path |

## How it was checked

On a private i386 guest booted from `vm/work/rhap-i386-bootstrapped.img`
with `-snapshot`:

1. Each project was built with
   `rbuild buildpackage --toolchain gcc-darwin-universal.conf`, giving
   `lipo` `ppc i386` binaries.
2. `apk add --root <scratch> --initdb` was run with every
   `*-universal.apk` in the repository except the `-hdrs` and `-obj`
   companions.
3. Host keys were made with the packaged `ssh-keygen`, in a `chroot` of the
   new root, and the packaged `sshd` was started there on a spare port and
   forwarded to the Windows host.

Results on 2026-09-27:

| Check | Result |
|---|---|
| `apk add --root <scratch> --initdb` of 44 base apks | Exit 0, `OK: 44 packages, 362 dirs, 3649 files` |
| `private/var/lib/apk/installed` | 44 `P:` records, one per apk, among them `apk-tools`, `files`, `openssh`, `openssl`, `perl` and `zlib` |
| Root layout | `.hidden`, and `cores`, `dev`, `etc`, `mach`, `tmp` and `var` as the symlinks `files` ships |
| `chroot <root> ssh-keygen` (RSA1 and DSA) | Both exit 0 |
| `chroot <root> sshd -p 2200` | Starts. A password login as `root` from the Windows host lands inside the new root |
| `apk-tools/tests/smoke.sh` on the guest | Passes |

## Worth knowing

- **Install base packages only.** A `-hdrs` or `-obj` companion repeats
  files its base package ships, and apk refuses to overwrite another
  package's file, so a root is made from the base apks.
- **OpenSSH's entropy source is decided in the build chroot.** configure
  uses `/dev/urandom` if the chroot has it, and `files` makes that node
  (commit `ba4dcd9ae`). Built against an older `files`, OpenSSH falls back
  to running the commands in `/etc/ssh_prng_cmds`. It needs 16 of those,
  and its install step marks any that fail in the chroot as `undef`, which
  leaves too few for `ssh-keygen` to start.
- **The chrooted login used the running system's accounts.** `files` ships
  `root:*`, yet the guest's own root password worked, so libc found the
  account outside the chroot, presumably through the running system's
  `lookupd`. Whether an installed system does the same is risk 7 in the
  design.
- **`files`' install scripts run `umount` and `mount` on `/dev`.** apk runs
  them chrooted in the new root. This repository has no diskdev-cmds apk, so
  neither command was there, and the scripts printed `not found` and went
  on. In a root that gets diskdev-cmds before `files`, they would unmount
  and remount the target's `/dev`.
- **Fetch results from a `-snapshot` guest at once.** Everything built there
  lives in QEMU's temporary overlay and is gone when the guest stops.
