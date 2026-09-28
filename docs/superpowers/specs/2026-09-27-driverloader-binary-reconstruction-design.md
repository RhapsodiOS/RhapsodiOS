# driverLoader binary reconstruction

Reconstruct Apple's i386 `driverLoader` from Rhapsody DR2 as source in a new
project, `src/driverLoader`. Drive it to function-level parity with Apple's
binary under binrecon, the bar PnPDump used. Package it as an apk, add it to
the world manifest, and boot-test it against Apple's copy.

## Motivation

The tree has no source for `driverLoader`, yet every boot depends on it.
`src/files-5/private/etc/startup/0700_Devices` runs `driverLoader D=<name>`
per driver and then `driverLoader a`. Recent work relies on its behaviour:
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
4. **libDriver user-side objects**: `IOConfigTable` (with `parseDriverList`
   and the `Private` category), `IODevice` (with the `GlobalParameter` and
   `Internal` categories), `IODeviceMaster`, the `driverServer.defs` MIG user
   stubs (`_IOGetDriverConfig`, `_IOProbeDriver`, …), `NXConditionLock`,
   `NXLock`, `generalFuncs` (`IOLog`, `IOMalloc`, `IOScheduleFunc`, …)
5. **libkernload objects**: `kern_loader_*` MIG user stubs,
   `kern_loader_reply_handler`, `kern_loader_look_up`

Groups 4 and 5 are exactly what `-lDriver -lkernload` pulls into a link. Apple
linked the installed static libraries (`src/driverkit-3/libDriver` installs
`/usr/lib/libDriver.a`; `src/kernload-1/libkernload` installs
`/usr/lib/libkernload.a`). Only groups 2 and 3 are source this project owns.

## 2. Project layout

```
src/driverLoader/
  PB.project, Makefile, Makefile.preamble, Makefile.postamble
  driverLoader.m        # group 2
  kl_com.m              # group 3
  driverLoader.8        # from the image, if the tree has no copy
  apk/pkginfo
  reconstruction/
    ledger.json  source-map.json  divergences.md  nlist.md  function-worklist.md
tools/binrecon/profiles/driverloader.json
```

- `src/Manifest` gets a `dir driverLoader` line after `driverkit-3` and
  `kernload-1`.
- The tool installs `/usr/sbin/driverLoader`, with mode and owner taken from
  the reference inode, and `/usr/share/man/man8/driverLoader.8`.
- Link line: `driverLoader.o kl_com.o -lDriver -lkernload` against the build
  root, in that order, so the object layout follows Apple's.
- The build targets i386 only. It is not universal.

### How the sources are written

- Start from IDA 9.2 decompiles of the group 2 and 3 functions, cleaned into
  the ObjC/C the NeXT sources of the time used.
- `kl_com.m` starts from `src/hfs-1/hfs_util/kl_com.c` and
  `src/driverkit-3/Examples/loadable/User/kl_com.m` where the decompile shows
  they match.
- String literals come from `__cstring`. Where the usage text and the man
  page disagree, the binary wins.
- Every function, static and global keeps Apple's name from the symbol table.
  No names are invented.
- Behaviour that is odd but harmless is reproduced. A genuine bug is fixed
  only as a labelled entry in `divergences.md`.

## 3. Libraries: link, don't vendor

Group 4 and 5 functions are measured in this binary and held to the bar in §4.
When one misses:

- **The fix belongs in the library.** Make it in `src/driverkit-3/libDriver`
  or `src/kernload-1/libkernload`. It must not regress libDriver's existing
  `reconstruction/ledger.json` or any other recorded parity result.
- **The library fix would conflict with its own ledger.** Vendor that
  function's object (or the smallest source file holding it) into
  `src/driverLoader`, link it ahead of `-lDriver`, and record why in
  `divergences.md`.
- **The difference is Apple's own source moving on.** Our libDriver sources
  are Darwin 0.3, later than DR2's binaries (see
  `src/driverkit-3/libDriver/reconstruction/divergences.md`). A difference
  explained that way is an **accept** with that reason. libDriver is not
  rewritten back to DR2.

## 4. Done bar

**Owned functions (groups 2 and 3).** Done when `raw_equal` or
`masked_equal` holds on a comparison against the current guest-built binary,
or when the leftover is recorded in `divergences.md` with its
`binrecon function --name` dump and an explicit *accept*. Accepts are for
compiler-shaped differences only: register allocation or instruction
scheduling.

**Linked functions (groups 4 and 5).** The same bar, or a recorded accept or
vendor decision under §3.

**The campaign is done when:**

- every owned function meets the bar, and none is `unexamined` in the ledger
- every linked function meets the bar or has a recorded disposition
- `parity_check.py` reports 0 `missing_strings` and 0 `missing_symbols`
- the §5 packaging and §6 boot test have passed, or any gap is recorded

`__text` size is not a target. `cfg_equal` is not a pass signal.

### Tooling

`tools/binrecon/profiles/driverloader.json`, modelled on `pnpdump.json`: i386,
IDA 9.2 and angr enabled, Ghidra disabled, acceptance `normalized-functions`,
output under `out/driverloader`. Reference and rebuilt paths come from
`BINRECON_REFERENCE` / `BINRECON_REBUILT`.

### Guest workflow

- Use a private `-snapshot` guest booted from `rhap-i386-bootstrapped.img` on
  its own ssh and QMP ports. Never use the shared box.
- Keep one ssh session at a time, and never poll.
- Build with `gnumake` in the project, and fetch the binary to the host
  straight after each build.
- Compare on the host.

## 5. Packaging

- `apk/pkginfo` lists the libDriver and libkernload apks as build
  dependencies.
- Build with
  `rbuild buildpackage --toolchain .../gcc-darwin-i386.conf --arch i386` on
  the private guest, and fetch the apk to the host as soon as it exists.
- Add the apk to the world manifest.
- Find what currently supplies `/usr/sbin/driverLoader` in the install media
  and world root: a DR2 carry-over or another package. Remove that source in
  the same change, so exactly one package owns the file.

## 6. Boot test

Two boots of the same test image (a private `-snapshot` guest or a temporary
disk image, per CLAUDE.md §6):

1. **Baseline:** Apple's `driverLoader`.
2. **Rebuilt:** ours at `/usr/sbin/driverLoader`.

Capture for each boot:

- the COM1 serial log and the kernel message log
- the output of `0700_Devices`
- listings of `/usr/Devices` and `/dev`
- driverLoader's own inquiry or listing output, in whatever mode the man page
  documents

**Pass:**

- the same drivers load in both boots
- `driverLoader a` brings up the boot and active drivers
- `D=BPF` creates `/dev/bpf*`
- `D=PortServer` runs its Post-Load `pdservd`, which creates `/dev/ttyda`
- the rebuilt boot shows no new error lines

Any difference is either fixed or recorded in `divergences.md`.

## 7. Out of scope

- ppc and fat builds (a later pass against a ppc reference)
- behaviour changes and new features
- changes to `0700_Devices`
- libDriver or libkernload functions that `driverLoader` does not link
- hardware testing beyond the QEMU guest
