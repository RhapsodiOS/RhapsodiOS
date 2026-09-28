# driverLoader binary reconstruction

Reconstruct Apple's `driverLoader` as source in a new subproject of
`src/driverkit-3`. Drive both slices of a fat build to function-level parity
with Apple's binaries under binrecon, the bar PnPDump used: i386 against
Rhapsody DR2, ppc against Mac OS X Server 1.2v3. Ship it in the driverkit apk
and boot-test the i386 slice against Apple's copy.

## Motivation

The tree has no source for `driverLoader`, yet every boot depends on it. On
i386 the DR2 root's `/etc/startup/0300_Devices` runs `driverLoader a`, and the
tree's ppc `src/files-5/private/etc/startup/0700_Devices` runs
`driverLoader D=<name>` per driver. Recent work relies on its behaviour:
running a config's Post-Load (`drvPortServer/reconstruction/pdservd.md`) and
loading BPF at boot (the dhcpcd-1 plan). Today the binary comes along from
Apple's roots, so it can be neither rebuilt nor fixed.

## 1. References and triage (do not rediscover)

### i386: Rhapsody DR2

| Property | Value |
|---|---|
| Source | `/usr/sbin/driverLoader` in `vm/work/rhap-i386-bootstrapped.img`, read with `vm/rhap_image.py` opened read-only |
| Host copy | `C:\Users\raynorpat\Downloads\test\DR2\usr\sbin\driverLoader` |
| Mode / owner | `0555`, root:wheel (0:0) |
| Size | 70132 bytes |
| SHA-256 | `e005522ec2e4f107b8071a573ccda9208d49e64e2114d08b8868ee956a0e98b7` |
| Mach-O | thin i386 `MH_EXECUTE`, flags `0x15`, links only `System.framework/Versions/B/System` |
| `__text` | `0x3840`, 28940 bytes |
| Symbols | 349 in the symbol table, 269 defined; **unstripped**, statics included |

The bootstrapped image is a shared backing file for other sessions' guests.
Never open it writable.

### ppc: Mac OS X Server 1.2v3

| Property | Value |
|---|---|
| Source | `/usr/sbin/driverLoader` in `C:\Users\raynorpat\Downloads\rhapsody.img` (unzipped from `rhapsody.img_.zip`) |
| Host copy | `C:\Users\raynorpat\Downloads\test\MOSXS12v3\usr\sbin\driverLoader` |
| Mode / owner | `0555`, root:wheel (0:0) |
| Size | 40776 bytes |
| SHA-256 | `cd8dd33035aae133ce4ab1d6a203807cbceabc3d5d300326ff105ad33d9d3e14` |
| Mach-O | thin ppc `MH_EXECUTE`, flags `0x15`, links `/usr/lib/libDriver.A.dylib` then `System.framework/Versions/B/System` |
| `__text` | `0x2acc`, 13080 bytes |
| Symbols | 117; **unstripped**, statics included |

How the image was read: an Apple partition map, root in partition 8
(`Apple_Rhapsody_UFS`, 512-byte sector 18624). Inside it is a NeXT label
(`dlV3`, 1024-byte sectors, `front` 160, `p_base` 9312, and `p_base` is
absolute on the disk) and a **big-endian** UFS starting at byte
`(160 + 9312) * 1024`. `vm/rhap_image.py` with every `<` format turned to `>`
reads it.

### Man page

`/usr/share/man/man8/driverLoader.8` is byte-identical in both roots: 1872
bytes, SHA-256 `0049722e66fc99474a26134640c23664fe11f035719843c0669d46ce644c0b97`,
mode `0444`. Host copies sit under each root's `usr\share\man\man8\`. It is
dated 1994, documents `/usr/etc/driverLoader` and the `a`, `i`, `v` and `d=`
operations. Both binaries' usage text also has `D=deviceName`
(non-interactive), and both install in `/usr/sbin`. The binaries win.

### What the binaries contain

Both carry the same owned code, in the same order:

1. **driverLoader's own code** (i386 `0x39a0`–`0x4b98`, ppc
   `0x2cf0`–`0x3fac`): `main`, `usage`, `inquire`, `processDriverList`,
   `processDriver`, `loadDriver`, `unloadDriver`, `getInstanceFile`,
   `configDriver`, `securityCheck`, `securityCheckDir`, `prePostExec`, plus
   globals `verbose`, `interactive`, `instruction`, `progName`
2. **a kern_loader client module** (i386 `0x4b98`–`0x51d4`, ppc
   `0x3fac`–`0x4768`): `kl_init`, `kl_com_log`, `print_string`, `ping`,
   `kl_com_add`, `kl_com_delete`, `kl_com_load`, `kl_com_unload`,
   `kl_com_get_state`, `kl_com_error`, `kl_com_wait`, statics `strings.N`
   (`strings.10` on i386, `strings.2` on ppc) and `ping_lock`, and globals
   `kl_init_flag`, `kl_port`, `kernel_task`, `reply_port`
3. **libkernload objects**, linked statically in both: `kern_loader_*` MIG
   user stubs, `kern_loader_reply_handler`, `kern_loader_look_up`

The owned `__cstring` sets are identical in both directions. The ppc binary
also has a common `catch_exception_raise`.

They differ only in how libDriver is linked:

- **DR2 i386** carries libDriver's user-mode objects statically, in this
  order: `IOConfigTable` (with `parseDriverList` and the `Private` category),
  `IODevice` (with the `GlobalParameter` and `Internal` categories),
  `IODeviceMaster`, `driverServerUser` (the `driverServer.defs` MIG stubs),
  `NXConditionLock`, `NXLock`, `generalFuncs`.
- **MOSXS 1.2v3 ppc** links `/usr/lib/libDriver.A.dylib` and imports
  `IOConfigTable`, `IODevice`, `IODeviceMaster`, `NXConditionLock`, `IOLog`,
  `_IOProbeDriver` and `_IOUnloadDriver` from it.

**Decision: link the libDriver dylib on both slices**, the MOSXS 1.2v3 shape.
That is the later release this tree reimplements. Our libDriver is Darwin 0.3,
its contemporary, and it already builds `libDriver.A.dylib`. DR2's static
libDriver code in the i386 reference becomes one recorded accept (§3).

## 2. Project layout

```
src/driverkit-3/
  Makefile              # SUBDIR and INSTALL_SUBDIR gain driverLoader, after libDriver
  PB.project            # SUBPROJECTS gains driverLoader
  apk/pkginfo           # makedepends gains kernload-hdrs, kernload
  driverLoader/
    Makefile            # handwritten, in the style of configutil/Makefile
    driverLoader.m      # owned group 1
    kl_com.m, kl_com.h  # owned group 2
    driverLoader.8      # from the image
    reconstruction/     # as libDriver/reconstruction
      nlist.md  divergences.md  function-worklist.md
      i386/  ledger.json  source-map.json
      ppc/   ledger.json  source-map.json
tools/binrecon/profiles/driverloader.json       # i386
tools/binrecon/profiles/driverloader-ppc.json   # ppc
```

- `src/Manifest` already lists `driverkit-3`, so it does not change.
- For each CPU in `RC_ARCHS`, `driverLoader/Makefile` compiles
  `driverLoader.m` and `kl_com.m` and links:
  ```
  driverLoader.o kl_com.o <libDriver.A.dylib from this build> -lkernload
  ```
  Then it `lipo`s the slices together, as libDriver does. The dylib is the
  fat `libDriver.A.dylib` that libDriver's `lipoize` step leaves in its
  `syms` directory. The top-level Makefile gives each subproject
  `SYMROOT=$(SYMROOT)/<subdir>`, so from `driverLoader` that is
  `$(SYMROOT)/../libDriver/syms/libDriver.A.dylib`. Its install name is
  `/usr/lib/libDriver.A.dylib`, the path the ppc reference loads, and the
  dylib comes before System on the link line, as in the reference.
- It installs `/usr/sbin/driverLoader` (mode `0555`, root:wheel, **not
  stripped**: Apple's copies keep their full symbol tables) and
  `/usr/share/man/man8/driverLoader.8` (mode `0444`).
- The world build of driverkit is universal, and rbuild's product check needs
  every Mach-O in the package to hold exactly the package's CPUs, so the
  shipped binary is fat. Both slices are measured.

### How the sources are written

- Start from IDA 9.2 decompiles of the owned functions. Where the i386 and
  ppc decompiles disagree about behaviour, stop and resolve it from both
  disassemblies before writing the line.
- `kl_com.m` and `kl_com.h` start as copies of
  `src/driverkit-3/Examples/loadable/User/kl_com.m` and `kl_com.h`. Their
  globals and statics (`kl_port`, `kernel_task`, `reply_port`,
  `kl_init_flag`, static `ping_lock`, static `kl_init`) already match the
  references.
- String literals come from `__cstring`.
- Every function, static and global keeps Apple's name from the symbol table.
  No names are invented.
- Behaviour that is odd but harmless is reproduced. A genuine bug is fixed
  only as a labelled entry in `divergences.md`.

## 3. Linked library code

- **libDriver is not in the binary.** It is reached through the dylib, so its
  functions are not part of this campaign's parity. DR2's i386 reference
  carries them statically. That is recorded once in `divergences.md` as an
  **accept** ("DR2 linked libDriver's objects statically; MOSXS 1.2 links
  `libDriver.A.dylib`, and this build follows 1.2"). The i386 ledger marks
  each of those reference functions `intentional-mismatch` with that reason.
- **libkernload is in both binaries** and is measured on both slices under
  §4. A miss is fixed in `src/kernload-1/libkernload` if the fix does not
  break its other users (`kern_loader`, `kl_util`, drivers). Otherwise, or if
  the difference is Apple's own source moving on, it is an accept with the
  reason.

## 4. Done bar

**Owned functions (groups 1 and 2) and libkernload functions (group 3).**
Each is done, **per slice**, when `raw_equal` or `masked_equal` holds on a
comparison against the current guest-built slice, or when the leftover is
recorded in `divergences.md` with its `binrecon function --name` dump for
that slice and an explicit *accept*. Accepts are for compiler-shaped
differences only: register allocation or instruction scheduling. Fixing one
slice must not regress the other. A one-sided win is reverted, or both
dumps go into the accept.

**The campaign is done when:**

- every owned and libkernload function meets the bar on both slices, and
  none is `unexamined` in either ledger
- `parity_check.py` reports 0 `missing_strings` on both slices
- `parity_check.py` reports 0 `missing_symbols` on ppc, and on i386 lists
  only the DR2 static libDriver symbols covered by the §3 accept
- the §5 packaging and the §6 behaviour and boot tests have passed, or any
  gap is recorded

`__text` size is not a target. `cfg_equal` is not a pass signal.

### Tooling

- `tools/binrecon/profiles/driverloader.json`: i386, IDA 9.2 and angr
  enabled, Ghidra disabled, acceptance `normalized-functions`, output under
  `out/driverloader`.
- `tools/binrecon/profiles/driverloader-ppc.json`: ppc, big-endian, IDA 9.2
  only (binrecon's Ghidra and angr adapters reject ppc), output under
  `out/driverloader-ppc`, and it gains a `rebuilt` path.
- Both take their inputs from `BINRECON_REFERENCE` / `BINRECON_REBUILT`.
- The rebuilt inputs are thin slices, split from the fat build with
  `lipo -thin`.

### Guest workflow

- Use a private `-snapshot` guest booted from `rhap-i386-bootstrapped.img` on
  its own ssh and QMP ports. Never use the shared box.
- Keep one ssh session at a time, and never poll.
- Build driverkit with `rbuild buildpackage` and
  `--toolchain .../gcc-darwin-universal.conf` into a private output
  directory, so each build gives both slices. When a compile fails, iterate
  in the leftover build root.
- Fetch the apk to the host straight after each build, and compare on the
  host.

## 5. Packaging

- Add `kernload-hdrs, kernload` to driverkit's `makedepends`.
- The driverkit apk ships the fat `driverLoader` and the man page.
- Check the repository's apks for any other package that ships
  `usr/sbin/driverLoader`. If one does, remove it from that package in the
  same change, so exactly one package owns the file.

## 6. Behaviour and boot tests (i386)

These run on the i386 guest. There is no ppc guest; the ppc slice is held to
its parity bar only.

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
2. **Rebuilt:** ours at `/usr/sbin/driverLoader`, with our
   `libDriver.A.dylib` installed from the same driverkit apk.

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

- libDriver parity (reached through the dylib)
- behaviour changes and new features
- changes to startup scripts
- a ppc boot test
- hardware testing beyond the QEMU guest
