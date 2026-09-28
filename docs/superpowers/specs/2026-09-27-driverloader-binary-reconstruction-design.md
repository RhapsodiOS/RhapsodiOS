# driverLoader binary reconstruction

Reconstruct Apple's i386 `driverLoader` from Rhapsody DR2 as source in a new
subproject of `src/driverkit-3`. Drive it to function-level parity with Apple's
binary under binrecon, the bar PnPDump used. Ship it in the driverkit apk and
boot-test it against Apple's copy.

## Motivation

The tree has no source for `driverLoader`, yet every boot depends on it. On
i386 the DR2 root's `/etc/startup/0300_Devices` runs `driverLoader a`, and the
tree's ppc `src/files-5/private/etc/startup/0700_Devices` runs
`driverLoader D=<name>` per driver. Recent work relies on its behaviour:
running a config's Post-Load (`drvPortServer/reconstruction/pdservd.md`) and
loading BPF at boot (the dhcpcd-1 plan). Today the binary comes along from the
DR2 base, so it can be neither rebuilt nor fixed.

## 1. Reference and triage (do not rediscover)

| Property | Value |
|---|---|
| Source | `/usr/sbin/driverLoader` in `vm/work/rhap-i386-bootstrapped.img` (DR2 i386), read with `vm/rhap_image.py` opened read-only |
| Host copy | `C:\Users\raynorpat\Downloads\test\DR2\usr\sbin\driverLoader` (outside the repo, like the PnPDump reference) |
| Mode / owner | `0555`, root:wheel (0:0) |
| Size | 70132 bytes |
| SHA-256 | `e005522ec2e4f107b8071a573ccda9208d49e64e2114d08b8868ee956a0e98b7` |
| Mach-O | i386 `MH_EXECUTE`, flags `0x15`, links only `System.framework/Versions/B/System` |
| `__text` | `0x3840`, 28940 bytes |
| Symbols | 349 in the symbol table, 269 defined; **unstripped**, statics included |
| Man page | `/usr/share/man/man8/driverLoader.8`, 1872 bytes, SHA-256 `0049722e66fc99474a26134640c23664fe11f035719843c0669d46ce644c0b97`, mode `0444`; host copy under `...\DR2\usr\share\man\man8\` |

The base image is a shared backing file for other sessions' guests. Never open
it writable.

The man page (dated 1994) documents `/usr/etc/driverLoader` and the `a`, `i`,
`v` and `d=` operations. The binary's usage text also has `D=deviceName`
(non-interactive), and DR2 installs it in `/usr/sbin`. The binary wins.

`__text` holds, in this order:

1. crt and dyld glue (`start`, `__call_mod_init_funcs`, …)
2. **driverLoader's own code**, `0x39a0`–`0x4b98`, in address order: `main`,
   `usage`, `inquire`, `processDriverList`, `processDriver`, `loadDriver`,
   `unloadDriver`, `getInstanceFile`, `configDriver`, `securityCheck`,
   `securityCheckDir`, `prePostExec`, plus globals `verbose`, `interactive`,
   `instruction`, `progName`
3. **a kern_loader client module**, `0x4b98`–`0x51d4`, in address order:
   `kl_init`, `kl_com_log`, `print_string`, `ping`, `kl_com_add`,
   `kl_com_delete`, `kl_com_load`, `kl_com_unload`, `kl_com_get_state`,
   `kl_com_error`, `kl_com_wait`, statics `strings.10`, `ping_lock`, and
   globals `kl_init_flag`, `kl_port`, `kernel_task`, `reply_port`
4. **libDriver user-mode objects**, in this order: `IOConfigTable`
   (with `parseDriverList` and the `Private` category), `IODevice` (with the
   `GlobalParameter` and `Internal` categories), `IODeviceMaster`,
   `driverServerUser` (the `driverServer.defs` MIG user stubs
   `_IOGetDriverConfig`, `_IOProbeDriver`, …), `NXConditionLock`, `NXLock`,
   `generalFuncs` (`IOLog`, `IOMalloc`, `IOScheduleFunc`, …)
5. **libkernload objects**: `kern_loader_*` MIG user stubs,
   `kern_loader_reply_handler`, `kern_loader_look_up`

Only groups 2 and 3 are source this project owns.

### How Apple linked groups 4 and 5

- `src/kernload-1/libkernload` installs a static `/usr/lib/libkernload.a`, and
  both DR2 and the bootstrap root have it. Group 5 comes from `-lkernload`.
- `src/driverkit-3/libDriver` builds only dylibs (`libDriver.A.dylib`,
  `_profile`, `_g`) and kernel objects. DR2 and the bootstrap root have only
  `libDriver.dylib`, and there is no user-mode static archive anywhere. Yet
  Apple's binary carries the group 4 objects statically and depends on
  nothing but System.
- Group 4's order is not alphabetical: `driverServerUser` sits between
  `IODeviceMaster` and `NXConditionLock`. That is an explicit object list.
- So Apple linked libDriver's user release objects directly, out of the
  driverkit build. `driverLoader` was a driverkit subproject that Darwin 0.3
  dropped. This reconstruction puts it back there.

## 2. Project layout

```
src/driverkit-3/
  Makefile              # SUBDIR and INSTALL_SUBDIR gain driverLoader, after libDriver
  PB.project            # SUBPROJECTS gains driverLoader
  apk/pkginfo           # makedepends gains kernload-hdrs, kernload
  driverLoader/
    Makefile            # handwritten, in the style of configutil/Makefile
    driverLoader.m      # group 2
    kl_com.m            # group 3
    driverLoader.8      # from the image
    reconstruction/     # as libDriver/reconstruction
      nlist.md  ledger.json  source-map.json  divergences.md  function-worklist.md
tools/binrecon/profiles/driverloader.json
```

- `src/Manifest` already lists `driverkit-3`, so it does not change.
- `driverLoader/Makefile` compiles `driverLoader.m` and `kl_com.m` and links:
  ```
  driverLoader.o kl_com.o \
    ../libDriver/<arch>Release/{IOConfigTable,IODevice,IODeviceMaster,driverServerUser,NXConditionLock,NXLock,generalFuncs}.o \
    -lkernload
  ```
  The libDriver objects are named explicitly, in Apple's order, from the
  build directory libDriver's `<arch>release` target already fills. The
  top-level Makefile gives each subproject `OBJROOT=$(OBJROOT)/<subdir>`, so
  from `driverLoader` that directory is `$(OBJROOT)/../libDriver/<arch>Release`.
  Nothing else from libDriver is linked.
- It installs `/usr/sbin/driverLoader` (mode `0555`, root:wheel, **not
  stripped**: Apple's copy keeps its full symbol table) and
  `/usr/share/man/man8/driverLoader.8` (mode `0444`).
- It builds one slice per CPU in `RC_ARCHS` and `lipo`s them together, as
  libDriver does. The world build of driverkit is universal, and rbuild's
  product check needs every Mach-O in the package to hold exactly the
  package's CPUs. So the shipped binary is fat. Its **ppc slice compiles from
  the same source and is not measured**: parity work is i386 only.

### How the sources are written

- Start from IDA 9.2 decompiles of the group 2 and 3 functions, cleaned into
  the ObjC/C the NeXT sources of the time used.
- `kl_com.m` starts from `src/hfs-1/hfs_util/kl_com.c` and
  `src/driverkit-3/Examples/loadable/User/kl_com.m` where the decompile shows
  they match.
- String literals come from `__cstring`.
- Every function, static and global keeps Apple's name from the symbol table.
  No names are invented.
- Behaviour that is odd but harmless is reproduced. A genuine bug is fixed
  only as a labelled entry in `divergences.md`.

## 3. Linked library code

Group 4 and 5 functions are measured in this binary and held to the bar in §4.
When one misses:

- **The fix belongs in the library source.** Edit `src/driverkit-3/libDriver`
  or `src/kernload-1/libkernload`. `IODevice.m`, `IOConfigTable.m` and
  `generalFuncs.m` are also compiled into libDriver's kernel objects, and all
  group 4 files go into `libDriver.dylib`. A fix must not regress libDriver's
  existing `reconstruction/ledger.json` or any other recorded parity result.
- **The difference is Apple's own source moving on.** Our libDriver sources
  are Darwin 0.3, later than DR2's binaries (see
  `src/driverkit-3/libDriver/reconstruction/divergences.md`). A difference
  explained that way is an **accept** with that reason. libDriver is not
  rewritten back to DR2.
- **A fix would break another consumer.** Record an accept that names the
  consumer. Do not fork the file into `driverLoader/`.

## 4. Done bar

**Owned functions (groups 2 and 3).** Done when `raw_equal` or
`masked_equal` holds on a comparison against the current guest-built i386
binary, or when the leftover is recorded in `divergences.md` with its
`binrecon function --name` dump and an explicit *accept*. Accepts are for
compiler-shaped differences only: register allocation or instruction
scheduling.

**Linked functions (groups 4 and 5).** The same bar, or a recorded accept
under §3.

**The campaign is done when:**

- every owned function meets the bar, and none is `unexamined` in the ledger
- every linked function meets the bar or has a recorded disposition
- `parity_check.py` reports 0 `missing_strings` and 0 `missing_symbols`
- the §5 packaging and the §6 behaviour and boot tests have passed, or any gap
  is recorded

`__text` size is not a target. `cfg_equal` is not a pass signal.

### Tooling

`tools/binrecon/profiles/driverloader.json`, modelled on `pnpdump.json`: i386,
IDA 9.2 and angr enabled, Ghidra disabled, acceptance `normalized-functions`,
output under `out/driverloader`. Reference and rebuilt paths come from
`BINRECON_REFERENCE` / `BINRECON_REBUILT`. The rebuilt input is the thin i386
binary (or the i386 slice of a fat one).

### Guest workflow

- Use a private `-snapshot` guest booted from `rhap-i386-bootstrapped.img` on
  its own ssh and QMP ports. Never use the shared box.
- Keep one ssh session at a time, and never poll.
- Build driverkit with `rbuild buildpackage` and
  `--toolchain .../gcc-darwin-i386.conf --arch i386` into a private output
  directory. When a compile fails, iterate in the leftover build root.
- Fetch the apk to the host straight after each build, and compare on the
  host.

## 5. Packaging

- Add `kernload-hdrs, kernload` to driverkit's `makedepends`.
- The closing build is universal, as the world builds it:
  `rbuild buildpackage --toolchain .../gcc-darwin-universal.conf`. The
  resulting `driverLoader` is `lipo` ppc+i386, and its i386 slice is the one
  the ledger measured.
- Check the repository's apks for any other package that ships
  `usr/sbin/driverLoader`. If one does, remove it from that package in the
  same change, so exactly one package owns the file.

## 6. Behaviour and boot tests

### Side-by-side behaviour

A guest script runs Apple's binary and ours with the same arguments and diffs
stdout, stderr and exit status. It uses only cases that load nothing into the
kernel:

- no arguments, and an unknown operation (usage)
- `D=` of a driver with no config
- a scratch config whose `_reloc` is not owned by root, and one whose
  `_reloc` is group-writable (the security refusals)
- a scratch config whose Pre-Load exits non-zero (Pre-Load abort)
- `d=BPF` with every prompt answered `n` on stdin (interactive path)

Every case must match.

### Boot

Two guest boots from the same starting image, with `BPF PortServer` appended
to `"Active Drivers"` in `/usr/Devices/System.config/Instance0.table` so that
DR2's `0300_Devices` (`driverLoader a`) loads them:

1. **Baseline:** Apple's `driverLoader`.
2. **Rebuilt:** ours at `/usr/sbin/driverLoader`.

Capture for each boot:

- the COM2 kernel console log
- `/usr/Devices` and `/dev/` listings, and `ps -axww`

**Pass:**

- the same drivers register in both boots (`Registering:` lines)
- `/dev/bpf*` exists
- PortServer's Post-Load `pdservd` runs and `/dev/ttyda` exists
- the rebuilt boot shows no new error lines

Any difference is either fixed or recorded in `divergences.md`.

## 7. Out of scope

- ppc parity (the ppc slice ships unmeasured)
- behaviour changes and new features
- changes to startup scripts
- libDriver or libkernload functions that `driverLoader` does not link
- hardware testing beyond the QEMU guest
